using Zaghlol.Application.Prices;

namespace Zaghlol.Application.Tests.Prices;

/// <summary>A clock the test moves by hand.</summary>
internal sealed class TestClock(DateTimeOffset start) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = start;

    public override DateTimeOffset GetUtcNow() => Now;
}

internal sealed class StubProvider(string name, Func<ProviderSnapshot> fetch) : IPriceProvider
{
    public string Name => name;

    public Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken) => Task.FromResult(fetch());
}

internal sealed class RecordingMetrics : IPriceMetrics
{
    public List<(string Provider, string Outcome)> Fetches { get; } = [];

    public Dictionary<string, TimeSpan> Ages { get; } = [];

    public void Fetched(string provider, string outcome) => Fetches.Add((provider, outcome));

    public void SetAge(string symbol, TimeSpan age) => Ages[symbol] = age;
}

/// <summary>An in-memory cache that follows the same upsert rules as the SQL (feed never overwrites an active override).</summary>
internal sealed class MemoryPriceStore : IPriceFeedStore, IPriceAdminStore, IPriceReader
{
    public Dictionary<(string Symbol, string Currency), PriceRow> Rows { get; } = [];

    public Dictionary<string, FxRow> Fx { get; } = [];

    public int Applies { get; private set; }

    public List<(string Action, Guid Operator)> Audit { get; } = [];

    public Task ApplyFeedAsync(NormalizedPrices prices, DateTimeOffset now, CancellationToken cancellationToken)
    {
        Applies++;
        foreach (var g in prices.Gold)
        {
            var key = (g.Symbol, g.Currency);
            if (Rows.TryGetValue(key, out var existing) && existing.OverrideActive(now))
            {
                Rows[key] = existing with { FeedPrice = g.Price, FeedAsOf = now };
            }
            else
            {
                Rows[key] = new PriceRow(g.Symbol, g.Currency, g.Price, now, g.Source, false, null, g.Price, now);
            }
        }

        foreach (var f in prices.Fx)
        {
            Fx[f.Quote] = new FxRow(f.Quote, f.Rate, now, f.Source);
        }

        return Task.CompletedTask;
    }

    public Task<IReadOnlyDictionary<string, DateTimeOffset>> FeedTimesAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyDictionary<string, DateTimeOffset>>(
            Rows.Values.Where(r => r.Currency == PriceSymbols.Egp && r.FeedAsOf is not null).ToDictionary(r => r.Symbol, r => r.FeedAsOf!.Value));

    public Task<PriceRow> SetOverrideAsync(
        string symbol,
        string currency,
        decimal price,
        string reason,
        DateTimeOffset now,
        DateTimeOffset expiresAt,
        Guid operatorId,
        CancellationToken cancellationToken)
    {
        Rows.TryGetValue((symbol, currency), out var existing);
        var row = new PriceRow(symbol, currency, price, now, "override", true, expiresAt, existing?.FeedPrice, existing?.FeedAsOf);
        Rows[(symbol, currency)] = row;
        Audit.Add(("price_override", operatorId));
        return Task.FromResult(row);
    }

    public Task<bool> ClearOverrideAsync(string symbol, string currency, DateTimeOffset now, Guid operatorId, CancellationToken cancellationToken)
    {
        if (Rows.TryGetValue((symbol, currency), out var row) && row.OverrideActive(now))
        {
            Rows[(symbol, currency)] = row with { OverrideExpiresAt = now };
            Audit.Add(("price_override_clear", operatorId));
            return Task.FromResult(true);
        }

        return Task.FromResult(false);
    }

    public Task<IReadOnlyList<PriceRow>> ListGoldAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<PriceRow>>(Rows.Values.ToList());

    public Task<IReadOnlyList<FxRow>> ListFxAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<FxRow>>(Fx.Values.ToList());
}
