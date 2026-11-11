using System.Buffers.Text;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>T-131 §2 step 3: the pinned Apple Root CA - G3 resource.</summary>
public sealed class AppleRootCertificateTests
{
    [Fact]
    public void TheEmbeddedRootIsApplesG3WithThePublishedFingerprint()
    {
        var der = AppleRootCertificate.Load();
        using var root = X509CertificateLoader.LoadCertificate(der);

        Assert.Equal(AppleRootCertificate.Sha256Fingerprint, Convert.ToHexStringLower(SHA256.HashData(der)));
        Assert.Equal("63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179", Convert.ToHexString(SHA256.HashData(der)));
        Assert.Equal("Apple Root CA - G3", root.GetNameInfo(X509NameType.SimpleName, forIssuer: false));
        Assert.Contains("O=Apple Inc.", root.Subject, StringComparison.Ordinal);
        Assert.Equal(root.Subject, root.Issuer);
        Assert.Equal("2DC5FC88D2C54B95", root.SerialNumber);
        Assert.Equal(new DateTime(2039, 4, 30, 18, 19, 6, DateTimeKind.Utc), root.NotAfter.ToUniversalTime());
    }

    [Fact]
    public void AMissingOrDifferentResourceStopsStartup()
    {
        Assert.Throws<AppStoreConfigurationException>(() => AppleRootCertificate.Load(null, AppleRootCertificate.Sha256Fingerprint));

        var tampered = AppleRootCertificate.Der;
        tampered[^1] ^= 0x01;
        Assert.Throws<AppStoreConfigurationException>(() => AppleRootCertificate.Load(new MemoryStream(tampered), AppleRootCertificate.Sha256Fingerprint));
    }
}

/// <summary>T-131 §5-6 and §10 "Other": <c>Purchases:Apple</c> validation and the Production refusals.</summary>
public sealed class AppStoreOptionsTests
{
    private const string Marker = "SECRET-apple-key-5c2";

    [Fact]
    public void ACompleteProductionConfigurationIsAccepted()
    {
        var options = AppStoreOptions.Read(Config(Production()), new Env("Production"));

        Assert.Equal("app.zaghlol", options.Catalog.BundleId);
        Assert.Equal(3, options.Catalog.Products.Count);
        Assert.False(options.Catalog.AllowSandbox);
        Assert.Equal(new Uri("https://api.storekit.apple.com/"), options.ProductionUrl);
        Assert.Equal(new Uri("https://api.storekit-sandbox.apple.com/"), options.SandboxUrl);
        Assert.True(options.HasCredential);
        Assert.Null(options.TestRoot);
        Assert.Equal(AppleRootCertificate.Der, options.TrustAnchor());
        Assert.Equal("***", options.PrivateKey.ToString());
    }

    [Theory]
    [InlineData("Purchases:Apple:BundleId", null)]
    [InlineData("Purchases:Apple:BundleId", "app.zaghlol.dev")]
    [InlineData("Purchases:Apple:BundleId", "not a bundle")]
    [InlineData("Purchases:Apple:IssuerId", null)]
    [InlineData("Purchases:Apple:IssuerId", "issuer")]
    [InlineData("Purchases:Apple:KeyId", null)]
    [InlineData("Purchases:Apple:KeyId", "abc")]
    [InlineData("Purchases:Apple:PrivateKey", null)]
    [InlineData("Purchases:Apple:PrivateKey", "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----")]
    [InlineData("Purchases:Apple:AllowSandbox", null)]
    [InlineData("Purchases:Apple:AllowSandbox", "yes")]
    [InlineData("Purchases:Apple:ProductionBaseUrl", "https://api.storekit.example.test")]
    [InlineData("Purchases:Apple:ProductionBaseUrl", "http://api.storekit.apple.com")]
    [InlineData("Purchases:Apple:SandboxBaseUrl", "https://api.storekit.apple.com")]
    [InlineData("Purchases:Apple:SandboxBaseUrl", "https://api.storekit-sandbox.itunes.apple.com")]
    [InlineData("Purchases:Apple:TestRootCertificate", "AAAA")]
    [InlineData("Purchases:Apple:Products:zaghlol_gold_lifetime:Type", "auto_renewable")]
    [InlineData("Purchases:Apple:Products:zaghlol_gold_yearly:Plan", "monthly")]
    [InlineData("Purchases:Apple:Products:Zaghlol Gold:Type", "non_consumable")]
    public void ProductionRefusesAnIncompleteOrTestConfiguration(string key, string? value)
    {
        var settings = Production();
        settings[key] = value;

        Assert.Throws<AppStoreConfigurationException>(() => AppStoreOptions.Read(Config(settings), new Env("Production")));
    }

