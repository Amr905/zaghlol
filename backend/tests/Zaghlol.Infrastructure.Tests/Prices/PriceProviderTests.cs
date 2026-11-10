using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Prices;
using Zaghlol.Infrastructure.Prices;

namespace Zaghlol.Infrastructure.Tests.Prices;

public class PriceProviderTests
{
    private sealed class Env(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "test";

        public string ContentRootPath { get; set; } = "/";

        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private static IConfiguration Config(string? providers, params (string Key, string Value)[] more) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(
                new Dictionary<string, string?> { ["Prices:Providers"] = providers }
                    .Concat(more.Select(m => new KeyValuePair<string, string?>(m.Key, m.Value))))
            .Build();

    [Fact]
    public void NoProvidersConfiguredIsAnEmptyList()
    {
        Assert.Empty(PriceProviderFactory.Create(Config(null), new Env("Production"), TimeProvider.System));
        Assert.Empty(PriceProviderFactory.Create(Config(" "), new Env("Production"), TimeProvider.System));
    }

    [Fact]
    public void FakeIsAllowedOutsideProduction()
    {
        var providers = PriceProviderFactory.Create(Config("fake"), new Env("Staging"), TimeProvider.System);

        Assert.Equal("fake", Assert.Single(providers).Name);
    }

    [Fact]
    public void FakeIsRefusedInProduction()
    {
        Assert.Throws<InvalidOperationException>(() => PriceProviderFactory.Create(Config("fake"), new Env("Production"), TimeProvider.System));
    }

    [Theory]
    [InlineData("local_gold")]
    [InlineData("fx")]
    [InlineData("spot_gold")]
    [InlineData("whatever")]
    public void ANameWithoutAnAdapterStopsStartup(string name)
    {
        Assert.Throws<InvalidOperationException>(() => PriceProviderFactory.Create(Config(name), new Env("Development"), TimeProvider.System));
    }

    [Fact]
    public async Task TheFakeProviderReturnsGold24AndFxFromConfigurationAndTheNormalizerFillsTheRest()
    {
        var provider = PriceProviderFactory.Create(
            Config("fake", ("Prices:Fake:Gold24Egp", "4895"), ("Prices:Fake:UsdEgp", "48.95")),
            new Env("Development"),
            TimeProvider.System).Single();

        var snapshot = await provider.FetchAsync(CancellationToken.None);
        var normalized = PriceNormalizer.Normalize([(provider.Name, snapshot)]);

        Assert.Equal(4895m, Assert.Single(snapshot.Gold).Price);
        Assert.Equal(6, normalized.Gold.Count);
        Assert.Equal(100.00m, normalized.Gold.Single(g => g.Symbol == "XAU24_G" && g.Currency == "USD").Price);
        Assert.Contains(normalized.Fx, f => f.Quote == "KWD");
    }
}
