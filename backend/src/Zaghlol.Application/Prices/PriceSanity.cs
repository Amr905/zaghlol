namespace Zaghlol.Application.Prices;

/// <summary>A provider answered, but its numbers fail the sanity bounds or its shape is wrong. The job isolates it like any failure.</summary>
public sealed class PriceProviderException(string message) : Exception(message);

/// <summary>
/// Sanity bounds for provider data (T-127). A value outside them is a feed fault (a unit mix-up, a wrong currency, a zero), so the
/// adapter throws and the cache keeps the last good value instead of serving nonsense. Defaults are wide on purpose and
/// configurable under <c>Prices:Bounds:*</c> (read in Infrastructure).
/// </summary>
public sealed record PriceBounds(decimal MinUsdPerOunce, decimal MaxUsdPerOunce, decimal MinEgpPerUsd, decimal MaxEgpPerUsd)
{
    /// <summary>Troy ounce in grams: price per gram = price per ounce / this (exact definition: 31.1034768 g).</summary>
    public const decimal GramsPerTroyOunce = 31.1034768m;

    public static PriceBounds Default { get; } = new(500m, 20_000m, 5m, 500m);

    public decimal RequireUsdPerOunce(decimal value) =>
        value >= MinUsdPerOunce && value <= MaxUsdPerOunce ? value : throw new PriceProviderException("Gold USD per ounce is outside the sanity bounds.");

    public decimal RequireEgpPerUsd(decimal value) =>
        value >= MinEgpPerUsd && value <= MaxEgpPerUsd ? value : throw new PriceProviderException("USD to EGP is outside the sanity bounds.");

    /// <summary>The 24K gram price from an ounce price, rounded to cents (away from zero).</summary>
    public static decimal GramFromOunce(decimal perOunce) =>
        decimal.Round(perOunce / GramsPerTroyOunce, PriceNormalizer.GoldDecimals, MidpointRounding.AwayFromZero);
}
