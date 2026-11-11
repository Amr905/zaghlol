using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Seats;

/// <summary>The channel that asks for the seat (backend-api §4.3, §4.6, §5.3).</summary>
public enum SeatChannel
{
    Verify,
    Restore,
    SignIn,
    Support,
}

/// <summary><c>purchase_seats.proof</c>: how the holder got the seat.</summary>
public enum SeatProofKind
{
    Binding,
    Attested,
    Basic,
    Account,
    Support,
    Device,
}

/// <summary>The attestation level of a restore (backend-api §4.3 step 2 and step 6).</summary>
public enum RestoreProof
{
    /// <summary>Play <c>MEETS_DEVICE_INTEGRITY</c> or a verified App Attest assertion.</summary>
    Attested,

    /// <summary>Play <c>MEETS_BASIC_INTEGRITY</c> only (R-19): shorter tokens.</summary>
    Basic,
}

/// <summary><c>seat_claimants.channel</c>.</summary>
public enum SeatClaimantChannel
{
    Restore,
    SignIn,
    Verify,
}

/// <summary>The seat decision (T-184 design note §4).</summary>
public enum SeatOutcome
{
    /// <summary>A seatless purchase was bound to the buying install (not a move).</summary>
    Bound,

    /// <summary>Nothing moved. <see cref="SeatResult.CallerHolds"/> says whether the caller holds the seat.</summary>
    Unchanged,

    /// <summary>The seat moved to the caller (or the support target).</summary>
    Moved,

    /// <summary>A same-iPhone rebind inside the D-63 cap: no cooldown, window unchanged.</summary>
    Rebound,

    /// <summary>A same-iPhone rebind over the cap (D-65(a)): never refused, window restarts.</summary>
    ReboundOverCap,

    /// <summary>Restore or sign-in refused by the cooldown; the caller is a pending claimant.</summary>
    Refused,

    /// <summary>The account rule kept the caller off the seat (R4-4, D-61(c)).</summary>
    AccountRequired,

    /// <summary>A plan-change verify kept off by the cooldown: the payment stands, the caller is a pending claimant.</summary>
    ClaimantAdded,

    /// <summary>Support only: the target is neither an unexpired claimant nor the move-back target (caller answers 409).</summary>
    NotEligible,
}

/// <summary>Who moved the seat away from the previous holder (the token's <c>movedBy</c>).</summary>
public enum SeatMovedBy
{
    User,
    Support,
}

/// <summary>The outcome of one seat operation.</summary>
/// <param name="CallerHolds">The caller (support: the target) holds the seat after the operation.</param>
/// <param name="NextMoveAt">The stored, hour-rounded <c>next_move_at</c> while a cooldown runs after the operation; otherwise null.</param>
/// <param name="PreviousHolder">The install that lost the seat (null when it was vacant or nothing moved).</param>
/// <param name="MovedBy">How <paramref name="PreviousHolder"/> lost it.</param>
/// <param name="RestoreSuggested">Over-cap sign-in against an untrusted seat key (D-65(a), D-66).</param>
/// <param name="Cause">The <c>purchase_events.cause</c> written, or null when no event row was written.</param>
public sealed record SeatResult(
    SeatOutcome Outcome,
    bool CallerHolds,
    DateTimeOffset? NextMoveAt,
    Guid? PreviousHolder,
    SeatMovedBy? MovedBy,
    bool RestoreSuggested,
    string? Cause);

/// <summary>
/// Proof that an App Attest assertion verified over a <c>clientDataHash</c> covering these seat public keys (backend-api §4.3
/// step 2, R4-1(3)), for this install. The only way to register a seat key as trusted (R5-2).
/// </summary>
/// <remarks>
/// A sealed class with an internal constructor and no factory: <c>default</c> can't forge it (not a struct) and nothing outside
/// this assembly can make one. Inside it, only the restore flow (namespace <c>Zaghlol.Application.Purchases.Restore</c>, T-185)
/// may construct it, after the assertion verified; <c>AppAttestVerifiedTests</c> scans every method body of every production
/// assembly and fails on any other construction site.
/// </remarks>
public sealed class AppAttestVerified
{
    /// <summary>The namespace that alone may construct this type (T-185).</summary>
    public const string IssuerNamespace = "Zaghlol.Application.Purchases.Restore";

    private readonly byte[] seatKeysDigest;

    internal AppAttestVerified(InstallId installId, ReadOnlySpan<byte> seatKeysDigest)
    {
        if (seatKeysDigest.Length != 32)
        {
            throw new ArgumentException("The seat-keys digest must be 32 bytes.", nameof(seatKeysDigest));
        }

        InstallId = installId;
        this.seatKeysDigest = seatKeysDigest.ToArray();
    }

    /// <summary>The install whose App Attest key made the assertion.</summary>
    public InstallId InstallId { get; }

    /// <summary>The <c>seatKeysDigest</c> the assertion's <c>clientDataHash</c> covered.</summary>
    internal ReadOnlySpan<byte> SeatKeysDigest => seatKeysDigest;

    public override string ToString() => "***";
}

