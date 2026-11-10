using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Prices;

namespace Zaghlol.Workers.Tests;

public class PriceFetcherServiceTests
{
    private sealed class CountingProvider(Func<int, ProviderSnapshot> fetch) : IPriceProvider
    {
        private int calls;

        public string Name => "fake";

        public int Calls => Volatile.Read(ref calls);

        public Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken) =>
            Task.FromResult(fetch(Interlocked.Increment(ref calls)));
    }

    private sealed class NullStore : IPriceFeedStore
    {
        public int Applied;

        public Task ApplyFeedAsync(NormalizedPrices prices, DateTimeOffset now, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Applied);
            return Task.CompletedTask;
        }

        public Task<IReadOnlyDictionary<string, DateTimeOffset>> FeedTimesAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyDictionary<string, DateTimeOffset>>(new Dictionary<string, DateTimeOffset>());
    }

    private sealed class NullMetrics : IPriceMetrics
    {
        public void Fetched(string provider, string outcome)
        {
        }

        public void SetAge(string symbol, TimeSpan age)
        {
        }
    }

    private static IConfiguration Config(string? minutes) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Prices:IntervalMinutes"] = minutes })
            .Build();

    [Theory]
    [InlineData(null, 60)]
    [InlineData("", 60)]
    [InlineData("abc", 60)]
    [InlineData("15", 15)]
    [InlineData("0", 1)]
    [InlineData("-5", 1)]
    public void TheIntervalDefaultsToAnHourAndIsAtLeastOneMinute(string? configured, int expectedMinutes)
    {
        Assert.Equal(TimeSpan.FromMinutes(expectedMinutes), PriceFetcherService.IntervalFrom(Config(configured)));
    }

    [Fact]
    public async Task ItRunsTheJobAtStartAndSurvivesAFailingRun()
    {
        var provider = new CountingProvider(_ => throw new InvalidOperationException("provider bug"));
        var store = new NullStore();
        var job = new PriceFetchJob([provider], store, new NullMetrics(), TimeProvider.System);
        using var service = new PriceFetcherService(job, TimeProvider.System, Config("60"), NullLogger<PriceFetcherService>.Instance);

        await service.StartAsync(CancellationToken.None);
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (provider.Calls == 0 && DateTime.UtcNow < deadline)
        {
            await Task.Delay(20);
        }

        await service.StopAsync(CancellationToken.None);

        Assert.Equal(1, provider.Calls);
        Assert.Equal(0, store.Applied);
        Assert.True(service.ExecuteTask is null || service.ExecuteTask.IsCompletedSuccessfully);
    }

    [Fact]
    public async Task ItWritesTheFeedOnTheFirstRun()
    {
        var snapshot = new ProviderSnapshot([new GoldQuote("XAU24_G", "EGP", 4820m)], [], DateTimeOffset.UtcNow);
        var provider = new CountingProvider(_ => snapshot);
        var store = new NullStore();
        var job = new PriceFetchJob([provider], store, new NullMetrics(), TimeProvider.System);
        using var service = new PriceFetcherService(job, TimeProvider.System, Config("60"), NullLogger<PriceFetcherService>.Instance);

        await service.StartAsync(CancellationToken.None);
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (Volatile.Read(ref store.Applied) == 0 && DateTime.UtcNow < deadline)
        {
            await Task.Delay(20);
        }

        await service.StopAsync(CancellationToken.None);

        Assert.Equal(1, store.Applied);
    }
}
