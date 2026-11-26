using System.Buffers.Text;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The OpenBao Transit KMS (<c>Kms:Provider = OpenBao</c>, D-76 step 2, T-201 design note). Signing, HMAC and envelope keys
/// live in OpenBao and never reach this process: it asks Transit to sign a digest (<c>ecdsa-p256</c>, JWS marshaling),
/// to MAC (<c>hmac</c> keys, version 1 pinned) and to make or open data keys (<c>datakey/plaintext</c>, <c>decrypt</c>).
/// Legacy <c>file:&lt;name&gt;</c> envelopes open through the imported key <c>file-&lt;name&gt;</c> with the File wrap's
/// associated data. Construction checks the settings and the credential directory (no network); <see cref="VerifyAsync"/>
/// (run by <see cref="OpenBaoStartupCheck"/>) proves key attributes and pins.
/// </summary>
internal sealed class OpenBaoKms : IKmsBackend, IVerifyOnlySigningKeys, IDisposable
{
    public const string ProviderName = "OpenBao";
    public const string Prefix = "openbao:";
    public const string LegacyTransitPrefix = "file-";
    public const string RoleIdFile = "role-id";
    public const string SecretIdFile = "secret-id";
    public const string CaFile = "ca.pem";

    public const string NotLinuxMessage = "Outside Development and Testing, Kms:Provider = OpenBao needs Linux (POSIX owner and mode checks of the credential directory).";
    public const string AddressMessage = "Kms:OpenBao:Address must be an absolute https URI with no user name, path, query or fragment (http only in Development and Testing).";
    public const string MountMessage = "Kms:OpenBao:Mount must be a-z, 0-9 and '-' (at most 63 characters).";
    public const string CredentialDirectoryUnsetMessage = "Kms:OpenBao:CredentialDirectory must be set.";
    public const string CredentialMessage = "Kms:OpenBao:CredentialDirectory must hold role-id and secret-id (1 to 256 printable characters, no spaces).";
    public const string CaMessage = "Kms:OpenBao:CredentialDirectory must hold ca.pem with at least one PEM certificate (the only trust anchor for OpenBao's TLS).";
    public const string KeyRefMessage = "OpenBao KMS key references must be openbao:<name> (a-z, 0-9, '-'); file:<name> is accepted only in Kms:Envelope:PreviousKeyRefs (an imported File key) and for Retired signing kids (verify-only).";
    public const string SharedKeyMessage = "An OpenBao key serves two roles: each signing, HMAC and envelope key needs its own Transit key.";
    public const string DevKidMessage = "Outside Development and Testing, the OpenBao KMS refuses the development and test kids (year 0000).";
    public const string OtherEnvironmentMalformedMessage = "Kms:OpenBao:OtherEnvironmentFingerprints entries must be 64 lower-case hex characters.";
    public const string OtherEnvironmentUnsetMessage = "Outside Development and Testing, Kms:OpenBao:OtherEnvironmentFingerprints must list the other environment's fingerprints, or Kms:OpenBao:NoOtherEnvironment must be true.";
    public const string OtherEnvironmentMessage = "An OpenBao key is listed in Kms:OpenBao:OtherEnvironmentFingerprints: keys of another environment are refused.";
    public const string NotDumpableMessage = "Outside Development and Testing, the OpenBao KMS could not mark the process non-dumpable (prctl PR_SET_DUMPABLE); its token and data keys would be exposed to core dumps.";
    public const string UnreachableMessage = "OpenBao could not be used at start (unreachable, sealed, TLS refused, login refused, or a key missing or not allowed by the policy).";
    public const string KeyTypeMessage = "An OpenBao key has the wrong type for its role (ecdsa-p256 for signing, hmac of 32 bytes for HMAC, aes256-gcm96 for envelopes).";
    public const string KeyAttributesMessage = "An OpenBao key is exportable, allows plaintext backup, allows deletion or is soft-deleted; keys must be none of these.";
    public const string KnownTestKeyMessage = "An OpenBao key is a key committed to the repository (test vector, fixture or development seed key).";
    public const string FingerprintMessage = "An OpenBao key does not match its Kms:OpenBao:Fingerprints:<name> pin (missing, malformed or a different key).";
    public const string ScopeMessage = "Kms:Scope = Envelope: this process may only use envelope keys.";