    [Theory]
    [InlineData("Purchases:Apple:BundleId", null)]
    [InlineData("Purchases:Apple:PrivateKey", null)]
    [InlineData("Purchases:Apple:ProductionBaseUrl", "https://api.storekit.example.test")]
    [InlineData("Purchases:Apple:TestRootCertificate", "AAAA")]
    public void StagingIsLockedTooExceptForSandboxAndBundle(string key, string? value)
    {
        var settings = Production();
        settings[key] = value;

        Assert.Throws<AppStoreConfigurationException>(() => AppStoreOptions.Read(Config(settings), new Env("Staging")));

        // Staging may name its staging bundle and leave AllowSandbox at its default.
        var staging = Production();
        staging["Purchases:Apple:BundleId"] = "app.zaghlol.staging";
        staging.Remove("Purchases:Apple:AllowSandbox");
        Assert.True(AppStoreOptions.Read(Config(staging), new Env("Staging")).Catalog.AllowSandbox);
    }

    [Fact]
    public void DevelopmentAndTestingAcceptAnEmptySectionAndATestRootButNotHalfAKey()
    {
        var empty = AppStoreOptions.Read(Config([]), new Env("Development"));
        Assert.Empty(empty.Catalog.Products);
        Assert.False(empty.HasCredential);
        Assert.True(empty.Catalog.AllowSandbox);

        using var pki = AppleTestPki.Create();
        var test = AppStoreOptions.Read(Config(new() { ["Purchases:Apple:TestRootCertificate"] = pki.RootBase64 }), new Env("Testing"));
        Assert.Equal(pki.RootDer, test.TrustAnchor());

        Assert.Throws<AppStoreConfigurationException>(() =>
            AppStoreOptions.Read(Config(new() { ["Purchases:Apple:KeyId"] = "ZT2K7Q9XAB" }), new Env("Testing")));
    }

