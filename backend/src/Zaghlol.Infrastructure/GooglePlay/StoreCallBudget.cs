using System.Threading.RateLimiting;
using Zaghlol.Application.Purchases;

namespace Zaghlol.Infrastructure.GooglePlay;

/// <summary>
/// The shared outbound store budget (T-130 design note §2, backend-api §1): one token bucket for every lane, sized under the
/// Play Developer API daily quota. Restore may use at most 30 % of the bucket (its own bucket of that size) and is denied
/// first: it needs the shared bucket to hold more than a 30 % reserve, which only verify, ack, RTDN and support may spend.
/// Per process; a denied call is never made.
/// </summary>
internal sealed class StoreCallBudget : IStoreCallBudget, IDisposable
{
    public const double RestoreShare = 0.3;

    private readonly TokenBucketRateLimiter shared;
    private readonly TokenBucketRateLimiter restore;
    private readonly int reserve;

    public StoreCallBudget(PlayBudgetOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        shared = Bucket(options.TokenLimit, options.TokensPerPeriod, options.Period);
        restore = Bucket(
            Math.Max(1, (int)(options.TokenLimit * RestoreShare)),
            Math.Max(1, (int)(options.TokensPerPeriod * RestoreShare)),
            options.Period);
        reserve = (int)(options.TokenLimit * RestoreShare);
    }

    public bool TryAcquire(StoreLane lane)
    {
        if (lane == StoreLane.Restore)
        {
            if ((shared.GetStatistics()?.CurrentAvailablePermits ?? 0) <= reserve)
            {
                return false;
            }

            using var restoreLease = restore.AttemptAcquire();
            if (!restoreLease.IsAcquired)
            {
                return false;
            }
        }

        using var lease = shared.AttemptAcquire();
        return lease.IsAcquired;
    }

    public void Dispose()
    {
        shared.Dispose();
        restore.Dispose();
    }

    private static TokenBucketRateLimiter Bucket(int limit, int perPeriod, TimeSpan period) => new(new TokenBucketRateLimiterOptions
    {
        TokenLimit = limit,
        TokensPerPeriod = perPeriod,
        ReplenishmentPeriod = period,
        QueueLimit = 0,
        AutoReplenishment = true,
    });
}
