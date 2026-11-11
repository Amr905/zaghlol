using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Text.RegularExpressions;
using Zaghlol.Application.Contributions;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Retention;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Application.Sync;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>
/// The <c>Zaghlol</c> meter (T-138 design note; alert rules in <c>deploy/observability/alerts</c>). Tags are low-cardinality
/// words only, never IDs, tokens or hashes: every tag value is checked and replaced by <c>invalid</c> when it isn't a short
/// lower- or upper-case word. T-138 ships the instruments; the owning tasks call them.
/// </summary>
public sealed partial class ZaghlolMetrics : ISeatKeyMetrics, IDisposable
{
    public const string MeterName = "Zaghlol";

    private readonly Meter meter = new(MeterName);
    private readonly Counter<long> verify;
    private readonly Histogram<double> timeToAck;
    private readonly Histogram<double> notificationLag;
    private readonly Counter<long> deadLetter;
    private readonly Counter<long> ingested;
    private readonly Histogram<long> syncBytes;
    private readonly Counter<long> seatChange;
    private readonly Counter<long> moveCooldownRefused;
    private readonly Counter<long> seatProof;
    private readonly Counter<long> seatElementZero;
    private readonly Counter<long> supportAction;
    private readonly Counter<long> attestationFailure;
    private readonly Counter<long> playIntegrityCalls;
    private readonly Counter<long> alertFired;
    private readonly Counter<long> installHashUnavailable;
    private readonly Counter<long> rateLimited;
    private readonly Counter<long> flagChanged;
    private readonly Counter<long> supportLookup;
    private readonly Counter<long> phishingResistantUnproven;
    private readonly Counter<long> operatorUnknownRole;
    private readonly Counter<long> priceFetch;
    private readonly Counter<long> retentionPurged;
    private readonly Counter<long> retentionFailed;
    private readonly Counter<long> priceOverridden;
    private readonly Counter<long> syncRequests;
    private readonly Counter<long> syncCatalog;
    private readonly Counter<long> syncIntake;
    private readonly Counter<long> syncBlockFailure;
    private readonly Counter<long> syncFlagRulesInvalid;
    private readonly Counter<long> contributionEvents;
    private readonly Counter<long> storeCall;
    private readonly Counter<long> purchaseAck;
    private readonly Counter<long> ownershipCheck;
    private readonly Counter<long> idempotencyClaim;
    private readonly Counter<long> appleJws;
    private readonly Counter<long> purchaseEnvironment;
    private readonly Counter<long> assnIngest;
    private readonly Counter<long> assnProcessed;
    private readonly Histogram<double> assnLag;
    private readonly Counter<long> assnReconcile;
    private readonly Counter<long> assnRecovered;
    private readonly Counter<long> assnRefundNotReflected;
    private long assnBacklogLessThan1h;
    private long assnBacklogAtLeast1h;
    private readonly Counter<long> rtdnAuth;
    private readonly Counter<long> rtdnIngest;
    private readonly Counter<long> rtdnProcessed;
    private readonly Histogram<double> rtdnLag;
    private readonly Counter<long> rtdnReconcile;
    private readonly Counter<long> rtdnRecovered;
    private readonly Counter<long> rtdnRefundNotReflected;
    private readonly Counter<long> backlogFailed;
    private long rtdnBacklogLessThan1h;
    private long rtdnBacklogAtLeast1h;
    private readonly ConcurrentDictionary<string, long> heartbeats = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, double> priceAges = new(StringComparer.Ordinal);
    private readonly string serviceVersion;
    private long unackedLessThan48h;
    private long unackedAtLeast48h;
    private double unackedOldestAgeSeconds;
    private long playIntegrityDailyQuota;

