using Zaghlol.Application.Prices;

namespace Zaghlol.Application.Tests.Prices;

public class PriceFetchJobTests
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);

    private readonly TestClock clock = new(T0);
    private readonly MemoryPriceStore store = new();
    private readonly RecordingMetrics metrics = new();

    private PriceFetchJob Job(params IPriceProvider[] providers) => new(providers, store, metrics, clock);

    private static StubProvider Good(string name = "fake", decimal gold24 = 4820m) =>
        new(name, () => new ProviderSnapshot([new GoldQuote("XAU24_G", "EGP", gold24)], [new FxQuote("EGP", 48.95m)], T0));

    private static StubProvider Failing(string name) => new(name, () => throw new HttpRequestException("boom"));

    [Fact]
    public async Task AGoodFetchWritesTheDerivedSetAndReportsOk()
    {
        var written = await Job(Good()).RunOnceAsync(CancellationToken.None);

        Assert.Equal(7, written); // 3 karats x EGP/USD = 6 gold + 1 FX
        Assert.Equal(6, store.Rows.Count);
        Assert.Equal([("fake", "ok")], metrics.Fetches);
        Assert.Equal(TimeSpan.Zero, metrics.Ages["XAU21_G"]);
    }

    [Fact]
    public async Task OneFailingProviderIsIsolatedAndTheOthersStillWrite()
    {
        var written = await Job(Failing("local_gold"), Good("spot_gold")).RunOnceAsync(CancellationToken.None);

        Assert.Equal(7, written);
        Assert.Equal([("local_gold", "failed"), ("spot_gold", "ok")], metrics.Fetches);
        Assert.Equal("spot_gold", store.Rows[("XAU24_G", "EGP")].Source);
    }

    [Fact]
    public async Task AFullOutageLeavesTheCacheAloneAndTheAgeGrows()
    {
        await Job(Good()).RunOnceAsync(CancellationToken.None);
        var applies = store.Applies;

        clock.Now = T0.AddHours(25);
        var written = await Job(Failing("local_gold"), Failing("fx")).RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, written);
        Assert.Equal(applies, store.Applies);
        Assert.Equal(4820m, store.Rows[("XAU24_G", "EGP")].Price);
        Assert.Equal(TimeSpan.FromHours(25), metrics.Ages["XAU24_G"]);
        var block = PriceReadService.Build(store.Rows.Values.ToList(), store.Fx.Values.ToList(), clock.Now);
        Assert.True(block!.Stale);
    }

    [Fact]
    public async Task AnEmptySnapshotIsReportedEmptyAndWritesNothing()
    {
        var empty = new StubProvider("fx", () => new ProviderSnapshot([], [], T0));

        var written = await Job(empty).RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, written);
        Assert.Equal([("fx", "empty")], metrics.Fetches);
        Assert.Equal(0, store.Applies);
    }

    [Fact]
    public async Task NoProvidersConfiguredIsReportedAndWritesNothing()
    {
        Assert.Equal(0, await Job().RunOnceAsync(CancellationToken.None));
        Assert.Equal([("none", "empty")], metrics.Fetches);
    }

    [Fact]
    public async Task InvalidQuotesFromAProviderAreDroppedNotStored()
    {
        var junk = new StubProvider("fake", () => new ProviderSnapshot([new GoldQuote("XAU24_G", "EGP", -5m), new GoldQuote("BTC", "EGP", 1m)], [], T0));

        Assert.Equal(0, await Job(junk).RunOnceAsync(CancellationToken.None));
        Assert.Empty(store.Rows);
    }

    [Fact]
    public async Task CancellationIsNotSwallowed()
    {
        using var cts = new CancellationTokenSource();
        var cancelling = new StubProvider("fake", () =>
        {
            cts.Cancel();
            throw new OperationCanceledException(cts.Token);
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Job(cancelling).RunOnceAsync(cts.Token));
    }
}
