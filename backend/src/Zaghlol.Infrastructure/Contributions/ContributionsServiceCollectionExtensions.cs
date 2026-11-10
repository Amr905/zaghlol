using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Contributions;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Contributions;

public static class ContributionsServiceCollectionExtensions
{
    /// <summary>
    /// The operator queue on the Admin login. Call after <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Admin</c> and after
    /// <c>AddZaghlolCatalog</c> (promote edits the draft under the catalog lock).
    /// </summary>
    public static IServiceCollection AddZaghlolContributionAdmin(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.AddZaghlolAudit();
        services.TryAddSingleton<IContributionAdminStore, ContributionAdminStore>();
        services.TryAddSingleton<IContributionMetrics, ZaghlolContributionMetrics>();
        return services;
    }

    /// <summary>
    /// The aggregation job on the Worker login. Call after <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Worker</c> and
    /// <c>AddZaghlolTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolContributionWorker(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<IContributionAggregationStore, ContributionAggregationStore>();
        services.TryAddSingleton<IContributionMetrics, ZaghlolContributionMetrics>();
        services.TryAddSingleton<ContributionAggregationJob>();
        return services;
    }
}

internal sealed class ZaghlolContributionMetrics(ZaghlolMetrics metrics) : IContributionMetrics
{
    public void Count(string name, int count) => metrics.ContributionEvent(name, count);
}
