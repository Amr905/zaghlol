using System.Globalization;
using System.Net;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The OpenBao side of the T-200 → T-201 migration (T-201 design note §5): <c>dotnet Zaghlol.Workers.dll --openbao-keys …</c>.
/// Imports the File HMAC keys (as Transit <c>hmac</c> keys of the same names) and File envelope keys (as <c>aes256-gcm96</c>
/// keys <c>file-&lt;name&gt;</c>) by BYOK, verifies each import without reading key material back, and prints public values
/// only: the <c>Kms__OpenBao__Fingerprints__…</c> pins and the ring entries of signing keys made by <c>setup.sh</c>. A key
/// that already exists is verified, not imported again, so the tool can be re-run.
/// </summary>
public static class OpenBaoKeyTool
{
    public const string Flag = "--openbao-keys";

    public const int Ok = 0;
    public const int Failed = 1;
    public const int Usage = 2;

    private const string UsageText =
        "usage: --openbao-keys --environment Staging|Production|Testing --address <url> --token-file <file> [--ca-file <pem>] [--mount transit]\n"
        + "       [--file-keys <T-200 key directory>] [--import-hmac <name>]... [--import-envelope <name>]... [--kid <kid>]... [--envelope <name>]...\n"
        + "  --import-hmac      import <file-keys>/<name>.key as Transit hmac key <name> (seat, audit, install-pepper)\n"
        + "  --import-envelope  import <file-keys>/<name>.key as Transit aes256-gcm96 key file-<name> (opens old file:<name> envelopes)\n"
        + "  --kid              print the ring entry and pin of a Transit ecdsa-p256 key made by setup.sh\n"
        + "  --envelope         print the pin of a Transit envelope key made by setup.sh";

    private static readonly string[] Environments = ["Staging", "Production", "Testing", "Development"];

    /// <summary>Runs the tool; <paramref name="handler"/> replaces the TLS transport in tests.</summary>
    public static int Run(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr) => Run(args, stdout, stderr, handler: null);

    internal static int Run(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, HttpMessageHandler? handler)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(stdout);
        ArgumentNullException.ThrowIfNull(stderr);

        if (!TryParse(args, out var request, out var problem))
        {
            stderr.WriteLine("refused: " + problem);
            stderr.WriteLine(UsageText);
            return Usage;
        }

        if (!OperatingSystem.IsLinux())
        {
            stderr.WriteLine("refused: the OpenBao key tool runs on Linux only (it checks POSIX owner and mode of the key files).");
            return Usage;
        }

