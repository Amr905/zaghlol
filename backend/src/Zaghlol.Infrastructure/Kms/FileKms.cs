using System.Buffers;
using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Hosting;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The hardened key-file KMS (<c>Kms:Provider = File</c>, D-76 option B, T-200 design note). Allowed in every environment on
/// Linux. Every configured key is read once at start from <c>Kms:File:KeyDirectory</c>, after the guards G2–G13 of the design
/// note; any failure refuses the start with a constant message that names no path, key or value. <c>file:&lt;name&gt;</c> is
/// <c>&lt;name&gt;.pem</c> (a P-256 private key) or <c>&lt;name&gt;.key</c> (32 random bytes, base64), the formats
/// <c>dev-keys.sh</c> and the production key tool write.
/// </summary>
internal sealed partial class FileKms : IKmsBackend, IDisposable
{
    public const string ProviderName = "File";
    public const string Prefix = "file:";

    public const string NotLinuxMessage = "Kms:Provider = File needs Linux (POSIX owner and mode checks); use Local for development elsewhere.";
    public const string DirectoryUnsetMessage = "Kms:File:KeyDirectory must be set.";
    public const string DirectoryNotCanonicalMessage = "Kms:File:KeyDirectory must be an absolute, canonical path to a directory with no symbolic link in it.";
    public const string DirectoryUnreadableMessage = "Kms:File:KeyDirectory or one of its parents can't be inspected.";
    public const string DirectoryPermissionsMessage = "Kms:File:KeyDirectory must be owned by the process user or root and have no group or other permission (0700 or 0500).";
    public const string AncestorPermissionsMessage = "A parent of Kms:File:KeyDirectory is writable by another user (each parent must be owned by root or the process user and not group/other-writable, unless sticky).";
    public const string SourceTreeMessage = "Kms:File:KeyDirectory is inside a source tree, the content root or the application directory; keep production keys outside them.";
    public const string DevKeysMessage = "Kms:File:KeyDirectory holds kms.env, which backend/tools/dev-keys.sh writes; development keys are refused.";
    public const string EntryMessage = "Kms:File:KeyDirectory holds an entry that is a symbolic link, not a regular file, group/other accessible or owned by another user (key files must be 0400 or 0600, owned by the process user or root).";
    public const string TooManyEntriesMessage = "Kms:File:KeyDirectory holds too many entries.";
    public const string KeyRefMessage = "A File KMS key reference must look like file:<name> (a-z, 0-9, '-'), and a key can't be both a signing key and a symmetric key.";
    public const string MissingKeyMessage = "A File KMS key file is missing or unreadable.";
    public const string ChangedKeyMessage = "A File KMS key file changed while it was read.";
    public const string TooLargeMessage = "A File KMS key file is larger than 8 KiB.";
    public const string NotEcPemMessage = "A File KMS signing key file is not a single PEM EC private key on P-256.";
    public const string NotSecretMessage = "A File KMS symmetric key file must be the base64 of exactly 32 bytes.";
    public const string KnownTestKeyMessage = "A File KMS key is a key committed to the repository (test vector, fixture or development seed key) or is degenerate.";
    public const string FingerprintMessage = "A File KMS key does not match its Kms:File:Fingerprints:<name> pin (missing, malformed or a different key).";
    public const string OtherEnvironmentMessage = "A File KMS key is listed in Kms:File:OtherEnvironmentFingerprints: keys of another environment are refused.";
    public const string OtherEnvironmentUnsetMessage = "Outside Development and Testing, Kms:File:OtherEnvironmentFingerprints must list the other environment's fingerprints, or Kms:File:NoOtherEnvironment must be true.";
    public const string OtherEnvironmentMalformedMessage = "Kms:File:OtherEnvironmentFingerprints entries must be 64 lower-case hex characters.";
    public const string DevKidMessage = "Outside Development and Testing, the File KMS refuses the development and test kids (year 0000).";

    internal const int MaxFileBytes = 8 * 1024;
    internal const int MaxEntries = 256;
    internal const string DevKeysMarker = "kms.env";

    private const string P256Oid = "1.2.840.10045.3.1.7";
    private const int WrappedSize = EnvelopeCipher.NonceSize + DataKey.Size + EnvelopeCipher.TagSize;

    private readonly Dictionary<string, SigningEntry> signing;
    private readonly Dictionary<string, byte[]> secrets;
    private int disposed;

