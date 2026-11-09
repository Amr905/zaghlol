using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Zaghlol.Infrastructure.Installs;

public static class InstallsServiceCollectionExtensions
{
    /// <summary>
    /// <see cref="IInstallStore"/> and <see cref="IIdempotencyStore"/> on the <c>App</c> login only (FU-021). Call after
    /// <c>AddZaghlolDatabase</c> with <c>DatabaseRole.App</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolInstallStores(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IInstallStore, InstallStore>();
        services.TryAddSingleton<IIdempotencyStore, IdempotencyStore>();
        return services;
    }
}
