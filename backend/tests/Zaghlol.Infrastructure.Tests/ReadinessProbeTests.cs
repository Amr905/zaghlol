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

    [Theory]
    [InlineData("Host=db.invalid;Database=zaghlol;Username=zaghlol_api")]
    [InlineData("Host=db.invalid;Database=zaghlol;Username=zaghlol_api;Maximum Pool Size=100;Minimum Pool Size=10")]
    public void TheProductionProbeHasAPoolOfOneWhateverTheAppStringSays(string app)
    {
        var settings = new Npgsql.NpgsqlConnectionStringBuilder(PostgresDatabaseReadiness.ProbeConnectionString(app));

        Assert.Equal(1, settings.MaxPoolSize);
        Assert.Equal(0, settings.MinPoolSize);
        Assert.Equal("zaghlol-api-readiness", settings.ApplicationName);
        Assert.Equal("zaghlol_api", settings.Username);
        Assert.Equal(PostgresDatabaseReadiness.ConnectTimeoutSeconds, settings.Timeout);
        using var source = PostgresDatabaseReadiness.CreateProbeSource(app);
    }

    [Fact]
    public async Task AnAbandonedProbeFreesThePoolOfOneWithinTheConnectTimeout()
    {
        // FU-022: the production probe pool (one connection) against a server that never answers. The first probe gives
        // up after 1 s but its open keeps the only slot until Npgsql's connect timeout. With the forced 2 s timeout the
        // slot is free again soon after, so the next probe makes a new attempt instead of queueing for 15 s.
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        await using var probeSource = PostgresDatabaseReadiness.CreateProbeSource(
            $"Host=127.0.0.1;Port={server.Port};Database=none;Username=none;Password=none;Timeout=30");
        using var readiness = new PostgresDatabaseReadiness(probeSource, clock, NullLogger<PostgresDatabaseReadiness>.Instance);

        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
        Assert.Equal(1, server.Connections);

        await Task.Delay(TimeSpan.FromSeconds(PostgresDatabaseReadiness.ConnectTimeoutSeconds + 1));
        clock.Advance(TimeSpan.FromSeconds(3));
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));

        var deadline = Stopwatch.StartNew();
        while (server.Connections < 2 && deadline.Elapsed < TimeSpan.FromSeconds(2))
        {
            await Task.Delay(50);
        }

        Assert.Equal(2, server.Connections);
    }

    [Fact]
    public async Task ACallerThatGivesUpWhileWaitingDoesNotDisturbTheProbe()
    {
        // FU-026: a waiter's cancellation ends only its own wait; the probe in flight finishes and is shared.
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        await using var dataSource = ZaghlolDbContextOptions.CreateDataSource(
            $"Host=127.0.0.1;Port={server.Port};Database=none;Username=none;Password=none;Pooling=false;Timeout=30",
            DatabaseRole.App);
        using var readiness = new PostgresDatabaseReadiness(dataSource, clock, NullLogger<PostgresDatabaseReadiness>.Instance);

        var first = readiness.IsReadyAsync(CancellationToken.None).AsTask();
        while (server.Connections < 1)
        {
            await Task.Delay(10);
        }

        using var impatient = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => readiness.IsReadyAsync(impatient.Token).AsTask());

        Assert.False(await first);
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
        Assert.Equal(1, server.Connections);
    }

    [Fact]
    public async Task TheProbeIgnoresTheCallersToken()
    {
        // FU-026: one client hanging up mid-probe must not record "not ready" (or a cancellation) for everyone.
        var clock = new ManualClock(DateTimeOffset.UtcNow);
        await using var dataSource = ZaghlolDbContextOptions.CreateDataSource(
            $"Host=127.0.0.1;Port={server.Port};Database=none;Username=none;Password=none;Pooling=false;Timeout=30",
            DatabaseRole.App);
        using var readiness = new PostgresDatabaseReadiness(dataSource, clock, NullLogger<PostgresDatabaseReadiness>.Instance);
        using var hangUp = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        var elapsed = Stopwatch.StartNew();
        Assert.False(await readiness.IsReadyAsync(hangUp.Token));

        Assert.True(elapsed.Elapsed >= TimeSpan.FromMilliseconds(800), $"the probe was cut short after {elapsed.Elapsed}");
    }

    private sealed class ManualClock(DateTimeOffset start) : TimeProvider
    {
        private long ticks = start.UtcTicks;

        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref ticks), TimeSpan.Zero);

        public void Advance(TimeSpan by) => Interlocked.Add(ref ticks, by.Ticks);
    }
}
