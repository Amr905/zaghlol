using System.Threading.RateLimiting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>Which share of the Apple budget a process serves (T-134 design note §6).</summary>
public enum AppleBudgetPartition
{
    /// <summary>An API process: verify, support and restore; refuses <see cref="StoreLane.Notification"/>.</summary>
    Api,

    /// <summary>The worker: notification processing and reconciliation only (<see cref="StoreLane.Notification"/>).</summary>
    Worker,
}

/// <summary>
/// The Apple outbound budget (T-131 design note §6, T-134 §6), separate from Play's, charged once per HTTP <b>attempt</b> (retries
/// included, by <see cref="AppleBudgetHandler"/> inside the retry). The configured total is <b>partitioned</b> across processes instead
/// of reserved inside one: the worker gets <c>WorkerShare</c> of it for <see cref="StoreLane.Notification"/> (the only lane it serves),
/// and each API process <c>(1 − WorkerShare) / Replicas</c> for every other lane (it refuses <see cref="StoreLane.Notification"/>).
/// Inside an API bucket restore is denied first: it stops while only a 30 % reserve is left, and it may take at most 30 % of the bucket
/// through its own sub-bucket. The checks and both acquisitions run under one lock (FU-092 item 2): only <see cref="TryAcquire"/>
/// consumes permits and replenishment only adds them, so a check under the lock can't be invalidated before the acquisition, and a
/// failed shared acquisition never spends a restore permit. A denied attempt is never sent.
/// </summary>
public sealed class AppleCallBudget : IStoreCallBudget, IDisposable
{
    public const double RestoreShare = 0.3;

    private readonly Lock gate = new();
    private readonly TokenBucketRateLimiter shared;
    private readonly TokenBucketRateLimiter restore;
    private readonly int restoreReserve;

    public AppleCallBudget(AppleBudgetOptions options, AppleBudgetPartition partition = AppleBudgetPartition.Api)
    {
        ArgumentNullException.ThrowIfNull(options);

        Partition = partition;
        var (limit, perPeriod) = partition == AppleBudgetPartition.Worker
            ? (options.WorkerLimit, options.WorkerPerPeriod)
            : (options.PerReplicaLimit, options.PerReplicaPerPeriod);
        Limit = limit;
        shared = Bucket(limit, perPeriod, options.Period);
        restore = Bucket(Math.Max(1, (int)(limit * RestoreShare)), Math.Max(1, (int)(perPeriod * RestoreShare)), options.Period);
        restoreReserve = (int)(limit * RestoreShare);
    }

    public AppleBudgetPartition Partition { get; }

    /// <summary>This process's bucket size.</summary>
    public int Limit { get; }

    public bool TryAcquire(StoreLane lane)
    {
        // A lane the partition doesn't serve is a programming error: refused, never sent.
        if ((lane == StoreLane.Notification) != (Partition == AppleBudgetPartition.Worker))
        {
            return false;
        }

        lock (gate)
        {
            if (lane == StoreLane.Restore
                && ((shared.GetStatistics()?.CurrentAvailablePermits ?? 0) <= restoreReserve
                    || (restore.GetStatistics()?.CurrentAvailablePermits ?? 0) < 1))
            {
                return false;
            }

            using (var lease = shared.AttemptAcquire())
            {
                if (!lease.IsAcquired)
                {
                    return false;
                }
            }

            if (lane == StoreLane.Restore)
            {
                // Checked above under the same lock, and nothing else consumes it: this succeeds.
                using var restoreLease = restore.AttemptAcquire();
            }

            return true;
        }
    }

    /// <summary>The permits each bucket holds now (tests).</summary>
    internal (long Shared, long Restore) Available() =>
        (shared.GetStatistics()?.CurrentAvailablePermits ?? 0, restore.GetStatistics()?.CurrentAvailablePermits ?? 0);

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
