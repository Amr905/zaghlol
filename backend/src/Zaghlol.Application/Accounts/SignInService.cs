using System.Security.Cryptography;
using System.Text;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Accounts;

/// <summary>A parsed, shape-checked <c>POST /v1/accounts/signin</c> body (the endpoint checks patterns and sizes).</summary>
/// <param name="Nonce">The raw client nonce; null when the request had none (<c>422 ID_TOKEN_INVALID</c>, R2-9).</param>
public sealed record SignInCommand(
    AccountProvider Provider,
    Sensitive<string> IdToken,
    Sensitive<string>? Nonce,
    Sensitive<string>? AuthorizationCode,
    bool ReplaceLink,
    IReadOnlyList<SeatKeyProofInput?>? SeatKeys)
{
    public override string ToString() => "***";
}

public enum SignInResultKind
{
    Completed,

    /// <summary>Token, nonce, age or replay: <c>422 ID_TOKEN_INVALID</c>.</summary>
    IdTokenInvalid,

    /// <summary>Seat keys on an Android install, or a malformed or badly signed <c>seatKeys</c>: <c>400 VALIDATION_FAILED</c>.</summary>
    ValidationFailed,

    /// <summary>Element 0 isn't this install's registered key: <c>400 SEAT_KEY_MISMATCH</c>; nothing was linked.</summary>
    SeatKeyMismatch,

    /// <summary><c>409 INSTALL_LINKED_TO_OTHER_ACCOUNT</c>.</summary>
    LinkedToOtherAccount,

    /// <summary>The provider's keys are unavailable: <c>503 UPSTREAM_UNAVAILABLE</c>.</summary>
    Unavailable,

    /// <summary>The install was deleted meanwhile: <c>401 INSTALL_TOKEN_INVALID</c>.</summary>
    InstallGone,
}

/// <summary>The data of a 200 (backend-api §4.6). The account token and entitlement are secrets: <see cref="ToString"/> is <c>***</c>.</summary>
public sealed record SignInResult(
    SignInResultKind Kind,
    Guid AccountId = default,
    Sensitive<string> AccountToken = default,
    Sensitive<string> EntitlementToken = default,
    int LinkedInstalls = 0,
    bool MovedFromOtherPhone = false,
    bool MoveRefused = false,
    bool RestoreSuggested = false,
    DateTimeOffset? NextMoveAt = null)
{
    public override string ToString() => Kind.ToString();
}