/// <summary>
/// A verified <c>seatKeys</c> set whose element 0 is the caller's registered key (registered in this transaction if it had
/// none). Issued only by <see cref="SeatService.RegisterElementZeroAsync"/>, so every seat operation that takes one has rebind
/// condition 1 (backend-api §4.3) by construction.
/// </summary>
public sealed class RegisteredSeatKey
{
    internal RegisteredSeatKey(VerifiedSeatKeys keys, bool trusted)
    {
        Keys = keys;
        Trusted = trusted;
    }

    public InstallId InstallId => Keys.InstallId;

    public SeatOp Op => Keys.Op;

    /// <summary><c>installs.seat_key_trusted</c> after the registration, in this transaction.</summary>
    public bool Trusted { get; }

    internal VerifiedSeatKeys Keys { get; }

    public override string ToString() => "***";
}

/// <summary>How element 0 related to the install's registered key.</summary>
public enum SeatKeyRegistrationStatus
{
    /// <summary>The install had none; element 0 is now registered.</summary>
    Registered,

    /// <summary>Element 0 is the registered key.</summary>
    AlreadyRegistered,

    /// <summary>Element 0 isn't the registered key: restore / sign-in answer <c>400 SEAT_KEY_MISMATCH</c>; verify ignores the keys.</summary>
    Mismatch,
}

/// <summary>The registration result; <see cref="Key"/> is null exactly on <see cref="SeatKeyRegistrationStatus.Mismatch"/>.</summary>
public sealed record SeatKeyRegistration(SeatKeyRegistrationStatus Status, RegisteredSeatKey? Key);

/// <summary>Verify's seat request (backend-api §4.3 <i>Seat at verify</i>).</summary>
/// <param name="IsNewPayment">A Google successor or an Apple <c>PURCHASE</c>-reason transaction new for this purchase (D-59).</param>
/// <param name="PresentedAccountId">The account of a valid <c>Zaghlol-Account</c> token on this request, if any.</param>
/// <param name="PredecessorPurchaseId">Google: the purchase named by <c>linkedPurchaseToken</c>, whose seat a successor inherits.</param>
public sealed record VerifySeatRequest(
    Guid PurchaseId,
    InstallId Caller,
    bool IsNewPayment,
    Guid? PresentedAccountId,
    Guid? PredecessorPurchaseId,
    RegisteredSeatKey? Key);

/// <summary>Restore's seat request for one item (backend-api §4.3 Restore steps 4–5), after attestation and store checks.</summary>
public sealed record RestoreSeatRequest(Guid PurchaseId, InstallId Caller, RestoreProof Proof, Guid? PresentedAccountId, RegisteredSeatKey? Key);

/// <summary>Sign-in's seat request for one purchase linked to <paramref name="AccountId"/> (backend-api §4.6 steps 4–5).</summary>
/// <param name="AccountId">The account the caller just signed in to.</param>
/// <param name="AttachedNow">Step 3 attached this purchase in this request (the account-attach reclaim may apply).</param>
public sealed record SignInSeatRequest(Guid PurchaseId, InstallId Caller, Guid AccountId, bool AttachedNow, RegisteredSeatKey? Key);

/// <summary>The support-move primitive (backend-api §5.3, D-56, R5-4) for T-186, after its own checks.</summary>
/// <param name="MoveBack">A correction's move back to the <c>from_install</c> of the corrected audit row.</param>
public sealed record SupportSeatMoveRequest(Guid PurchaseId, InstallId Target, bool MoveBack);

/// <summary>The locked purchase and seat rows (no seat row: <see cref="SeatExists"/> false and every seat member default).</summary>
public sealed record SeatSnapshot(
    Guid PurchaseId,
    StoredPurchaseState PurchaseState,
    Guid? BuyingInstall,
    Guid? AccountId,
    DateTimeOffset? AttachReclaimUsedAt,
    bool SeatExists,
    Guid? Holder,
    SeatProofKind? Proof,
    DateTimeOffset? BoundAt,
    DateTimeOffset? LastMovedAt,
    DateTimeOffset? NextMoveAt,
    SeatKeyHash? DeviceKeyHash,
    bool DeviceKeyTrusted,
    IReadOnlyList<DateTimeOffset> RecentRebinds);

/// <summary>The seat row to write.</summary>
public sealed record SeatRow(
    Guid PurchaseId,
    Guid? Holder,
    SeatProofKind? Proof,
    DateTimeOffset? BoundAt,
    DateTimeOffset? LastMovedAt,
    DateTimeOffset? NextMoveAt,
    SeatKeyHash? DeviceKeyHash,
    bool DeviceKeyTrusted,
    IReadOnlyList<DateTimeOffset> RecentRebinds);

/// <summary>A <c>seat_claimants</c> row.</summary>
public sealed record SeatClaimantRow(Guid InstallId, DateTimeOffset ClaimedAt, SeatClaimantChannel Channel, SeatKeyHash? DeviceKeyHash);

/// <summary><c>installs.seat_key_hash</c> and <c>seat_key_trusted</c> (null when the install row doesn't exist).</summary>
public sealed record InstallSeatKey(InstallKeyHash? Registered, bool Trusted);
