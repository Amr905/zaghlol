using System.Diagnostics.CodeAnalysis;
using System.Security.Cryptography;
using Zaghlol.Domain;

namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// A structurally valid <c>seatKeys</c> set in request order (T-182 design note §3 steps 1–4): the count fits the op, every
/// element is canonical base64url of a 65-byte <c>0x04</c> point and a 64-byte signature, and the keys are distinct. Nothing is
/// verified yet. No public member returns key or signature bytes.
/// </summary>
public sealed class ParsedSeatKeys
{
    internal ParsedSeatKeys(SeatOp op, byte[][] points, byte[][] signatures)
    {
        Op = op;
        Points = points;
        Signatures = signatures;
    }

    public SeatOp Op { get; }

    public int Count => Points.Length;

    internal byte[][] Points { get; }

    internal byte[][] Signatures { get; }

    /// <summary>
    /// <c>SHA-256(pk₀ ‖ … ‖ pkₙ₋₁)</c> over the raw 65-byte points in request order: the <c>seatKeysDigest</c> of the restore
    /// <c>clientDataHash</c> (T-185; vectors <c>restore-binding-v1.json</c>). A hash of public keys, not a key.
    /// </summary>
    public byte[] Digest()
    {
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var point in Points)
        {
            sha.AppendData(point);
        }

        return sha.GetHashAndReset();
    }

    public override string ToString() => "***";
}

/// <summary>The <c>seatKeysDigest</c> when the request carries no <c>seatKeys</c>.</summary>
public static class SeatKeysDigest
{
    /// <summary>SHA-256 of the empty string (a fresh copy).</summary>
    public static byte[] Empty => SHA256.HashData([]);
}

/// <summary>
/// A <c>seatKeys</c> set whose every element verified for one op, install and challenge. Only
/// <see cref="SeatKeyProofVerifier"/> constructs it; the keyed hashes (<see cref="SeatKeyHasher"/>) are computed only from it.
/// </summary>
public sealed class VerifiedSeatKeys
{
    internal VerifiedSeatKeys(ParsedSeatKeys parsed, InstallId installId)
    {
        Op = parsed.Op;
        InstallId = installId;
        var keys = new VerifiedSeatKey[parsed.Count];
        for (var i = 0; i < keys.Length; i++)
        {
            keys[i] = new VerifiedSeatKey(i, installId, parsed.Points[i]);
        }

        ElementZero = keys[0];
        Others = keys[1..];
        All = keys;
        digest = parsed.Digest();
    }

    private readonly byte[] digest;

    public SeatOp Op { get; }

    /// <summary>The install the proofs are bound to (from the install token).</summary>
    public InstallId InstallId { get; }

    public int Count => All.Count;

    /// <summary>The caller's own key (backend-api §4.3): registered on the install, never a rebind candidate.</summary>
    public VerifiedSeatKey ElementZero { get; }

    /// <summary>Positions ≥ 1: the only rebind candidates.</summary>
    public IReadOnlyList<VerifiedSeatKey> Others { get; }

    internal IReadOnlyList<VerifiedSeatKey> All { get; }

    /// <summary>The same value as <see cref="ParsedSeatKeys.Digest"/>.</summary>
    public byte[] Digest() => (byte[])digest.Clone();

    public override string ToString() => "***";
}

/// <summary>One verified public key. Its bytes are internal and reach only <see cref="SeatKeyHasher"/>.</summary>
public sealed class VerifiedSeatKey
{
    internal VerifiedSeatKey(int position, InstallId installId, byte[] point)
    {
        Position = position;
        InstallId = installId;
        Point = point;
    }

    /// <summary>The element's index in the request.</summary>
    public int Position { get; }

    internal InstallId InstallId { get; }

    internal byte[] Point { get; }

    public override string ToString() => "***";
}

/// <summary>The outcome of <see cref="SeatKeyProofVerifier.Parse"/>: the parsed set or the first rejection reason.</summary>
public sealed class SeatKeyParseResult
{
    internal SeatKeyParseResult(ParsedSeatKeys keys) => Keys = keys;

    internal SeatKeyParseResult(SeatKeyRejection rejection) => Rejection = rejection;

    public ParsedSeatKeys? Keys { get; }

    public SeatKeyRejection? Rejection { get; }

    [MemberNotNullWhen(true, nameof(Keys))]
    [MemberNotNullWhen(false, nameof(Rejection))]
    public bool IsValid => Keys is not null;

    public override string ToString() => IsValid ? "valid" : SeatKeyTags.Result(Rejection);
}

/// <summary>The outcome of <see cref="SeatKeyProofVerifier.Verify"/>: the verified set or the first failing element's reason.</summary>
public sealed class SeatKeyVerification
{
    internal SeatKeyVerification(VerifiedSeatKeys keys) => Keys = keys;

    internal SeatKeyVerification(SeatKeyRejection rejection) => Rejection = rejection;

    public VerifiedSeatKeys? Keys { get; }

    public SeatKeyRejection? Rejection { get; }

    [MemberNotNullWhen(true, nameof(Keys))]
    [MemberNotNullWhen(false, nameof(Rejection))]
    public bool IsValid => Keys is not null;

    public override string ToString() => IsValid ? "valid" : SeatKeyTags.Result(Rejection);
}
