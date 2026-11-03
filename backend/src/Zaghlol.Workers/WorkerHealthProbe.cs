namespace Zaghlol.Workers;

internal static class WorkerHealthProbe
{
    private static readonly TimeSpan MaxAge = TimeSpan.FromSeconds(45);

    public static int Run()
    {
        var path = HeartbeatFile.ResolvePath(Environment.GetEnvironmentVariable("Worker__HeartbeatFile"));
        return HeartbeatFile.IsFresh(path, TimeProvider.System.GetUtcNow(), MaxAge) ? 0 : 1;
    }
}
