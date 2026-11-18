using System.Net;
using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Prices;
using Zaghlol.Infrastructure.Prices;

namespace Zaghlol.Infrastructure.Tests.Prices;

/// <summary>Contract tests for the two HTTP adapters against recorded-shape fake responses. No live calls.</summary>
public class PriceAdapterTests
{
    // Shapes follow the providers' public docs; numbers are synthetic (T-127 doc, "verification status").
    private const string GoldApiEgp = """
        {"timestamp":1763470000,"metal":"XAU","currency":"EGP","price":202500.50,"price_gram_24k":6510.25,"price_gram_22k":5967.73,"price_gram_21k":5696.47,"price_gram_18k":4882.69}
        """;

    private const string GoldApiUsd = """
        {"timestamp":1763470000,"metal":"XAU","currency":"USD","price":4140.00,"price_gram_24k":133.10,"price_gram_21k":116.46,"price_gram_18k":99.83}
        """;

    private const string MetalpriceOk = """
        {"success":true,"base":"USD","timestamp":1763470000,"rates":{"EGP":48.90,"SAR":3.75,"EUR":0.8600,"GBP":0.7600,"KWD":0.3070,"XAU":0.000241546,"USDXAU":4140.00}}
        """;

    private sealed class StepClock(DateTimeOffset start) : TimeProvider
    {
        private DateTimeOffset now = start;

        public override DateTimeOffset GetUtcNow() => now;

        public void Advance(TimeSpan by) => now += by;
    }

