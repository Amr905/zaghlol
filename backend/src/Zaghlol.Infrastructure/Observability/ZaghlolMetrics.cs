using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Text.RegularExpressions;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Retention;
using Zaghlol.Application.Sync;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>
/// The <c>Zaghlol</c> meter (T-138 design note; alert rules in <c>deploy/observability/alerts</c>). Tags are low-cardinality
/// words only, never IDs, tokens or hashes: every tag value is checked and replaced by <c>invalid</c> when it isn't a short
/// lower- or upper-case word. T-138 ships the instruments; the owning tasks call them.
/// </summary>
public sealed partial class ZaghlolMetrics : IDisposable
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
    private readonly ConcurrentDictionary<string, double> priceAges = new(StringComparer.Ordinal);
    private readonly string serviceVersion;
    private long unackedCount;
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

        syncRequests = meter.CreateCounter<long>("zaghlol.sync.requests", description: "Sync calls by outcome (ok|throttled|rejected).");
        syncCatalog = meter.CreateCounter<long>("zaghlol.sync.catalog", description: "Full sync answers by catalog mode (none|delta|full).");
        syncIntake = meter.CreateCounter<long>(
            "zaghlol.sync.intake",
            description: "Contributions and bank requests by kind and result (accepted|filtered|invalid_code|duplicate|dropped_hasher).");
        syncBlockFailure = meter.CreateCounter<long>("zaghlol.sync.block_failure", description: "Sync source failures by block (catalog|flags|prices|entitlement).");
        syncFlagRulesInvalid = meter.CreateCounter<long>(
            "zaghlol.sync.flag_rules_invalid",
            description: "Syncs that evaluated a flag OFF because its stored rules failed the strict parse, by flag key (FU-056).");

        meter.CreateObservableGauge("zaghlol.purchase.unacked", () => Interlocked.Read(ref unackedCount), description: "Purchases waiting for acknowledgement.");
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

    /// <summary>Called by the worker that counts unacknowledged purchases; the oldest age is 0 when none.</summary>
    public void SetUnacked(long count, TimeSpan oldestAge)
    {
        Interlocked.Exchange(ref unackedCount, count);
        Volatile.Write(ref unackedOldestAgeSeconds, oldestAge.TotalSeconds);
    }

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

    /// <param name="outcome"><c>ok</c>, <c>throttled</c> or <c>rejected</c>.</param>
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

        foreach (var flag in FlagKeys.Known)
        {
            syncFlagRulesInvalid.Add(0, Tags(("flag", flag)));
        }
    }

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
