using System.Globalization;
using System.Runtime.Versioning;
using System.Security.Cryptography;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The production key tool for the File KMS (T-200 design note §7):
/// <c>dotnet Zaghlol.Workers.dll --generate-keys --environment Staging|Production --out &lt;new dir&gt; [--kid s2026a]… [--secret seat]…</c>.
/// It writes P-256 keys (<c>&lt;kid&gt;.pem</c>) and 32-byte keys (<c>&lt;name&gt;.key</c>) into a new 0700 directory as 0400
/// files, then makes the directory 0500. It prints public values only: fingerprints, the key-ring entries with each public JWK,
/// and <c>SeatCheck</c>. It refuses to run inside a source tree or to write into one, and never prints private material.
/// </summary>
public static class FileKeyTool
{
    public const string Flag = "--generate-keys";

    public const int Ok = 0;
    public const int Failed = 1;
    public const int Usage = 2;

    private const UnixFileMode DirectoryWhileWriting = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;
    private const UnixFileMode DirectoryDone = UnixFileMode.UserRead | UnixFileMode.UserExecute;
    private const UnixFileMode KeyFile = UnixFileMode.UserRead;

    private const string UsageText =
        "usage: --generate-keys --environment Staging|Production --out <new directory> [--kid <kid>]... [--secret <name>]...\n"
        + "  --kid     a P-256 signing key, kid ^[se][0-9]{4}[a-z]$ (s = Sync, e = Entitlement; not year 0000)\n"
        + "  --secret  a 32-byte key name ([a-z0-9][a-z0-9-]*), e.g. seat, audit, install-pepper, envelope";

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
            return Usage;
        }

        if (!OperatingSystem.IsLinux())
        {
            stderr.WriteLine("refused: the key tool runs on Linux only (the File KMS checks POSIX owner and mode).");
            return Usage;
        }

        if (FileKms.IsInSourceTree(workingDirectory))
        {
            stderr.WriteLine("refused: the current directory is inside a source tree (.git or Zaghlol.sln above it); run the tool elsewhere.");
            return Usage;
        }

        var output = request.Output;
        var parent = Path.GetDirectoryName(output);
        if (parent is null || !Directory.Exists(parent))
        {
            stderr.WriteLine("refused: the parent of --out must exist.");
            return Usage;
        }

        // The source-tree checks below are lexical, so every component must be a real directory: a symbolic link anywhere
        // in the parent chain could point into a checkout (review C1/S1).
        if (!IsRealDirectoryChain(parent))
        {
            stderr.WriteLine("refused: --out must not pass through a symbolic link (give the real path).");
            return Usage;
        }

        if (FileKms.IsInSourceTree(parent) || FileKms.Overlaps(output, AppContext.BaseDirectory))
        {
            stderr.WriteLine("refused: --out is inside a source tree or the application directory; keys must never be written there.");
            return Usage;
        }

        // lstat, not Exists: a dangling symbolic link at --out makes Exists false.
        if (PosixFiles.LStat(output) is not null || Directory.Exists(output) || File.Exists(output))
        {
            stderr.WriteLine("refused: --out must not exist yet (the tool creates it with mode 0700).");
            return Usage;
        }

        return Generate(request, stdout, stderr);
    }

    /// <summary>True when every component from <c>/</c> down to <paramref name="directory"/> is a directory and none is a symlink.</summary>
    private static bool IsRealDirectoryChain(string directory)
    {
        var current = "/";
        if (PosixFiles.LStat(current) is not { IsDirectory: true })
        {
            return false;
        }

        foreach (var part in directory.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            current = current.Length == 1 ? "/" + part : current + "/" + part;
            if (PosixFiles.LStat(current) is not { IsDirectory: true, IsSymlink: false })
            {
                return false;
            }
        }

        return true;
    }

    [SupportedOSPlatform("linux")]
    private static int Generate(Request request, TextWriter stdout, TextWriter stderr)
    {
        var written = new List<string>();
        var lines = new List<string>();
        try
        {
            Directory.CreateDirectory(request.Output, DirectoryWhileWriting);
            File.SetUnixFileMode(request.Output, DirectoryWhileWriting);

            var index = 0;
            foreach (var kid in request.Kids)
            {
                using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
                WritePem(Path.Combine(request.Output, kid + ".pem"), key, written);
                var jwk = EcPublicJwk.FromX963(PublicPoint(key));
                var prefix = string.Create(CultureInfo.InvariantCulture, $"Signing__Keys__{index++}__");
                lines.Add(prefix + "Kid=" + kid);
                lines.Add(prefix + "Purpose=" + (kid[0] == 's' ? "Sync" : "Entitlement"));
                lines.Add(prefix + "Status=Next");
                lines.Add(prefix + "KeyRef=" + FileKms.Prefix + kid);
                lines.Add(prefix + "PublicJwk__Kty=" + jwk.Kty);
                lines.Add(prefix + "PublicJwk__Crv=" + jwk.Crv);
                lines.Add(prefix + "PublicJwk__X=" + jwk.X);
                lines.Add(prefix + "PublicJwk__Y=" + jwk.Y);
                lines.Add("Kms__File__Fingerprints__" + kid + "=" + KeyFingerprints.OfSigningKey(key));
            }

            foreach (var name in request.Secrets)
            {
                var secret = GC.AllocateArray<byte>(DataKey.Size, pinned: true);
                try
                {
                    RandomNumberGenerator.Fill(secret);
                    WriteSecret(Path.Combine(request.Output, name + ".key"), secret, written);
                    lines.Add("Kms__File__Fingerprints__" + name + "=" + KeyFingerprints.OfSecret(secret));
                    if (name == "seat" || name.StartsWith("seat-", StringComparison.Ordinal))
                    {
                        lines.Add("Kms__HmacKeys__SeatCheck=" + Convert.ToHexStringLower(HMACSHA256.HashData(secret, "zaghlol-kseat-check-v1"u8)));
                    }
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(secret);
                }
            }

            File.SetUnixFileMode(request.Output, DirectoryDone);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or CryptographicException)
        {
            // Only what this run created is removed; the message carries the exception type, never a path or key.
            foreach (var file in written)
            {
                TryDelete(() => File.Delete(file));
            }

            TryDelete(() => Directory.Delete(request.Output));
            stderr.WriteLine("failed: could not write the keys (" + ex.GetType().Name + "); nothing from this run was kept.");
            return Failed;
        }

        stdout.WriteLine("# Zaghlol File KMS keys for " + request.Environment + " (T-200). Public values only: fingerprints, JWKs, SeatCheck.");
        stdout.WriteLine("# Files: " + written.Count + " key file(s), mode 0400, directory 0500, owner = the user that ran this tool.");
        stdout.WriteLine("# Next: back the directory up offline (deployment.md section 3), mount it read-only at Kms:File:KeyDirectory,");
        stdout.WriteLine("# renumber the Signing__Keys__<n> entries to fit the ring, and set Status=Active only per the rotation rules.");
        stdout.WriteLine("Kms__Provider=File");
        foreach (var line in lines)
        {
            stdout.WriteLine(line);
        }

        return Ok;
    }

    [SupportedOSPlatform("linux")]
    private static void WritePem(string path, ECDsa key, List<string> written)
    {
        var der = key.ExportPkcs8PrivateKey();
        char[]? chars = null;
        byte[]? bytes = null;
        try
        {
            chars = PemEncoding.Write("PRIVATE KEY", der);
            bytes = new byte[chars.Length + 1];
            for (var i = 0; i < chars.Length; i++)
            {
                bytes[i] = (byte)chars[i];
            }

            bytes[^1] = (byte)'\n';
            WriteNew(path, bytes, written);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(der);
            if (chars is not null)
            {
                Array.Clear(chars);
            }

            if (bytes is not null)
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }
    }

    [SupportedOSPlatform("linux")]
    private static void WriteSecret(string path, ReadOnlySpan<byte> secret, List<string> written)
    {
        var bytes = GC.AllocateArray<byte>(45, pinned: true);
        try
        {
            if (System.Buffers.Text.Base64.EncodeToUtf8(secret, bytes, out _, out var length) != System.Buffers.OperationStatus.Done || length != 44)
            {
                throw new CryptographicException();
            }

            bytes[44] = (byte)'\n';
            WriteNew(path, bytes, written);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    [SupportedOSPlatform("linux")]
    private static void WriteNew(string path, ReadOnlySpan<byte> content, List<string> written)
    {
        var options = new FileStreamOptions
        {
            Mode = FileMode.CreateNew,
            Access = FileAccess.Write,
            Share = FileShare.None,
            UnixCreateMode = KeyFile,
        };

        using (var stream = new FileStream(path, options))
        {
            written.Add(path);
            stream.Write(content);
            stream.Flush(flushToDisk: true);
        }

        // UnixCreateMode is masked by the umask; set it explicitly.
        File.SetUnixFileMode(path, KeyFile);
    }

    private static byte[] PublicPoint(ECDsa key)
    {
        var q = key.ExportParameters(includePrivateParameters: false).Q;
        return [0x04, .. q.X!, .. q.Y!];
    }

    private static void TryDelete(Action delete)
    {
        try
        {
            delete();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best effort: the run already failed and says so.
        }
    }

    private static bool TryParse(IReadOnlyList<string> args, out Request request, out string problem)
    {
        request = default!;
        string? environment = null;
        string? output = null;
        var kids = new List<string>();
        var secrets = new List<string>();
        for (var i = 0; i < args.Count; i++)
        {
            var arg = args[i];
            if (arg == Flag)
            {
                continue;
            }

            if (arg is not ("--environment" or "--out" or "--kid" or "--secret"))
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
                case "--out" when output is null:
                    output = value;
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

        if (environment is not ("Staging" or "Production"))
        {
            problem = "--environment must be Staging or Production";
            return false;
        }

        if (output is null || !Path.IsPathFullyQualified(output) || output.EndsWith('/') || Path.GetFullPath(output) != output)
        {
            problem = "--out must be an absolute, canonical path";
            return false;
        }

        if (kids.Count + secrets.Count == 0)
        {
            problem = "nothing to generate (give --kid and/or --secret)";
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

        request = new Request(environment, output, kids, secrets);
        problem = string.Empty;
        return true;
    }

    private sealed record Request(string Environment, string Output, IReadOnlyList<string> Kids, IReadOnlyList<string> Secrets);
}
