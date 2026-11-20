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
/// T-200 acceptance 2 and 3 at host level: the real API <c>Program</c> starts in Staging and Production with
/// <c>Kms:Provider = File</c> and correct keys (the database is unreachable on purpose; the host still starts and readiness
/// stays red), and refuses to start on a group-readable key with the constant message and no key material in the logs.
/// </summary>
[Collection(ApiHostGroup.Name)]
[SupportedOSPlatform("linux")]
public sealed class FileKmsHostStartupTests : IDisposable
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    private readonly FileKmsKeySet keys = new();
    private readonly FakeOidcIssuer issuer = new();
    private readonly ECDsa appleKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private readonly CapturingSink logs = new();

    public void Dispose()
    {
        keys.Dispose();
        appleKey.Dispose();
    }

    [ApiLinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task TheApiStartsWithTheFileKms(string environment)
    {
        using var factory = Factory(environment, keys.Settings());

        _ = factory.Services; // starts the host: every startup check, the KMS ones included

        Assert.Equal("FileKms", factory.Services.GetRequiredService<ISigningKeyProvider>().GetType().Name);
        var signer = factory.Services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        var point = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.ToX963();
        using var verifier = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = point[1..33], Y = point[33..] },
        });
        Assert.True(verifier.VerifyData("{}"u8, signature.Signature.Span, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
        Assert.Contains(logs.Entries, e => e.StartsWith("KMS key ring verified", StringComparison.Ordinal));
        AssertNoKeyMaterial();
    }

    [ApiLinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public void TheApiRefusesAGroupReadableKeyFile(string environment)
    {
        File.SetUnixFileMode(Path.Combine(keys.Directory, "envelope.key"), UnixFileMode.UserRead | UnixFileMode.GroupRead);
        var error = ApiStartRefusal.Expect(() => Factory(environment, keys.Settings()));

        var refusal = Assert.Single(HostStartupTests.Chain(error).OfType<KmsConfigurationException>());
        Assert.StartsWith("Kms:File:KeyDirectory holds an entry that is a symbolic link, not a regular file, group/other accessible", refusal.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(keys.Directory, error.ToString(), StringComparison.Ordinal);
        AssertNoKeyMaterial(error.ToString());
    }

    [ApiLinuxFact]
    public void TheApiStillRefusesTheLocalProviderInProduction()
    {
        var settings = keys.Settings();
        settings["Kms:Provider"] = "Local";
        settings["Kms:Local:KeyDirectory"] = keys.Directory;
        var error = ApiStartRefusal.Expect(() => Factory("Production", settings));

        Assert.Contains(HostStartupTests.Chain(error), e => e is KmsConfigurationException && e.Message.Contains("Development and Testing", StringComparison.Ordinal));
    }

    private void AssertNoKeyMaterial(string? extra = null)
    {
        foreach (var haystack in logs.Entries.Append(extra ?? string.Empty))
        {
            foreach (var sentinel in keys.Sentinels)
            {
                Assert.DoesNotContain(sentinel, haystack, StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    /// <summary>The real Program with every Production setting a self-hosted deployment needs (public test values).</summary>
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

/// <summary>A [Fact] that runs only on Linux (the File KMS checks POSIX owner and mode).</summary>
public sealed class ApiLinuxFactAttribute : FactAttribute
{
    public ApiLinuxFactAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only: the File KMS refuses other systems (Infrastructure test G2).";
        }
    }
}

/// <summary>A [Theory] that runs only on Linux.</summary>
public sealed class ApiLinuxTheoryAttribute : TheoryAttribute
{
    public ApiLinuxTheoryAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only: the File KMS refuses other systems (Infrastructure test G2).";
        }
    }
}
