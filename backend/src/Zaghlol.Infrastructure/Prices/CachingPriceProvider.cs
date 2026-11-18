using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>
/// Wraps a provider so it is called at most once per <paramref name="ttl"/> (the task's update interval), however often the job
/// runs (restarts, manual runs). That protects a metered API quota. A failure is not cached: the next run tries again, and the
/// job's own rule keeps the last good stored value meanwhile.
/// </summary>
public sealed class CachingPriceProvider(IPriceProvider inner, TimeSpan ttl, TimeProvider clock) : IPriceProvider, IDisposable
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private ProviderSnapshot? cached;
    private DateTimeOffset fetchedAt;

    public string Name => inner.Name;

    public void Dispose() => gate.Dispose();

    public async Task<ProviderSnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var now = clock.GetUtcNow();
            if (cached is not null && now - fetchedAt < ttl)
            {
                return cached;
            }

            cached = await inner.FetchAsync(cancellationToken).ConfigureAwait(false);
            fetchedAt = now;
            return cached;
        }
        finally
        {
            gate.Release();
        }
    }
}
