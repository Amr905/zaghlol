using System.Collections.Concurrent;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-200 acceptance 2 and 3: the File KMS starts in Staging and Production with correct keys, and every guard of the design
/// note (G2–G13) refuses the start with its constant message and no key material, path or key name in any log or message.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class FileKmsTests : IDisposable
{
    private readonly FileKmsKeySet keys = new();

    public void Dispose() => keys.Dispose();

    [LinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    [InlineData("Testing")]
    public async Task CorrectKeysStartAndServeEveryPort(string environment)
    {
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = FileKmsHost.Services(environment, keys.Settings(), logs);

        await FileKmsHost.StartAsync(services);

        var signer = services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        Assert.True(signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.Verifies("{}"u8, signature.Signature.Span));
        var mac = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "x"u8.ToArray(), CancellationToken.None);
        Assert.Equal(HMACSHA256.HashData(keys.ReadSecret("audit"), "x"u8), mac);
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync("hello"u8.ToArray(), "ctx", CancellationToken.None);
        Assert.Equal("hello"u8.ToArray(), await cipher.DecryptAsync(blob, "ctx", CancellationToken.None));
        Assert.Contains(logs.Lines, l => l.Contains("KMS key ring verified", StringComparison.Ordinal));
        AssertNoSecrets(logs.Lines);
    }

    [LinuxFact]
    public async Task Mode0600FilesAnd0500DirectoryAreAccepted()
    {
        foreach (var file in Directory.EnumerateFiles(keys.Directory))
        {
            File.SetUnixFileMode(file, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }

        File.SetUnixFileMode(keys.Directory, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        await using var services = FileKmsHost.Services("Production", keys.Settings());

        await FileKmsHost.StartAsync(services);
    }

    [LinuxFact]
    public async Task TwoActorsSignAtTheSameTime()
    {
        await using var services = FileKmsHost.Services("Production", keys.Settings());
        await FileKmsHost.StartAsync(services);
        var signer = services.GetRequiredService<ISigner>();
        var jwk = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk;

        var results = await Task.WhenAll(Enumerable.Range(0, 64).Select(i => Task.Run(async () =>
        {
            var body = BitConverter.GetBytes(i);
            var signature = await signer.SignAsync(SigningPurpose.Sync, body, CancellationToken.None);
            return jwk.Verifies(body, signature.Signature.Span);
        })));

        Assert.All(results, Assert.True);
    }

    // ---- G1: Local is still refused outside Development/Testing ----------------------------------------------------------

    [LinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task G1_TheLocalProviderIsStillRefused(string environment)
    {
        var settings = keys.Settings();
        settings["Kms:Provider"] = "Local";
        settings["Kms:Local:KeyDirectory"] = keys.Directory;

        var error = await RefusedAsync(environment, settings);

        Assert.Contains("Development and Testing", error.Message, StringComparison.Ordinal);
    }

    // ---- G3: the directory setting -----------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData(null, FileKms.DirectoryUnsetMessage)]
    [InlineData("relative/keys", FileKms.DirectoryNotCanonicalMessage)]
    [InlineData("{dir}/", FileKms.DirectoryNotCanonicalMessage)]
    [InlineData("{dir}/../keys", FileKms.DirectoryNotCanonicalMessage)]
    [InlineData("{dir}/seat.key", FileKms.DirectoryNotCanonicalMessage)]
    [InlineData("{dir}/absent", FileKms.DirectoryUnreadableMessage)]
    public async Task G3_ABadDirectorySettingIsRefused(string? value, string message)
    {
        var settings = keys.Settings();
        settings["Kms:File:KeyDirectory"] = value?.Replace("{dir}", keys.Directory, StringComparison.Ordinal);

        await RefusedAsync("Production", settings, message);
    }

    [LinuxFact]
    public async Task G3_ADirectoryReachedThroughASymlinkIsRefused()
    {
        var link = Path.Combine(keys.Root, "link");
        Directory.CreateSymbolicLink(link, keys.Directory);
        var settings = keys.Settings();
        settings["Kms:File:KeyDirectory"] = link;

        await RefusedAsync("Production", settings, FileKms.DirectoryNotCanonicalMessage);
    }

    // ---- G4: the directory's own mode and owner ----------------------------------------------------------------------

    [LinuxTheory]
    [InlineData(UnixFileMode.GroupRead)]
    [InlineData(UnixFileMode.GroupExecute)]
    [InlineData(UnixFileMode.OtherRead)]
    [InlineData(UnixFileMode.OtherWrite)]
    public async Task G4_AGroupOrWorldAccessibleDirectoryIsRefused(UnixFileMode extra)
    {
        File.SetUnixFileMode(keys.Directory, FileKmsKeySet.Mode0700 | extra);

        await RefusedAsync("Production", keys.Settings(), FileKms.DirectoryPermissionsMessage);
    }

    [LinuxFact]
    public async Task G4_ADirectoryOwnedByAnotherUserIsRefused()
    {
        if (!FileKmsKeySet.IsRoot)
        {
            return; // chown needs root; the CI container and the local-ci runner run as root.
        }

        FileKmsKeySet.Chown(keys.Directory, 4242);

        await RefusedAsync("Production", keys.Settings(), FileKms.DirectoryPermissionsMessage);
    }

    // ---- G5: parents --------------------------------------------------------------------------------------------------

    [LinuxFact]
    public async Task G5_AGroupWritableParentIsRefused()
    {
        using var nested = new FileKmsKeySet("shared");
        File.SetUnixFileMode(Path.Combine(nested.Root, "shared"), FileKmsKeySet.Mode0700 | UnixFileMode.GroupWrite | UnixFileMode.GroupRead | UnixFileMode.GroupExecute);

        await RefusedAsync("Production", nested.Settings(), FileKms.AncestorPermissionsMessage);
    }

    [LinuxFact]
    public async Task G5_AWorldWritableStickyParentIsAccepted()
    {
        using var nested = new FileKmsKeySet("sticky");
        File.SetUnixFileMode(Path.Combine(nested.Root, "sticky"), (UnixFileMode)Convert.ToInt32("1777", 8));
        await using var services = FileKmsHost.Services("Production", nested.Settings());

        await FileKmsHost.StartAsync(services);
    }

    [LinuxFact]
    public async Task G5_AWorldWritableParentWithoutStickyIsRefused()
    {
        using var nested = new FileKmsKeySet("open");
        File.SetUnixFileMode(Path.Combine(nested.Root, "open"), (UnixFileMode)Convert.ToInt32("777", 8));

        await RefusedAsync("Production", nested.Settings(), FileKms.AncestorPermissionsMessage);
    }

    // ---- G6: entries ----------------------------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData(UnixFileMode.GroupRead)]
    [InlineData(UnixFileMode.OtherRead)]
    [InlineData(UnixFileMode.GroupWrite)]
    [InlineData(UnixFileMode.OtherWrite)]
    [InlineData(UnixFileMode.SetUser)]
    public async Task G6_AGroupOrWorldAccessibleKeyFileIsRefused(UnixFileMode extra)
    {
        File.SetUnixFileMode(Path.Combine(keys.Directory, "seat.key"), FileKmsKeySet.Mode0400 | extra);

        await RefusedAsync("Production", keys.Settings(), FileKms.EntryMessage);
    }

    [LinuxFact]
    public async Task G6_AnUnrelatedGroupReadableFileIsRefusedToo()
    {
        var notes = keys.Write("notes.txt", "operator notes");
        File.SetUnixFileMode(notes, FileKmsKeySet.Mode0400 | UnixFileMode.OtherRead);

        await RefusedAsync("Production", keys.Settings(), FileKms.EntryMessage);
    }

    [LinuxFact]
    public async Task G6_ASymlinkedKeyFileIsRefused()
    {
        var real = Path.Combine(keys.Root, "seat-real.key");
        File.Move(Path.Combine(keys.Directory, "seat.key"), real);
        File.CreateSymbolicLink(Path.Combine(keys.Directory, "seat.key"), real);

        await RefusedAsync("Production", keys.Settings(), FileKms.EntryMessage);
    }

    [LinuxFact]
    public async Task G6_ASubdirectoryIsRefused()
    {
        Directory.CreateDirectory(Path.Combine(keys.Directory, "old"), FileKmsKeySet.Mode0700);

        await RefusedAsync("Production", keys.Settings(), FileKms.EntryMessage);
    }

    [LinuxFact]
    public async Task G6_AKeyFileOwnedByAnotherUserIsRefused()
    {
        if (!FileKmsKeySet.IsRoot)
        {
            return; // chown needs root.
        }

        FileKmsKeySet.Chown(Path.Combine(keys.Directory, "audit.key"), 4242);

        await RefusedAsync("Production", keys.Settings(), FileKms.EntryMessage);
    }

    // ---- G7: references and formats ------------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData("file:../seat")]
    [InlineData("file:Seat")]
    [InlineData("local:seat")]
    [InlineData("seat")]
    [InlineData("file:s2026a")]
    public async Task G7_ABadKeyReferenceIsRefused(string keyRef)
    {
        var settings = keys.Settings();
        settings["Kms:HmacKeys:Seat"] = keyRef;

        await RefusedAsync("Production", settings, FileKms.KeyRefMessage);
    }

    [LinuxFact]
    public async Task G7_AMissingKeyFileIsRefused()
    {
        File.Delete(Path.Combine(keys.Directory, "install-pepper.key"));

        await RefusedAsync("Production", keys.Settings(), FileKms.MissingKeyMessage);
    }

    [LinuxFact]
    public async Task G7_AnOversizedKeyFileIsRefused()
    {
        keys.Write("seat.key", new string('A', FileKms.MaxFileBytes + 1));

        await RefusedAsync("Production", keys.Settings(), FileKms.TooLargeMessage);
    }

    [LinuxTheory]
    [InlineData("short")]
    [InlineData("not base64")]
    [InlineData("long")]
    [InlineData("crlf")]
    public async Task G7_ASymmetricKeyThatIsNot32BytesOfBase64IsRefused(string kind)
    {
        var content = kind switch
        {
            "short" => Convert.ToBase64String(RandomNumberGenerator.GetBytes(31)) + "\n",
            "long" => Convert.ToBase64String(RandomNumberGenerator.GetBytes(33)) + "\n",
            "crlf" => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)) + "\r\n",
            _ => "!!!!" + new string('A', 40) + "\n",
        };
        keys.Write("audit.key", content);

        await RefusedAsync("Production", keys.Settings(), FileKms.NotSecretMessage);
    }

    [LinuxTheory]
    [InlineData("public")]
    [InlineData("p384")]
    [InlineData("garbage")]
    [InlineData("rsa")]
    [InlineData("explicit")]
    public async Task G7_ASigningKeyThatIsNotAP256PrivateKeyIsRefused(string kind)
    {
        string pem;
        switch (kind)
        {
            case "public":
                using (var ec = ECDsa.Create(ECCurve.NamedCurves.nistP256))
                {
                    pem = ec.ExportSubjectPublicKeyInfoPem();
                }

                break;
            case "p384":
                using (var ec = ECDsa.Create(ECCurve.NamedCurves.nistP384))
                {
                    pem = ec.ExportPkcs8PrivateKeyPem();
                }

                break;
            case "rsa":
                using (var rsa = RSA.Create(2048))
                {
                    pem = rsa.ExportPkcs8PrivateKeyPem();
                }

                break;
            case "explicit":
                // Review C2: P-256 written with explicit curve parameters (no OID).
                using (var named = ECDsa.Create(ECCurve.NamedCurves.nistP256))
                using (var explicitKey = ECDsa.Create(named.ExportExplicitParameters(includePrivateParameters: true)))
                {
                    pem = explicitKey.ExportPkcs8PrivateKeyPem();
                }

                break;
            default:
                pem = "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n";
                break;
        }

        keys.Write("s2026a.pem", pem);

        await RefusedAsync("Production", keys.Settings(), FileKms.NotEcPemMessage);
    }

    // ---- G8: source tree and content root ------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData(".git", true)]
    [InlineData(".git", false)]
    [InlineData("Zaghlol.sln", false)]
    public async Task G8_AKeyDirectoryInsideASourceTreeIsRefused(string marker, bool isDirectory)
    {
        var path = Path.Combine(keys.Root, marker);
        if (isDirectory)
        {
            Directory.CreateDirectory(path);
        }
        else
        {
            File.WriteAllText(path, "gitdir: elsewhere");
        }

        await RefusedAsync("Production", keys.Settings(), FileKms.SourceTreeMessage);
    }

    [LinuxTheory]
    [InlineData("root")]
    [InlineData("keys")]
    [InlineData("inside")]
    public async Task G8_AKeyDirectoryOverlappingTheContentRootIsRefused(string where)
    {
        var contentRoot = where switch
        {
            "root" => keys.Root,
            "keys" => keys.Directory,
            _ => Path.Combine(keys.Directory, "app"),
        };

        await RefusedAsync("Production", keys.Settings(), FileKms.SourceTreeMessage, contentRoot);
    }

    [LinuxFact]
    public void G8_TheRepositoryItselfIsASourceTree()
    {
        // The test binaries live under backend/tests/.../bin inside this repository.
        Assert.True(FileKms.IsInSourceTree(AppContext.BaseDirectory));
        Assert.False(FileKms.IsInSourceTree(keys.Directory));
    }

    // ---- G9: dev-keys.sh output ------------------------------------------------------------------------------------------

    [LinuxFact]
    public async Task G9_ADirectoryHoldingKmsEnvIsRefused()
    {
        keys.Write("kms.env", "# Generated by backend/tools/dev-keys.sh\n");

        await RefusedAsync("Production", keys.Settings(), FileKms.DevKeysMessage);
    }

    // ---- G10: committed and degenerate keys -----------------------------------------------------------------------------

    [LinuxFact]
    public async Task G10_TheCommittedVectorSeatKeyIsRefused()
    {
        keys.WriteSecret("seat", FakeKms.FixedSeatKey);

        await RefusedAsync("Production", keys.Settings(), FileKms.KnownTestKeyMessage);
    }

    [LinuxTheory]
    [InlineData("zero")]
    [InlineData("repeated")]
    [InlineData("pattern")]
    public async Task G10_ADegenerateSymmetricKeyIsRefused(string kind)
    {
        var secret = kind switch
        {
            "zero" => new byte[32],
            "repeated" => Enumerable.Repeat((byte)0x5a, 32).ToArray(),
            _ => Enumerable.Range(0, 32).Select(i => (byte)(i % 8)).ToArray(),
        };
        keys.WriteSecret("envelope", secret);

        await RefusedAsync("Production", keys.Settings(), FileKms.KnownTestKeyMessage);
    }

    [LinuxFact]
    public async Task G10_TheCommittedCatalogDevKeyIsRefused()
    {
        using var committed = KnownTestKeysTests.CatalogDevKey();
        keys.WriteSigningKey("s2026a", committed);
        var settings = keys.Settings();
        var point = committed.ExportParameters(false).Q;
        settings["Signing:Keys:0:PublicJwk:X"] = System.Buffers.Text.Base64Url.EncodeToString(point.X!);
        settings["Signing:Keys:0:PublicJwk:Y"] = System.Buffers.Text.Base64Url.EncodeToString(point.Y!);

        await RefusedAsync("Production", settings, FileKms.KnownTestKeyMessage);
    }

    [LinuxFact]
    public async Task G10_ASigningKeyWithATinyScalarIsRefused()
    {
        // Review S4: d = 5, so the public key is 5G; the pin and JWK match, only the scalar check stops it.
        var scalar = new byte[32];
        scalar[31] = 5;
        using var tiny = ECDsa.Create();
        tiny.ImportParameters(new ECParameters { Curve = ECCurve.NamedCurves.nistP256, D = scalar });
        keys.WriteSigningKey("s2026a", tiny);
        var settings = keys.Settings();
        var point = tiny.ExportParameters(false).Q;
        settings["Signing:Keys:0:PublicJwk:X"] = System.Buffers.Text.Base64Url.EncodeToString(point.X!);
        settings["Signing:Keys:0:PublicJwk:Y"] = System.Buffers.Text.Base64Url.EncodeToString(point.Y!);

        await RefusedAsync("Production", settings, FileKms.KnownTestKeyMessage);
    }

    // ---- S3: one key, one role ------------------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData("Kms:Envelope:KeyRef")]
    [InlineData("Kms:HmacKeys:Audit")]
    public async Task S3_OneKeyReferenceInTwoRolesIsRefused(string setting)
    {
        var settings = keys.Settings();
        settings[setting] = "file:seat";

        await RefusedAsync("Production", settings, FileKms.SharedKeyMessage);
    }

    [LinuxFact]
    public async Task S3_TheSameKeyBytesUnderTwoNamesAreRefused()
    {
        keys.WriteSecret("envelope", keys.ReadSecret("audit"));

        await RefusedAsync("Production", keys.Settings(), FileKms.SharedKeyMessage);
    }

    [LinuxFact]
    public async Task C7_AShellSafePinNameIsAccepted()
    {
        var settings = keys.Settings();
        settings["Kms:File:Fingerprints:install_pepper"] = settings["Kms:File:Fingerprints:install-pepper"];
        settings.Remove("Kms:File:Fingerprints:install-pepper");
        await using var services = FileKmsHost.Services("Production", settings);

        await FileKmsHost.StartAsync(services);
    }

    // ---- G11: fingerprint pins ------------------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData("seat", null)]
    [InlineData("seat", "ABC")]
    [InlineData("seat", "0000000000000000000000000000000000000000000000000000000000000000")]
    [InlineData("e2026a", null)]
    [InlineData("e2026a", "1111111111111111111111111111111111111111111111111111111111111111")]
    public async Task G11_AMissingOrWrongPinIsRefused(string name, string? pin)
    {
        var settings = keys.Settings();
        settings["Kms:File:Fingerprints:" + name] = pin;

        await RefusedAsync("Production", settings, FileKms.FingerprintMessage);
    }

    [LinuxFact]
    public async Task G11_AReplacedKeyFileIsRefusedEvenWithAValidRing()
    {
        // The operator restores the wrong backup of the HMAC key: the ring and SeatCheck don't cover audit, the pin does.
        var settings = keys.Settings();
        keys.WriteSecret("audit", RandomNumberGenerator.GetBytes(32));

        await RefusedAsync("Production", settings, FileKms.FingerprintMessage);
    }

    // ---- G12: the other environment's keys -------------------------------------------------------------------------------

    [LinuxFact]
    public async Task G12_AKeyListedAsTheOtherEnvironmentsIsRefused()
    {
        var settings = keys.Settings();
        settings["Kms:File:NoOtherEnvironment"] = null;
        settings["Kms:File:OtherEnvironmentFingerprints:0"] = new string('a', 64);
        settings["Kms:File:OtherEnvironmentFingerprints:1"] = settings["Kms:File:Fingerprints:envelope"];

        await RefusedAsync("Production", settings, FileKms.OtherEnvironmentMessage);
    }

    [LinuxFact]
    public async Task G12_AStagingKeyCopiedIntoProductionIsRefused()
    {
        // Staging's key set; production config lists staging's fingerprints, and its own pins were copied too.
        using var staging = new FileKmsKeySet();
        var stagingSettings = staging.Settings();
        var production = staging.Settings();
        production["Kms:File:NoOtherEnvironment"] = null;
        var index = 0;
        foreach (var (key, value) in stagingSettings.Where(p => p.Key.StartsWith("Kms:File:Fingerprints:", StringComparison.Ordinal)))
        {
            production["Kms:File:OtherEnvironmentFingerprints:" + index++] = value;
        }

        await RefusedAsync("Production", production, FileKms.OtherEnvironmentMessage);
    }

    [LinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task G12_StagingAndProductionMustSayWhatTheOtherEnvironmentIs(string environment)
    {
        var settings = keys.Settings();
        settings["Kms:File:NoOtherEnvironment"] = null;

        await RefusedAsync(environment, settings, FileKms.OtherEnvironmentUnsetMessage);
    }

    [LinuxFact]
    public async Task G12_AnOtherEnvironmentListOfDifferentKeysIsAccepted()
    {
        using var staging = new FileKmsKeySet();
        var settings = keys.Settings();
        settings["Kms:File:NoOtherEnvironment"] = null;
        var index = 0;
        foreach (var value in staging.Settings().Where(p => p.Key.StartsWith("Kms:File:Fingerprints:", StringComparison.Ordinal)).Select(p => p.Value))
        {
            settings["Kms:File:OtherEnvironmentFingerprints:" + index++] = value;
        }

        await using var services = FileKmsHost.Services("Production", settings);
        await FileKmsHost.StartAsync(services);
    }

    [LinuxFact]
    public async Task G12_AMalformedOtherEnvironmentEntryIsRefused()
    {
        var settings = keys.Settings();
        settings["Kms:File:OtherEnvironmentFingerprints:0"] = "not-a-fingerprint";

        await RefusedAsync("Production", settings, FileKms.OtherEnvironmentMalformedMessage);
    }

    // ---- G13: dev and test kids ----------------------------------------------------------------------------------------

    [LinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task G13_DevelopmentKidsAreRefusedOutsideDevelopment(string environment)
    {
        using var dev = new FileKmsKeySet(syncKid: "s0000d", entitlementKid: "e0000d");

        await RefusedAsync(environment, dev.Settings(), FileKms.DevKidMessage);
    }

    [LinuxFact]
    public async Task G13_DevelopmentKidsAreAllowedInTesting()
    {
        using var dev = new FileKmsKeySet(syncKid: "s0000d", entitlementKid: "e0000d");
        await using var services = FileKmsHost.Services("Testing", dev.Settings());

        await FileKmsHost.StartAsync(services);
    }

    // ---- the K_seat check still runs ----------------------------------------------------------------------------------

    [LinuxFact]
    public async Task TheSeatCheckStillRefusesAWrongSeatCheckValue()
    {
        var settings = keys.Settings();
        settings[SeatKeysServiceCollectionExtensions.SeatCheckKey] = new string('0', 64);

        var error = await RefusedAsync("Production", settings);

        Assert.Equal(SeatKeyStartupCheck.MismatchMessage, error.Message);
    }

    private async Task<KmsConfigurationException> RefusedAsync(
        string environment,
        Dictionary<string, string?> settings,
        string? message = null,
        string? contentRoot = null)
    {
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = FileKmsHost.Services(environment, settings, logs, contentRoot);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));

        if (message is not null)
        {
            Assert.Equal(message, error.Message);
        }

        // Nothing that names or contains a key: not the directory, not a key name, not key bytes.
        var text = error.ToString();
        Assert.DoesNotContain(keys.Root, text, StringComparison.Ordinal);
        Assert.DoesNotContain(keys.Directory, text, StringComparison.Ordinal);
        foreach (var name in FileKmsKeySet.SecretNames.Concat(["s2026a", "e2026a"]))
        {
            Assert.DoesNotContain(name + ".", text, StringComparison.Ordinal);
        }

        AssertNoSecrets([text, .. logs.Lines]);
        return error;
    }

    private void AssertNoSecrets(IEnumerable<string> haystacks)
    {
        foreach (var haystack in haystacks)
        {
            foreach (var sentinel in keys.Sentinels)
            {
                Assert.DoesNotContain(sentinel, haystack, StringComparison.OrdinalIgnoreCase);
            }
        }
    }

}

/// <summary>The KMS services of the API and the worker (AddZaghlolKms + AddZaghlolSeatKeys) over a settings dictionary.</summary>
internal static class FileKmsHost
{
    internal static ServiceProvider Services(string environment, Dictionary<string, string?> settings, CapturingLogs? logs = null, string? contentRoot = null)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        services.AddSingleton<IHostEnvironment>(new TestEnvironment(environment, contentRoot ?? AppContext.BaseDirectory));
        services.AddLogging(l => l.ClearProviders().AddProvider(logs ?? new CapturingLogs()).SetMinimumLevel(LogLevel.Trace));
        services.AddZaghlolKms();
        services.AddZaghlolSeatKeys();
        return services.BuildServiceProvider();
    }

    internal static async Task StartAsync(IServiceProvider services)
    {
        foreach (var hosted in services.GetServices<IHostedService>())
        {
            await hosted.StartAsync(CancellationToken.None);
        }
    }

    internal sealed class TestEnvironment(string name, string contentRoot) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "Zaghlol.Infrastructure.Tests";

        public string ContentRootPath { get; set; } = contentRoot;

        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    internal sealed class CapturingLogs : ILoggerProvider
    {
        private readonly ConcurrentQueue<string> lines = new();

        public IReadOnlyList<string> Lines => [.. lines];

        public ILogger CreateLogger(string categoryName) => new Logger(categoryName, lines);

        public void Dispose()
        {
        }

        private sealed class Logger(string category, ConcurrentQueue<string> lines) : ILogger
        {
            public IDisposable? BeginScope<TState>(TState state)
                where TState : notnull => null;

            public bool IsEnabled(LogLevel logLevel) => true;

            public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
            {
                var values = state is IEnumerable<KeyValuePair<string, object?>> pairs ? string.Join(',', pairs.Select(p => $"{p.Key}={p.Value}")) : string.Empty;
                lines.Enqueue($"{category} {logLevel} {formatter(state, exception)} {values} {exception}");
            }
        }
    }
}

