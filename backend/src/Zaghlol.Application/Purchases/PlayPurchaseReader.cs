using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>One Play read of a purchase token, mapped (T-130 design note §1 step 3-4).</summary>
/// <param name="PlayProductId">
/// The product ID Play returned that equals the expected one, or <c>null</c> when Play's answer names another product (another
/// product's token is not this purchase).
/// </param>
public sealed record PlayPurchaseRead(
    string? PlayProductId,
    MappedPlayState Mapped,
    DateTimeOffset? ExpiresAt,
    Sensitive<string>? LinkedPurchaseToken,
    bool Acknowledged,
    bool TestPurchase,
    string? ObfuscatedAccountId,
    DateTimeOffset? PurchasedAt)
{
    /// <summary>Play's answer is for the expected product.</summary>
    public bool ProductMatches => PlayProductId is not null;

    public PurchaseEnvironment Environment => TestPurchase ? PurchaseEnvironment.Sandbox : PurchaseEnvironment.Production;
}

/// <summary>
/// The Play read verify, the RTDN worker and its jobs share (T-133 design note §3 step 3): <c>subscriptionsv2.get</c> or
/// <c>productsv2.getproductpurchasev2</c> on the given budget lane, mapped through <see cref="PlayStateMapping"/>. Extracted unchanged
/// from <c>PlayVerification</c>, with the lane as a parameter. Play failures propagate as <see cref="PlayApiException"/>; each caller
/// decides what they mean.
/// </summary>
public sealed class PlayPurchaseReader(IPlayDeveloperApi play)
{
    public Task<PlayPurchaseRead> ReadAsync(
        PlayProductKind kind,
        Sensitive<string> token,
        string productId,
        StoreLane lane,
        DateTimeOffset now,
        CancellationToken cancellationToken) =>
        kind == PlayProductKind.Subscription
            ? ReadSubscriptionAsync(token, productId, lane, now, cancellationToken)
            : ReadProductAsync(token, productId, lane, cancellationToken);

    public async Task<PlayPurchaseRead> ReadSubscriptionAsync(
        Sensitive<string> token,
        string productId,
        StoreLane lane,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var subscription = await play.GetSubscriptionAsync(token, lane, cancellationToken);

        // The product ID Play returns must equal the expected one (another product's token is not this purchase).
        var item = subscription.LineItems.FirstOrDefault(i => string.Equals(i.ProductId, productId, StringComparison.Ordinal));
        if (item is null)
        {
            return new PlayPurchaseRead(null, default, null, null, false, subscription.TestPurchase, null, null);
        }

        return new PlayPurchaseRead(
            item.ProductId!,
            PlayStateMapping.Map(subscription.State, item.ExpiryTime, now),
            item.ExpiryTime,
            subscription.LinkedPurchaseToken,
            subscription.Acknowledged,
            subscription.TestPurchase,
            subscription.ObfuscatedExternalAccountId,
            subscription.StartTime);
    }

    public async Task<PlayPurchaseRead> ReadProductAsync(
        Sensitive<string> token,
        string productId,
        StoreLane lane,
        CancellationToken cancellationToken)
    {
        var product = await play.GetProductAsync(token, lane, cancellationToken);

        var matched = product.ProductIds.FirstOrDefault(id => string.Equals(id, productId, StringComparison.Ordinal));
        if (matched is null)
        {
            return new PlayPurchaseRead(null, default, null, null, false, product.TestPurchase, null, null);
        }

        return new PlayPurchaseRead(
            matched,
            PlayStateMapping.Map(product.State),
            null,
            null,
            product.Acknowledged,
            product.TestPurchase,
            product.ObfuscatedExternalAccountId,
            product.PurchaseCompletionTime);
    }
}
