using System.Diagnostics.Metrics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Application.Retention;
using Zaghlol.Infrastructure.Llm.Spend;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Retention;
using Zaghlol.Infrastructure.Tests.Llm.Quota;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm.Spend;

public class LlmSpendMetricsTests
{
    // AC 4: every tag key the metrics emit is in the closed allow-list, and no tag value carries text, an install or an account id.
    [Fact]
    public void MetricsCarryOnlyAllowListedTagKeysAndFixedValues()
    {
        var seen = new List<(string Instrument, string Key, string Value)>();
        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Name.StartsWith("zaghlol.llm.", StringComparison.Ordinal))
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        void Capture(Instrument instrument, ReadOnlySpan<KeyValuePair<string, object?>> tags)
        {
            foreach (var t in tags)
            {
                seen.Add((instrument.Name, t.Key, t.Value?.ToString() ?? string.Empty));
            }
        }

        listener.SetMeasurementEventCallback<long>((i, _, tags, _) => Capture(i, tags));
        listener.SetMeasurementEventCallback<double>((i, _, tags, _) => Capture(i, tags));
        listener.SetMeasurementEventCallback<decimal>((i, _, tags, _) => Capture(i, tags));
        listener.Start();

        using var metrics = new LlmMetrics();
        const string marker = "salary question 3f2504e0-4f89-41d3-9a0c-0305e82c3301";
        foreach (var feature in new[] { LlmFeature.Ask, LlmFeature.Categorise })
        {
            metrics.ProviderCall(feature, marker, LlmOutcome.Ok, TimeSpan.FromMilliseconds(120), new LlmUsage(100, 20, 30), 0.0012m);
            metrics.Plan(feature, "PL-SPEND");
            metrics.Plan(feature, marker);
            metrics.Fallback(feature);
            metrics.Refusal(feature, marker);
            metrics.ValidationFailure(feature, "schema");
            metrics.RateLimited(feature, "install");
            metrics.QuotaHit(feature);
            metrics.Paused(feature, "cap");
        }

        Assert.NotEmpty(seen);
        Assert.All(seen, s => Assert.Contains(s.Key, LlmMetricTags.AllowedKeys));
        Assert.DoesNotContain(seen, s => s.Value.Contains("salary", StringComparison.Ordinal) || s.Value.Contains("3f2504e0", StringComparison.Ordinal));
        Assert.Contains(seen, s => s is { Instrument: "zaghlol.llm.plans", Value: "other" });
        Assert.Equal(
            ["zaghlol.llm.cost_usd", "zaghlol.llm.fallbacks", "zaghlol.llm.latency", "zaghlol.llm.paused", "zaghlol.llm.plans", "zaghlol.llm.quota_hits", "zaghlol.llm.rate_limited", "zaghlol.llm.refusals", "zaghlol.llm.requests", "zaghlol.llm.tokens", "zaghlol.llm.validation_failures"],
            seen.Select(s => s.Instrument).Distinct().Order(StringComparer.Ordinal));
    }
}

