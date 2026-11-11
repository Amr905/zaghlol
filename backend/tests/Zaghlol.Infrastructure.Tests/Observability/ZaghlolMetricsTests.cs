using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-138: the <c>Zaghlol</c> meter. Tag values are unique per test, because meters are process-wide.</summary>
public sealed class ZaghlolMetricsTests : IDisposable
{
    private readonly ZaghlolMetrics metrics = new();
    private readonly MeterListener listener = new();
    private readonly ConcurrentQueue<(string Instrument, double Value, Dictionary<string, object?> Tags)> seen = new();

    public ZaghlolMetricsTests()
    {
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Meter.Name == ZaghlolMetrics.MeterName)
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((i, v, t, _) => Record(i, v, t));
        listener.SetMeasurementEventCallback<double>((i, v, t, _) => Record(i, v, t));
        listener.Start();
    }

    public void Dispose()
    {
        listener.Dispose();
        metrics.Dispose();
    }

    [Fact]
    public void PurchaseVerifyCarriesStoreOutcomeAndCode()
    {
        metrics.PurchaseVerified("t138play", "failure", "PURCHASE_PENDING");

        var m = Assert.Single(Named("zaghlol.purchase.verify"), x => Equals(x.Tags["store"], "t138play"));
        Assert.Equal(1, m.Value);
        Assert.Equal("failure", m.Tags["outcome"]);
        Assert.Equal("PURCHASE_PENDING", m.Tags["code"]);
    }

    [Fact]
    public void ATagValueThatIsNotAShortWordIsReplaced()
    {
        metrics.SeatChanged("t138 channel with spaces", "move");
        metrics.SeatChanged(new string('a', 41), "bind");

        var changes = Named("zaghlol.seat.change").Where(x => Equals(x.Tags["kind"], "move") || Equals(x.Tags["kind"], "bind")).ToArray();
        Assert.Contains(changes, x => Equals(x.Tags["kind"], "move") && Equals(x.Tags["channel"], "invalid"));
        Assert.Contains(changes, x => Equals(x.Tags["kind"], "bind") && Equals(x.Tags["channel"], "invalid"));
    }

    [Fact]
    public void EveryDesignInstrumentIsPublished()
    {
        metrics.PurchaseVerified("t138a", "success", "NONE");
        metrics.PurchaseAcknowledged(TimeSpan.FromMinutes(3));
        metrics.NotificationProcessed(TimeSpan.FromSeconds(4));
        metrics.NotificationDeadLettered("t138a");
        metrics.NotificationIngested("t138a");
        metrics.SyncResponse(512, upToDate: true);
        metrics.SeatChanged("t138a", "rebind_over_cap");
        metrics.MoveCooldownRefused("t138a");
        metrics.SupportAction("move", "ok", "passed");
        metrics.AttestationFailed("ios", "hash_mismatch");
        metrics.PlayIntegrityCalled();
        metrics.SetUnacked(2, 0, TimeSpan.FromHours(1));
        metrics.SetPriceAge("XAU", TimeSpan.FromMinutes(5));
        metrics.SetPlayIntegrityDailyQuota(10000);
        listener.RecordObservableInstruments();

        string[] expected =
        [
            "zaghlol.purchase.verify", "zaghlol.purchase.time_to_ack", "zaghlol.notification.processing_lag",
            "zaghlol.notification.dead_letter", "zaghlol.notification.ingested", "zaghlol.sync.response.size",
            "zaghlol.seat.change", "zaghlol.seat.move_cooldown_refused", "zaghlol.support.action", "zaghlol.attestation.failure",
            "zaghlol.play_integrity.calls", "zaghlol.purchase.unacked", "zaghlol.purchase.unacked.oldest_age", "zaghlol.price.age",
            "zaghlol.play_integrity.daily_quota", "zaghlol.service.up",
        ];
        var published = seen.Select(x => x.Instrument).ToHashSet(StringComparer.Ordinal);
        Assert.All(expected, name => Assert.Contains(name, published));
    }

    [Fact]
    public void GaugesReportTheLastValueSet()
    {
        metrics.SetUnacked(7, 3, TimeSpan.FromHours(50));
        metrics.SetPriceAge("T138SYM", TimeSpan.FromHours(7));

        listener.RecordObservableInstruments();

        Assert.Contains(Named("zaghlol.purchase.unacked"), x => Equals(x.Tags["age"], "lt_48h") && x.Value == 7);
        Assert.Contains(Named("zaghlol.purchase.unacked"), x => Equals(x.Tags["age"], "ge_48h") && x.Value == 3);
        Assert.Contains(Named("zaghlol.purchase.unacked.oldest_age"), x => x.Value == 50 * 3600);
        Assert.Contains(Named("zaghlol.price.age"), x => Equals(x.Tags["symbol"], "T138SYM") && x.Value == 7 * 3600);
    }

    [Fact]
    public void SyncSizeIsTaggedByUpToDateOnly()
    {
        metrics.SyncResponse(300, upToDate: true);

        var m = Assert.Single(Named("zaghlol.sync.response.size"), x => x.Value == 300);
        Assert.Equal("up_to_date", Assert.Single(m.Tags).Key);
        Assert.Equal("true", m.Tags["up_to_date"]);
    }

    private IEnumerable<(string Instrument, double Value, Dictionary<string, object?> Tags)> Named(string instrument) =>
        seen.Where(x => x.Instrument == instrument);

    private void Record(Instrument instrument, double value, ReadOnlySpan<KeyValuePair<string, object?>> tags)
    {
        var map = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var tag in tags)
        {
            map[tag.Key] = tag.Value;
        }

        seen.Enqueue((instrument.Name, value, map));
    }
}
