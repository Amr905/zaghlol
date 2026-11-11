using System.Numerics;
using System.Security.Cryptography;

namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// The P-256 primitive of the seat-key verifier (T-182 design note §3 steps 3, 5, 6): an explicit point check in managed code
/// (the curve check of .NET's import differs between OpenSSL and CNG) and ECDSA-SHA-256 over an IEEE P1363 <c>r ‖ s</c>
/// signature. Inputs are public data, so nothing here needs to run in constant time. High-S signatures are accepted on purpose
/// (Secure Enclave doesn't normalise s; §2). Published Wycheproof vectors run through <see cref="VerifyP1363"/>.
/// </summary>
public static class P256
{
    /// <summary>X9.63 uncompressed point: <c>0x04 ‖ X ‖ Y</c>.</summary>
    public const int PointLength = 65;

    /// <summary>IEEE P1363 <c>r ‖ s</c>.</summary>
    public const int SignatureLength = 64;

    private const int FieldLength = 32;

    // FIPS 186-5 / SEC 2 v2 secp256r1; P256ConstantsTests checks them against ECDsa.ExportExplicitParameters.
    internal static readonly BigInteger Prime = Hex("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff");
    internal static readonly BigInteger A = Prime - 3;
    internal static readonly BigInteger B = Hex("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b");
    internal static readonly BigInteger Order = Hex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
    internal static readonly BigInteger Gx = Hex("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296");
    internal static readonly BigInteger Gy = Hex("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5");

    /// <summary>
    /// True only when <paramref name="signature"/> is a valid ECDSA P-256 / SHA-256 signature by <paramref name="point"/> over
    /// <paramref name="message"/>, with the point and signature checks of §3. Never throws on input.
    /// </summary>
    public static bool VerifyP1363(ReadOnlySpan<byte> point, ReadOnlySpan<byte> message, ReadOnlySpan<byte> signature) =>
        Check(point, message, signature) is null;

    /// <summary>§3 steps 3 and 5: length 65, prefix <c>0x04</c>, x &lt; p, y &lt; p and y² ≡ x³ − 3x + b (mod p).</summary>
    public static bool IsUncompressedOnCurve(ReadOnlySpan<byte> point)
    {
        if (point.Length != PointLength || point[0] != 0x04)
        {
            return false;
        }

        var x = Unsigned(point.Slice(1, FieldLength));
        var y = Unsigned(point.Slice(1 + FieldLength, FieldLength));
        if (x >= Prime || y >= Prime)
        {
            return false;
        }

        var left = y * y % Prime;
        var right = (((x * x % Prime * x) + (A * x) + B) % Prime + Prime) % Prime;
        return left == right;
    }

    /// <summary>The rejection for one element, or <see langword="null"/> when it verifies (point first, then signature).</summary>
    internal static SeatKeyRejection? Check(ReadOnlySpan<byte> point, ReadOnlySpan<byte> message, ReadOnlySpan<byte> signature)
    {
        if (!IsUncompressedOnCurve(point))
        {
            return SeatKeyRejection.BadPoint;
        }

        if (signature.Length != SignatureLength)
        {
            return SeatKeyRejection.BadSignature;
        }

        // 1 ≤ r, s ≤ n − 1 explicitly (§3 step 6); the platform verifier refuses these too, so this doesn't depend on it.
        var r = Unsigned(signature[..FieldLength]);
        var s = Unsigned(signature[FieldLength..]);
        if (r.IsZero || s.IsZero || r >= Order || s >= Order)
        {
            return SeatKeyRejection.BadSignature;
        }

        ECDsa key;
        try
        {
            key = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = point.Slice(1, FieldLength).ToArray(), Y = point.Slice(1 + FieldLength, FieldLength).ToArray() },
            });
        }
        catch (CryptographicException)
        {
            return SeatKeyRejection.BadPoint;
        }

        using (key)
        {
            try
            {
                return key.VerifyData(message, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation)
                    ? null
                    : SeatKeyRejection.BadSignature;
            }
            catch (CryptographicException)
            {
                return SeatKeyRejection.BadSignature;
            }
        }
    }

    private static BigInteger Unsigned(ReadOnlySpan<byte> bigEndian) => new(bigEndian, isUnsigned: true, isBigEndian: true);

    private static BigInteger Hex(string hex) => Unsigned(Convert.FromHexString(hex));
}
