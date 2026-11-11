using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// The 32-byte challenge a seat-key proof signs, paired with its <see cref="SeatOp"/> so the two can't be mixed up at a call
/// site (T-182 design note §1). The value is public data (a hash the client also knows); it is still never logged.
/// </summary>
public sealed class SeatChallenge
{
    public const int Length = 32;

    private readonly byte[] value;

    private SeatChallenge(SeatOp op, byte[] value)
    {
        Op = op;
        this.value = value;
    }

    public SeatOp Op { get; }

    /// <summary>Verify: SHA-256 of the UTF-8 bytes of the decoded JSON string <c>signedTransaction</c>.</summary>
    public static SeatChallenge ForVerify(string signedTransaction)
    {
        ArgumentNullException.ThrowIfNull(signedTransaction);
        return new SeatChallenge(SeatOp.Verify, SHA256.HashData(Encoding.UTF8.GetBytes(signedTransaction)));
    }

    /// <summary>Restore: the install-bound <c>bodyHash</c> (backend-api §4.3 step 1), exactly 32 bytes.</summary>
    public static SeatChallenge ForRestore(ReadOnlySpan<byte> bodyHash)
    {
        if (bodyHash.Length != Length)
        {
            throw new ArgumentException("The restore bodyHash must be 32 bytes.", nameof(bodyHash));
        }

        return new SeatChallenge(SeatOp.Restore, bodyHash.ToArray());
    }

    /// <summary>Sign-in: SHA-256 of the raw nonce's ASCII bytes. A nonce with a non-ASCII character is a caller bug.</summary>
    public static SeatChallenge ForSignIn(string rawNonce)
    {
        ArgumentNullException.ThrowIfNull(rawNonce);
        if (!Ascii.IsValid(rawNonce))
        {
            throw new ArgumentException("The sign-in nonce must be ASCII.", nameof(rawNonce));
        }

        return new SeatChallenge(SeatOp.SignIn, SHA256.HashData(Encoding.ASCII.GetBytes(rawNonce)));
    }

    /// <summary>A copy of the 32 bytes (test signers and vectors).</summary>
    public byte[] ToArray() => (byte[])value.Clone();

    public override string ToString() => "***";

    internal ReadOnlySpan<byte> Span => value;
}
