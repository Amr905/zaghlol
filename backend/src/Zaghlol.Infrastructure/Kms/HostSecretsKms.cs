using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The shared-host key provider (<c>Kms:Provider = HostSecrets</c>, T-205, ADR-026, D-80). Reads the File-format key ring
/// (<c>file:&lt;name&gt;</c> references, the same PEM P-256 and 32-byte keys, the same pins and envelope wrap as <see cref="FileKms"/>)
/// from secret settings the host injects, one per key: <c>ZAGHLOL_KEYS__&lt;name&gt;</c> = unpadded base64url of
/// <c>{"zaghlol":"host-key-v1","name":"&lt;name&gt;","pem"|"key":"&lt;the .pem or .key file text&gt;"}</c>. Works on Windows and
/// Linux. Keeps every T-200 guard that doesn't depend on the OS and adds: no key in a configuration file, and an explicit
/// <c>Kms:AcceptSharedHostCustody = true</c> outside Development and Testing. Every refusal is a constant message.
/// </summary>
internal sealed class HostSecretsKms : IKmsBackend, IDisposable
{
    public const string ProviderName = "HostSecrets";
    public const string SettingsSection = "ZAGHLOL_KEYS";
    public const string CustodyKey = "Kms:AcceptSharedHostCustody";
    public const string FormatTag = "host-key-v1";

    public const string CustodyMessage = "Outside Development and Testing, Kms:Provider = HostSecrets needs Kms:AcceptSharedHostCustody = true (shared-host key custody, ADR-026).";
    public const string InFileMessage = "Key material (ZAGHLOL_KEYS) was found in a configuration file such as appsettings*.json; keys must come only from the host's secret settings.";
    public const string MissingMessage = "A ZAGHLOL_KEYS__<name> setting for a configured key is missing or empty.";
    public const string MalformedMessage = "A ZAGHLOL_KEYS__<name> setting is not the base64url of a host-key-v1 object for that name and key type, or is larger than 16 KiB.";
    public const string DuplicateMessage = "A key is set twice in ZAGHLOL_KEYS (its name written once with '-' and once with '_').";
    public const string NotDumpableMessage = "Outside Development and Testing, the HostSecrets provider could not mark the process non-dumpable (prctl PR_SET_DUMPABLE); keys would be exposed to core dumps.";

    public const string KeyRefMessage = "A HostSecrets key reference must look like file:<name> (a-z, 0-9, '-'), and a key can't be both a signing key and a symmetric key.";
    public const string SharedKeyMessage = "A HostSecrets key serves two roles: each HMAC key and each envelope key needs its own key reference and its own key bytes.";
    public const string KnownTestKeyMessage = "A HostSecrets key is a key committed to the repository (test vector, fixture or development seed key) or is degenerate.";
    public const string FingerprintMessage = "A HostSecrets key does not match its Kms:File:Fingerprints:<name> pin (missing, malformed or a different key).";
    public const string OtherEnvironmentMessage = "A HostSecrets key pin is listed in Kms:File:OtherEnvironmentFingerprints: keys of another environment are refused.";
    public const string OtherEnvironmentKeyMessage = "A HostSecrets key matches a fingerprint in Kms:File:OtherEnvironmentFingerprints: keys of another environment are refused.";
    public const string OtherEnvironmentUnsetMessage = "Outside Development and Testing, Kms:File:OtherEnvironmentFingerprints must list the other environment's fingerprints, or Kms:File:NoOtherEnvironment must be true.";
    public const string OtherEnvironmentMalformedMessage = "Kms:File:OtherEnvironmentFingerprints entries must be 64 lower-case hex characters.";
    public const string DevKidMessage = "Outside Development and Testing, the HostSecrets provider refuses the development and test kids (year 0000).";
    public const string NotEcPemMessage = "A ZAGHLOL_KEYS signing key is not a single PEM EC private key on P-256.";
    public const string NotSecretMessage = "A ZAGHLOL_KEYS symmetric key must be the base64 of exactly 32 bytes.";

    /// <summary>Longest accepted setting value, in characters.</summary>
    internal const int MaxValueChars = 16 * 1024;

    /// <summary>Largest configuration file scanned for pasted keys.</summary>
    internal const int MaxScannedFileBytes = 4 * 1024 * 1024;

    internal static readonly FileFormatMessages Messages = new(
        KeyRefMessage,
        SharedKeyMessage,
        KnownTestKeyMessage,
        FingerprintMessage,
        OtherEnvironmentMessage,
        OtherEnvironmentKeyMessage,
        OtherEnvironmentUnsetMessage,
        OtherEnvironmentMalformedMessage,
        DevKidMessage,
        NotEcPemMessage,
        NotSecretMessage);

    /// <summary>The first 24 bytes every value's JSON starts with (<c>{"zaghlol":"host-key-v1"</c>).</summary>
    internal static readonly byte[] JsonHeader = "{\"zaghlol\":\"host-key-v1\""u8.ToArray();

    /// <summary>The 32 base64url characters every setting value starts with: a pasted key is recognisable in any file.</summary>
    internal static readonly string ValueMarker = Base64Url.EncodeToString(JsonHeader);