        try
        {
            return RunAsync(request, stdout, stderr, handler).GetAwaiter().GetResult();
        }
        catch (KmsConfigurationException ex)
        {
            // Constant messages only (they never name a path, key or value).
            stderr.WriteLine("refused: " + ex.Message);
            return Failed;
        }
        catch (Exception ex) when (ex is OpenBaoUnavailableException or KmsUnavailableException or CryptographicException or IOException)
        {
            stderr.WriteLine("failed: OpenBao refused or could not be reached (" + ex.GetType().Name + "); nothing printed is valid.");
            return Failed;
        }
    }

    [SupportedOSPlatform("linux")]
    private static async Task<int> RunAsync(Request request, TextWriter stdout, TextWriter stderr, HttpMessageHandler? handler)
    {
        var euid = PosixFiles.EffectiveUid() ?? throw new KmsConfigurationException(FileKms.DirectoryUnreadableMessage);
        var token = ReadToken(request.TokenFile, euid);
        X509Certificate2Collection? roots = null;
        if (request.Address.Scheme == Uri.UriSchemeHttps)
        {
            roots = ReadCa(request.CaFile!, euid);
        }

        string? keyDirectory = null;
        if (request.ImportHmac.Count + request.ImportEnvelope.Count > 0)
        {
            keyDirectory = FileKms.CheckDirectory(request.FileKeys, euid);
            if (FileKms.IsInSourceTree(keyDirectory))
            {
                throw new KmsConfigurationException(FileKms.SourceTreeMessage);
            }

            FileKms.CheckEntries(keyDirectory, euid);
        }

        using var client = OpenBaoClient.WithToken(request.Address, handler ?? OpenBaoClient.CreateHandler(roots, TimeSpan.FromSeconds(10)), token, TimeProvider.System);
        using var kms = OpenBaoKms.ForTool(client, request.Mount);
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var ct = timeout.Token;
        var lines = new List<string>();
        RSA? wrappingKey = null;
        try
        {
            foreach (var name in request.ImportHmac)
            {
                var secret = LoadFileSecret(keyDirectory!, name, euid);
                try
                {
                    var role = new OpenBaoKms.KeyRole(name, OpenBaoKms.KeyKind.Hmac);
                    if (!await ExistsAsync(client, request.Mount, name, ct))
                    {
                        wrappingKey ??= await WrappingKeyAsync(client, request.Mount, ct);
                        await ImportAsync(client, request.Mount, name, "hmac", wrappingKey, secret, ct);
                        stderr.WriteLine("imported: hmac key " + name);
                    }
                    else
                    {
                        stderr.WriteLine("exists: hmac key " + name + " (verifying, not importing)");
                    }

                    await CheckAsync(kms, role, ct);
                    var pin = Convert.ToHexStringLower(await kms.TransitHmacAsync(name, OpenBaoKms.PinLabel, ct));
                    if (!string.Equals(pin, KeyFingerprints.OfSecret(secret), StringComparison.Ordinal))
                    {
                        throw new KmsConfigurationException("The OpenBao key " + name + " is not the File key of that name (its fingerprint differs); nothing was changed by this check.");
                    }

                    lines.Add("Kms__OpenBao__Fingerprints__" + ShellName(name) + "=" + pin);
                    lines.Add("# " + name + ": same value as Kms__File__Fingerprints__" + ShellName(name) + " (the import is the same key)");
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(secret);
                }
            }

            var previous = 0;
            foreach (var name in request.ImportEnvelope)
            {
                var transitName = OpenBaoKms.LegacyTransitPrefix + name;
                var secret = LoadFileSecret(keyDirectory!, name, euid);
                try
                {
                    var role = new OpenBaoKms.KeyRole(transitName, OpenBaoKms.KeyKind.LegacyEnvelope);
                    if (!await ExistsAsync(client, request.Mount, transitName, ct))
                    {
                        wrappingKey ??= await WrappingKeyAsync(client, request.Mount, ct);
                        await ImportAsync(client, request.Mount, transitName, "aes256-gcm96", wrappingKey, secret, ct);
                        stderr.WriteLine("imported: envelope key " + transitName);
                    }
                    else
                    {
                        stderr.WriteLine("exists: envelope key " + transitName + " (verifying, not importing)");
                    }

                    await CheckAsync(kms, role, ct);
                    await VerifyLegacyEnvelopeAsync(client, request.Mount, transitName, FileKms.Prefix + name, secret, ct);
                    var pin = Convert.ToHexStringLower(await kms.TransitHmacAsync(transitName, OpenBaoKms.PinLabel, ct));
                    lines.Add("Kms__OpenBao__Fingerprints__" + ShellName(transitName) + "=" + pin);
                    lines.Add(string.Create(CultureInfo.InvariantCulture, $"Kms__Envelope__PreviousKeyRefs__{previous++}={FileKms.Prefix}{name}"));
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(secret);
                }
            }

            var index = 0;
            foreach (var kid in request.Kids)
            {
                var info = await CheckAsync(kms, new OpenBaoKms.KeyRole(kid, OpenBaoKms.KeyKind.Signing), ct);
                var jwk = EcPublicJwk.FromX963(info.PublicKeyPoint!);
                var prefix = string.Create(CultureInfo.InvariantCulture, $"Signing__Keys__{index++}__");
                lines.Add(prefix + "Kid=" + kid);
                lines.Add(prefix + "Purpose=" + (kid[0] == 's' ? "Sync" : "Entitlement"));
                lines.Add(prefix + "Status=Next");
                lines.Add(prefix + "KeyRef=" + OpenBaoKms.Prefix + kid);
                lines.Add(prefix + "PublicJwk__Kty=" + jwk.Kty);
                lines.Add(prefix + "PublicJwk__Crv=" + jwk.Crv);
                lines.Add(prefix + "PublicJwk__X=" + jwk.X);
                lines.Add(prefix + "PublicJwk__Y=" + jwk.Y);
                lines.Add("Kms__OpenBao__Fingerprints__" + ShellName(kid) + "=" + info.PublicKeyFingerprint);
            }

            foreach (var name in request.Envelopes)
            {
                _ = await CheckAsync(kms, new OpenBaoKms.KeyRole(name, OpenBaoKms.KeyKind.Envelope), ct);
                lines.Add("Kms__OpenBao__Fingerprints__" + ShellName(name) + "=" + Convert.ToHexStringLower(await kms.TransitHmacAsync(name, OpenBaoKms.PinLabel, ct)));
            }
        }
        finally
        {
            wrappingKey?.Dispose();
        }

        stdout.WriteLine("# Zaghlol OpenBao KMS for " + request.Environment + " (T-201). Public values only: pins and ring entries.");
        stdout.WriteLine("# Renumber Signing__Keys__<n> to fit the ring; set Status=Active only per the rotation rules (deployment.md section 3).");
        foreach (var line in lines)
        {
            stdout.WriteLine(line);
        }

        return Ok;
    }

    /// <summary>
    /// The BYOK ciphertext (OpenBao <c>wrapTargetPKCS8ForImport</c>): <c>RSA-OAEP-SHA256(ephemeral AES-256 key)</c> (512 bytes)
    /// followed by <c>AES-KWP(ephemeral, key)</c> (RFC 5649), base64. The ephemeral key is zeroed.
    /// </summary>
    internal static string ImportCiphertext(RSA wrappingKey, ReadOnlySpan<byte> key)
    {
        var ephemeral = GC.AllocateArray<byte>(32, pinned: true);
        try
        {
            RandomNumberGenerator.Fill(ephemeral);
            var wrappedEphemeral = wrappingKey.Encrypt(ephemeral, RSAEncryptionPadding.OaepSHA256);
            using var aes = Aes.Create();
            aes.Key = ephemeral;
            var wrappedKey = aes.EncryptKeyWrapPadded(key);
            return Convert.ToBase64String([.. wrappedEphemeral, .. wrappedKey]);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(ephemeral);
        }
    }

    private static async Task<bool> ExistsAsync(OpenBaoClient client, string mount, string name, CancellationToken ct)
    {
        using var answer = await client.SendAsync(HttpMethod.Get, $"{mount}/keys/{name}", body: null, ct);
        return answer.Status switch
        {
            HttpStatusCode.OK => true,
            HttpStatusCode.NotFound => false,
            _ => throw new OpenBaoUnavailableException(),
        };
    }

    private static async Task<RSA> WrappingKeyAsync(OpenBaoClient client, string mount, CancellationToken ct)
    {
        using var answer = await client.SendAsync(HttpMethod.Get, $"{mount}/wrapping_key", body: null, ct);
        if (!answer.IsSuccess
            || answer.Data is not { } data
            || !data.TryGetProperty("public_key", out var pem)
            || pem.ValueKind != System.Text.Json.JsonValueKind.String)
        {
            throw new OpenBaoUnavailableException();
        }

        var rsa = RSA.Create();
        try
        {
            rsa.ImportFromPem(pem.GetString());
            if (rsa.KeySize != 4096)
            {
                throw new KmsConfigurationException("The OpenBao wrapping key is not a 4096-bit RSA key; refusing to import.");
            }

            return rsa;
        }
        catch (Exception ex) when (ex is ArgumentException or CryptographicException)
        {
            rsa.Dispose();
            throw new KmsConfigurationException("The OpenBao wrapping key is not a 4096-bit RSA key; refusing to import.");
        }
        catch
        {
            rsa.Dispose();
            throw;
        }
    }

    private static async Task ImportAsync(OpenBaoClient client, string mount, string name, string type, RSA wrappingKey, byte[] secret, CancellationToken ct)
    {
        var ciphertext = ImportCiphertext(wrappingKey, secret);
        using var answer = await client.SendAsync(
            HttpMethod.Post,
            $"{mount}/keys/{name}/import",
            w =>
            {
                w.WriteString("type", type);
                w.WriteString("ciphertext", ciphertext);
                w.WriteString("hash_function", "SHA256");
                w.WriteBoolean("exportable", false);
                w.WriteBoolean("allow_plaintext_backup", false);
                w.WriteBoolean("allow_rotation", false);
            },
            ct);

        if (!answer.IsSuccess)
        {
            throw new OpenBaoUnavailableException();
        }
    }

    private static async Task<OpenBaoKms.KeyInfo> CheckAsync(OpenBaoKms kms, OpenBaoKms.KeyRole role, CancellationToken ct)
    {
        var info = await kms.ReadKeyAsync(role.TransitName, ct);
        OpenBaoKms.CheckAttributes(role, info);
        return info;
    }

    /// <summary>A File-format wrap of a random test key, made here, must open in Transit: the import is the File KEK.</summary>
    private static async Task VerifyLegacyEnvelopeAsync(OpenBaoClient client, string mount, string transitName, string keyRef, byte[] kek, CancellationToken ct)
    {
        var probe = RandomNumberGenerator.GetBytes(DataKey.Size);
        try
        {
            var wrapped = FileKms.Wrap(kek, keyRef, probe);
            using var answer = await client.SendAsync(
                HttpMethod.Post,
                $"{mount}/decrypt/{transitName}",
                w =>
                {
                    w.WriteString("ciphertext", "vault:v1:" + Convert.ToBase64String(wrapped));
                    w.WriteString("associated_data", Convert.ToBase64String(FileKms.WrapAad(keyRef)));
                },
                ct);

            byte[]? opened = null;
            try
            {
                if (!answer.IsSuccess
                    || answer.Data is not { } data
                    || !data.TryGetProperty("plaintext", out var plaintext)
                    || !plaintext.TryGetBytesFromBase64(out opened)
                    || !CryptographicOperations.FixedTimeEquals(opened, probe))
                {
                    throw new KmsConfigurationException("The OpenBao key " + transitName + " does not open envelopes of the File key it should hold.");
                }
            }
            finally
            {
                if (opened is not null)
                {
                    CryptographicOperations.ZeroMemory(opened);
                }
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(probe);
        }
    }

    [SupportedOSPlatform("linux")]
    private static byte[] LoadFileSecret(string directory, string name, uint euid)
    {
        var secret = FileKms.LoadSecret(directory, FileKms.Prefix + name, euid);
        if (KnownTestKeys.IsDegenerate(secret) || KnownTestKeys.Secrets.Contains(KeyFingerprints.OfSecret(secret)))
        {
            CryptographicOperations.ZeroMemory(secret);
            throw new KmsConfigurationException(FileKms.KnownTestKeyMessage);
        }

        return secret;
    }

    [SupportedOSPlatform("linux")]
    private static string ReadToken(string path, uint euid)
    {
        var (buffer, length) = FileKms.ReadChecked(Path.GetFullPath(path), euid);
        try
        {
            var text = buffer.AsSpan(0, length);
            if (text.EndsWith("\n"u8))
            {
                text = text[..^1];
            }

            if (text.Length is 0 or > 1024 || text.ContainsAnyExceptInRange((byte)0x21, (byte)0x7E))
            {
                throw new KmsConfigurationException("--token-file must hold one OpenBao token (printable characters, no spaces).");
            }

            return Encoding.ASCII.GetString(text);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(buffer);
        }
    }

    [SupportedOSPlatform("linux")]
    private static X509Certificate2Collection ReadCa(string path, uint euid)
    {
        var (buffer, length) = FileKms.ReadChecked(Path.GetFullPath(path), euid);
        try
        {
            var roots = new X509Certificate2Collection();
            roots.ImportFromPem(Encoding.ASCII.GetString(buffer, 0, length));
            return roots.Count > 0 ? roots : throw new KmsConfigurationException(OpenBaoKms.CaMessage);
        }
        catch (CryptographicException)
        {
            throw new KmsConfigurationException(OpenBaoKms.CaMessage);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(buffer);
        }
    }

    private static string ShellName(string name) => name.Replace('-', '_');

    private static bool TryParse(IReadOnlyList<string> args, out Request request, out string problem)
    {
        request = null!;
        string? environment = null, address = null, tokenFile = null, caFile = null, fileKeys = null, mount = null;
        var importHmac = new List<string>();
        var importEnvelope = new List<string>();
        var kids = new List<string>();
        var envelopes = new List<string>();

        for (var i = 0; i < args.Count; i++)
        {
            var arg = args[i];
            if (arg == Flag)
            {
                continue;
            }

            if (i + 1 >= args.Count)
            {
                problem = "an option is missing its value.";
                return false;
            }

            var value = args[++i];
            switch (arg)
            {
                case "--environment": environment = value; break;
                case "--address": address = value; break;
                case "--token-file": tokenFile = value; break;
                case "--ca-file": caFile = value; break;
                case "--file-keys": fileKeys = value; break;
                case "--mount": mount = value; break;
                case "--import-hmac": importHmac.Add(value); break;
                case "--import-envelope": importEnvelope.Add(value); break;
                case "--kid": kids.Add(value); break;
                case "--envelope": envelopes.Add(value); break;
                default:
                    // Never echo the argument: it could be a pasted secret.
                    problem = "unknown option.";
                    return false;
            }
        }

        if (environment is null || !Environments.Contains(environment, StringComparer.Ordinal))
        {
            problem = "--environment must be Staging, Production, Testing or Development.";
            return false;
        }

        var lax = environment is "Testing" or "Development";
        if (address is null
            || !Uri.TryCreate(address, UriKind.Absolute, out var uri)
            || !(uri.Scheme == Uri.UriSchemeHttps || (uri.Scheme == Uri.UriSchemeHttp && lax))
            || uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0 || uri.AbsolutePath != "/")
        {
            problem = "--address must be an https URL with no path (http only for Testing or Development).";
            return false;
        }

        if (uri.Scheme == Uri.UriSchemeHttps && caFile is null)
        {
            problem = "--ca-file is required for https (the CA that signed OpenBao's certificate).";
            return false;
        }

        if (tokenFile is null)
        {
            problem = "--token-file is required (a short-lived token with the zaghlol-keytool policy).";
            return false;
        }

        mount ??= "transit";
        var names = importHmac.Concat(envelopes).Concat(importEnvelope.Select(n => OpenBaoKms.LegacyTransitPrefix + n)).Concat(kids).ToList();
        if (!FileKms.NamePattern().IsMatch(mount)
            || names.Any(n => !FileKms.NamePattern().IsMatch(n))
            || importEnvelope.Any(n => !FileKms.NamePattern().IsMatch(n)))
        {
            problem = "names must be a-z, 0-9 and '-' (at most 63 characters, file-<name> included).";
            return false;
        }

        if (kids.Any(k => !KmsSettings.KidPattern().IsMatch(k) || k.AsSpan(1, 4).SequenceEqual("0000")))
        {
            problem = "a kid must match ^[se][0-9]{4}[a-z]$ and not use year 0000.";
            return false;
        }

        if (names.Distinct(StringComparer.Ordinal).Count() != names.Count)
        {
            problem = "a name repeats.";
            return false;
        }

        if (names.Count == 0)
        {
            problem = "nothing to do.";
            return false;
        }

        if (importHmac.Count + importEnvelope.Count > 0 && fileKeys is null)
        {
            problem = "--file-keys is required to import (the T-200 key directory, mounted read-only).";
            return false;
        }

        request = new Request(environment, uri, tokenFile, caFile, fileKeys, mount, importHmac, importEnvelope, kids, envelopes);
        problem = string.Empty;
        return true;
    }

    private sealed record Request(
        string Environment,
        Uri Address,
        string TokenFile,
        string? CaFile,
        string? FileKeys,
        string Mount,
        List<string> ImportHmac,
        List<string> ImportEnvelope,
        List<string> Kids,
        List<string> Envelopes);
}
