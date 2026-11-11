using Zaghlol.Application.Purchases;

namespace Zaghlol.Workers;

/// <summary>
/// The Google acknowledge sweeper (T-130 design note §3): one run at start, then every 15 minutes. Each run resolves a fresh
/// <see cref="PlayAckSweepJob"/> (it holds the typed Play client). A run that finds the advisory lock taken does nothing; a failed
/// run is logged by type only and retried at the next tick; it never stops the host.
/// </summary>
public sealed partial class PlayAckSweeperService(
    IServiceProvider services,
    TimeProvider clock,
    ILogger<PlayAckSweeperService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromMinutes(15);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval, clock);
        do
        {
            try
            {
                var run = await services.GetRequiredService<PlayAckSweepJob>().RunOnceAsync(stoppingToken);
                if (run.Ran)
                {
                    LogRun(logger, run.Rows, run.Acknowledged, run.Failed);
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
        }
        while (await WaitAsync(timer, stoppingToken));
    }

    private static async Task<bool> WaitAsync(PeriodicTimer timer, CancellationToken stoppingToken)
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

    [LoggerMessage(Level = LogLevel.Information, Message = "Acknowledge sweep finished; {Count} rows read")]
    private static partial void LogRun(ILogger logger, int count, int acknowledged, int failed);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Acknowledge sweep failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}
