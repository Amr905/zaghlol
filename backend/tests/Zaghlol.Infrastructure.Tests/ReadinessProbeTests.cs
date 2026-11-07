using System.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// The readiness probe against a "black hole" server that accepts TCP connections and never answers: proves the 1 s
/// timeout, the 2 s cache and that concurrent callers share one probe (each probe is one accepted connection).
/// </summary>
public sealed class ReadinessProbeTests : IDisposable
{
    private readonly BlackHoleServer server = new();

    public void Dispose() => server.Dispose();

    [Fact]
    public async Task ProbeTimesOutAfterOneSecondCachesForTwoSecondsAndRunsOnlyOnceAtATime()
    {
        var clock = new ManualClock(DateTimeOffset.UtcNow);

        // Pooling off so each probe is a new TCP connection the server can count.
        await using var dataSource = ZaghlolDbContextOptions.CreateDataSource(
            $"Host=127.0.0.1;Port={server.Port};Database=none;Username=none;Password=none;Pooling=false;Timeout=30",
            DatabaseRole.App);
        using var readiness = new PostgresDatabaseReadiness(dataSource, clock, NullLogger<PostgresDatabaseReadiness>.Instance);

        var first = Stopwatch.StartNew();
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
        first.Stop();
        Assert.InRange(first.Elapsed, TimeSpan.FromMilliseconds(800), TimeSpan.FromSeconds(5));
        Assert.Equal(1, server.Connections);

        // Within the cache window: answered from cache, no new connection.
        clock.Advance(TimeSpan.FromSeconds(1.9));
        var cached = Stopwatch.StartNew();
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
        Assert.True(cached.Elapsed < TimeSpan.FromMilliseconds(500), $"cached answer took {cached.Elapsed}");
        Assert.Equal(1, server.Connections);

        // After the window: one probe for many concurrent callers.
        clock.Advance(TimeSpan.FromSeconds(0.2));
        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => readiness.IsReadyAsync(CancellationToken.None).AsTask()));
        Assert.All(results, Assert.False);
        Assert.Equal(2, server.Connections);
    }

    [Fact]
    public void TheProductionProbeSourceHasAPoolOfOne()
    {
        using var source = PostgresDatabaseReadiness.CreateProbeSource("Host=db.invalid;Database=zaghlol;Username=zaghlol_api;Max Pool Size=100");
        var settings = new Npgsql.NpgsqlConnectionStringBuilder(source.ConnectionString);

        Assert.Equal(1, settings.MaxPoolSize);
        Assert.Equal("zaghlol-api-readiness", settings.ApplicationName);
    }

    private sealed class ManualClock(DateTimeOffset start) : TimeProvider
    {
        private long ticks = start.UtcTicks;

        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref ticks), TimeSpan.Zero);

        public void Advance(TimeSpan by) => Interlocked.Add(ref ticks, by.Ticks);
    }
}
