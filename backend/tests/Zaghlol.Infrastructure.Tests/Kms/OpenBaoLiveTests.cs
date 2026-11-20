using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-201 acceptance 2 against a real OpenBao (CI job <c>openbao-live</c>, <c>backend/tools/openbao-live.sh</c>): the production
/// <c>openbao.hcl</c> (raft, static seal, TLS, audit), <c>setup.sh apply</c>, the T-200 key tool and the OpenBao key tool. Each
/// phase runs after one server event; locally (no <c>ZAGHLOL_OPENBAO_ADDR</c>) every test is skipped.
/// <list type="bullet">
/// <item><c>1</c>: API and worker start in Production; sign/verify; JWK = Transit key; HMAC = HMAC of the T-200 key bytes;
/// new and T-200 envelopes open. Writes <c>state.json</c> (MACs of fixed probes, two envelopes, a signature).</item>
/// <item><c>2</c> (after <c>docker restart</c>, static auto-unseal): the same MACs, both envelopes still open.</item>
/// <item><c>sealed</c> (after <c>bao operator seal</c>) and <c>stopped</c> (after <c>docker stop</c>): calls are
/// <see cref="KmsUnavailableException"/> (503), never "undecryptable"; the start is refused.</item>
/// </list>
/// </summary>
[SupportedOSPlatform("linux")]
[Trait("Category", "OpenBaoLive")]
public sealed class OpenBaoLiveTests
{
    private static readonly byte[] Probe = "zaghlol-openbao-live-probe"u8.ToArray();

    private static string Work => Environment.GetEnvironmentVariable("ZAGHLOL_OPENBAO_DIR")!;

    private static string StatePath => Path.Combine(Work, "state.json");

    [OpenBaoLiveFact("1")]
    public async Task Phase1_EveryPortWorksAgainstARealOpenBao()
    {
        // A T-200 envelope sealed by the real File provider before the switch.
        byte[] legacy;
        await using (var file = FileKmsHost.Services("Production", FileSettings()))
        {
            await FileKmsHost.StartAsync(file);
            legacy = await file.GetRequiredService<IEnvelopeCipher>().EncryptAsync("legacy"u8.ToArray(), "live", CancellationToken.None);
        }

        await using var services = OpenBaoTestBed.Services("Production", ApiSettings());
        await FileKmsHost.StartAsync(services);

        var signer = services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, Probe, CancellationToken.None);
        Assert.True(signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.Verifies(Probe, signature.Signature.Span));
        var provider = services.GetRequiredService<ISigningKeyProvider>();
        foreach (var purpose in Enum.GetValues<SigningPurpose>())
        {
            var key = signer.PublishedKeys(purpose).Single();
            Assert.Equal(key.PublicJwk.ToX963(), await provider.GetPublicKeyAsync(key.KeyRef, CancellationToken.None));
        }

        var macs = await MacsAsync(services);
        foreach (var (name, mac) in macs)
        {
            Assert.Equal(Convert.ToHexStringLower(HMACSHA256.HashData(FileSecret(name), Probe)), mac);
        }

        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var fresh = await cipher.EncryptAsync("fresh"u8.ToArray(), "live", CancellationToken.None);
        Assert.Equal("fresh"u8.ToArray(), await cipher.DecryptAsync(fresh, "live", CancellationToken.None));
        Assert.Equal("legacy"u8.ToArray(), await cipher.DecryptAsync(legacy, "live", CancellationToken.None));

        // The worker: envelope keys only, its own AppRole.
        await using (var worker = OpenBaoTestBed.Services("Production", WorkerSettings()))
        {
            await FileKmsHost.StartAsync(worker);
            var workerCipher = worker.GetRequiredService<IEnvelopeCipher>();
            Assert.Equal("legacy"u8.ToArray(), await workerCipher.DecryptAsync(legacy, "live", CancellationToken.None));
            Assert.Equal("fresh"u8.ToArray(), await workerCipher.DecryptAsync(fresh, "live", CancellationToken.None));
        }

