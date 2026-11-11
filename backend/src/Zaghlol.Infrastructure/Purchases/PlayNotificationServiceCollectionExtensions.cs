using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>The RTDN metrics over <see cref="ZaghlolMetrics"/> (fixed tag sets only).</summary>
internal sealed class PlayNotificationTelemetry(ZaghlolMetrics metrics) : IPlayNotificationTelemetry
{
    /// <summary>The <c>store</c> tag of the generic notification series (seeded since T-138).</summary>
    public const string Store = "play";

    public void Ingested(string kind, string outcome) => metrics.RtdnIngested(kind, outcome);

    public void Processed(string type, string outcome) => metrics.RtdnProcessed(type, outcome);

    public void Lag(TimeSpan lag)
    {
        metrics.RtdnLag(lag);
        metrics.NotificationProcessed(lag < TimeSpan.Zero ? TimeSpan.Zero : lag);
    }

    public void DeadLettered() => metrics.NotificationDeadLettered(Store);

    public void SetBacklog(long lessThan1h, long atLeast1h) => metrics.SetRtdnBacklog(lessThan1h, atLeast1h);

    public void BacklogFailed() => metrics.NotificationBacklogFailed(Store);

    public void Reconciled(string job, string outcome) => metrics.RtdnReconciled(job, outcome);

    public void Recovered(int count) => metrics.RtdnRecovered(count);

    public void RefundNotReflected() => metrics.RtdnRefundNotReflected();

    public void Heartbeat() => metrics.Heartbeat(Store);
}

public static class PlayNotificationServiceCollectionExtensions
{
    /// <summary>
    /// The API side of <c>POST /v1/notifications/google</c> (T-133): the Google Play services on the API budget partition, the RTDN
    /// settings, the ingest and its <c>store_notifications</c> inbox on the App login. Nothing here calls Play. Call after
    /// <c>AddZaghlolDatabase</c> with the App role and <c>AddZaghlolApiTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolPlayNotificationIngest(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolGooglePlay();
        services.TryAddSingleton(provider => PlayRtdnOptions.Read(provider.GetRequiredService<IConfiguration>()));
        services.TryAddSingleton<IPlayNotificationTelemetry, PlayNotificationTelemetry>();
        services.TryAddSingleton<IStoreNotificationInbox>(provider =>
        {
            var factory = provider.GetRequiredService<IAppDbContextFactory>();
            return new StoreNotificationInbox(factory.CreateDbContext);
        });
        services.TryAddSingleton<PlayNotificationIngest>();
        return services;
    }

    /// <summary>
    /// The worker side (T-133 design note §3, §4): the Google Play services on the worker budget partition (acknowledge and
    /// notification lanes), the processor, the daily voided-purchases job and the hourly expiry sweep, all on the Worker login. Call
    /// after <c>AddZaghlolDatabase</c> with the Worker role and <c>AddZaghlolTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolPlayNotificationWorker(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolGooglePlay(PlayBudgetPartition.Worker);
        services.TryAddSingleton<IPlayNotificationTelemetry, PlayNotificationTelemetry>();
        services.TryAddSingleton<IStoreNotificationInbox>(provider =>
        {
            var factory = provider.GetRequiredService<IZaghlolDbContextFactory>();
            return new StoreNotificationInbox(() => factory.CreateDbContext(DatabaseRole.Worker));
        });
        services.TryAddSingleton<IPlayNotificationStore, PlayNotificationStore>();

        // Transient: they hold the Play client, whose handlers the factory rotates.
        services.TryAddTransient<PlayPurchaseReader>();
        services.TryAddTransient<PlayNotificationProcessor>(provider => new PlayNotificationProcessor(
            provider.GetRequiredService<IPlayNotificationStore>(),
            provider.GetRequiredService<PlayPurchaseReader>(),
            provider.GetRequiredService<PlayProductCatalog>(),
            provider.GetRequiredService<IPlayNotificationTelemetry>(),
            provider.GetRequiredService<TimeProvider>()));
        services.TryAddTransient<PlayVoidedReconcileJob>();
        services.TryAddTransient<PlayExpirySweepJob>();
        return services;
    }
}
