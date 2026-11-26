using System.Diagnostics.Metrics;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Llm.Spend;

/// <summary><c>llm_spend_daily</c> through raw SQL on the App login (grant: SELECT, INSERT, UPDATE; no delete).</summary>
internal sealed class SpendLedgerRepository([FromKeyedServices(DatabaseRole.App)] NpgsqlDataSource source) : ISpendLedgerStore
{
    internal const string UpsertSql = """
        INSERT INTO zaghlol.llm_spend_daily AS d (day, feature, provider_id, model, calls, input_tokens, cached_tokens, output_tokens, cost_usd)
        VALUES (@day, @f, @p, @m, @calls, @in, @cached, @out, @cost)
        ON CONFLICT (day, feature, provider_id, model) DO UPDATE
          SET calls = d.calls + EXCLUDED.calls,
              input_tokens = d.input_tokens + EXCLUDED.input_tokens,
              cached_tokens = d.cached_tokens + EXCLUDED.cached_tokens,
              output_tokens = d.output_tokens + EXCLUDED.output_tokens,
              cost_usd = d.cost_usd + EXCLUDED.cost_usd
        """;

    internal const string TotalSql = "SELECT COALESCE(SUM(cost_usd), 0) FROM zaghlol.llm_spend_daily WHERE day >= @from AND day < @to";

    internal const string ClaimSql = """
        INSERT INTO zaghlol.llm_spend_daily (day, feature, provider_id, model, calls, input_tokens, cached_tokens, output_tokens, cost_usd)
        VALUES (@day, @f, @p, '-', 0, 0, 0, 0, 0)
        ON CONFLICT (day, feature, provider_id, model) DO NOTHING
        """;

    public async Task RecordAsync(SpendRecord record, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(record);
        await using var command = source.CreateCommand(UpsertSql);
        command.Parameters.Add(new("day", NpgsqlDbType.Date) { Value = record.Day });
        command.Parameters.Add(new("f", NpgsqlDbType.Text) { Value = Quota.LlmQuotaRepository.FeatureText(record.Feature) });
        command.Parameters.Add(new("p", NpgsqlDbType.Text) { Value = record.ProviderId });
        command.Parameters.Add(new("m", NpgsqlDbType.Text) { Value = record.Model });
        command.Parameters.Add(new("calls", NpgsqlDbType.Integer) { Value = record.Calls });
        command.Parameters.Add(new("in", NpgsqlDbType.Bigint) { Value = record.InputTokens });
        command.Parameters.Add(new("cached", NpgsqlDbType.Bigint) { Value = record.CachedTokens });
        command.Parameters.Add(new("out", NpgsqlDbType.Bigint) { Value = record.OutputTokens });
        command.Parameters.Add(new("cost", NpgsqlDbType.Numeric) { Value = record.CostUsd });
        _ = await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<decimal> TotalAsync(DateOnly fromInclusive, DateOnly untilExclusive, CancellationToken cancellationToken)
    {
        await using var command = source.CreateCommand(TotalSql);
        command.Parameters.Add(new("from", NpgsqlDbType.Date) { Value = fromInclusive });
        command.Parameters.Add(new("to", NpgsqlDbType.Date) { Value = untilExclusive });
        var value = await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false);
        return value is decimal d ? d : throw new InvalidOperationException("The spend total is not a decimal.");
    }

    public async Task<bool> TryClaimAlertAsync(LlmFeature feature, DateOnly monthStart, CancellationToken cancellationToken)
    {
        await using var command = source.CreateCommand(ClaimSql);
        command.Parameters.Add(new("day", NpgsqlDbType.Date) { Value = monthStart });
        command.Parameters.Add(new("f", NpgsqlDbType.Text) { Value = Quota.LlmQuotaRepository.FeatureText(feature) });
        command.Parameters.Add(new("p", NpgsqlDbType.Text) { Value = SpendLedgerMarkers.AlertProvider });
        return await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false) > 0;
    }
}

