using System.Buffers.Text;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Testing;

/// <summary>A defect applied to a valid proof, for negative tests (T-182 design note §3 and §8).</summary>
public enum SeatKeyDefect
{
    /// <summary>A trailing <c>=</c> on the public key.</summary>
    PaddedPublicKey,

    /// <summary><c>==</c> on the signature.</summary>
    PaddedSignature,

    /// <summary>A space inside the public key.</summary>
    WhitespaceInPublicKey,

    /// <summary>The public key's last character with non-zero trailing bits (decodes to the same bytes).</summary>
    NonCanonicalPublicKey,

    /// <summary>The 33-byte compressed form of the key.</summary>
    CompressedKey,

    /// <summary>The 64-byte <c>X ‖ Y</c> without the <c>0x04</c> prefix.</summary>
    TruncatedKey,

    /// <summary>The hybrid prefix <c>0x06</c>.</summary>
    HybridPrefix06,

    /// <summary>The hybrid prefix <c>0x07</c>.</summary>
    HybridPrefix07,

    /// <summary>y + 1 (mod p): off the curve.</summary>
    OffCurve,

    /// <summary><c>0x04</c> and 64 zero bytes.</summary>
    ZeroPoint,

    /// <summary>x = p: a coordinate that is not below p.</summary>
    XEqualsPrime,

    /// <summary>The signature as ASN.1 DER instead of P1363.</summary>
    DerSignature,

    /// <summary>r = 0.</summary>
    RZero,

    /// <summary>s = 0.</summary>
    SZero,

    /// <summary>r = n.</summary>
    REqualsN,

    /// <summary>s = n.</summary>
    SEqualsN,

    /// <summary>The last signature byte flipped.</summary>
    FlippedSignatureBit,

    /// <summary>The generator G presented with this signature.</summary>
    GeneratorKey,
}

/// <summary>
/// Software P-256 seat keys that make <b>real</b> proofs over the documented message (T-182 design note §8), for the seat-key
/// consumers (T-132, T-135, T-184, T-185). Use them with the production <see cref="SeatKeyProofVerifier"/>: there is no
/// always-valid fake verifier, because it would hide a wrong op or challenge in a consumer. The message is built here
/// independently of the production code, so a production message bug fails the tests. Test-only: never referenced by src/.
/// </summary>
public sealed class SeatKeyTestSigner : IDisposable
{
    private static readonly BigInteger P = Hex("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff");
    private static readonly BigInteger N = Hex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
    private static readonly byte[] G = Convert.FromHexString(
        "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5");

