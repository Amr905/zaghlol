using System.Buffers.Text;
using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// Parses and verifies <c>seatKeys</c> proofs (T-182 design note §2–§3; backend-api §4.3). Both steps are total: bad input is a
/// rejection result, never an exception. Every element must pass; the reason feeds only the metric. T-185 calls
/// <see cref="Parse"/> before App Attest (structural garbage never costs an assertion check), takes
/// <see cref="ParsedSeatKeys.Digest"/>, then calls <see cref="Verify"/>; T-132 and T-135 can call <see cref="ParseAndVerify"/>.
/// </summary>
public sealed class SeatKeyProofVerifier(ISeatKeyMetrics metrics)
{
    /// <summary>The ASCII prefix of every proof message.</summary>
    public const string MessagePrefix = "zaghlol-seat-v1";

    /// <summary>§3 steps 1–4. A rejection is counted in <c>zaghlol.seat.proof</c>; a valid parse is counted by <see cref="Verify"/>.</summary>
    public SeatKeyParseResult Parse(SeatOp op, IReadOnlyList<SeatKeyProofInput?>? inputs)
    {
        var result = SeatKeyParser.Parse(op, inputs);
        if (!result.IsValid)
        {
            metrics.Proof(op, result.Rejection);
        }

        return result;
    }

    /// <summary>
    /// §3 steps 5–7 over every element, with no early exit. <paramref name="installId"/> must come from the authenticated install
    /// token, never from the body. The challenge's op must equal the parsed op (a caller bug otherwise).
    /// </summary>
    public SeatKeyVerification Verify(ParsedSeatKeys parsed, SeatChallenge challenge, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(parsed);
        ArgumentNullException.ThrowIfNull(challenge);
        if (challenge.Op != parsed.Op)
        {
            throw new ArgumentException("The challenge belongs to another op.", nameof(challenge));
        }

        var message = Message(parsed.Op, installId, challenge.Span);
        SeatKeyRejection? first = null;
        for (var i = 0; i < parsed.Count; i++)
        {
            var rejection = P256.Check(parsed.Points[i], message, parsed.Signatures[i]);
            first ??= rejection;
        }

        metrics.Proof(parsed.Op, first);
        return first is { } reason ? new SeatKeyVerification(reason) : new SeatKeyVerification(new VerifiedSeatKeys(parsed, installId));
    }

    /// <summary><see cref="Parse"/> then <see cref="Verify"/>; exactly one metric sample per call.</summary>
    public SeatKeyVerification ParseAndVerify(IReadOnlyList<SeatKeyProofInput?>? inputs, SeatChallenge challenge, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(challenge);
        var parsed = Parse(challenge.Op, inputs);
        return parsed.IsValid ? Verify(parsed.Keys, challenge, installId) : new SeatKeyVerification(parsed.Rejection.Value);
    }

    /// <summary><c>ASCII(prefix) ‖ 0x00 ‖ ASCII(op) ‖ 0x00 ‖ ASCII(installId) ‖ 0x00 ‖ challenge(32)</c> (§2).</summary>
    internal static byte[] Message(SeatOp op, InstallId installId, ReadOnlySpan<byte> challenge)
    {
        if (challenge.Length != SeatChallenge.Length)
        {
            throw new ArgumentException("The challenge must be 32 bytes.", nameof(challenge));
        }

        var wire = SeatOps.Wire(op);
        var install = installId.ToString();
        var message = new byte[MessagePrefix.Length + 1 + wire.Length + 1 + install.Length + 1 + SeatChallenge.Length];
        var at = Encoding.ASCII.GetBytes(MessagePrefix, message);
        message[at++] = 0;
        at += Encoding.ASCII.GetBytes(wire, message.AsSpan(at));
        message[at++] = 0;
        at += Encoding.ASCII.GetBytes(install, message.AsSpan(at));
        message[at++] = 0;
        challenge.CopyTo(message.AsSpan(at));
        return message;
    }
}

/// <summary>§3 steps 1–4: count, strict encoding, prefix, distinct keys. Pure; never throws on input.</summary>
internal static class SeatKeyParser
{
    /// <summary>Base64url characters of a 65-byte point and of a 64-byte signature (no padding).</summary>
    internal const int PublicKeyChars = 87;
    internal const int SignatureChars = 86;

    public static SeatKeyParseResult Parse(SeatOp op, IReadOnlyList<SeatKeyProofInput?>? inputs)
    {
        // Step 1, before any decoding.
        var count = inputs?.Count ?? 0;
        if (count == 0)
        {
            return new SeatKeyParseResult(SeatKeyRejection.Empty);
        }

        if (count > SeatOps.MaxKeys(op))
        {
            return new SeatKeyParseResult(SeatKeyRejection.TooMany);
        }

        var points = new byte[count][];
        var signatures = new byte[count][];
        for (var i = 0; i < count; i++)
        {
            // Step 2.
            var input = inputs![i];
            if (input is null
                || !TryDecodeCanonical(input.PublicKey, PublicKeyChars, P256.PointLength, out points[i])
                || !TryDecodeCanonical(input.Signature, SignatureChars, P256.SignatureLength, out signatures[i]))
            {
                return new SeatKeyParseResult(SeatKeyRejection.Encoding);
            }
        }

        // Step 3: rejects the hybrid prefixes 0x06 / 0x07, which are also 65 bytes.
        foreach (var point in points)
        {
            if (point[0] != 0x04)
            {
                return new SeatKeyParseResult(SeatKeyRejection.BadPoint);
            }
        }

        // Step 4: public data, compared ordinally.
        for (var i = 1; i < count; i++)
        {
            for (var j = 0; j < i; j++)
            {
                if (points[i].AsSpan().SequenceEqual(points[j]))
                {
                    return new SeatKeyParseResult(SeatKeyRejection.Duplicate);
                }
            }
        }

        return new SeatKeyParseResult(new ParsedSeatKeys(op, points, signatures));
    }

    /// <summary>
    /// Exactly <paramref name="chars"/> characters from <c>[A-Za-z0-9_-]</c> that decode to <paramref name="bytes"/> bytes and
    /// re-encode to the same text: rejects padding, whitespace and non-canonical trailing bits, which the decoder would accept.
    /// </summary>
    private static bool TryDecodeCanonical(string? text, int chars, int bytes, out byte[] value)
    {
        value = [];
        if (text is null || text.Length != chars)
        {
            return false;
        }

        foreach (var c in text)
        {
            if (c is not ((>= 'A' and <= 'Z') or (>= 'a' and <= 'z') or (>= '0' and <= '9') or '-' or '_'))
            {
                return false;
            }
        }

        var buffer = new byte[bytes];
        if (Base64Url.DecodeFromChars(text, buffer, out var consumed, out var written) != System.Buffers.OperationStatus.Done
            || consumed != chars
            || written != bytes
            || !string.Equals(Base64Url.EncodeToString(buffer), text, StringComparison.Ordinal))
        {
            return false;
        }

        value = buffer;
        return true;
    }
}
