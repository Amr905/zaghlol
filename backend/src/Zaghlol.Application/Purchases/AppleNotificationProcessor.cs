namespace Zaghlol.Application.Purchases;

/// <summary>
/// The ASSN V2 processor's error codes (T-134 design note §3, error-handling-and-observability §2). The schedule itself is the shared
/// <see cref="StoreNotificationSchedule"/> (T-133 §5); the members here delegate to it. <c>last_error</c> holds only these constants
/// (the schema's <c>^[A-Z0-9_]{1,64}$</c> CHECK), so nothing from Apple reaches the database or a log.
/// </summary>
public static class AppleNotificationSchedule
{
    /// <summary>The 10th counted failure dead-letters the row (about 30 h after the first).</summary>
    public const int MaxAttempts = StoreNotificationSchedule.MaxAttempts;

    /// <summary><c>REFUND</c>/<c>REVOKE</c>: Apple's answer is taken as eventual consistency for this many attempts (about 40 min).</summary>
    public const int RefundFloorAttempts = 4;

    public const string StoreError = "STORE_ERROR";
    public const string StoreAuth = "STORE_AUTH";
    public const string NotFound = "NOT_FOUND";
    public const string JwsApi = "JWS_API";
    public const string Unmapped = "UNMAPPED";
    public const string RefundNotReflected = "REFUND_NOT_REFLECTED";
    public const string Contradiction = "CONTRADICTION";

    /// <summary>An unexpected exception on one row (FU-098 code 2): counted, and the run goes on with the next row.</summary>
    public const string Internal = StoreNotificationSchedule.Internal;

    /// <summary>Informational codes on processed rows (not failures).</summary>
    public const string NoPurchase = "NO_PURCHASE";
    public const string EnvMismatch = "ENV_MISMATCH";

    public static TimeSpan BaseDelay => StoreNotificationSchedule.BaseDelay;

    public static TimeSpan MaxDelay => StoreNotificationSchedule.MaxDelay;

    /// <summary>Uncounted deferrals: an Apple 429 waits <c>Retry-After</c> clamped to this range; budget or circuit 1 minute.</summary>
    public static TimeSpan MinDefer => StoreNotificationSchedule.MinDefer;

    public static TimeSpan MaxDefer => StoreNotificationSchedule.MaxDefer;

    /// <summary>Every counted failure code (the dead-letter codes).</summary>
    public static IReadOnlyList<string> FailureCodes { get; } =
        [StoreError, StoreAuth, NotFound, JwsApi, Unmapped, RefundNotReflected, Contradiction, Internal];

    /// <summary><c>min(1 min · 3^(attempts−1), 8 h)</c>: 1 m, 3 m, 9 m, 27 m, 81 m, 4 h 3 m, then 8 h.</summary>
    public static TimeSpan Backoff(int attempts) => StoreNotificationSchedule.Backoff(attempts);

    /// <summary>The next try after the <paramref name="attempts"/>-th counted failure, ± 10 % (<paramref name="jitterUnit"/> in [0, 1)).</summary>
    public static DateTimeOffset NextAttemptAt(int attempts, DateTimeOffset now, double jitterUnit) =>
        StoreNotificationSchedule.NextAttemptAt(attempts, now, jitterUnit);

    /// <summary>An Apple 429: its <c>Retry-After</c> clamped to 1 min-1 h (1 min when absent).</summary>
    public static TimeSpan RateLimitedDelay(TimeSpan? retryAfter) => StoreNotificationSchedule.RateLimitedDelay(retryAfter);
}

/// <summary>
/// How a failed re-read is handled: a counted failure with its code, or an uncounted deferral (the event isn't at fault, and the rest
/// of the run would fail the same way, so the run stops).
/// </summary>
public readonly record struct AppleRefreshFailure(string Code, bool Counted, TimeSpan DeferFor);

/// <summary>
/// The worker's re-read of a stored App Store purchase (T-134 design note §2 step 3), shared by the processor and the expiry sweep:
/// the same calls and the same state table as verify (<see cref="AppleSubscriptionReader"/>), on the <see cref="StoreLane.Notification"/>
/// lane and the base URL of the stored environment.
/// </summary>
public sealed class AppleStateRefresher(AppleSubscriptionReader reader, AppStoreCatalog catalog)
{
    public async Task<AppleStoreRead> ReadAsync(ApplePurchaseRow purchase, DateTimeOffset readAt, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(purchase);

        if (!catalog.TryGet(purchase.ProductId, out var product))
        {
            // A product removed from our table: never write on doubt.
            throw new AppleReadException(AppleReadFailure.UnknownProduct);
        }

        var key = purchase.StoreKey.Reveal();
        return product.Type == AppleProductType.NonConsumable
            ? await reader.ReadLifetimeAsync(purchase.Environment, key, StoreLane.Notification, readAt, cancellationToken)
            : await reader.ReadSubscriptionAsync(purchase.Environment, purchase.StoreKey, key, StoreLane.Notification, readAt, cancellationToken);
    }

