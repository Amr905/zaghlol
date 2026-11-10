using System.Globalization;
using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>
/// A deterministic stand-in for the contracted providers (D-41 is open, BLK-03): 24K gold in EGP and a few FX rates, so the
/// normalizer derives the other karats and USD prices. Selected with <c>Prices:Providers = fake</c>; refused in Production.
/// Values come from <c>Prices:Fake:*</c> so a staging run can move them.
/// </summary>
public sealed class FakePriceProvider(IConfiguration configuration, TimeProvider clock) : IPriceProvider
{
    public string Name => PriceProviderNames.Fake;

    public Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        var section = configuration.GetSection("Prices:Fake");
        var gold24 = Read(section["Gold24Egp"], 4820.00m);
        var fx = new List<FxQuote>
        {
            new("EGP", Read(section["UsdEgp"], 48.95m)),
            new("SAR", 3.75m),
            new("EUR", 0.9210m),
            new("GBP", 0.7840m),
            new("KWD", 0.3070m),
        };
        return Task.FromResult(new ProviderSnapshot([new GoldQuote(PriceSymbols.Gold24, PriceSymbols.Egp, gold24)], fx, clock.GetUtcNow()));
    }

    private static decimal Read(string? text, decimal fallback) =>
        decimal.TryParse(text, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value) ? value : fallback;
}
