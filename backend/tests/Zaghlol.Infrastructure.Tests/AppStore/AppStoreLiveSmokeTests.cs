using System.Text.Json.Nodes;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>
/// A <see cref="FactAttribute"/> that reports <b>skipped</b> (never passed) unless the live App Store variables are set (T-130
/// finding 5: an unconfigured live test must not look green).
/// </summary>
public sealed class LiveAppStoreFactAttribute : FactAttribute
{
    public LiveAppStoreFactAttribute()
    {
        if (!AppStoreLiveSmokeTests.Configured)
        {
            Skip = "Live App Store smoke test not configured: set ZAGHLOL_LIVE_APPLE_BUNDLE_ID, _ISSUER_ID, _KEY_ID, _PRIVATE_KEY and _TRANSACTION_ID (PO question 6).";
        }
    }
}

/// <summary>Reports <b>skipped</b> until the PO's recorded sandbox transaction is checked in (T-131 §10).</summary>
public sealed class RecordedAppleVectorFactAttribute : FactAttribute
{
    public RecordedAppleVectorFactAttribute()
    {
        if (!File.Exists(AppStoreLiveSmokeTests.RecordedVectorPath))
        {
            Skip = "No recorded sandbox JWS yet (AppStore/fixtures/recorded-sandbox-transaction.json; PO question 6).";
        }
    }
}

/// <summary>
/// The real client and verifier against Apple. <see cref="ASandboxTransactionReadsFromTheRealAppStoreServerApiWhenConfigured"/> reads a
/// sandbox transaction (<c>ZAGHLOL_LIVE_APPLE_TRANSACTION_ID</c>) with the In-App Purchase key from <c>ZAGHLOL_LIVE_APPLE_*</c>, and
/// checks Apple's JWS against the real pinned root; with <c>ZAGHLOL_LIVE_APPLE_ORDER_ID</c> (a team member's production order)
/// it also calls Look Up Order ID. <see cref="TheRecordedSandboxTransactionVerifiesAgainstThePinnedAppleRoot"/> checks the recorded
/// vector <c>{signedTransaction, installId}</c> (a synthetic install ID, no personal data) at its own <c>signedDate</c>. No value is
/// printed.
/// </summary>
[Trait("live", "appstore")]
public sealed class AppStoreLiveSmokeTests
{
    public static string RecordedVectorPath => Path.Combine(AppContext.BaseDirectory, "AppStore", "fixtures", "recorded-sandbox-transaction.json");

    private static readonly string[] Required = ["BUNDLE_ID", "ISSUER_ID", "KEY_ID", "PRIVATE_KEY", "TRANSACTION_ID"];

    internal static bool Configured => Required
        .All(name => !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_APPLE_" + name)));

    [LiveAppStoreFact]
    public async Task ASandboxTransactionReadsFromTheRealAppStoreServerApiWhenConfigured()
    {
        var bundleId = Variable("BUNDLE_ID");
        var settings = new Dictionary<string, string?>
        {
            ["Purchases:Apple:BundleId"] = bundleId,
            ["Purchases:Apple:IssuerId"] = Variable("ISSUER_ID"),
            ["Purchases:Apple:KeyId"] = Variable("KEY_ID"),
            ["Purchases:Apple:PrivateKey"] = Variable("PRIVATE_KEY"),

            // The table needs exactly one product per plan; these are never called.
            ["Purchases:Apple:Products:zaghlol_live_a:Type"] = "auto_renewable",
            ["Purchases:Apple:Products:zaghlol_live_a:Plan"] = "monthly",
            ["Purchases:Apple:Products:zaghlol_live_b:Type"] = "auto_renewable",
            ["Purchases:Apple:Products:zaghlol_live_b:Plan"] = "yearly",
            ["Purchases:Apple:Products:zaghlol_live_c:Type"] = "non_consumable",
            ["Purchases:Apple:Products:zaghlol_live_c:Plan"] = "lifetime",
        };
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        services.AddSingleton<IHostEnvironment>(new AppStoreOptionsTests.Env("Staging"));
        services.AddLogging();
        services.AddZaghlolAppStore();
        await using var provider = services.BuildServiceProvider();
        var api = provider.GetRequiredService<IAppStoreServerApi>();
        var verifier = provider.GetRequiredService<IAppleJwsVerifier>();

        var signed = await api.GetTransactionInfoAsync(PurchaseEnvironment.Sandbox, new Sensitive<string>(Variable("TRANSACTION_ID")), StoreLane.Verify, CancellationToken.None);
        var transaction = verifier.VerifyTransaction(signed, JwsSource.Api, DateTimeOffset.UtcNow);

        Assert.Equal(bundleId, transaction.BundleId);
        Assert.Equal(AppleEnvironment.Sandbox, transaction.Environment);

        if (Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_APPLE_ORDER_ID") is { Length: > 0 } orderId)
        {
            var lookup = await api.LookUpOrderIdAsync(new Sensitive<string>(orderId), StoreLane.Support, CancellationToken.None);
            Assert.True(lookup.Status is 0 or 1);
            foreach (var entry in lookup.SignedTransactions)
            {
                Assert.Equal(AppleEnvironment.Production, verifier.VerifyTransaction(entry, JwsSource.Api, DateTimeOffset.UtcNow).Environment);
            }
        }
    }

    [RecordedAppleVectorFact]
    public void TheRecordedSandboxTransactionVerifiesAgainstThePinnedAppleRoot()
    {
        var vector = JsonNode.Parse(File.ReadAllText(RecordedVectorPath))!;
        var verifier = new AppleJwsVerifier(AppleRootCertificate.Der);

        var transaction = verifier.VerifyTransaction(new Sensitive<string>(vector["signedTransaction"]!.GetValue<string>()), JwsSource.App, DateTimeOffset.UtcNow);

        Assert.Equal(AppleEnvironment.Sandbox, transaction.Environment);
        Assert.True(StoreBindingRef.MatchesAppAccountToken(transaction.AppAccountToken?.Reveal(), InstallId.Parse(vector["installId"]!.GetValue<string>())));
    }

    private static string Variable(string name) => Environment.GetEnvironmentVariable("ZAGHLOL_LIVE_APPLE_" + name)!;
}