    /// <summary>Maps a failed re-read to its code (T-134 §3).</summary>
    public static AppleRefreshFailure Classify(AppleReadException error)
    {
        ArgumentNullException.ThrowIfNull(error);

        return error.Failure switch
        {
            AppleReadFailure.Jws => new(AppleNotificationSchedule.JwsApi, true, TimeSpan.Zero),
            AppleReadFailure.Contradiction => new(AppleNotificationSchedule.Contradiction, true, TimeSpan.Zero),
            AppleReadFailure.UnknownProduct => new(AppleNotificationSchedule.Unmapped, true, TimeSpan.Zero),
            _ => Classify(error.ApiError),
        };
    }

    private static AppleRefreshFailure Classify(AppStoreApiException? api) => api?.Outcome switch
    {
        AppStoreCallOutcome.RateLimited => new(AppleNotificationSchedule.StoreError, false, AppleNotificationSchedule.RateLimitedDelay(api.RetryAfter)),
        AppStoreCallOutcome.BudgetDenied or AppStoreCallOutcome.CircuitOpen => new(AppleNotificationSchedule.StoreError, false, AppleNotificationSchedule.MinDefer),
        AppStoreCallOutcome.AuthError => new(AppleNotificationSchedule.StoreAuth, true, TimeSpan.Zero),
        AppStoreCallOutcome.ClientError when api.IsTransactionNotFound => new(AppleNotificationSchedule.NotFound, true, TimeSpan.Zero),
        _ => new(AppleNotificationSchedule.StoreError, true, TimeSpan.Zero),
    };
}

/// <summary>What one processor run did (counts only).</summary>
public sealed record AppleProcessRun(bool Ran, int Rows, int Applied, int Failed, bool Stopped);

