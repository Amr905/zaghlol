using System.Globalization;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// The RTDN processor's codes (T-133 design note §5, error-handling-and-observability §2). <c>last_error</c> holds only these
/// constants (the schema's <c>^[A-Z0-9_]{1,64}$</c> CHECK); the schedule is the shared <see cref="StoreNotificationSchedule"/>.
/// </summary>
public static class PlayNotificationSchedule
{
    public const string StoreError = "STORE_ERROR";
    public const string StoreAuth = "STORE_AUTH";
    public const string NotFound = "NOT_FOUND";
    public const string Unmapped = "UNMAPPED";
    public const string RefundNotReflected = "REFUND_NOT_REFLECTED";
    public const string Contradiction = "CONTRADICTION";
    public const string Internal = StoreNotificationSchedule.Internal;

    /// <summary>Informational codes on processed rows (not failures).</summary>
    public const string NoPurchase = "NO_PURCHASE";
    public const string EnvMismatch = "ENV_MISMATCH";
    public const string Refused = "REFUSED";
    public const string TokenGone = "TOKEN_GONE";

    /// <summary>
    /// The refund floor (FU-098 nit 6: by time, not by attempts): a <c>VOIDED_PURCHASE</c> or <c>SUBSCRIPTION_REVOKED</c> whose read
    /// still entitles is retried until this long after <c>received_at</c>, then Play's answer is applied and a warning raised.
    /// Provisional, PO to confirm (T-133 PO question 3).
    /// </summary>
    public static readonly TimeSpan RefundFloor = TimeSpan.FromMinutes(40);

    /// <summary>Every counted failure code (the dead-letter codes).</summary>
    public static IReadOnlyList<string> FailureCodes { get; } =
        [StoreError, StoreAuth, NotFound, Unmapped, RefundNotReflected, Contradiction, Internal];
}

/// <summary>A failed re-read: a counted failure with its code, or an uncounted deferral (the run stops).</summary>
public readonly record struct PlayRefreshFailure(string Code, bool Counted, TimeSpan DeferFor)
{
    /// <summary>Maps a Play failure to its code (T-133 §3 step 4). A 410 is handled before this (<c>TOKEN_GONE</c>).</summary>
    public static PlayRefreshFailure Classify(PlayApiException error)
    {
        ArgumentNullException.ThrowIfNull(error);

        return error.Outcome switch
        {
            PlayCallOutcome.RateLimited => new(PlayNotificationSchedule.StoreError, false, StoreNotificationSchedule.RateLimitedDelay(error.RetryAfter)),
            PlayCallOutcome.BudgetDenied or PlayCallOutcome.CircuitOpen => new(PlayNotificationSchedule.StoreError, false, StoreNotificationSchedule.MinDefer),
            PlayCallOutcome.AuthError => new(PlayNotificationSchedule.StoreAuth, true, TimeSpan.Zero),
            PlayCallOutcome.ClientError => new(PlayNotificationSchedule.NotFound, true, TimeSpan.Zero),
            _ => new(PlayNotificationSchedule.StoreError, true, TimeSpan.Zero),
        };
    }
}

/// <summary>What one processor run did (counts only).</summary>
public sealed record PlayProcessRun(bool Ran, int Rows, int Applied, int Failed, bool Stopped);

