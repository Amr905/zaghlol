using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// The extracted columns of one <c>store_notifications</c> row (backend-schema §2, T-134 design note §1 step 6). Nothing else of a
/// notification is ever stored: no JWS text, transaction ID, <c>appAccountToken</c>, <c>status</c> or bundle ID.
/// </summary>
/// <param name="ExternalId">The canonical lower-case <c>notificationUUID</c>.</param>
/// <param name="StoreKey">The transaction's <c>originalTransactionId</c> (<c>null</c> without a <c>signedTransactionInfo</c>).</param>
/// <param name="EventTime">The notification's <c>signedDate</c>.</param>
/// <param name="PayloadDigest">SHA-256 of the UTF-8 <c>signedPayload</c> string (32 bytes).</param>
/// <param name="Processed">Inserted with <c>processed_at = now()</c>: outside the reconcile set, or no transaction to re-read.</param>
/// <param name="LastError">An informational code on a row inserted processed (<c>NO_TRANSACTION</c>), else <c>null</c>.</param>
public sealed record StoreNotificationRecord(
    Guid Id,
    PurchaseStore Store,
    string ExternalId,
    string Type,
    string? Subtype,
    string? ProductId,
    Sensitive<string>? StoreKey,
    PurchaseEnvironment Environment,
    DateTimeOffset EventTime,
    byte[] PayloadDigest,
    bool Processed,
    string? LastError);

/// <summary>
/// The idempotent <c>store_notifications</c> insert (<c>ON CONFLICT (store, external_id) DO NOTHING</c>). The API implements it on
/// the App login, the worker (history reconciliation) on the Worker login.
/// </summary>
public interface IStoreNotificationInbox
{
    /// <summary>True when the row was inserted, false when <c>(store, external_id)</c> already existed (a duplicate).</summary>
    Task<bool> TryInsertAsync(StoreNotificationRecord record, CancellationToken cancellationToken);
}

/// <summary>A due <c>store_notifications</c> row of the App Store (the processor's pick, T-134 §2).</summary>
public sealed record DueAppleNotification(
    Guid Id,
    string Type,
    Sensitive<string>? StoreKey,
    PurchaseEnvironment? Environment,
    int Attempts,
    DateTimeOffset ReceivedAt);

/// <summary>The stored App Store purchase a notification or the expiry sweep re-reads.</summary>
public sealed record ApplePurchaseRow(
    Guid Id,
    Sensitive<string> StoreKey,
    string ProductId,
    GoldPlan Plan,
    PurchaseEnvironment Environment,
    StoredPurchaseState State);

/// <summary>
/// One worker write (T-134 §2 step 6): Apple's current answer, applied only when <c>last_verified_at &lt; ReadAt</c>. It never
/// carries <c>install_id</c>, <c>obfuscated_install_ref</c>, <c>environment</c>, <c>acknowledged</c>, <c>last_payment_at</c>, account
/// or seat columns: the worker's grant doesn't allow them.
/// </summary>
/// <param name="Cause">The <c>purchase_events.cause</c>: <c>assn:&lt;type&gt;</c> or <c>sweep</c>.</param>
public sealed record AppleStateWrite(
    Guid PurchaseId,
    StoredPurchaseState State,
    DateTimeOffset? ExpiresAt,
    bool KeepStoredExpiry,
    string ProductId,
    GoldPlan Plan,
    DateTimeOffset ReadAt,
    string Cause);

/// <summary>What a worker write did.</summary>
public enum AppleWriteResult
{
    /// <summary>Written, and the state changed (a <c>purchase_events</c> row was added).</summary>
    Applied,

    /// <summary>Written, same state (expiry, product or plan may have moved).</summary>
    Unchanged,

    /// <summary>A newer read (verify, the sweep, another notification) is already stored: nothing written.</summary>
    Superseded,

    /// <summary>The purchase row no longer exists.</summary>
    Gone,
}

/// <summary>The notification worker's rows, on the Worker login (<c>worker_rw</c>).</summary>
public interface IAppleNotificationStore
{
    /// <summary>
    /// <c>pg_try_advisory_lock</c> named <paramref name="name"/> on one dedicated connection, held until disposed; <c>null</c> when
    /// another replica holds it.
    /// </summary>
    Task<IAsyncDisposable?> TryLockAsync(string name, CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> unprocessed App Store rows whose <c>next_attempt_at</c> is NULL or due, never-failed first, then
    /// earliest due, then oldest. No transaction held.
    /// </summary>
    Task<IReadOnlyList<DueAppleNotification>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken);

    /// <summary>The App Store purchase of <paramref name="storeKey"/>, or <c>null</c>. Never inserts one.</summary>
    Task<ApplePurchaseRow?> FindPurchaseAsync(Sensitive<string> storeKey, CancellationToken cancellationToken);

    /// <summary>
    /// One short transaction: lock the purchase, write <paramref name="write"/> under the monotonic guard, add a
    /// <c>purchase_events</c> row on a state change and, when <paramref name="notificationId"/> is given, mark that notification
    /// processed (<c>last_error = NULL</c>, or <c>NO_PURCHASE</c> when the row is gone) in the same transaction.
    /// </summary>
    Task<AppleWriteResult> ApplyAsync(AppleStateWrite write, Guid? notificationId, CancellationToken cancellationToken);

    /// <summary>Marks a notification processed with an informational code (<c>NO_PURCHASE</c>, <c>ENV_MISMATCH</c>, ...) or none.</summary>
    Task CompleteAsync(Guid notificationId, string? code, CancellationToken cancellationToken);