    private readonly FileKms keys;

    private HostSecretsKms(FileKms keys) => this.keys = keys;

    /// <summary>Runs every guard and loads every configured key from the host's secret settings, or throws <see cref="KmsConfigurationException"/>.</summary>
    public static HostSecretsKms Load(KmsSettings settings, IConfiguration configuration, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var strict = !environment.IsDevelopment() && !environment.IsEnvironment("Testing");

        CheckCustody(configuration, environment);

        CheckNoKeysInFiles(configuration, environment);
        FileKms.CheckDevKids(settings, strict, Messages);
        FileKms.CheckOtherEnvironmentSettings(settings, strict, Messages);
        var (ecRefs, secretRefs) = FileKms.KeyRefs(settings, Messages);

        // G14 where the OS has it: keep the keys out of core files. Windows has no per-process equivalent (ADR-026).
        if (strict && OperatingSystem.IsLinux() && !PosixFiles.SetNotDumpable())
        {
            throw new KmsConfigurationException(NotDumpableMessage);
        }

        var section = configuration.GetSection(SettingsSection);
        var signingKeys = new Dictionary<string, ECDsa>(StringComparer.Ordinal);
        var secretKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        try
        {
            foreach (var keyRef in ecRefs)
            {
                var name = keyRef[FileKms.Prefix.Length..];
                var pem = ReadValue(section, name, KeyKind.Pem);
                try
                {
                    var key = FileKms.ParseEcPem(pem, Messages);
                    signingKeys[keyRef] = key;
                    FileKms.CheckFingerprint(settings, keyRef, KeyFingerprints.OfSigningKey(key), KnownTestKeys.SigningKeys, seen, Messages);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(pem);
                }
            }

            foreach (var keyRef in secretRefs)
            {
                var name = keyRef[FileKms.Prefix.Length..];
                var text = ReadValue(section, name, KeyKind.Key);
                try
                {
                    var secret = FileKms.ParseSecret(text, Messages);
                    secretKeys[keyRef] = secret;
                    FileKms.CheckSecret(settings, keyRef, secret, seen, Messages);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(text);
                }
            }
        }
        catch
        {
            FileKms.FromLoadedKeys(signingKeys, secretKeys).Dispose();
            throw;
        }

        return new HostSecretsKms(FileKms.FromLoadedKeys(signingKeys, secretKeys));
    }

    public ValueTask<byte[]> SignDigestAsync(string keyRef, ReadOnlyMemory<byte> sha256, CancellationToken cancellationToken) =>
        keys.SignDigestAsync(keyRef, sha256, cancellationToken);

    public ValueTask<byte[]> GetPublicKeyAsync(string keyRef, CancellationToken cancellationToken) =>
        keys.GetPublicKeyAsync(keyRef, cancellationToken);

    public ValueTask<byte[]> HmacSha256Async(string keyRef, ReadOnlyMemory<byte> data, CancellationToken cancellationToken) =>
        keys.HmacSha256Async(keyRef, data, cancellationToken);

    public ValueTask<DataKey> GenerateDataKeyAsync(string keyRef, CancellationToken cancellationToken) =>
        keys.GenerateDataKeyAsync(keyRef, cancellationToken);

    public ValueTask<DataKey> DecryptDataKeyAsync(string keyRef, ReadOnlyMemory<byte> wrapped, CancellationToken cancellationToken) =>
        keys.DecryptDataKeyAsync(keyRef, wrapped, cancellationToken);

    public void Dispose() => keys.Dispose();

    /// <summary>H4: the weaker custody of a shared host is an explicit, recorded choice outside Development and Testing (ADR-026).</summary>
    internal static void CheckCustody(IConfiguration configuration, IHostEnvironment environment)
    {
        var strict = !environment.IsDevelopment() && !environment.IsEnvironment("Testing");
        if (strict && !(bool.TryParse(configuration[CustodyKey], out var accepted) && accepted))
        {
            throw new KmsConfigurationException(CustodyMessage);
        }
    }

