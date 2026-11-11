namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// Why a <c>seatKeys</c> set was rejected (T-182 design note §3). It feeds only the <c>zaghlol.seat.proof</c> metric, never a
/// response: restore and sign-in answer the same <c>400 VALIDATION_FAILED</c> for every reason, verify ignores the set.
/// </summary>
public enum SeatKeyRejection
{
    /// <summary>No element.</summary>
    Empty,

    /// <summary>More elements than the op allows.</summary>
    TooMany,

    /// <summary>Not exactly 87 / 86 canonical base64url characters (padding, whitespace, trailing bits, wrong size, DER).</summary>
    Encoding,

    /// <summary>Not an uncompressed (<c>0x04</c>) P-256 point on the curve with coordinates below p.</summary>
    BadPoint,

    /// <summary>The same public key twice.</summary>
    Duplicate,

    /// <summary>r or s out of [1, n − 1], or the signature doesn't verify over the message.</summary>
    BadSignature,
}

/// <summary>The fixed metric tag words of the seat-key module (observability metrics table, T-182 design note §7).</summary>
public static class SeatKeyTags
{
    public const string Valid = "valid";

    /// <summary>Every <c>result</c> value of <c>zaghlol.seat.proof</c>.</summary>
    public static IReadOnlyList<string> Results { get; } = ["valid", "empty", "too_many", "encoding", "bad_point", "duplicate", "bad_signature"];

    /// <summary>Every <c>status</c> value of <c>zaghlol.seat.element_zero</c>.</summary>
    public static IReadOnlyList<string> ElementZeroStatuses { get; } = ["none_registered", "matches", "mismatch"];

    /// <summary><c>valid</c> for <see langword="null"/>, else the reason word.</summary>
    public static string Result(SeatKeyRejection? rejection) => rejection switch
    {
        null => Valid,
        SeatKeyRejection.Empty => "empty",
        SeatKeyRejection.TooMany => "too_many",
        SeatKeyRejection.Encoding => "encoding",
        SeatKeyRejection.BadPoint => "bad_point",
        SeatKeyRejection.Duplicate => "duplicate",
        SeatKeyRejection.BadSignature => "bad_signature",
        _ => throw new ArgumentOutOfRangeException(nameof(rejection)),
    };

    public static string Status(ElementZeroStatus status) => status switch
    {
        ElementZeroStatus.NoneRegistered => "none_registered",
        ElementZeroStatus.MatchesRegistered => "matches",
        ElementZeroStatus.Mismatch => "mismatch",
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };
}

/// <summary>
/// The seat-key metrics (<c>zaghlol.seat.proof{op, result}</c>, <c>zaghlol.seat.element_zero{op, status}</c>), implemented by
/// <c>ZaghlolMetrics</c>. Only fixed words reach the tags: no IDs, keys, hashes or key prefixes.
/// </summary>
public interface ISeatKeyMetrics
{
    /// <summary>A set reached a decision: <paramref name="rejection"/> is <see langword="null"/> when it verified.</summary>
    void Proof(SeatOp op, SeatKeyRejection? rejection);

    void ElementZero(SeatOp op, ElementZeroStatus status);
}
