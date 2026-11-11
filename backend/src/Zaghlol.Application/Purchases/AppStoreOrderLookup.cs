using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// D-57 for App Store purchases (T-131 design note §7): <c>Look Up Order ID</c> on production. <c>pass</c> needs <c>status = 0</c>
/// and a verified signed transaction of this purchase's <c>originalTransactionId</c> that isn't refunded; <c>status = 1</c>, another
/// purchase's order, a refunded order, a malformed order ID and a sandbox purchase (the endpoint doesn't exist there) are
/// <c>fail</c>; an outage, our <c>support</c> budget, a JWS Apple signed that fails verification, a status value Apple adds later
/// and a 401 are <c>unavailable</c>, never <c>fail</c>. The order ID lives only in this call.
/// </summary>
public sealed partial class AppStoreOrderLookup(
    IAppStoreServerApi apple,
    IAppleJwsVerifier jws,
    AppStoreCatalog catalog,
    IPurchaseTelemetry telemetry,
    TimeProvider clock) : IAppStoreOrderLookup
{
    /// <summary>Apple order IDs (for example <c>MK5TTTVWJH</c>), after upper-casing: checked before any call.</summary>
    public const string OrderIdPattern = @"^[A-Z0-9]{6,20}\z";

    /// <summary>The most signed transactions read from one order.</summary>
    public const int MaxTransactions = 50;

    public async Task<OwnershipOutcome> CheckAsync(Sensitive<string> orderId, AppStoreOwnershipPurchase purchase, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(purchase);

        var outcome = await DecideAsync(orderId, purchase, cancellationToken);
        telemetry.OwnershipChecked(PurchaseTags.PathApple, outcome);
        return outcome;
    }

    private async Task<OwnershipOutcome> DecideAsync(Sensitive<string> orderId, AppStoreOwnershipPurchase purchase, CancellationToken cancellationToken)
    {
        if (orderId.Reveal()?.ToUpperInvariant() is not { } normalized || !OrderId().IsMatch(normalized)
            || purchase.Environment == PurchaseEnvironment.Sandbox)
        {
            return OwnershipOutcome.Fail;
        }

        AppleOrderLookupResult lookup;
        try
        {
            lookup = await apple.LookUpOrderIdAsync(new Sensitive<string>(normalized), StoreLane.Support, cancellationToken);
        }
        catch (AppStoreApiException)
        {
            // Only Apple's explicit status says anything about the order (the T-130 L-4 lesson): every error is "try again".
            return OwnershipOutcome.Unavailable;
        }

        switch (lookup.Status)
        {
            case 0:
                break;
            case 1:
                return OwnershipOutcome.Fail;
            default:
                return OwnershipOutcome.Unavailable;
        }

        if (lookup.SignedTransactions.Count > MaxTransactions)
        {
            return OwnershipOutcome.Unavailable;
        }

        var now = clock.GetUtcNow();
        var wanted = purchase.OriginalTransactionId.Reveal();
        var matched = false;
        var refunded = false;
        foreach (var signed in lookup.SignedTransactions)
        {
            AppleTransaction transaction;
            try
            {
                transaction = jws.VerifyTransaction(signed, JwsSource.Api, now);
                telemetry.AppleJwsChecked(JwsSource.Api, null);
            }
            catch (AppleJwsException error)
            {
                telemetry.AppleJwsChecked(JwsSource.Api, error.Reason);
                return OwnershipOutcome.Unavailable;
            }

            if (!string.Equals(transaction.BundleId, catalog.BundleId, StringComparison.Ordinal) || transaction.Environment != AppleEnvironment.Production)
            {
                // Apple answered for another app or environment: doubt, alerted, never a decision.
                telemetry.AppleJwsChecked(JwsSource.Api, AppleJwsFailure.Payload);
                return OwnershipOutcome.Unavailable;
            }

            if (PlayStateMapping.FixedTimeEquals(transaction.OriginalTransactionId?.Reveal(), wanted))
            {
                matched = true;
                refunded |= transaction.RevocationDate is not null;
            }
        }

        return matched && !refunded ? OwnershipOutcome.Pass : OwnershipOutcome.Fail;
    }

    [GeneratedRegex(OrderIdPattern, RegexOptions.CultureInvariant)]
    private static partial Regex OrderId();
}