    /// <summary>
    /// H3: a <c>ZAGHLOL_KEYS</c> value served by a configuration file, or an <c>appsettings*.json</c> in the content root or the
    /// application directory that holds <c>ZAGHLOL_KEYS</c> or <see cref="ValueMarker"/> (loaded in this environment or not).
    /// </summary>
    internal static void CheckNoKeysInFiles(IConfiguration configuration, IHostEnvironment environment)
    {
        if (configuration is IConfigurationRoot root
            && root.Providers.Any(p => p is FileConfigurationProvider && p.GetChildKeys([], SettingsSection).Any()))
        {
            throw new KmsConfigurationException(InFileMessage);
        }

        var directories = new[] { environment.ContentRootPath, AppContext.BaseDirectory }
            .Where(d => !string.IsNullOrEmpty(d) && Directory.Exists(d))
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.Ordinal);
        foreach (var directory in directories)
        {
            foreach (var file in Directory.EnumerateFiles(directory, "appsettings*.json", SearchOption.TopDirectoryOnly))
            {
                if (FileHoldsKeys(file))
                {
                    throw new KmsConfigurationException(InFileMessage);
                }
            }
        }
    }

    private static bool FileHoldsKeys(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (info.Length > MaxScannedFileBytes)
            {
                return true; // no real settings file is this large; refuse rather than skip it
            }

            var text = File.ReadAllText(path, Encoding.UTF8);
            return text.Contains(SettingsSection, StringComparison.OrdinalIgnoreCase)
                || text.Contains(ValueMarker, StringComparison.Ordinal);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // A settings file the host can't read was not loaded either; nothing in it can reach the key ring.
            return false;
        }
    }

    /// <summary>
    /// The <c>pem</c> or <c>key</c> text of <c>ZAGHLOL_KEYS:&lt;name&gt;</c> (or its <c>_</c> spelling) in a pinned array the caller
    /// zeroes. Intermediate buffers are pinned and zeroed here.
    /// </summary>
    internal static byte[] ReadValue(IConfigurationSection section, string name, KeyKind kind)
    {
        var dash = section[name];
        var underscore = name.Contains('-', StringComparison.Ordinal) ? section[name.Replace('-', '_')] : null;
        if (dash is not null && underscore is not null)
        {
            throw new KmsConfigurationException(DuplicateMessage);
        }

        var value = (dash ?? underscore).AsSpan().Trim();
        if (value.IsEmpty)
        {
            throw new KmsConfigurationException(MissingMessage);
        }

        if (value.Length > MaxValueChars || value.ContainsAnyExcept(Base64UrlChars))
        {
            throw new KmsConfigurationException(MalformedMessage);
        }

        var json = GC.AllocateArray<byte>(Base64Url.GetMaxDecodedLength(value.Length), pinned: true);
        try
        {
            if (Base64Url.DecodeFromChars(value, json, out var consumed, out var written) != System.Buffers.OperationStatus.Done
                || consumed != value.Length)
            {
                throw new KmsConfigurationException(MalformedMessage);
            }

            return ParseJson(json.AsSpan(0, written), name, kind);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(json);
        }
    }

    /// <summary>Exactly <c>{"zaghlol":"host-key-v1","name":&lt;name&gt;,"pem"|"key"|"secret":&lt;text&gt;}</c>, members in this order.</summary>
    internal static byte[] ParseJson(ReadOnlySpan<byte> json, string name, KeyKind kind)
    {
        byte[]? text = null;
        try
        {
            if (!json.StartsWith(JsonHeader))
            {
                throw new KmsConfigurationException(MalformedMessage);
            }

            var reader = new Utf8JsonReader(json, new JsonReaderOptions { CommentHandling = JsonCommentHandling.Disallow, MaxDepth = 2 });
            Expect(ref reader, JsonTokenType.StartObject);
            ExpectMember(ref reader, "zaghlol"u8);
            Expect(ref reader, JsonTokenType.String);
            Require(reader.ValueTextEquals(FormatTag));
            ExpectMember(ref reader, "name"u8);
            Expect(ref reader, JsonTokenType.String);
            Require(reader.ValueTextEquals(name));
            ExpectMember(ref reader, kind switch { KeyKind.Pem => "pem"u8, KeyKind.Key => "key"u8, _ => "secret"u8 });
            Expect(ref reader, JsonTokenType.String);
            Require(!reader.HasValueSequence);
            text = GC.AllocateArray<byte>(reader.ValueSpan.Length, pinned: true);
            var length = reader.CopyString(text);
            Expect(ref reader, JsonTokenType.EndObject);
            Require(!reader.Read());

            var exact = GC.AllocateArray<byte>(length, pinned: true);
            text.AsSpan(0, length).CopyTo(exact);
            return exact;
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or ArgumentException)
        {
            // The reader's message can quote the input; it is dropped.
            throw new KmsConfigurationException(MalformedMessage);
        }
        finally
        {
            if (text is not null)
            {
                CryptographicOperations.ZeroMemory(text);
            }
        }
    }

    private static void ExpectMember(ref Utf8JsonReader reader, ReadOnlySpan<byte> member)
    {
        Expect(ref reader, JsonTokenType.PropertyName);
        Require(reader.ValueTextEquals(member));
    }

    private static void Expect(ref Utf8JsonReader reader, JsonTokenType type) => Require(reader.Read() && reader.TokenType == type);

    private static void Require(bool condition)
    {
        if (!condition)
        {
            throw new KmsConfigurationException(MalformedMessage);
        }
    }

    private static readonly System.Buffers.SearchValues<char> Base64UrlChars =
        System.Buffers.SearchValues.Create("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_");

    /// <summary>
    /// Which member a value must hold: <c>pem</c> for a signing key, <c>key</c> for an HMAC or key-encryption key, <c>secret</c> for
    /// an LLM provider key (T-333, <c>ZAGHLOL_KEYS__llm_&lt;id&gt;</c>).
    /// </summary>
    internal enum KeyKind
    {
        Pem,
        Key,
        Secret,
    }
}