    /// <summary>The pin label: for an <c>hmac</c> key the Transit MAC equals the T-200 File fingerprint (KeyFingerprints).</summary>
    internal static readonly byte[] PinLabel = "zaghlol-kms-file-fingerprint-v1"u8.ToArray();

    internal const string AuthenticationFailed = "cipher: message authentication failed";
    internal const int MaxCredentialLength = 256;
    internal const int MaxWrappedLength = 1024;

    private const string VersionOnePrefix = "vault:v1:";
    private const string P256Oid = "1.2.840.10045.3.1.7";

    private readonly OpenBaoClient client;
    private readonly string mount;
    private readonly KmsScope scope;
    private readonly Dictionary<string, KeyRole> roles;

    private OpenBaoKms(OpenBaoClient client, string mount, KmsScope scope, Dictionary<string, KeyRole> roles)
    {
        this.client = client;
        this.mount = mount;
        this.scope = scope;
        this.roles = roles;
    }

    internal enum KeyKind
    {
        Signing,
        Hmac,
        Envelope,
        LegacyEnvelope,

        /// <summary>A Retired T-200 kid (<c>file:</c>): verify-only, its public key is the configured JWK (pinned); never signs.</summary>
        VerifyOnly,
    }

    /// <summary>The client, for tests (login count).</summary>
    internal OpenBaoClient Client => client;

    /// <summary>The KV v2 mount that holds the LLM provider keys (T-333): <c>zaghlol/llm/&lt;id&gt;</c>.</summary>
    internal const string KvMount = "zaghlol";

    /// <summary>
    /// T-333: reads the KV v2 secret <c>zaghlol/&lt;path&gt;</c> (<c>GET /v1/zaghlol/data/&lt;path&gt;</c>) with this adapter's AppRole
    /// session. Its <c>data</c> must be exactly <c>{"secret": "&lt;text&gt;"}</c>. A 404 is <see cref="KvSecretStatus.NotFound"/>;
    /// a refusal (403 after one re-login), a transport failure or another status throws <see cref="OpenBaoUnavailableException"/>
    /// (the caller runs it under <see cref="KmsCall"/>). The answer buffer is zeroed on return; no path or value reaches a message.
    /// </summary>
    internal async Task<(KvSecretStatus Status, string? Secret)> ReadKvSecretAsync(string path, CancellationToken cancellationToken)
    {
        using var answer = await client.SendAsync(HttpMethod.Get, $"{KvMount}/data/{path}", null, cancellationToken).ConfigureAwait(false);
        if (answer.Status == HttpStatusCode.NotFound)
        {
            return (KvSecretStatus.NotFound, null);
        }

        if (!answer.IsSuccess)
        {
            throw new OpenBaoUnavailableException();
        }

        if (answer.Data is not { } outer
            || !outer.TryGetProperty("data", out var data)
            || data.ValueKind != JsonValueKind.Object)
        {
            return (KvSecretStatus.Malformed, null);
        }

        string? secret = null;
        var members = 0;
        foreach (var member in data.EnumerateObject())
        {
            members++;
            if (member.NameEquals("secret") && member.Value.ValueKind == JsonValueKind.String)
            {
                secret = member.Value.GetString();
            }
        }

        return members == 1 && secret is not null ? (KvSecretStatus.Found, secret) : (KvSecretStatus.Malformed, null);
    }

    internal enum KvSecretStatus
    {
        Found,
        NotFound,
        Malformed,
    }

