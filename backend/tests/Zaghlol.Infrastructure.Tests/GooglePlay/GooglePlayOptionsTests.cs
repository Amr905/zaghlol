using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>T-130 design note §1 step 2 and §7: <c>Purchases:Google</c> validation and the Production refusals.</summary>
public sealed class GooglePlayOptionsTests
{
    private const string SecretMarker = "SECRET-sa-json-7f1";

    [Fact]
    public void ACompleteProductionConfigurationIsAccepted()
    {
        var options = GooglePlayOptions.Read(Config(Production()), new Env("Production"));

        Assert.Equal("app.zaghlol", options.Catalog.PackageName);
        Assert.Equal(3, options.Catalog.Products.Count);
        Assert.Equal(new Uri("https://androidpublisher.googleapis.com/"), options.BaseUrl);
        Assert.Equal(PlayCredentialSource.ApplicationDefault, options.CredentialSource);
        Assert.Equal(PlayOrderLookupPath.Fallback, options.OrderLookup);
        Assert.Equal(PlayResilienceOptions.Default, options.Resilience);
    }

    [Theory]
    [InlineData("Purchases:Google:PackageName", null)]
    [InlineData("Purchases:Google:PackageName", "app.zaghlol.dev")]
    [InlineData("Purchases:Google:PackageName", "app.zaghlol.staging")]
    [InlineData("Purchases:Google:PackageName", "not a package")]
    [InlineData("Purchases:Google:BaseUrl", "https://play.example.test")]
    [InlineData("Purchases:Google:BaseUrl", "http://androidpublisher.googleapis.com")]
    [InlineData("Purchases:Google:CredentialSource", null)]
    [InlineData("Purchases:Google:CredentialSource", "None")]
    [InlineData("Purchases:Google:CredentialSource", "ServiceAccountJson")]
    [InlineData("Purchases:Google:OrderLookup", "both")]
    [InlineData("Purchases:Google:Products:zaghlol_gold_lifetime:Kind", null)]
    [InlineData("Purchases:Google:Products:zaghlol_gold_lifetime:Kind", "subscription")]
    [InlineData("Purchases:Google:Products:zaghlol_gold_yearly:Plan", "monthly")]
    [InlineData("Purchases:Google:Products:android.test.purchased:Kind", "onetime")]
    public void ProductionRefusesAnIncompleteOrTestConfiguration(string key, string? value)
    {
        var settings = Production();
        settings[key] = value;
        if (key.EndsWith(":Kind", StringComparison.Ordinal) && value is null)
        {
            settings.Remove(key.Replace(":Kind", ":Plan", StringComparison.Ordinal));
        }

        Assert.Throws<PlayConfigurationException>(() => GooglePlayOptions.Read(Config(settings), new Env("Production")));
    }

    [Fact]
    public void AnEmptyProductTableIsRefusedOutsideDevelopmentAndTesting()
    {
        var settings = Production().Where(p => !p.Key.Contains(":Products:", StringComparison.Ordinal)).ToDictionary(p => p.Key, p => p.Value);

        Assert.Throws<PlayConfigurationException>(() => GooglePlayOptions.Read(Config(settings), new Env("Production")));
        Assert.Throws<PlayConfigurationException>(() => GooglePlayOptions.Read(Config(settings), new Env("Staging")));
        Assert.Empty(GooglePlayOptions.Read(Config(settings), new Env("Testing")).Catalog.Products);
    }

    [Fact]
    public void TheServiceAccountJsonIsKeptSensitiveAndNeverEchoed()
    {
        var settings = Production();
        settings["Purchases:Google:CredentialSource"] = "ServiceAccountJson";
        settings["Purchases:Google:Credential"] = "{\"type\":\"service_account\",\"private_key\":\"" + SecretMarker + "\"}";
        settings["Purchases:Google:PackageName"] = "bad package " + SecretMarker;

        var error = Assert.Throws<PlayConfigurationException>(() => GooglePlayOptions.Read(Config(settings), new Env("Production")));
        Assert.DoesNotContain(SecretMarker, error.ToString(), StringComparison.Ordinal);

        settings["Purchases:Google:PackageName"] = "app.zaghlol";
        var options = GooglePlayOptions.Read(Config(settings), new Env("Production"));
        Assert.Equal(PlayCredentialSource.ServiceAccountJson, options.CredentialSource);
        Assert.Equal("***", options.CredentialJson.ToString());
    }

    [Fact]
    public void ResilienceOverridesApplyOnlyInDevelopmentAndTesting()
    {
        var settings = Production();
        settings["Purchases:Google:Resilience:RetryBaseDelayMs"] = "1";

        Assert.Equal(PlayResilienceOptions.Default, GooglePlayOptions.Read(Config(settings), new Env("Production")).Resilience);
        settings["Purchases:Google:BaseUrl"] = "http://127.0.0.1:9";
        Assert.Equal(TimeSpan.FromMilliseconds(1), GooglePlayOptions.Read(Config(settings), new Env("Testing")).Resilience.RetryBaseDelay);
    }

