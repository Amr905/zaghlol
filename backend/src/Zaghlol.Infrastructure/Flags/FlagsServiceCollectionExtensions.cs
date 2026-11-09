using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Flags;

namespace Zaghlol.Infrastructure.Flags;

public static class FlagsServiceCollectionExtensions
{
    /// <summary>
    /// The admin store (Admin login, writes flags and their audit rows) and the ops-channel notifier. Call after
    /// <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Admin</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolFlagAdmin(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IFlagAdminStore, FlagAdminStore>();
        services.TryAddSingleton<IOpsNotifier>(provider => new WebhookOpsNotifier(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<ILogger<WebhookOpsNotifier>>()));
        return services;
    }

    /// <summary>The read-only flag reader on the App login, for the sync response. Call after <c>AddZaghlolDatabase</c> with <c>DatabaseRole.App</c>.</summary>
    public static IServiceCollection AddZaghlolFlagReader(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IFlagReader, FlagReader>();
        return services;
    }
}
