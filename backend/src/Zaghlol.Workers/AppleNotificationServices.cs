using Zaghlol.Application.Purchases;

namespace Zaghlol.Workers;

/// <summary>
/// The ASSN V2 processor loop (T-134 design note §2): a run at start, then again at once while a run filled its batch, otherwise
/// after <see cref="IdleDelay"/>. One instance across replicas (advisory lock inside the job). A failed run is logged by type only
/// and retried at the next tick; it never stops the host.
/// </summary>
public sealed partial class AppleNotificationProcessorService(
    IServiceProvider services,
    TimeProvider clock,
    ILogger<AppleNotificationProcessorService> logger) : BackgroundService
{
    public static readonly TimeSpan IdleDelay = TimeSpan.FromSeconds(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var busy = false;
            try
            {
                var run = await services.GetRequiredService<AppleNotificationProcessor>().RunOnceAsync(stoppingToken);
                busy = run.Ran && !run.Stopped && run.Rows == AppleNotificationProcessor.BatchSize;
                if (run.Rows > 0)
                {
                    LogRun(logger, run.Rows, run.Applied, run.Failed);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
#pragma warning disable CA1031 // The loop must survive any failure of one run (database down, Apple outage).
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

    [LoggerMessage(Level = LogLevel.Information, Message = "ASSN processor run finished; {Count} rows, {Applied} applied, {Failed} failed")]
    private static partial void LogRun(ILogger logger, int count, int applied, int failed);

    [LoggerMessage(Level = LogLevel.Warning, Message = "ASSN processor run failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}

/// <summary>The daily <c>Get Notification History</c> reconciliation (T-134 §4): a run at start, then every 24 hours.</summary>
public sealed partial class AppleNotificationHistoryService(
    IServiceProvider services,
    TimeProvider clock,
    ILogger<AppleNotificationHistoryService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    protected override Task ExecuteAsync(CancellationToken stoppingToken) =>
        WorkerDelay.EveryAsync(Interval, clock, async () =>
        {
            var run = await services.GetRequiredService<AppleNotificationHistoryJob>().RunOnceAsync(stoppingToken);
            if (run.Ran)
            {
                LogRun(logger, run.Read, run.Inserted, run.Failed);
            }
        }, type => LogFailed(logger, type), stoppingToken);

    [LoggerMessage(Level = LogLevel.Information, Message = "ASSN history reconciliation finished; {Read} read, {Inserted} recovered, {Failed} failed")]
    private static partial void LogRun(ILogger logger, int read, int inserted, int failed);

    [LoggerMessage(Level = LogLevel.Warning, Message = "ASSN history reconciliation failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}

/// <summary>The hourly App Store expiry sweep (T-134 §4): a run at start, then every hour.</summary>
public sealed partial class AppleExpirySweepService(
    IServiceProvider services,
    TimeProvider clock,
    ILogger<AppleExpirySweepService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    protected override Task ExecuteAsync(CancellationToken stoppingToken) =>
        WorkerDelay.EveryAsync(Interval, clock, async () =>
        {
            var run = await services.GetRequiredService<AppleExpirySweepJob>().RunOnceAsync(stoppingToken);
            if (run.Ran)
            {
                LogRun(logger, run.Read, run.Inserted, run.Failed);
            }
        }, type => LogFailed(logger, type), stoppingToken);

    [LoggerMessage(Level = LogLevel.Information, Message = "App Store expiry sweep finished; {Read} rows, {Written} written, {Failed} failed")]
    private static partial void LogRun(ILogger logger, int read, int written, int failed);

    [LoggerMessage(Level = LogLevel.Warning, Message = "App Store expiry sweep failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}

/// <summary>Shared loop helpers of the worker services.</summary>
internal static class WorkerDelay
{
    /// <summary>False when the host is stopping.</summary>
    public static async Task<bool> WaitAsync(TimeSpan delay, TimeProvider clock, CancellationToken stoppingToken)
    {
        try
        {
            await Task.Delay(delay, clock, stoppingToken);
            return true;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
    }

    /// <summary>Runs <paramref name="run"/> at start and then every <paramref name="interval"/>; a failed run is reported by type only.</summary>
    public static async Task EveryAsync(TimeSpan interval, TimeProvider clock, Func<Task> run, Action<string> failed, CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(interval, clock);
        do
        {
            try
            {
                await run();
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
#pragma warning disable CA1031 // The loop must survive any failure of one run (database down, Apple outage).
            catch (Exception exception)
#pragma warning restore CA1031
            {
                failed(exception.GetType().Name);
            }
        }
        while (await Tick(timer, stoppingToken));
    }

    private static async Task<bool> Tick(PeriodicTimer timer, CancellationToken stoppingToken)
    {
        try
        {
            return await timer.WaitForNextTickAsync(stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return false;
        }
    }
}
