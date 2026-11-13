using System.Security.Cryptography;
using System.Text;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases.Restore;

/// <summary>
/// <c>POST /v1/purchases/restore</c> after the strict parse (T-185 design note; backend-api §4.3 Restore). Possession of a genuine
/// token is not proof of ownership, so the order is fixed and each step runs only if the one before passed:
/// <list type="number">
/// <item>seat-key structure (iOS), before any attestation work;</item>
/// <item>device attestation bound to this install and body (Play Integrity, or App Attest with element 0 of <c>seatKeys</c> checked
/// in the same transaction as the counter update, R5-6), then the 10-per-day per-purchase limit;</item>
/// <item>store verification of every item without the install-binding check (no database transaction is open across these calls);</item>
/// <item>one seat transaction: items in ascending purchase-id order (FU-112), the seat decision of <see cref="SeatService"/>, commit
/// (a cooldown refusal commits its claimant row, then answers <c>409</c>);</item>
/// <item>the merged entitlement from the seats this install now holds.</item>
/// </list>
/// An outage anywhere is <c>502/503</c>, never <c>422</c>. Nothing here logs or returns a token, key or proof.
/// </summary>
public sealed class RestoreService(
    IEnumerable<IStoreVerification> verifiers,
    IAppleJwsVerifier jws,
    IPlayIntegrityVerifier playIntegrity,
    IAppAttestVerifier appAttest,
    SeatKeyProofVerifier seatProofs,
    ISeatTransactionFactory transactions,
    SeatService seats,
    IAccountTokenValidator accounts,
    EntitlementService entitlement,
    IRestoreAttemptLimiter limiter,
    IRestoreTelemetry telemetry,
    TimeProvider clock)
{
    /// <summary><c>Retry-After</c> for an attestation-service outage.</summary>
    public const int AttestationRetryAfterSeconds = 30;

    /// <summary><c>Retry-After</c> of the per-purchase limit: the window is 24 h, so the app should not retry soon.</summary>
    public const int PurchaseLimitRetryAfterSeconds = 3600;

    /// <summary><c>Retry-After</c> when no verifier for a store is registered.</summary>
    public const int NoVerifierRetryAfterSeconds = 3600;

    public async Task<RestoreResult> RestoreAsync(
        RestoreRequest request, InstallId install, Sensitive<string>? accountToken, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        var now = clock.GetUtcNow();
        var purchases = ToItems(request);

        RestoreProof proof;
        RegisteredSeatKey? seatKey = null;
        switch (request)
        {
            case AndroidRestoreRequest android:
                {
                    var attestation = await playIntegrity.VerifyAsync(android.IntegrityToken, android.BodyHash, cancellationToken).ConfigureAwait(false);
                    if (Refuse(RestorePlatforms.Android, attestation) is { } refused)
                    {
                        return refused;
                    }

                    proof = attestation.Level == ProofLevel.Basic ? RestoreProof.Basic : RestoreProof.Attested;
                    if (!ChargeLimits(purchases, now))
                    {
                        return new RestoreResult(RestoreResultKind.PurchaseRateLimited, RetryAfterSeconds: PurchaseLimitRetryAfterSeconds);
                    }

                    break;
                }

            case IosRestoreRequest ios:
                {
                    proof = RestoreProof.Attested;
                    var ensured = await AttestIosAsync(ios, install, purchases, now, cancellationToken).ConfigureAwait(false);
                    if (ensured.Refused is { } refused)
                    {
                        return refused;
                    }

                    seatKey = ensured.Key;
                    break;
                }

            default:
                throw new ArgumentException("Unknown restore platform.", nameof(request));
        }

        // Step 3: store verification, no transaction open. Any store failure aborts the call before a seat is touched.
        var outcomes = new List<StoreVerificationResult>();
        foreach (var item in purchases)
        {
            var verifier = verifiers.FirstOrDefault(v => v.Store == item.Store);
            if (verifier is null)
            {
                return new RestoreResult(RestoreResultKind.StoreUnavailable, RetryAfterSeconds: NoVerifierRetryAfterSeconds, BudgetShort: true);
            }

            try
            {
                var verified = await verifier.VerifyAsync(item.Ref, install, BindingCheck.Skip, cancellationToken).ConfigureAwait(false);
                outcomes.Add(verified);
            }
            catch (StoreUnavailableException unavailable)
            {
                return new RestoreResult(
                    RestoreResultKind.StoreUnavailable,
                    RetryAfterSeconds: unavailable.RetryAfterSeconds,
                    BudgetShort: unavailable.Kind == StoreFailureKind.Budget);
            }
        }

        var account = await accounts.ValidateAsync(accountToken, install, now, cancellationToken).ConfigureAwait(false);

        // Step 4-5: one seat transaction. Distinct purchases in ascending id order, so two restores that share purchases lock
        // them in the same order and can't deadlock (FU-112, T184-I3).
        var seatResults = new Dictionary<Guid, SeatResult>();
        var active = outcomes
            .Where(o => o is { Status: VerifyStatus.Active, PurchaseId: not null })
            .Select(o => o.PurchaseId!.Value)
            .Distinct()
            .Order()
            .ToList();
        if (active.Count > 0)
        {
            var transaction = await transactions.BeginAsync(SeatLogin.App, cancellationToken).ConfigureAwait(false);
            await using (transaction.ConfigureAwait(false))
            {
                foreach (var purchaseId in active)
                {
                    seatResults[purchaseId] = await seats.RestoreAsync(
                        transaction.Seats,
                        new RestoreSeatRequest(purchaseId, install, proof, account?.AccountId, seatKey),
                        cancellationToken).ConfigureAwait(false);
                }

                await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
            }
        }

        return await FoldAsync(outcomes, seatResults, install, account?.AccountId, now, cancellationToken).ConfigureAwait(false);
    }

    private async Task<RestoreResult> FoldAsync(
        List<StoreVerificationResult> outcomes,
        Dictionary<Guid, SeatResult> seatResults,
        InstallId install,
        Guid? accountId,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var items = new List<RestoreItemOutcome>();
        var holding = new HashSet<Guid>();
        var moved = false;
        DateTimeOffset? earliest = null;
        foreach (var verification in outcomes)
        {
            if (verification is { Status: VerifyStatus.Active, PurchaseId: { } purchaseId })
            {
                var seat = seatResults[purchaseId];
                if (seat.CallerHolds)
                {
                    items.Add(RestoreItemOutcome.Active);
                    holding.Add(purchaseId);
                    moved |= seat.Outcome == SeatOutcome.Moved && seat.PreviousHolder is not null;
                }
                else if (seat.Outcome == SeatOutcome.AccountRequired)
                {
                    items.Add(RestoreItemOutcome.AccountRequired);
                }
                else if (seat.Outcome == SeatOutcome.Refused)
                {
                    items.Add(RestoreItemOutcome.CooldownRefused);
                    telemetry.MoveCooldownRefused();
                    earliest = seat.NextMoveAt is { } next && (earliest is null || next < earliest) ? next : earliest;
                }
                else
                {
                    // Fail closed: no seat, no Gold.
                    items.Add(RestoreItemOutcome.Invalid);
                }

                continue;
            }

            items.Add(verification.Status switch
            {
                VerifyStatus.Pending => RestoreItemOutcome.Pending,
                VerifyStatus.Expired => RestoreItemOutcome.Expired,
                VerifyStatus.Refunded => RestoreItemOutcome.Refunded,
                _ => RestoreItemOutcome.Invalid,
            });
        }

        var anyGold = items.Any(i => i is RestoreItemOutcome.Active or RestoreItemOutcome.Pending);
        if (!anyGold && items.Contains(RestoreItemOutcome.CooldownRefused) && earliest is { } nextMoveAt)
        {
            return new RestoreResult(RestoreResultKind.MoveCooldown, NextMoveAt: nextMoveAt);
        }

        var status = Aggregate(items);
        var issue = await entitlement.IssueAsync(install, accountId, now, carryNotice: false, cancellationToken).ConfigureAwait(false);
        var grants = issue.Claims.Status is "active" or "grace";
        return new RestoreResult(
            RestoreResultKind.Completed,
            status,
            holding.Count,
            moved,
            grants ? new Sensitive<string>(issue.Token) : null);
    }

    /// <summary>Precedence <c>active &gt; pending &gt; account_required &gt; expired &gt; refunded &gt; invalid</c>.</summary>
    internal static string Aggregate(IReadOnlyCollection<RestoreItemOutcome> items) =>
        items.Contains(RestoreItemOutcome.Active) ? "active"
        : items.Contains(RestoreItemOutcome.Pending) ? "pending"
        : items.Contains(RestoreItemOutcome.AccountRequired) ? "account_required"
        : items.Contains(RestoreItemOutcome.Expired) ? "expired"
        : items.Contains(RestoreItemOutcome.Refunded) ? "refunded"
        : "invalid";

    /// <summary>
    /// iOS step 2 in one transaction: structure of <c>seatKeys</c>, the optional <c>attestationObject</c> (first use of a key), the
    /// assertion over <c>clientDataHash</c>, the seat-key proofs, the per-purchase limit and the element-0 check, which only then
    /// commits. A mismatch or any refusal rolls the counter, the key registration and the element-0 registration back (R5-6).
    /// </summary>
    private async Task<IosAttested> AttestIosAsync(
        IosRestoreRequest request, InstallId install, IReadOnlyList<RestoreItem> purchases, DateTimeOffset now, CancellationToken cancellationToken)
    {
        ParsedSeatKeys? parsed = null;
        if (request.SeatKeys is not null)
        {
            var parse = seatProofs.Parse(SeatOp.Restore, request.SeatKeys);
            if (!parse.IsValid)
            {
                return new IosAttested(new RestoreResult(RestoreResultKind.ValidationFailed), null);
            }

            parsed = parse.Keys;
        }

        var digest = parsed?.Digest() ?? SeatKeysDigest.Empty;
        var clientDataHash = RestoreRequestParser.ClientDataHash(request.BodyHash, digest);

        var transaction = await transactions.BeginAsync(SeatLogin.App, cancellationToken).ConfigureAwait(false);
        await using (transaction.ConfigureAwait(false))
        {
            if (request.AttestationObject is { } attestationObject)
            {
                var registered = await appAttest.RegisterAttestationAsync(
                    transaction.AppAttestKeys, install, request.KeyId, attestationObject, clientDataHash, cancellationToken).ConfigureAwait(false);
                if (Refuse(RestorePlatforms.Ios, registered) is { } refusedRegistration)
                {
                    return new IosAttested(refusedRegistration, null);
                }
            }

            var assertion = await appAttest.VerifyAssertionAsync(
                transaction.AppAttestKeys, install, request.KeyId, request.Assertion, clientDataHash, cancellationToken).ConfigureAwait(false);
            if (Refuse(RestorePlatforms.Ios, assertion) is { } refusedAssertion)
            {
                return new IosAttested(refusedAssertion, null);
            }

            RegisteredSeatKey? key = null;
            if (parsed is not null)
            {
                var verification = seatProofs.Verify(parsed, SeatChallenge.ForRestore(request.BodyHash), install);
                if (!verification.IsValid)
                {
                    return new IosAttested(new RestoreResult(RestoreResultKind.ValidationFailed), null);
                }

                // The assertion verified over a clientDataHash that covers exactly these public keys: the one capability that
                // lets element 0 register as trusted (R5-2).
                var verified = new AppAttestVerified(install, digest);
                var registration = await seats.RegisterElementZeroAsync(transaction.Seats, verification.Keys, verified, cancellationToken).ConfigureAwait(false);
                if (registration.Status == SeatKeyRegistrationStatus.Mismatch)
                {
                    return new IosAttested(new RestoreResult(RestoreResultKind.SeatKeyMismatch), null);
                }

                key = registration.Key;
            }

            if (!ChargeLimits(purchases, now))
            {
                return new IosAttested(new RestoreResult(RestoreResultKind.PurchaseRateLimited, RetryAfterSeconds: PurchaseLimitRetryAfterSeconds), null);
            }

            await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
            return new IosAttested(null, key);
        }
    }

    private RestoreResult? Refuse(string platform, AttestationResult result)
    {
        switch (result.Outcome)
        {
            case AttestationOutcome.Verified:
                return null;
            case AttestationOutcome.Unavailable:
                return new RestoreResult(RestoreResultKind.Unavailable, RetryAfterSeconds: AttestationRetryAfterSeconds);
            default:
                telemetry.AttestationFailed(platform, result.Code);
                return new RestoreResult(RestoreResultKind.AttestationFailed);
        }
    }

    /// <summary>One attempt for each distinct purchase of the request; any purchase over its limit refuses the call.</summary>
    private bool ChargeLimits(IReadOnlyList<RestoreItem> purchases, DateTimeOffset now)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in purchases)
        {
            if (LimitKey(item, now) is { } key && seen.Add(Convert.ToBase64String(key)) && !limiter.TryAcquire(key))
            {
                return false;
            }
        }

        return true;
    }

    /// <summary>
    /// SHA-256 of the Play token, or of the original transaction ID of a JWS that verifies (a forged ID can't burn someone else's
    /// allowance); an iOS item that doesn't verify has no key and is an invalid item (the App Store verifier rejects it again).
    /// </summary>
    private byte[]? LimitKey(RestoreItem item, DateTimeOffset now)
    {
        switch (item.Ref)
        {
            case PlayPurchaseRef play:
                return SHA256.HashData(Encoding.UTF8.GetBytes(play.PurchaseToken.Reveal()));
            case AppStorePurchaseRef apple:
                try
                {
                    return jws.VerifyTransaction(apple.SignedTransaction, JwsSource.App, now).OriginalTransactionId is { } original
                        ? SHA256.HashData(Encoding.UTF8.GetBytes(original.Reveal()))
                        : null;
                }
                catch (AppleJwsException)
                {
                    return null;
                }

            default:
                return null;
        }
    }

    private static List<RestoreItem> ToItems(RestoreRequest request) => request switch
    {
        AndroidRestoreRequest android => [.. android.Purchases.Select(p => new RestoreItem(PurchaseStore.GooglePlay, p))],
        IosRestoreRequest ios => [.. ios.SignedTransactions.Select(s => new RestoreItem(PurchaseStore.AppStore, new AppStorePurchaseRef(s)))],
        _ => throw new ArgumentException("Unknown restore platform.", nameof(request)),
    };

    private sealed record RestoreItem(PurchaseStore Store, StorePurchaseRef Ref)
    {
        public override string ToString() => "***";
    }

    private sealed record IosAttested(RestoreResult? Refused, RegisteredSeatKey? Key);
}