/// <summary>T-339 against PostgreSQL: the upsert, the month total, the alert claim and the 13-month purge.</summary>
public class LlmSpendRepositoryTests(LlmQuotaFixture fixture) : IClassFixture<LlmQuotaFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 20, 10, 0, 0, TimeSpan.Zero);

    private SpendLedgerRepository Repository => new(fixture.Services.GetRequiredKeyedService<Npgsql.NpgsqlDataSource>(DatabaseRole.App));

    [Fact]
    public async Task UpsertAddsToTheDayRowAndTheTotalIsADecimalSum()
    {
        var repository = Repository;
        var day = new DateOnly(2031, 3, 5);
        await repository.RecordAsync(new SpendRecord(day, LlmFeature.Ask, "p1", "m1", 1, 100, 20, 30, 0.000123m), CancellationToken.None);
        await repository.RecordAsync(new SpendRecord(day, LlmFeature.Ask, "p1", "m1", 1, 50, 0, 10, 0.000077m), CancellationToken.None);
        await repository.RecordAsync(new SpendRecord(day, LlmFeature.Categorise, "p1", "m1", 1, 5, 0, 1, 0.5m), CancellationToken.None);
        await repository.RecordAsync(new SpendRecord(new DateOnly(2031, 4, 1), LlmFeature.Ask, "p1", "m1", 1, 1, 0, 1, 7m), CancellationToken.None);

        var row = (await Db.QueryAsync(fixture.Database.Superuser, "SELECT calls, input_tokens, cached_tokens, output_tokens, cost_usd FROM zaghlol.llm_spend_daily WHERE day = '2031-03-05' AND feature = 'ask'")).Single();
        Assert.Equal((2, 150L, 20L, 40L, 0.0002m), ((int)row[0]!, (long)row[1]!, (long)row[2]!, (long)row[3]!, (decimal)row[4]!));
        Assert.Equal(0.5002m, await repository.TotalAsync(new DateOnly(2031, 3, 1), new DateOnly(2031, 4, 1), CancellationToken.None));
        Assert.Equal(0m, await repository.TotalAsync(new DateOnly(2031, 5, 1), new DateOnly(2031, 6, 1), CancellationToken.None));
    }

    [Fact]
    public async Task ParallelSettlesLoseNoUpdate()
    {
        var repository = Repository;
        var day = new DateOnly(2032, 1, 2);
        await Task.WhenAll(Enumerable.Range(0, 25).Select(_ =>
            repository.RecordAsync(new SpendRecord(day, LlmFeature.Ask, "p2", "m", 1, 10, 0, 1, 0.01m), CancellationToken.None)));
        Assert.Equal(0.25m, await repository.TotalAsync(day, day.AddDays(1), CancellationToken.None));
    }

    [Fact]
    public async Task TheAlertClaimHasExactlyOneWinnerPerFeatureAndMonthAndCostsNothing()
    {
        var repository = Repository;
        var month = new DateOnly(2033, 6, 1);
        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => repository.TryClaimAlertAsync(LlmFeature.Ask, month, CancellationToken.None)));
        Assert.Equal(1, results.Count(r => r));
        Assert.True(await repository.TryClaimAlertAsync(LlmFeature.Categorise, month, CancellationToken.None));
        Assert.True(await repository.TryClaimAlertAsync(LlmFeature.Ask, month.AddMonths(1), CancellationToken.None));
        Assert.Equal(0m, await repository.TotalAsync(month, month.AddMonths(2), CancellationToken.None));
    }

    // AC 5
    [Fact]
    public async Task ThePurgeKeepsThirteenMonths()
    {
        var repository = Repository;
        // now = 2026-11-20: cut-off = 2025-10-20. Older goes, the cut-off day and newer stay.
        var days = new[] { new DateOnly(2025, 10, 19), new DateOnly(2025, 10, 20), new DateOnly(2026, 1, 1), new DateOnly(2026, 11, 20) };
        foreach (var day in days)
        {
            await repository.RecordAsync(new SpendRecord(day, LlmFeature.Ask, "purge", "m", 1, 1, 0, 1, 0.01m), CancellationToken.None);
        }

        var store = new RetentionStore(fixture.Services.GetRequiredService<IZaghlolDbContextFactory>());
        Assert.True(await store.PurgeBatchAsync(RetentionRules.LlmSpendDaily, Now, 100, CancellationToken.None) >= 1);
        var left = await Db.QueryAsync(fixture.Database.Superuser, "SELECT day FROM zaghlol.llm_spend_daily WHERE provider_id = 'purge' ORDER BY 1");
        Assert.Equal(days.Skip(1), left.Select(r => (DateOnly)r[0]!));
    }

    [Fact]
    public void PricesAndModelComeFromTheProviderConfiguration()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Llm:Providers:openai:Kind"] = "OpenAiResponses",
            ["Llm:Providers:openai:Model"] = "model-a",
            ["Llm:Providers:openai:Endpoint"] = "https://llm.example.test/v1/responses",
            ["Llm:Providers:openai:PriceInPerMTok"] = "0.15",
            ["Llm:Providers:openai:PriceCachedPerMTok"] = "0.075",
            ["Llm:Providers:openai:PriceOutPerMTok"] = "0.60",
        }).Build();
        var list = new ConfiguredLlmPriceList(configuration);
        Assert.True(list.TryGet("openai", out var entry));
        Assert.Equal(("model-a", 0.15m, 0.075m, 0.60m), (entry.Model, entry.Prices.InPerMTok, entry.Prices.CachedPerMTok, entry.Prices.OutPerMTok));
        Assert.False(list.TryGet("other", out _));
    }
}
