using System.Threading.RateLimiting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>
/// The Apple outbound budget (T-131 design note §6, FU-077 M-2 applied from the start), separate from Play's. One token bucket per
/// process, sized <c>1 / Replicas</c> of the configured total, charged once per HTTP <b>attempt</b> (retries included, by
/// <see cref="AppleBudgetHandler"/> inside the retry). Lanes:
/// <list type="bullet">
/// <item>store notifications (<see cref="StoreLane.Rtdn"/>, T-134) may spend the whole bucket;</item>
/// <item>verify, support and anything else stop while only the 20 % notification reserve is left;</item>
/// <item>restore is denied first: it stops while only the notification reserve plus a 30 % reserve is left, and it may take at
/// most 30 % of the bucket through its own sub-bucket.</item>
/// </list>
/// A denied attempt is never sent.
/// </summary>
public sealed class AppleCallBudget : IStoreCallBudget, IDisposable
{
    public const double NotificationReserveShare = 0.2;
    public const double RestoreShare = 0.3;

    private readonly TokenBucketRateLimiter shared;
    private readonly TokenBucketRateLimiter restore;
    private readonly int notificationReserve;
    private readonly int restoreReserve;

    public AppleCallBudget(AppleBudgetOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var limit = options.PerReplicaLimit;
        var perPeriod = options.PerReplicaPerPeriod;
        shared = Bucket(limit, perPeriod, options.Period);
        restore = Bucket(Math.Max(1, (int)(limit * RestoreShare)), Math.Max(1, (int)(perPeriod * RestoreShare)), options.Period);
        notificationReserve = (int)(limit * NotificationReserveShare);
        restoreReserve = notificationReserve + (int)(limit * RestoreShare);
    }

    public bool TryAcquire(StoreLane lane)
    {
        var available = shared.GetStatistics()?.CurrentAvailablePermits ?? 0;
        switch (lane)
        {
            case StoreLane.Rtdn:
                break;
            case StoreLane.Restore:
                if (available <= restoreReserve)
                {
                    return false;
                }

                using (var restoreLease = restore.AttemptAcquire())
                {
                    if (!restoreLease.IsAcquired)
                    {
                        return false;
                    }
                }

                break;
            default:
                if (available <= notificationReserve)
                {
                    return false;
                }

                break;
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

/// <summary>
/// The verify per-install limit (FU-077 M-2): <c>VerifyPerInstallPerHour</c> verifies that reach Apple per install per hour (10 by
/// default), refilled evenly. Per process, in memory; idle installs drop out of the limiter.
/// </summary>
public sealed class AppleVerifyLimiter : IAppleVerifyLimiter, IDisposable
{
    private readonly PartitionedRateLimiter<InstallId> limiter;

    public AppleVerifyLimiter(AppleBudgetOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var perHour = options.VerifyPerInstallPerHour;
        limiter = PartitionedRateLimiter.Create<InstallId, InstallId>(install => RateLimitPartition.GetTokenBucketLimiter(install, _ => new TokenBucketRateLimiterOptions
        {
            TokenLimit = perHour,
            TokensPerPeriod = 1,
            ReplenishmentPeriod = TimeSpan.FromHours(1) / perHour,
            QueueLimit = 0,
            AutoReplenishment = true,
        }));
    }

    public bool TryAcquire(InstallId install)
    {
        using var lease = limiter.AttemptAcquire(install);
        return lease.IsAcquired;
    }

    public void Dispose() => limiter.Dispose();
}

/// <summary>Our own Apple budget refused an attempt. Never retried by the pipeline; the client maps it to <c>budget_denied</c>.</summary>
internal sealed class AppleBudgetDeniedException : Exception
{
    public AppleBudgetDeniedException()
        : base("The Apple call budget is exhausted.")
    {
    }

    public AppleBudgetDeniedException(string message)
        : base(message)
    {
    }

    public AppleBudgetDeniedException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Takes one Apple budget permit per HTTP attempt, for the lane the request names (<see cref="AppleRequestLane"/>). It sits inside
/// the resilience pipeline, so every retry is charged (FU-077 M-2).
/// </summary>
internal sealed class AppleBudgetHandler(AppleCallBudget budget) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (!request.Options.TryGetValue(AppleRequestLane.Key, out var lane))
        {
            throw new InvalidOperationException("An App Store request must name its budget lane.");
        }

        if (!budget.TryAcquire(lane))
        {
            throw new AppleBudgetDeniedException();
        }

        return base.SendAsync(request, cancellationToken);
    }
}

/// <summary>The budget lane an App Store request is charged to.</summary>
internal static class AppleRequestLane
{
    public static readonly HttpRequestOptionsKey<StoreLane> Key = new("zaghlol.apple_lane");
}