    private FileKms(Dictionary<string, SigningEntry> signing, Dictionary<string, byte[]> secrets)
    {
        this.signing = signing;
        this.secrets = secrets;
    }

    /// <summary>Runs every guard and loads every configured key, or throws <see cref="KmsConfigurationException"/>.</summary>
    public static FileKms Load(KmsSettings settings, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(environment);

        if (!OperatingSystem.IsLinux())
        {
            throw new KmsConfigurationException(NotLinuxMessage);
        }

        var euid = PosixFiles.EffectiveUid() ?? throw new KmsConfigurationException(DirectoryUnreadableMessage);
        var strict = !environment.IsDevelopment() && !environment.IsEnvironment("Testing");

        if (strict && settings.SigningKeys.Any(k => k.Kid.Length > 5 && k.Kid.AsSpan(1, 4).SequenceEqual("0000")))
        {
            throw new KmsConfigurationException(DevKidMessage);
        }

        CheckOtherEnvironmentSettings(settings, strict);

        var directory = CheckDirectory(settings.FileKeyDirectory, euid);
        CheckNotInSourceTree(directory, environment);
        CheckEntries(directory, euid);

        var (ecRefs, secretRefs) = KeyRefs(settings);
        var signingKeys = new Dictionary<string, SigningEntry>(StringComparer.Ordinal);
        var secretKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        try
        {
            foreach (var keyRef in ecRefs)
            {
                var key = LoadEc(directory, keyRef, euid);
                signingKeys[keyRef] = new SigningEntry(key);
                CheckFingerprint(settings, keyRef, KeyFingerprints.OfSigningKey(key), KnownTestKeys.SigningKeys);
            }

            foreach (var keyRef in secretRefs)
            {
                var secret = LoadSecret(directory, keyRef, euid);
                secretKeys[keyRef] = secret;
                if (KnownTestKeys.IsDegenerate(secret))
                {
                    throw new KmsConfigurationException(KnownTestKeyMessage);
                }

                CheckFingerprint(settings, keyRef, KeyFingerprints.OfSecret(secret), KnownTestKeys.Secrets);
            }
        }
        catch
        {
            new FileKms(signingKeys, secretKeys).Dispose();
            throw;
        }

        return new FileKms(signingKeys, secretKeys);
    }

    public ValueTask<byte[]> SignDigestAsync(string keyRef, ReadOnlyMemory<byte> sha256, CancellationToken cancellationToken)
    {
        var entry = Signing(keyRef);
        lock (entry.Gate)
        {
            return ValueTask.FromResult(entry.Key.SignHash(sha256.Span, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
        }
    }

    public ValueTask<byte[]> GetPublicKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        var entry = Signing(keyRef);
        lock (entry.Gate)
        {
            var q = entry.Key.ExportParameters(includePrivateParameters: false).Q;
            return ValueTask.FromResult<byte[]>([0x04, .. q.X!, .. q.Y!]);
        }
    }

    public ValueTask<byte[]> HmacSha256Async(string keyRef, ReadOnlyMemory<byte> data, CancellationToken cancellationToken) =>
        ValueTask.FromResult(HMACSHA256.HashData(Secret(keyRef), data.Span));

    public ValueTask<DataKey> GenerateDataKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        var kek = Secret(keyRef);
        var plaintext = RandomNumberGenerator.GetBytes(DataKey.Size);
        var wrapped = new byte[WrappedSize];
        var nonce = wrapped.AsSpan(0, EnvelopeCipher.NonceSize);
        RandomNumberGenerator.Fill(nonce);
        using var aes = new AesGcm(kek, EnvelopeCipher.TagSize);
        aes.Encrypt(
            nonce,
            plaintext,
            wrapped.AsSpan(EnvelopeCipher.NonceSize, DataKey.Size),
            wrapped.AsSpan(EnvelopeCipher.NonceSize + DataKey.Size),
            WrapAad(keyRef));
        return ValueTask.FromResult(new DataKey(plaintext, wrapped));
    }

