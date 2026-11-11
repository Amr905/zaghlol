using System.Security.Cryptography;
using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// The store-side install binding (T-130 design note §5; backend-api §4.3): the value the app sets as Play
/// <c>obfuscatedAccountId</c> and Apple <c>appAccountToken</c> at purchase, and verify compares with the install that the
/// install token authenticates. <c>StoreBindingRef(id)</c> = the first 16 bytes of
/// <c>HMAC-SHA256(key = ASCII "zaghlol-store-binding-v1", msg = ASCII lower-case 36-character installId)</c>, with the RFC 9562
/// version 8 and variant bits set, written as a lower-case hyphenated UUID in network byte order.
/// </summary>
/// <remarks>
/// The key is a public domain separator, not a secret: the check compares the store's value with the install the token
/// authenticates, so knowing another install's value lets nobody act as that install. Shared vectors:
/// <c>backend/tests/Zaghlol.Contract.Tests/vectors/store-binding-v1.json</c> (T-145 Dart, T-131, T-130).
/// </remarks>
public static class StoreBindingRef
{
    /// <summary>The HMAC key: ASCII bytes of this label.</summary>
    public const string KeyLabel = "zaghlol-store-binding-v1";

    /// <summary>Lower-case hyphenated UUID: 36 characters.</summary>
    public const int Length = 36;

    private static readonly byte[] Key = Encoding.ASCII.GetBytes(KeyLabel);

    public static string Compute(InstallId installId)
    {
        Span<byte> mac = stackalloc byte[32];
        HMACSHA256.HashData(Key, Encoding.ASCII.GetBytes(installId.ToString()), mac);
        var bytes = mac[..16];
        bytes[6] = (byte)((bytes[6] & 0x0F) | 0x80); // version 8
        bytes[8] = (byte)((bytes[8] & 0x3F) | 0x80); // variant 10xx
        var hex = Convert.ToHexStringLower(bytes);
        return $"{hex[..8]}-{hex[8..12]}-{hex[12..16]}-{hex[16..20]}-{hex[20..]}";
    }

    /// <summary>
    /// True when <paramref name="storeValue"/> is exactly <see cref="Compute"/> of <paramref name="installId"/>, compared in
    /// constant time over the fixed length. A missing or differently sized value is false.
    /// </summary>
    public static bool Matches(string? storeValue, InstallId installId)
    {
        if (storeValue is null || storeValue.Length != Length)
        {
            return false;
        }

        var expected = Encoding.ASCII.GetBytes(Compute(installId));
        var actual = Encoding.UTF8.GetBytes(storeValue);
        return actual.Length == expected.Length && CryptographicOperations.FixedTimeEquals(actual, expected);
    }

    /// <summary>
    /// Apple <c>appAccountToken</c> (T-131 §3 step 4): parsed as a hyphenated UUID (any hex case), its 16 bytes compared in constant
    /// time with <see cref="Compute"/> of <paramref name="installId"/>. Absent or unparsable is false.
    /// </summary>
    public static bool MatchesAppAccountToken(string? appAccountToken, InstallId installId)
    {
        if (!TryCanonicalUuid(appAccountToken, out var actual))
        {
            return false;
        }

        Span<byte> actualBytes = stackalloc byte[16];
        Span<byte> expectedBytes = stackalloc byte[16];
        Guid.ParseExact(actual, "D").TryWriteBytes(actualBytes, bigEndian: true, out _);
        Guid.ParseExact(Compute(installId), "D").TryWriteBytes(expectedBytes, bigEndian: true, out _);
        return CryptographicOperations.FixedTimeEquals(actualBytes, expectedBytes);
    }

    /// <summary>The lower-case hyphenated form of a hyphenated UUID string (what <c>obfuscated_install_ref</c> stores for Apple).</summary>
    public static bool TryCanonicalUuid(string? value, out string canonical)
    {
        if (value is { Length: Length } && Guid.TryParseExact(value, "D", out var uuid))
        {
            canonical = uuid.ToString("D");
            return true;
        }

        canonical = string.Empty;
        return false;
    }
}
