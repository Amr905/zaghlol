using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// HMAC-SHA256 under <c>K_seat</c>, computed inside the KMS (Infrastructure <c>KmsSeatKeyMac</c> over
/// <c>IKeyedHasher.HmacSha256Async(KeyedHashKey.Seat, …)</c>). Throws the KMS's unavailable exception (503) and never returns a
/// placeholder.
/// </summary>
public interface ISeatKeyMac
{
    ValueTask<byte[]> MacAsync(ReadOnlyMemory<byte> input, CancellationToken cancellationToken);
}

/// <summary>How element 0 relates to the install's registered key (backend-api §4.3, R4-1(1)).</summary>
public enum ElementZeroStatus
{
    /// <summary><c>installs.seat_key_hash</c> is NULL: the seat service (T-184) registers <see cref="ElementZeroCheck.Computed"/>.</summary>
    NoneRegistered,

    /// <summary>Element 0 is the registered key.</summary>
    MatchesRegistered,

    /// <summary>Restore / sign-in: <c>400 SEAT_KEY_MISMATCH</c>; verify: ignore the proof.</summary>
    Mismatch,
}

/// <summary>The element-0 status and the hash computed for it, so T-184 registers it without a second KMS call.</summary>
public sealed record ElementZeroCheck(ElementZeroStatus Status, InstallKeyHash Computed);

/// <summary>
/// The <c>K_seat</c> keyed hashes (T-182 design note §4). UUIDs are their 36-character lower-case text; keys are the raw 65-byte
/// points, and only verified keys are ever hashed. The three inputs have fixed, pairwise different lengths (109, 101, 22 bytes)
/// and start with different bytes (<c>i</c>, a hex digit, <c>z</c>), so no input of one construction equals an input of another.
/// KMS failures propagate; callers never read a failure as "no match", "none registered" or a NULL hash.
/// </summary>
public sealed class SeatKeyHasher(ISeatKeyMac mac, ISeatKeyMetrics metrics)
{
    public const string InstallLabel = "install";

    /// <summary>The startup check value is HMAC(<c>K_seat</c>, ASCII of this label) (deployment §3).</summary>
    public const string SeatCheckLabel = "zaghlol-kseat-check-v1";

    internal const int InstallInputLength = 7 + 1 + 36 + P256.PointLength;
    internal const int SeatInputLength = 36 + P256.PointLength;

    /// <summary>
    /// Element 0 against the install's registered hash (<paramref name="registered"/> is NULL when none is stored). The keys must
    /// have been verified for <paramref name="installId"/>. Counted in <c>zaghlol.seat.element_zero</c>.
    /// </summary>
    public async Task<ElementZeroCheck> CheckElementZeroAsync(
        InstallId installId, InstallKeyHash? registered, VerifiedSeatKeys keys, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(keys);
        var computed = await InstallKeyHashAsync(installId, keys.ElementZero, cancellationToken).ConfigureAwait(false);
        var status = registered is null
            ? ElementZeroStatus.NoneRegistered
            : computed.Matches(registered) ? ElementZeroStatus.MatchesRegistered : ElementZeroStatus.Mismatch;
        metrics.ElementZero(keys.Op, status);
        return new ElementZeroCheck(status, computed);
    }

    /// <summary><c>HMAC(K_seat, "install" ‖ 0x00 ‖ installId ‖ pk)</c>.</summary>
    public async Task<InstallKeyHash> InstallKeyHashAsync(InstallId installId, VerifiedSeatKey key, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(key);
        if (key.InstallId != installId)
        {
            throw new ArgumentException("The key was verified for another install.", nameof(key));
        }

        var value = await mac.MacAsync(InstallKeyInput(installId, key.Point), cancellationToken).ConfigureAwait(false);
        return InstallKeyHash.FromMac(value);
    }