    /// <summary>
    /// A counted failure: <c>attempts</c> and <c>last_error</c> set; <paramref name="nextAttemptAt"/> is the next try, or <c>null</c>
    /// for the dead letter (<c>processed_at = now()</c>).
    /// </summary>
    Task FailAsync(Guid notificationId, int attempts, DateTimeOffset? nextAttemptAt, string code, CancellationToken cancellationToken);

    /// <summary>An uncounted deferral (Apple 429, our budget, an open circuit): only <c>next_attempt_at</c> moves.</summary>
    Task DeferAsync(Guid notificationId, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken);

    /// <summary>Unprocessed App Store rows younger and older than one hour (the backlog gauge).</summary>
    Task<(long LessThan1h, long AtLeast1h)> BacklogAsync(DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> App Store subscriptions in an entitling state whose <c>expires_at</c> passed between 7 days and
    /// 10 minutes ago without a newer read (<c>last_verified_at &lt; expires_at</c>), oldest expiry first (T-134 §4).
    /// </summary>
    Task<IReadOnlyList<ApplePurchaseRow>> ListExpiredSubscriptionsAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken);
}

/// <summary>Metric tag values of the ASSN V2 instruments (T-134 design note §7; fixed sets).</summary>
public static class AssnTags
{
    public const string EnvProduction = "production";
    public const string EnvSandbox = "sandbox";
    public const string EnvNone = "none";

    public const string Stored = "stored";
    public const string Duplicate = "duplicate";
    public const string Unauthorized = "unauthorized";
    public const string IgnoredNoData = "ignored_no_data";
    public const string IgnoredSandbox = "ignored_sandbox";
    public const string IgnoredProduct = "ignored_product";
    public const string BadRequest = "bad_request";

    public const string Applied = "applied";
    public const string Unchanged = "unchanged";
    public const string Superseded = "superseded";
    public const string NoPurchase = "no_purchase";
    public const string EnvMismatch = "env_mismatch";
    public const string Retry = "retry";
    public const string Deferred = "deferred";
    public const string DeadLetter = "dead_letter";
    public const string Ignored = "ignored";

    public const string StepHistory = "history";
    public const string StepExpiry = "expiry";

    /// <summary><c>zaghlol.assn.reconcile{outcome}</c> values.</summary>
    public const string ReconcileOk = "ok";
    public const string ReconcileFailed = "failed";
    public const string ReconcileInvalidEntry = "invalid_entry";
    public const string ReconcileTruncated = "truncated";

    public const string TypeTest = "test";
    public const string TypeOther = "other";

    public static IReadOnlyList<string> IngestOutcomes { get; } =
        [Stored, Duplicate, Unauthorized, IgnoredNoData, IgnoredSandbox, IgnoredProduct, BadRequest];

    public static IReadOnlyList<string> ProcessedOutcomes { get; } =
        [Applied, Unchanged, Superseded, NoPurchase, EnvMismatch, Retry, Deferred, DeadLetter, Ignored];

    public static IReadOnlyList<string> ReconcileOutcomes { get; } =
        [Applied, Unchanged, Superseded, ReconcileOk, ReconcileFailed, ReconcileInvalidEntry, ReconcileTruncated, Deferred];

    /// <summary>The <c>type</c> tag: a reconcile-set name in lower case, <c>test</c> or <c>other</c> (never Apple's raw text).</summary>
    public static string Type(string? notificationType) =>
        notificationType is not null && AppleNotificationIngest.ReconcileSet.Contains(notificationType)
            ? notificationType.ToLowerInvariant()
            : notificationType == "TEST" ? TypeTest : TypeOther;

    public static IReadOnlyList<string> Types { get; } =
        [.. AppleNotificationIngest.ReconcileSet.Select(t => t.ToLowerInvariant()).Order(StringComparer.Ordinal), TypeTest, TypeOther];
}

/// <summary>The ASSN V2 metrics (T-134 design note §7), implemented over <c>ZaghlolMetrics</c>.</summary>
public interface IAppleNotificationTelemetry
{
    /// <summary><c>zaghlol.assn.ingest{env, outcome}</c>; <c>ignored_product</c> is alerted.</summary>
    void Ingested(string env, string outcome);

    /// <summary><c>zaghlol.assn.processed{type, outcome}</c>; <c>env_mismatch</c> and <c>dead_letter</c> are alerted.</summary>
    void Processed(string type, string outcome);

    /// <summary><c>zaghlol.assn.lag</c> (received to processed) and the generic notification lag.</summary>
    void Lag(TimeSpan lag);

    /// <summary>The generic <c>zaghlol.notification.dead_letter{store="apple"}</c> (paged).</summary>
    void DeadLettered();

    /// <summary>The <c>zaghlol.assn.backlog{age}</c> gauge.</summary>
    void SetBacklog(long lessThan1h, long atLeast1h);

    /// <summary><c>zaghlol.assn.reconcile{step, outcome}</c>; <c>invalid_entry</c> and <c>truncated</c> are alerted.</summary>
    void Reconciled(string job, string outcome);

    /// <summary><c>zaghlol.assn.recovered</c>: rows the history job inserted (alerted when &gt; 0: delivery is failing).</summary>
    void Recovered(int count);

    /// <summary><c>zaghlol.assn.refund_not_reflected</c>: a refund applied although Apple still answers otherwise (alerted).</summary>
    void RefundNotReflected();
}