    /// <summary>Checks every setting and the credential directory, then builds the client. No network call.</summary>
    public static OpenBaoKms Create(KmsSettings settings, IHostEnvironment environment, TimeProvider clock, KmsCallPolicy policy, HttpMessageHandler? handler = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentNullException.ThrowIfNull(policy);

        var strict = !environment.IsDevelopment() && !environment.IsEnvironment("Testing");
        var openBao = settings.OpenBao;

        if (strict && !OperatingSystem.IsLinux())
        {
            throw new KmsConfigurationException(NotLinuxMessage);
        }

        if (strict && settings.SigningKeys.Any(k => k.Kid.Length > 5 && k.Kid.AsSpan(1, 4).SequenceEqual("0000")))
        {
            throw new KmsConfigurationException(DevKidMessage);
        }

        var address = ParseAddress(openBao.Address, strict);
        if (!FileKms.NamePattern().IsMatch(openBao.Mount))
        {
            throw new KmsConfigurationException(MountMessage);
        }

        CheckOtherEnvironmentSettings(openBao, strict);
        var roles = Roles(settings);

        if (string.IsNullOrWhiteSpace(openBao.CredentialDirectory))
        {
            throw new KmsConfigurationException(CredentialDirectoryUnsetMessage);
        }

        // G14: the token, the secret_id and every data key live in this process from here on.
        if (strict && !PosixFiles.SetNotDumpable())
        {
            throw new KmsConfigurationException(NotDumpableMessage);
        }

        var directory = openBao.CredentialDirectory;
        if (OperatingSystem.IsLinux())
        {
            var euid = PosixFiles.EffectiveUid() ?? throw new KmsConfigurationException(Rename(FileKms.DirectoryUnreadableMessage));
            directory = AsCredentialCheck(() => FileKms.CheckDirectory(openBao.CredentialDirectory, euid));
            AsCredentialCheck(() =>
            {
                FileKms.CheckNotInSourceTree(directory, environment);
                FileKms.CheckEntries(directory, euid);
                return directory;
            });
        }

        // Read once now so a missing or malformed credential refuses the start; read again at every login.
        _ = ReadCredentials(directory);
        var roots = address.Scheme == Uri.UriSchemeHttps ? ReadCa(directory) : null;

        var transport = handler ?? OpenBaoClient.CreateHandler(roots, policy.Timeout);
        var client = new OpenBaoClient(address, transport, () => ReadCredentials(directory), clock, policy.Timeout);
        return new OpenBaoKms(client, openBao.Mount, settings.Scope, roles);
    }

    public async ValueTask<byte[]> SignDigestAsync(string keyRef, ReadOnlyMemory<byte> sha256, CancellationToken cancellationToken)
    {
        RequireFullScope();
        var role = Role(keyRef, KeyKind.Signing);
        if (sha256.Length != 32)
        {
            throw new ArgumentException("A SHA-256 digest is 32 bytes.", nameof(sha256));
        }

        var input = Convert.ToBase64String(sha256.Span);
        using var answer = await client.SendAsync(
            HttpMethod.Post,
            $"{mount}/sign/{role.TransitName}/sha2-256",
            w =>
            {
                w.WriteString("input", input);
                w.WriteBoolean("prehashed", true);
                w.WriteString("marshaling_algorithm", "jws");
                w.WriteNumber("key_version", 1);
            },
            cancellationToken).ConfigureAwait(false);

        var text = SuccessString(answer, "signature");
        var signature = new byte[64];
        if (!text.StartsWith(VersionOnePrefix, StringComparison.Ordinal)
            || text.Length != VersionOnePrefix.Length + 86
            || Base64Url.DecodeFromChars(text.AsSpan(VersionOnePrefix.Length), signature, out var consumed, out var written) != System.Buffers.OperationStatus.Done
            || consumed != 86
            || written != 64)
        {
            throw new OpenBaoUnavailableException();
        }

        return signature;
    }

