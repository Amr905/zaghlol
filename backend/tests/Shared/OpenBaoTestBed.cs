using System.Runtime.Versioning;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Testing;

/// <summary>
/// T-201: the migration as an operator runs it, against <see cref="OpenBaoStub"/>. T-200 File keys (seat, audit,
/// install-pepper, envelope) are imported by the real key tool (<see cref="OpenBaoKeyTool"/>, BYOK over TLS); the signing
/// kids and the new envelope key are created in the stub (setup.sh's job); the API and worker AppRoles get the policies
/// the committed <c>setup.sh</c> prints; credential folders are laid out as in deployment.md (0700, files 0400).
/// </summary>
[SupportedOSPlatform("linux")]
internal sealed class OpenBaoTestBed : IAsyncDisposable
{
    public const string SyncKid = "s2027a";
    public const string EntitlementKid = "e2027a";
    public const string Envelope = "envelope-2027";

    /// <summary>The T-200 kids of <see cref="FileKmsKeySet"/>: Retired and verify-only after the switch-over.</summary>
    public const string RetiredSyncKid = "s2026a";
    public const string RetiredEntitlementKid = "e2026a";

    // The credential file names the adapter reads (OpenBaoKms.RoleIdFile, SecretIdFile, CaFile; deployment.md §3).
    public const string RoleIdFile = "role-id";
    public const string SecretIdFile = "secret-id";
    public const string CaFileName = "ca.pem";

    public static readonly Dictionary<string, string> PolicyEnvironment = new(StringComparer.Ordinal)
    {
        ["ZAGHLOL_KIDS"] = SyncKid + " " + EntitlementKid,
        ["ZAGHLOL_ENVELOPE_KEYS"] = Envelope,
        ["ZAGHLOL_LEGACY_ENVELOPE_KEYS"] = "envelope",
    };

    private readonly Dictionary<string, string?> toolSettings = new(StringComparer.Ordinal);

    private OpenBaoTestBed(OpenBaoStub stub)
    {
        Stub = stub;
        Root = Directory.CreateTempSubdirectory("zaghlol-openbao-").FullName;
        File.SetUnixFileMode(Root, FileKmsKeySet.Mode0700);
    }

    public FileKmsKeySet FileKeys { get; } = new();

    public OpenBaoStub Stub { get; }

    /// <summary>A private temp folder for credentials, the CA file and the key-tool token.</summary>
    public string Root { get; }

    public string ApiCredentials => Path.Combine(Root, "api");

    public string WorkerCredentials => Path.Combine(Root, "worker");

    public string CaFile => Path.Combine(Root, "ca.pem");

    public string ToolTokenFile => Path.Combine(Root, "keytool-token");

    public (string RoleId, string SecretId) ApiRole { get; private set; }

    public (string RoleId, string SecretId) WorkerRole { get; private set; }

    public string ToolOutput { get; private set; } = string.Empty;

    public string ToolErrors { get; private set; } = string.Empty;

    /// <summary>Text that must never reach a log, an exception or tool output: credentials, tokens and every File key.</summary>
    public IEnumerable<string> Sentinels =>
        FileKeys.Sentinels.Concat([ApiRole.SecretId, WorkerRole.SecretId, ApiRole.RoleId, File.ReadAllText(ToolTokenFile).Trim()]).Concat(Stub.IssuedTokens);

    public static async Task<OpenBaoTestBed> CreateAsync(bool import = true)
    {
        var bed = new OpenBaoTestBed(await OpenBaoStub.StartAsync());
        foreach (var which in new[] { "api", "worker", "keytool" })
        {
            bed.Stub.LoadSetupPolicy(which, PolicyEnvironment);
        }

        bed.Stub.CreateKey(SyncKid, "ecdsa-p256");
        bed.Stub.CreateKey(EntitlementKid, "ecdsa-p256");
        bed.Stub.CreateKey(Envelope, "aes256-gcm96");
        bed.ApiRole = bed.Stub.CreateRole("zaghlol-api");
        bed.WorkerRole = bed.Stub.CreateRole("zaghlol-worker");
        WriteCredentials(bed.ApiCredentials, bed.ApiRole, bed.Stub.Ca.Pem);
        WriteCredentials(bed.WorkerCredentials, bed.WorkerRole, bed.Stub.Ca.Pem);
        WritePrivate(bed.CaFile, bed.Stub.Ca.Pem);
        WritePrivate(bed.ToolTokenFile, bed.Stub.CreateToken("zaghlol-keytool") + "\n");

        if (import)
        {
            var (code, output, errors) = RunTool(bed.ImportArguments());
            if (code != OpenBaoKeyTool.Ok)
            {
                throw new InvalidOperationException("key tool failed: " + errors);
            }

            bed.ToolOutput = output;
            bed.ToolErrors = errors;
            bed.toolSettings.Clear();
            foreach (var (key, value) in ParseEnvLines(output))
            {
                bed.toolSettings[key] = value;
            }
        }

        return bed;
    }

