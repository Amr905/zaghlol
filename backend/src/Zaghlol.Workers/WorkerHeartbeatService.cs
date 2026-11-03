using System.Globalization;

namespace Zaghlol.Workers;

/// <summary>
/// Placeholder worker: no jobs are registered yet (price fetcher, notification processor, ... arrive in later tasks).
/// It only keeps the host alive and writes a heartbeat file for the container health check.
/// </summary>
public sealed partial class WorkerHeartbeatService(
    TimeProvider clock,
    IConfiguration configuration,
    ILogger<WorkerHeartbeatService> logger) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromSeconds(10);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var path = HeartbeatFile.ResolvePath(configuration["Worker:HeartbeatFile"]);
        LogStarted(logger);

        while (!stoppingToken.IsCancellationRequested)
        {
            await File.WriteAllTextAsync(
                path,
                clock.GetUtcNow().ToString("O", CultureInfo.InvariantCulture),
                stoppingToken);

            try
            {
                await Task.Delay(Interval, clock, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Worker host started; no jobs registered yet")]
    private static partial void LogStarted(ILogger logger);
}
