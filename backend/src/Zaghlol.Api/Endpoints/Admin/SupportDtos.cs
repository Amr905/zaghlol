namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// OpenAPI <c>SupportEntitlement</c> (backend-api §5.2): entitlement and seat status only. Never a purchase token, store key,
/// transaction or order ID, another install's ID, the e-mail or any device data. Null members are written as <c>null</c>.
/// </summary>
public sealed record SupportEntitlementDto(
    string Status,
    IReadOnlyList<SupportPurchaseDto> Purchases,
    string? Plan,
    DateTimeOffset? Exp,
    DateTimeOffset? GraceUntil);

/// <summary>OpenAPI <c>SupportPurchase</c>.</summary>
public sealed record SupportPurchaseDto(
    Guid PurchaseId,
    string Plan,
    string State,
    string Store,
    string Seat,
    bool AccountLinked,
    string? LinkedBy,
    DateTimeOffset? LastMovedAt,
    DateTimeOffset? NextMoveAt,
    int PendingClaimants,
    bool BuyingInstallSilent,
    bool? IsBuyingInstall,
    DateTimeOffset? DisputeFrozenUntil,
    int RebindsLast30Days);

/// <summary>OpenAPI <c>SupportSeatMoveResult</c> (T-186). <c>nextMoveAt</c> is written as <c>null</c> when no cooldown runs.</summary>
public sealed record SupportSeatMoveResultDto(Guid PurchaseId, bool Moved, bool Attached, DateTimeOffset? NextMoveAt, long AuditId);

/// <summary>OpenAPI <c>SupportDetachResult</c> (T-186).</summary>
public sealed record SupportDetachResultDto(Guid PurchaseId, bool Detached, long AuditId);

/// <summary>OpenAPI <c>SupportUnfreezeResult</c> (T-186).</summary>
public sealed record SupportUnfreezeResultDto(Guid PurchaseId, bool Unfrozen, long AuditId);