    public async ValueTask<byte[]> GetPublicKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        RequireFullScope();
        var role = Role(keyRef, KeyKind.Signing);
        var info = await ReadKeyAsync(role.TransitName, cancellationToken).ConfigureAwait(false);
        return info.PublicKeyPoint ?? throw new OpenBaoUnavailableException();
    }

    public async ValueTask<byte[]> HmacSha256Async(string keyRef, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        RequireFullScope();
        var role = Role(keyRef, KeyKind.Hmac);
        return await TransitHmacAsync(role.TransitName, data, cancellationToken).ConfigureAwait(false);
    }

    public async ValueTask<DataKey> GenerateDataKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        var role = Role(keyRef, KeyKind.Envelope);
        using var answer = await client.SendAsync(
            HttpMethod.Post,
            $"{mount}/datakey/plaintext/{role.TransitName}",
            w => w.WriteNumber("bits", 256),
            cancellationToken).ConfigureAwait(false);

        var data = SuccessData(answer);
        var wrapped = SuccessString(answer, "ciphertext");
        if (!IsTransitCiphertext(wrapped))
        {
            throw new OpenBaoUnavailableException();
        }

        var plaintext = DecodeKey(data);
        return new DataKey(plaintext, Encoding.ASCII.GetBytes(wrapped));
    }

    public async ValueTask<DataKey> DecryptDataKeyAsync(string keyRef, ReadOnlyMemory<byte> wrapped, CancellationToken cancellationToken)
    {
        var role = Role(keyRef, KeyKind.Envelope, KeyKind.LegacyEnvelope);
        string ciphertext;
        string? associatedData = null;
        if (role.Kind == KeyKind.LegacyEnvelope)
        {
            // A T-200 File wrap: nonce(12) ‖ ciphertext(32) ‖ tag(16), the layout of Transit's AES-GCM ciphertext.
            if (wrapped.Length != FileKms.WrappedSize)
            {
                throw new CryptographicException();
            }

            ciphertext = VersionOnePrefix + Convert.ToBase64String(wrapped.Span);
            associatedData = Convert.ToBase64String(FileKms.WrapAad(keyRef));
        }
        else
        {
            if (wrapped.Length > MaxWrappedLength || wrapped.Span.ContainsAnyExceptInRange((byte)0x21, (byte)0x7E))
            {
                throw new CryptographicException();
            }

            ciphertext = Encoding.ASCII.GetString(wrapped.Span);
            if (!IsTransitCiphertext(ciphertext))
            {
                throw new CryptographicException();
            }
        }

        using var answer = await client.SendAsync(
            HttpMethod.Post,
            $"{mount}/decrypt/{role.TransitName}",
            w =>
            {
                w.WriteString("ciphertext", ciphertext);
                if (associatedData is not null)
                {
                    w.WriteString("associated_data", associatedData);
                }
            },
            cancellationToken).ConfigureAwait(false);

        // Only a proven bad tag is a decryption failure: callers may delete a row that can't be opened (T-135), so a
        // missing key, a too-new version, a denial or an outage must stay "unavailable" (T-201 design note §3).
        if (answer.Status == HttpStatusCode.BadRequest && answer.HasOnlyError(AuthenticationFailed))
        {
            throw new CryptographicException();
        }

        return new DataKey(DecodeKey(SuccessData(answer)), wrapped.ToArray());
    }

    /// <summary>True for a Retired <c>file:</c> kid: no key in OpenBao, nothing to compare at start but its pin.</summary>
    public bool IsVerifyOnly(string keyRef) => roles.TryGetValue(keyRef, out var role) && role.Kind == KeyKind.VerifyOnly;

    public void Dispose() => client.Dispose();

    /// <summary>
    /// The startup proof (T-201 design note §6, O1/O2, G10–G12, G15): each key in scope has the right type and attributes,
    /// is not a committed test key or another environment's key, has a distinct fingerprint and matches its pin.
    /// </summary>
    internal async Task VerifyAsync(KmsSettings settings, KmsCallPolicy policy, TimeProvider clock, CancellationToken cancellationToken)
    {
        var openBao = settings.OpenBao;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var role in roles.Values.Where(r => scope == KmsScope.Full || r.Kind is KeyKind.Envelope or KeyKind.LegacyEnvelope))
        {
            string fingerprint;
            if (role.Kind == KeyKind.VerifyOnly)
            {
                // The T-200 definition (SHA-256 of the SPKI), from the configured public JWK: the pin is the T-200 one.
                using var key = ECDsa.Create(new ECParameters
                {
                    Curve = ECCurve.NamedCurves.nistP256,
                    Q = new ECPoint { X = role.ConfiguredPoint![1..33], Y = role.ConfiguredPoint[33..] },
                });
                fingerprint = Convert.ToHexStringLower(SHA256.HashData(key.ExportSubjectPublicKeyInfo()));
            }
            else
            {
                try
                {
                    var info = await KmsCall.RunAsync(policy, clock, "public_key", ct => new ValueTask<KeyInfo>(ReadKeyAsync(role.TransitName, ct)), cancellationToken);
                    CheckAttributes(role, info);
                    fingerprint = role.Kind == KeyKind.Signing
                        ? info.PublicKeyFingerprint!
                        : Convert.ToHexStringLower(await KmsCall.RunAsync(
                            policy, clock, "hmac", ct => new ValueTask<byte[]>(TransitHmacAsync(role.TransitName, PinLabel, ct)), cancellationToken));
                }
                catch (KmsUnavailableException)
                {
                    throw new KmsConfigurationException(UnreachableMessage);
                }
            }

            if (!seen.Add(fingerprint))
            {
                throw new KmsConfigurationException(SharedKeyMessage);
            }

            var denied = role.Kind switch
            {
                KeyKind.Signing or KeyKind.VerifyOnly => KnownTestKeys.SigningKeys,
                KeyKind.Hmac => KnownTestKeys.Secrets,
                _ => (IReadOnlySet<string>)new HashSet<string>(),
            };
            if (denied.Contains(fingerprint))
            {
                throw new KmsConfigurationException(KnownTestKeyMessage);
            }

            if (openBao.OtherEnvironmentFingerprints.Contains(fingerprint))
            {
                throw new KmsConfigurationException(OtherEnvironmentMessage);
            }

            var pinned = openBao.Fingerprints.GetValueOrDefault(role.TransitName);
            if (!KeyFingerprints.IsWellFormed(pinned)
                || !CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(pinned!), Encoding.ASCII.GetBytes(fingerprint)))
            {
                throw new KmsConfigurationException(FingerprintMessage);
            }
        }
    }

    /// <summary>The Transit name of a key reference, or <c>null</c> when it isn't an OpenBao or legacy File reference.</summary>
    internal static string? TransitName(string keyRef)
    {
        if (keyRef.StartsWith(Prefix, StringComparison.Ordinal))
        {
            var name = keyRef[Prefix.Length..];
            return FileKms.NamePattern().IsMatch(name) ? name : null;
        }

        if (keyRef.StartsWith(FileKms.Prefix, StringComparison.Ordinal))
        {
            var name = LegacyTransitPrefix + keyRef[FileKms.Prefix.Length..];
            return FileKms.NamePattern().IsMatch(name) ? name : null;
        }

        return null;
    }

    /// <summary>Reads <c>role-id</c> and <c>secret-id</c> through the T-200 file checks (Linux) and the format rule.</summary>
    internal static OpenBaoCredentials ReadCredentials(string directory)
    {
        return new OpenBaoCredentials(ReadToken(directory, RoleIdFile), ReadToken(directory, SecretIdFile));

        static string ReadToken(string directory, string name)
        {
            var (buffer, length) = ReadCredentialFile(directory, name);
            try
            {
                var text = buffer.AsSpan(0, length);
                if (text.EndsWith("\n"u8))
                {
                    text = text[..^1];
                }

                if (text.Length is 0 or > MaxCredentialLength || text.ContainsAnyExceptInRange((byte)0x21, (byte)0x7E))
                {
                    throw new KmsConfigurationException(CredentialMessage);
                }

                return Encoding.ASCII.GetString(text);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(buffer);
            }
        }
    }

    private static (byte[] Buffer, int Length) ReadCredentialFile(string directory, string name)
    {
        var path = Path.Combine(directory, name);
        if (OperatingSystem.IsLinux())
        {
            var euid = PosixFiles.EffectiveUid() ?? throw new KmsConfigurationException(CredentialMessage);
            try
            {
                return FileKms.ReadChecked(path, euid);
            }
            catch (KmsConfigurationException ex) when (ex.Message == FileKms.MissingKeyMessage)
            {
                throw new KmsConfigurationException(name == CaFile ? CaMessage : CredentialMessage);
            }
            catch (KmsConfigurationException ex)
            {
                throw new KmsConfigurationException(Rename(ex.Message));
            }
        }

        // Development/Testing off Linux only (Create refuses the rest): no owner/mode to check.
        try
        {
            var bytes = File.ReadAllBytes(path);
            if (bytes.Length > FileKms.MaxFileBytes)
            {
                CryptographicOperations.ZeroMemory(bytes);
                throw new KmsConfigurationException(Rename(FileKms.TooLargeMessage));
            }

            return (bytes, bytes.Length);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new KmsConfigurationException(name == CaFile ? CaMessage : CredentialMessage);
        }
    }

    private static X509Certificate2Collection ReadCa(string directory)
    {
        var (buffer, length) = ReadCredentialFile(directory, CaFile);
        try
        {
            var roots = new X509Certificate2Collection();
            roots.ImportFromPem(Encoding.ASCII.GetString(buffer, 0, length));
            return roots.Count > 0 ? roots : throw new KmsConfigurationException(CaMessage);
        }
        catch (CryptographicException)
        {
            throw new KmsConfigurationException(CaMessage);
        }
    }

    /// <summary>The T-200 guard messages name the File setting; for the credential directory they name the OpenBao one.</summary>
    private static string Rename(string fileMessage) => fileMessage
        .Replace("Kms:File:KeyDirectory", "Kms:OpenBao:CredentialDirectory", StringComparison.Ordinal)
        .Replace("A File KMS key file", "An OpenBao credential file", StringComparison.Ordinal)
        .Replace("key files must be", "credential files must be", StringComparison.Ordinal)
        .Replace("development keys are refused", "development keys are refused here too", StringComparison.Ordinal)
        .Replace("keep production keys outside them", "keep the OpenBao credentials outside them", StringComparison.Ordinal);

    private static string AsCredentialCheck(Func<string> check)
    {
        try
        {
            return check();
        }
        catch (KmsConfigurationException ex)
        {
            throw new KmsConfigurationException(Rename(ex.Message));
        }
    }

    private static Uri ParseAddress(string? value, bool strict)
    {
        if (string.IsNullOrWhiteSpace(value)
            || !Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || !(uri.Scheme == Uri.UriSchemeHttps || (uri.Scheme == Uri.UriSchemeHttp && !strict))
            || uri.UserInfo.Length != 0
            || uri.Query.Length != 0
            || uri.Fragment.Length != 0
            || uri.AbsolutePath != "/"
            || value.Contains('@', StringComparison.Ordinal)
            || value.Contains('#', StringComparison.Ordinal)
            || value.Contains('?', StringComparison.Ordinal))
        {
            throw new KmsConfigurationException(AddressMessage);
        }

        return uri;
    }

    private static void CheckOtherEnvironmentSettings(OpenBaoProviderSettings openBao, bool strict)
    {
        if (openBao.OtherEnvironmentFingerprints.Any(f => !KeyFingerprints.IsWellFormed(f)))
        {
            throw new KmsConfigurationException(OtherEnvironmentMalformedMessage);
        }

        if (strict && openBao.OtherEnvironmentFingerprints.Count == 0 && !openBao.NoOtherEnvironment)
        {
            throw new KmsConfigurationException(OtherEnvironmentUnsetMessage);
        }

        if (openBao.Fingerprints.Values.Any(openBao.OtherEnvironmentFingerprints.Contains))
        {
            throw new KmsConfigurationException(OtherEnvironmentMessage);
        }
    }

    /// <summary>Every configured reference with its role; G7/G15 for OpenBao (T-201 design note §1, §6).</summary>
    private static Dictionary<string, KeyRole> Roles(KmsSettings settings)
    {
        var roles = new Dictionary<string, KeyRole>(StringComparer.Ordinal);

        void Add(string keyRef, KeyKind kind, byte[]? point = null)
        {
            if (kind == KeyKind.VerifyOnly)
            {
                // Lives in no Transit key; its pin is looked up under the File key name (the T-200 pin name).
                var fileName = keyRef[FileKms.Prefix.Length..];
                if (!FileKms.NamePattern().IsMatch(fileName) || roles.ContainsKey(keyRef))
                {
                    throw new KmsConfigurationException(KeyRefMessage);
                }

                roles[keyRef] = new KeyRole(fileName, kind, point);
                return;
            }

            var legacy = keyRef.StartsWith(FileKms.Prefix, StringComparison.Ordinal);
            if (TransitName(keyRef) is not { } name || (legacy && kind != KeyKind.LegacyEnvelope) || (!legacy && kind == KeyKind.LegacyEnvelope))
            {
                throw new KmsConfigurationException(KeyRefMessage);
            }

            if (roles.ContainsKey(keyRef) || roles.Values.Any(r => r.Kind != KeyKind.VerifyOnly && r.TransitName == name))
            {
                throw new KmsConfigurationException(SharedKeyMessage);
            }

            roles[keyRef] = new KeyRole(name, kind);
        }

        foreach (var key in settings.SigningKeys)
        {
            // C1 (review): after the switch-over the T-200 kids stay published as Retired, verify-only; they never sign.
            if (key.Status == SigningKeyStatus.Retired && key.KeyRef.StartsWith(FileKms.Prefix, StringComparison.Ordinal))
            {
                Add(key.KeyRef, KeyKind.VerifyOnly, key.PublicJwk.ToX963());
            }
            else
            {
                Add(key.KeyRef, KeyKind.Signing);
            }
        }

        foreach (var keyRef in settings.HmacKeyRefs.Values)
        {
            Add(keyRef, KeyKind.Hmac);
        }

        if (settings.EnvelopeKeyRef.StartsWith(FileKms.Prefix, StringComparison.Ordinal))
        {
            // New envelopes are wrapped by Transit only; a File KEK may only open old ones.
            throw new KmsConfigurationException(KeyRefMessage);
        }

        foreach (var keyRef in settings.EnvelopeDecryptKeyRefs)
        {
            Add(keyRef, keyRef.StartsWith(FileKms.Prefix, StringComparison.Ordinal) ? KeyKind.LegacyEnvelope : KeyKind.Envelope);
        }

        return roles;
    }

    /// <summary>The key tool's view: no roles, the operator's client.</summary>
    internal static OpenBaoKms ForTool(OpenBaoClient client, string mount) => new(client, mount, KmsScope.Full, new Dictionary<string, KeyRole>());

    internal static void CheckAttributes(KeyRole role, KeyInfo info)
    {
        var expected = role.Kind switch
        {
            KeyKind.Signing => "ecdsa-p256",
            KeyKind.Hmac => "hmac",
            _ => "aes256-gcm96",
        };

        if (!string.Equals(info.Type, expected, StringComparison.Ordinal)
            || (role.Kind == KeyKind.Hmac && info.KeySize != 32)
            || (role.Kind == KeyKind.Signing && info.PublicKeyPoint is null))
        {
            throw new KmsConfigurationException(KeyTypeMessage);
        }

        if (info.Exportable || info.AllowPlaintextBackup || info.DeletionAllowed || info.SoftDeleted || info.LatestVersion < 1)
        {
            throw new KmsConfigurationException(KeyAttributesMessage);
        }
    }

    private static bool IsTransitCiphertext(string value)
    {
        if (value.Length > MaxWrappedLength || !value.StartsWith("vault:v", StringComparison.Ordinal))
        {
            return false;
        }

        var rest = value.AsSpan("vault:v".Length);
        var colon = rest.IndexOf(':');
        if (colon is <= 0 or > 9 || rest[..colon].ContainsAnyExceptInRange('0', '9'))
        {
            return false;
        }

        var body = rest[(colon + 1)..];
        return body.Length > 0 && Base64.IsValid(body);
    }

    private static JsonElement SuccessData(OpenBaoAnswer answer) =>
        answer.IsSuccess && answer.Data is { } data ? data : throw new OpenBaoUnavailableException();

    private static string SuccessString(OpenBaoAnswer answer, string name) =>
        SuccessData(answer).TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String && value.GetString() is { } text
            ? text
            : throw new OpenBaoUnavailableException();

    private static byte[] DecodeKey(JsonElement data)
    {
        if (!data.TryGetProperty("plaintext", out var value)
            || value.ValueKind != JsonValueKind.String
            || !value.TryGetBytesFromBase64(out var key))
        {
            throw new OpenBaoUnavailableException();
        }

        if (key.Length != DataKey.Size)
        {
            CryptographicOperations.ZeroMemory(key);
            throw new OpenBaoUnavailableException();
        }

        return key;
    }

    internal async Task<byte[]> TransitHmacAsync(string transitName, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        var input = Convert.ToBase64String(data.Span);
        using var answer = await client.SendAsync(
            HttpMethod.Post,
            $"{mount}/hmac/{transitName}/sha2-256",
            w =>
            {
                w.WriteString("input", input);
                w.WriteNumber("key_version", 1);
            },
            cancellationToken).ConfigureAwait(false);

        var text = SuccessString(answer, "hmac");
        var mac = new byte[32];
        if (!text.StartsWith(VersionOnePrefix, StringComparison.Ordinal)
            || !Convert.TryFromBase64String(text[VersionOnePrefix.Length..], mac, out var written)
            || written != 32)
        {
            throw new OpenBaoUnavailableException();
        }

        return mac;
    }

    internal async Task<KeyInfo> ReadKeyAsync(string transitName, CancellationToken cancellationToken)
    {
        using var answer = await client.SendAsync(HttpMethod.Get, $"{mount}/keys/{transitName}", body: null, cancellationToken).ConfigureAwait(false);
        var data = SuccessData(answer);

        static bool Flag(JsonElement data, string name) =>
            !data.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.False;

        var type = data.TryGetProperty("type", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() : null;
        var latest = data.TryGetProperty("latest_version", out var l) && l.TryGetInt32(out var v) ? v : 0;
        var keySize = data.TryGetProperty("key_size", out var k) && k.TryGetInt32(out var size) ? size : 0;
        var softDeleted = data.TryGetProperty("soft_deleted", out var sd) && sd.ValueKind == JsonValueKind.True;

        (byte[] Point, string Fingerprint)? publicKey = null;
        if (type == "ecdsa-p256"
            && data.TryGetProperty("keys", out var keys)
            && keys.ValueKind == JsonValueKind.Object
            && keys.TryGetProperty("1", out var first)
            && first.ValueKind == JsonValueKind.Object
            && first.TryGetProperty("public_key", out var pem)
            && pem.ValueKind == JsonValueKind.String)
        {
            publicKey = ParsePublicKey(pem.GetString()!);
        }

        // A missing flag is read as set (fail closed).
        return new KeyInfo(type, Flag(data, "exportable"), Flag(data, "allow_plaintext_backup"), Flag(data, "deletion_allowed"), softDeleted, latest, keySize, publicKey?.Point, publicKey?.Fingerprint);
    }

    /// <summary>A named P-256 public key in PEM → its X9.63 point and the T-200 fingerprint (SHA-256 of the SPKI).</summary>
    private static (byte[] Point, string Fingerprint) ParsePublicKey(string pem)
    {
        if (pem.Length > 4096 || !PemEncoding.TryFind(pem, out var fields) || !pem.AsSpan()[fields.Label].SequenceEqual("PUBLIC KEY"))
        {
            throw new OpenBaoUnavailableException();
        }

        using var key = ECDsa.Create();
        try
        {
            key.ImportFromPem(pem);
            var parameters = key.ExportParameters(includePrivateParameters: false);
            if (!parameters.Curve.IsNamed || !string.Equals(parameters.Curve.Oid?.Value, P256Oid, StringComparison.Ordinal))
            {
                throw new OpenBaoUnavailableException();
            }

            return ([0x04, .. parameters.Q.X!, .. parameters.Q.Y!], Convert.ToHexStringLower(SHA256.HashData(key.ExportSubjectPublicKeyInfo())));
        }
        catch (Exception ex) when (ex is ArgumentException or CryptographicException)
        {
            throw new OpenBaoUnavailableException();
        }
    }

    private void RequireFullScope()
    {
        if (scope != KmsScope.Full)
        {
            throw new KmsConfigurationException(ScopeMessage);
        }
    }

    private KeyRole Role(string keyRef, params KeyKind[] kinds) =>
        roles.TryGetValue(keyRef, out var role) && kinds.Contains(role.Kind)
            ? role
            : throw new KmsConfigurationException("An OpenBao KMS key reference is not configured for this use.");

    /// <param name="TransitName">The Transit key name; for <see cref="KeyKind.VerifyOnly"/> the File key name (pin lookup only).</param>
    /// <param name="ConfiguredPoint">For <see cref="KeyKind.VerifyOnly"/>: the configured public point (X9.63).</param>
    internal sealed record KeyRole(string TransitName, KeyKind Kind, byte[]? ConfiguredPoint = null);

    internal sealed record KeyInfo(
        string? Type,
        bool Exportable,
        bool AllowPlaintextBackup,
        bool DeletionAllowed,
        bool SoftDeleted,
        int LatestVersion,
        int KeySize,
        byte[]? PublicKeyPoint,
        string? PublicKeyFingerprint);
}

/// <summary>
/// Runs <see cref="OpenBaoKms.VerifyAsync"/> before <see cref="KmsStartupCheck"/> when <c>Kms:Provider = OpenBao</c>; a no-op
/// for every other provider (and when tests replace the provider ports).
/// </summary>
internal sealed class OpenBaoStartupCheck(IServiceProvider services) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var settings = services.GetRequiredService<KmsSettings>();
        if (settings.Provider != OpenBaoKms.ProviderName
            || services.GetRequiredService<ISigningKeyProvider>() is not OpenBaoKms openBao)
        {
            return;
        }

        await openBao.VerifyAsync(
            settings,
            services.GetRequiredService<KmsCallPolicy>(),
            services.GetRequiredService<TimeProvider>(),
            cancellationToken);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