    public ValueTask<DataKey> DecryptDataKeyAsync(string keyRef, ReadOnlyMemory<byte> wrapped, CancellationToken cancellationToken)
    {
        if (wrapped.Length != WrappedSize)
        {
            throw new CryptographicException();
        }

        var kek = Secret(keyRef);
        var span = wrapped.Span;
        var plaintext = new byte[DataKey.Size];
        using var aes = new AesGcm(kek, EnvelopeCipher.TagSize);
        aes.Decrypt(
            span[..EnvelopeCipher.NonceSize],
            span.Slice(EnvelopeCipher.NonceSize, DataKey.Size),
            span[(EnvelopeCipher.NonceSize + DataKey.Size)..],
            plaintext,
            WrapAad(keyRef));
        return ValueTask.FromResult(new DataKey(plaintext, wrapped.ToArray()));
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 1)
        {
            return;
        }

        foreach (var entry in signing.Values)
        {
            lock (entry.Gate)
            {
                entry.Key.Dispose();
            }
        }

        foreach (var secret in secrets.Values)
        {
            CryptographicOperations.ZeroMemory(secret);
        }

        signing.Clear();
        secrets.Clear();
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9-]{0,62}\\z", RegexOptions.CultureInvariant)]
    internal static partial Regex NamePattern();

    /// <summary>True when <paramref name="path"/> or one of its parents holds <c>.git</c> or <c>Zaghlol.sln</c>.</summary>
    internal static bool IsInSourceTree(string path)
    {
        for (var current = new DirectoryInfo(Path.GetFullPath(path)); current is not null; current = current.Parent)
        {
            var git = Path.Combine(current.FullName, ".git");
            if (Directory.Exists(git) || File.Exists(git) || File.Exists(Path.Combine(current.FullName, "Zaghlol.sln")))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>True when one path is the other or contains it.</summary>
    internal static bool Overlaps(string a, string b)
    {
        var x = Trim(Path.GetFullPath(a));
        var y = Trim(Path.GetFullPath(b));
        return string.Equals(x, y, StringComparison.Ordinal)
            || x.StartsWith(y + "/", StringComparison.Ordinal)
            || y.StartsWith(x + "/", StringComparison.Ordinal)
            || x.Length == 0
            || y.Length == 0;

        static string Trim(string p) => p.TrimEnd('/');
    }

    private static byte[] WrapAad(string keyRef) => [.. "zaghlol-file-wrap-v1"u8, 0x00, .. Encoding.ASCII.GetBytes(keyRef)];

    private static void CheckOtherEnvironmentSettings(KmsSettings settings, bool strict)
    {
        if (settings.FileOtherEnvironmentFingerprints.Any(f => !KeyFingerprints.IsWellFormed(f)))
        {
            throw new KmsConfigurationException(OtherEnvironmentMalformedMessage);
        }

        if (strict && settings.FileOtherEnvironmentFingerprints.Count == 0 && !settings.FileNoOtherEnvironment)
        {
            throw new KmsConfigurationException(OtherEnvironmentUnsetMessage);
        }

        if (settings.FileFingerprints.Values.Any(settings.FileOtherEnvironmentFingerprints.Contains))
        {
            throw new KmsConfigurationException(OtherEnvironmentMessage);
        }
    }

    private static string CheckDirectory(string? configured, uint euid)
    {
        if (string.IsNullOrWhiteSpace(configured))
        {
            throw new KmsConfigurationException(DirectoryUnsetMessage);
        }

        if (!Path.IsPathFullyQualified(configured)
            || configured.Length < 2
            || configured.EndsWith('/')
            || !string.Equals(Path.GetFullPath(configured), configured, StringComparison.Ordinal))
        {
            throw new KmsConfigurationException(DirectoryNotCanonicalMessage);
        }

        // Every component from the root down: no symbolic link, each parent safe from other users.
        var parts = configured.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var current = "/";
        CheckAncestor(PosixFiles.LStat(current), euid);
        for (var i = 0; i < parts.Length; i++)
        {
            current = current.Length == 1 ? "/" + parts[i] : current + "/" + parts[i];
            var stat = PosixFiles.LStat(current) ?? throw new KmsConfigurationException(DirectoryUnreadableMessage);
            if (stat.IsSymlink || !stat.IsDirectory)
            {
                throw new KmsConfigurationException(DirectoryNotCanonicalMessage);
            }

            if (i < parts.Length - 1)
            {
                CheckAncestor(stat, euid);
            }
            else if (stat.HasGroupOrOtherBits || (stat.Uid != euid && stat.Uid != 0))
            {
                throw new KmsConfigurationException(DirectoryPermissionsMessage);
            }
        }

        return configured;
    }

    private static void CheckAncestor(PosixStat? stat, uint euid)
    {
        if (stat is not { } s)
        {
            throw new KmsConfigurationException(DirectoryUnreadableMessage);
        }

        if ((s.Uid != 0 && s.Uid != euid) || (s.GroupOrOtherWritable && !s.IsSticky))
        {
            throw new KmsConfigurationException(AncestorPermissionsMessage);
        }
    }

    private static void CheckNotInSourceTree(string directory, IHostEnvironment environment)
    {
        if (IsInSourceTree(directory)
            || (!string.IsNullOrEmpty(environment.ContentRootPath) && Overlaps(directory, environment.ContentRootPath))
            || Overlaps(directory, AppContext.BaseDirectory))
        {
            throw new KmsConfigurationException(SourceTreeMessage);
        }
    }

    private static void CheckEntries(string directory, uint euid)
    {
        var options = new EnumerationOptions
        {
            AttributesToSkip = 0,
            IgnoreInaccessible = false,
            RecurseSubdirectories = false,
            ReturnSpecialDirectories = false,
        };

        var count = 0;
        IEnumerable<string> entries;
        try
        {
            entries = Directory.EnumerateFileSystemEntries(directory, "*", options).ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new KmsConfigurationException(DirectoryUnreadableMessage);
        }

        foreach (var entry in entries)
        {
            if (++count > MaxEntries)
            {
                throw new KmsConfigurationException(TooManyEntriesMessage);
            }

            if (string.Equals(Path.GetFileName(entry), DevKeysMarker, StringComparison.Ordinal))
            {
                throw new KmsConfigurationException(DevKeysMessage);
            }

            CheckEntry(PosixFiles.LStat(entry), euid);
        }
    }

    private static void CheckEntry(PosixStat? stat, uint euid)
    {
        if (stat is not { } s || !s.IsRegular || s.HasGroupOrOtherBits || (s.Uid != euid && s.Uid != 0) || (s.Mode & 0xE00) != 0)
        {
            throw new KmsConfigurationException(EntryMessage);
        }
    }

    private static (List<string> Ec, List<string> Secrets) KeyRefs(KmsSettings settings)
    {
        var ec = settings.SigningKeys.Select(k => k.KeyRef).Distinct(StringComparer.Ordinal).ToList();
        var symmetric = settings.HmacKeyRefs.Values.Concat(settings.EnvelopeDecryptKeyRefs).Distinct(StringComparer.Ordinal).ToList();
        foreach (var keyRef in ec.Concat(symmetric))
        {
            if (!keyRef.StartsWith(Prefix, StringComparison.Ordinal) || !NamePattern().IsMatch(keyRef[Prefix.Length..]))
            {
                throw new KmsConfigurationException(KeyRefMessage);
            }
        }

        if (ec.Intersect(symmetric, StringComparer.Ordinal).Any())
        {
            throw new KmsConfigurationException(KeyRefMessage);
        }

        return (ec, symmetric);
    }

    private static void CheckFingerprint(KmsSettings settings, string keyRef, string fingerprint, IReadOnlySet<string> denied)
    {
        if (denied.Contains(fingerprint))
        {
            throw new KmsConfigurationException(KnownTestKeyMessage);
        }

        if (settings.FileOtherEnvironmentFingerprints.Contains(fingerprint))
        {
            throw new KmsConfigurationException(OtherEnvironmentMessage);
        }

        var pinned = settings.FileFingerprints.GetValueOrDefault(keyRef[Prefix.Length..]);
        if (!KeyFingerprints.IsWellFormed(pinned)
            || !CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(pinned!), Encoding.ASCII.GetBytes(fingerprint)))
        {
            throw new KmsConfigurationException(FingerprintMessage);
        }
    }

    private static ECDsa LoadEc(string directory, string keyRef, uint euid)
    {
        var (buffer, length) = ReadChecked(Path.Combine(directory, keyRef[Prefix.Length..] + ".pem"), euid);
        var chars = new char[length];
        var key = ECDsa.Create();
        try
        {
            if (Ascii(buffer.AsSpan(0, length), chars) is false
                || !PemEncoding.TryFind(chars, out var fields)
                || !IsPrivateKeyLabel(chars.AsSpan()[fields.Label]))
            {
                throw new KmsConfigurationException(NotEcPemMessage);
            }

            key.ImportFromPem(chars);
            if (!string.Equals(key.ExportParameters(includePrivateParameters: false).Curve.Oid.Value, P256Oid, StringComparison.Ordinal))
            {
                throw new KmsConfigurationException(NotEcPemMessage);
            }

            return key;
        }
        catch (Exception ex) when (ex is ArgumentException or CryptographicException)
        {
            key.Dispose();
            throw new KmsConfigurationException(NotEcPemMessage);
        }
        catch
        {
            key.Dispose();
            throw;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(buffer);
            Array.Clear(chars);
        }
    }

    private static byte[] LoadSecret(string directory, string keyRef, uint euid)
    {
        var (buffer, length) = ReadChecked(Path.Combine(directory, keyRef[Prefix.Length..] + ".key"), euid);
        var secret = GC.AllocateArray<byte>(DataKey.Size, pinned: true);
        try
        {
            var text = buffer.AsSpan(0, length);
            if (text.EndsWith("\n"u8))
            {
                text = text[..^1];
            }

            if (Base64.DecodeFromUtf8(text, secret, out var consumed, out var written) != OperationStatus.Done
                || consumed != text.Length
                || written != DataKey.Size)
            {
                CryptographicOperations.ZeroMemory(secret);
                throw new KmsConfigurationException(NotSecretMessage);
            }

            return secret;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(buffer);
        }
    }

    /// <summary>
    /// Opens the file only after its name passes the entry checks, then checks the open descriptor again (same inode, same
    /// rules), and reads at most <see cref="MaxFileBytes"/> from it. The returned buffer is pinned; the caller zeroes it.
    /// </summary>
    private static (byte[] Buffer, int Length) ReadChecked(string path, uint euid)
    {
        var before = PosixFiles.LStat(path) ?? throw new KmsConfigurationException(MissingKeyMessage);
        CheckEntry(before, euid);

        var buffer = GC.AllocateArray<byte>(MaxFileBytes + 1, pinned: true);
        try
        {
            using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var after = PosixFiles.FStat(handle) ?? throw new KmsConfigurationException(MissingKeyMessage);
            if (!after.SameFileAs(before))
            {
                throw new KmsConfigurationException(ChangedKeyMessage);
            }

            CheckEntry(after, euid);
            if (after.Size > MaxFileBytes)
            {
                throw new KmsConfigurationException(TooLargeMessage);
            }

            var total = 0;
            int read;
            while (total < buffer.Length && (read = RandomAccess.Read(handle, buffer.AsSpan(total), total)) > 0)
            {
                total += read;
            }

            if (total > MaxFileBytes)
            {
                throw new KmsConfigurationException(TooLargeMessage);
            }

            return (buffer, total);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // The runtime's message carries the path, which names the key: keep it out of logs.
            CryptographicOperations.ZeroMemory(buffer);
            throw new KmsConfigurationException(MissingKeyMessage);
        }
        catch
        {
            CryptographicOperations.ZeroMemory(buffer);
            throw;
        }
    }

    private static bool IsPrivateKeyLabel(ReadOnlySpan<char> label) =>
        label.SequenceEqual("PRIVATE KEY") || label.SequenceEqual("EC PRIVATE KEY");

    private static bool Ascii(ReadOnlySpan<byte> bytes, Span<char> chars)
    {
        for (var i = 0; i < bytes.Length; i++)
        {
            if (bytes[i] > 0x7F)
            {
                return false;
            }

            chars[i] = (char)bytes[i];
        }

        return true;
    }

    private SigningEntry Signing(string keyRef)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) == 1, this);
        return signing.TryGetValue(keyRef, out var entry)
            ? entry
            : throw new KmsConfigurationException("A File KMS signing key reference is not in the configured ring.");
    }

    private byte[] Secret(string keyRef)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) == 1, this);
        return secrets.TryGetValue(keyRef, out var secret)
            ? secret
            : throw new KmsConfigurationException("A File KMS symmetric key reference is not in the configured ring.");
    }

    // Non-public members: KmsSurfaceTests forbids any public member that returns key objects.
    private sealed class SigningEntry(ECDsa key)
    {
        internal readonly ECDsa Key = key;

        internal readonly Lock Gate = new();
    }
}