    private readonly ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);

    /// <summary>The raw 65-byte X9.63 point.</summary>
    public byte[] PublicPoint
    {
        get
        {
            var q = key.ExportParameters(false).Q;
            return [0x04, .. q.X!, .. q.Y!];
        }
    }

    /// <summary>The point as the 87-character base64url the app sends.</summary>
    public string PublicKey => Base64Url.EncodeToString(PublicPoint);

    /// <summary><c>"zaghlol-seat-v1" ‖ 0x00 ‖ op ‖ 0x00 ‖ installId ‖ 0x00 ‖ challenge</c>, built independently of production.</summary>
    public static byte[] Message(string op, string installId, ReadOnlySpan<byte> challenge) =>
        [.. "zaghlol-seat-v1"u8, 0, .. Encoding.ASCII.GetBytes(op), 0, .. Encoding.ASCII.GetBytes(installId), 0, .. challenge];

    /// <summary>A valid proof for <paramref name="challenge"/> (its op) and <paramref name="installId"/>.</summary>
    public SeatKeyProofInput Prove(SeatChallenge challenge, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(challenge);
        return Prove(SeatOps.Wire(challenge.Op), installId.ToString(), challenge.ToArray());
    }

    /// <summary>A proof over any op literal, install text and challenge bytes (for "other op / install / challenge" tests).</summary>
    public SeatKeyProofInput Prove(string op, string installId, ReadOnlySpan<byte> challenge) =>
        new(PublicKey, Base64Url.EncodeToString(Sign(Message(op, installId, challenge))));

    /// <summary>Signs raw bytes (P1363, possibly high-S as the platform produces it).</summary>
    public byte[] Sign(byte[] message) => key.SignData(message, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);

    /// <summary><paramref name="proof"/>'s signature presented with this signer's public key (key B with key A's signature).</summary>
    public SeatKeyProofInput WithSignatureOf(SeatKeyProofInput proof)
    {
        ArgumentNullException.ThrowIfNull(proof);
        return new SeatKeyProofInput(PublicKey, proof.Signature);
    }

    /// <summary>The same signature with s replaced by n − s (both forms must verify; low-S is never enforced).</summary>
    public static SeatKeyProofInput FlipS(SeatKeyProofInput proof)
    {
        ArgumentNullException.ThrowIfNull(proof);
        var sig = Base64Url.DecodeFromChars(proof.Signature);
        var s = Unsigned(sig.AsSpan(32));
        return proof with { Signature = Base64Url.EncodeToString([.. sig.AsSpan(0, 32), .. Fixed(N - s)]) };
    }

    /// <summary><paramref name="proof"/> with <paramref name="defect"/> applied.</summary>
    public static SeatKeyProofInput Defective(SeatKeyProofInput proof, SeatKeyDefect defect)
    {
        ArgumentNullException.ThrowIfNull(proof);
        var pk = Base64Url.DecodeFromChars(proof.PublicKey);
        var sig = Base64Url.DecodeFromChars(proof.Signature);
        var x = pk.AsSpan(1, 32).ToArray();
        var y = Unsigned(pk.AsSpan(33));
        var r = Unsigned(sig.AsSpan(0, 32));
        var s = Unsigned(sig.AsSpan(32));
        string Key(byte[] bytes) => Base64Url.EncodeToString(bytes);
        string Sig(byte[] bytes) => Base64Url.EncodeToString(bytes);

        return defect switch
        {
            SeatKeyDefect.PaddedPublicKey => proof with { PublicKey = proof.PublicKey + "=" },
            SeatKeyDefect.PaddedSignature => proof with { Signature = proof.Signature + "==" },
            SeatKeyDefect.WhitespaceInPublicKey => proof with { PublicKey = proof.PublicKey[..40] + " " + proof.PublicKey[40..] },
            SeatKeyDefect.NonCanonicalPublicKey => proof with { PublicKey = NonCanonical(proof.PublicKey) },
            SeatKeyDefect.CompressedKey => proof with { PublicKey = Key([(byte)(y.IsEven ? 0x02 : 0x03), .. x]) },
            SeatKeyDefect.TruncatedKey => proof with { PublicKey = Key(pk[1..]) },
            SeatKeyDefect.HybridPrefix06 => proof with { PublicKey = Key([0x06, .. pk[1..]]) },
            SeatKeyDefect.HybridPrefix07 => proof with { PublicKey = Key([0x07, .. pk[1..]]) },
            SeatKeyDefect.OffCurve => proof with { PublicKey = Key([0x04, .. x, .. Fixed((y + 1) % P)]) },
            SeatKeyDefect.ZeroPoint => proof with { PublicKey = Key([0x04, .. new byte[64]]) },
            SeatKeyDefect.XEqualsPrime => proof with { PublicKey = Key([0x04, .. Fixed(P), .. pk[33..]]) },
            SeatKeyDefect.DerSignature => proof with { Signature = Sig(Der(r, s)) },
            SeatKeyDefect.RZero => proof with { Signature = Sig([.. new byte[32], .. sig[32..]]) },
            SeatKeyDefect.SZero => proof with { Signature = Sig([.. sig[..32], .. new byte[32]]) },
            SeatKeyDefect.REqualsN => proof with { Signature = Sig([.. Fixed(N), .. sig[32..]]) },
            SeatKeyDefect.SEqualsN => proof with { Signature = Sig([.. sig[..32], .. Fixed(N)]) },
            SeatKeyDefect.FlippedSignatureBit => proof with { Signature = Sig([.. sig[..63], (byte)(sig[63] ^ 0x01)]) },
            SeatKeyDefect.GeneratorKey => proof with { PublicKey = Key(G) },
            _ => throw new ArgumentOutOfRangeException(nameof(defect)),
        };
    }

    /// <summary>The rejection the production verifier must give for a set whose only defect is <paramref name="defect"/>.</summary>
    public static SeatKeyRejection ExpectedRejection(SeatKeyDefect defect) => defect switch
    {
        SeatKeyDefect.PaddedPublicKey or SeatKeyDefect.PaddedSignature or SeatKeyDefect.WhitespaceInPublicKey
            or SeatKeyDefect.NonCanonicalPublicKey or SeatKeyDefect.CompressedKey or SeatKeyDefect.TruncatedKey
            or SeatKeyDefect.DerSignature => SeatKeyRejection.Encoding,
        SeatKeyDefect.HybridPrefix06 or SeatKeyDefect.HybridPrefix07 or SeatKeyDefect.OffCurve or SeatKeyDefect.ZeroPoint
            or SeatKeyDefect.XEqualsPrime => SeatKeyRejection.BadPoint,
        _ => SeatKeyRejection.BadSignature,
    };

    public void Dispose() => key.Dispose();

    private static string NonCanonical(string text)
    {
        const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

        // 87 characters carry 522 bits for 520: the last character's two low bits must be zero, so +1 changes no byte.
        return text[..^1] + Alphabet[Alphabet.IndexOf(text[^1], StringComparison.Ordinal) | 1];
    }

    private static byte[] Der(BigInteger r, BigInteger s)
    {
        static byte[] Integer(BigInteger value)
        {
            var bytes = value.ToByteArray(isUnsigned: false, isBigEndian: true);
            return [0x02, (byte)bytes.Length, .. bytes];
        }

        byte[] body = [.. Integer(r), .. Integer(s)];
        return [0x30, (byte)body.Length, .. body];
    }

    private static byte[] Fixed(BigInteger value)
    {
        var bytes = value.ToByteArray(isUnsigned: true, isBigEndian: true);
        return [.. new byte[32 - bytes.Length], .. bytes];
    }

    private static BigInteger Unsigned(ReadOnlySpan<byte> bytes) => new(bytes, isUnsigned: true, isBigEndian: true);

    private static BigInteger Hex(string hex) => Unsigned(Convert.FromHexString(hex));
}
