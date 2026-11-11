using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>One verified store read to upsert into <c>purchases</c> (T-130 design note §1 step 5).</summary>
/// <param name="StoreKey">Google purchase token or Apple originalTransactionId: the unique key with <paramref name="Store"/>.</param>
/// <param name="InstallId">The buying install, written on insert only (<c>null</c> from restore, which never sets it).</param>
/// <param name="Acknowledged">The store already reports the purchase acknowledged; never turns a stored <c>true</c> back.</param>
/// <param name="ReadAt">Taken before the store call; a row verified at or after it is newer and is not overwritten.</param>
public sealed record PurchaseUpsert(
    PurchaseStore Store,
    string ProductId,
    GoldPlan Plan,
    Sensitive<string> StoreKey,
    Sensitive<string>? LinkedPurchaseToken,
    InstallId? InstallId,
    StoredPurchaseState State,
    DateTimeOffset? ExpiresAt,
    bool Acknowledged,
    PurchaseEnvironment Environment,
    string? ObfuscatedInstallRef,
    DateTimeOffset ReadAt);

/// <summary>The row after the upsert.</summary>
/// <param name="Applied">False when a newer read had already been stored (the monotonic guard); the row is returned as stored.</param>
/// <param name="PredecessorPurchaseId">The purchase whose token is this row's <c>linked_purchase_token</c>, if known.</param>
public sealed record PurchaseUpsertResult(
    Guid PurchaseId,
    bool Applied,
    StoredPurchaseState State,
    DateTimeOffset? ExpiresAt,
    bool Acknowledged,
    Guid? PredecessorPurchaseId);

/// <summary><c>purchases</c> writes of the verify path, on the App login (T-133 reuses it for RTDN).</summary>
public interface IPurchaseWriter
{
    /// <summary>
    /// One short transaction: insert, or update when <c>last_verified_at &lt; ReadAt</c>; a <c>purchase_events</c> row
    /// (<paramref name="cause"/>) when the state changes. Never edits the predecessor.
    /// </summary>
    Task<PurchaseUpsertResult> UpsertAsync(PurchaseUpsert upsert, string cause, CancellationToken cancellationToken);

    /// <summary>Sets <c>acknowledged = true</c>; false when it already was (or the row is gone).</summary>
    Task<bool> MarkAcknowledgedAsync(Guid purchaseId, CancellationToken cancellationToken);
}

/// <summary>A Google purchase waiting for acknowledgement (<c>ix_purchases_unacked</c>).</summary>
public sealed record UnackedPurchase(Guid Id, string ProductId, Sensitive<string> Token, StoredPurchaseState State, DateTimeOffset CreatedAt);

/// <summary>What the sweeper learned about one row from a fresh Play read.</summary>
public sealed record SweepUpdate(
    Guid Id,
    StoredPurchaseState State,
    DateTimeOffset? ExpiresAt,
    bool Acknowledged,
    Sensitive<string>? LinkedPurchaseToken,
    DateTimeOffset ReadAt);

/// <summary>The unacknowledged-purchase gauge input: ackable rows younger than 72 h only (pending ones excluded).</summary>
public sealed record UnackedSummary(long LessThan48h, long AtLeast48h, TimeSpan OldestAge, IReadOnlyList<Guid> Overdue);

/// <summary>The acknowledge sweeper's rows, on the Worker login.</summary>
public interface IPlayAckSweepStore
{
    /// <summary>
    /// <c>pg_try_advisory_lock</c> on one dedicated connection, held until disposed; <c>null</c> when another sweeper holds it
    /// (one sweeper across replicas).
    /// </summary>
    Task<IAsyncDisposable?> TryLockAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> unacknowledged Google rows in a pending or ackable state whose <c>ack_next_attempt_at</c> is
    /// NULL or due at <paramref name="now"/>, in <see cref="PlayAckSweepSchedule.SortKey"/> order (ackable before pending, never
    /// tried before deferred, earliest due, oldest); no transaction held.
    /// </summary>
    Task<IReadOnlyList<UnackedPurchase>> ListAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken);

    /// <summary>
    /// Sets <c>ack_next_attempt_at</c> of a row the run could not finish (still waiting, skipped or failed), so it moves behind
    /// the rows that are due (T-130 security M-1). A scheduling stamp only: no state change, no monotonic guard.
    /// </summary>
    Task DeferAsync(Guid id, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken);

    /// <summary>One short update with the monotonic <c>last_verified_at</c> guard, and a <c>sweep</c> event on a state change.</summary>
    Task<bool> ApplyAsync(SweepUpdate update, CancellationToken cancellationToken);

    /// <summary>
    /// Counts ackable unacknowledged rows younger than <see cref="PlayAckSweepSchedule.RefundAge"/> by age (48 h) and returns up to
    /// <paramref name="maxOverdue"/> overdue IDs. Rows past 72 h are out: Play has already refunded them, so they can't page forever.
    /// </summary>
    Task<UnackedSummary> SummarizeAsync(DateTimeOffset now, int maxOverdue, CancellationToken cancellationToken);
}
