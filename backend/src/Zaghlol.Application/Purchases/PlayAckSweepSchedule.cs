namespace Zaghlol.Application.Purchases;

/// <summary>
/// The acknowledge sweeper's scheduling rules (T-130 security M-1). A row the sweeper can't finish (still pending, an unknown product
/// or state, a Play error) is stamped with <c>ack_next_attempt_at</c> and leaves the batch until then, so stuck rows can never
/// fill the 200-row window and starve a newer purchase that still has to be acknowledged before Play refunds it at 72 h. The
/// store's SQL (<c>PlayAckSweepStore</c>) implements exactly <see cref="IsDue"/> and <see cref="SortKey"/>.
/// </summary>
public static class PlayAckSweepSchedule
{
    /// <summary>Play refunds a purchase not acknowledged within 3 days.</summary>
    public static readonly TimeSpan RefundAge = TimeSpan.FromHours(72);

    /// <summary>The shortest deferral: one sweeper period.</summary>
    public static readonly TimeSpan MinRetryDelay = TimeSpan.FromMinutes(15);

    /// <summary>
    /// The longest deferral inside the refund window. It also bounds how late the sweeper sees a deferred pending row that verify
    /// later moved to active with a failed inline acknowledge (at least 12 more attempts in the last day before 72 h).
    /// </summary>
    public static readonly TimeSpan MaxRetryDelay = TimeSpan.FromHours(2);

    /// <summary>Past the refund age nothing is urgent any more: a daily re-read only closes the row.</summary>
    public static readonly TimeSpan PastRefundRetryDelay = TimeSpan.FromHours(24);

    /// <summary>The wait before the next attempt on a row of this age: a quarter of its age, 15 min to 2 h; 24 h past 72 h.</summary>
    public static TimeSpan RetryDelay(TimeSpan age)
    {
        if (age >= RefundAge)
        {
            return PastRefundRetryDelay;
        }

        var quarter = age / 4;
        return quarter < MinRetryDelay ? MinRetryDelay : quarter > MaxRetryDelay ? MaxRetryDelay : quarter;
    }

    /// <summary>When a row the run could not finish is tried again.</summary>
    public static DateTimeOffset NextAttemptAt(DateTimeOffset createdAt, DateTimeOffset now) => now + RetryDelay(now - createdAt);

    /// <summary>A row is listed when it was never deferred or its deferral has passed.</summary>
    public static bool IsDue(DateTimeOffset? nextAttemptAt, DateTimeOffset now) => nextAttemptAt is not { } next || next <= now;

    /// <summary>
    /// The listing order, ascending: ackable rows before pending ones (their 3-day clock is running), never-deferred rows before
    /// deferred ones, then the earliest due, then the oldest. SQL: <c>ORDER BY (state = 'pending'), ack_next_attempt_at NULLS
    /// FIRST, created_at</c>.
    /// </summary>
    public static (bool Pending, bool Deferred, DateTimeOffset Due, DateTimeOffset CreatedAt) SortKey(
        StoredPurchaseState state,
        DateTimeOffset? nextAttemptAt,
        DateTimeOffset createdAt) =>
        (state == StoredPurchaseState.Pending, nextAttemptAt is not null, nextAttemptAt ?? DateTimeOffset.MinValue, createdAt);

    /// <summary>Whether a row is still in the sweeper's queue after a read in this state (unacknowledged, pending or ackable).</summary>
    public static bool StillWaiting(StoredPurchaseState state, bool acknowledged) =>
        !acknowledged && (state == StoredPurchaseState.Pending || PlayStateMapping.IsAckable(state));
}
