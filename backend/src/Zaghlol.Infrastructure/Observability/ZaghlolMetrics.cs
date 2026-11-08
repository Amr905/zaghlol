using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Text.RegularExpressions;

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

        foreach (var store in NotificationStores)
        {
            deadLetter.Add(0, Tags(("store", store)));
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