    public ZaghlolMetrics()
    {
        serviceVersion = typeof(ZaghlolMetrics).Assembly.GetName().Version?.ToString() ?? "0";
        verify = meter.CreateCounter<long>("zaghlol.purchase.verify", description: "Purchase verifications by store, outcome (success|failure) and problem code.");
        timeToAck = meter.CreateHistogram<double>("zaghlol.purchase.time_to_ack", "s", "Time from purchase to acknowledgement.");
        notificationLag = meter.CreateHistogram<double>("zaghlol.notification.processing_lag", "s", "Store notification receipt to processed.");
        deadLetter = meter.CreateCounter<long>("zaghlol.notification.dead_letter", description: "Store notifications moved to the dead-letter queue.");
        ingested = meter.CreateCounter<long>("zaghlol.notification.ingested", description: "Store notifications accepted.");
        syncBytes = meter.CreateHistogram<long>("zaghlol.sync.response.size", "By", "Sync response size.");
        seatChange = meter.CreateCounter<long>("zaghlol.seat.change", description: "Seat binds, moves and rebinds by channel and kind.");
        moveCooldownRefused = meter.CreateCounter<long>("zaghlol.seat.move_cooldown_refused", description: "MOVE_COOLDOWN refusals by channel.");
        seatProof = meter.CreateCounter<long>(
            "zaghlol.seat.proof",
            description: "seatKeys sets decided, by op (verify|restore|signin) and result (valid or a rejection reason) (T-182).");
        seatElementZero = meter.CreateCounter<long>(
            "zaghlol.seat.element_zero",
            description: "Element-0 checks against the install's registered key, by op and status (none_registered|matches|mismatch) (T-182).");
        supportAction = meter.CreateCounter<long>("zaghlol.support.action", description: "Support actions by action, outcome and ownership-check outcome.");
        attestationFailure = meter.CreateCounter<long>("zaghlol.attestation.failure", description: "Device attestation failures by platform and reason code.");
        playIntegrityCalls = meter.CreateCounter<long>("zaghlol.play_integrity.calls", description: "Play Integrity API calls.");
        alertFired = meter.CreateCounter<long>("zaghlol.audit_alert.fired", description: "Audit alert signals by rule.");
        installHashUnavailable = meter.CreateCounter<long>(
            "zaghlol.diag.install_hash_unavailable",
            description: "Requests logged with installHash=unavailable because the log key could not be read (T-124 F7).");
        rateLimited = meter.CreateCounter<long>("zaghlol.rate_limit.rejected", description: "429 RATE_LIMITED answers by bucket name.");

        flagChanged = meter.CreateCounter<long>("zaghlol.flag.changed", description: "Feature flag changes by flag key (a fixed set of known keys).");
        supportLookup = meter.CreateCounter<long>(
            "zaghlol.support.lookup",
            description: "Support entitlement lookups by the caller's support role (enumeration alert, T-136).");
        phishingResistantUnproven = meter.CreateCounter<long>(
            "zaghlol.diag.operator_phishing_resistant_unproven",
            description: "Operator requests carrying support_agent or support_lead without a proving acrs claim, in Advisory mode (R4-6).");
        operatorUnknownRole = meter.CreateCounter<long>(
            "zaghlol.diag.operator_unknown_role",
            description: "Role strings in operators rows that the API doesn't know; they are dropped.");

        retentionPurged = meter.CreateCounter<long>("zaghlol.retention.purged", description: "Rows deleted or cleared by the RetentionPurger, by rule (fixed names).");
        retentionFailed = meter.CreateCounter<long>("zaghlol.retention.failed", description: "RetentionPurger rule runs that failed, by rule (fixed names).");
        priceFetch = meter.CreateCounter<long>("zaghlol.price.fetch", description: "Price provider fetches by provider (fixed names) and outcome (ok|failed|empty).");
        priceOverridden = meter.CreateCounter<long>("zaghlol.price.override", description: "Operator price overrides.");

        syncRequests = meter.CreateCounter<long>("zaghlol.sync.requests", description: "Sync calls by outcome (ok|throttled|rejected|unavailable).");
        syncCatalog = meter.CreateCounter<long>("zaghlol.sync.catalog", description: "Full sync answers by catalog mode (none|delta|full).");
        syncIntake = meter.CreateCounter<long>(
            "zaghlol.sync.intake",
            description: "Contributions and bank requests by kind and result (accepted|filtered|invalid_code|duplicate|dropped_hasher).");
        syncBlockFailure = meter.CreateCounter<long>("zaghlol.sync.block_failure", description: "Sync source failures by block (catalog|flags|prices|entitlement).");
        contributionEvents = meter.CreateCounter<long>(
            "zaghlol.contribution.events",
            description: "Contribution review events: aggregates ready, promoted, rejected, and raw rows purged (decided|expired). Counts only.");
        syncFlagRulesInvalid = meter.CreateCounter<long>(
            "zaghlol.sync.flag_rules_invalid",
            description: "Syncs that evaluated a flag OFF because its stored rules failed the strict parse, by flag key (FU-056).");

        storeCall = meter.CreateCounter<long>(
            "zaghlol.store.call",
            description: "Outbound store API calls by store, api (sub_get|prod_get|sub_ack|prod_ack|orders_get|tx_get|sub_status|order_lookup), outcome and, for the App Store, env (T-130, T-131).");
        appleJws = meter.CreateCounter<long>(
            "zaghlol.purchase.jws",
            description: "Apple JWS checks by source (app|api) and outcome (ok|malformed|alg|chain|oid|signature|payload) (T-131).");
        purchaseEnvironment = meter.CreateCounter<long>(
            "zaghlol.purchase.environment",
            description: "Verified purchases written, by store and environment (production|sandbox) (T-131).");
        purchaseAck = meter.CreateCounter<long>(
            "zaghlol.purchase.ack",
            description: "Google acknowledgements by channel (verify|sweeper) and outcome (acked|already|failed|not_ackable).");
        ownershipCheck = meter.CreateCounter<long>(
            "zaghlol.purchase.ownership_check",
            description: "Support order-ID ownership checks by path (orders|fallback|apple) and outcome (pass|fail|unavailable).");
        idempotencyClaim = meter.CreateCounter<long>(
            "zaghlol.idempotency.claim",
            description: "Idempotency claims by outcome (claimed|replayed|reused|in_progress|taken_over|lease_lost).");

        // T-134: App Store Server Notifications V2 (design note §7).
        assnIngest = meter.CreateCounter<long>("zaghlol.assn.ingest", description: "ASSN V2 payloads by env (production|sandbox|none) and outcome.");
        assnProcessed = meter.CreateCounter<long>("zaghlol.assn.processed", description: "ASSN V2 rows processed by type (reconcile-set name|test|other) and outcome.");
        assnLag = meter.CreateHistogram<double>("zaghlol.assn.lag", "s", "ASSN V2 notification receipt to processed.");
        assnReconcile = meter.CreateCounter<long>("zaghlol.assn.reconcile", description: "ASSN V2 reconciliation results by step (history|expiry) and outcome.");
        assnRecovered = meter.CreateCounter<long>("zaghlol.assn.recovered", description: "Notifications the history job inserted (Apple delivery failed).");
        assnRefundNotReflected = meter.CreateCounter<long>(
            "zaghlol.assn.refund_not_reflected",
            description: "REFUND/REVOKE notifications applied after the floor while Apple's API still answered otherwise.");
        meter.CreateObservableGauge("zaghlol.assn.backlog", ObserveAssnBacklog, description: "Unprocessed ASSN V2 rows by age (lt_1h|ge_1h).");

        // T-133: Google RTDN (design note §7).
        rtdnAuth = meter.CreateCounter<long>("zaghlol.rtdn.auth", description: "Pub/Sub push authentication by outcome (ok or the failed check).");
        rtdnIngest = meter.CreateCounter<long>("zaghlol.rtdn.ingest", description: "Authenticated RTDN pushes by kind and outcome.");
        rtdnProcessed = meter.CreateCounter<long>("zaghlol.rtdn.processed", description: "RTDN rows processed by type (reconcile-set name|test|other) and outcome.");
        rtdnLag = meter.CreateHistogram<double>("zaghlol.rtdn.lag", "s", "RTDN receipt to processed.");
        rtdnReconcile = meter.CreateCounter<long>("zaghlol.rtdn.reconcile", description: "Google reconciliation results by step (voided|expiry) and outcome.");
        rtdnRecovered = meter.CreateCounter<long>("zaghlol.rtdn.recovered", description: "Voided rows the daily job enqueued with no RTDN for the token (delivery failing).");
        rtdnRefundNotReflected = meter.CreateCounter<long>(
            "zaghlol.rtdn.refund_not_reflected",
            description: "VOIDED_PURCHASE/SUBSCRIPTION_REVOKED rows applied after the floor while Play still answered entitling.");
        meter.CreateObservableGauge("zaghlol.rtdn.backlog", ObserveRtdnBacklog, description: "Unprocessed RTDN rows by age (lt_1h|ge_1h).");
        backlogFailed = meter.CreateCounter<long>("zaghlol.notification.backlog_failed", description: "Backlog gauge refreshes that failed, by store.");
        meter.CreateObservableGauge<double>(
            "zaghlol.notification.processor_heartbeat_age",
            ObserveHeartbeats,
            "s",
            "Seconds since a notification processor of this process last completed a run (or found the lock held elsewhere), by store.");
        meter.CreateObservableGauge("zaghlol.purchase.unacked", ObserveUnacked, description: "Ackable Google purchases waiting for acknowledgement, by age (lt_48h|ge_48h).");
        meter.CreateObservableGauge("zaghlol.purchase.unacked.oldest_age", () => Volatile.Read(ref unackedOldestAgeSeconds), "s", "Age of the oldest unacknowledged purchase.");
        meter.CreateObservableGauge<double>("zaghlol.price.age", ObservePriceAges, "s", "Age of the newest quote per symbol.");
        meter.CreateObservableGauge("zaghlol.play_integrity.daily_quota", () => Interlocked.Read(ref playIntegrityDailyQuota), description: "Configured Play Integrity daily quota.");
        meter.CreateObservableGauge("zaghlol.service.up", () => new Measurement<long>(1, new KeyValuePair<string, object?>("version", serviceVersion)), description: "1 while the process runs.");
    }

