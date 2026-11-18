using System.Globalization;
using System.Text.Json;
using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>
/// MetalpriceAPI adapter (<c>Prices:Providers = metalpriceapi</c>). One call, <c>GET /v1/latest?base=USD&amp;currencies=XAU,EGP,...</c>
/// with the key in <c>api_key</c>. It gives only spot, so this adapter derives the gram prices:
/// <list type="bullet">
/// <item>USD per troy ounce = <c>rates.USDXAU</c>, or 1 / <c>rates.XAU</c> when only the inverse is present;</item>
/// <item>24K USD per gram = USD per ounce / 31.1034768; 24K EGP per gram = that x <c>rates.EGP</c>;</item>
/// <item>21K and 18K are derived from 24K by the normalizer: price(k) = price(24K) x k / 24 (purity 21/24 and 18/24).</item>
/// </list>
/// Rounding is to cents, away from zero; everything is <see cref="decimal"/>. The result is spot-based: it carries no Egyptian
/// retail premium (see docs/03-technical/gold-price-providers.md). Out-of-bounds values throw.
/// </summary>
public sealed class MetalpriceApiProvider(HttpClient client, string apiKey, PriceBounds bounds, IReadOnlyList<string> fxCurrencies, TimeProvider clock) : IPriceProvider
{
    public const string HttpClientName = "zaghlol-price-metalpriceapi";

    public string Name => PriceProviderNames.MetalpriceApi;

    public async Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        var currencies = string.Join(',', new[] { "XAU", PriceSymbols.Egp }.Concat(fxCurrencies).Distinct(StringComparer.Ordinal));
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            string.Create(CultureInfo.InvariantCulture, $"v1/latest?api_key={Uri.EscapeDataString(apiKey)}&base=USD&currencies={currencies}"));
        request.Headers.Add("Accept", "application/json");
        using var document = await PriceHttp.GetJsonAsync(client, request, cancellationToken).ConfigureAwait(false);
        var root = document.RootElement;
        if (!root.TryGetProperty("success", out var ok) || ok.ValueKind != JsonValueKind.True
            || !root.TryGetProperty("rates", out var rates) || rates.ValueKind != JsonValueKind.Object)
        {
            throw new PriceProviderException("The price provider response is not a success.");
        }

        var usdPerOunce = PriceHttp.Decimal(rates, "USDXAU") is { } direct && direct > 0
            ? direct
            : 1m / PriceHttp.Require(rates, "XAU");
        bounds.RequireUsdPerOunce(usdPerOunce);
        var usdEgp = bounds.RequireEgpPerUsd(PriceHttp.Require(rates, PriceSymbols.Egp));

        var usdGram = PriceBounds.GramFromOunce(usdPerOunce);
        var egpGram = decimal.Round(usdPerOunce / PriceBounds.GramsPerTroyOunce * usdEgp, PriceNormalizer.GoldDecimals, MidpointRounding.AwayFromZero);
        var fx = new List<FxQuote> { new(PriceSymbols.Egp, usdEgp) };
        foreach (var code in fxCurrencies.Where(c => c != PriceSymbols.Egp && c != PriceSymbols.Usd))
        {
            if (PriceHttp.Decimal(rates, code) is { } rate && rate > 0)
            {
                fx.Add(new FxQuote(code, rate));
            }
        }

        return new ProviderSnapshot(
            [new GoldQuote(PriceSymbols.Gold24, PriceSymbols.Usd, usdGram), new GoldQuote(PriceSymbols.Gold24, PriceSymbols.Egp, egpGram)],
            fx,
            PriceHttp.UnixSeconds(root, "timestamp", clock.GetUtcNow()));
    }
}
