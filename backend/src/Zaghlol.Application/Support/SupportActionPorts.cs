using Zaghlol.Application.Audit;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Support;

/// <summary><c>reasonCode</c> of a support move (backend-api 5.3).</summary>
public enum SupportReason
{
    LostOrBrokenPhone,
    Reinstall,
    BuyingPhoneGone,
    Correction,
    Other,
}

/// <summary>The wire names of <see cref="SupportReason"/>.</summary>
public static class SupportReasons
{
    public static string Wire(SupportReason reason) => reason switch
    {
        SupportReason.LostOrBrokenPhone => "lost_or_broken_phone",
        SupportReason.Reinstall => "reinstall",
        SupportReason.BuyingPhoneGone => "buying_phone_gone",
        SupportReason.Correction => "correction",
        SupportReason.Other => "other",
        _ => throw new ArgumentOutOfRangeException(nameof(reason)),
    };

    public static bool TryParse(string? text, out SupportReason reason)
    {
        (var found, reason) = text switch
        {
            "lost_or_broken_phone" => (true, SupportReason.LostOrBrokenPhone),
            "reinstall" => (true, SupportReason.Reinstall),
            "buying_phone_gone" => (true, SupportReason.BuyingPhoneGone),
            "correction" => (true, SupportReason.Correction),
            "other" => (true, SupportReason.Other),
            _ => (false, default),
        };
        return found;
    }
}

/// <summary>
/// <c>seat:move</c> after parsing. <see cref="OrderId"/> is the store order ID: it lives only in this command and the ownership check
/// (never stored, logged, traced or audited). There is deliberately no "move back" member: a correction's target comes only from the
/// referenced audit row (FU-112 184-2).
/// </summary>
public sealed record SupportSeatMoveCommand(
    Guid OperatorId,
    Guid PurchaseId,
    InstallId ToInstall,
    SupportReason Reason,
    string TicketRef,
    Sensitive<string> OrderId,
    bool Attach,
    long? CorrectsAuditId);

/// <summary><c>purchase:detach</c> after parsing.</summary>
public sealed record SupportDetachCommand(Guid OperatorId, Guid PurchaseId, string TicketRef, Sensitive<string> OrderId, long CorrectsAuditId);

/// <summary><c>purchase:unfreeze</c> after parsing.</summary>
public sealed record SupportUnfreezeCommand(Guid OperatorId, Guid PurchaseId, string TicketRef, Sensitive<string> OrderId);

/// <summary>How a support call ended; the endpoint maps it to 200, 404, 409, 422 or 503.</summary>
public enum SupportActionStatus
{
    Ok,
    NotFound,
    Conflict,
    OwnershipFailed,
    Unavailable,
}

/// <summary>A status and, for <see cref="SupportActionStatus.Ok"/>, the response. Every status except a failure of the audit write itself carries its audit row.</summary>
public sealed record SupportActionResult<T>(SupportActionStatus Status, T? Value = null)
    where T : class;

/// <summary><c>SupportSeatMoveResult</c>.</summary>
public sealed record SupportSeatMoveOutcome(Guid PurchaseId, bool Moved, bool Attached, DateTimeOffset? NextMoveAt, long AuditId);

/// <summary><c>SupportDetachResult</c>.</summary>
public sealed record SupportDetachOutcome(Guid PurchaseId, bool Detached, long AuditId);

/// <summary><c>SupportUnfreezeResult</c>.</summary>
public sealed record SupportUnfreezeOutcome(Guid PurchaseId, bool Unfrozen, long AuditId);

/// <summary>Which store a purchase came from.</summary>
public enum SupportStore
{
    GooglePlay,
    AppStore,
}

/// <summary>
/// The locked purchase a support call decides on: the seat snapshot (T-184) plus what the ownership check and the freeze rules need.
/// <see cref="StoreKey"/> and <see cref="LinkedPurchaseToken"/> are bearer-like (<see cref="Sensitive{T}"/>); the record never renders them.
/// </summary>
public sealed record SupportPurchase(
    SeatSnapshot Seat,
    SupportStore Store,
    string ProductId,
    Sensitive<string> StoreKey,
    Sensitive<string>? LinkedPurchaseToken,
    PurchaseEnvironment Environment,
    string? AccountLinkedBy,
    DateTimeOffset? DisputeFrozenUntil,
    bool BuyingInstallSilent);

