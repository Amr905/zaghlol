using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Retention;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Retention;

public static class RetentionServiceCollectionExtensions
{
    /// <summary>
    /// The worker side of the RetentionPurger: the store on the Worker login, the metrics and the job. Call after
    /// <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Worker</c> and <c>AddZaghlolTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolRetention(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IRetentionStore, RetentionStore>();
        services.TryAddSingleton<IRetentionMetrics, ZaghlolRetentionMetrics>();
        services.TryAddSingleton<RetentionPurgeJob>();
        return services;
    }
}

internal sealed class ZaghlolRetentionMetrics(ZaghlolMetrics metrics) : IRetentionMetrics
{
    public void Purged(string rule, long count) => metrics.RetentionPurged(rule, count);

    public void Failed(string rule) => metrics.RetentionFailed(rule);
}