    /// <summary>The stores whose notifications can be dead-lettered; their series start at 0.</summary>
    public static IReadOnlyList<string> NotificationStores { get; } = ["play", "apple"];

    public void PurchaseVerified(string store, string outcome, string code) =>
        verify.Add(1, Tags(("store", store), ("outcome", outcome), ("code", code)));

    public void PurchaseAcknowledged(TimeSpan sincePurchase) => timeToAck.Record(sincePurchase.TotalSeconds);

    /// <param name="provider">A name from <c>PriceProviderNames</c> (or <c>none</c>).</param>
    /// <param name="outcome">One of <c>ok</c>, <c>failed</c>, <c>empty</c>.</param>
    public void PriceFetched(string provider, string outcome) => priceFetch.Add(1, Tags(("provider", provider), ("outcome", outcome)));

    /// <param name="rule">A name from <c>RetentionRules</c>.</param>
    public void RetentionPurged(string rule, long count) => retentionPurged.Add(count, Tags(("rule", rule)));

    public void RetentionFailed(string rule) => retentionFailed.Add(1, Tags(("rule", rule)));

    public void PriceOverridden() => priceOverridden.Add(1);

    /// <summary>Called by the acknowledge sweeper after each run (ackable rows only); the oldest age is 0 when none.</summary>
    public void SetUnacked(long lessThan48h, long atLeast48h, TimeSpan oldestAge)
    {
        Interlocked.Exchange(ref unackedLessThan48h, lessThan48h);
        Interlocked.Exchange(ref unackedAtLeast48h, atLeast48h);
        Volatile.Write(ref unackedOldestAgeSeconds, oldestAge.TotalSeconds);
    }

