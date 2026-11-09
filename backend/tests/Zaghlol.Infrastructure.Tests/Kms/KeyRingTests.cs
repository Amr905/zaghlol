using System.Buffers.Text;
using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>T-123: the key ring and provider refuse to start unless every startup rule of the design note holds.</summary>
public sealed class KeyRingTests : IDisposable
{
    private readonly string directory = Directory.CreateTempSubdirectory("zaghlol-kms-test-").FullName;

    public void Dispose() => Directory.Delete(directory, recursive: true);

    public static TheoryData<string, string?> BadRings => new()
    {
        { "no active sync key", "Signing:Keys:0:Status=Next" },
        { "two active sync keys", "Signing:Keys:2:Kid=s0001t;Signing:Keys:2:Purpose=Sync;Signing:Keys:2:Status=Active;Signing:Keys:2:KeyRef=fake:s0001t" },
        { "kid pattern", "Signing:Keys:0:Kid=s2026" },
        { "upper-case kid", "Signing:Keys:0:Kid=S0000t" },
        { "purpose prefix", "Signing:Keys:0:Kid=e0009t" },
        { "duplicate kid", "Signing:Keys:1:Kid=s0000t;Signing:Keys:1:Purpose=Sync;Signing:Keys:1:Status=Next" },
        { "shared key reference", "Signing:Keys:1:KeyRef=fake:s0000t" },
        { "not P-256", "Signing:Keys:0:PublicJwk:Crv=P-384" },
        { "not EC", "Signing:Keys:0:PublicJwk:Kty=RSA" },
        { "short coordinate", "Signing:Keys:0:PublicJwk:X=AAAA" },
        { "unknown purpose", "Signing:Keys:0:Purpose=Catalog" },
        { "missing hmac key", "Kms:HmacKeys:Seat=" },
        { "missing envelope key", "Kms:Envelope:KeyRef=" },
    };