/// <summary>Model and prices from <c>Llm:Providers:&lt;id&gt;</c> (read once; the same section the adapters use).</summary>
internal sealed class ConfiguredLlmPriceList : ILlmPriceList
{
    private readonly Dictionary<string, LlmPriceEntry> entries;

    public ConfiguredLlmPriceList(IConfiguration configuration)
    {
        entries = LlmProviderOptions.ReadAll(configuration).ToDictionary(
            p => p.Id,
            p => new LlmPriceEntry(p.Model, new LlmPrices(p.PriceInPerMTok, p.PriceCachedPerMTok, p.PriceOutPerMTok)),
            StringComparer.Ordinal);
    }

    public bool TryGet(string providerId, out LlmPriceEntry entry) =>
        entries.TryGetValue(providerId, out entry!);
}

/// <summary>
/// The LLM counters on the shared Zaghlol meter. Tags: <c>feature</c> (ask|cat), <c>provider</c> (id pattern), <c>outcome</c>,
/// <c>plan</c> (PL-NAME pattern), <c>reason</c> and <c>bucket</c> (lower-case codes, else <c>other</c>). Cost is a decimal counter.
/// </summary>
internal sealed partial class LlmMetrics : ILlmMetrics, IDisposable
{
    private readonly Meter meter = new(ZaghlolMetrics.MeterName);
    private readonly Counter<long> requests;
    private readonly Counter<long> plans;
    private readonly Counter<long> fallbacks;
    private readonly Counter<long> refusals;
    private readonly Counter<long> validation;
    private readonly Counter<long> limited;
    private readonly Counter<long> quota;
    private readonly Counter<long> paused;
    private readonly Counter<long> tokens;
    private readonly Counter<decimal> cost;
    private readonly Histogram<double> latency;

    public LlmMetrics()
    {
        requests = meter.CreateCounter<long>("zaghlol.llm.requests", description: "Provider calls by feature, provider and outcome.");
        plans = meter.CreateCounter<long>("zaghlol.llm.plans", description: "Valid plans by name.");
        fallbacks = meter.CreateCounter<long>("zaghlol.llm.fallbacks", description: "Fallback answers.");
        refusals = meter.CreateCounter<long>("zaghlol.llm.refusals", description: "Refusals by reason code.");
        validation = meter.CreateCounter<long>("zaghlol.llm.validation_failures", description: "Plan validation failures by reason code.");
        limited = meter.CreateCounter<long>("zaghlol.llm.rate_limited", description: "429 answers by bucket.");
        quota = meter.CreateCounter<long>("zaghlol.llm.quota_hits", description: "Calls refused at the quota.");
        paused = meter.CreateCounter<long>("zaghlol.llm.paused", description: "Calls refused by the spend guard, by reason.");
        tokens = meter.CreateCounter<long>("zaghlol.llm.tokens", description: "Provider tokens by feature, provider and kind (reason tag: input, cached, output).");
        cost = meter.CreateCounter<decimal>("zaghlol.llm.cost_usd", description: "Provider cost in USD (decimal) by feature and provider.");
        latency = meter.CreateHistogram<double>("zaghlol.llm.latency", "ms", "Provider call latency (p50 and p95 come from the histogram).");
    }