    /// <param name="store"><c>google_play</c> or <c>app_store</c>.</param>
    /// <param name="api">One of <c>StoreCallTags.Apis</c>.</param>
    /// <param name="outcome">One of <c>StoreCallTags.Outcomes</c>.</param>
    public void StoreCall(string store, string api, string outcome) =>
        storeCall.Add(1, Tags(("store", store), ("api", api), ("outcome", outcome)));

    /// <summary>An App Store Server API call (T-131): the T-130 tags plus <c>env</c> (<c>production</c> or <c>sandbox</c>).</summary>
    public void StoreCall(string store, string api, string outcome, string env) =>
        storeCall.Add(1, Tags(("store", store), ("api", api), ("outcome", outcome), ("env", env)));

    /// <param name="source"><c>app</c> or <c>api</c>.</param>
    /// <param name="outcome"><c>ok</c> or a failure reason (<c>PurchaseTags.JwsOutcomes</c>).</param>
    public void AppleJws(string source, string outcome) => appleJws.Add(1, Tags(("source", source), ("outcome", outcome)));

    /// <param name="store"><c>google_play</c> or <c>app_store</c>.</param>
    /// <param name="env"><c>production</c> or <c>sandbox</c>.</param>
    public void PurchaseEnvironment(string store, string env) => purchaseEnvironment.Add(1, Tags(("store", store), ("env", env)));

