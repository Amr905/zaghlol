using Zaghlol.Application.Accounts;

namespace Zaghlol.Workers;

/// <summary>
/// Retries Apple token revocations that failed at account deletion (T-135, Lead decision): one pass at start, then every 15 minutes.
/// Each row backs off exponentially and is dropped after 30 days. A failed pass is logged by exception type only and retried at
/// the next tick; it never stops the host. Logs carry counts only, never a token.
/// </summary>
public sealed partial class AppleRevocationRetryService(
    AppleRevocationRetryJob job,
    TimeProvider clock,
    ILogger<AppleRevocationRetryService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromMinutes(15);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval, clock);
        do
        {
            try
            {
                var run = await job.RunOnceAsync(stoppingToken);
                if (run.Revoked + run.Deferred + run.Dropped + run.GaveUp > 0)
                {
                    LogRun(logger, run.Revoked, run.Deferred, run.Dropped, run.GaveUp);
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

    [LoggerMessage(Level = LogLevel.Information, Message = "Apple revocation retry: {Revoked} revoked, {Deferred} deferred, {Dropped} unreadable dropped, {GaveUp} past the window dropped")]
    private static partial void LogRun(ILogger logger, int revoked, int deferred, int dropped, int gaveUp);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Apple revocation retry failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}
