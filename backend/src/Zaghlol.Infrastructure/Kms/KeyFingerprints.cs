using System.Security.Cryptography;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// Public, one-way fingerprints of File-provider keys (T-200 design note §5), pinned in <c>Kms:File:Fingerprints:&lt;name&gt;</c>
/// and printed by the production key tool. A signing key: SHA-256 of its DER SubjectPublicKeyInfo. A 32-byte key:
/// HMAC-SHA256(key, <c>"zaghlol-kms-file-fingerprint-v1"</c>). Both are lower-case hex.
/// </summary>
public static class KeyFingerprints
{
    private static readonly byte[] SymmetricLabel = "zaghlol-kms-file-fingerprint-v1"u8.ToArray();

    /// <summary>The fingerprint of a P-256 key (only the public half is read).</summary>
    public static string OfSigningKey(ECDsa key)
    {
        ArgumentNullException.ThrowIfNull(key);
        return Convert.ToHexStringLower(SHA256.HashData(key.ExportSubjectPublicKeyInfo()));
    }

    /// <summary>The fingerprint of a 32-byte HMAC or key-encryption key.</summary>
    public static string OfSecret(ReadOnlySpan<byte> secret) => Convert.ToHexStringLower(HMACSHA256.HashData(secret, SymmetricLabel));

    /// <summary>64 lower-case hex characters.</summary>
    public static bool IsWellFormed(string? value) =>
        value is { Length: 64 } && value.All(c => c is (>= '0' and <= '9') or (>= 'a' and <= 'f'));
}

/// <summary>
/// T-200 design note §4: keys whose private half (or, for vectors, public half) is committed to this repository. The File
/// provider refuses any of them in every environment. <c>KnownTestKeysTests</c> scans the committed files and fails when a key
/// there is missing here.
/// </summary>
internal static class KnownTestKeys
{
    /// <summary>SHA-256 of the SubjectPublicKeyInfo (<see cref="KeyFingerprints.OfSigningKey"/>).</summary>
    public static readonly IReadOnlySet<string> SigningKeys = new HashSet<string>(StringComparer.Ordinal)
    {
        // tools/catalog_build/dev/dev_signing_key.json (kid s0000a), also used as kid s2026a in catalog_build_test.dart.
        "ad9ff1919f982e118731b71ab679038b10fc2e74b1a6c267eb2886fce8c6b0a2",

        // backend/tests/Zaghlol.Contract.Tests/vectors/catalog-snapshot-v1.json (s0000t).
        "3de8200d8b9b5bb06afb2e2394ff128d984b72f2d9197ee12902a5819675df54",

        // vectors/jws-es256-v1.json and response-signature-v1.json (s0000t, e0000t).
        "cc3e2778daf176f2d26954808fd009afa9b7fff562426d9344642ec184a56282",
        "ffc1c01baa595f2547596bc08b9af2ee0f14c9a909a5725756b224a289710fc1",
    };

    /// <summary><see cref="KeyFingerprints.OfSecret"/> of committed 32-byte keys.</summary>
    public static readonly IReadOnlySet<string> Secrets = new HashSet<string>(StringComparer.Ordinal)
    {
        // The fixed K_seat of vectors/seat-key-hash-v1.json and FakeKms.FixedSeatKey: bytes 00 01 .. 1f.
        "bbf16193521b15cd67957193648fb1924f0e312a1ae4bce8dcde2684476a5ce2",
    };

    /// <summary>
    /// Fewer than 16 distinct byte values: all-zero, repeated or counting patterns. A random 32-byte key has about 30, and the
    /// chance that one has 16 or fewer is far below 2^-100.
    /// </summary>
    public static bool IsDegenerate(ReadOnlySpan<byte> secret)
    {
        Span<bool> seen = stackalloc bool[256];
        var distinct = 0;
        foreach (var b in secret)
        {
            if (!seen[b])
            {
                seen[b] = true;
                distinct++;
            }
        }

        return distinct < 16;
    }
}
