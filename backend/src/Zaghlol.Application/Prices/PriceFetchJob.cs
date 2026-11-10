namespace Zaghlol.Application.Prices;

/// <summary>
/// One run of the hourly price fetch (ADR-014): ask each provider in priority order, isolate failures, normalize, and update the
/// cache. When nothing at all came back the cache is left alone, so an outage serves the last value (and turns stale after 24 h).
/// </summary>
public sealed class PriceFetchJob(
    IEnumerable<IPriceProvider> providers,
    IPriceFeedStore store,
    IPriceMetrics metrics,
    TimeProvider clock)
{
    private readonly IReadOnlyList<IPriceProvider> configured = providers.ToList();

    /// <summary>Returns the number of gold and FX quotes written.</summary>
    public async Task<int> RunOnceAsync(CancellationToken cancellationToken)
    {
        var written = await FetchAsync(cancellationToken);
        await ReportAgesAsync(cancellationToken);
        return written;
    }

    private async Task<int> FetchAsync(CancellationToken cancellationToken)
    {
        if (configured.Count == 0)
        {
            metrics.Fetched(PriceProviderNames.None, PriceFetchOutcomes.Empty);
            return 0;
        }

        var snapshots = new List<(string, ProviderSnapshot)>();
        foreach (var provider in configured)
        {
            try
            {
                var snapshot = await provider.FetchAsync(cancellationToken);
                var empty = snapshot.Gold.Count == 0 && snapshot.Fx.Count == 0;
                metrics.Fetched(provider.Name, empty ? PriceFetchOutcomes.Empty : PriceFetchOutcomes.Ok);
                if (!empty)
                {
                    snapshots.Add((provider.Name, snapshot));
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
#pragma warning disable CA1031 // A provider failure of any kind is isolated: the other providers and the cache are unaffected.
            catch (Exception)
#pragma warning restore CA1031
            {
                metrics.Fetched(provider.Name, PriceFetchOutcomes.Failed);
            }
        }

        var normalized = PriceNormalizer.Normalize(snapshots);
        if (normalized.Gold.Count + normalized.Fx.Count == 0)
        {
            return 0;
        }

        await store.ApplyFeedAsync(normalized, clock.GetUtcNow(), cancellationToken);
        return normalized.Gold.Count + normalized.Fx.Count;
    }

    private async Task ReportAgesAsync(CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        foreach (var (symbol, asOf) in await store.FeedTimesAsync(cancellationToken))
        {
            metrics.SetAge(symbol, now - asOf);
        }
    }
}