/// <summary>One <c>audit_log</c> row of a support action, as the rules read it back (only what they need).</summary>
public sealed record SupportAuditRow(
    long Id,
    Guid OperatorId,
    string Action,
    DateTimeOffset At,
    string? ReasonCode,
    string? Outcome,
    Guid? FromInstall,
    Guid? AttachedAccountId,
    long? CorrectsAuditId);

/// <summary>The alert counters of one call, read in its transaction after its audit row.</summary>
public sealed record SupportAuditCounts(long SuccessfulMovesLast90Days, long ActionsLastDay, long OwnershipFailuresLastDay);

/// <summary>The audited support write path on the Admin login (<c>ops_rw</c>). Every method runs in the transaction's one connection.</summary>
public interface ISupportActionTransaction : IAsyncDisposable
{
    /// <summary>The seat tables in this transaction, for the T-184 support-move primitive.</summary>
    ISeatStore Seats { get; }

    /// <summary>Locks the purchase and its seat row (purchase first), then reads the rest. Null when the purchase doesn't exist.</summary>
    Task<SupportPurchase?> LockPurchaseAsync(Guid purchaseId, DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>A support audit row (<c>support_seat_move</c>, <c>support_detach</c> or <c>support_unfreeze</c>) whose target is this purchase.</summary>
    Task<SupportAuditRow?> ReadAuditAsync(Guid purchaseId, long auditId, CancellationToken cancellationToken);

    /// <summary>The newest successful correction of the purchase: the row that started the current freeze.</summary>
    Task<SupportAuditRow?> NewestFreezeStartAsync(Guid purchaseId, CancellationToken cancellationToken);

    /// <summary>The newest <c>support_unfreeze</c> row of the purchase whose outcome is <c>unfrozen</c>.</summary>
    Task<SupportAuditRow?> NewestUnfreezeAsync(Guid purchaseId, CancellationToken cancellationToken);

    /// <summary>The install exists and isn't tombstoned.</summary>
    Task<bool> InstallLiveAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>The account the install is linked to, if any.</summary>
    Task<Guid?> AccountOfInstallAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>R4-7(2): <c>account_id</c>, <c>account_linked_by = 'support'</c>, <c>support_link_notice_pending = true</c>, <c>support_link_notice_iat = NULL</c>.</summary>
    Task LinkAccountBySupportAsync(Guid purchaseId, Guid accountId, CancellationToken cancellationToken);

    /// <summary>R5-7: clears <c>account_id</c>, <c>account_linked_by</c>, <c>support_link_notice_pending</c> and <c>support_link_notice_iat</c>.</summary>
    Task UnlinkAccountAsync(Guid purchaseId, CancellationToken cancellationToken);

    Task SetDisputeFreezeAsync(Guid purchaseId, DateTimeOffset? until, CancellationToken cancellationToken);

    /// <summary>Sets <c>dispute_frozen_until = now() + length</c> on the database clock, so a skewed app clock cannot change the freeze.</summary>
    Task StartDisputeFreezeAsync(Guid purchaseId, TimeSpan length, CancellationToken cancellationToken);

    /// <summary>Inserts the call's one audit row naming the operator and returns its id.</summary>
    Task<long> WriteAuditAsync(Guid operatorId, AuditEntry entry, CancellationToken cancellationToken);

    Task<SupportAuditCounts> CountsAsync(Guid operatorId, Guid purchaseId, CancellationToken cancellationToken);

    Task CommitAsync(CancellationToken cancellationToken);
}

public interface ISupportActionStore
{
    /// <summary>A READ COMMITTED transaction on the Admin login; rolled back on dispose unless committed.</summary>
    Task<ISupportActionTransaction> BeginAsync(CancellationToken cancellationToken);
}

/// <summary>The live store ownership check (D-57): Play <c>orders.get</c> or its fallback, or the App Store order lookup.</summary>
public interface ISupportOwnershipCheck
{
    /// <summary>Never throws for a store failure: those are <see cref="OwnershipOutcome.Unavailable"/>. The order ID is never kept.</summary>
    Task<OwnershipOutcome> CheckAsync(SupportPurchase purchase, Sensitive<string> orderId, CancellationToken cancellationToken);
}

/// <summary>The support alerts (T-138 rules). Purchase and operator UUIDs only; raised after the call's transaction commits.</summary>
public interface ISupportAlerts
{
    void DisputeFrozen(Guid purchaseId);

    void Unfreeze(Guid purchaseId);

    void MovesPerPurchase(Guid purchaseId);

    void ActionsPerOperator(Guid operatorId);

    void OwnershipFailuresPerOperator(Guid operatorId);
}
