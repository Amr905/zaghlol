using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;

namespace Zaghlol.Application.Entitlements;

/// <summary>
/// Seat at verify and the signed entitlement (T-132; backend-api §4.3 <i>Seat at verify</i>). Runs only after the store checks
/// passed and the purchase was written and acknowledged, for an active purchase. One seat transaction on the App login: the
/// verify-time <c>seatKeys</c> (iOS, R5-2: registered untrusted, a bad proof or a non-registered element 0 ignored, never an
/// error), then <see cref="SeatService.VerifyAsync"/>, which binds, refreshes or applies the plan-change rules and never refuses.
/// The token is issued after the commit from the seat rows, so it covers exactly what the install holds now.
/// </summary>
public sealed class VerifyGrant(
    ISeatTransactionFactory transactions,
    SeatService seats,
    SeatKeyProofVerifier proofs,
    IAccountTokenValidator accounts,
    EntitlementService entitlement) : IVerifyGrant
{
    public async Task<VerifyGrantResult> ComposeAsync(StoreVerificationResult verification, VerifyContext context, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(verification);
        ArgumentNullException.ThrowIfNull(context);
        if (verification.Status != VerifyStatus.Active || verification.PurchaseId is not { } purchaseId)
        {
            // Never grant on doubt: the endpoint only calls this for an active, written purchase.
            return VerifyGrantResult.None;
        }

        var account = await accounts.ValidateAsync(context.AccountToken, context.Install, context.Now, cancellationToken).ConfigureAwait(false);

        // Only after the store checks (this runs after them), only on iOS; challenge = SHA-256(signedTransaction).
        VerifiedSeatKeys? verifiedKeys = null;
        if (context.SeatKeys is { Count: > 0 } inputs && context.SignedTransaction is { } signed)
        {
            var check = proofs.ParseAndVerify(inputs, SeatChallenge.ForVerify(signed.Reveal()), context.Install);
            verifiedKeys = check.Keys;
        }

        SeatResult result;
        var transaction = await transactions.BeginAsync(SeatLogin.App, cancellationToken).ConfigureAwait(false);
        await using (transaction.ConfigureAwait(false))
        {
            RegisteredSeatKey? key = null;
            if (verifiedKeys is not null)
            {
                var registration = await seats.RegisterElementZeroAsync(transaction.Seats, verifiedKeys, attested: null, cancellationToken).ConfigureAwait(false);
                key = registration.Key;
            }

            result = await seats.VerifyAsync(
                transaction.Seats,
                new VerifySeatRequest(
                    purchaseId, context.Install, verification.IsNewPayment, account?.AccountId, verification.PredecessorPurchaseId, key),
                cancellationToken).ConfigureAwait(false);
            await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
        }

        var issue = await entitlement.IssueAsync(context.Install, account?.AccountId, context.Now, carryNotice: false, cancellationToken).ConfigureAwait(false);
        var heldElsewhere = result.Outcome is SeatOutcome.ClaimantAdded or SeatOutcome.AccountRequired;
        return new VerifyGrantResult(
            new Zaghlol.Domain.Sensitive<string>(issue.Token),
            heldElsewhere,
            result.Outcome == SeatOutcome.AccountRequired,
            heldElsewhere ? result.NextMoveAt : null);
    }
}