/// <summary>
/// <c>POST /v1/accounts/signin</c> (T-135 design note; backend-api §4.6). The order is fixed and each step runs only if the one
/// before passed: platform and <c>seatKeys</c> structure; ID token (signature, <c>iss</c>, <c>aud</c>, <c>exp</c>); nonce pre-image in
/// constant time and <c>iat</c> within 10 minutes (R2-9); the <c>replay_guard</c> insert, committed on its own, before and outside
/// the account transaction (R3-5); the seat-key proofs; the Apple code exchange; then one transaction: element 0 (R4-1(1), nothing
/// linked on a mismatch), upsert, link (EC-46), D-54 attach, and the seat decision of <see cref="SeatService"/> for each
/// account-linked purchase, which always commits steps 1-4 even when a move is refused (R3-5). No ID token, nonce, code, key or
/// account token is returned in a result's text or logged.
/// </summary>
public sealed class SignInService(
    IAccountStore store,
    IIdTokenVerifier verifier,
    IIdTokenReplayGuard replay,
    IAppleAccountClient apple,
    IAppleTokenVault vault,
    SeatKeyProofVerifier seatProofs,
    SeatService seats,
    IAccountTransactionFactory transactions,
    EntitlementService entitlement,
    IEntitlementSigner signer,
    TimeProvider clock)
{
    /// <summary>The oldest <c>iat</c> accepted (backend-api §4.6).</summary>
    public static readonly TimeSpan MaxTokenAge = TimeSpan.FromMinutes(10);

    /// <summary>How far in the future an <c>iat</c> may lie (clock skew).</summary>
    public static readonly TimeSpan MaxIssuedInFuture = TimeSpan.FromMinutes(5);

    /// <summary>The account token's lifetime (backend-api §3).</summary>
    public static readonly TimeSpan AccountTokenLifetime = TimeSpan.FromDays(30);

    public async Task<SignInResult> SignInAsync(SignInCommand command, InstallId install, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);

        var platform = await store.ReadInstallPlatformAsync(install.Value, cancellationToken).ConfigureAwait(false);
        if (platform is null)
        {
            return new SignInResult(SignInResultKind.InstallGone);
        }

        ParsedSeatKeys? parsed = null;
        if (command.SeatKeys is not null)
        {
            if (platform != "ios")
            {
                return new SignInResult(SignInResultKind.ValidationFailed);
            }

            var parse = seatProofs.Parse(SeatOp.SignIn, command.SeatKeys);
            if (!parse.IsValid)
            {
                return new SignInResult(SignInResultKind.ValidationFailed);
            }

            parsed = parse.Keys;
        }

        // R2-9: the nonce is required for both providers; a request without one is refused before any token work.
        if (command.Nonce?.Reveal() is not { Length: > 0 } rawNonce)
        {
            return new SignInResult(SignInResultKind.IdTokenInvalid);
        }

        var verification = await verifier.VerifyAsync(command.Provider, command.IdToken, cancellationToken).ConfigureAwait(false);
        if (verification.Outcome == IdTokenOutcome.Unavailable)
        {
            return new SignInResult(SignInResultKind.Unavailable);
        }

        if (verification.Outcome != IdTokenOutcome.Verified || verification.Token is not { } token)
        {
            return new SignInResult(SignInResultKind.IdTokenInvalid);
        }

        var now = clock.GetUtcNow();
        if (!NonceMatches(rawNonce, token.Nonce) || !FreshEnough(token.IssuedAt, now))
        {
            return new SignInResult(SignInResultKind.IdTokenInvalid);
        }

        // R3-5: single use, committed here, before and outside the account and seat transaction, so no later rollback can make
        // the same ID token and nonce usable again.
        var claimHash = SHA256.HashData(Encoding.ASCII.GetBytes(token.Nonce!));
        if (!await replay.TryUseAsync(command.Provider, claimHash, token.ExpiresAt, cancellationToken).ConfigureAwait(false))
        {
            return new SignInResult(SignInResultKind.IdTokenInvalid);
        }

        VerifiedSeatKeys? verifiedKeys = null;
        if (parsed is not null)
        {
            var seatVerification = seatProofs.Verify(parsed, SeatChallenge.ForSignIn(rawNonce), install);
            if (!seatVerification.IsValid)
            {
                return new SignInResult(SignInResultKind.ValidationFailed);
            }

            verifiedKeys = seatVerification.Keys;
        }

        byte[]? sealedRefresh = null;
        if (command.Provider == AccountProvider.Apple && command.AuthorizationCode is { } code)
        {
            var refresh = await apple.ExchangeCodeAsync(code, token.Audience, token.Subject, cancellationToken).ConfigureAwait(false);
            if (refresh is not null)
            {
                sealedRefresh = await vault.SealAsync(token.Subject, refresh, cancellationToken).ConfigureAwait(false);
            }
        }

        Guid accountId;
        var results = new List<SeatResult>();
        int linked;
        var transaction = await transactions.BeginAsync(cancellationToken).ConfigureAwait(false);
        await using (transaction.ConfigureAwait(false))
        {
            if (!await transaction.Accounts.LockInstallAsync(install.Value, cancellationToken).ConfigureAwait(false))
            {
                return new SignInResult(SignInResultKind.InstallGone);
            }

            // R4-1(1): before step 1, so a rejected request links nothing (the rollback also drops a first registration).
            RegisteredSeatKey? key = null;
            if (verifiedKeys is not null)
            {
                var registration = await seats.RegisterElementZeroAsync(transaction.Seats, verifiedKeys, attested: null, cancellationToken).ConfigureAwait(false);
                if (registration.Status == SeatKeyRegistrationStatus.Mismatch)
                {
                    return new SignInResult(SignInResultKind.SeatKeyMismatch);
                }

                key = registration.Key;
            }

            var accounts = transaction.Accounts;
            accountId = await accounts.UpsertAccountAsync(command.Provider, token.Subject, token.Email, sealedRefresh, now, cancellationToken).ConfigureAwait(false);

            var existing = await accounts.LinkedAccountsOfInstallAsync(install.Value, cancellationToken).ConfigureAwait(false);
            if (existing.Any(a => a != accountId))
            {
                if (!command.ReplaceLink)
                {
                    return new SignInResult(SignInResultKind.LinkedToOtherAccount);
                }

                await accounts.UnlinkInstallAsync(install.Value, cancellationToken).ConfigureAwait(false);
            }

            await accounts.LinkAsync(accountId, install.Value, now, cancellationToken).ConfigureAwait(false);
            var attached = (await accounts.AttachBuyingPurchasesAsync(install.Value, accountId, cancellationToken).ConfigureAwait(false)).ToHashSet();

            foreach (var purchaseId in await accounts.ListEntitlingPurchasesAsync(accountId, cancellationToken).ConfigureAwait(false))
            {
                results.Add(await seats.SignInAsync(
                    transaction.Seats,
                    new SignInSeatRequest(purchaseId, install, accountId, attached.Contains(purchaseId), key),
                    cancellationToken).ConfigureAwait(false));
            }

            linked = await accounts.CountLinkedInstallsAsync(accountId, cancellationToken).ConfigureAwait(false);
            await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
        }

        var issuedAt = clock.GetUtcNow();
        var issue = await entitlement.IssueAsync(install, accountId, issuedAt, carryNotice: false, cancellationToken).ConfigureAwait(false);
        var accountToken = await signer.SignAccountTokenAsync(
            new AccountTokenClaims(
                accountId.ToString("D"),
                install.ToString(),
                issuedAt.ToUnixTimeSeconds(),
                (issuedAt + AccountTokenLifetime).ToUnixTimeSeconds()),
            cancellationToken).ConfigureAwait(false);

        var refused = results.Where(r => r.Outcome == SeatOutcome.Refused).ToList();
        DateTimeOffset? next = refused.Select(r => r.NextMoveAt).Where(n => n is not null).Min();
        return new SignInResult(
            SignInResultKind.Completed,
            accountId,
            new Sensitive<string>(accountToken),
            new Sensitive<string>(issue.Token),
            linked,
            MovedFromOtherPhone: results.Any(r => r.Outcome == SeatOutcome.Moved && r.PreviousHolder is not null),
            MoveRefused: refused.Count > 0,
            RestoreSuggested: results.Any(r => r.RestoreSuggested),
            NextMoveAt: refused.Count > 0 ? next : null);
    }

    /// <summary><c>hex(SHA-256(raw))</c> against the token's <c>nonce</c> claim, in constant time; a missing claim never matches (R2-9).</summary>
    internal static bool NonceMatches(string rawNonce, string? claim)
    {
        if (claim is null || !Ascii.IsValid(rawNonce) || !Ascii.IsValid(claim))
        {
            return false;
        }

        var expected = Encoding.ASCII.GetBytes(Convert.ToHexStringLower(SHA256.HashData(Encoding.ASCII.GetBytes(rawNonce))));
        return CryptographicOperations.FixedTimeEquals(expected, Encoding.ASCII.GetBytes(claim));
    }

    private static bool FreshEnough(DateTimeOffset? issuedAt, DateTimeOffset now) =>
        issuedAt is { } iat && now - iat <= MaxTokenAge && iat - now <= MaxIssuedInFuture;
}
