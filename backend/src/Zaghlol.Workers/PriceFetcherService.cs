using Zaghlol.Application.Prices;

namespace Zaghlol.Workers;

/// <summary>
/// The hourly price fetch (FR-BE-04, ADR-014): one run at start, then one every <c>Prices:IntervalMinutes</c> (default 60, at
/// least 1). A failed run is logged by type only and retried at the next tick; it never stops the host.
/// </summary>
public sealed partial class PriceFetcherService(
    PriceFetchJob job,
    TimeProvider clock,
    IConfiguration configuration,
    ILogger<PriceFetcherService> logger) : BackgroundService
{
    public const int DefaultIntervalMinutes = 60;

    public static TimeSpan IntervalFrom(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var minutes = int.TryParse(configuration["Prices:IntervalMinutes"], out var parsed) ? parsed : DefaultIntervalMinutes;
        return TimeSpan.FromMinutes(Math.Max(1, minutes));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(IntervalFrom(configuration), clock);
        do
        {
            try
            {
                var written = await job.RunOnceAsync(stoppingToken);
                LogRun(logger, written);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
#pragma warning disable CA1031 // The loop must survive any failure of one run (database down, provider bug).
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

    [LoggerMessage(Level = LogLevel.Information, Message = "Price fetch finished; {Written} quotes written")]
    private static partial void LogRun(ILogger logger, int written);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Price fetch failed: {ExceptionType}")]
    private static partial void LogFailed(ILogger logger, string exceptionType);
}