    /// <summary><c>HMAC(K_seat, purchaseId ‖ pk)</c>: the value T-184 writes to <c>device_key_hash</c> (from element 0).</summary>
    public async Task<SeatKeyHash> SeatKeyHashAsync(Guid purchaseId, VerifiedSeatKey key, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(key);
        var value = await mac.MacAsync(SeatKeyInput(purchaseId, key.Point), cancellationToken).ConfigureAwait(false);
        return SeatKeyHash.FromMac(value);
    }

    /// <summary>
    /// The position (≥ 1) of the key whose seat hash equals <paramref name="stored"/>, or <see langword="null"/>. Element 0 is
    /// never a candidate (backend-api §4.3, rebind condition 2). Every position ≥ 1 is hashed and compared in constant time,
    /// with no early exit: at most 4 KMS calls, run in parallel.
    /// </summary>
    public async Task<int?> MatchSeatAsync(Guid purchaseId, SeatKeyHash stored, VerifiedSeatKeys keys, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(stored);
        ArgumentNullException.ThrowIfNull(keys);

        // MaxKeys is 5, so there are at most 4 candidates and therefore at most 4 calls in flight.
        var hashes = await Task.WhenAll(keys.Others.Select(k => SeatKeyHashAsync(purchaseId, k, cancellationToken))).ConfigureAwait(false);
        int? match = null;
        for (var i = 0; i < hashes.Length; i++)
        {
            var equal = hashes[i].Matches(stored);
            if (equal && match is null)
            {
                match = keys.Others[i].Position;
            }
        }

        return match;
    }

    /// <summary>HMAC(<c>K_seat</c>, <c>"zaghlol-kseat-check-v1"</c>), the startup check value. Not a secret.</summary>
    public async Task<byte[]> SeatCheckAsync(CancellationToken cancellationToken) =>
        await mac.MacAsync(SeatCheckInput(), cancellationToken).ConfigureAwait(false);

    /// <summary>22 bytes: ASCII <see cref="SeatCheckLabel"/>.</summary>
    internal static byte[] SeatCheckInput() => Encoding.ASCII.GetBytes(SeatCheckLabel);

    /// <summary>109 bytes: <c>ASCII("install") ‖ 0x00 ‖ ASCII(installId, 36) ‖ pk(65)</c>.</summary>
    internal static byte[] InstallKeyInput(InstallId installId, ReadOnlySpan<byte> point)
    {
        CheckPoint(point);
        var input = new byte[InstallInputLength];
        var at = Encoding.ASCII.GetBytes(InstallLabel, input);
        input[at++] = 0;
        at += Encoding.ASCII.GetBytes(installId.ToString(), input.AsSpan(at));
        point.CopyTo(input.AsSpan(at));
        return input;
    }

    /// <summary>101 bytes: <c>ASCII(purchaseId, 36, lower-case "D") ‖ pk(65)</c>.</summary>
    internal static byte[] SeatKeyInput(Guid purchaseId, ReadOnlySpan<byte> point)
    {
        CheckPoint(point);
        var input = new byte[SeatInputLength];
        var at = Encoding.ASCII.GetBytes(purchaseId.ToString("D", CultureInfo.InvariantCulture), input);
        point.CopyTo(input.AsSpan(at));
        return input;
    }

    private static void CheckPoint(ReadOnlySpan<byte> point)
    {
        if (point.Length != P256.PointLength || point[0] != 0x04)
        {
            throw new ArgumentException("A seat key must be a 65-byte uncompressed point.", nameof(point));
        }
    }
}

/// <summary>The constant-time check of a startup check value (hex text from configuration) against the computed MAC.</summary>
public static class SeatCheckValue
{
    /// <summary>True only for exactly 64 lower-case hex characters.</summary>
    public static bool IsWellFormed(string? hex) =>
        hex is { Length: 64 } && hex.All(c => c is (>= '0' and <= '9') or (>= 'a' and <= 'f'));

    /// <summary>Constant-time comparison of the configured value with <paramref name="computed"/> (a malformed value is false).</summary>
    public static bool Matches(string? configuredHex, ReadOnlySpan<byte> computed) =>
        IsWellFormed(configuredHex) && CryptographicOperations.FixedTimeEquals(Convert.FromHexString(configuredHex!), computed);
}
