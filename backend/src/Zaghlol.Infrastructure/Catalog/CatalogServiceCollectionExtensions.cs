using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Catalog;
using Zaghlol.Infrastructure.Audit;

namespace Zaghlol.Infrastructure.Catalog;

public static class CatalogServiceCollectionExtensions
{
    /// <summary>
    /// <see cref="ICatalogReader"/> (App login), <see cref="ICatalogAdminStore"/> (Admin login) and the directory snapshot
    /// store. Call after <c>AddZaghlolDatabase</c> with the App and Admin roles and after <c>AddZaghlolKms</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolCatalog(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ICatalogReader, CatalogReader>();
        services.TryAddSingleton<ICatalogSnapshotStore, DirectorySnapshotStore>();
        services.AddZaghlolAudit();
        services.TryAddSingleton<CatalogAdminStore>();
        services.TryAddSingleton<ICatalogAdminStore>(provider => provider.GetRequiredService<CatalogAdminStore>());
        return services;
    }
}
