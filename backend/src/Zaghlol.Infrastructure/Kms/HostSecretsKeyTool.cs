using System.Buffers.Text;
using System.Globalization;
using System.Security.Cryptography;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The key tool of the HostSecrets provider (T-205, ADR-026), reached through the T-200 tool:
/// <c>dotnet Zaghlol.Workers.dll --generate-keys --format host-secrets --environment Staging|Production</c> then either
/// <c>[--kid s2026a]… [--secret seat]…</c> (new keys) or <c>--from-dir &lt;File KMS key directory&gt;</c> (convert). It prints the
/// <c>ZAGHLOL_KEYS__&lt;name&gt;</c> settings (private: one GitHub environment secret each) and the public settings to stdout, once.
/// It never writes a file, runs on Windows and Linux, and refuses to run inside a source tree.
/// </summary>
public static class HostSecretsKeyTool
{
    public const string FormatFlag = "--format";
    public const string FormatName = "host-secrets";

    private const string UsageText =
        "usage: --generate-keys --format host-secrets --environment Staging|Production ([--kid <kid>]... [--secret <name>]... | --from-dir <File KMS key directory>)\n"
        + "  --kid       a new P-256 signing key, kid ^[se][0-9]{4}[a-z]$ (s = Sync, e = Entitlement; not year 0000)\n"
        + "  --secret    a new 32-byte key name ([a-z0-9][a-z0-9-]*), e.g. seat, audit, install-pepper, envelope\n"
        + "  --from-dir  print the keys of an existing File KMS directory (<kid>.pem, <name>.key) as host settings";

    /// <summary>Runs the tool. <paramref name="workingDirectory"/> is the caller's current directory.</summary>
    public static int Run(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, string workingDirectory)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(stdout);
        ArgumentNullException.ThrowIfNull(stderr);
        ArgumentNullException.ThrowIfNull(workingDirectory);

        if (!TryParse(args, out var request, out var problem))
        {
            stderr.WriteLine("refused: " + problem);
            stderr.WriteLine(UsageText);
            return FileKeyTool.Usage;
        }

        // The output holds private keys: a redirect into a checkout must not be possible by accident.
        if (FileKms.IsInSourceTree(workingDirectory))
        {
            stderr.WriteLine("refused: the current directory is inside a source tree (.git or Zaghlol.sln above it); run the tool elsewhere.");
            return FileKeyTool.Usage;
        }

        var secretLines = new List<string>();
        var publicLines = new List<string>();
        try
        {
            if (request.FromDirectory is { } directory)
            {
                if (!Convert(directory, secretLines, publicLines, stderr))
                {
                    return FileKeyTool.Usage;
                }
            }
            else
            {
                Generate(request, secretLines, publicLines);
            }
        }
        catch (CryptographicException ex)
        {
            stderr.WriteLine("failed: could not create the keys (" + ex.GetType().Name + "); nothing was printed.");
            return FileKeyTool.Failed;
        }

        stdout.WriteLine("# Zaghlol HostSecrets keys for " + request.Environment + " (T-205, ADR-026). Printed once; nothing was written to disk.");
        stdout.WriteLine("# PRIVATE: each ZAGHLOL_KEYS__ line is a key. Store each as a GitHub environment secret (" + request.Environment + "),");
        stdout.WriteLine("# keep the offline backup of deployment.md section 'MonsterASP.NET + Aiven', then clear this terminal. Never commit them.");
        foreach (var line in secretLines)
        {
            stdout.WriteLine(line);
        }

        stdout.WriteLine("# PUBLIC: settings that may live in appsettings." + request.Environment + ".json or the host settings.");
        stdout.WriteLine("# Set Kms__AcceptSharedHostCustody=true yourself, after reading ADR-026.");
        stdout.WriteLine("Kms__Provider=" + HostSecretsKms.ProviderName);
        foreach (var line in publicLines)
        {
            stdout.WriteLine(line);
        }