    [Fact]
    public async Task ProductionRefusesTheNullGrantMissingVerifiersAFakeClientAndNoCredential()
    {
        var env = new Env("Production");
        var play = new PlayVerification(new NoPlay(), new PlayProductCatalog("app.zaghlol", new Dictionary<string, PlayProductDefinition>()), null!, null!, TimeProvider.System);
        var appStore = new StubVerifier(PurchaseStore.AppStore);

        await Assert.ThrowsAsync<PurchasesConfigurationException>(() =>
            new PurchasesStartupCheck(new NullVerifyGrant(), [play, appStore], env, NullLogger<PurchasesStartupCheck>.Instance).StartAsync(CancellationToken.None));
        await Assert.ThrowsAsync<PurchasesConfigurationException>(() =>
            new PurchasesStartupCheck(new StubGrant(), [play], env, NullLogger<PurchasesStartupCheck>.Instance).StartAsync(CancellationToken.None));
        await new PurchasesStartupCheck(new StubGrant(), [play, appStore], env, NullLogger<PurchasesStartupCheck>.Instance).StartAsync(CancellationToken.None);

        // Outside Production the placeholder only logs a warning.
        await new PurchasesStartupCheck(new NullVerifyGrant(), [play], new Env("Testing"), NullLogger<PurchasesStartupCheck>.Instance).StartAsync(CancellationToken.None);

        // A fake Play client is refused in Production, and so is the None credential.
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(Config(Production()));
        services.AddSingleton<IHostEnvironment>(env);
        services.AddLogging();
        services.AddZaghlolGooglePlay();
        services.AddSingleton<IPlayDeveloperApi>(new NoPlay());
        await using (var provider = services.BuildServiceProvider())
        {
            var check = provider.GetServices<IHostedService>().Single(s => s.GetType().Name == "GooglePlayOptionsStartupCheck");
            await Assert.ThrowsAsync<PlayConfigurationException>(() => check.StartAsync(CancellationToken.None));
        }

        var real = new ServiceCollection();
        real.AddSingleton<IConfiguration>(Config(Production()));
        real.AddSingleton<IHostEnvironment>(env);
        real.AddLogging();
        real.AddZaghlolGooglePlay();
        await using (var provider = real.BuildServiceProvider())
        {
            var check = provider.GetServices<IHostedService>().Single(s => s.GetType().Name == "GooglePlayOptionsStartupCheck");
            await check.StartAsync(CancellationToken.None);
        }
    }

    private static Dictionary<string, string?> Production() => new(StringComparer.Ordinal)
    {
        ["Purchases:Google:PackageName"] = "app.zaghlol",
        ["Purchases:Google:CredentialSource"] = "ApplicationDefault",
        ["Purchases:Google:Products:zaghlol_gold_monthly:Kind"] = "subscription",
        ["Purchases:Google:Products:zaghlol_gold_monthly:Plan"] = "monthly",
        ["Purchases:Google:Products:zaghlol_gold_yearly:Kind"] = "subscription",
        ["Purchases:Google:Products:zaghlol_gold_yearly:Plan"] = "yearly",
        ["Purchases:Google:Products:zaghlol_gold_lifetime:Kind"] = "onetime",
        ["Purchases:Google:Products:zaghlol_gold_lifetime:Plan"] = "lifetime",
    };

    private static IConfiguration Config(Dictionary<string, string?> settings) => new ConfigurationBuilder().AddInMemoryCollection(settings).Build();

    private sealed class Env(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    private sealed class StubGrant : IVerifyGrant
    {
        public Task<VerifyGrantResult> ComposeAsync(StoreVerificationResult verification, VerifyContext context, CancellationToken cancellationToken) =>
            Task.FromResult(VerifyGrantResult.None);
    }

    private sealed class StubVerifier(PurchaseStore store) : IStoreVerification
    {
        public PurchaseStore Store => store;

        public Task<StoreVerificationResult> VerifyAsync(StorePurchaseRef purchase, InstallId caller, BindingCheck binding, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private sealed class NoPlay : IPlayDeveloperApi
    {
        public Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<PlayProduct> GetProductAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task AcknowledgeProductAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();
    }
}

/// <summary>T-130 design note §2: the shared budget and its restore lane.</summary>
public sealed class StoreCallBudgetTests
{
    [Fact]
    public void RestoreIsDeniedFirstAndNeverSpendsTheReserve()
    {
        using var budget = new StoreCallBudget(new PlayBudgetOptions(10, 1, TimeSpan.FromHours(1)));

        // Restore may take at most 30 % (3 of 10), and only while more than the 30 % reserve is left.
        Assert.Equal(3, Enumerable.Range(0, 10).Count(_ => budget.TryAcquire(StoreLane.Restore)));

        // Verify and ack spend the rest, down to zero.
        Assert.Equal(7, Enumerable.Range(0, 10).Count(_ => budget.TryAcquire(StoreLane.Verify)));
        Assert.False(budget.TryAcquire(StoreLane.Ack));
    }

    [Fact]
    public void RestoreIsRefusedWhileOnlyTheReserveIsLeft()
    {
        using var budget = new StoreCallBudget(new PlayBudgetOptions(10, 1, TimeSpan.FromHours(1)));
        Assert.Equal(7, Enumerable.Range(0, 7).Count(_ => budget.TryAcquire(StoreLane.Verify)));

        Assert.False(budget.TryAcquire(StoreLane.Restore));
        Assert.True(budget.TryAcquire(StoreLane.Ack));
        Assert.True(budget.TryAcquire(StoreLane.Support));
        Assert.True(budget.TryAcquire(StoreLane.Notification));
    }
}
