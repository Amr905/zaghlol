using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Sync;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-128 design note §7: the sync instruments carry only their fixed tag names and values (no install, no text).</summary>
public sealed class SyncMetricsTests : IDisposable
{
    private static readonly Dictionary<string, string[]> AllowedTags = new(StringComparer.Ordinal)
    {
        ["zaghlol.sync.requests"] = ["outcome"],
        ["zaghlol.sync.catalog"] = ["mode"],
        ["zaghlol.sync.intake"] = ["kind", "result"],
        ["zaghlol.sync.block_failure"] = ["block"],
        ["zaghlol.sync.flag_rules_invalid"] = ["flag"],
        ["zaghlol.sync.response.size"] = ["up_to_date"],
    };

    private readonly ZaghlolMetrics metrics = new();
    private readonly MeterListener listener = new();
    private readonly ConcurrentQueue<(string Instrument, long Value, Dictionary<string, object?> Tags)> seen = new();

    public SyncMetricsTests()
    {
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Meter.Name == ZaghlolMetrics.MeterName && instrument.Name.StartsWith("zaghlol.sync.", StringComparison.Ordinal))
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((i, v, t, _) =>
        {
            var tags = new Dictionary<string, object?>(StringComparer.Ordinal);
            foreach (var tag in t)
            {
                tags[tag.Key] = tag.Value;
            }

            seen.Enqueue((i.Name, v, tags));
        });
        listener.Start();
    }

    public void Dispose()
    {
        listener.Dispose();
        metrics.Dispose();
    }

    [Fact]
    public void EverySyncInstrumentUsesOnlyItsFixedTagsAndValues()
    {
        foreach (var outcome in SyncTags.Outcomes)
        {
            metrics.SyncRequest(outcome);
        }

        foreach (var mode in SyncTags.CatalogModeValues)
        {
            metrics.SyncCatalog(mode);
        }

        foreach (var kind in SyncTags.IntakeKinds)
        {
            foreach (var result in SyncTags.IntakeResults)
            {
                metrics.SyncIntake(kind, result, 2);
            }
        }

        foreach (var block in SyncTags.Blocks)
        {
            metrics.SyncBlockFailed(block);
        }

        foreach (var flag in FlagKeys.Known)
        {
            metrics.SyncFlagRulesInvalid(flag);
        }

        metrics.SyncResponse(300, upToDate: true);

        var values = SyncTags.Outcomes.Concat(SyncTags.CatalogModeValues).Concat(SyncTags.IntakeKinds).Concat(SyncTags.IntakeResults)
            .Concat(SyncTags.Blocks).Concat(FlagKeys.Known).Concat(["true", "false"]).ToHashSet(StringComparer.Ordinal);
        var measured = seen.ToArray();
        Assert.Equal(AllowedTags.Keys.Order(StringComparer.Ordinal), measured.Select(m => m.Instrument).Distinct().Order(StringComparer.Ordinal));
        Assert.All(measured, m =>
        {
            Assert.Equal(AllowedTags[m.Instrument].Order(StringComparer.Ordinal), m.Tags.Keys.Order(StringComparer.Ordinal));
            Assert.All(m.Tags.Values, v => Assert.Contains((string)v!, values));
        });
    }

    [Fact]
    public void AnIntakeCountOfZeroAddsNothingAndRequestTextNeverBecomesATag()
    {
        metrics.SyncIntake(SyncTags.Contribution, SyncTags.Accepted, 0);
        metrics.SyncBlockFailed("010 1234 5678");

        // Other tests may seed these series at 0 in parallel (the meter is process-wide), so only non-zero adds count here.
        Assert.DoesNotContain(seen, m => m.Instrument == "zaghlol.sync.intake" && m.Value > 0);
        var failures = seen.Where(m => m.Instrument == "zaghlol.sync.block_failure" && m.Value > 0).ToArray();
        Assert.Equal("invalid", Assert.Single(failures).Tags["block"]);
    }
}
