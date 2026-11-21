using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Infrastructure.Contributions;
using Zaghlol.Infrastructure.Prices;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Infrastructure.Retention;

namespace Zaghlol.Workers;

/// <summary>
/// The background jobs, registered in one place so the worker process (<c>Zaghlol.Workers</c>) and the API's embedded-workers
/// mode (<c>Hosting:EmbeddedWorkers=true</c>, T-206, one IIS site on MonsterASP.NET) run exactly the same set.
/// The caller registers <c>AddInfrastructure</c>, <c>AddZaghlolKms</c> and <c>AddZaghlolDatabase</c> with the Worker role first.
/// </summary>
public static class WorkerJobRegistration
{
    /// <summary>Every worker hosted service, in registration order.</summary>
    public static IReadOnlyList<Type> JobTypes { get; } =
    [
        typeof(WorkerHeartbeatService),
        typeof(PriceFetcherService),
        typeof(ContributionAggregatorService),
        typeof(RetentionPurgerService),
        typeof(PlayAckSweeperService),
        typeof(AppleNotificationProcessorService),
        typeof(AppleNotificationHistoryService),
        typeof(AppleExpirySweepService),
        typeof(PlayNotificationProcessorService),
        typeof(PlayVoidedReconcileService),
        typeof(PlayExpirySweepService),
        typeof(AppleRevocationRetryService),
    ];

    public static IServiceCollection AddZaghlolWorkerJobs(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddHostedService<WorkerHeartbeatService>();

        // Price fetcher (T-127): providers from Prices:Providers, hourly.
        services.AddZaghlolPriceWorker();
        services.AddHostedService<PriceFetcherService>();

        // Contribution aggregator (T-129): roll raw rows into aggregates, A-48 threshold, retention purge.
        services.AddZaghlolContributionWorker();
        services.AddHostedService<ContributionAggregatorService>();
        // RetentionPurger (T-139): daily, Retention:IntervalHours / Retention:BatchSize.
        services.AddZaghlolRetention();
        services.AddHostedService<RetentionPurgerService>();
        // Google acknowledge sweeper (T-130): every 15 min, one instance across replicas (advisory lock), Purchases:Google:* config.
        services.AddZaghlolPlayAckSweeper();
        services.AddHostedService<PlayAckSweeperService>();
        // App Store Server Notifications V2 (T-134): processor (5 s idle poll), daily history reconciliation, hourly expiry sweep; one
        // instance of each across replicas (advisory locks), Purchases:Apple:* config, the worker's share of the Apple budget.
        services.AddZaghlolAppleNotificationWorker();
        services.AddHostedService<AppleNotificationProcessorService>();
        services.AddHostedService<AppleNotificationHistoryService>();
        services.AddHostedService<AppleExpirySweepService>();
        // Google RTDN (T-133): processor (5 s idle poll), daily voided-purchases reconciliation, hourly expiry sweep; one instance of each
        // across replicas (advisory locks), Purchases:Google:* config, the worker's share of the Play budget (with the ack sweeper's).
        services.AddZaghlolPlayNotificationWorker();
        services.AddHostedService<PlayNotificationProcessorService>();
        services.AddHostedService<PlayVoidedReconcileService>();
        services.AddHostedService<PlayExpirySweepService>();
        // Apple revocation retry (T-135): token revocations that failed at account deletion, every 15 min for up to 30 days. Needs the
        // Kms:* ring (registered by the caller) and Accounts:Apple:* (the Sign in with Apple key).
        services.AddZaghlolAppleRevocationWorker();
        services.AddHostedService<AppleRevocationRetryService>();
        return services;
    }
}
