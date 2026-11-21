using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-205 acceptance 1, 2, 4 and 5: the HostSecrets provider starts on any OS from <c>ZAGHLOL_KEYS</c> settings, refuses every
/// misconfiguration with a constant message and no key material, and keeps File KMS kids, HMAC outputs and envelopes.
/// </summary>
public sealed class HostSecretsKmsTests : IDisposable
{
    private readonly HostSecretsKeySet keys = new();
    private readonly string scratch = Directory.CreateTempSubdirectory("zaghlol-host-secrets-").FullName;

    public void Dispose() => Directory.Delete(scratch, recursive: true);

    [Theory]
    [InlineData("Staging")]
    [InlineData("Production")]
    [InlineData("Testing")]
    public async Task CorrectKeysStartAndServeEveryPort(string environment)
    {
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = Services(environment, keys.Settings(), logs);

        await FileKmsHost.StartAsync(services);

        Assert.IsType<HostSecretsKms>(services.GetRequiredService<ISigningKeyProvider>());
        var signer = services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        Assert.True(signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.Verifies("{}"u8, signature.Signature.Span));
        var mac = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "x"u8.ToArray(), CancellationToken.None);
        Assert.Equal(HMACSHA256.HashData(keys.Secret("audit"), "x"u8), mac);
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync("hello"u8.ToArray(), "ctx", CancellationToken.None);
        Assert.Equal("hello"u8.ToArray(), await cipher.DecryptAsync(blob, "ctx", CancellationToken.None));
        Assert.Contains(logs.Lines, l => l.Contains("KMS key ring verified", StringComparison.Ordinal));
        AssertNoSecrets(string.Join('\n', logs.Lines));
    }

    [Fact]
    public async Task TwoActorsSignAndHashAtTheSameTime()
    {
        await using var services = Services("Production", keys.Settings());
        await FileKmsHost.StartAsync(services);
        var signer = services.GetRequiredService<ISigner>();
        var hasher = services.GetRequiredService<IKeyedHasher>();
        var jwk = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk;

        var results = await Task.WhenAll(Enumerable.Range(0, 64).Select(i => Task.Run(async () =>
        {
            var body = BitConverter.GetBytes(i);
            var signature = await signer.SignAsync(SigningPurpose.Sync, body, CancellationToken.None);
            var mac = await hasher.HmacSha256Async(KeyedHashKey.Seat, body, CancellationToken.None);
            return jwk.Verifies(body, signature.Signature.Span) && mac.AsSpan().SequenceEqual(HMACSHA256.HashData(keys.Secret("seat"), body));
        })));

        Assert.All(results, Assert.True);
    }

    [Fact]
    public async Task ShellSafeAndUpperCaseSettingNamesAreAccepted()
    {
        var settings = keys.Settings();
        var value = settings["ZAGHLOL_KEYS:install-pepper"];
        settings.Remove("ZAGHLOL_KEYS:install-pepper");
        settings["ZAGHLOL_KEYS:INSTALL_PEPPER"] = value;
        await using var services = Services("Production", settings);

        await FileKmsHost.StartAsync(services);
    }

    // ---- H4: custody flag (negative proof 1) ----------------------------------------------------------------------------

    [Theory]
    [InlineData("Production", null)]
    [InlineData("Production", "false")]
    [InlineData("Production", "yes")]
    [InlineData("Staging", null)]
    public async Task WithoutTheCustodyFlagTheProviderRefusesToStart(string environment, string? flag)
    {
        var settings = keys.Settings();
        settings["Kms:AcceptSharedHostCustody"] = flag;

        await AssertRefusedAsync(environment, settings, HostSecretsKms.CustodyMessage);
    }

    [Fact]
    public async Task TestingNeedsNoCustodyFlag()
    {
        var settings = keys.Settings();
        settings.Remove("Kms:AcceptSharedHostCustody");
        await using var services = Services("Testing", settings);

        await FileKmsHost.StartAsync(services);
    }

    // ---- H3: keys in configuration files (negative proof 2) -------------------------------------------------------------

    [Fact]
    public async Task AKeyServedByAnAppsettingsFileIsRefused()
    {
        var settings = keys.Settings();
        // Outside the content root, so only the configuration-provider check can see it.
        var json = Path.Combine(Directory.CreateDirectory(Path.Combine(scratch, "conf")).FullName, "appsettings.Production.json");
        await File.WriteAllTextAsync(json, "{\"ZAGHLOL_KEYS\":{\"seat\":\"" + settings["ZAGHLOL_KEYS:seat"] + "\"}}");
        settings.Remove("ZAGHLOL_KEYS:seat");
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).AddJsonFile(json).Build();

        await AssertRefusedAsync(Services("Production", configuration, null, null), HostSecretsKms.InFileMessage);
    }

    [Theory]
    [InlineData("appsettings.json", "{\"Zaghlol_Keys__seat\": \"x\"}")]
    [InlineData("appsettings.Staging.json", "{\"Somewhere\": \"MARKER\"}")]
    public async Task AKeyInAnAppsettingsFileOfTheContentRootIsRefusedEvenIfNotLoaded(string fileName, string content)
    {
        var contentRoot = Directory.CreateDirectory(Path.Combine(scratch, "root")).FullName;
        await File.WriteAllTextAsync(Path.Combine(contentRoot, fileName), content.Replace("MARKER", keys.Settings()["ZAGHLOL_KEYS:audit"], StringComparison.Ordinal));

        await AssertRefusedAsync(Services("Production", keys.Settings(), null, contentRoot), HostSecretsKms.InFileMessage);
    }

    [Fact]
    public void EverySettingValueStartsWithTheMarker()
    {
        Assert.Equal(32, HostSecretsKms.ValueMarker.Length);
        Assert.All(keys.Settings().Where(p => p.Key.StartsWith("ZAGHLOL_KEYS:", StringComparison.Ordinal)), p => Assert.StartsWith(HostSecretsKms.ValueMarker, p.Value, StringComparison.Ordinal));
    }

    // ---- H1/H2: the settings themselves ---------------------------------------------------------------------------------

    [Fact]
    public async Task AMissingSettingIsRefused()
    {
        var settings = keys.Settings();
        settings.Remove("ZAGHLOL_KEYS:envelope");

        await AssertRefusedAsync("Production", settings, HostSecretsKms.MissingMessage);
    }

    [Fact]
    public async Task BothSpellingsOfOneNameAreRefused()
    {
        var settings = keys.Settings();
        settings["ZAGHLOL_KEYS:install_pepper"] = settings["ZAGHLOL_KEYS:install-pepper"];

        await AssertRefusedAsync("Production", settings, HostSecretsKms.DuplicateMessage);
    }

    public static TheoryData<string> MalformedCases => new()
    {
        "not base64url",
        "padded",
        "extra member",
        "wrong tag",
        "wrong name",
        "pem for a symmetric key",
        "key for a signing key",
        "trailing data",
        "too long",
    };

    [Theory]
    [MemberData(nameof(MalformedCases))]
    public async Task AMalformedSettingIsRefused(string caseName)
    {
        var settings = keys.Settings();
        var secret = Convert.ToBase64String(keys.Secret("audit"));
        string Encode(string json) => System.Buffers.Text.Base64Url.EncodeToString(Encoding.UTF8.GetBytes(json));
        var audit = HostSecretsKeySet.Json("audit", "key", secret);
        switch (caseName)
        {
            case "not base64url":
                settings["ZAGHLOL_KEYS:audit"] = "+" + settings["ZAGHLOL_KEYS:audit"];
                break;
            case "padded":
                settings["ZAGHLOL_KEYS:audit"] += "==";
                break;
            case "extra member":
                settings["ZAGHLOL_KEYS:audit"] = Encode(audit[..^1] + ",\"note\":1}");
                break;
            case "wrong tag":
                settings["ZAGHLOL_KEYS:audit"] = Encode(audit.Replace("host-key-v1", "host-key-v2", StringComparison.Ordinal));
                break;
            case "wrong name":
                settings["ZAGHLOL_KEYS:audit"] = settings["ZAGHLOL_KEYS:seat"];
                break;
            case "pem for a symmetric key":
                settings["ZAGHLOL_KEYS:audit"] = Encode(HostSecretsKeySet.Json("audit", "pem", secret));
                break;
            case "key for a signing key":
                settings["ZAGHLOL_KEYS:s2026a"] = Encode(HostSecretsKeySet.Json("s2026a", "key", secret));
                break;
            case "trailing data":
                settings["ZAGHLOL_KEYS:audit"] = Encode(audit + "{}");
                break;
            case "too long":
                settings["ZAGHLOL_KEYS:audit"] = new string('A', HostSecretsKms.MaxValueChars + 1);
                break;
        }

        await AssertRefusedAsync("Production", settings, HostSecretsKms.MalformedMessage);
    }

    // ---- T-200 guards that carry over ------------------------------------------------------------------------------------

    [Fact]
    public async Task ACommittedKeyIsRefused()
    {
        keys.SetSecret("seat", FakeKms.FixedSeatKey);

        await AssertRefusedAsync("Production", keys.Settings(), HostSecretsKms.KnownTestKeyMessage);
    }

    [Fact]
    public async Task ADegenerateKeyIsRefused()
    {
        keys.SetSecret("audit", new byte[32]);

        await AssertRefusedAsync("Production", keys.Settings(), HostSecretsKms.KnownTestKeyMessage);
    }

    [Fact]
    public async Task AKeyThatDoesNotMatchItsPinIsRefused()
    {
        var settings = keys.Settings();
        settings["Kms:File:Fingerprints:audit"] = new string('a', 64);

        await AssertRefusedAsync("Production", settings, HostSecretsKms.FingerprintMessage);
    }

    [Fact]
    public async Task AnotherEnvironmentsKeyIsRefused()
    {
        var settings = keys.Settings();
        settings.Remove("Kms:File:NoOtherEnvironment");
        settings["Kms:File:OtherEnvironmentFingerprints:0"] = settings["Kms:File:Fingerprints:seat"];
        settings["Kms:File:Fingerprints:seat"] = new string('b', 64);

        await AssertRefusedAsync("Production", settings, HostSecretsKms.OtherEnvironmentKeyMessage);
    }

    [Fact]
    public async Task ProductionNeedsTheOtherEnvironmentList()
    {
        var settings = keys.Settings();
        settings.Remove("Kms:File:NoOtherEnvironment");

        await AssertRefusedAsync("Production", settings, HostSecretsKms.OtherEnvironmentUnsetMessage);
    }

    [Fact]
    public async Task OneKeyUnderTwoNamesIsRefused()
    {
        keys.SetSecret("envelope", keys.Secret("audit"));

        await AssertRefusedAsync("Production", keys.Settings(), HostSecretsKms.SharedKeyMessage);
    }

    [Fact]
    public async Task ADevelopmentKidIsRefusedInProduction()
    {
        var dev = new HostSecretsKeySet("s0000d", "e0000d");

        await AssertRefusedAsync("Production", dev.Settings(), HostSecretsKms.DevKidMessage);
    }

    [Fact]
    public async Task ANonP256SigningKeyIsRefused()
    {
        using var p384 = ECDsa.Create(ECCurve.NamedCurves.nistP384);
        var settings = keys.Settings();
        settings["ZAGHLOL_KEYS:s2026a"] = HostSecretsKeySet.Value("s2026a", "pem", p384.ExportPkcs8PrivateKeyPem());

        await AssertRefusedAsync("Production", settings, HostSecretsKms.NotEcPemMessage);
    }

    [Fact]
    public async Task AKeyRefOfAnotherProviderIsRefused()
    {
        var settings = keys.Settings();
        settings["Kms:HmacKeys:Audit"] = "local:audit";

        await AssertRefusedAsync("Production", settings, HostSecretsKms.KeyRefMessage);
    }

    [Fact]
    public async Task ADuplicateKidIsRefusedByTheRing()
    {
        var settings = keys.Settings();
        settings["Signing:Keys:1:Kid"] = "s2026a";
        settings["Signing:Keys:1:Purpose"] = "Sync";
        await using var services = Services("Production", settings);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));

        Assert.Contains("kids must be unique", error.Message, StringComparison.Ordinal);
        AssertNoSecrets(error.ToString());
    }

    // ---- AC4: the same keys as the File KMS -----------------------------------------------------------------------------

    /// <summary>
    /// The File key directory converted by the tool (<c>--from-dir</c>) starts HostSecrets with the same kids and public keys,
    /// the same HMAC output for every HMAC key, and envelopes that open in both directions, so a later move keeps every hash.
    /// </summary>
    [LinuxFact]
    [System.Runtime.Versioning.SupportedOSPlatform("linux")]
    public async Task TheConvertedFileKeysGiveTheSameKidsHmacsAndEnvelopes()
    {
        using var fileKeys = new FileKmsKeySet();
        var cwd = Directory.CreateDirectory(Path.Combine(scratch, "cwd")).FullName;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        Assert.Equal(0, FileKeyTool.Run(["--generate-keys", "--format", "host-secrets", "--environment", "Production", "--from-dir", fileKeys.Directory], stdout, stderr, cwd));

        var hostSettings = fileKeys.Settings();
        foreach (var key in hostSettings.Keys.Where(k => k.StartsWith("Kms:File:Fingerprints:", StringComparison.Ordinal)).ToList())
        {
            hostSettings.Remove(key);
        }

        foreach (var (key, value) in HostSecretsKeyToolTests.ParseLines(stdout.ToString()))
        {
            hostSettings[key] = value;
        }

        hostSettings.Remove("Kms:File:KeyDirectory");
        hostSettings["Kms:AcceptSharedHostCustody"] = "true";
        Assert.Equal("HostSecrets", hostSettings["Kms:Provider"]);

        await using var file = FileKmsHost.Services("Production", fileKeys.Settings());
        await using var host = Services("Production", hostSettings);
        await FileKmsHost.StartAsync(file);
        await FileKmsHost.StartAsync(host);

        var fileProvider = file.GetRequiredService<IKmsBackend>();
        var hostProvider = host.GetRequiredService<IKmsBackend>();
        foreach (var kid in new[] { "s2026a", "e2026a" })
        {
            Assert.Equal(await fileProvider.GetPublicKeyAsync("file:" + kid, default), await hostProvider.GetPublicKeyAsync("file:" + kid, default));
        }

        foreach (var name in new[] { "seat", "audit", "install-pepper" })
        {
            Assert.Equal(await fileProvider.HmacSha256Async("file:" + name, "probe"u8.ToArray(), default), await hostProvider.HmacSha256Async("file:" + name, "probe"u8.ToArray(), default));
        }

        var fromFile = await file.GetRequiredService<IEnvelopeCipher>().EncryptAsync("one"u8.ToArray(), "ctx", default);
        Assert.Equal("one"u8.ToArray(), await host.GetRequiredService<IEnvelopeCipher>().DecryptAsync(fromFile, "ctx", default));
        var fromHost = await host.GetRequiredService<IEnvelopeCipher>().EncryptAsync("two"u8.ToArray(), "ctx", default);
        Assert.Equal("two"u8.ToArray(), await file.GetRequiredService<IEnvelopeCipher>().DecryptAsync(fromHost, "ctx", default));
        Assert.All(fileKeys.Sentinels, s => Assert.DoesNotContain(s, stderr.ToString(), StringComparison.OrdinalIgnoreCase));
    }

    private async Task AssertRefusedAsync(string environment, Dictionary<string, string?> settings, string message) =>
        await AssertRefusedAsync(Services(environment, settings), message);

    private async Task AssertRefusedAsync(ServiceProvider services, string message)
    {
        await using (services)
        {
            var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));
            Assert.Equal(message, error.Message);
            AssertNoSecrets(error.ToString());
        }
    }

    private void AssertNoSecrets(string text)
    {
        foreach (var sentinel in keys.Sentinels)
        {
            Assert.DoesNotContain(sentinel, text, StringComparison.OrdinalIgnoreCase);
        }
    }

    private ServiceProvider Services(string environment, Dictionary<string, string?> settings, FileKmsHost.CapturingLogs? logs = null) =>
        Services(environment, new ConfigurationBuilder().AddInMemoryCollection(settings).Build(), logs, null);

    private ServiceProvider Services(string environment, Dictionary<string, string?> settings, FileKmsHost.CapturingLogs? logs, string? contentRoot) =>
        Services(environment, new ConfigurationBuilder().AddInMemoryCollection(settings).Build(), logs, contentRoot);

    private ServiceProvider Services(string environment, IConfigurationRoot configuration, FileKmsHost.CapturingLogs? logs, string? contentRoot)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new FileKmsHost.TestEnvironment(environment, contentRoot ?? scratch));
        services.AddLogging(l => l.ClearProviders().AddProvider(logs ?? new FileKmsHost.CapturingLogs()).SetMinimumLevel(LogLevel.Trace));
        services.AddZaghlolKms();
        services.AddZaghlolSeatKeys();
        return services.BuildServiceProvider();
    }
}
