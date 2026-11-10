namespace Zaghlol.Application.Prices;

/// <summary>Builds the sync response's <c>prices</c> block from the cache (T-128 sends it).</summary>
public sealed class PriceReadService(IPriceReader reader, TimeProvider clock)
{
    /// <summary>A feed older than this is flagged stale (ADR-014, FR-BE-04).</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromHours(24);

    /// <summary>The block, or <c>null</c> when there is nothing to serve yet.</summary>
    public async Task<PricesBlock?> GetBlockAsync(CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var rows = await reader.ListGoldAsync(cancellationToken);
        var fxRows = await reader.ListFxAsync(cancellationToken);
        return Build(rows, fxRows, now);
    }

    public static PricesBlock? Build(IReadOnlyList<PriceRow> rows, IReadOnlyList<FxRow> fxRows, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(rows);
        ArgumentNullException.ThrowIfNull(fxRows);

        var gold = rows
            .Select(r => r.Effective(now))
            .OfType<EffectivePrice>()
            .OrderBy(p => p.Symbol, StringComparer.Ordinal)
            .ThenBy(p => p.Currency, StringComparer.Ordinal)
            .ToList();

        // Staleness is about the feed, not about an operator override that papers over an outage: the newest feed time.
        var feedTimes = rows
            .Select(r => r.FeedAsOf ?? (r.IsOverride ? null : (DateTimeOffset?)r.AsOf))
            .Concat(fxRows.Select(f => (DateTimeOffset?)f.AsOf))
            .OfType<DateTimeOffset>()
            .ToList();
        if (gold.Count == 0 && fxRows.Count == 0)
        {
            return null;
        }

        var asOf = feedTimes.Count > 0 ? feedTimes.Max() : gold.Max(p => p.AsOf);
        var stale = feedTimes.Count == 0 || now - asOf > StaleAfter;
        return new PricesBlock(
            asOf,
            stale,
            gold.Select(p => new GoldQuote(p.Symbol, p.Currency, p.Price)).ToList(),
            PriceSymbols.FxBase,
            fxRows.OrderBy(f => f.Quote, StringComparer.Ordinal).Select(f => new FxQuote(f.Quote, f.Rate)).ToList());
    }
}