/// <summary>
/// The ASSN V2 processor (T-134 design note §2): one instance across replicas (advisory lock), up to <see cref="BatchSize"/> due rows
/// per run. A notification is a signed trigger, not the source of state: each row re-reads the purchase from the App Store Server
/// API and writes Apple's current answer under the monotonic <c>last_verified_at</c> guard, so out-of-order, duplicate and late
/// notifications converge. It never inserts a purchase, never moves a seat and never writes the verify-only columns.
/// </summary>
public sealed class AppleNotificationProcessor(
    IAppleNotificationStore store,
    AppleStateRefresher refresher,
    IAppleNotificationTelemetry telemetry,
    TimeProvider clock,
    Func<double>? jitter = null)
{
    public const int BatchSize = 50;

    public const string LockName = "apple-assn-processor";

    private readonly Func<double> jitter = jitter ?? Random.Shared.NextDouble;

    public async Task<AppleProcessRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var held = await store.TryLockAsync(LockName, cancellationToken);
        if (held is null)
        {
            // Another replica holds the lock: this process is alive, the run happens there.
            telemetry.Heartbeat();
            return new AppleProcessRun(false, 0, 0, 0, false);
        }

        await using (held)
        {
            int rows = 0, applied = 0, failed = 0;
            var stopped = false;
            try
            {
                var due = await store.ListDueAsync(clock.GetUtcNow(), BatchSize, cancellationToken);
                rows = due.Count;
                foreach (var row in due)
                {
                    string outcome;
                    try
                    {
                        outcome = await ProcessAsync(row, cancellationToken);
                    }
#pragma warning disable CA1031 // FU-098 code 2: any failure of one row is that row's, never the run's.
                    catch (Exception) when (!cancellationToken.IsCancellationRequested)
#pragma warning restore CA1031
                    {
                        // FU-098 code 2: one throwing row is a counted INTERNAL failure, never the end of the run. Only a failing
                        // FailAsync (the database itself) aborts the run.
                        outcome = await FailAsync(row, new AppleRefreshFailure(AppleNotificationSchedule.Internal, true, TimeSpan.Zero), cancellationToken);
                    }

                    telemetry.Processed(AssnTags.Type(row.Type), outcome);
                    applied += outcome == AssnTags.Applied ? 1 : 0;
                    failed += outcome is AssnTags.Retry or AssnTags.DeadLetter ? 1 : 0;
                    if (outcome == AssnTags.Deferred)
                    {
                        stopped = true;
                        break;
                    }
                }

                telemetry.Heartbeat();
            }
            finally
            {
                await RefreshBacklogAsync();
            }

            return new AppleProcessRun(true, rows, applied, failed, stopped);
        }
    }

    /// <summary>The backlog gauge, refreshed after every run, even a failed one; its own failure is swallowed and counted.</summary>
    private async Task RefreshBacklogAsync()
    {
        try
        {
            var (young, old) = await store.BacklogAsync(clock.GetUtcNow(), CancellationToken.None);
            telemetry.SetBacklog(young, old);
        }
#pragma warning disable CA1031 // The gauge refresh must never hide the run's own outcome.
        catch (Exception)
#pragma warning restore CA1031
        {
            telemetry.BacklogFailed();
        }
    }

    private async Task<string> ProcessAsync(DueAppleNotification row, CancellationToken cancellationToken)
    {
        if (!AppleNotificationIngest.ReconcileSet.Contains(row.Type) || row.StoreKey is not { } key || row.Environment is not { } environment)
        {
            // The ingest inserts these processed; a row like this can only come from outside the ingest. Never call Apple for it.
            await CompleteAsync(row, AppleNotificationIngest.NoTransaction, cancellationToken);
            return AssnTags.Ignored;
        }

        // 1. The purchase. The worker never inserts one: verify does (it alone knows the buying install).
        var purchase = await store.FindPurchaseAsync(key, cancellationToken);
        if (purchase is null)
        {
            await CompleteAsync(row, AppleNotificationSchedule.NoPurchase, cancellationToken);
            return AssnTags.NoPurchase;
        }

        // 2. A production notification for a sandbox row (or the reverse) is never applied.
        if (purchase.Environment != environment)
        {
            await CompleteAsync(row, AppleNotificationSchedule.EnvMismatch, cancellationToken);
            return AssnTags.EnvMismatch;
        }

        // 3. Apple's current answer; readAt first, so a slower read never overwrites a newer one.
        var readAt = clock.GetUtcNow();
        AppleStoreRead read;
        try
        {
            read = await refresher.ReadAsync(purchase, readAt, cancellationToken);
        }
        catch (AppleReadException error)
        {
            return await FailAsync(row, AppleStateRefresher.Classify(error), cancellationToken);
        }

        // 4. Never a write on doubt.
        if (!read.Mapped.IsKnown)
        {
            return await FailAsync(row, new AppleRefreshFailure(AppleNotificationSchedule.Unmapped, true, TimeSpan.Zero), cancellationToken);
        }

        // 5. The refund floor: Apple's API may lag its own refund notification.
        var state = read.Mapped.State!.Value;
        if (row.Type is "REFUND" or "REVOKE" && state is not (StoredPurchaseState.Refunded or StoredPurchaseState.Revoked))
        {
            if (row.Attempts < AppleNotificationSchedule.RefundFloorAttempts)
            {
                return await FailAsync(row, new AppleRefreshFailure(AppleNotificationSchedule.RefundNotReflected, true, TimeSpan.Zero), cancellationToken);
            }

            // An older period may have been refunded while the current one is paid: Apple's answer wins, a human looks.
            telemetry.RefundNotReflected();
        }

        // 6. One short transaction: the guarded write, the event and the processed mark.
        var result = await store.ApplyAsync(
            new AppleStateWrite(purchase.Id, state, read.Mapped.ExpiresAt, read.Mapped.KeepStoredExpiry, read.ProductId, read.Plan, readAt, "assn:" + row.Type),
            row.Id,
            cancellationToken);
        telemetry.Lag(clock.GetUtcNow() - row.ReceivedAt);
        return result switch
        {
            AppleWriteResult.Applied => AssnTags.Applied,
            AppleWriteResult.Unchanged => AssnTags.Unchanged,
            AppleWriteResult.Superseded => AssnTags.Superseded,
            _ => AssnTags.NoPurchase,
        };
    }

    private async Task CompleteAsync(DueAppleNotification row, string? code, CancellationToken cancellationToken)
    {
        await store.CompleteAsync(row.Id, code, cancellationToken);
        telemetry.Lag(clock.GetUtcNow() - row.ReceivedAt);
    }

    private async Task<string> FailAsync(DueAppleNotification row, AppleRefreshFailure failure, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        if (!failure.Counted)
        {
            await store.DeferAsync(row.Id, now + failure.DeferFor, cancellationToken);
            return AssnTags.Deferred;
        }

        var attempts = row.Attempts + 1;
        if (attempts >= AppleNotificationSchedule.MaxAttempts)
        {
            await store.FailAsync(row.Id, attempts, null, failure.Code, cancellationToken);
            telemetry.DeadLettered();
            telemetry.Lag(now - row.ReceivedAt);
            return AssnTags.DeadLetter;
        }

        await store.FailAsync(row.Id, attempts, AppleNotificationSchedule.NextAttemptAt(attempts, now, jitter()), failure.Code, cancellationToken);
        return AssnTags.Retry;
    }
}
