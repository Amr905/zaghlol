namespace Zaghlol.Application.Prices;

/// <summary>A gold price per gram in <see cref="Currency"/>.</summary>
public sealed record GoldQuote(string Symbol, string Currency, decimal Price);

/// <summary>One FX rate: 1 unit of <see cref="PriceSymbols.FxBase"/> buys <see cref="Rate"/> units of <see cref="Quote"/>.</summary>
public sealed record FxQuote(string Quote, decimal Rate);

/// <summary>What a provider returned for one fetch. Either list may be empty (a gold-only or FX-only provider).</summary>
public sealed record ProviderSnapshot(IReadOnlyList<GoldQuote> Gold, IReadOnlyList<FxQuote> Fx, DateTimeOffset AsOf);

/// <summary>A source of prices (ADR-014). Implementations throw on any failure; the job isolates it.</summary>
public interface IPriceProvider
{
    /// <summary>A fixed word from <see cref="PriceProviderNames"/>: it becomes a metric tag.</summary>
    string Name { get; }

    Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken);
}

/// <summary>The provider names (a fixed value set, also the <c>source</c> column and the metric tag).</summary>
public static class PriceProviderNames
{
    public const string Fake = "fake";
    public const string LocalGold = "local_gold";
    public const string Fx = "fx";
    public const string SpotGold = "spot_gold";

    /// <summary>Metric tag for a run in which no provider is configured.</summary>
    public const string None = "none";

    public static IReadOnlyList<string> Known { get; } = [Fake, LocalGold, Fx, SpotGold];
}

/// <summary>Fetch outcomes, a fixed value set for the metric tag.</summary>
public static class PriceFetchOutcomes
{
    public const string Ok = "ok";
    public const string Failed = "failed";
    public const string Empty = "empty";
}

/// <summary>A normalized gold quote ready to store.</summary>
public sealed record StoredGold(string Symbol, string Currency, decimal Price, string Source);

/// <summary>The result of merging providers: the gold quotes (derived ones included) and the FX rates with their source.</summary>
public sealed record NormalizedPrices(IReadOnlyList<StoredGold> Gold, IReadOnlyList<StoredFx> Fx);

public sealed record StoredFx(string Quote, decimal Rate, string Source);

/// <summary>A <c>price_quotes</c> row as the service sees it.</summary>
public sealed record PriceRow(
    string Symbol,
    string Currency,
    decimal Price,
    DateTimeOffset AsOf,
    string Source,
    bool IsOverride,
    DateTimeOffset? OverrideExpiresAt,
    decimal? FeedPrice,
    DateTimeOffset? FeedAsOf)
{
    /// <summary>True while an operator override is in force at <paramref name="now"/>.</summary>
    public bool OverrideActive(DateTimeOffset now) => IsOverride && OverrideExpiresAt is { } expires && expires > now;

    /// <summary>
    /// The value to serve at <paramref name="now"/>: an unexpired override; otherwise the last feed value (a row written
    /// before <c>feed_price</c> existed is a feed value itself unless it is an override). <c>null</c> when an override has expired
    /// on a quote the feed never supplied.
    /// </summary>
    public EffectivePrice? Effective(DateTimeOffset now)
    {
        if (OverrideActive(now))
        {
            return new EffectivePrice(Symbol, Currency, Price, AsOf, FromOverride: true);
        }

        if (FeedPrice is { } feed && FeedAsOf is { } feedAsOf)
        {
            return new EffectivePrice(Symbol, Currency, feed, feedAsOf, FromOverride: false);
        }

        return IsOverride ? null : new EffectivePrice(Symbol, Currency, Price, AsOf, FromOverride: false);
    }
}

public sealed record EffectivePrice(string Symbol, string Currency, decimal Price, DateTimeOffset AsOf, bool FromOverride);

/// <summary>An FX row.</summary>
public sealed record FxRow(string Quote, decimal Rate, DateTimeOffset AsOf, string Source);

/// <summary>The <c>prices</c> block of the sync response (T-128 signs and sends it).</summary>
public sealed record PricesBlock(
    DateTimeOffset AsOf,
    bool Stale,
    IReadOnlyList<GoldQuote> Gold,
    string FxBaseCurrency,
    IReadOnlyList<FxQuote> Fx);
