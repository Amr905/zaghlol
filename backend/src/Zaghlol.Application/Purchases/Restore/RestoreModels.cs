using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases.Restore;

/// <summary>The wire words of <c>platform</c> (also the metric tag of attestation failures).</summary>
public static class RestorePlatforms
{
    public const string Android = "android";
    public const string Ios = "ios";
}

/// <summary>Why a restore body was refused before any proof was checked: both are <c>400</c>, with different codes.</summary>
public enum RestoreParseFailure
{
    /// <summary><c>400 VALIDATION_FAILED</c>: bad JSON, duplicate member, lone surrogate, wrong type, size or count.</summary>
    ValidationFailed,

    /// <summary><c>400 UNKNOWN_FIELD</c>: a member the schema of the body's platform doesn't declare (BR-SYNC-03).</summary>
    UnknownField,
}

/// <summary>
/// A restore body that parsed strictly and bound once (backend-api §4.3 step 1). <see cref="BodyHash"/> is the install-bound hash
/// of exactly the object this was bound from. Nothing here renders a secret.
/// </summary>
public abstract record RestoreRequest
{
    /// <summary><c>SHA-256("zaghlol-restore-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body without "attestation"))</c>.</summary>
    public required byte[] BodyHash { get; init; }

    public abstract string Platform { get; }

    public sealed override string ToString() => "***";
}

/// <summary>An Android restore: Play Billing items and the Play Integrity token.</summary>
public sealed record AndroidRestoreRequest : RestoreRequest
{
    public required IReadOnlyList<PlayPurchaseRef> Purchases { get; init; }

    public required Sensitive<string> IntegrityToken { get; init; }

    public override string Platform => RestorePlatforms.Android;
}

/// <summary>An iOS restore: StoreKit signed transactions, the App Attest proof and optional seat keys.</summary>
public sealed record IosRestoreRequest : RestoreRequest
{
    public required IReadOnlyList<Sensitive<string>> SignedTransactions { get; init; }

    public required byte[] KeyId { get; init; }

    public required byte[] Assertion { get; init; }

    public byte[]? AttestationObject { get; init; }

    public IReadOnlyList<SeatKeyProofInput>? SeatKeys { get; init; }

    public override string Platform => RestorePlatforms.Ios;
}

/// <summary>The outcome of <see cref="RestoreRequestParser.Parse"/>.</summary>
public sealed record RestoreParseResult(RestoreRequest? Request, RestoreParseFailure? Failure)
{
    public override string ToString() => Request is null ? Failure.ToString()! : "parsed";
}

/// <summary>What the restore answered, as the Api maps it (backend-api §4.3).</summary>
public enum RestoreResultKind
{
    /// <summary><c>200</c>: <see cref="RestoreResult.Status"/> and the rest are set.</summary>
    Completed,

    /// <summary><c>400 VALIDATION_FAILED</c> (a seat-key set that doesn't parse or verify).</summary>
    ValidationFailed,

    /// <summary><c>400 SEAT_KEY_MISMATCH</c> (R5-6): nothing written, the App Attest counter included.</summary>
    SeatKeyMismatch,

    /// <summary><c>422 DEVICE_ATTESTATION_FAILED</c>: nothing written.</summary>
    AttestationFailed,

    /// <summary><c>503 UPSTREAM_UNAVAILABLE</c> from the attestation service or the outbound budget.</summary>
    Unavailable,

    /// <summary><c>429 RATE_LIMITED</c>: a purchase already had 10 attempts in 24 h.</summary>
    PurchaseRateLimited,

    /// <summary><c>502 STORE_UNAVAILABLE</c>: a store call failed; nothing was granted.</summary>
    StoreUnavailable,

    /// <summary><c>409 MOVE_COOLDOWN</c>.</summary>
    MoveCooldown,
}

/// <summary>The per-item outcome folded into the aggregate status.</summary>
public enum RestoreItemOutcome
{
    Active,
    Pending,
    AccountRequired,
    Expired,
    Refunded,
    Invalid,

    /// <summary>The seat is under the 30-day cooldown (never a status of its own: <c>409</c> or ignored).</summary>
    CooldownRefused,
}

/// <summary>The aggregate of a restore.</summary>
/// <param name="Status">Wire word of <c>PurchaseStatus</c> (<c>active</c> …), set on <see cref="RestoreResultKind.Completed"/>.</param>
/// <param name="EntitlementToken">The merged entitlement, or null when nothing grants Gold.</param>
/// <param name="NextMoveAt">Kind <see cref="RestoreResultKind.MoveCooldown"/>: the earliest stored, hour-rounded <c>next_move_at</c>.</param>
/// <param name="RetryAfterSeconds">Kinds <see cref="RestoreResultKind.Unavailable"/>, <see cref="RestoreResultKind.StoreUnavailable"/>, <see cref="RestoreResultKind.PurchaseRateLimited"/>.</param>
/// <param name="BudgetShort">Kind <see cref="RestoreResultKind.StoreUnavailable"/>: our own outbound budget (answer <c>503</c>), not the store.</param>
public sealed record RestoreResult(
    RestoreResultKind Kind,
    string? Status = null,
    int RestoredCount = 0,
    bool MovedFromOtherPhone = false,
    Sensitive<string>? EntitlementToken = null,
    DateTimeOffset? NextMoveAt = null,
    int RetryAfterSeconds = 0,
    bool BudgetShort = false);