    /// <param name="channel"><c>verify</c> or <c>sweeper</c>.</param>
    /// <param name="outcome"><c>acked</c>, <c>already</c>, <c>failed</c> or <c>not_ackable</c>.</param>
    public void PurchaseAck(string channel, string outcome) => purchaseAck.Add(1, Tags(("channel", channel), ("outcome", outcome)));

    /// <param name="path"><c>orders</c>, <c>fallback</c> or <c>apple</c>.</param>
    /// <param name="outcome"><c>pass</c>, <c>fail</c> or <c>unavailable</c>.</param>
    public void OwnershipCheck(string path, string outcome) => ownershipCheck.Add(1, Tags(("path", path), ("outcome", outcome)));

    /// <param name="outcome">One of <c>IdempotencyClaimOutcomes</c>.</param>
    public void IdempotencyClaim(string outcome) => idempotencyClaim.Add(1, Tags(("outcome", outcome)));

    /// <summary><c>zaghlol.assn.ingest{env, outcome}</c> (T-134).</summary>
    public void AssnIngested(string env, string outcome) => assnIngest.Add(1, Tags(("env", env), ("outcome", outcome)));

    /// <summary><c>zaghlol.assn.processed{type, outcome}</c> (T-134).</summary>
    public void AssnProcessed(string type, string outcome) => assnProcessed.Add(1, Tags(("type", type), ("outcome", outcome)));

    public void AssnLag(TimeSpan lag) => assnLag.Record(Math.Max(0, lag.TotalSeconds));

    /// <summary><c>zaghlol.assn.reconcile{step, outcome}</c> (T-134).</summary>
    public void AssnReconciled(string step, string outcome) => assnReconcile.Add(1, Tags(("step", step), ("outcome", outcome)));

    public void AssnRecovered(long count) => assnRecovered.Add(count);

    public void AssnRefundNotReflected() => assnRefundNotReflected.Add(1);

    public void SetAssnBacklog(long lessThan1h, long atLeast1h)
    {
        Interlocked.Exchange(ref assnBacklogLessThan1h, lessThan1h);
        Interlocked.Exchange(ref assnBacklogAtLeast1h, atLeast1h);
    }

    /// <summary><c>zaghlol.rtdn.auth{outcome}</c> (T-133).</summary>
    public void RtdnAuth(string outcome) => rtdnAuth.Add(1, Tags(("outcome", outcome)));

    /// <summary><c>zaghlol.rtdn.ingest{kind, outcome}</c> (T-133).</summary>
    public void RtdnIngested(string kind, string outcome) => rtdnIngest.Add(1, Tags(("kind", kind), ("outcome", outcome)));

    /// <summary><c>zaghlol.rtdn.processed{type, outcome}</c> (T-133).</summary>
    public void RtdnProcessed(string type, string outcome) => rtdnProcessed.Add(1, Tags(("type", type), ("outcome", outcome)));

    public void RtdnLag(TimeSpan lag) => rtdnLag.Record(Math.Max(0, lag.TotalSeconds));

    /// <summary><c>zaghlol.rtdn.reconcile{step, outcome}</c> (T-133).</summary>
    public void RtdnReconciled(string step, string outcome) => rtdnReconcile.Add(1, Tags(("step", step), ("outcome", outcome)));

    public void RtdnRecovered(long count) => rtdnRecovered.Add(count);

    public void RtdnRefundNotReflected() => rtdnRefundNotReflected.Add(1);

    public void SetRtdnBacklog(long lessThan1h, long atLeast1h)
    {
        Interlocked.Exchange(ref rtdnBacklogLessThan1h, lessThan1h);
        Interlocked.Exchange(ref rtdnBacklogAtLeast1h, atLeast1h);
    }

    /// <summary><c>zaghlol.notification.backlog_failed{store}</c>.</summary>
    public void NotificationBacklogFailed(string store) => backlogFailed.Add(1, Tags(("store", store)));

    /// <summary>
    /// Starts reporting <c>zaghlol.notification.processor_heartbeat_age{store}</c> in this process (the worker registers its processors),
    /// counting from now: a processor that never completes a run shows a growing age (FU-077 L-3).
    /// </summary>
    public void TrackHeartbeat(string store) => heartbeats.TryAdd(Clean(store), Stopwatch.GetTimestamp());

    /// <summary>A processor of <paramref name="store"/> completed a run (or found the lock held elsewhere): the age restarts at 0.</summary>
    public void Heartbeat(string store) => heartbeats[Clean(store)] = Stopwatch.GetTimestamp();

