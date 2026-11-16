using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Support;

/// <summary>
/// Maps the stored purchase to the T-130 / T-131 order lookups. A purchase whose product the server no longer knows can't be checked
/// and is <see cref="OwnershipOutcome.Unavailable"/> (our configuration, not the user's fault).
/// </summary>
public sealed class SupportOwnershipCheck(IPlayOrderLookup play, IAppStoreOrderLookup apple, PlayProductCatalog playProducts) : ISupportOwnershipCheck
{
    public async Task<OwnershipOutcome> CheckAsync(SupportPurchase purchase, Sensitive<string> orderId, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(purchase);

        if (purchase.Store == SupportStore.AppStore)
        {
            return await apple.CheckAsync(orderId, new AppStoreOwnershipPurchase(purchase.StoreKey, purchase.Environment), cancellationToken)
                .ConfigureAwait(false);
        }

        if (!playProducts.TryGet(purchase.ProductId, out var product))
        {
            return OwnershipOutcome.Unavailable;
        }

        return await play.CheckAsync(orderId, new OwnershipPurchase(product.Kind, purchase.StoreKey, purchase.LinkedPurchaseToken), cancellationToken)
            .ConfigureAwait(false);
    }
}
