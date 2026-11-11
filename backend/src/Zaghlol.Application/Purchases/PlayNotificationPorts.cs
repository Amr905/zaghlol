using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>A due <c>store_notifications</c> row of Google Play (the processor's pick, T-133 §3).</summary>
/// <param name="ExternalId">The Pub/Sub <c>messageId</c>, or a job key (<c>voided:…</c>, <c>sweep:…</c>).</param>
public sealed record DuePlayNotification(
    Guid Id,
    string ExternalId,
    string Type,
    string? Subtype,
    Sensitive<string>? StoreKey,
    PurchaseEnvironment? Environment,
    int Attempts,
    DateTimeOffset ReceivedAt);

/// <summary>The stored Google purchase a notification or a job re-reads.</summary>
public sealed record PlayPurchaseRow(
    Guid Id,
    Sensitive<string> StoreKey,
    string ProductId,
    PurchaseEnvironment Environment,
    StoredPurchaseState State);

/// <summary>A Google subscription whose expiry passed without a newer read (the hourly sweep's candidate, T-133 §4).</summary>
public sealed record PlayExpiredSubscription(Guid PurchaseId, Sensitive<string> StoreKey, DateTimeOffset ExpiresAt);

/// <summary>
/// One worker write (T-133 §3 step 7): Play's current answer, settled through <see cref="PlayStateMapping.Settle"/> under the row lock
/// and applied only when <c>last_verified_at &lt; ReadAt</c>. It carries only <c>state</c>, <c>expires_at</c> and
/// <c>last_verified_at</c>: a Google row never changes product or plan, and the worker's grant allows nothing verify-only.
/// </summary>
/// <param name="Read">Play's mapped state (before the label rule).</param>
/// <param name="SettleType">The RTDN type for the label rule (<c>VOIDED_PURCHASE</c>, <c>SUBSCRIPTION_REVOKED</c>, …).</param>
/// <param name="OnlyFromPending">
/// <c>SUBSCRIPTION_PENDING_PURCHASE_CANCELED</c>: write <c>expired</c> only while the stored state is <c>pending</c>, else nothing.
/// </param>
/// <param name="Cause">The <c>purchase_events.cause</c>: <c>rtdn:&lt;type&gt;</c> or <c>sweep</c>.</param>
public sealed record PlayStateWrite(
    Guid PurchaseId,
    StoredPurchaseState Read,
    DateTimeOffset? ExpiresAt,
    bool KeepStoredExpiry,
    string? SettleType,
    bool OnlyFromPending,
    DateTimeOffset ReadAt,
    string Cause);

/// <summary>What a Google worker write did.</summary>
public enum PlayWriteResult
{
    /// <summary>Written, and the state changed (a <c>purchase_events</c> row was added).</summary>
    Applied,

    /// <summary>Written with the same state, or nothing to write (a pending-cancel for a row that isn't pending).</summary>
    Unchanged,

    /// <summary>A newer read (verify, the sweeper, another notification) is already stored: nothing written.</summary>
    Superseded,

    /// <summary>The purchase row no longer exists.</summary>
    Gone,
}

/// <summary>The RTDN worker's rows, on the Worker login (<c>worker_rw</c>).</summary>
public interface IPlayNotificationStore
{
    /// <summary><c>pg_try_advisory_lock</c> named <paramref name="name"/>, held until disposed; <c>null</c> when another replica holds it.</summary>
    Task<IAsyncDisposable?> TryLockAsync(string name, CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> unprocessed Google rows whose <c>next_attempt_at</c> is NULL or due, never-failed first, then
    /// earliest due, then oldest (<c>ix_store_notifications_due</c>). No transaction held.
    /// </summary>
    Task<IReadOnlyList<DuePlayNotification>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken);

    /// <summary>The Google purchase of <paramref name="storeKey"/>, or <c>null</c>. Never inserts one.</summary>
    Task<PlayPurchaseRow?> FindPurchaseAsync(Sensitive<string> storeKey, CancellationToken cancellationToken);

    /// <summary>
    /// One short transaction: <c>SELECT … FOR UPDATE</c>, the label rule, the guarded update, a <c>purchase_events</c> row on a state
    /// change and the processed mark of <paramref name="notificationId"/> (<c>NO_PURCHASE</c> when the row is gone).
    /// </summary>
    Task<PlayWriteResult> ApplyAsync(PlayStateWrite write, Guid notificationId, CancellationToken cancellationToken);

    /// <summary>Marks a notification processed with an informational code (<c>NO_PURCHASE</c>, <c>REFUSED</c>, …) or none.</summary>
    Task CompleteAsync(Guid notificationId, string? code, CancellationToken cancellationToken);

    /// <summary>A counted failure; <paramref name="nextAttemptAt"/> <c>null</c> is the dead letter (<c>processed_at = now()</c>).</summary>
    Task FailAsync(Guid notificationId, int attempts, DateTimeOffset? nextAttemptAt, string code, CancellationToken cancellationToken);

    /// <summary>An uncounted deferral (Play 429, our budget, an open circuit): only <c>next_attempt_at</c> moves.</summary>
    Task DeferAsync(Guid notificationId, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken);

    /// <summary>Unprocessed Google rows younger and older than one hour (the backlog gauge).</summary>
    Task<(long LessThan1h, long AtLeast1h)> BacklogAsync(DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>
    /// Up to <paramref name="limit"/> Google subscriptions in <c>active|in_grace|canceled_active</c> whose <c>expires_at</c> lies in
    /// <c>[now − 7 d, now − 10 min]</c> with <c>last_verified_at &lt; expires_at</c>, and for which no <c>sweep:</c> row of that expiry
    /// exists yet (pending, done or dead-lettered: FU-098 code 3), oldest expiry first.
    /// </summary>
    Task<IReadOnlyList<PlayExpiredSubscription>> ListExpiredSubscriptionsAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken);

    /// <summary>True when an RTDN (not the voided job) already delivered a <c>VOIDED_PURCHASE</c> for this token.</summary>
    Task<bool> HasRtdnVoidedAsync(Sensitive<string> storeKey, CancellationToken cancellationToken);
}

/// <summary>Metric tag values of the RTDN instruments (T-133 design note §7; fixed sets).</summary>
public static class RtdnTags
{
    public const string Stored = "stored";
    public const string Duplicate = "duplicate";
    public const string IgnoredMalformed = "ignored_malformed";
    public const string IgnoredStale = "ignored_stale";
    public const string IgnoredPackage = "ignored_package";
    public const string IgnoredSubscription = "ignored_subscription";

    public const string Applied = "applied";
    public const string Unchanged = "unchanged";
    public const string Superseded = "superseded";
    public const string NoPurchase = "no_purchase";
    public const string EnvMismatch = "env_mismatch";
    public const string Refused = "refused";
    public const string TokenGone = "gone";
    public const string Retry = "retry";
    public const string Deferred = "deferred";
    public const string DeadLetter = "dead_letter";
    public const string Ignored = "ignored";

    public const string StepVoided = "voided";
    public const string StepExpiry = "expiry";

    public const string ReconcileOk = "ok";
    public const string ReconcileFailed = "failed";
    public const string ReconcileTruncated = "truncated";

    /// <summary><c>zaghlol.rtdn.auth{outcome}</c> values.</summary>
    public static class Auth
    {
        public const string Ok = "ok";
        public const string Missing = "missing";
        public const string Malformed = "malformed";
        public const string BadAlg = "bad_alg";
        public const string UnknownKid = "unknown_kid";
        public const string BadSignature = "bad_signature";
        public const string BadIssuer = "bad_issuer";
        public const string BadAudience = "bad_audience";
        public const string BadSender = "bad_sender";
        public const string UnverifiedSender = "unverified_sender";
        public const string Expired = "expired";
        public const string KeysUnavailable = "keys_unavailable";

        /// <summary>Development/Testing without <c>Rtdn:Audience</c>/<c>PushServiceAccount</c> (Production refuses to start).</summary>
        public const string NotConfigured = "not_configured";

        public static IReadOnlyList<string> All { get; } =
        [
            Ok, Missing, Malformed, BadAlg, UnknownKid, BadSignature, BadIssuer, BadAudience, BadSender, UnverifiedSender, Expired,
            KeysUnavailable, NotConfigured,
        ];
    }

    public static IReadOnlyList<string> IngestOutcomes { get; } =
        [Stored, Duplicate, IgnoredMalformed, IgnoredStale, IgnoredPackage, IgnoredSubscription];

    public static IReadOnlyList<string> ProcessedOutcomes { get; } =
        [Applied, Unchanged, Superseded, NoPurchase, EnvMismatch, Refused, TokenGone, Retry, Deferred, DeadLetter, Ignored];

    public static IReadOnlyList<string> ReconcileOutcomes { get; } =
        [ReconcileOk, ReconcileFailed, ReconcileTruncated, Deferred];
}

/// <summary>The RTDN metrics (T-133 design note §7), implemented over <c>ZaghlolMetrics</c>.</summary>
public interface IPlayNotificationTelemetry
{
    /// <summary><c>zaghlol.rtdn.ingest{kind, outcome}</c>; <c>ignored_package</c> pages, other <c>ignored_*</c> warn.</summary>
    void Ingested(string kind, string outcome);

    /// <summary><c>zaghlol.rtdn.processed{type, outcome}</c>; <c>env_mismatch</c>, <c>refused</c>, <c>gone</c> (Play 410 on an entitling row) warn.</summary>
    void Processed(string type, string outcome);

    /// <summary><c>zaghlol.rtdn.lag</c> (received to processed) and the generic notification lag.</summary>
    void Lag(TimeSpan lag);

    /// <summary>The generic <c>zaghlol.notification.dead_letter{store="play"}</c> (paged).</summary>
    void DeadLettered();

    /// <summary>The <c>zaghlol.rtdn.backlog{age}</c> gauge.</summary>
    void SetBacklog(long lessThan1h, long atLeast1h);

    /// <summary>The backlog query failed after a run (counted, never hides the run's outcome).</summary>
    void BacklogFailed();

    /// <summary><c>zaghlol.rtdn.reconcile{step, outcome}</c>.</summary>
    void Reconciled(string job, string outcome);

    /// <summary><c>zaghlol.rtdn.recovered</c>: voided rows the daily job inserted with no RTDN for the token (warn: delivery failing).</summary>
    void Recovered(int count);

    /// <summary><c>zaghlol.rtdn.refund_not_reflected</c>: a void/revoke applied after the floor while Play still entitles (warn).</summary>
    void RefundNotReflected();

    /// <summary><c>zaghlol.notification.processor_heartbeat_age{store="play"}</c> restarts at 0 (a run completed or the lock is held elsewhere).</summary>
    void Heartbeat();
}