    [Fact]
    public void APrivateKeyFromAConfigurationFileIsRefusedInProduction()
    {
        var file = Path.Combine(Path.GetTempPath(), "zaghlol-apple-" + Guid.NewGuid().ToString("N") + ".json");
        var settings = Production();
        try
        {
            File.WriteAllText(file, JsonSerializer.Serialize(new Dictionary<string, object>
            {
                ["Purchases"] = new Dictionary<string, object> { ["Apple"] = new Dictionary<string, string> { ["PrivateKey"] = settings["Purchases:Apple:PrivateKey"]! } },
            }));
            settings.Remove("Purchases:Apple:PrivateKey");
            var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).AddJsonFile(file).Build();

            Assert.Throws<AppStoreConfigurationException>(() => AppStoreOptions.Read(configuration, new Env("Production")));
            Assert.True(AppStoreOptions.Read(configuration, new Env("Staging")).HasCredential);
        }
        finally
        {
            File.Delete(file);
        }
    }

    [Fact]
    public void NoValueIsEchoedInAnError()
    {
        var settings = Production();
        settings["Purchases:Apple:PrivateKey"] = "-----BEGIN PRIVATE KEY-----\n" + Marker + "\n-----END PRIVATE KEY-----";
        settings["Purchases:Apple:BundleId"] = "bad bundle " + Marker;

        var error = Assert.Throws<AppStoreConfigurationException>(() => AppStoreOptions.Read(Config(settings), new Env("Production")));
        Assert.DoesNotContain(Marker, error.ToString(), StringComparison.Ordinal);

        settings["Purchases:Apple:BundleId"] = "app.zaghlol";
        var keyError = Assert.Throws<AppStoreConfigurationException>(() => AppStoreOptions.Read(Config(settings), new Env("Production")));
        Assert.DoesNotContain(Marker, keyError.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void BudgetAndResilienceOverridesApplyOnlyWhereAllowed()
    {
        var settings = Production();
        settings["Purchases:Apple:Budget:Replicas"] = "3";
        settings["Purchases:Apple:Budget:VerifyPerInstallPerHour"] = "1000";
        settings["Purchases:Apple:Resilience:RetryBaseDelayMs"] = "1";

        var production = AppStoreOptions.Read(Config(settings), new Env("Production"));
        Assert.Equal(100, production.Budget.PerReplicaLimit);
        Assert.Equal(20, production.Budget.PerReplicaPerPeriod);
        Assert.Equal(10, production.Budget.VerifyPerInstallPerHour);
        Assert.Equal(TimeSpan.FromMilliseconds(400), production.Resilience.RetryBaseDelay);

        settings["Purchases:Apple:Budget:Replicas"] = "0";
        Assert.Throws<AppStoreConfigurationException>(() => AppStoreOptions.Read(Config(settings), new Env("Production")));
    }

    [Fact]
    public async Task ProductionStartupRefusesAFakeClientOrVerifierAndAcceptsTheRealOnes()
    {
        var env = new Env("Production");
        await using (var real = Services(Production(), env))
        {
            await Check(real).StartAsync(CancellationToken.None);
        }

        await using (var fakeClient = Services(Production(), env, s => s.AddSingleton<IAppStoreServerApi>(new NoApple())))
        {
            await Assert.ThrowsAsync<AppStoreConfigurationException>(() => Check(fakeClient).StartAsync(CancellationToken.None));
        }

        await using (var fakeVerifier = Services(Production(), env, s => s.AddSingleton<IAppleJwsVerifier>(new NoJws())))
        {
            await Assert.ThrowsAsync<AppStoreConfigurationException>(() => Check(fakeVerifier).StartAsync(CancellationToken.None));
        }

        // Development: an empty section starts (docker compose), and the pinned root still loads.
        await using var development = Services([], new Env("Development"));
        await Check(development).StartAsync(CancellationToken.None);
    }

    internal static Dictionary<string, string?> Production()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        return new(StringComparer.Ordinal)
        {
            ["Purchases:Apple:BundleId"] = "app.zaghlol",
            ["Purchases:Apple:AllowSandbox"] = "false",
            ["Purchases:Apple:IssuerId"] = AppleWireMock.IssuerId,
            ["Purchases:Apple:KeyId"] = AppleWireMock.KeyId,
            ["Purchases:Apple:PrivateKey"] = key.ExportPkcs8PrivateKeyPem(),
            ["Purchases:Apple:Products:zaghlol_gold_monthly:Type"] = "auto_renewable",
            ["Purchases:Apple:Products:zaghlol_gold_monthly:Plan"] = "monthly",
            ["Purchases:Apple:Products:zaghlol_gold_yearly:Type"] = "auto_renewable",
            ["Purchases:Apple:Products:zaghlol_gold_yearly:Plan"] = "yearly",
            ["Purchases:Apple:Products:zaghlol_gold_lifetime:Type"] = "non_consumable",
            ["Purchases:Apple:Products:zaghlol_gold_lifetime:Plan"] = "lifetime",
        };
    }

    private static IConfiguration Config(Dictionary<string, string?> settings) => new ConfigurationBuilder().AddInMemoryCollection(settings).Build();

    private static ServiceProvider Services(Dictionary<string, string?> settings, IHostEnvironment env, Action<IServiceCollection>? extra = null)
    {
        var services = new ServiceCollection();
        services.AddSingleton(Config(settings));
        services.AddSingleton(env);
        services.AddLogging();
        services.AddZaghlolAppStore();
        extra?.Invoke(services);
        return services.BuildServiceProvider();
    }

    private static IHostedService Check(IServiceProvider provider) =>
        provider.GetServices<IHostedService>().Single(s => s.GetType().Name == "AppStoreStartupCheck");

    internal sealed class Env(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    private sealed class NoApple : IAppStoreServerApi
    {
        public Task<Sensitive<string>> GetTransactionInfoAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<IReadOnlyList<AppleLastTransaction>> GetAllSubscriptionStatusesAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<AppleOrderLookupResult> LookUpOrderIdAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class NoJws : IAppleJwsVerifier
    {
        public AppleTransaction VerifyTransaction(Sensitive<string> jws, JwsSource source, DateTimeOffset now) => throw new NotSupportedException();

        public AppleRenewalInfo VerifyRenewalInfo(Sensitive<string> jws, DateTimeOffset now) => throw new NotSupportedException();
    }
}

/// <summary>T-131 §5: the App Store Server API token.</summary>
public sealed class AppStoreApiTokenProviderTests
{
    [Fact]
    public void TheTokenHasApplesClaimsAndVerifiesWithTheKey()
    {
        using var apple = new AppleWireMock();
        var clock = new MovableClock(new DateTimeOffset(2026, 11, 11, 10, 0, 0, 500, TimeSpan.Zero));
        using var provider = new AppStoreApiTokenProvider(Options(apple), clock);

        var token = provider.GetToken()!.Value.Reveal();
        var parts = token.Split('.');
        using var header = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[0]));
        using var payload = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1]));

        Assert.Equal("ES256", header.RootElement.GetProperty("alg").GetString());
        Assert.Equal(AppleWireMock.KeyId, header.RootElement.GetProperty("kid").GetString());
        Assert.Equal("JWT", header.RootElement.GetProperty("typ").GetString());
        var claims = payload.RootElement;
        Assert.Equal(["iss", "iat", "exp", "aud", "bid"], claims.EnumerateObject().Select(p => p.Name));
        Assert.Equal(AppleWireMock.IssuerId, claims.GetProperty("iss").GetString());
        Assert.Equal("appstoreconnect-v1", claims.GetProperty("aud").GetString());
        Assert.Equal(AppleWireMock.BundleId, claims.GetProperty("bid").GetString());
        var iat = claims.GetProperty("iat").GetInt64();
        Assert.Equal(clock.Now.ToUnixTimeSeconds(), iat);
        Assert.Equal(1200, claims.GetProperty("exp").GetInt64() - iat);
        Assert.True(claims.GetProperty("exp").GetInt64() - iat <= 3600, "Apple refuses tokens living more than 60 minutes");
        Assert.True(apple.ApiKey.VerifyData(
            Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]),
            Base64Url.DecodeFromChars(parts[2]),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
    }

    [Fact]
    public void OneTokenIsReusedUntilFiveMinutesBeforeItExpires()
    {
        using var apple = new AppleWireMock();
        var clock = new MovableClock(DateTimeOffset.UtcNow);
        using var provider = new AppStoreApiTokenProvider(Options(apple), clock);

        var first = provider.GetToken()!.Value.Reveal();
        clock.Now = clock.Now.AddMinutes(14);
        Assert.Equal(first, provider.GetToken()!.Value.Reveal());
        clock.Now = clock.Now.AddMinutes(1).AddSeconds(1);
        Assert.NotEqual(first, provider.GetToken()!.Value.Reveal());
    }

    [Fact]
    public void WithoutAKeyNoTokenIsSent()
    {
        var options = AppStoreOptions.Read(new ConfigurationBuilder().Build(), new AppStoreOptionsTests.Env("Testing"));
        using var provider = new AppStoreApiTokenProvider(options, TimeProvider.System);

        Assert.Null(provider.GetToken());
    }

    private static AppStoreOptions Options(AppleWireMock apple) =>
        AppStoreOptions.Read(new ConfigurationBuilder().AddInMemoryCollection(apple.Settings()).Build(), new AppStoreOptionsTests.Env("Testing"));
}

