using Zaghlol.Application.Retention;

namespace Zaghlol.Workers;

/// <summary>
/// The RetentionPurger (NFR-PRIV-06, backend-schema.md section 4): one run at start, then one every
/// <c>Retention:IntervalHours</c> (default 24, at least 1). Every rule is idempotent, so a run at each start is harmless. A failed
/// rule is logged by name and counted, never by exception message, and retried at the next tick. Logs carry only the rule name
/// and a row count (the T-138 allow-list drops anything else); no IP, token or row content ever reaches this code.
/// </summary>
public sealed partial class RetentionPurgerService(
    RetentionPurgeJob job,
    TimeProvider clock,
    IConfiguration configuration,
    ILogger<RetentionPurgerService> logger) : BackgroundService
{
    public const int DefaultIntervalHours = 24;

    public static TimeSpan IntervalFrom(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var hours = int.TryParse(configuration["Retention:IntervalHours"], out var parsed) ? parsed : DefaultIntervalHours;
        return TimeSpan.FromHours(Math.Max(1, hours));
    }

    public static int BatchSizeFrom(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var size = int.TryParse(configuration["Retention:BatchSize"], out var parsed) ? parsed : RetentionPurgeJob.DefaultBatchSize;
        return Math.Clamp(size, 100, 50_000);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(IntervalFrom(configuration), clock);
        do
        {
            try
            {
                var result = await job.RunOnceAsync(BatchSizeFrom(configuration), stoppingToken);
                foreach (var (rule, count) in result.Purged)
                {
                    if (count > 0)
                    {
                        LogPurged(logger, rule, count);
                    }
                }

                foreach (var rule in result.Failed)
                {
                    LogRuleFailed(logger, rule);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
#pragma warning disable CA1031 // The loop must survive any failure of one run.
            catch (Exception exception)
#pragma warning restore CA1031
            {
                LogRunFailed(logger, exception.GetType().Name);
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

    [LoggerMessage(Level = LogLevel.Information, Message = "Retention purge finished {Operation} {Count}")]
    private static partial void LogPurged(ILogger logger, string operation, int count);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Retention rule failed {Operation}")]
    private static partial void LogRuleFailed(ILogger logger, string operation);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Retention run failed: {ExceptionType}")]
    private static partial void LogRunFailed(ILogger logger, string exceptionType);
}