    public void ProviderCall(LlmFeature feature, string providerId, LlmOutcome outcome, TimeSpan elapsed, LlmUsage usage, decimal costUsd)
    {
        ArgumentNullException.ThrowIfNull(usage);
        var f = Feature(feature);
        var p = Provider(providerId);
        requests.Add(1, Tag(LlmMetricTags.Feature, f), Tag(LlmMetricTags.Provider, p), Tag(LlmMetricTags.Outcome, outcome.ToString().ToLowerInvariant()));
        tokens.Add(usage.InputTokens - usage.CachedTokens, Tag(LlmMetricTags.Feature, f), Tag(LlmMetricTags.Provider, p), Tag(LlmMetricTags.Reason, "input"));
        tokens.Add(usage.CachedTokens, Tag(LlmMetricTags.Feature, f), Tag(LlmMetricTags.Provider, p), Tag(LlmMetricTags.Reason, "cached"));
        tokens.Add(usage.OutputTokens, Tag(LlmMetricTags.Feature, f), Tag(LlmMetricTags.Provider, p), Tag(LlmMetricTags.Reason, "output"));
        cost.Add(costUsd, Tag(LlmMetricTags.Feature, f), Tag(LlmMetricTags.Provider, p));
        latency.Record(elapsed.TotalMilliseconds, Tag(LlmMetricTags.Feature, f), Tag(LlmMetricTags.Provider, p));
    }

    public void Plan(LlmFeature feature, string planName) =>
        plans.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)), Tag(LlmMetricTags.Plan, PlanPattern().IsMatch(planName ?? string.Empty) ? planName! : "other"));

    public void Fallback(LlmFeature feature) => fallbacks.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)));

    public void Refusal(LlmFeature feature, string reason) =>
        refusals.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)), Tag(LlmMetricTags.Reason, Code(reason)));

    public void ValidationFailure(LlmFeature feature, string reason) =>
        validation.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)), Tag(LlmMetricTags.Reason, Code(reason)));

    public void RateLimited(LlmFeature feature, string bucket) =>
        limited.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)), Tag(LlmMetricTags.Bucket, Code(bucket)));

    public void QuotaHit(LlmFeature feature) => quota.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)));

    public void Paused(LlmFeature feature, string reason) =>
        paused.Add(1, Tag(LlmMetricTags.Feature, Feature(feature)), Tag(LlmMetricTags.Reason, Code(reason)));

    public void Dispose() => meter.Dispose();

    private static KeyValuePair<string, object?> Tag(string key, string value) => new(key, value);

    private static string Feature(LlmFeature feature) => feature == LlmFeature.Ask ? "ask" : "cat";

    private static string Provider(string id) => id is { Length: > 0 } && ProviderPattern().IsMatch(id) ? id : "other";

    private static string Code(string value) => value is { Length: > 0 } && CodePattern().IsMatch(value) ? value : "other";

    [GeneratedRegex(@"^PL-[A-Z]{2,16}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex PlanPattern();

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{0,31}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex ProviderPattern();

    [GeneratedRegex(@"^[a-z][a-z0-9_]{0,39}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex CodePattern();
}

public static class LlmSpendServiceCollectionExtensions
{
    /// <summary>
    /// The spend ledger, the cap guard and the LLM metrics (T-339). Call after <c>AddZaghlolDatabase</c> with the App role,
    /// <c>AddZaghlolRemoteConfig</c> and <c>AddZaghlolFlagAdmin</c> or any other registration of <see cref="Zaghlol.Application.Flags.IOpsAlertSink"/>.
    /// Not called by the API host yet (T-349 wires it).
    /// </summary>
    public static IServiceCollection AddZaghlolLlmSpend(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ISpendLedgerStore, SpendLedgerRepository>();
        services.TryAddSingleton<ILlmPriceList>(p => new ConfiguredLlmPriceList(p.GetRequiredService<IConfiguration>()));
        services.TryAddSingleton<ILlmMetrics, LlmMetrics>();
        services.TryAddSingleton<ISpendGuard>(p => new SpendGuard(
            p.GetRequiredService<ISpendLedgerStore>(),
            p.GetRequiredService<Zaghlol.Application.Config.IRemoteConfigService>(),
            p.GetRequiredService<ILlmPriceList>(),
            p.GetRequiredService<Zaghlol.Application.Flags.IOpsAlertSink>(),
            p.GetRequiredService<ILlmMetrics>(),
            p.GetRequiredService<TimeProvider>(),
            p.GetRequiredService<ILogger<SpendGuard>>()));
        return services;
    }
}
