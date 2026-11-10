namespace Zaghlol.Application.Prices;

/// <summary>The worker's view of the price cache (Worker login).</summary>
public interface IPriceFeedStore
{
    /// <summary>
    /// Writes the feed values: always <c>feed_price/feed_as_of</c>, and <c>price/as_of/source</c> only where no unexpired override is
    /// in force at <paramref name="now"/> (an override is never overwritten by the feed).
    /// </summary>
    Task ApplyFeedAsync(NormalizedPrices prices, DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>The time of the last feed value per gold symbol (EGP rows), for the price-age gauge.</summary>
    Task<IReadOnlyDictionary<string, DateTimeOffset>> FeedTimesAsync(CancellationToken cancellationToken);
}

/// <summary>Reads the cache with the App login, for the sync response.</summary>
public interface IPriceReader
{
    Task<IReadOnlyList<PriceRow>> ListGoldAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<FxRow>> ListFxAsync(CancellationToken cancellationToken);
}

/// <summary>Operator override writes (Admin login): the row and exactly one audit row, in one transaction.</summary>
public interface IPriceAdminStore
{
    /// <summary>Sets the override and returns the stored row.</summary>
    Task<PriceRow> SetOverrideAsync(
        string symbol,
        string currency,
        decimal price,
        string reason,
        DateTimeOffset now,
        DateTimeOffset expiresAt,
        Guid operatorId,
        CancellationToken cancellationToken);

    /// <summary>Ends an override now; the feed value serves again. <c>false</c> when there was no active override.</summary>
    Task<bool> ClearOverrideAsync(string symbol, string currency, DateTimeOffset now, Guid operatorId, CancellationToken cancellationToken);
}

/// <summary>Counters the job reports; the Infrastructure adapter maps them onto the Zaghlol meter with fixed tag values.</summary>
public interface IPriceMetrics
{
    void Fetched(string provider, string outcome);

    void SetAge(string symbol, TimeSpan age);
}
