namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>The request a seat-key proof belongs to (backend-api §4.3 <i>Same-iPhone recognition</i>).</summary>
public enum SeatOp
{
    /// <summary><c>POST /v1/purchases/verify</c>: challenge = SHA-256 of the <c>signedTransaction</c>; at most 1 key.</summary>
    Verify,

    /// <summary><c>POST /v1/purchases/restore</c>: challenge = the install-bound <c>bodyHash</c>; at most 5 keys.</summary>
    Restore,

    /// <summary><c>POST /v1/accounts/signin</c>: challenge = SHA-256 of the raw nonce; at most 5 keys.</summary>
    SignIn,
}

/// <summary>Wire literals and limits per <see cref="SeatOp"/> (T-182 design note §2–§3).</summary>
public static class SeatOps
{
    /// <summary>The ASCII literal signed into the proof message and used as the metric tag.</summary>
    public static string Wire(SeatOp op) => op switch
    {
        SeatOp.Verify => "verify",
        SeatOp.Restore => "restore",
        SeatOp.SignIn => "signin",
        _ => throw new ArgumentOutOfRangeException(nameof(op)),
    };

    /// <summary>The largest <c>seatKeys</c> array accepted for <paramref name="op"/>.</summary>
    public static int MaxKeys(SeatOp op) => op switch
    {
        SeatOp.Verify => 1,
        SeatOp.Restore or SeatOp.SignIn => 5,
        _ => throw new ArgumentOutOfRangeException(nameof(op)),
    };
}