    private sealed class StubHandler(Func<HttpRequestMessage, (HttpStatusCode, string)> reply) : HttpMessageHandler
    {
        public List<HttpRequestMessage> Requests { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request);
            var (status, body) = reply(request);
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }
    }

    private static readonly StepClock Clock = new(DateTimeOffset.Parse("2026-11-18T12:00:00Z", System.Globalization.CultureInfo.InvariantCulture));

    private static HttpClient Client(StubHandler handler, string baseAddress) => new(handler) { BaseAddress = new Uri(baseAddress) };

    [Fact]
    public async Task GoldApiReadsKaratGramPricesAndDerivesUsdToEgpFromTheOuncePrices()
    {
        var handler = new StubHandler(r => (HttpStatusCode.OK, r.RequestUri!.AbsolutePath.EndsWith("/EGP", StringComparison.Ordinal) ? GoldApiEgp : GoldApiUsd));
        var provider = new GoldApiProvider(Client(handler, "https://www.goldapi.io/"), "KEY", PriceBounds.Default, Clock);

        var snapshot = await provider.FetchAsync(CancellationToken.None);

        Assert.Equal(6510.25m, snapshot.Gold.Single(g => g.Symbol == "XAU24_G" && g.Currency == "EGP").Price);
        Assert.Equal(4882.69m, snapshot.Gold.Single(g => g.Symbol == "XAU18_G" && g.Currency == "EGP").Price);
        Assert.Equal(116.46m, snapshot.Gold.Single(g => g.Symbol == "XAU21_G" && g.Currency == "USD").Price);
        Assert.Equal(decimal.Round(202500.50m / 4140.00m, 8), snapshot.Fx.Single(f => f.Quote == "EGP").Rate);
        Assert.All(handler.Requests, r => Assert.Equal("KEY", Assert.Single(r.Headers.GetValues("x-access-token"))));
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1763470000), snapshot.AsOf);
    }

    [Fact]
    public async Task GoldApiFallsBackToTheOunceDividedByGramsWhenAKaratFieldIsMissing()
    {
        const string noKarat = """{"timestamp":1763470000,"metal":"XAU","currency":"USD","price":4140.00}""";
        var handler = new StubHandler(r => (HttpStatusCode.OK, r.RequestUri!.AbsolutePath.EndsWith("/EGP", StringComparison.Ordinal) ? """{"timestamp":1763470000,"price":202446.00}""" : noKarat));
        var provider = new GoldApiProvider(Client(handler, "https://www.goldapi.io/"), "KEY", PriceBounds.Default, Clock);

        var snapshot = await provider.FetchAsync(CancellationToken.None);
        var normalized = PriceNormalizer.Normalize([(provider.Name, snapshot)]);

        Assert.Equal(133.10m, snapshot.Gold.Single(g => g.Currency == "USD").Price); // 4140 / 31.1034768 = 133.1
        Assert.Equal(116.46m, normalized.Gold.Single(g => g.Symbol == "XAU21_G" && g.Currency == "USD").Price); // 133.10 x 21 / 24 = 116.4625
    }

    [Fact]
    public async Task MetalpriceDerivesGramPricesFromTheOunceAndTheNormalizerFillsKarats()
    {
        var handler = new StubHandler(_ => (HttpStatusCode.OK, MetalpriceOk));
        var provider = new MetalpriceApiProvider(Client(handler, "https://api.metalpriceapi.com/"), "KEY", PriceBounds.Default, ["SAR", "KWD", "XXX1"], Clock);

        var snapshot = await provider.FetchAsync(CancellationToken.None);
        var normalized = PriceNormalizer.Normalize([(provider.Name, snapshot)]);

        // 4140 / 31.1034768 = 133.0964...; x 48.90 = 6508.2...
        Assert.Equal(133.10m, snapshot.Gold.Single(g => g.Currency == "USD").Price);
        Assert.Equal(decimal.Round(4140m / 31.1034768m * 48.90m, 2, MidpointRounding.AwayFromZero), snapshot.Gold.Single(g => g.Currency == "EGP").Price);
        var egp24 = snapshot.Gold.Single(g => g.Currency == "EGP").Price;
        Assert.Equal(decimal.Round(egp24 * 21m / 24m, 2, MidpointRounding.AwayFromZero), normalized.Gold.Single(g => g.Symbol == "XAU21_G" && g.Currency == "EGP").Price);
        Assert.Equal(decimal.Round(egp24 * 18m / 24m, 2, MidpointRounding.AwayFromZero), normalized.Gold.Single(g => g.Symbol == "XAU18_G" && g.Currency == "EGP").Price);
        Assert.Equal(48.90m, snapshot.Fx.Single(f => f.Quote == "EGP").Rate);
        Assert.Contains(snapshot.Fx, f => f.Quote == "KWD");
        Assert.DoesNotContain(snapshot.Fx, f => f.Quote == "XXX1");
        var query = Assert.Single(handler.Requests).RequestUri!.Query;
        Assert.Contains("api_key=KEY", query, StringComparison.Ordinal);
        Assert.Contains("base=USD", query, StringComparison.Ordinal);
    }

    [Fact]
    public async Task MetalpriceUsesTheInverseXauRateWhenUsdXauIsAbsent()
    {
        var body = """{"success":true,"timestamp":1763470000,"rates":{"EGP":48.90,"XAU":0.00025}}""";
        var provider = new MetalpriceApiProvider(Client(new StubHandler(_ => (HttpStatusCode.OK, body)), "https://api.metalpriceapi.com/"), "KEY", PriceBounds.Default, [], Clock);

        var snapshot = await provider.FetchAsync(CancellationToken.None);

        Assert.Equal(decimal.Round(4000m / 31.1034768m, 2, MidpointRounding.AwayFromZero), snapshot.Gold.Single(g => g.Currency == "USD").Price);
    }

    [Theory]
    [InlineData("""{"success":false,"error":{"code":101}}""")]
    [InlineData("""{"success":true,"rates":{"EGP":48.90,"USDXAU":0.5}}""")] // unit mix-up: below the USD/oz floor
    [InlineData("""{"success":true,"rates":{"EGP":0.5,"USDXAU":4140}}""")] // EGP rate below the floor
    [InlineData("""{"success":true,"rates":{"EGP":48.90}}""")] // no gold
    [InlineData("not json")]
    [InlineData("""{"success":true,"rates":{"EGP":-1,"USDXAU":4140}}""")]
    public async Task MetalpriceRefusesBadOrOutOfBoundsAnswers(string body)
    {
        var provider = new MetalpriceApiProvider(Client(new StubHandler(_ => (HttpStatusCode.OK, body)), "https://api.metalpriceapi.com/"), "KEY", PriceBounds.Default, [], Clock);

        await Assert.ThrowsAsync<PriceProviderException>(() => provider.FetchAsync(CancellationToken.None));
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    [InlineData(HttpStatusCode.InternalServerError)]
    public async Task GoldApiRefusesAnErrorStatusWithoutLeakingTheKey(HttpStatusCode status)
    {
        var provider = new GoldApiProvider(Client(new StubHandler(_ => (status, "{}")), "https://www.goldapi.io/"), "SECRETKEY", PriceBounds.Default, Clock);

        var ex = await Assert.ThrowsAsync<PriceProviderException>(() => provider.FetchAsync(CancellationToken.None));
        Assert.DoesNotContain("SECRETKEY", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GoldApiRefusesAnEgpPriceOutOfBoundsAndAMissingPrice()
    {
        var wild = new StubHandler(r => (HttpStatusCode.OK, r.RequestUri!.AbsolutePath.EndsWith("/EGP", StringComparison.Ordinal) ? """{"price":1000.00}""" : GoldApiUsd));
        await Assert.ThrowsAsync<PriceProviderException>(() => new GoldApiProvider(Client(wild, "https://www.goldapi.io/"), "K", PriceBounds.Default, Clock).FetchAsync(CancellationToken.None));
        var none = new StubHandler(_ => (HttpStatusCode.OK, """{"metal":"XAU"}"""));
        await Assert.ThrowsAsync<PriceProviderException>(() => new GoldApiProvider(Client(none, "https://www.goldapi.io/"), "K", PriceBounds.Default, Clock).FetchAsync(CancellationToken.None));
    }

    [Fact]
    public async Task GoldApiRefusesAKaratGramPriceThatDisagreesWithTheOuncePrice()
    {
        var bad = GoldApiUsd.Replace("\"price_gram_21k\":116.46", "\"price_gram_21k\":140.00", StringComparison.Ordinal);
        var handler = new StubHandler(r => (HttpStatusCode.OK, r.RequestUri!.AbsolutePath.EndsWith("/EGP", StringComparison.Ordinal) ? GoldApiEgp : bad));
        var provider = new GoldApiProvider(Client(handler, "https://www.goldapi.io/"), "K", PriceBounds.Default, Clock);

        var ex = await Assert.ThrowsAsync<PriceProviderException>(() => provider.FetchAsync(CancellationToken.None));
        Assert.Contains("price_gram_21k", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task TheTransportErrorBecomesAFixedMessageWithoutTheUrl()
    {
        var provider = new MetalpriceApiProvider(
            new HttpClient(new ThrowingHandler()) { BaseAddress = new Uri("https://api.metalpriceapi.com/") }, "SECRETKEY", PriceBounds.Default, [], Clock);

        var ex = await Assert.ThrowsAsync<PriceProviderException>(() => provider.FetchAsync(CancellationToken.None));
        Assert.DoesNotContain("SECRETKEY", ex.ToString(), StringComparison.Ordinal);
    }

    private sealed class ThrowingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new HttpRequestException("failed " + request.RequestUri);
    }

    [Fact]
    public async Task TheCacheCallsTheProviderOncePerTtlAndRetriesAfterAFailure()
    {
        var clock = new StepClock(DateTimeOffset.Parse("2026-11-18T12:00:00Z", System.Globalization.CultureInfo.InvariantCulture));
        var inner = new CountingProvider();
        var cache = new CachingPriceProvider(inner, TimeSpan.FromMinutes(59), clock);

        await cache.FetchAsync(CancellationToken.None);
        clock.Advance(TimeSpan.FromMinutes(30));
        await cache.FetchAsync(CancellationToken.None);
        Assert.Equal(1, inner.Calls);

        clock.Advance(TimeSpan.FromMinutes(30));
        inner.Fail = true;
        await Assert.ThrowsAsync<PriceProviderException>(() => cache.FetchAsync(CancellationToken.None));
        inner.Fail = false;
        await cache.FetchAsync(CancellationToken.None);
        Assert.Equal(3, inner.Calls);
    }

    private sealed class CountingProvider : IPriceProvider
    {
        public int Calls { get; private set; }

        public bool Fail { get; set; }

        public string Name => "fake";

        public Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken)
        {
            Calls++;
            return Fail
                ? throw new PriceProviderException("x")
                : Task.FromResult(new ProviderSnapshot([], [], DateTimeOffset.UnixEpoch));
        }
    }

    [Fact]
    public void TheFactoryBuildsTheAdaptersFromTheSecretKeyAndNeedsTheKey()
    {
        var env = new PriceProviderTests.EnvFor("Production");
        var clients = new FakeFactory();
        var cfg = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Prices:Providers"] = "metalpriceapi, goldapi",
            ["Prices:MetalpriceApi:ApiKey"] = "k1",
            ["Prices:GoldApi:ApiKey"] = "k2",
        }).Build();

        var providers = PriceProviderFactory.Create(cfg, env, TimeProvider.System, clients);

        Assert.Equal(["metalpriceapi", "goldapi"], providers.Select(p => p.Name));

        var noKey = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Prices:Providers"] = "goldapi" }).Build();
        Assert.Throws<InvalidOperationException>(() => PriceProviderFactory.Create(noKey, env, TimeProvider.System, clients));
        Assert.Throws<InvalidOperationException>(() => PriceProviderFactory.Create(cfg, env, TimeProvider.System));
    }

    private sealed class FakeFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(new StubHandler(_ => (HttpStatusCode.OK, "{}"))) { BaseAddress = new Uri("https://example.invalid/") };
    }
}
