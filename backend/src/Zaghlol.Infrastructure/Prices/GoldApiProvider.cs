using System.Text.Json;
using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>
/// GoldAPI.io adapter (<c>Prices:Providers = goldapi</c>). Two calls per fetch, <c>GET /api/XAU/EGP</c> and <c>/api/XAU/USD</c>,
/// with the key in the <c>x-access-token</c> header. Each answer carries the ounce price (<c>price</c>) and per-gram prices by karat
/// (<c>price_gram_24k</c>, <c>_21k</c>, <c>_18k</c>); a missing karat is derived by the normalizer. USD to EGP is the ratio of the two
/// ounce prices, so no third call is needed. The 24K gram falls back to <c>price</c> / 31.1034768 when the field is absent. All math
/// is <see cref="decimal"/>. Out-of-bounds values throw, so the cache keeps the last good value.
/// </summary>
public sealed class GoldApiProvider(HttpClient client, string apiKey, PriceBounds bounds, TimeProvider clock) : IPriceProvider
{
    public const string HttpClientName = "zaghlol-price-goldapi";

    /// <summary>Largest accepted relative gap between a vendor per-karat gram price and the ounce-derived value.</summary>
    public const decimal GramTolerance = 0.05m;

    public string Name => PriceProviderNames.GoldApi;

    public async Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        var (egpOunce, egp, egpAt) = await ReadAsync(PriceSymbols.Egp, cancellationToken).ConfigureAwait(false);
        var (usdOunce, usd, usdAt) = await ReadAsync(PriceSymbols.Usd, cancellationToken).ConfigureAwait(false);

        bounds.RequireUsdPerOunce(usdOunce);
        var usdEgp = bounds.RequireEgpPerUsd(decimal.Round(egpOunce / usdOunce, PriceNormalizer.FxDecimals, MidpointRounding.AwayFromZero));
        var gold = new List<GoldQuote>();
        gold.AddRange(egp);
        gold.AddRange(usd);
        var asOf = egpAt < usdAt ? egpAt : usdAt;
        return new ProviderSnapshot(gold, [new FxQuote(PriceSymbols.Egp, usdEgp)], asOf);
    }

    private async Task<(decimal Ounce, List<GoldQuote> Gold, DateTimeOffset At)> ReadAsync(string currency, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"api/XAU/{currency}");
        request.Headers.Add("x-access-token", apiKey);
        request.Headers.Add("Accept", "application/json");
        using var document = await PriceHttp.GetJsonAsync(client, request, cancellationToken).ConfigureAwait(false);
        var root = document.RootElement;
        var ounce = PriceHttp.Require(root, "price");
        var quotes = new List<GoldQuote>();
        var gram24 = PriceBounds.GramFromOunce(ounce);
        foreach (var (symbol, field, karat) in new[] { (PriceSymbols.Gold24, "price_gram_24k", 24m), (PriceSymbols.Gold21, "price_gram_21k", 21m), (PriceSymbols.Gold18, "price_gram_18k", 18m) })
        {
            if (PriceHttp.Decimal(root, field) is { } gram && gram > 0)
            {
                // Consistency check (FU-259): a vendor karat price far from the ounce-derived value is a feed fault.
                var expected = gram24 * karat / 24m;
                if (Math.Abs(gram - expected) > expected * GramTolerance)
                {
                    throw new PriceProviderException($"GoldAPI {field} for {currency} disagrees with the ounce price by more than {GramTolerance:P0}.");
                }

                quotes.Add(new GoldQuote(symbol, currency, decimal.Round(gram, PriceNormalizer.GoldDecimals, MidpointRounding.AwayFromZero)));
            }
        }

        if (!quotes.Any(q => q.Symbol == PriceSymbols.Gold24))
        {
            quotes.Add(new GoldQuote(PriceSymbols.Gold24, currency, PriceBounds.GramFromOunce(ounce)));
        }

        return (ounce, quotes, PriceHttp.UnixSeconds(root, "timestamp", clock.GetUtcNow()));
    }
}
