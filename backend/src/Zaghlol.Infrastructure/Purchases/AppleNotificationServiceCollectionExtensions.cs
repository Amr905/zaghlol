using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>The ASSN V2 metrics over <see cref="ZaghlolMetrics"/> (fixed tag sets only).</summary>
internal sealed class AppleNotificationTelemetry(ZaghlolMetrics metrics) : IAppleNotificationTelemetry
{
    public const string Store = "apple";

    public void Ingested(string env, string outcome) => metrics.AssnIngested(env, outcome);

    public void Processed(string type, string outcome) => metrics.AssnProcessed(type, outcome);

    public void Lag(TimeSpan lag)
    {
        metrics.AssnLag(lag);
        metrics.NotificationProcessed(lag < TimeSpan.Zero ? TimeSpan.Zero : lag);
    }

    public void DeadLettered() => metrics.NotificationDeadLettered(Store);

    public void SetBacklog(long lessThan1h, long atLeast1h) => metrics.SetAssnBacklog(lessThan1h, atLeast1h);

    public void Reconciled(string job, string outcome) => metrics.AssnReconciled(job, outcome);

    public void Recovered(int count) => metrics.AssnRecovered(count);

    public void RefundNotReflected() => metrics.AssnRefundNotReflected();
}

public static class AppleNotificationServiceCollectionExtensions
{
    /// <summary>
    /// The API side of <c>POST /v1/notifications/apple</c> (T-134): the App Store services on the API budget partition, the ingest and
    /// its <c>store_notifications</c> inbox on the App login. Nothing here calls Apple. Call after <c>AddZaghlolDatabase</c> with the App
    /// role and <c>AddZaghlolApiTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolAppleNotificationIngest(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolAppStore();
        AddCommon(services);
        services.TryAddSingleton<IStoreNotificationInbox>(provider =>
        {
            var factory = provider.GetRequiredService<IAppDbContextFactory>();
            return new StoreNotificationInbox(factory.CreateDbContext);
        });
        services.TryAddSingleton<AppleNotificationIngest>();
        return services;
    }

    /// <summary>
    /// The worker side (T-134 design note §2, §4): the App Store services on the worker budget partition (lane
    /// <see cref="StoreLane.Notification"/> only), the processor, the daily history job and the hourly expiry sweep, all on the Worker
    /// login. Call after <c>AddZaghlolDatabase</c> with the Worker role and <c>AddZaghlolTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolAppleNotificationWorker(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolAppStore(AppleBudgetPartition.Worker);
        AddCommon(services);
        services.TryAddSingleton<IStoreNotificationInbox>(provider =>
        {
            var factory = provider.GetRequiredService<IZaghlolDbContextFactory>();
            return new StoreNotificationInbox(() => factory.CreateDbContext(DatabaseRole.Worker));
        });
        services.TryAddSingleton<IAppleNotificationStore, AppleNotificationStore>();

        // Transient: they hold the App Store client, whose handlers the factory rotates.
        services.TryAddTransient<AppleNotificationIngest>();
        services.TryAddTransient<AppleSubscriptionReader>();
        services.TryAddTransient<AppleStateRefresher>();
        services.TryAddTransient<AppleNotificationProcessor>();
        services.TryAddTransient<AppleNotificationHistoryJob>();
        services.TryAddTransient<AppleExpirySweepJob>();
        return services;
    }

    private static void AddCommon(IServiceCollection services)
    {
        services.TryAddSingleton<IPurchaseTelemetry, PurchaseTelemetry>();
        services.TryAddSingleton<IAppleNotificationTelemetry, AppleNotificationTelemetry>();
    }
}