/// <summary>
/// The Google RTDN processor (T-133 design note §3): one instance across replicas (advisory lock), up to <see cref="BatchSize"/> due
/// rows per run. A notification is an authenticated trigger, never the source of state: each row re-reads the purchase from Play
/// (<see cref="PlayPurchaseReader"/>, the T-130 calls and state table) and writes Play's current answer under the monotonic
/// <c>last_verified_at</c> guard, so duplicate, out-of-order and late messages converge on Play. The payload only chooses the label of
/// a non-entitling state (<see cref="PlayStateMapping.Settle"/>), never whether Gold is granted. It never inserts a purchase, never
/// moves a seat, and refuses rows the ingest would never produce without calling Play (FU-098 I-2).
/// </summary>
public sealed partial class PlayNotificationProcessor(
    IPlayNotificationStore store,
    PlayPurchaseReader reader,
    PlayProductCatalog catalog,
    IPlayNotificationTelemetry telemetry,
    TimeProvider clock,
    Func<double>? jitter = null)
{
    public const int BatchSize = 50;

    public const string LockName = "play-rtdn-processor";

    private readonly Func<double> jitter = jitter ?? Random.Shared.NextDouble;

    public async Task<PlayProcessRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var held = await store.TryLockAsync(LockName, cancellationToken);
        if (held is null)
        {
            // Another replica holds the lock: this process is alive, the run happens there.
            telemetry.Heartbeat();
            return new PlayProcessRun(false, 0, 0, 0, false);
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
                        // Counted INTERNAL; only a failing FailAsync (the database itself) aborts the run.
                        outcome = await FailAsync(row, new PlayRefreshFailure(PlayNotificationSchedule.Internal, true, TimeSpan.Zero), cancellationToken);
                    }

                    telemetry.Processed(PlayRtdnTypes.Tag(row.Type), outcome);
                    applied += outcome == RtdnTags.Applied ? 1 : 0;
                    failed += outcome is RtdnTags.Retry or RtdnTags.DeadLetter ? 1 : 0;
                    if (outcome == RtdnTags.Deferred)
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

            return new PlayProcessRun(true, rows, applied, failed, stopped);
        }
    }

    /// <summary>
    /// Step 0 (FU-098 I-2): the shapes the ingest and the two jobs produce. Anything else can only come from outside them (a worker-login
    /// row injection) and is refused without a Play call.
    /// </summary>
    public static bool IsIngestShaped(DuePlayNotification row)
    {
        ArgumentNullException.ThrowIfNull(row);

        if (!PlayRtdnTypes.ReconcileSet.Contains(row.Type) || row.Environment is not null || row.Subtype is not null
            || row.StoreKey is not { } key || !PlayStateMapping.IsWellFormedToken(key))
        {
            return false;
        }

        if (row.ExternalId.StartsWith(PlayJobKeys.VoidedPrefix, StringComparison.Ordinal))
        {
            return row.Type == PlayRtdnTypes.VoidedPurchase && VoidedKeyRegex().IsMatch(row.ExternalId);
        }

        if (row.ExternalId.StartsWith(PlayJobKeys.SweepPrefix, StringComparison.Ordinal))
        {
            return row.Type == PlayRtdnTypes.ExpirySweep && PlayJobKeys.TryParseSweep(row.ExternalId, out _, out _);
        }

        return row.Type != PlayRtdnTypes.ExpirySweep && MessageIdRegex().IsMatch(row.ExternalId);
    }

    private async Task<string> ProcessAsync(DuePlayNotification row, CancellationToken cancellationToken)
    {
        // 0. Refuse what the ingest never produces: no Play call.
        if (!IsIngestShaped(row))
        {
            await CompleteAsync(row, PlayNotificationSchedule.Refused, cancellationToken);
            return RtdnTags.Refused;
        }

        // 1. The purchase. The worker never inserts one: verify does (it alone knows the buying install), so a successor token's
        // SUBSCRIPTION_PURCHASED that beats verify leaves no row and verify still decides "new payment" (FU-092 item 9).
        var purchase = await store.FindPurchaseAsync(row.StoreKey!.Value, cancellationToken);
        if (purchase is null)
        {
            await CompleteAsync(row, PlayNotificationSchedule.NoPurchase, cancellationToken);
            return RtdnTags.NoPurchase;
        }

        if (row.Type == PlayRtdnTypes.ExpirySweep
            && (!PlayJobKeys.TryParseSweep(row.ExternalId, out var sweptPurchase, out _) || sweptPurchase != purchase.Id))
        {
            await CompleteAsync(row, PlayNotificationSchedule.Refused, cancellationToken);
            return RtdnTags.Refused;
        }

        // 2. The kind from the stored product (never from the payload).
        if (!catalog.TryGet(purchase.ProductId, out var product))
        {
            return await FailAsync(row, new PlayRefreshFailure(PlayNotificationSchedule.Unmapped, true, TimeSpan.Zero), cancellationToken);
        }

        // 3. Play's current answer; readAt first, so a slower read never overwrites a newer one.
        var readAt = clock.GetUtcNow();
        PlayPurchaseRead read;
        try
        {
            read = await reader.ReadAsync(product.Kind, purchase.StoreKey, purchase.ProductId, StoreLane.Notification, readAt, cancellationToken);
        }
        catch (PlayApiException error) when (error.Outcome == PlayCallOutcome.ClientError && error.HttpStatus == 410)
        {
            // Gone from Play: nothing to write. Alerted only when the stored state still grants Gold.
            await CompleteAsync(row, PlayNotificationSchedule.TokenGone, cancellationToken);
            return PlayStateMapping.IsEntitling(purchase.State) ? RtdnTags.TokenGone : RtdnTags.Unchanged;
        }
        catch (PlayApiException error)
        {
            return await FailAsync(row, PlayRefreshFailure.Classify(error), cancellationToken);
        }

        if (!read.ProductMatches)
        {
            return await FailAsync(row, new PlayRefreshFailure(PlayNotificationSchedule.Contradiction, true, TimeSpan.Zero), cancellationToken);
        }

        // A test purchase for a production row (or the reverse) is never applied.
        if (read.Environment != purchase.Environment)
        {
            await CompleteAsync(row, PlayNotificationSchedule.EnvMismatch, cancellationToken);
            return RtdnTags.EnvMismatch;
        }

        // 4. Never a write on doubt.
        StoredPurchaseState state;
        var onlyFromPending = false;
        switch (read.Mapped.Outcome)
        {
            case PlayReadOutcome.Known:
                state = read.Mapped.State!.Value;
                break;
            case PlayReadOutcome.PendingPurchaseCanceled:
                state = StoredPurchaseState.Expired;
                onlyFromPending = true;
                break;
            default:
                return await FailAsync(row, new PlayRefreshFailure(PlayNotificationSchedule.Unmapped, true, TimeSpan.Zero), cancellationToken);
        }

        // 5. The refund floor, by time: Play's API may lag its own void or revoke.
        if (row.Type is PlayRtdnTypes.VoidedPurchase or PlayRtdnTypes.SubscriptionRevoked && PlayStateMapping.IsEntitling(state))
        {
            if (clock.GetUtcNow() - row.ReceivedAt < PlayNotificationSchedule.RefundFloor)
            {
                return await FailAsync(row, new PlayRefreshFailure(PlayNotificationSchedule.RefundNotReflected, true, TimeSpan.Zero), cancellationToken);
            }

            // Provisional, PO to confirm (T-133 PO question 3a): an order refunded without revoke keeps Gold until Play ends it.
            telemetry.RefundNotReflected();
        }

        // 6-7. One short transaction: the label rule under the row lock, the guarded write, the event and the processed mark.
        var cause = row.Type == PlayRtdnTypes.ExpirySweep ? "sweep" : "rtdn:" + row.Type;

        // A pending-cancel keeps the stored expiry; so does a subscription read without one (never NULL a subscription's expiry,
        // which would look like a lifetime row). A one-time product has none.
        var keepExpiry = onlyFromPending || (product.Kind == PlayProductKind.Subscription && read.ExpiresAt is null);
        var result = await store.ApplyAsync(
            new PlayStateWrite(purchase.Id, state, read.ExpiresAt, keepExpiry, row.Type, onlyFromPending, readAt, cause),
            row.Id,
            cancellationToken);
        telemetry.Lag(clock.GetUtcNow() - row.ReceivedAt);
        return result switch
        {
            PlayWriteResult.Applied => RtdnTags.Applied,
            PlayWriteResult.Unchanged => RtdnTags.Unchanged,
            PlayWriteResult.Superseded => RtdnTags.Superseded,
            _ => RtdnTags.NoPurchase,
        };
    }

    private async Task CompleteAsync(DuePlayNotification row, string? code, CancellationToken cancellationToken)
    {
        await store.CompleteAsync(row.Id, code, cancellationToken);
        telemetry.Lag(clock.GetUtcNow() - row.ReceivedAt);
    }

    private async Task<string> FailAsync(DuePlayNotification row, PlayRefreshFailure failure, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        if (!failure.Counted)
        {
            await store.DeferAsync(row.Id, now + failure.DeferFor, cancellationToken);
            return RtdnTags.Deferred;
        }

        var attempts = row.Attempts + 1;
        if (attempts >= StoreNotificationSchedule.MaxAttempts)
        {
            await store.FailAsync(row.Id, attempts, null, failure.Code, cancellationToken);
            telemetry.DeadLettered();
            telemetry.Lag(now - row.ReceivedAt);
            return RtdnTags.DeadLetter;
        }

        await store.FailAsync(row.Id, attempts, StoreNotificationSchedule.NextAttemptAt(attempts, now, jitter()), failure.Code, cancellationToken);
        return RtdnTags.Retry;
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

    [GeneratedRegex(PlayNotificationIngest.MessageIdPattern, RegexOptions.CultureInvariant)]
    private static partial Regex MessageIdRegex();

    [GeneratedRegex(@"^voided:[0-9a-f]{64}\z", RegexOptions.CultureInvariant)]
    private static partial Regex VoidedKeyRegex();
}

/// <summary>The <c>external_id</c> forms of the two Google jobs (backend-schema <c>store_notifications</c>, T-133 §4).</summary>
public static partial class PlayJobKeys
{
    public const string VoidedPrefix = "voided:";
    public const string SweepPrefix = "sweep:";

    /// <summary><c>sweep:&lt;purchase id&gt;:&lt;epoch seconds of expires_at&gt;</c>: a renewal (new expiry) gets a new key.</summary>
    public static string Sweep(Guid purchaseId, DateTimeOffset expiresAt) =>
        SweepPrefix + purchaseId.ToString("D") + ":" + expiresAt.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture);

    public static bool TryParseSweep(string externalId, out Guid purchaseId, out long epoch)
    {
        ArgumentNullException.ThrowIfNull(externalId);
        purchaseId = Guid.Empty;
        epoch = 0;
        var match = SweepRegex().Match(externalId);
        return match.Success
            && Guid.TryParseExact(match.Groups[1].Value, "D", out purchaseId)
            && long.TryParse(match.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out epoch);
    }

    [GeneratedRegex(@"^sweep:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):([0-9]{1,12})\z", RegexOptions.CultureInvariant)]
    private static partial Regex SweepRegex();
}
