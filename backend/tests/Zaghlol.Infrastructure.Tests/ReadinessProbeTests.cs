using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// The readiness probe against a "black hole" server that accepts TCP connections and never answers: proves the 1 s
/// timeout, the 2 s cache and that concurrent callers share one probe (each probe is one accepted connection).
/// </summary>
public sealed class ReadinessProbeTests : IAsyncLifetime, IDisposable
{
    private readonly TcpListener listener = new(IPAddress.Loopback, 0);
    private readonly List<TcpClient> accepted = [];
    private readonly CancellationTokenSource stop = new();
    private Task? acceptLoop;
    private int connections;

    public Task InitializeAsync()
    {
        listener.Start();
        acceptLoop = Task.Run(async () =>
        {
            while (!stop.IsCancellationRequested)
            {
                try
                {
                    var client = await listener.AcceptTcpClientAsync(stop.Token);
                    lock (accepted)
                    {
                        accepted.Add(client);
                    }

                    Interlocked.Increment(ref connections);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
            }
        });
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await stop.CancelAsync();
        listener.Stop();
        if (acceptLoop is not null)
        {
            await acceptLoop;
        }

        lock (accepted)
        {
            accepted.ForEach(c => c.Dispose());
        }
    }

    public void Dispose()
    {
        stop.Dispose();
        listener.Dispose();
    }

    [Fact]
    public async Task ProbeTimesOutAfterOneSecondCachesForTwoSecondsAndRunsOnlyOnceAtATime()
    {
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        await using var dataSource = ZaghlolDbContextOptions.CreateDataSource(
            $"Host=127.0.0.1;Port={port};Database=none;Username=none;Password=none;Pooling=false;Timeout=30",
            DatabaseRole.App);
        using var readiness = new PostgresDatabaseReadiness(dataSource, clock, NullLogger<PostgresDatabaseReadiness>.Instance);

        var first = Stopwatch.StartNew();
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
        first.Stop();
        Assert.InRange(first.Elapsed, TimeSpan.FromMilliseconds(800), TimeSpan.FromSeconds(5));
        Assert.Equal(1, Volatile.Read(ref connections));

        // Within the cache window: answered from cache, no new connection.
        clock.Advance(TimeSpan.FromSeconds(1.9));
        var cached = Stopwatch.StartNew();
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
        Assert.True(cached.Elapsed < TimeSpan.FromMilliseconds(500), $"cached answer took {cached.Elapsed}");
        Assert.Equal(1, Volatile.Read(ref connections));

        // After the window: one probe for many concurrent callers.
        clock.Advance(TimeSpan.FromSeconds(0.2));
        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => readiness.IsReadyAsync(CancellationToken.None).AsTask()));
        Assert.All(results, Assert.False);
        Assert.Equal(2, Volatile.Read(ref connections));
    }

    private sealed class ManualClock(DateTimeOffset start) : TimeProvider
    {
        private long ticks = start.UtcTicks;

        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref ticks), TimeSpan.Zero);

        public void Advance(TimeSpan by) => Interlocked.Add(ref ticks, by.Ticks);
    }
}
