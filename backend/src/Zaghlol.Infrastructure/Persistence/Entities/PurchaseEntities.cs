namespace Zaghlol.Infrastructure.Persistence.Entities;

// backend-schema.md section 2, "Purchases", seats, claimants, App Attest keys and the entitlement view.

/// <summary><c>purchases</c> (FR-BE-02).</summary>
public sealed class Purchase
{
    public Guid Id { get; set; }

    public Store Store { get; set; }

    public required string ProductId { get; set; }

    public Plan Plan { get; set; }

    /// <summary>Google purchase token or Apple originalTransactionId.</summary>
    public required string StoreKey { get; set; }

    public string? LinkedPurchaseToken { get; set; }

    /// <summary>The buying install (set by verify, never by restore).</summary>
    public Guid? InstallId { get; set; }

    public Guid? AccountId { get; set; }

    /// <summary>NULL exactly when <see cref="AccountId"/> is NULL (CHECK).</summary>
    public AccountLinkSource? AccountLinkedBy { get; set; }

    /// <summary>D-58: never cleared, not even when the account is deleted.</summary>
    public DateTimeOffset? AttachReclaimUsedAt { get; set; }

    /// <summary>D-64.</summary>
    public DateTimeOffset? DisputeFrozenUntil { get; set; }

    /// <summary>R4-7(2).</summary>
    public bool SupportLinkNoticePending { get; set; }

    /// <summary>R5-7.</summary>
    public DateTimeOffset? SupportLinkNoticeIat { get; set; }

    public PurchaseState State { get; set; }

    public DateTimeOffset? ExpiresAt { get; set; }

    public bool Acknowledged { get; set; }

    /// <summary>T-130 security M-1: when the acknowledge sweeper may next try a row it could not finish; NULL = never deferred.</summary>
    public DateTimeOffset? AckNextAttemptAt { get; set; }

    public StoreEnvironment Environment { get; set; }

    public string? ObfuscatedInstallRef { get; set; }

    public DateTimeOffset LastVerifiedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
}

/// <summary><c>purchase_events</c>: audit trail of state transitions (no raw receipts).</summary>
public sealed class PurchaseEvent
{
    public Guid Id { get; set; }

    public Guid PurchaseId { get; set; }

    public PurchaseState? FromState { get; set; }

    public PurchaseState ToState { get; set; }

    /// <summary>One of the documented causes; enforced by a regex CHECK.</summary>
    public required string Cause { get; set; }

    public DateTimeOffset OccurredAt { get; set; }
}

/// <summary><c>purchase_seats</c> (D-52, FR-GOLD-08): exactly one row per purchase.</summary>
public sealed class PurchaseSeat
{
    public Guid PurchaseId { get; set; }

    /// <summary>The holder; NULL = vacant.</summary>
    public Guid? InstallId { get; set; }

    /// <summary>NULL exactly when vacant (CHECK).</summary>
    public SeatProof? Proof { get; set; }

    public DateTimeOffset? BoundAt { get; set; }

    /// <summary>Server-side only, never sent to the app.</summary>
    public DateTimeOffset? LastMovedAt { get; set; }

    /// <summary>A whole UTC hour (CHECK); NULL exactly when <see cref="LastMovedAt"/> is NULL.</summary>
    public DateTimeOffset? NextMoveAt { get; set; }

    /// <summary>D-55 keyed hash; kept when the seat goes vacant.</summary>
    public byte[]? DeviceKeyHash { get; set; }

    public bool DeviceKeyTrusted { get; set; }

    /// <summary>D-63: at most 2 elements (CHECK).</summary>
    public DateTimeOffset[] RecentRebinds { get; set; } = [];
}

/// <summary><c>seat_claimants</c> (R3-4, R4-4).</summary>
public sealed class SeatClaimant
{
    public Guid PurchaseId { get; set; }

    public Guid InstallId { get; set; }

    public DateTimeOffset ClaimedAt { get; set; }

    public ClaimantChannel Channel { get; set; }

    public byte[]? DeviceKeyHash { get; set; }
}

/// <summary><c>app_attest_keys</c>: no device identifier is stored (FR-GOLD-09).</summary>
public sealed class AppAttestKey
{
    /// <summary>SHA-256 of the credential public key (= keyId).</summary>
    public required byte[] KeyId { get; set; }

    public Guid InstallId { get; set; }

    /// <summary>The App Attest credential public key (not a seat key).</summary>
    public required byte[] PublicKey { get; set; }

    public long SignCount { get; set; }

    public AttestEnvironment Environment { get; set; }

    public DateTimeOffset AttestedAt { get; set; }
}

/// <summary>Read-only view <c>v_entitlements</c>: purchases whose seat an install holds, in an entitling state.</summary>
public sealed class EffectiveEntitlement
{
    public Guid InstallId { get; set; }

    public Guid PurchaseId { get; set; }

    public Plan Plan { get; set; }

    public PurchaseState State { get; set; }

    public DateTimeOffset? ExpiresAt { get; set; }

    public Store Store { get; set; }

    public Guid? AccountId { get; set; }

    public SeatProof Proof { get; set; }

    public DateTimeOffset? NextMoveAt { get; set; }
}

/// <summary><c>store_notifications</c> (FR-BE-03): only extracted columns, never the raw envelope.</summary>
public sealed class StoreNotification
{
    public Guid Id { get; set; }

    public required string Store { get; set; }

    /// <summary>Pub/Sub messageId or ASSN notificationUUID.</summary>
    public required string ExternalId { get; set; }

    /// <summary>Column <c>type</c>.</summary>
    public required string NotificationType { get; set; }

    public string? Subtype { get; set; }

    public string? ProductId { get; set; }

    public string? StoreKey { get; set; }

    public StoreEnvironment? Environment { get; set; }

    public DateTimeOffset? EventTime { get; set; }

    public DateTimeOffset ReceivedAt { get; set; }

    public DateTimeOffset? ProcessedAt { get; set; }

    public int Attempts { get; set; }

    /// <summary>An error code only; never payload text.</summary>
    public string? LastError { get; set; }

    public required byte[] PayloadDigest { get; set; }
}