        await File.WriteAllTextAsync(StatePath, JsonSerializer.Serialize(new State(macs, Convert.ToBase64String(fresh), Convert.ToBase64String(legacy))));
    }

    [OpenBaoLiveFact("2")]
    public async Task Phase2_AfterARestartTheHashesAndEnvelopesAreUnchanged()
    {
        var state = JsonSerializer.Deserialize<State>(await File.ReadAllTextAsync(StatePath))!;
        await using var services = OpenBaoTestBed.Services("Production", ApiSettings());
        await FileKmsHost.StartAsync(services);

        Assert.Equal(state.Macs, await MacsAsync(services));
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        Assert.Equal("fresh"u8.ToArray(), await cipher.DecryptAsync(Convert.FromBase64String(state.Fresh), "live", CancellationToken.None));
        Assert.Equal("legacy"u8.ToArray(), await cipher.DecryptAsync(Convert.FromBase64String(state.Legacy), "live", CancellationToken.None));
    }

    [OpenBaoLiveFact("sealed")]
    public Task PhaseSealed_EveryCallIsUnavailable() => AssertUnavailableAsync();

    [OpenBaoLiveFact("stopped")]
    public Task PhaseStopped_EveryCallIsUnavailable() => AssertUnavailableAsync();

    private static async Task AssertUnavailableAsync()
    {
        var state = JsonSerializer.Deserialize<State>(await File.ReadAllTextAsync(StatePath))!;
        await using var services = OpenBaoTestBed.Services("Production", ApiSettings());

        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<ISigner>().SignAsync(SigningPurpose.Sync, Probe, CancellationToken.None).AsTask());
        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Seat, Probe, CancellationToken.None).AsTask());
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        await Assert.ThrowsAsync<KmsUnavailableException>(() => cipher.DecryptAsync(Convert.FromBase64String(state.Fresh), "live", CancellationToken.None).AsTask());
        await Assert.ThrowsAsync<KmsUnavailableException>(() => cipher.DecryptAsync(Convert.FromBase64String(state.Legacy), "live", CancellationToken.None).AsTask());

        await using var starting = OpenBaoTestBed.Services("Production", ApiSettings());
        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(starting));
        Assert.Equal(OpenBaoKms.UnreachableMessage, error.Message);
    }

    private static async Task<Dictionary<string, string>> MacsAsync(IServiceProvider services)
    {
        var hasher = services.GetRequiredService<IKeyedHasher>();
        var macs = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, name) in new[] { (KeyedHashKey.Seat, "seat"), (KeyedHashKey.Audit, "audit"), (KeyedHashKey.InstallHashPepper, "install-pepper") })
        {
            macs[name] = Convert.ToHexStringLower(await hasher.HmacSha256Async(key, Probe, CancellationToken.None));
        }

        return macs;
    }

    private static byte[] FileSecret(string name) =>
        Convert.FromBase64String(File.ReadAllText(Path.Combine(Work, "filekeys", "keys", name + ".key")).Trim());

    private static Dictionary<string, string?> EnvFile(string name) =>
        OpenBaoTestBed.ParseEnvLines(File.ReadAllText(Path.Combine(Work, name))).ToDictionary(p => p.Key, string? (p) => p.Value, StringComparer.Ordinal);

    /// <summary>The T-200 settings the File key tool printed (CI generated the File keys the way production did).</summary>
    private static Dictionary<string, string?> FileSettings()
    {
        var settings = EnvFile("file-kms.env");
        settings["Kms:File:KeyDirectory"] = Path.Combine(Work, "filekeys", "keys");
        settings["Kms:File:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "file:seat";
        settings["Kms:HmacKeys:Audit"] = "file:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "file:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "file:envelope";
        foreach (var key in settings.Keys.Where(k => k.EndsWith(":Status", StringComparison.Ordinal)).ToList())
        {
            settings[key] = "Active";
        }

        return settings;
    }

    private static Dictionary<string, string?> ApiSettings(bool worker = false)
    {
        var settings = EnvFile("openbao-kms.env");
        settings["Kms:Provider"] = "OpenBao";
        settings["Kms:OpenBao:Address"] = Environment.GetEnvironmentVariable("ZAGHLOL_OPENBAO_ADDR");
        settings["Kms:OpenBao:CredentialDirectory"] = Path.Combine(Work, "creds", worker ? "worker" : "api");
        settings["Kms:OpenBao:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "openbao:seat";
        settings["Kms:HmacKeys:Audit"] = "openbao:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "openbao:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "openbao:envelope-2027";
        settings["Kms:HmacKeys:SeatCheck"] = EnvFile("file-kms.env")["Kms:HmacKeys:SeatCheck"];
        if (worker)
        {
            settings["Kms:Scope"] = "Envelope";
        }

        foreach (var key in settings.Keys.Where(k => k.EndsWith(":Status", StringComparison.Ordinal)).ToList())
        {
            settings[key] = "Active";
        }

        return settings;
    }

    private static Dictionary<string, string?> WorkerSettings() => ApiSettings(worker: true);

    private sealed record State(Dictionary<string, string> Macs, string Fresh, string Legacy);
}

/// <summary>Runs only in the CI phase named by <c>ZAGHLOL_OPENBAO_PHASE</c>, with <c>ZAGHLOL_OPENBAO_ADDR</c> set.</summary>
public sealed class OpenBaoLiveFactAttribute : FactAttribute
{
    public OpenBaoLiveFactAttribute(string phase)
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ZAGHLOL_OPENBAO_ADDR")))
        {
            Skip = "Needs a real OpenBao (CI job openbao-live sets ZAGHLOL_OPENBAO_ADDR).";
        }
        else if (Environment.GetEnvironmentVariable("ZAGHLOL_OPENBAO_PHASE") != phase)
        {
            Skip = "Another OpenBao live phase is running.";
        }
        else if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only.";
        }
    }
}
