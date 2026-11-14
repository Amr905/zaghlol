using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Api.Dev;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.Dev;

[Collection(ApiHostGroup.Name)]
public sealed class DevFakeStoresTests
{
    private static IConfiguration Config(string? on) =>
        new ConfigurationBuilder().AddInMemoryCollection(on is null ? [] : new Dictionary<string, string?> { [DevFakeStores.ConfigKey] = on }).Build();

    internal sealed class EnvProduction : Env
    {
        public EnvProduction() : base("Production") { }
    }

    internal class Env(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Testing")]
    public void TheFlagIsRefusedOutsideDevelopment(string environment)
    {
        var services = new ServiceCollection();
        Assert.Throws<InvalidOperationException>(() => services.AddZaghlolDevFakeStores(Config("true"), new Env(environment)));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("false")]
    [InlineData("")]
    public void WithoutTheFlagNothingIsRegisteredInAnyEnvironment(string? flag)
    {
        var services = new ServiceCollection();
        services.AddZaghlolDevFakeStores(Config(flag), new Env("Production"));
        Assert.Empty(services);
    }

    [Fact]
    public void TheFlagInDevelopmentReplacesThePlayApi()
    {
        var services = new ServiceCollection();
        services.AddSingleton<IPlayDeveloperApi, DevFakePlayApi>();
        services.AddZaghlolDevFakeStores(Config("true"), new Env("Development"));
        using var provider = services.BuildServiceProvider();
        Assert.IsType<DevFakePlayApi>(provider.GetRequiredService<IPlayDeveloperApi>());
        Assert.Single(services, d => d.ServiceType == typeof(IPlayDeveloperApi));
    }

    [Fact]
    public void AppKeysListsThePublicJwksOnly()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Signing:Keys:0:Kid"] = "s0000d",
            ["Signing:Keys:0:PublicJwk:X"] = "xx",
            ["Signing:Keys:0:PublicJwk:Y"] = "yy",
            ["Signing:Keys:0:KeyRef"] = "local:s0000d",
            ["Signing:Keys:1:Kid"] = "e0000d",
            ["Signing:Keys:1:PublicJwk:X"] = "x2",
            ["Signing:Keys:1:PublicJwk:Y"] = "y2",
        }).Build();
        Assert.Equal("s0000d:xx:yy,e0000d:x2:y2", DevFakeStores.AppKeys(configuration));
    }

    [Fact]
    public async Task OnlyARegisteredTokenReadsAsAnActiveBoundPurchase()
    {
        var play = new DevFakePlayApi();
        var now = DateTimeOffset.Parse("2026-11-14T10:00:00Z", System.Globalization.CultureInfo.InvariantCulture);
        play.Register("devfake.abc", "zaghlol_gold_yearly", PlayProductKind.Subscription, "bind-1", now);

        var subscription = await play.GetSubscriptionAsync(new Sensitive<string>("devfake.abc"), StoreLane.Verify, CancellationToken.None);
        Assert.Equal(PlaySubscriptionState.Active, subscription.State);
        Assert.Equal("bind-1", subscription.ObfuscatedExternalAccountId);
        Assert.Equal("zaghlol_gold_yearly", subscription.LineItems[0].ProductId);

        var unknown = await Assert.ThrowsAsync<PlayApiException>(() => play.GetSubscriptionAsync(new Sensitive<string>("real-play-token"), StoreLane.Verify, CancellationToken.None));
        Assert.True(unknown.IsFinalRejection);
        var wrongKind = await Assert.ThrowsAsync<PlayApiException>(() => play.GetProductAsync(new Sensitive<string>("devfake.abc"), StoreLane.Verify, CancellationToken.None));
        Assert.True(wrongKind.IsFinalRejection);
    }
}

[Collection(ApiHostGroup.Name)]
public sealed class DevKeyEnvFileTests
{
    [Fact]
    public void ParsesKeyValueLinesWithSectionSeparators()
    {
        var parsed = DevKeyEnvFile.Parse(["# comment", "", "Kms__Provider=Local", "Signing__Keys__0__PublicJwk__X=ab-_=", "junk"]);
        Assert.Equal("Local", parsed["Kms:Provider"]);
        Assert.Equal("ab-_=", parsed["Signing:Keys:0:PublicJwk:X"]);
        Assert.Equal(2, parsed.Count);
    }

    [Fact]
    public void IsRefusedOutsideDevelopment()
    {
        var configuration = new ConfigurationManager();
        configuration[DevKeyEnvFile.ConfigKey] = "/x/kms.env";
        Assert.Throws<InvalidOperationException>(() => DevKeyEnvFile.AddIfConfigured(configuration, new DevFakeStoresTests.EnvProduction()));
    }
}
