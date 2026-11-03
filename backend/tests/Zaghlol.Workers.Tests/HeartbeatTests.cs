using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

namespace Zaghlol.Workers.Tests;

public class HeartbeatTests
{
    private static string NewTempPath() => Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.heartbeat");

    [Fact]
    public void MissingFileIsNotFresh()
    {
        Assert.False(HeartbeatFile.IsFresh(NewTempPath(), DateTimeOffset.UtcNow, TimeSpan.FromSeconds(30)));
    }

    [Fact]
    public void ResolvePathUsesConfiguredValueOrTempDefault()
    {
        Assert.Equal("/x/y", HeartbeatFile.ResolvePath("/x/y"));
        Assert.EndsWith(HeartbeatFile.FileName, HeartbeatFile.ResolvePath(null), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ServiceWritesFreshHeartbeatFile()
    {
        var path = NewTempPath();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Worker:HeartbeatFile"] = path })
            .Build();
        using var service = new WorkerHeartbeatService(
            TimeProvider.System,
            configuration,
            NullLogger<WorkerHeartbeatService>.Instance);

        try
        {
            await service.StartAsync(CancellationToken.None);

            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (!File.Exists(path) && DateTime.UtcNow < deadline)
            {
                await Task.Delay(50);
            }

            Assert.True(File.Exists(path));
            Assert.True(HeartbeatFile.IsFresh(path, DateTimeOffset.UtcNow, TimeSpan.FromSeconds(30)));
        }
        finally
        {
            await service.StopAsync(CancellationToken.None);
            File.Delete(path);
        }
    }
}
