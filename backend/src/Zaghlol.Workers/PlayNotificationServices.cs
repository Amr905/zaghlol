using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Workers;

/// <summary>
/// The Google RTDN processor loop (T-133 design note §3): a run at start, then again at once while a run filled its batch, otherwise
/// after <see cref="IdleDelay"/>. One instance across replicas (advisory lock inside the job). The heartbeat gauge of this process
/// starts when the loop starts, so a processor that never completes a run is paged (FU-077 L-3). A failed run is logged by type only
/// and retried at the next tick; it never stops the host.
/// </summary>
public sealed partial class PlayNotificationProcessorService(
    IServiceProvider services,
    ZaghlolMetrics metrics,
    TimeProvider clock,
    ILogger<PlayNotificationProcessorService> logger) : BackgroundService
{
    public static readonly TimeSpan IdleDelay = TimeSpan.FromSeconds(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        metrics.TrackHeartbeat("play");
        while (!stoppingToken.IsCancellationRequested)
        {
            var busy = false;
            try
            {
                var run = await services.GetRequiredService<PlayNotificationProcessor>().RunOnceAsync(stoppingToken);
                busy = run.Ran && !run.Stopped && run.Rows == PlayNotificationProcessor.BatchSize;
                if (run.Rows > 0)
                {
                    LogRun(logger, run.Rows, run.Applied, run.Failed);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
#pragma warning disable CA1031 // The loop must survive any failure of one run (database down, Play outage).
            catch (Exception exception)
#pragma warning restore CA1031
            {
                LogFailed(logger, exception.GetType().Name);
            }

            if (!busy && !await WorkerDelay.WaitAsync(IdleDelay, clock, stoppingToken))
            {
                break;
            }
        }
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "RTDN processor run finished; {Count} rows, {Applied} applied, {Failed} failed")]
    private static partial void LogRun(ILogger logger, int count, int applied, int failed);

    [LoggerMessage(Level = LogLevel.Warning, Message = "RTDN processor run failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}

/// <summary>The daily voided-purchases reconciliation (T-133 §4): a run at start, then every 24 hours.</summary>
public sealed partial class PlayVoidedReconcileService(
    IServiceProvider services,
    TimeProvider clock,
    ILogger<PlayVoidedReconcileService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    protected override Task ExecuteAsync(CancellationToken stoppingToken) =>
        WorkerDelay.EveryAsync(Interval, clock, async () =>
        {
            var run = await services.GetRequiredService<PlayVoidedReconcileJob>().RunOnceAsync(stoppingToken);
            if (run.Ran)
            {
                LogRun(logger, run.Read, run.Inserted, run.Skipped);
            }
        }, type => LogFailed(logger, type), stoppingToken);

    [LoggerMessage(Level = LogLevel.Information, Message = "Play voided reconciliation finished; {Read} read, {Inserted} enqueued, {Skipped} skipped")]
    private static partial void LogRun(ILogger logger, int read, int inserted, int skipped);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Play voided reconciliation failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}

/// <summary>The hourly Google expiry sweep (T-133 §4): a run at start, then every hour.</summary>
public sealed partial class PlayExpirySweepService(
    IServiceProvider services,
    TimeProvider clock,
    ILogger<PlayExpirySweepService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    protected override Task ExecuteAsync(CancellationToken stoppingToken) =>
        WorkerDelay.EveryAsync(Interval, clock, async () =>
        {
            var run = await services.GetRequiredService<PlayExpirySweepJob>().RunOnceAsync(stoppingToken);
            if (run.Ran && run.Read > 0)
            {
                LogRun(logger, run.Read, run.Inserted);
            }
        }, type => LogFailed(logger, type), stoppingToken);

    [LoggerMessage(Level = LogLevel.Information, Message = "Play expiry sweep finished; {Read} candidates, {Inserted} enqueued")]
    private static partial void LogRun(ILogger logger, int read, int inserted);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Play expiry sweep failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}
