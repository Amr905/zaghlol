using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>
/// T-130 AC 9 / PO question 5: the real client against the real Google Play Developer API with a license-tester purchase. It runs
/// only when <c>ZAGHLOL_LIVE_PLAY_PACKAGE</c>, <c>ZAGHLOL_LIVE_PLAY_PRODUCT</c> and <c>ZAGHLOL_LIVE_PLAY_TOKEN</c> are set (credential
/// from Application Default Credentials, or <c>ZAGHLOL_LIVE_PLAY_CREDENTIAL</c> holding the service-account JSON); otherwise it
/// returns at once. With <c>ZAGHLOL_LIVE_PLAY_ORDER_ID</c> it also calls <c>orders.get</c>: the AC 5 availability evidence (record
/// the outcome in the T-130 task file). No value is printed.
/// </summary>
[Trait("live", "play")]
public sealed class PlayLiveSmokeTests
{
    [Fact]
    public async Task ALicenseTesterPurchaseReadsFromTheRealPlayApiWhenConfigured()
    {
        var package = Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_PLAY_PACKAGE");
        var product = Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_PLAY_PRODUCT");
        var token = Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_PLAY_TOKEN");
        if (string.IsNullOrEmpty(package) || string.IsNullOrEmpty(product) || string.IsNullOrEmpty(token))
        {
            return;
        }

        var credential = Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_PLAY_CREDENTIAL");
        var lifetime = product.Contains("lifetime", StringComparison.Ordinal);
        var settings = new Dictionary<string, string?>
        {
            ["Purchases:Google:PackageName"] = package,
            ["Purchases:Google:CredentialSource"] = string.IsNullOrEmpty(credential) ? "ApplicationDefault" : "ServiceAccountJson",
            ["Purchases:Google:Credential"] = credential,
            ["Purchases:Google:Products:" + product + ":Kind"] = lifetime ? "onetime" : "subscription",
            ["Purchases:Google:Products:" + product + ":Plan"] = lifetime ? "lifetime" : "yearly",
            // The table needs exactly one product per plan; the two placeholders are never called.
            ["Purchases:Google:Products:zaghlol_live_a:Kind"] = "subscription",
            ["Purchases:Google:Products:zaghlol_live_a:Plan"] = "monthly",
            ["Purchases:Google:Products:zaghlol_live_b:Kind"] = lifetime ? "subscription" : "onetime",
            ["Purchases:Google:Products:zaghlol_live_b:Plan"] = lifetime ? "yearly" : "lifetime",
        };
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        services.AddSingleton<IHostEnvironment>(new StagingEnvironment());
        services.AddLogging();
        services.AddZaghlolGooglePlay();
        await using var provider = services.BuildServiceProvider();
        var play = provider.GetRequiredService<IPlayDeveloperApi>();

        if (lifetime)
        {
            var read = await play.GetProductAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);
            Assert.Contains(product, read.ProductIds);
            Assert.NotEqual(PlayProductState.Unknown, read.State);
            Assert.True(read.TestPurchase);
        }
        else
        {
            var read = await play.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);
            Assert.Contains(read.LineItems, i => i.ProductId == product);
            Assert.NotEqual(PlaySubscriptionState.Unknown, read.State);
            Assert.True(read.TestPurchase);
        }

        if (Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_PLAY_ORDER_ID") is { Length: > 0 } orderId)
        {
            // AC 5: orders.get must be available to the developer account and return purchaseToken.
            var order = await play.GetOrderAsync(new Sensitive<string>(orderId), StoreLane.Support, CancellationToken.None);
            Assert.NotNull(order.PurchaseToken);
            Assert.NotEqual(PlayOrderState.Unknown, order.State);
        }
    }

    private sealed class StagingEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Staging";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}
