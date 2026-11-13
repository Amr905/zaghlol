using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Sync;

namespace Zaghlol.Infrastructure.Entitlements;

public static class EntitlementServiceCollectionExtensions
{
    /// <summary>
    /// The entitlement (T-132): the store, the signer, the account-token validator, <see cref="EntitlementService"/>, the real
    /// <see cref="IVerifyGrant"/> and the sync's <see cref="ISyncEntitlementBlock"/>. Call <b>before</b>
    /// <c>AddZaghlolPurchaseVerification</c> and <c>AddZaghlolSync</c> (their placeholders are <c>TryAdd</c>), and after
    /// <c>AddZaghlolKms</c>, <c>AddZaghlolSeatKeys</c>, <c>AddZaghlolSeats</c> and <c>AddZaghlolDatabase</c> with the App role.
    /// </summary>
    public static IServiceCollection AddZaghlolEntitlements(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<IEntitlementStore, EntitlementStore>();
        services.TryAddSingleton<IEntitlementSigner, KmsEntitlementSigner>();
        services.TryAddSingleton<IAccountTokenValidator, AccountTokenValidator>();
        services.TryAddSingleton<EntitlementService>();
        services.TryAddSingleton<IVerifyGrant, VerifyGrant>();
        services.TryAddSingleton<ISyncEntitlementBlock, SyncEntitlementBlock>();
        return services;
    }
}
