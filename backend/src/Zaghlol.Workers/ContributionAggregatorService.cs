using Zaghlol.Application.Contributions;

namespace Zaghlol.Workers;

/// <summary>
/// The contribution aggregation (FR-BE-07, A-48): one run at start, then one every <c>Contributions:IntervalMinutes</c>
/// (default 60, at least 1). Each run rolls the raw rows up, marks aggregates with at least 5 distinct installs
/// <c>ready_for_review</c>, and purges raw rows (decided aggregates, and older than 180 days). A failed run is logged by type
/// only and retried at the next tick; it never stops the host. Nothing here logs merchant text or counts per key.
/// </summary>
public sealed partial class ContributionAggregatorService(
    ContributionAggregationJob job,
    TimeProvider clock,
    IConfiguration configuration,
    ILogger<ContributionAggregatorService> logger) : BackgroundService
{
    public const int DefaultIntervalMinutes = 60;

    public static TimeSpan IntervalFrom(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var minutes = int.TryParse(configuration["Contributions:IntervalMinutes"], out var parsed) ? parsed : DefaultIntervalMinutes;
        return TimeSpan.FromMinutes(Math.Max(1, minutes));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(IntervalFrom(configuration), clock);
        do
        {
            try
            {
                var run = await job.RunOnceAsync(stoppingToken);
                LogRun(logger, run.Updated, run.BecameReady, run.PurgedDecided, run.PurgedExpired);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
#pragma warning disable CA1031 // The loop must survive any failure of one run (database down).
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

    [LoggerMessage(Level = LogLevel.Information, Message = "Contribution aggregation finished; {Updated} aggregates refreshed, {Ready} newly ready, {PurgedDecided} decided and {PurgedExpired} expired raw rows purged")]
    private static partial void LogRun(ILogger logger, int updated, int ready, int purgedDecided, int purgedExpired);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Contribution aggregation failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}
