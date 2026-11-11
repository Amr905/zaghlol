namespace Zaghlol.Application.Retention;

/// <summary>
/// The retention rules of backend-schema.md section 4 (NFR-PRIV-06, D-47), in run order. Each name is a fixed lower-case
/// word: it is a metric tag value and a log <c>operation</c> value, never derived from data.
/// </summary>
public static class RetentionRules
{
    public const string RegistrationColumns = "registration_columns";
    public const string TombstonedInstalls = "tombstoned_installs";
    public const string InactiveInstalls = "inactive_installs";
    public const string StoreNotifications = "store_notifications";
    public const string Contributions = "contributions";
    public const string BankRequests = "bank_requests";
    public const string AuditSupport = "audit_support";
    public const string AuditOther = "audit_other";
    public const string ReplayGuard = "replay_guard";
    public const string SeatClaimants = "seat_claimants";
    public const string IdempotencyRecords = "idempotency_records";

    public static IReadOnlyList<string> All { get; } =
    [
        RegistrationColumns, TombstonedInstalls, InactiveInstalls, StoreNotifications, Contributions, BankRequests,
        AuditSupport, AuditOther, ReplayGuard, SeatClaimants, IdempotencyRecords,
    ];
}

/// <summary>The audit actions that are personal data and are deleted exactly one year after creation (D-47, FR-BE-11).</summary>
public static class RetentionAuditActions
{
    public static IReadOnlyList<string> OneYear { get; } = ["support_lookup", "support_seat_move", "support_detach", "support_unfreeze"];
}

/// <summary>Deletes the rows of one rule that are past their age, on the worker login (<c>worker_rw</c>).</summary>
public interface IRetentionStore
{
    /// <summary>
    /// Purges at most <paramref name="batchSize"/> rows of <paramref name="rule"/> that are past their age at <paramref name="now"/>
    /// and returns how many it changed. A result below <paramref name="batchSize"/> means the rule is done.
    /// </summary>
    Task<int> PurgeBatchAsync(string rule, DateTimeOffset now, int batchSize, CancellationToken cancellationToken);
}

/// <summary>Counters of the purger. Rule names come from <see cref="RetentionRules"/>.</summary>
public interface IRetentionMetrics
{
    void Purged(string rule, long count);

    void Failed(string rule);
}

/// <summary>What one run did: rows changed per rule, and the rules that failed (by name; never an exception message).</summary>
public sealed record RetentionRunResult(IReadOnlyDictionary<string, int> Purged, IReadOnlyList<string> Failed);

/// <summary>
/// One daily run of the RetentionPurger: every rule in turn, in batches, each isolated so one failing rule doesn't stop the others.
/// </summary>
public sealed class RetentionPurgeJob(IRetentionStore store, IRetentionMetrics metrics, TimeProvider clock)
{
    public const int DefaultBatchSize = 5000;

    /// <summary>A rule stops after this many batches in one run; the next run continues (bounds one run's time).</summary>
    public const int MaxBatchesPerRule = 1000;

    public async Task<RetentionRunResult> RunOnceAsync(int batchSize, CancellationToken cancellationToken)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(batchSize, 1);

        var now = clock.GetUtcNow();
        var purged = new Dictionary<string, int>(StringComparer.Ordinal);
        var failed = new List<string>();
        foreach (var rule in RetentionRules.All)
        {
            var total = 0;
            try
            {
                for (var batch = 0; batch < MaxBatchesPerRule; batch++)
                {
                    var changed = await store.PurgeBatchAsync(rule, now, batchSize, cancellationToken);
                    total += changed;
                    if (changed < batchSize)
                    {
                        break;
                    }
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
#pragma warning disable CA1031 // One failing rule (lock timeout, outage) must not stop the other rules; it is counted and retried next run.
            catch (Exception)
#pragma warning restore CA1031
            {
                failed.Add(rule);
                metrics.Failed(rule);
            }

            purged[rule] = total;
            if (total > 0)
            {
                metrics.Purged(rule, total);
            }
        }

        return new RetentionRunResult(purged, failed);
    }
}

/// <summary>
/// Retention ages that code outside the purger depends on (FU-098 nit 5): the purger's SQL and every acceptance window that must stay
/// below a retention read the same value.
/// </summary>
public static class RetentionAges
{
    /// <summary><c>store_notifications</c> rows are deleted 90 days after <c>received_at</c>.</summary>
    public const int StoreNotificationsDays = 90;

    public static TimeSpan StoreNotifications { get; } = TimeSpan.FromDays(StoreNotificationsDays);
}
