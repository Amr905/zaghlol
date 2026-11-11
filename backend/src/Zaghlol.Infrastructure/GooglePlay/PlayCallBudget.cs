using System.Threading.RateLimiting;
using Zaghlol.Application.Purchases;

namespace Zaghlol.Infrastructure.GooglePlay;

/// <summary>Which share of the Play budget a process serves (T-133 design note §6).</summary>
public enum PlayBudgetPartition
{
    /// <summary>An API process: verify, inline acknowledge, support and restore; refuses <see cref="StoreLane.Notification"/>.</summary>
    Api,

    /// <summary>The worker: the acknowledge sweeper and the RTDN lanes (<see cref="StoreLane.Ack"/>, <see cref="StoreLane.Notification"/>).</summary>
    Worker,
}

/// <summary>
/// The Play outbound budget (T-130 design note §2, T-133 §6; FU-077 M-2, FU-098 code 4), charged once per HTTP <b>attempt</b> (retries
/// included, by <see cref="PlayBudgetHandler"/> inside the retry). The configured numbers are the total over all processes:
/// <list type="bullet">
/// <item>the worker partition takes <c>WorkerShare ÷ WorkerReplicas</c> and serves <see cref="StoreLane.Ack"/> and
/// <see cref="StoreLane.Notification"/>; <see cref="StoreLane.Notification"/> is refused while at most <see cref="AckReserveShare"/>
/// of the bucket remains, so a notification flood can't miss the 3-day acknowledge deadline;</item>
/// <item>each API process takes <c>(1 − WorkerShare) ÷ Replicas</c> and serves verify, acknowledge, support and restore; restore is
/// denied first (it stops while only a 30 % reserve is left and has its own 30 % sub-bucket).</item>
/// </list>
/// A lane the partition doesn't serve is refused (a programming error, never sent). All checks and acquisitions run under one lock
/// (FU-092 item 2): only <see cref="TryAcquire"/> consumes permits, so a check can't be invalidated before the acquisition, and a
/// failed shared acquisition never spends a sub-bucket permit.
/// </summary>
public sealed class PlayCallBudget : IStoreCallBudget, IDisposable
{
    public const double RestoreShare = 0.3;

    /// <summary>The worker bucket share kept for the acknowledge sweeper (T-133 §6).</summary>
    public const double AckReserveShare = 0.25;

    private readonly Lock gate = new();
    private readonly TokenBucketRateLimiter shared;
    private readonly TokenBucketRateLimiter? restore;
    private readonly int reserve;

    public PlayCallBudget(PlayBudgetOptions options, PlayBudgetPartition partition = PlayBudgetPartition.Api)
    {
        ArgumentNullException.ThrowIfNull(options);

        Partition = partition;
        var (limit, perPeriod) = partition == PlayBudgetPartition.Worker
            ? (options.WorkerLimit, options.WorkerPerPeriod)
            : (options.PerReplicaLimit, options.PerReplicaPerPeriod);
        Limit = limit;
        shared = Bucket(limit, perPeriod, options.Period);
        if (partition == PlayBudgetPartition.Api)
        {
            restore = Bucket(Math.Max(1, (int)(limit * RestoreShare)), Math.Max(1, (int)(perPeriod * RestoreShare)), options.Period);
            reserve = (int)(limit * RestoreShare);
        }
        else
        {
            reserve = (int)(limit * AckReserveShare);
        }
    }

    public PlayBudgetPartition Partition { get; }

    /// <summary>This process's bucket size.</summary>
    public int Limit { get; }

    public bool TryAcquire(StoreLane lane)
    {
        if (!Serves(lane))
        {
            return false;
        }

        lock (gate)
        {
            var available = shared.GetStatistics()?.CurrentAvailablePermits ?? 0;
            if (Partition == PlayBudgetPartition.Worker && lane == StoreLane.Notification && available <= reserve)
            {
                return false;
            }

            if (lane == StoreLane.Restore
                && (available <= reserve || (restore!.GetStatistics()?.CurrentAvailablePermits ?? 0) < 1))
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
                using var restoreLease = restore!.AttemptAcquire();
            }

            return true;
        }
    }

    /// <summary>The permits the shared bucket holds now (tests).</summary>
    internal long Available() => shared.GetStatistics()?.CurrentAvailablePermits ?? 0;

    public void Dispose()
    {
        shared.Dispose();
        restore?.Dispose();
    }

    private bool Serves(StoreLane lane) => Partition == PlayBudgetPartition.Worker
        ? lane is StoreLane.Ack or StoreLane.Notification
        : lane is StoreLane.Verify or StoreLane.Ack or StoreLane.Support or StoreLane.Restore;

    private static TokenBucketRateLimiter Bucket(int limit, int perPeriod, TimeSpan period) => new(new TokenBucketRateLimiterOptions
    {
        TokenLimit = limit,
        TokensPerPeriod = perPeriod,
        ReplenishmentPeriod = period,
        QueueLimit = 0,
        AutoReplenishment = true,
    });
}

/// <summary>Our own Play budget refused an attempt. Never retried by the pipeline; the client maps it to <c>budget_denied</c>.</summary>
internal sealed class PlayBudgetDeniedException : Exception
{
    public PlayBudgetDeniedException()
        : base("The Play call budget is exhausted.")
    {
    }

    public PlayBudgetDeniedException(string message)
        : base(message)
    {
    }

    public PlayBudgetDeniedException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Takes one Play budget permit per HTTP attempt, for the lane the request names (<see cref="PlayRequestLane"/>). It sits inside the
/// resilience pipeline, so every retry is charged (FU-077 M-2).
/// </summary>
internal sealed class PlayBudgetHandler(PlayCallBudget budget) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (!request.Options.TryGetValue(PlayRequestLane.Key, out var lane))
        {
            throw new InvalidOperationException("A Play request must name its budget lane.");
        }

        if (!budget.TryAcquire(lane))
        {
            throw new PlayBudgetDeniedException();
        }

        return base.SendAsync(request, cancellationToken);
    }
}

/// <summary>The budget lane a Play request is charged to.</summary>
internal static class PlayRequestLane
{
    public static readonly HttpRequestOptionsKey<StoreLane> Key = new("zaghlol.play_lane");
}