    public void NotificationProcessed(TimeSpan lag) => notificationLag.Record(lag.TotalSeconds);

    public void NotificationDeadLettered(string store) => deadLetter.Add(1, Tags(("store", store)));

    public void NotificationIngested(string store) => ingested.Add(1, Tags(("store", store)));

    /// <summary>Called by the price worker for every symbol it tracks.</summary>
    public void SetPriceAge(string symbol, TimeSpan age) => priceAges[Clean(symbol)] = age.TotalSeconds;

    public void SyncResponse(long bytes, bool upToDate) =>
        syncBytes.Record(bytes, new TagList { { "up_to_date", upToDate ? "true" : "false" } });

    /// <param name="kind"><c>bind</c>, <c>move</c>, <c>rebind</c> or <c>rebind_over_cap</c>.</param>
    public void SeatChanged(string channel, string kind) => seatChange.Add(1, Tags(("channel", channel), ("kind", kind)));

    public void MoveCooldownRefused(string channel) => moveCooldownRefused.Add(1, Tags(("channel", channel)));

    /// <summary><c>zaghlol.seat.proof{op, result}</c> (T-182): fixed words only.</summary>
    void ISeatKeyMetrics.Proof(SeatOp op, SeatKeyRejection? rejection) =>
        seatProof.Add(1, Tags(("op", SeatOps.Wire(op)), ("result", SeatKeyTags.Result(rejection))));

    /// <summary><c>zaghlol.seat.element_zero{op, status}</c> (T-182): fixed words only.</summary>
    void ISeatKeyMetrics.ElementZero(SeatOp op, ElementZeroStatus status) =>
        seatElementZero.Add(1, Tags(("op", SeatOps.Wire(op)), ("status", SeatKeyTags.Status(status))));

    public void SupportAction(string action, string outcome, string ownershipOutcome) =>
        supportAction.Add(1, Tags(("action", action), ("outcome", outcome), ("ownership_outcome", ownershipOutcome)));

    public void AttestationFailed(string platform, string reason) =>
        attestationFailure.Add(1, Tags(("platform", platform), ("reason", reason)));

    public void PlayIntegrityCalled() => playIntegrityCalls.Add(1);

    /// <summary>The install auth handler or registration could not compute <c>installHash</c>; the request went on.</summary>
    public void InstallHashUnavailable() => installHashUnavailable.Add(1);

    /// <summary><paramref name="bucket"/> is a bucket name constant (<c>network</c>, <c>token</c>, <c>idempotency</c>).</summary>
    public void RateLimited(string bucket) => rateLimited.Add(1, Tags(("bucket", bucket)));

    /// <summary><paramref name="key"/> is one of the known flag keys (the admin endpoint 404s any other).</summary>
    public void FlagChanged(string key) => flagChanged.Add(1, Tags(("key", key)));

    /// <param name="outcome"><c>ok</c>, <c>throttled</c>, <c>rejected</c> or <c>unavailable</c>.</param>
    public void SyncRequest(string outcome) => syncRequests.Add(1, Tags(("outcome", outcome)));

    /// <param name="mode"><c>none</c>, <c>delta</c> or <c>full</c>.</param>
    public void SyncCatalog(string mode) => syncCatalog.Add(1, Tags(("mode", mode)));

    /// <param name="kind"><c>contribution</c> or <c>bank_request</c>.</param>
    /// <param name="result">One of <c>SyncTags.IntakeResults</c>.</param>
    public void SyncIntake(string kind, string result, int count)
    {
        if (count > 0)
        {
            syncIntake.Add(count, Tags(("kind", kind), ("result", result)));
        }
    }

    /// <param name="block"><c>catalog</c>, <c>flags</c>, <c>prices</c> or <c>entitlement</c>.</param>
    public void SyncBlockFailed(string block) => syncBlockFailure.Add(1, Tags(("block", block)));

    /// <param name="flag">A known flag key (the closed set).</param>
    public void SyncFlagRulesInvalid(string flag) => syncFlagRulesInvalid.Add(1, Tags(("flag", flag)));

    /// <param name="name">One of <c>ContributionEvents.All</c>.</param>
    public void ContributionEvent(string name, int count)
    {
        if (count > 0)
        {
            contributionEvents.Add(count, Tags(("event", name)));
        }
    }

