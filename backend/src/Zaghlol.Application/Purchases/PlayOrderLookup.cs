using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>Which ownership-check path runs (<c>Purchases:Google:OrderLookup</c>, default <see cref="Fallback"/>).</summary>
public enum PlayOrderLookupPath
{
    /// <summary>Play <c>orders.get</c>: the order's <c>purchaseToken</c> must be in the purchase's chain.</summary>
    Orders,

    /// <summary>R4-7/R5-8: compare with <c>lineItems[].latestSuccessfulOrderId</c> along the <c>linkedPurchaseToken</c> chain.</summary>
    Fallback,
}

/// <summary>The stored purchase a support check is about (from <c>purchases</c>, read by the caller under its own audit).</summary>
public sealed record OwnershipPurchase(PlayProductKind Kind, Sensitive<string> Token, Sensitive<string>? LinkedPurchaseToken);

/// <summary>
/// The live Google Play order-ID check of the audited support actions (D-57, backend-api §5.3; T-186 calls it). The order ID
/// lives only in this call: it is never stored, logged, traced or put in an exception message.
/// </summary>
public interface IPlayOrderLookup
{
    Task<OwnershipOutcome> CheckAsync(Sensitive<string> orderId, OwnershipPurchase purchase, CancellationToken cancellationToken);
}

/// <summary>
/// Both paths of the ownership check (T-130 design note §6). <c>pass</c> needs a positive match; a Play 4xx on the order or the
/// token is <c>fail</c>; an outage, an open circuit or an exhausted <c>support</c> budget is <c>unavailable</c>, never
/// <c>fail</c>. The deprecated <c>latestOrderId</c> is never read (the DTO has no member for it).
/// </summary>
public sealed class PlayOrderLookup(
    IPlayDeveloperApi play,
    PlayOrderLookupPath path,
    IPurchaseTelemetry telemetry,
    TimeProvider clock) : IPlayOrderLookup
{
    /// <summary>How many tokens of a <c>linkedPurchaseToken</c> chain are read at most.</summary>
    public const int MaxChainDepth = 10;

    public PlayOrderLookupPath Path => path;

    public async Task<OwnershipOutcome> CheckAsync(Sensitive<string> orderId, OwnershipPurchase purchase, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(purchase);

        OwnershipOutcome outcome;
        if (!PlayStateMapping.IsWellFormedOrderId(orderId))
        {
            outcome = OwnershipOutcome.Fail;
        }
        else
        {
            try
            {
                outcome = path == PlayOrderLookupPath.Orders
                    ? await ByOrderAsync(orderId, purchase, cancellationToken)
                    : await ByChainAsync(orderId, purchase, cancellationToken);
            }
            catch (PlayApiException error)
            {
                outcome = error.IsFinalRejection ? OwnershipOutcome.Fail : OwnershipOutcome.Unavailable;
            }
        }

        telemetry.OwnershipChecked(path == PlayOrderLookupPath.Orders ? PurchaseTags.PathOrders : PurchaseTags.PathFallback, outcome);
        return outcome;
    }

    private async Task<OwnershipOutcome> ByOrderAsync(Sensitive<string> orderId, OwnershipPurchase purchase, CancellationToken cancellationToken)
    {
        var order = await play.GetOrderAsync(orderId, StoreLane.Support, cancellationToken);
        if (order.State is not (PlayOrderState.Processed or PlayOrderState.PartiallyRefunded))
        {
            return OwnershipOutcome.Fail;
        }

        if (order.PurchaseToken?.Reveal() is not { } orderToken)
        {
            // orders.get without purchaseToken can't decide anything: the operator retries or the fallback path is configured.
            return OwnershipOutcome.Unavailable;
        }

        if (PlayStateMapping.FixedTimeEquals(orderToken, purchase.Token.Reveal())
            || PlayStateMapping.FixedTimeEquals(orderToken, purchase.LinkedPurchaseToken?.Reveal()))
        {
            return OwnershipOutcome.Pass;
        }

        if (purchase.Kind != PlayProductKind.Subscription)
        {
            return OwnershipOutcome.Fail;
        }

        // Further back in the chain: follow linkedPurchaseToken through Play reads, comparing each predecessor.
        var seen = new HashSet<string>(StringComparer.Ordinal) { purchase.Token.Reveal() };
        var next = purchase.LinkedPurchaseToken
            ?? (await play.GetSubscriptionAsync(purchase.Token, StoreLane.Support, cancellationToken)).LinkedPurchaseToken;
        while (next is { } token && seen.Count < MaxChainDepth && seen.Add(token.Reveal()))
        {
            if (PlayStateMapping.FixedTimeEquals(orderToken, token.Reveal()))
            {
                return OwnershipOutcome.Pass;
            }

            next = (await play.GetSubscriptionAsync(token, StoreLane.Support, cancellationToken)).LinkedPurchaseToken;
        }

        return OwnershipOutcome.Fail;
    }

    private async Task<OwnershipOutcome> ByChainAsync(Sensitive<string> orderId, OwnershipPurchase purchase, CancellationToken cancellationToken)
    {
        var wanted = orderId.Reveal();
        if (purchase.Kind == PlayProductKind.OneTime)
        {
            var product = await play.GetProductAsync(purchase.Token, StoreLane.Support, cancellationToken);
            return product.State == PlayProductState.Purchased && PlayStateMapping.FixedTimeEquals(product.OrderId?.Reveal(), wanted)
                ? OwnershipOutcome.Pass
                : OwnershipOutcome.Fail;
        }

        // The purchase's own token must still entitle; the order may be the latest one of that token or of a predecessor
        // (an upgrade, downgrade or re-subscription), reached through linkedPurchaseToken: the stored link first, then Play's.
        var now = clock.GetUtcNow();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        Sensitive<string>? current = purchase.Token;
        var head = true;
        while (current is { } token && seen.Count < MaxChainDepth && seen.Add(token.Reveal()))
        {
            var read = await play.GetSubscriptionAsync(token, StoreLane.Support, cancellationToken);
            if (head && !read.LineItems.Any(i => PlayStateMapping.Map(read.State, i.ExpiryTime, now).Status == VerifyStatus.Active))
            {
                return OwnershipOutcome.Fail;
            }

            if (read.LineItems.Any(i => PlayStateMapping.FixedTimeEquals(i.LatestSuccessfulOrderId?.Reveal(), wanted)))
            {
                return OwnershipOutcome.Pass;
            }

            current = read.LinkedPurchaseToken ?? (head ? purchase.LinkedPurchaseToken : null);
            head = false;
        }

        return OwnershipOutcome.Fail;
    }
}