    [Theory]
    [MemberData(nameof(BadRings))]
    public async Task AMisconfiguredRingIsRejected(string name, string? overrides)
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices(Parse(overrides, kms));

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
        Assert.False(string.IsNullOrEmpty(error.Message), name);
    }

    // Windows CNG throws PlatformNotSupportedException while the test builds the off-curve key; the check
    // under test runs on Linux (CI, local-ci containers).
    [FactSkipOnWindows]
    public async Task AnOffCurvePointIsRejected()
    {
        using var kms = FakeKms.CreateDefault();
        var jwk = kms.Keys[0].PublicJwk;
        var y = Base64Url.DecodeFromChars(jwk.Y);
        y[31] ^= 0x01;
        var extra = new Dictionary<string, string?> { ["Signing:Keys:0:PublicJwk:Y"] = Base64Url.EncodeToString(y) };
        await using var services = kms.BuildServices(extra);

        await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
    }

    [Fact]
    public async Task AJwkThatIsNotTheKmsKeyIsRejected()
    {
        // A wrong key reference: the configured JWK belongs to another key.
        using var kms = FakeKms.CreateDefault();
        using var other = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var q = other.ExportParameters(false).Q;
        var extra = new Dictionary<string, string?>
        {
            ["Signing:Keys:1:PublicJwk:X"] = Base64Url.EncodeToString(q.X!),
            ["Signing:Keys:1:PublicJwk:Y"] = Base64Url.EncodeToString(q.Y!),
        };
        await using var services = kms.BuildServices(extra);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
        Assert.Contains("does not match", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AValidRingPassesTheStartupCheck()
    {
        using var kms = FakeKms.CreateDefault();
        kms.AddSigningKey("s0001t", SigningPurpose.Sync, SigningKeyStatus.Next);
        kms.AddSigningKey("e1999t", SigningPurpose.Entitlement, SigningKeyStatus.Retired);
        await using var services = kms.BuildServices();

        await StartCheckAsync(services);
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public async Task TheLocalProviderRefusesToStartOutsideDevelopmentAndTesting(string environment)
    {
        WriteLocalKeys();
        await using var services = LocalServices(environment);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
        Assert.Contains("Development and Testing", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnUnknownProviderRefusesToStart()
    {
        WriteLocalKeys();
        await using var services = LocalServices("Development", provider: "AzureKeyVault");

        await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    public async Task TheLocalProviderSignsHashesAndWrapsWithKeyFiles(string environment)
    {
        WriteLocalKeys();
        await using var services = LocalServices(environment);

        await StartCheckAsync(services);
        var signer = services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        Assert.True(signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.Verifies("{}"u8, signature.Signature.Span));

        var mac = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "x"u8.ToArray(), CancellationToken.None);
        Assert.Equal(HMACSHA256.HashData(Convert.FromBase64String(File.ReadAllText(Path.Combine(directory, "audit.key"))), "x"u8), mac);
    }

    [Fact]
    public async Task AMissingLocalKeyFileFailsWithoutNamingIt()
    {
        WriteLocalKeys();
        File.Delete(Path.Combine(directory, "seat.key"));
        await using var services = LocalServices("Development");

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
        Assert.DoesNotContain("seat", error.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(directory, error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("local:../etc/passwd")]
    [InlineData("local:Seat")]
    [InlineData("seat")]
    public async Task LocalKeyReferencesCannotLeaveTheKeyDirectory(string keyRef)
    {
        WriteLocalKeys();
        await using var services = LocalServices("Development", extra: new Dictionary<string, string?> { ["Kms:HmacKeys:Seat"] = keyRef });

        await Assert.ThrowsAsync<KmsConfigurationException>(() => StartCheckAsync(services));
    }

    private static async Task StartCheckAsync(IServiceProvider services)
    {
        foreach (var hosted in services.GetServices<IHostedService>())
        {
            await hosted.StartAsync(CancellationToken.None);
        }
    }

    private static Dictionary<string, string?> Parse(string? overrides, FakeKms kms)
    {
        var result = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var pair in (overrides ?? string.Empty).Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var (key, value) = (pair[..pair.IndexOf('=', StringComparison.Ordinal)], pair[(pair.IndexOf('=', StringComparison.Ordinal) + 1)..]);
            result[key] = value;
        }

        // Entries that add a key copy the JWK of key 0 unless they set their own.
        foreach (var index in new[] { "1", "2" })
        {
            if (result.ContainsKey($"Signing:Keys:{index}:Kid") && !result.ContainsKey($"Signing:Keys:{index}:PublicJwk:X"))
            {
                var source = kms.Keys[0];
                result.TryAdd($"Signing:Keys:{index}:KeyRef", "fake:extra" + index);
                result[$"Signing:Keys:{index}:PublicJwk:Kty"] = source.PublicJwk.Kty;
                result[$"Signing:Keys:{index}:PublicJwk:Crv"] = source.PublicJwk.Crv;
                result[$"Signing:Keys:{index}:PublicJwk:X"] = source.PublicJwk.X;
                result[$"Signing:Keys:{index}:PublicJwk:Y"] = source.PublicJwk.Y;
            }
        }

        return result;
    }

    /// <summary>The files <c>backend/tools/dev-keys.sh</c> writes, generated here at test time.</summary>
    private void WriteLocalKeys()
    {
        foreach (var name in new[] { "s0000d", "e0000d" })
        {
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            File.WriteAllText(Path.Combine(directory, name + ".pem"), key.ExportPkcs8PrivateKeyPem());
        }

        foreach (var name in new[] { "seat", "audit", "install-pepper", "envelope" })
        {
            File.WriteAllText(Path.Combine(directory, name + ".key"), Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)) + "\n");
        }
    }

    private ServiceProvider LocalServices(string environment, string provider = "Local", Dictionary<string, string?>? extra = null)
    {
        var settings = new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["Kms:Provider"] = provider,
            ["Kms:Local:KeyDirectory"] = directory,
            ["Kms:HmacKeys:Seat"] = "local:seat",
            ["Kms:HmacKeys:Audit"] = "local:audit",
            ["Kms:HmacKeys:InstallHashPepper"] = "local:install-pepper",
            ["Kms:Envelope:KeyRef"] = "local:envelope",
        };
        var index = 0;
        foreach (var (kid, purpose) in new[] { ("s0000d", "Sync"), ("e0000d", "Entitlement") })
        {
            using var key = ECDsa.Create();
            key.ImportFromPem(File.ReadAllText(Path.Combine(directory, kid + ".pem")));
            var q = key.ExportParameters(false).Q;
            var prefix = string.Create(System.Globalization.CultureInfo.InvariantCulture, $"Signing:Keys:{index++}:");
            settings[prefix + "Kid"] = kid;
            settings[prefix + "Purpose"] = purpose;
            settings[prefix + "Status"] = "Active";
            settings[prefix + "KeyRef"] = "local:" + kid;
            settings[prefix + "PublicJwk:Kty"] = "EC";
            settings[prefix + "PublicJwk:Crv"] = "P-256";
            settings[prefix + "PublicJwk:X"] = Base64Url.EncodeToString(q.X!);
            settings[prefix + "PublicJwk:Y"] = Base64Url.EncodeToString(q.Y!);
        }

        foreach (var (key, value) in extra ?? new Dictionary<string, string?>())
        {
            settings[key] = value;
        }

        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        services.AddSingleton<IHostEnvironment>(new TestEnvironment(environment));
        services.AddLogging();
        services.AddZaghlolKms();
        return services.BuildServiceProvider();
    }

    private sealed class TestEnvironment(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "Zaghlol.Infrastructure.Tests";

        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;

        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}

/// <summary>A [Fact] that is skipped on Windows (xunit 2 has no runtime skip).</summary>
internal sealed class FactSkipOnWindowsAttribute : FactAttribute
{
    public FactSkipOnWindowsAttribute()
    {
        if (OperatingSystem.IsWindows())
        {
            Skip = "Windows CNG rejects off-curve EC points with PlatformNotSupportedException when the fixture builds them; covered on Linux.";
        }
    }
}