        return FileKeyTool.Ok;
    }

    private static void Generate(Request request, List<string> secretLines, List<string> publicLines)
    {
        var index = 0;
        foreach (var kid in request.Kids)
        {
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            secretLines.Add(SettingLine(kid, PemOf(key), isPem: true));
            var q = key.ExportParameters(includePrivateParameters: false).Q;
            var jwk = EcPublicJwk.FromX963([0x04, .. q.X!, .. q.Y!]);
            var prefix = string.Create(CultureInfo.InvariantCulture, $"Signing__Keys__{index++}__");
            publicLines.Add(prefix + "Kid=" + kid);
            publicLines.Add(prefix + "Purpose=" + (kid[0] == 's' ? "Sync" : "Entitlement"));
            publicLines.Add(prefix + "Status=Next");
            publicLines.Add(prefix + "KeyRef=" + FileKms.Prefix + kid);
            publicLines.Add(prefix + "PublicJwk__Kty=" + jwk.Kty);
            publicLines.Add(prefix + "PublicJwk__Crv=" + jwk.Crv);
            publicLines.Add(prefix + "PublicJwk__X=" + jwk.X);
            publicLines.Add(prefix + "PublicJwk__Y=" + jwk.Y);
            publicLines.Add("Kms__File__Fingerprints__" + ShellName(kid) + "=" + KeyFingerprints.OfSigningKey(key));
        }

        foreach (var name in request.Secrets)
        {
            var secret = GC.AllocateArray<byte>(DataKey.Size, pinned: true);
            try
            {
                RandomNumberGenerator.Fill(secret);
                AddSecret(name, secret, secretLines, publicLines);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(secret);
            }
        }
    }

    /// <summary>
    /// <c>--from-dir</c>: every <c>&lt;name&gt;.pem</c> and <c>&lt;name&gt;.key</c> in the folder (not recursive), each parsed and
    /// checked like the providers do (committed or degenerate keys refused). Other files are ignored; <c>kms.env</c> (written by
    /// <c>dev-keys.sh</c>), links, oversized files and bad names refuse the run. Messages name no file.
    /// </summary>
    private static bool Convert(string directory, List<string> secretLines, List<string> publicLines, TextWriter stderr)
    {
        List<string> entries;
        try
        {
            entries = [.. Directory.EnumerateFileSystemEntries(directory, "*", SearchOption.TopDirectoryOnly).Order(StringComparer.Ordinal)];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            stderr.WriteLine("refused: --from-dir can't be listed.");
            return false;
        }

        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var path in entries)
        {
            var fileName = Path.GetFileName(path);
            if (string.Equals(fileName, FileKms.DevKeysMarker, StringComparison.Ordinal))
            {
                stderr.WriteLine("refused: --from-dir holds kms.env (dev-keys.sh output); development keys are never converted.");
                return false;
            }

            var extension = Path.GetExtension(fileName);
            if (extension is not (".pem" or ".key"))
            {
                continue;
            }

            var name = Path.GetFileNameWithoutExtension(fileName);
            if (!FileKms.NamePattern().IsMatch(name) || !seen.Add(name))
            {
                stderr.WriteLine("refused: a key file name in --from-dir is not a valid key name, or a name is used twice.");
                return false;
            }

            var bytes = ReadKeyFile(path);
            if (bytes is null)
            {
                stderr.WriteLine("refused: a key file in --from-dir is a link, unreadable or larger than 8 KiB.");
                return false;
            }

            try
            {
                if (extension == ".pem")
                {
                    using var key = FileKms.ParseEcPem(bytes, HostSecretsKms.Messages);
                    var fingerprint = KeyFingerprints.OfSigningKey(key);
                    if (KnownTestKeys.SigningKeys.Contains(fingerprint))
                    {
                        throw new KmsConfigurationException(HostSecretsKms.KnownTestKeyMessage);
                    }

                    secretLines.Add(SettingLine(name, PemOf(key), isPem: true));
                    publicLines.Add("Kms__File__Fingerprints__" + ShellName(name) + "=" + fingerprint);
                }
                else
                {
                    var secret = FileKms.ParseSecret(bytes, HostSecretsKms.Messages);
                    try
                    {
                        if (KnownTestKeys.IsDegenerate(secret) || KnownTestKeys.Secrets.Contains(KeyFingerprints.OfSecret(secret)))
                        {
                            throw new KmsConfigurationException(HostSecretsKms.KnownTestKeyMessage);
                        }

                        AddSecret(name, secret, secretLines, publicLines);
                    }
                    finally
                    {
                        CryptographicOperations.ZeroMemory(secret);
                    }
                }
            }
            catch (KmsConfigurationException ex)
            {
                stderr.WriteLine("refused: " + ex.Message);
                return false;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }

        if (secretLines.Count == 0)
        {
            stderr.WriteLine("refused: --from-dir holds no .pem or .key file.");
            return false;
        }

        return true;
    }

    private static byte[]? ReadKeyFile(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.LinkTarget is not null || (info.Attributes & FileAttributes.ReparsePoint) != 0 || info.Length > FileKms.MaxFileBytes)
            {
                return null;
            }

            using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var buffer = GC.AllocateArray<byte>(FileKms.MaxFileBytes + 1, pinned: true);
            var total = 0;
            int read;
            while (total < buffer.Length && (read = RandomAccess.Read(handle, buffer.AsSpan(total), total)) > 0)
            {
                total += read;
            }

            if (total > FileKms.MaxFileBytes)
            {
                CryptographicOperations.ZeroMemory(buffer);
                return null;
            }

            var exact = GC.AllocateArray<byte>(total, pinned: true);
            buffer.AsSpan(0, total).CopyTo(exact);
            CryptographicOperations.ZeroMemory(buffer);
            return exact;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static void AddSecret(string name, ReadOnlySpan<byte> secret, List<string> secretLines, List<string> publicLines)
    {
        var text = GC.AllocateArray<byte>(44, pinned: true);
        try
        {
            if (Base64.EncodeToUtf8(secret, text, out _, out var length) != System.Buffers.OperationStatus.Done || length != 44)
            {
                throw new CryptographicException();
            }

            secretLines.Add(SettingLine(name, text, isPem: false));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(text);
        }

        publicLines.Add("Kms__File__Fingerprints__" + ShellName(name) + "=" + KeyFingerprints.OfSecret(secret));
        if (name == "seat" || name.StartsWith("seat-", StringComparison.Ordinal))
        {
            publicLines.Add("Kms__HmacKeys__SeatCheck=" + System.Convert.ToHexStringLower(HMACSHA256.HashData(secret, "zaghlol-kseat-check-v1"u8)));
        }
    }

    /// <summary>The PKCS#8 PEM text of <paramref name="key"/> with a trailing newline, as the T-200 tool writes it (pinned; caller zeroes).</summary>
    private static byte[] PemOf(ECDsa key)
    {
        var der = GC.AllocateArray<byte>(512, pinned: true);
        char[]? chars = null;
        try
        {
            if (!key.TryExportPkcs8PrivateKey(der, out var derLength))
            {
                throw new CryptographicException();
            }

            chars = GC.AllocateArray<char>(PemEncoding.GetEncodedSize("PRIVATE KEY".Length, derLength), pinned: true);
            if (!PemEncoding.TryWrite("PRIVATE KEY", der.AsSpan(0, derLength), chars, out var written) || written != chars.Length)
            {
                throw new CryptographicException();
            }

            var bytes = GC.AllocateArray<byte>(chars.Length + 1, pinned: true);
            for (var i = 0; i < chars.Length; i++)
            {
                bytes[i] = (byte)chars[i];
            }

            bytes[^1] = (byte)'\n';
            return bytes;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(der);
            if (chars is not null)
            {
                Array.Clear(chars);
            }
        }
    }

    /// <summary>
    /// <c>ZAGHLOL_KEYS__&lt;name&gt;=</c> + base64url(<c>{"zaghlol":"host-key-v1","name":…,"pem"|"key":…}</c>). The text is PEM
    /// (ASCII letters, digits, <c>+/=-</c>, space, newline) or base64, so only the newline needs a JSON escape. Zeroes
    /// <paramref name="text"/> when <paramref name="isPem"/> (the caller owns the base64 buffer otherwise).
    /// </summary>
    internal static string SettingLine(string name, byte[] text, bool isPem)
    {
        var json = BuildJson(name, text, isPem);
        try
        {
            return "ZAGHLOL_KEYS__" + ShellName(name) + "=" + Base64Url.EncodeToString(json);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(json);
            if (isPem)
            {
                CryptographicOperations.ZeroMemory(text);
            }
        }
    }

    /// <summary>The JSON of one setting value, in a pinned array the caller zeroes.</summary>
    internal static byte[] BuildJson(string name, ReadOnlySpan<byte> text, bool isPem)
    {
        var head = HostSecretsKms.JsonHeader;
        var middle = System.Text.Encoding.ASCII.GetBytes(",\"name\":\"" + name + "\",\"" + (isPem ? "pem" : "key") + "\":\"");
        var escapes = text.Count((byte)'\n');
        var json = GC.AllocateArray<byte>(head.Length + middle.Length + text.Length + escapes + 2, pinned: true);
        var at = 0;
        head.CopyTo(json, at);
        at += head.Length;
        middle.CopyTo(json, at);
        at += middle.Length;
        foreach (var b in text)
        {
            if (b == (byte)'\n')
            {
                json[at++] = (byte)'\\';
                json[at++] = (byte)'n';
            }
            else if (b is < 0x20 or > 0x7E or (byte)'"' or (byte)'\\')
            {
                CryptographicOperations.ZeroMemory(json);
                throw new CryptographicException();
            }
            else
            {
                json[at++] = b;
            }
        }

        json[at++] = (byte)'"';
        json[at] = (byte)'}';
        return json;
    }

    /// <summary>Review C7 (T-200): names a POSIX shell and GitHub accept ('-' becomes '_'; the provider reads both).</summary>
    private static string ShellName(string name) => name.Replace('-', '_');

    private static bool TryParse(IReadOnlyList<string> args, out Request request, out string problem)
    {
        request = default!;
        string? environment = null;
        string? format = null;
        string? fromDirectory = null;
        var kids = new List<string>();
        var secrets = new List<string>();
        for (var i = 0; i < args.Count; i++)
        {
            var arg = args[i];
            if (arg == FileKeyTool.Flag)
            {
                continue;
            }

            if (arg is not ("--environment" or FormatFlag or "--kid" or "--secret" or "--from-dir"))
            {
                // The unknown argument is not echoed.
                problem = "unknown argument";
                return false;
            }

            if (i + 1 >= args.Count)
            {
                problem = arg + " needs a value";
                return false;
            }

            var value = args[++i];
            switch (arg)
            {
                case "--environment" when environment is null:
                    environment = value;
                    break;
                case FormatFlag when format is null:
                    format = value;
                    break;
                case "--from-dir" when fromDirectory is null:
                    fromDirectory = value;
                    break;
                case "--kid":
                    kids.Add(value);
                    break;
                case "--secret":
                    secrets.Add(value);
                    break;
                default:
                    problem = arg + " given twice";
                    return false;
            }
        }

        if (format != FormatName)
        {
            problem = "--format must be host-secrets";
            return false;
        }

        if (environment is not ("Staging" or "Production"))
        {
            problem = "--environment must be Staging or Production";
            return false;
        }

        if (fromDirectory is not null)
        {
            if (kids.Count + secrets.Count != 0)
            {
                problem = "--from-dir can't be combined with --kid or --secret";
                return false;
            }

            if (!Path.IsPathFullyQualified(fromDirectory) || !Directory.Exists(fromDirectory))
            {
                problem = "--from-dir must be an absolute path to an existing directory";
                return false;
            }
        }
        else if (kids.Count + secrets.Count == 0)
        {
            problem = "nothing to generate (give --kid and/or --secret, or --from-dir)";
            return false;
        }

        if (kids.Any(k => !KmsSettings.KidPattern().IsMatch(k) || k.AsSpan(1, 4).SequenceEqual("0000")))
        {
            problem = "a kid must match ^[se][0-9]{4}[a-z]$ and not use year 0000";
            return false;
        }

        if (secrets.Any(s => !FileKms.NamePattern().IsMatch(s)))
        {
            problem = "a secret name must match ^[a-z0-9][a-z0-9-]{0,62}$";
            return false;
        }

        if (kids.Concat(secrets).Distinct(StringComparer.Ordinal).Count() != kids.Count + secrets.Count)
        {
            problem = "a name is repeated";
            return false;
        }

        request = new Request(environment, fromDirectory, kids, secrets);
        problem = string.Empty;
        return true;
    }

    private sealed record Request(string Environment, string? FromDirectory, IReadOnlyList<string> Kids, IReadOnlyList<string> Secrets);
}
