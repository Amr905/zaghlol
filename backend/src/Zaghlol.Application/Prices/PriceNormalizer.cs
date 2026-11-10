namespace Zaghlol.Application.Prices;

/// <summary>
/// Merges provider snapshots and derives what the feed lacks (FR-BE-04): a karat from any other karat of the same
/// currency (price per gram scales with purity, <c>k / 24</c>), and a USD price from the EGP price and the USD to EGP rate.
/// Invalid values (not positive, too large, unknown symbol or currency) are dropped, never stored.
/// </summary>
public static class PriceNormalizer
{
    /// <summary>Derived gold is rounded to cents.</summary>
    public const int GoldDecimals = 2;

    /// <summary>The cap that fits <c>numeric(20,6)</c> with a margin, and the 15 integer digits of the wire type.</summary>
    public const decimal MaxPrice = 999_999_999_999m;

    /// <summary>FX is kept to the wire type's 8 decimals.</summary>
    public const int FxDecimals = 8;

    public const string DerivedSuffix = "+derived";

    /// <param name="snapshots">In priority order: the first provider that supplies a (symbol, currency) or FX quote wins.</param>
    public static NormalizedPrices Normalize(IReadOnlyList<(string Source, ProviderSnapshot Snapshot)> snapshots)
    {
        ArgumentNullException.ThrowIfNull(snapshots);

        var fx = new Dictionary<string, StoredFx>(StringComparer.Ordinal);
        var gold = new Dictionary<(string Symbol, string Currency), StoredGold>();
        foreach (var (source, snapshot) in snapshots)
        {
            foreach (var quote in snapshot.Fx)
            {
                var rate = decimal.Round(quote.Rate, FxDecimals, MidpointRounding.AwayFromZero);
                if (PriceSymbols.IsCurrencyShape(quote.Quote)
                    && quote.Quote != PriceSymbols.FxBase
                    && rate > 0
                    && rate <= MaxPrice
                    && !fx.ContainsKey(quote.Quote))
                {
                    fx[quote.Quote] = new StoredFx(quote.Quote, rate, source);
                }
            }

            foreach (var quote in snapshot.Gold)
            {
                if (PriceSymbols.IsGold(quote.Symbol)
                    && PriceSymbols.IsGoldCurrency(quote.Currency)
                    && quote.Price > 0
                    && quote.Price <= MaxPrice
                    && !gold.ContainsKey((quote.Symbol, quote.Currency)))
                {
                    gold[(quote.Symbol, quote.Currency)] = new StoredGold(quote.Symbol, quote.Currency, quote.Price, source);
                }
            }
        }

        DeriveKarats(gold);
        DeriveUsd(gold, fx);
        DeriveKarats(gold);

        return new NormalizedPrices(
            gold.Values.OrderBy(g => g.Symbol, StringComparer.Ordinal).ThenBy(g => g.Currency, StringComparer.Ordinal).ToList(),
            fx.Values.OrderBy(f => f.Quote, StringComparer.Ordinal).ToList());
    }

    private static void DeriveKarats(Dictionary<(string Symbol, string Currency), StoredGold> gold)
    {
        foreach (var currency in PriceSymbols.GoldCurrencies)
        {
            // Prefer the purest karat present as the anchor: less rounding error.
            var anchor = PriceSymbols.Gold
                .Where(s => gold.ContainsKey((s, currency)))
                .OrderByDescending(s => PriceSymbols.KaratOf(s))
                .Select(s => gold[(s, currency)])
                .FirstOrDefault();
            if (anchor is null)
            {
                continue;
            }

            var anchorKarat = PriceSymbols.KaratOf(anchor.Symbol)!.Value;
            foreach (var symbol in PriceSymbols.Gold.Where(s => !gold.ContainsKey((s, currency))))
            {
                var karat = PriceSymbols.KaratOf(symbol)!.Value;
                var price = Round(anchor.Price * karat / anchorKarat);
                if (price > 0)
                {
                    gold[(symbol, currency)] = new StoredGold(symbol, currency, price, anchor.Source + DerivedSuffix);
                }
            }
        }
    }

    private static void DeriveUsd(Dictionary<(string Symbol, string Currency), StoredGold> gold, Dictionary<string, StoredFx> fx)
    {
        if (!fx.TryGetValue(PriceSymbols.Egp, out var egp))
        {
            return;
        }

        foreach (var symbol in PriceSymbols.Gold)
        {
            if (gold.ContainsKey((symbol, PriceSymbols.Usd)) || !gold.TryGetValue((symbol, PriceSymbols.Egp), out var inEgp))
            {
                continue;
            }

            var usd = Round(inEgp.Price / egp.Rate);
            if (usd > 0)
            {
                gold[(symbol, PriceSymbols.Usd)] = new StoredGold(symbol, PriceSymbols.Usd, usd, inEgp.Source + DerivedSuffix);
            }
        }
    }

    private static decimal Round(decimal value) => decimal.Round(value, GoldDecimals, MidpointRounding.AwayFromZero);
}