    /// <summary>The operator's import and describe run (deployment.md §3).</summary>
    public List<string> ImportArguments() =>
    [
        OpenBaoKeyTool.Flag,
        "--environment", "Production",
        "--address", Stub.Address.ToString(),
        "--ca-file", CaFile,
        "--token-file", ToolTokenFile,
        "--file-keys", FileKeys.Directory,
        "--import-hmac", "seat",
        "--import-hmac", "audit",
        "--import-hmac", "install-pepper",
        "--import-envelope", "envelope",
        "--kid", SyncKid,
        "--kid", EntitlementKid,
        "--envelope", Envelope,
    ];

    public static (int Code, string Output, string Errors) RunTool(IReadOnlyList<string> args)
    {
        using var output = new StringWriter();
        using var errors = new StringWriter();
        var code = OpenBaoKeyTool.Run(args, output, errors);
        return (code, output.ToString(), errors.ToString());
    }

    /// <summary>The API's (or, with <paramref name="worker"/>, the worker's) settings after the migration.</summary>
    public Dictionary<string, string?> Settings(bool worker = false)
    {
        var file = FileKeys.Settings();
        var settings = file
            .Where(p => !p.Key.StartsWith("Kms:File:", StringComparison.Ordinal) && !p.Key.StartsWith("Signing:", StringComparison.Ordinal))
            .ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);

        // The documented switch-over (deployment.md §3): the T-200 kids stay in the ring as Retired, verify-only `file:` entries
        // (indices 10+, after the key tool's), pinned with their T-200 fingerprints.
        foreach (var (key, value) in file.Where(p => p.Key.StartsWith("Signing:Keys:", StringComparison.Ordinal)))
        {
            var rest = key["Signing:Keys:".Length..];
            var index = int.Parse(rest[..rest.IndexOf(':', StringComparison.Ordinal)], System.Globalization.CultureInfo.InvariantCulture);
            var field = rest[(rest.IndexOf(':', StringComparison.Ordinal) + 1)..];
            settings[$"Signing:Keys:{index + 10}:{field}"] = field == "Status" ? "Retired" : value;
        }

        foreach (var kid in new[] { RetiredSyncKid, RetiredEntitlementKid })
        {
            settings["Kms:OpenBao:Fingerprints:" + kid] = file["Kms:File:Fingerprints:" + kid];
        }

        settings["Kms:Provider"] = "OpenBao";
        settings["Kms:OpenBao:Address"] = Stub.Address.ToString();
        settings["Kms:OpenBao:CredentialDirectory"] = worker ? WorkerCredentials : ApiCredentials;
        settings["Kms:OpenBao:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "openbao:seat";
        settings["Kms:HmacKeys:Audit"] = "openbao:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "openbao:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "openbao:" + Envelope;
        if (worker)
        {
            settings["Kms:Scope"] = "Envelope";
        }

        foreach (var (key, value) in toolSettings)
        {
            // The tool prints new kids as Next; at the switch-over they become Active (one per purpose).
            settings[key] = key.EndsWith(":Status", StringComparison.Ordinal) ? "Active" : value;
        }

        return settings;
    }

    public static IEnumerable<KeyValuePair<string, string>> ParseEnvLines(string output)
    {
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (line.StartsWith('#'))
            {
                continue;
            }

            var split = line.IndexOf('=', StringComparison.Ordinal);
            yield return new(line[..split].Replace("__", ":", StringComparison.Ordinal), line[(split + 1)..]);
        }
    }

    public static void WritePrivate(string path, string content)
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }

        File.WriteAllText(path, content);
        File.SetUnixFileMode(path, FileKmsKeySet.Mode0400);
    }

    public static void WriteCredentials(string directory, (string RoleId, string SecretId) role, string caPem)
    {
        Directory.CreateDirectory(directory);
        File.SetUnixFileMode(directory, FileKmsKeySet.Mode0700);
        WritePrivate(Path.Combine(directory, RoleIdFile), role.RoleId + "\n");
        WritePrivate(Path.Combine(directory, SecretIdFile), role.SecretId + "\n");
        WritePrivate(Path.Combine(directory, CaFileName), caPem);
    }

    public async ValueTask DisposeAsync()
    {
        await Stub.DisposeAsync();
        Stub.Ca.Dispose();
        FileKeys.Dispose();
        foreach (var entry in Directory.EnumerateFileSystemEntries(Root, "*", SearchOption.AllDirectories))
        {
            if (Directory.Exists(entry))
            {
                File.SetUnixFileMode(entry, FileKmsKeySet.Mode0700);
            }
        }

        Directory.Delete(Root, recursive: true);
    }
}
