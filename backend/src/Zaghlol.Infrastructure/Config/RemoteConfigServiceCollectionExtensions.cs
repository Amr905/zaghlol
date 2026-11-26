using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Config;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Audit;

namespace Zaghlol.Infrastructure.Config;

public static class RemoteConfigServiceCollectionExtensions
{
    /// <summary>
    /// <c>remote_config</c>: the admin store and service (Admin login, audited), the reader and per-request service (App login),
    /// and the per-install LLM feature gate over the flag reader. Call after <c>AddZaghlolDatabase</c> and <c>AddZaghlolFlagReader</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolRemoteConfig(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolAudit();
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<IRemoteConfigAdminStore, RemoteConfigAdminStore>();
        services.TryAddSingleton<RemoteConfigAdminService>();
        services.TryAddSingleton<IRemoteConfigReader, RemoteConfigReader>();
        services.TryAddSingleton<IRemoteConfigService, RemoteConfigService>();
        services.TryAddSingleton<ILlmFeatureGate>(provider => new LlmFeatureGate(provider.GetRequiredService<IFlagReader>()));
        return services;
    }
}
