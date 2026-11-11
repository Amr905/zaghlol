namespace Zaghlol.Application.Purchases;

/// <summary>What one sweeper run did (counts only).</summary>
public sealed record AckSweepRun(bool Ran, int Rows, int Acknowledged, int Failed, bool BudgetExhausted);

/// <summary>
/// The acknowledge sweeper (T-130 design note §3, BR-GOLD-06): Google refunds a purchase not acknowledged within 3 days, so
/// every 15 minutes one sweeper (advisory lock across replicas) re-reads up to 200 due unacknowledged rows from Play, ackable
/// before pending (<see cref="PlayAckSweepSchedule"/>), and acknowledges those Play reports as purchased or active. A row it can't
/// finish (still pending, skipped, failed) is deferred with a backoff, so stuck rows never starve newer ones (security M-1). Each row is read and acknowledged outside any transaction, then
/// written in one short update under the monotonic <c>last_verified_at</c> guard. A cancelled, refunded or expired purchase
/// is recorded and never acknowledged; a pending one waits. An exhausted <c>ack</c> budget ends the run early; the next run
/// continues. Then the unacked gauge is recomputed and every ackable row 48 h or older raises the alert.
/// </summary>
public sealed class PlayAckSweepJob(
    IPlayAckSweepStore store,
    IPlayDeveloperApi play,
    PlayProductCatalog catalog,
    IPurchaseTelemetry telemetry,
    TimeProvider clock)
{
    public const int BatchSize = 200;

    /// <summary>The alert threshold; Play refunds at 72 h.</summary>
    public static readonly TimeSpan AlertAge = TimeSpan.FromHours(48);

    /// <summary>At most this many per-purchase alert signals per run.</summary>
    public const int MaxAlertsPerRun = 50;

    public async Task<AckSweepRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var held = await store.TryLockAsync(cancellationToken);
        if (held is null)
        {
            return new AckSweepRun(false, 0, 0, 0, false);
        }

        await using (held)
        {
            var rows = await store.ListAsync(clock.GetUtcNow(), BatchSize, cancellationToken);
            int acked = 0, failed = 0;
            var exhausted = false;
            foreach (var row in rows)
            {
                var outcome = await SweepAsync(row, cancellationToken);
                if (outcome == RowOutcome.BudgetDenied)
                {
                    exhausted = true;
                    break;
                }

                acked += outcome == RowOutcome.Acknowledged ? 1 : 0;
                failed += outcome == RowOutcome.Failed ? 1 : 0;
                if (outcome is RowOutcome.Waiting or RowOutcome.Failed or RowOutcome.Skipped)
                {
                    // Behind the due rows until then; never re-picked at the head of every run.
                    await store.DeferAsync(row.Id, PlayAckSweepSchedule.NextAttemptAt(row.CreatedAt, clock.GetUtcNow()), cancellationToken);
                }
            }

            var now = clock.GetUtcNow();
            var summary = await store.SummarizeAsync(now, MaxAlertsPerRun, cancellationToken);
            telemetry.SetUnacked(summary.LessThan48h, summary.AtLeast48h, summary.OldestAge);
            foreach (var overdue in summary.Overdue)
            {
                telemetry.UnackedOver48h(overdue);
            }

            return new AckSweepRun(true, rows.Count, acked, failed, exhausted);
        }
    }

    private async Task<RowOutcome> SweepAsync(UnackedPurchase row, CancellationToken cancellationToken)
    {
        if (!catalog.TryGet(row.ProductId, out var product))
        {
            // A product removed from the table: leave the row alone (an operator decides).
            return RowOutcome.Skipped;
        }

        var readAt = clock.GetUtcNow();
        Read read;
        try
        {
            read = await ReadAsync(product.Kind, row, readAt, cancellationToken);
        }
        catch (PlayApiException error) when (error.Outcome == PlayCallOutcome.BudgetDenied)
        {
            return RowOutcome.BudgetDenied;
        }
        catch (PlayApiException)
        {
            telemetry.Acknowledged(PurchaseTags.ChannelSweeper, PurchaseTags.AckFailed);
            return RowOutcome.Failed;
        }

        if (read.State is not { } state)
        {
            // Unknown state or a product ID that doesn't match the row: never write or acknowledge on doubt.
            return RowOutcome.Skipped;
        }

        var acknowledged = read.Acknowledged;
        var outcome = RowOutcome.Updated;
        if (acknowledged)
        {
            telemetry.Acknowledged(PurchaseTags.ChannelSweeper, PurchaseTags.AckAlready);
        }
        else if (PlayStateMapping.IsAckable(state))
        {
            try
            {
                if (product.Kind == PlayProductKind.Subscription)
                {
                    await play.AcknowledgeSubscriptionAsync(read.PlayProductId, row.Token, StoreLane.Ack, cancellationToken);
                }
                else
                {
                    await play.AcknowledgeProductAsync(read.PlayProductId, row.Token, StoreLane.Ack, cancellationToken);
                }

                acknowledged = true;
                outcome = RowOutcome.Acknowledged;
                telemetry.Acknowledged(PurchaseTags.ChannelSweeper, PurchaseTags.AckAcked);
                if (read.PurchasedAt is { } purchasedAt)
                {
                    telemetry.TimeToAck(clock.GetUtcNow() - purchasedAt);
                }
            }
            catch (PlayApiException error) when (error.Outcome == PlayCallOutcome.BudgetDenied)
            {
                await store.ApplyAsync(new SweepUpdate(row.Id, state, read.ExpiresAt, false, read.LinkedPurchaseToken, readAt), cancellationToken);
                return RowOutcome.BudgetDenied;
            }
            catch (PlayApiException)
            {
                outcome = RowOutcome.Failed;
                telemetry.Acknowledged(PurchaseTags.ChannelSweeper, PurchaseTags.AckFailed);
            }
        }
        else if (state != StoredPurchaseState.Pending)
        {
            telemetry.Acknowledged(PurchaseTags.ChannelSweeper, PurchaseTags.AckNotAckable);
        }

        await store.ApplyAsync(new SweepUpdate(row.Id, state, read.ExpiresAt, acknowledged, read.LinkedPurchaseToken, readAt), cancellationToken);
        return outcome == RowOutcome.Updated && PlayAckSweepSchedule.StillWaiting(state, acknowledged) ? RowOutcome.Waiting : outcome;
    }

    private async Task<Read> ReadAsync(PlayProductKind kind, UnackedPurchase row, DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (kind == PlayProductKind.Subscription)
        {
            var subscription = await play.GetSubscriptionAsync(row.Token, StoreLane.Ack, cancellationToken);
            var item = subscription.LineItems.FirstOrDefault(i => string.Equals(i.ProductId, row.ProductId, StringComparison.Ordinal));
            if (item is null)
            {
                return Read.Unusable;
            }

            var mapped = PlayStateMapping.Map(subscription.State, item.ExpiryTime, now);
            var state = mapped.Outcome switch
            {
                PlayReadOutcome.Known => mapped.State,

                // The pending payment never completed: the row is closed, never acknowledged.
                PlayReadOutcome.PendingPurchaseCanceled => StoredPurchaseState.Expired,
                _ => null,
            };
            return new Read(state, item.ProductId!, item.ExpiryTime, subscription.Acknowledged, subscription.LinkedPurchaseToken, subscription.StartTime);
        }

        var product = await play.GetProductAsync(row.Token, StoreLane.Ack, cancellationToken);
        if (!product.ProductIds.Contains(row.ProductId, StringComparer.Ordinal))
        {
            return Read.Unusable;
        }

        return new Read(PlayStateMapping.Map(product.State).State, row.ProductId, null, product.Acknowledged, null, product.PurchaseCompletionTime);
    }

    private enum RowOutcome
    {
        /// <summary>Written, and out of the queue (acknowledged, or a state that is never acknowledged).</summary>
        Updated,

        /// <summary>Written, still unacknowledged and pending or ackable: deferred.</summary>
        Waiting,

        Acknowledged,
        Failed,
        Skipped,
        BudgetDenied,
    }

    private sealed record Read(
        StoredPurchaseState? State,
        string PlayProductId,
        DateTimeOffset? ExpiresAt,
        bool Acknowledged,
        Domain.Sensitive<string>? LinkedPurchaseToken,
        DateTimeOffset? PurchasedAt)
    {
        public static Read Unusable { get; } = new(null, string.Empty, null, false, null, null);
    }
}