/// <summary>T-131 §6 (FU-077 M-2): the separate Apple budget and the verify per-install limit.</summary>
public sealed class AppleCallBudgetTests
{
    [Fact]
    public void NotificationsKeepA20PercentReserveAndRestoreIsDeniedFirst()
    {
        using var budget = new AppleCallBudget(new AppleBudgetOptions(10, 1, TimeSpan.FromHours(1), 1, 10));

        // Restore stops while only the notification reserve (2) plus its own 30 % reserve (3) is left; its sub-bucket holds 3.
        Assert.Equal(3, Enumerable.Range(0, 10).Count(_ => budget.TryAcquire(StoreLane.Restore)));

        // Verify and support stop at the 20 % notification reserve.
        Assert.Equal(5, Enumerable.Range(0, 10).Count(_ => budget.TryAcquire(StoreLane.Verify)));
        Assert.False(budget.TryAcquire(StoreLane.Support));
        Assert.False(budget.TryAcquire(StoreLane.Restore));

        // Notifications spend the reserve, down to zero.
        Assert.True(budget.TryAcquire(StoreLane.Rtdn));
        Assert.True(budget.TryAcquire(StoreLane.Rtdn));
        Assert.False(budget.TryAcquire(StoreLane.Rtdn));
    }

    [Fact]
    public void TheBucketIsSizedPerReplica()
    {
        using var budget = new AppleCallBudget(new AppleBudgetOptions(30, 1, TimeSpan.FromHours(1), 3, 10));

        // 30 over 3 replicas = 10 here; verify may take 8 (20 % reserve).
        Assert.Equal(8, Enumerable.Range(0, 30).Count(_ => budget.TryAcquire(StoreLane.Verify)));
    }

    [Fact]
    public void EachInstallGetsTenVerifiesAnHour()
    {
        using var limiter = new AppleVerifyLimiter(AppleBudgetOptions.Default);
        var a = InstallId.FromGuid(Guid.NewGuid());
        var b = InstallId.FromGuid(Guid.NewGuid());

        Assert.Equal(10, Enumerable.Range(0, 15).Count(_ => limiter.TryAcquire(a)));
        Assert.True(limiter.TryAcquire(b));
    }
}

/// <summary>A clock the tests move.</summary>
internal sealed class MovableClock(DateTimeOffset now) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = now;

    public override DateTimeOffset GetUtcNow() => Now;
}