    /// <param name="role">A known operator role constant.</param>
    public void SupportLookup(string role) => supportLookup.Add(1, Tags(("role", role)));

    /// <param name="role"><c>support_agent</c> or <c>support_lead</c>.</param>
    public void OperatorPhishingResistantUnproven(string role) => phishingResistantUnproven.Add(1, Tags(("role", role)));

    public void OperatorUnknownRole() => operatorUnknownRole.Add(1);

    public void SetPlayIntegrityDailyQuota(long quota) => Interlocked.Exchange(ref playIntegrityDailyQuota, quota);

    internal void AuditAlertFired(string rule) => alertFired.Add(1, Tags(("rule", rule)));

    public void Dispose() => meter.Dispose();

    /// <summary>
    /// A labelled counter series doesn't exist until its first Add, and Prometheus <c>increase()</c> needs an earlier sample,
    /// so the first event of a rare "any occurrence" alert would never fire. Every such series starts at 0 here. Counter.Add is dropped
    /// while no listener exists, so this runs from <c>MetricsStarter</c> after the MeterProvider is built, never from the constructor.
    /// </summary>
    public void SeedSeries()
    {
        foreach (var rule in Enum.GetValues<AuditAlertRule>())
        {
            alertFired.Add(0, Tags(("rule", AlertSignal.RuleName(rule))));
        }

        foreach (var rule in RetentionRules.All)
        {
            retentionPurged.Add(0, Tags(("rule", rule)));
            retentionFailed.Add(0, Tags(("rule", rule)));
        }

        foreach (var store in NotificationStores)
        {
            deadLetter.Add(0, Tags(("store", store)));
        }

        foreach (var outcome in SyncTags.Outcomes)
        {
            syncRequests.Add(0, Tags(("outcome", outcome)));
        }

        foreach (var mode in SyncTags.CatalogModeValues)
        {
            syncCatalog.Add(0, Tags(("mode", mode)));
        }

        foreach (var kind in SyncTags.IntakeKinds)
        {
            foreach (var result in SyncTags.IntakeResults)
            {
                syncIntake.Add(0, Tags(("kind", kind), ("result", result)));
            }
        }

        foreach (var block in SyncTags.Blocks)
        {
            syncBlockFailure.Add(0, Tags(("block", block)));
        }

        foreach (var name in ContributionEvents.All)
        {
            contributionEvents.Add(0, Tags(("event", name)));
        }

        foreach (var flag in FlagKeys.Known)
        {
            syncFlagRulesInvalid.Add(0, Tags(("flag", flag)));
        }

        // The auth_error alert (a wrong credential or permission, T-130) needs a sample before the first failure.
        foreach (var api in StoreCallApis)
        {
            storeCall.Add(0, Tags(("store", "google_play"), ("api", api), ("outcome", "auth_error")));
        }

        foreach (var channel in new[] { "verify", "sweeper" })
        {
            purchaseAck.Add(0, Tags(("channel", channel), ("outcome", "failed")));
        }

        // T-131: the Apple auth_error and client_error alerts, and the alert on any Apple API JWS that fails verification.
        foreach (var api in AppleCallApis)
        {
            foreach (var env in new[] { "production", "sandbox" })
            {
                storeCall.Add(0, Tags(("store", "app_store"), ("api", api), ("outcome", "auth_error"), ("env", env)));
                storeCall.Add(0, Tags(("store", "app_store"), ("api", api), ("outcome", "client_error"), ("env", env)));
            }
        }

        foreach (var outcome in new[] { "malformed", "alg", "chain", "oid", "signature", "payload" })
        {
            appleJws.Add(0, Tags(("source", "api"), ("outcome", outcome)));
        }

        // T-134: every alerted ASSN series starts at 0.
        foreach (var env in new[] { AssnTags.EnvProduction, AssnTags.EnvSandbox })
        {
            assnIngest.Add(0, Tags(("env", env), ("outcome", AssnTags.IgnoredProduct)));
        }

        foreach (var type in AssnTags.Types)
        {
            assnProcessed.Add(0, Tags(("type", type), ("outcome", AssnTags.EnvMismatch)));
            assnProcessed.Add(0, Tags(("type", type), ("outcome", AssnTags.DeadLetter)));
        }

        foreach (var outcome in new[] { AssnTags.ReconcileInvalidEntry, AssnTags.ReconcileTruncated, AssnTags.ReconcileFailed })
        {
            assnReconcile.Add(0, Tags(("step", AssnTags.StepHistory), ("outcome", outcome)));
        }

        assnRecovered.Add(0);
        assnRefundNotReflected.Add(0);

        // T-133: every alerted RTDN series starts at 0.
        foreach (var outcome in new[] { RtdnTags.Auth.BadAudience, RtdnTags.Auth.BadSender, RtdnTags.Auth.KeysUnavailable })
        {
            rtdnAuth.Add(0, Tags(("outcome", outcome)));
        }

        foreach (var outcome in new[] { RtdnTags.IgnoredPackage, RtdnTags.IgnoredMalformed, RtdnTags.IgnoredStale, RtdnTags.IgnoredSubscription })
        {
            rtdnIngest.Add(0, Tags(("kind", PlayNotificationIngest.Kinds.None), ("outcome", outcome)));
        }

        foreach (var type in PlayRtdnTypes.Tags)
        {
            foreach (var outcome in new[] { RtdnTags.EnvMismatch, RtdnTags.Refused, RtdnTags.TokenGone, RtdnTags.DeadLetter })
            {
                rtdnProcessed.Add(0, Tags(("type", type), ("outcome", outcome)));
            }
        }

        foreach (var outcome in new[] { RtdnTags.ReconcileFailed, RtdnTags.ReconcileTruncated })
        {
            rtdnReconcile.Add(0, Tags(("step", RtdnTags.StepVoided), ("outcome", outcome)));
        }

        rtdnRecovered.Add(0);
        rtdnRefundNotReflected.Add(0);
        foreach (var store in NotificationStores)
        {
            backlogFailed.Add(0, Tags(("store", store)));
        }
    }

