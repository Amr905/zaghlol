using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>T-131 §8: every App Store tag value comes from a fixed set (no identifier can become a label).</summary>
public sealed class AppStoreMetricsTests
{
    [Fact]
    public void JwsEnvironmentAndOwnershipTagsComeFromFixedSets()
    {
        using var metrics = new ZaghlolMetrics();
        var seen = new ConcurrentQueue<(string Instrument, Dictionary<string, string?> Tags)>();
        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (ReferenceEquals(instrument.Meter, typeof(ZaghlolMetrics).GetField("meter", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.GetValue(metrics)))
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((instrument, _, tags, _) =>
            seen.Enqueue((instrument.Name, tags.ToArray().ToDictionary(t => t.Key, t => t.Value as string, StringComparer.Ordinal))));
        listener.Start();
        var telemetry = new PurchaseTelemetry(metrics, new AlertSignal(metrics, NullLogger<AlertSignal>.Instance));

        foreach (var source in Enum.GetValues<JwsSource>())
        {
            telemetry.AppleJwsChecked(source, null);
            foreach (var failure in Enum.GetValues<AppleJwsFailure>())
            {
                telemetry.AppleJwsChecked(source, failure);
            }
        }

        foreach (var environment in Enum.GetValues<PurchaseEnvironment>())
        {
            telemetry.EnvironmentSeen(PurchaseTags.AppStore, environment);
        }

        foreach (var outcome in Enum.GetValues<OwnershipOutcome>())
        {
            telemetry.OwnershipChecked(PurchaseTags.PathApple, outcome);
        }

        foreach (var api in Enum.GetValues<AppStoreApi>())
        {
            foreach (var outcome in Enum.GetValues<AppStoreCallOutcome>())
            {
                metrics.StoreCall(PurchaseTags.AppStore, AppStoreCallTags.Api(api), AppStoreCallTags.Outcome(outcome), "sandbox");
            }
        }

        var jws = seen.Where(s => s.Instrument == "zaghlol.purchase.jws").ToList();
        Assert.Equal(Enum.GetValues<JwsSource>().Length * (1 + Enum.GetValues<AppleJwsFailure>().Length), jws.Count);
        Assert.All(jws, s => Assert.Contains(s.Tags["source"], PurchaseTags.JwsSources));
        Assert.All(jws, s => Assert.Contains(s.Tags["outcome"], PurchaseTags.JwsOutcomes));
        Assert.Equal(PurchaseTags.JwsOutcomes.Count, jws.Select(s => s.Tags["outcome"]).Distinct().Count());

        var environments = seen.Where(s => s.Instrument == "zaghlol.purchase.environment").ToList();
        Assert.Equal(["production", "sandbox"], environments.Select(s => s.Tags["env"]).Order());
        Assert.All(environments, s => Assert.Equal("app_store", s.Tags["store"]));

        Assert.All(seen.Where(s => s.Instrument == "zaghlol.purchase.ownership_check"), s => Assert.Equal("apple", s.Tags["path"]));

        var calls = seen.Where(s => s.Instrument == "zaghlol.store.call").ToList();
        Assert.All(calls, s => Assert.Contains(s.Tags["api"], AppStoreCallTags.Apis));
        Assert.All(calls, s => Assert.Contains(s.Tags["outcome"], Zaghlol.Infrastructure.GooglePlay.StoreCallTags.Outcomes));
        Assert.Equal(AppStoreCallTags.Apis, ZaghlolMetrics.AppleCallApis);
    }
}
