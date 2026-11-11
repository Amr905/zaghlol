using System.Security.Cryptography;

namespace Zaghlol.Application.Seats.SeatKeys;

// Two distinct wrappers with no shared base and no cross-type Equals, so an install hash can never be compared with a seat hash
// (T-182 design note §1). Both compare in constant time and print as ***.

/// <summary>
/// <c>installs.seat_key_hash</c> = HMAC-SHA256(<c>K_seat</c>, <c>"install" ‖ 0x00 ‖ installId ‖ publicKey</c>) (backend-api §4.3,
/// R4-1(1)).
/// </summary>
public sealed class InstallKeyHash
{
    public const int Length = 32;

    private readonly byte[] value;

    private InstallKeyHash(byte[] value) => this.value = value;

    /// <summary>A value read from <c>installs.seat_key_hash</c> (the DB CHECK makes any length other than 32 impossible).</summary>
    public static InstallKeyHash FromStored(byte[] stored)
    {
        ArgumentNullException.ThrowIfNull(stored);
        return stored.Length == Length
            ? new InstallKeyHash((byte[])stored.Clone())
            : throw new InvalidOperationException("A stored install key hash must be 32 bytes.");
    }

    /// <summary>A copy for the <c>bytea</c> column.</summary>
    public byte[] ToStorage() => (byte[])value.Clone();

    /// <summary>Constant-time comparison; <see langword="null"/> never matches.</summary>
    public bool Matches(InstallKeyHash? other) => other is not null && CryptographicOperations.FixedTimeEquals(value, other.value);

    public override string ToString() => "***";

    internal static InstallKeyHash FromMac(byte[] mac) => mac.Length == Length
        ? new InstallKeyHash((byte[])mac.Clone())
        : throw new InvalidOperationException("The keyed hash must be 32 bytes.");
}

/// <summary>
/// <c>purchase_seats.device_key_hash</c> / <c>seat_claimants.device_key_hash</c> = HMAC-SHA256(<c>K_seat</c>,
/// <c>purchaseId ‖ publicKey</c>) (backend-api §4.3).
/// </summary>
public sealed class SeatKeyHash
{
    public const int Length = 32;

    private readonly byte[] value;

    private SeatKeyHash(byte[] value) => this.value = value;

    /// <summary>A value read from <c>device_key_hash</c> (the DB CHECK makes any length other than 32 impossible).</summary>
    public static SeatKeyHash FromStored(byte[] stored)
    {
        ArgumentNullException.ThrowIfNull(stored);
        return stored.Length == Length
            ? new SeatKeyHash((byte[])stored.Clone())
            : throw new InvalidOperationException("A stored seat key hash must be 32 bytes.");
    }

    /// <summary>A copy for the <c>bytea</c> column.</summary>
    public byte[] ToStorage() => (byte[])value.Clone();

    /// <summary>Constant-time comparison; <see langword="null"/> never matches.</summary>
    public bool Matches(SeatKeyHash? other) => other is not null && CryptographicOperations.FixedTimeEquals(value, other.value);

    public override string ToString() => "***";

    internal static SeatKeyHash FromMac(byte[] mac) => mac.Length == Length
        ? new SeatKeyHash((byte[])mac.Clone())
        : throw new InvalidOperationException("The keyed hash must be 32 bytes.");
}