    /// <summary>The <c>api</c> tag values of App Store calls (<c>AppStoreCallTags.Apis</c>).</summary>
    internal static IReadOnlyList<string> AppleCallApis { get; } = ["tx_get", "sub_status", "order_lookup", "notification_history"];

    /// <summary>The <c>api</c> tag values of <c>zaghlol.store.call</c> (StoreCallTags.Apis).</summary>
    internal static IReadOnlyList<string> StoreCallApis { get; } = ["sub_get", "prod_get", "sub_ack", "prod_ack", "orders_get", "voided_list"];

    private IEnumerable<Measurement<long>> ObserveUnacked() =>
    [
        new(Interlocked.Read(ref unackedLessThan48h), new KeyValuePair<string, object?>("age", "lt_48h")),
        new(Interlocked.Read(ref unackedAtLeast48h), new KeyValuePair<string, object?>("age", "ge_48h")),
    ];

    private IEnumerable<Measurement<long>> ObserveAssnBacklog() =>
    [
        new(Interlocked.Read(ref assnBacklogLessThan1h), new KeyValuePair<string, object?>("age", "lt_1h")),
        new(Interlocked.Read(ref assnBacklogAtLeast1h), new KeyValuePair<string, object?>("age", "ge_1h")),
    ];

    private IEnumerable<Measurement<long>> ObserveRtdnBacklog() =>
    [
        new(Interlocked.Read(ref rtdnBacklogLessThan1h), new KeyValuePair<string, object?>("age", "lt_1h")),
        new(Interlocked.Read(ref rtdnBacklogAtLeast1h), new KeyValuePair<string, object?>("age", "ge_1h")),
    ];

    private IEnumerable<Measurement<double>> ObserveHeartbeats() =>
        heartbeats.Select(h => new Measurement<double>(Stopwatch.GetElapsedTime(h.Value).TotalSeconds, new KeyValuePair<string, object?>("store", h.Key)));

    private IEnumerable<Measurement<double>> ObservePriceAges() =>
        priceAges.Select(p => new Measurement<double>(p.Value, new KeyValuePair<string, object?>("symbol", p.Key)));

    private static TagList Tags(params (string Name, string Value)[] tags)
    {
        var list = new TagList();
        foreach (var (name, value) in tags)
        {
            list.Add(name, Clean(value));
        }

        return list;
    }

    private static string Clean(string? value) => value is not null && TagValueRegex().IsMatch(value) ? value : "invalid";

    [GeneratedRegex("^[A-Za-z0-9_:.-]{1,40}$", RegexOptions.CultureInvariant)]
    private static partial Regex TagValueRegex();
}
