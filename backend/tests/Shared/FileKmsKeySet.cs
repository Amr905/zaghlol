using System.Buffers.Text;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Testing;

/// <summary>
/// T-200: a File KMS key directory in a fresh temp folder (mode 0700, files 0400), the way the production key tool lays it
/// out, and the matching settings: provider, directory, fingerprints, key ring, HMAC and envelope refs and <c>SeatCheck</c>.
/// Linux only. Every key is random per instance; <see cref="Sentinels"/> lists text that must never reach a log or message.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class FileKmsKeySet : IDisposable
{
    public const UnixFileMode Mode0700 = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;
    public const UnixFileMode Mode0400 = UnixFileMode.UserRead;

    public static readonly string[] SecretNames = ["seat", "audit", "install-pepper", "envelope"];

    private readonly Dictionary<string, string?> settings = new(StringComparer.Ordinal);
    private readonly List<string> sentinels = [];

    /// <param name="subPath">Folders between the temp root and <c>keys</c> (created 0755), for the parent-folder tests.</param>
    public FileKmsKeySet(string? subPath = null, string syncKid = "s2026a", string entitlementKid = "e2026a")
    {
        Root = System.IO.Directory.CreateTempSubdirectory("zaghlol-file-kms-").FullName;
        File.SetUnixFileMode(Root, Mode0700);
        var parentDirectory = subPath is null ? Root : Path.Combine(Root, subPath);
        System.IO.Directory.CreateDirectory(parentDirectory);
        Directory = Path.Combine(parentDirectory, "keys");
        System.IO.Directory.CreateDirectory(Directory);
        File.SetUnixFileMode(Directory, Mode0700);

        settings["Kms:Provider"] = "File";
        settings["Kms:File:KeyDirectory"] = Directory;
        settings["Kms:File:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "file:seat";
        settings["Kms:HmacKeys:Audit"] = "file:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "file:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "file:envelope";
        settings["ForwardedHeaders:NoProxy"] = "true";

        var index = 0;
        foreach (var (kid, purpose) in new[] { (syncKid, "Sync"), (entitlementKid, "Entitlement") })
        {
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            WriteSigningKey(kid, key);
            var q = key.ExportParameters(false).Q;
            var prefix = string.Create(CultureInfo.InvariantCulture, $"Signing:Keys:{index++}:");
            settings[prefix + "Kid"] = kid;
            settings[prefix + "Purpose"] = purpose;
            settings[prefix + "Status"] = "Active";
            settings[prefix + "KeyRef"] = "file:" + kid;
            settings[prefix + "PublicJwk:Kty"] = "EC";
            settings[prefix + "PublicJwk:Crv"] = "P-256";
            settings[prefix + "PublicJwk:X"] = Base64Url.EncodeToString(q.X!);
            settings[prefix + "PublicJwk:Y"] = Base64Url.EncodeToString(q.Y!);
        }

        foreach (var name in SecretNames)
        {
            WriteSecret(name, RandomNumberGenerator.GetBytes(32));
        }
    }

    /// <summary>The temp folder this instance owns (deleted on dispose).</summary>
    public string Root { get; }

    /// <summary>The key directory (<c>Kms:File:KeyDirectory</c>).</summary>
    public string Directory { get; }

    /// <summary>Key text and key bytes (base64, hex, PEM lines): none of it may appear in a log, message or output.</summary>
    public IReadOnlyList<string> Sentinels => sentinels;

    /// <summary>A copy of the settings; change it freely.</summary>
    public Dictionary<string, string?> Settings() => new(settings, StringComparer.Ordinal);

    /// <summary>Writes <c>&lt;name&gt;.pem</c> (mode 0400) and pins its fingerprint.</summary>
    public void WriteSigningKey(string name, ECDsa key)
    {
        var pem = key.ExportPkcs8PrivateKeyPem();
        Write(name + ".pem", pem);
        settings["Kms:File:Fingerprints:" + name] = KeyFingerprints.OfSigningKey(key);
        sentinels.AddRange(pem.Split('\n').Where(l => l.Length >= 16 && !l.StartsWith("-----", StringComparison.Ordinal)));
    }

    /// <summary>Writes <c>&lt;name&gt;.key</c> (base64 + newline, mode 0400) and pins its fingerprint; for seat, also SeatCheck.</summary>
    public void WriteSecret(string name, byte[] secret)
    {
        Write(name + ".key", Convert.ToBase64String(secret) + "\n");
        settings["Kms:File:Fingerprints:" + name] = KeyFingerprints.OfSecret(secret);
        if (name == "seat")
        {
            settings["Kms:HmacKeys:SeatCheck"] = Convert.ToHexStringLower(HMACSHA256.HashData(secret, "zaghlol-kseat-check-v1"u8));
        }

        sentinels.Add(Convert.ToBase64String(secret));
        sentinels.Add(Convert.ToHexStringLower(secret));
    }

    /// <summary>Writes a file into the key directory, replacing any old one, with mode 0400.</summary>
    public string Write(string fileName, string content)
    {
        var path = Path.Combine(Directory, fileName);
        if (File.Exists(path))
        {
            File.Delete(path);
        }

        File.WriteAllText(path, content);
        File.SetUnixFileMode(path, Mode0400);
        return path;
    }

    /// <summary>The secret bytes of a <c>.key</c> file.</summary>
    public byte[] ReadSecret(string name) => Convert.FromBase64String(File.ReadAllText(Path.Combine(Directory, name + ".key")).Trim());

    /// <summary><c>chown</c> through the system tool (root only; tests that need it skip otherwise).</summary>
    public static void Chown(string path, int uid)
    {
        using var process = Process.Start(new ProcessStartInfo("chown", [uid.ToString(CultureInfo.InvariantCulture), path]) { UseShellExecute = false })!;
        process.WaitForExit();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException("chown failed");
        }
    }

    public static bool IsRoot => Environment.UserName == "root";

    public void Dispose()
    {
        foreach (var dir in System.IO.Directory.EnumerateDirectories(Root, "*", SearchOption.AllDirectories).Prepend(Root))
        {
            try
            {
                File.SetUnixFileMode(dir, Mode0700);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        System.IO.Directory.Delete(Root, recursive: true);
    }
}