/// <summary>G2: the File provider refuses to start on any OS but Linux (runs on the Windows PC runner; skipped on Linux).</summary>
public sealed class FileKmsPlatformTests
{
    [NonLinuxFact]
    public async Task G2_TheFileProviderRefusesToStartOffLinux()
    {
        var settings = new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["Kms:Provider"] = "File",
            ["Kms:File:KeyDirectory"] = Path.GetTempPath(),
            ["Kms:HmacKeys:Seat"] = "file:seat",
            ["Kms:HmacKeys:Audit"] = "file:audit",
            ["Kms:HmacKeys:InstallHashPepper"] = "file:install-pepper",
            ["Kms:Envelope:KeyRef"] = "file:envelope",
        };
        using var kms = FakeKms.CreateDefault();
        foreach (var (key, value) in kms.Settings().Where(p => p.Key.StartsWith("Signing:", StringComparison.Ordinal)))
        {
            settings[key] = value;
        }

        await using var services = FileKmsHost.Services("Testing", settings);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));
        Assert.Equal(FileKms.NotLinuxMessage, error.Message);
    }
}

/// <summary>A [Fact] that runs only on Linux (the File KMS and its key tool check POSIX owner and mode).</summary>
public sealed class LinuxFactAttribute : FactAttribute
{
    public LinuxFactAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only: the File KMS checks POSIX owner and mode; G2 covers other systems.";
        }
    }
}

/// <summary>A [Theory] that runs only on Linux.</summary>
public sealed class LinuxTheoryAttribute : TheoryAttribute
{
    public LinuxTheoryAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only: the File KMS checks POSIX owner and mode; G2 covers other systems.";
        }
    }
}

/// <summary>A [Fact] that runs only off Linux (the G2 refusal).</summary>
public sealed class NonLinuxFactAttribute : FactAttribute
{
    public NonLinuxFactAttribute()
    {
        if (OperatingSystem.IsLinux())
        {
            Skip = "Off-Linux only: on Linux the File KMS runs; this checks the refusal elsewhere (Windows PC runner).";
        }
    }
}
