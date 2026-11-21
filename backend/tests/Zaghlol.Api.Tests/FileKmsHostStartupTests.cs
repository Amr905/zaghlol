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

    private WebApplicationFactory<Program> Factory(string environment, Dictionary<string, string?> kms) =>
        ProductionApiFactory.Create(environment, kms, logs, issuer, appleKey);
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
