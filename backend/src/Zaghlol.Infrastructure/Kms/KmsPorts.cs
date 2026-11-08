using System.Buffers.Text;

namespace Zaghlol.Infrastructure.Kms;

// The KMS abstraction (T-123 design note). No member of any type in this namespace returns private, HMAC or data-key
// material; KmsSurfaceTests asserts it by reflection.

/// <summary>What a signing key is for. Kids carry the purpose as their first letter.</summary>
public enum SigningPurpose
{
    /// <summary><c>s…</c> kids: every <c>Zaghlol-Signature</c> header and catalog <c>.sig</c> file.</summary>
    Sync,

    /// <summary><c>e…</c> kids: JWS tokens (entitlement and account).</summary>
    Entitlement,
}

/// <summary>Rotation state of a key in the ring.</summary>
public enum SigningKeyStatus
{
    /// <summary>Published (embedded in the app at least one release early); never signs.</summary>
    Next,

    /// <summary>The one key of its purpose that signs.</summary>
    Active,

    /// <summary>Never signs; stays published until the app release that drops it.</summary>
    Retired,
}

/// <summary>One entry of the key ring (<c>Signing:Keys[]</c>). <see cref="KeyRef"/> names the key inside the KMS.</summary>
public sealed record SigningKey(string Kid, SigningPurpose Purpose, SigningKeyStatus Status, string KeyRef, EcPublicJwk PublicJwk);

/// <summary>An ECDSA P-256 / SHA-256 signature in IEEE P1363 form (<c>r‖s</c>, 64 bytes) and the kid that made it.</summary>
public sealed record ResponseSignature(string Kid, ReadOnlyMemory<byte> Signature)
{
    /// <summary>The <c>Zaghlol-Signature</c> header value: <c>kid=&lt;kid&gt;; alg=ES256; sig=&lt;86 base64url chars&gt;</c>.</summary>
    public string HeaderValue => $"kid={Kid}; alg=ES256; sig={Base64Url.EncodeToString(Signature.Span)}";
}

/// <summary>Asymmetric P-256 signing inside the KMS, one adapter per KMS. Keys never leave it.</summary>
public interface ISigningKeyProvider
{
    /// <summary>Signs a SHA-256 digest; returns the IEEE P1363 <c>r‖s</c> signature (64 bytes).</summary>
    ValueTask<byte[]> SignDigestAsync(string keyRef, ReadOnlyMemory<byte> sha256, CancellationToken cancellationToken);

    /// <summary>The key's public point in X9.63 uncompressed form (65 bytes). Used by the startup check only.</summary>
    ValueTask<byte[]> GetPublicKeyAsync(string keyRef, CancellationToken cancellationToken);
}

/// <summary>HMAC-SHA256 computed inside the KMS.</summary>
public interface IHmacProvider
{
    /// <summary>HMAC-SHA256 of <paramref name="data"/> under the KMS key <paramref name="keyRef"/> (32 bytes).</summary>
    ValueTask<byte[]> HmacSha256Async(string keyRef, ReadOnlyMemory<byte> data, CancellationToken cancellationToken);
}

/// <summary>Envelope data keys: generated and unwrapped by the KMS under a key-encryption key.</summary>
public interface IDataKeyProvider
{
    /// <summary>A fresh 256-bit data key and its wrapped form under <paramref name="keyRef"/>.</summary>
    ValueTask<DataKey> GenerateDataKeyAsync(string keyRef, CancellationToken cancellationToken);

    /// <summary>Unwraps a data key made by <see cref="GenerateDataKeyAsync"/>. Throws <c>CryptographicException</c> when it doesn't unwrap.</summary>
    ValueTask<DataKey> DecryptDataKeyAsync(string keyRef, ReadOnlyMemory<byte> wrapped, CancellationToken cancellationToken);
}

/// <summary>What callers use to sign. Only the active key of a purpose signs.</summary>
public interface ISigner
{
    /// <summary>
    /// ES256 over the exact <paramref name="data"/> bytes with the active <see cref="SigningPurpose.Sync"/> key (response
    /// bodies, catalog snapshots). Throws <see cref="KmsUnavailableException"/> when the KMS can't sign.
    /// </summary>
    ValueTask<ResponseSignature> SignAsync(SigningPurpose purpose, ReadOnlyMemory<byte> data, CancellationToken cancellationToken);

    /// <summary>
    /// A compact JWS with header <c>{"alg":"ES256","kid":…,"typ":"JWT"}</c> over <paramref name="payload"/> serialized by
    /// System.Text.Json (web defaults, no indentation), signed with the active <see cref="SigningPurpose.Entitlement"/> key.
    /// </summary>
    ValueTask<string> CreateJwsAsync<T>(SigningPurpose purpose, T payload, CancellationToken cancellationToken);

    /// <summary>Every published key of a purpose (next, active and retired), for verification and the JWKS export.</summary>
    IReadOnlyList<SigningKey> PublishedKeys(SigningPurpose purpose);
}

/// <summary>The keyed-hash keys. Domain separation of the input belongs to the caller.</summary>
public enum KeyedHashKey
{
    /// <summary><c>K_seat</c> (D-55 <c>device_key_hash</c>).</summary>
    Seat,

    /// <summary><c>K_audit</c> (support-lookup e-mails).</summary>
    Audit,

    /// <summary>The <c>install_hash</c> pepper.</summary>
    InstallHashPepper,
}

/// <summary>Raw HMAC-SHA256 through the KMS. The key never leaves the KMS in production.</summary>
public interface IKeyedHasher
{
    ValueTask<byte[]> HmacSha256Async(KeyedHashKey key, ReadOnlyMemory<byte> data, CancellationToken cancellationToken);
}

/// <summary>
/// Envelope encryption (format v1, AES-256-GCM with a fresh data key per record) for idempotency bodies and Apple
/// refresh tokens. <c>context</c> is bound as associated data, so a ciphertext copied to another row doesn't decrypt.
/// </summary>
public interface IEnvelopeCipher
{
    ValueTask<byte[]> EncryptAsync(ReadOnlyMemory<byte> plain, string context, CancellationToken cancellationToken);

    /// <summary>Throws <see cref="EnvelopeDecryptionException"/> for a malformed, tampered or mis-bound blob.</summary>
    ValueTask<byte[]> DecryptAsync(ReadOnlyMemory<byte> blob, string context, CancellationToken cancellationToken);
}
