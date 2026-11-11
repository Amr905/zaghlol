using Zaghlol.Application.Retention;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// The retry schedule both notification processors share (T-134 design note §3, T-133 §5; error-handling-and-observability §2):
/// <c>next_attempt_at = now + min(1 min · 3^(n−1), 8 h)</c> ± 10 %, the 10th counted failure dead-letters the row (about 30 h after
/// the first), and an uncounted deferral (store 429, our budget, an open circuit) waits between 1 minute and 1 hour.
/// </summary>
public static class StoreNotificationSchedule
{
    /// <summary>The 10th counted failure dead-letters the row (about 30 h after the first).</summary>
    public const int MaxAttempts = 10;

    /// <summary><c>last_error</c> of a row whose processing threw unexpectedly (a counted failure; FU-098 code 2).</summary>
    public const string Internal = "INTERNAL";

    public static readonly TimeSpan BaseDelay = TimeSpan.FromMinutes(1);
    public static readonly TimeSpan MaxDelay = TimeSpan.FromHours(8);

    /// <summary>Uncounted deferrals: a store 429 waits <c>Retry-After</c> clamped to this range; budget or circuit 1 minute.</summary>
    public static readonly TimeSpan MinDefer = TimeSpan.FromMinutes(1);
    public static readonly TimeSpan MaxDefer = TimeSpan.FromHours(1);

    /// <summary>
    /// How long a notification row is kept (the <c>store_notifications</c> retention rule, <see cref="RetentionAges.StoreNotifications"/>).
    /// Every acceptance window for a store's replays must stay below it, so a replay still hits the dedupe key (FU-098 nit 5).
    /// </summary>
    public static TimeSpan Retention => RetentionAges.StoreNotifications;

    /// <summary><c>min(1 min · 3^(attempts−1), 8 h)</c>: 1 m, 3 m, 9 m, 27 m, 81 m, 4 h 3 m, then 8 h.</summary>
    public static TimeSpan Backoff(int attempts)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(attempts, 1);
        var delay = BaseDelay;
        for (var i = 1; i < attempts && delay < MaxDelay; i++)
        {
            delay *= 3;
        }

        return delay < MaxDelay ? delay : MaxDelay;
    }

    /// <summary>The next try after the <paramref name="attempts"/>-th counted failure, ± 10 % (<paramref name="jitterUnit"/> in [0, 1)).</summary>
    public static DateTimeOffset NextAttemptAt(int attempts, DateTimeOffset now, double jitterUnit)
    {
        var factor = 0.9 + (0.2 * Math.Clamp(jitterUnit, 0, 1));
        return now + (Backoff(attempts) * factor);
    }

    /// <summary>A store 429: its <c>Retry-After</c> clamped to 1 min-1 h (1 min when absent).</summary>
    public static TimeSpan RateLimitedDelay(TimeSpan? retryAfter)
    {
        var delay = retryAfter ?? MinDefer;
        return delay < MinDefer ? MinDefer : delay > MaxDefer ? MaxDefer : delay;
    }
}
