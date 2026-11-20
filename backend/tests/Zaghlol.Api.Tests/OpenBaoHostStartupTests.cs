using System.Runtime.Versioning;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Serilog.Core;
using Zaghlol.Api.Auth;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>
/// T-201 acceptance 1 at host level: the real API <c>Program</c> starts in Staging and Production with
/// <c>Kms:Provider = OpenBao</c> after the T-200 migration (keys in the stub OpenBao, imported by the key tool), signs through
/// Transit, and refuses to start when OpenBao is sealed, with the constant message and no credential in the logs. The database
/// is unreachable on purpose, as in <see cref="FileKmsHostStartupTests"/>.
/// </summary>
[Collection(ApiHostGroup.Name)]
[SupportedOSPlatform("linux")]
public sealed class OpenBaoHostStartupTests : IAsyncLifetime, IDisposable
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    private readonly FakeOidcIssuer issuer = new();
    private readonly ECDsa appleKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private readonly CapturingSink logs = new();
    private OpenBaoTestBed bed = null!;

    public async Task InitializeAsync() => bed = await OpenBaoTestBed.CreateAsync();

    public async Task DisposeAsync() => await bed.DisposeAsync();

    public void Dispose()
    {
        issuer.Dispose();
        appleKey.Dispose();
    }

    [ApiLinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task TheApiStartsWithOpenBao(string environment)
    {
        using var factory = Factory(environment, bed.Settings());

        _ = factory.Services; // starts the host: the OpenBao check, the ring check and the SeatCheck

        Assert.Equal("OpenBaoKms", factory.Services.GetRequiredService<ISigningKeyProvider>().GetType().Name);
        var signer = factory.Services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        var point = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.ToX963();
        using var verifier = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = point[1..33], Y = point[33..] },
        });
        Assert.True(verifier.VerifyData("{}"u8, signature.Signature.Span, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
        Assert.Contains(bed.Stub.Requests, r => r.Contains("/v1/transit/sign/s2027a/sha2-256", StringComparison.Ordinal));
        Assert.Contains(logs.Entries, e => e.StartsWith("KMS key ring verified", StringComparison.Ordinal));
        AssertNoSecrets();
    }

    [ApiLinuxFact]
    public void TheApiRefusesToStartWhenOpenBaoIsSealed()
    {
        bed.Stub.Sealed = true;
        using var factory = Factory("Production", bed.Settings());

        var error = Assert.ThrowsAny<Exception>(() => factory.Services);

        var refusal = Assert.Single(HostStartupTests.Chain(error).OfType<KmsConfigurationException>());
        Assert.StartsWith("OpenBao could not be used at start", refusal.Message, StringComparison.Ordinal);
        AssertNoSecrets(error.ToString());
    }

    private void AssertNoSecrets(string? extra = null)
    {
        foreach (var haystack in logs.Entries.Append(extra ?? string.Empty))
        {
            foreach (var sentinel in bed.Sentinels)
            {
                Assert.DoesNotContain(sentinel, haystack, StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    private WebApplicationFactory<Program> Factory(string environment, Dictionary<string, string?> kms)
    {
        var settings = new Dictionary<string, string?>(kms, StringComparer.Ordinal)
        {
            ["ConnectionStrings:App"] = Unreachable,
            ["ConnectionStrings:Admin"] = Unreachable,
            ["Purchases:Google:PackageName"] = "app.zaghlol",
            ["Purchases:Google:CredentialSource"] = "ApplicationDefault",
            ["Purchases:Google:Rtdn:Audience"] = "https://api.zaghlol.app/v1/notifications/google",
            ["Purchases:Google:Rtdn:PushServiceAccount"] = "push@zaghlol-test.iam.gserviceaccount.com",
            ["Purchases:Apple:BundleId"] = "app.zaghlol",
            ["Purchases:Apple:AllowSandbox"] = "true",
            ["Purchases:Apple:IssuerId"] = "57246542-96fe-1a63-e053-0824d011072a",
            ["Purchases:Apple:KeyId"] = "ABCDE12345",
            ["Purchases:Apple:PrivateKey"] = appleKey.ExportPkcs8PrivateKeyPem(),
            ["Accounts:Google:ClientIds:0"] = "123-abc.apps.googleusercontent.com",
            ["Accounts:Apple:ServicesId"] = "app.zaghlol.signin",
            ["Accounts:Apple:BundleId"] = "app.zaghlol",
            ["Accounts:Apple:TeamId"] = "ABCDE12345",
            ["Accounts:Apple:KeyId"] = "ABCDE12345",
            ["Accounts:Apple:PrivateKey"] = appleKey.ExportPkcs8PrivateKeyPem(),
            ["Attestation:AppAttest:TeamId"] = "ABCDE12345",
            ["OperatorAuth:Enabled"] = "true",
            ["OperatorAuth:Profile"] = "Entra",
            ["OperatorAuth:AllowedTenants:0"] = FakeOidcIssuer.TenantId,
            ["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer,
            ["OperatorAuth:Audiences:0"] = FakeOidcIssuer.CliAudience,
        };
        foreach (var (plan, kind, type) in new[] { ("monthly", "subscription", "auto_renewable"), ("yearly", "subscription", "auto_renewable"), ("lifetime", "onetime", "non_consumable") })
        {
            settings[$"Purchases:Google:Products:zaghlol_gold_{plan}:Kind"] = kind;
            settings[$"Purchases:Google:Products:zaghlol_gold_{plan}:Plan"] = plan;
            settings[$"Purchases:Apple:Products:zaghlol_gold_{plan}:Type"] = type;
            settings[$"Purchases:Apple:Products:zaghlol_gold_{plan}:Plan"] = plan;
        }

        return new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment(environment);
            foreach (var (key, value) in settings)
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                services.AddSingleton<ILogEventSink>(logs);
                services.AddHttpClient(OidcKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => issuer.CreateHandler());
            });
        });
    }
}
