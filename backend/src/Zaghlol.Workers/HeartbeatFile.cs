namespace Zaghlol.Workers;

/// <summary>
/// The worker proves liveness by touching a file; the container health check reads its age.
/// </summary>
public static class HeartbeatFile
{
    public const string FileName = "zaghlol-worker.heartbeat";

    public static string ResolvePath(string? configured) =>
        string.IsNullOrWhiteSpace(configured) ? Path.Combine(Path.GetTempPath(), FileName) : configured;

    public static bool IsFresh(string path, DateTimeOffset now, TimeSpan maxAge)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        return now - File.GetLastWriteTimeUtc(path) <= maxAge;
    }
}
