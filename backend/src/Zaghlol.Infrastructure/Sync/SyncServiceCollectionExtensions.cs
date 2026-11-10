using System.Globalization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Sync;

namespace Zaghlol.Infrastructure.Sync;

public static class SyncServiceCollectionExtensions
{
    public const string ThrottleWindowKey = "Sync:ThrottleWindow";
    public const string MaxDeltaOpsKey = "Sync:MaxDeltaOps";

    /// <summary>
    /// The sync service and its ports: the store on the App login, the keyed install hasher (KMS), the options from
    /// <c>Sync:*</c> and the default <see cref="NullSyncEntitlementBlock"/> (T-132 replaces it). Call after
    /// <c>AddZaghlolDatabase</c> with the App role, <c>AddZaghlolKms</c>, <c>AddZaghlolCatalog</c>, <c>AddZaghlolFlagReader</c>
    /// and <c>AddZaghlolPrices</c>; the host registers <see cref="ISyncTelemetry"/>.
    /// </summary>
    public static IServiceCollection AddZaghlolSyncServices(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ISyncStore, SyncStore>();
        services.TryAddSingleton<IInstallHasher, KeyedInstallHasher>();
        services.TryAddSingleton<ISyncEntitlementBlock, NullSyncEntitlementBlock>();
        services.TryAddSingleton(provider => ReadOptions(provider.GetRequiredService<IConfiguration>()));
        services.TryAddSingleton<SyncService>();
        return services;
    }

    /// <summary><c>Sync:ThrottleWindow</c> (a <c>TimeSpan</c>, default 24 h) and <c>Sync:MaxDeltaOps</c> (default 2000), both positive.</summary>
    public static SyncOptions ReadOptions(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var defaults = SyncOptions.Default;
        var window = defaults.ThrottleWindow;
        if (configuration[ThrottleWindowKey] is { Length: > 0 } windowText
            && (!TimeSpan.TryParse(windowText, CultureInfo.InvariantCulture, out window) || window <= TimeSpan.Zero))
        {
            throw new InvalidOperationException("Sync:ThrottleWindow must be a positive TimeSpan.");
        }

        var maxOps = defaults.MaxDeltaOps;
        if (configuration[MaxDeltaOpsKey] is { Length: > 0 } opsText
            && (!int.TryParse(opsText, NumberStyles.None, CultureInfo.InvariantCulture, out maxOps) || maxOps <= 0))
        {
            throw new InvalidOperationException("Sync:MaxDeltaOps must be a positive integer.");
        }

        return new SyncOptions(window, maxOps);
    }
}
