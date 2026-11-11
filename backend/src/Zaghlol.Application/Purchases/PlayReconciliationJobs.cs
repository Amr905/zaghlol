using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>What one Google reconciliation run did (counts only).</summary>
public sealed record PlayReconcileRun(bool Ran, int Read, int Inserted, int Skipped);

/// <summary>
/// The daily voided-purchases reconciliation (T-133 design note §4): <c>voidedpurchases.list</c> over the last 30 days (less one hour,
/// so the window never touches Play's 30-day limit), <c>type=1</c>, following the page token for at most <see cref="MaxPages"/> pages.
/// It only <b>enqueues</b>: each void of a known Google purchase becomes one <c>VOIDED_PURCHASE</c> row keyed by
/// <c>voided:&lt;sha256(orderId, token, voidedTime)&gt;</c> (one per voided order: with <c>type=1</c> renewals share a token), so
/// the processor's re-read, refund floor, retries, dead letter and refusals apply to it exactly as to an RTDN. The 30-day window lies
/// inside the 90-day retention, so a void is enqueued once. Unknown tokens are counted, never stored.
/// </summary>
public sealed class PlayVoidedReconcileJob(
    IPlayNotificationStore store,
    IStoreNotificationInbox inbox,
    IPlayDeveloperApi play,
    PlayProductCatalog catalog,
    IPlayNotificationTelemetry telemetry,
    TimeProvider clock)
{
    public const string LockName = "play-voided-reconcile";

    public const int MaxPages = 10;

    /// <summary>Play accepts a <c>startTime</c> no older than 30 days; one hour of margin.</summary>
    public static readonly TimeSpan LookBack = TimeSpan.FromDays(30) - TimeSpan.FromHours(1);

    public async Task<PlayReconcileRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        // Development with an empty Purchases:Google section: nothing could be matched, so nothing is fetched.
        if (catalog.PackageName.Length == 0)
        {
            return new PlayReconcileRun(false, 0, 0, 0);
        }

        var held = await store.TryLockAsync(LockName, cancellationToken);
        if (held is null)
        {
            return new PlayReconcileRun(false, 0, 0, 0);
        }

        await using (held)
        {
            var end = clock.GetUtcNow();
            var start = end - LookBack;
            int read = 0, inserted = 0, skipped = 0, recovered = 0, pages = 0;
            Sensitive<string>? token = null;
            try
            {
                do
                {
                    PlayVoidedPage page;
                    try
                    {
                        page = await play.ListVoidedPurchasesAsync(start, end, token, StoreLane.Notification, cancellationToken);
                    }
                    catch (PlayApiException error)
                    {
                        // The next daily run covers the same 30 days again; the hourly expiry sweep still runs.
                        telemetry.Reconciled(
                            RtdnTags.StepVoided,
                            PlayRefreshFailure.Classify(error).Counted ? RtdnTags.ReconcileFailed : RtdnTags.Deferred);
                        return new PlayReconcileRun(true, read, inserted, skipped);
                    }

                    pages++;
                    foreach (var voided in page.Purchases)
                    {
                        read++;
                        switch (await EnqueueAsync(voided, cancellationToken))
                        {
                            case Enqueued.Inserted:
                                inserted++;
                                break;
                            case Enqueued.Recovered:
                                inserted++;
                                recovered++;
                                break;
                            case Enqueued.Skipped:
                                skipped++;
                                break;
                        }
                    }

                    token = page.NextPageToken is { } next && next.Reveal() is { Length: > 0 } ? next : null;
                }
                while (token is not null && pages < MaxPages);
            }
            finally
            {
                telemetry.Recovered(recovered);
            }

            telemetry.Reconciled(RtdnTags.StepVoided, token is not null ? RtdnTags.ReconcileTruncated : RtdnTags.ReconcileOk);
            return new PlayReconcileRun(true, read, inserted, skipped);
        }
    }

    /// <summary>SHA-256 over <c>orderId ‖ 0x00 ‖ purchaseToken ‖ 0x00 ‖ voidedTimeMillis</c> (UTF-8): one key per voided order.</summary>
    public static byte[] Key(string? orderId, string purchaseToken, long voidedTimeMillis)
    {
        ArgumentNullException.ThrowIfNull(purchaseToken);
        var text = (orderId ?? string.Empty) + "\0" + purchaseToken + "\0" + voidedTimeMillis.ToString(CultureInfo.InvariantCulture);
        return SHA256.HashData(Encoding.UTF8.GetBytes(text));
    }

    private async Task<Enqueued> EnqueueAsync(PlayVoidedPurchase voided, CancellationToken cancellationToken)
    {
        if (voided.PurchaseToken is not { } token || !PlayStateMapping.IsWellFormedToken(token)
            || voided.VoidedTimeMillis is not { } millis || millis is <= 0 or > 253402300799999L
            || (voided.OrderId is { } order && !PlayStateMapping.IsWellFormedOrderId(order)))
        {
            return Enqueued.Skipped;
        }

        if (await store.FindPurchaseAsync(token, cancellationToken) is null)
        {
            // Not ours (or not yet verified): counted, never stored.
            return Enqueued.Skipped;
        }

        var key = Key(voided.OrderId?.Reveal(), token.Reveal()!, millis);
        var record = new StoreNotificationRecord(
            Guid.CreateVersion7(),
            PurchaseStore.GooglePlay,
            PlayJobKeys.VoidedPrefix + Convert.ToHexStringLower(key),
            PlayRtdnTypes.VoidedPurchase,
            null,
            null,
            token,
            null,
            DateTimeOffset.FromUnixTimeMilliseconds(millis),
            key,
            Processed: false,
            LastError: null);
        if (!await inbox.TryInsertAsync(record, cancellationToken))
        {
            return Enqueued.Duplicate;
        }

        return await store.HasRtdnVoidedAsync(token, cancellationToken) ? Enqueued.Inserted : Enqueued.Recovered;
    }

    private enum Enqueued
    {
        Inserted,
        Recovered,
        Duplicate,
        Skipped,
    }
}

/// <summary>
/// The hourly Google expiry sweep (T-133 design note §4): up to <see cref="BatchSize"/> Google subscriptions in an entitling state
/// whose expiry passed (10 min to 7 days ago) without a newer read get one <c>EXPIRY_SWEEP</c> row each
/// (<c>sweep:&lt;purchase id&gt;:&lt;expiry epoch&gt;</c>), processed like an RTDN. Needed because <c>v_entitlements</c> checks only
/// <c>state</c>: a lost <c>SUBSCRIPTION_EXPIRED</c> would otherwise keep Gold. A purchase whose sweep row for that expiry exists
/// (pending, done or dead-lettered) is not listed, so a stuck row never blocks the rest (FU-098 code 3); a renewal gets a new key.
/// </summary>
public sealed class PlayExpirySweepJob(
    IPlayNotificationStore store,
    IStoreNotificationInbox inbox,
    IPlayNotificationTelemetry telemetry,
    TimeProvider clock)
{
    public const string LockName = "play-expiry-sweep";

    public const int BatchSize = 200;

    public async Task<PlayReconcileRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var held = await store.TryLockAsync(LockName, cancellationToken);
        if (held is null)
        {
            return new PlayReconcileRun(false, 0, 0, 0);
        }

        await using (held)
        {
            var rows = await store.ListExpiredSubscriptionsAsync(clock.GetUtcNow(), BatchSize, cancellationToken);
            var inserted = 0;
            foreach (var row in rows)
            {
                var key = PlayJobKeys.Sweep(row.PurchaseId, row.ExpiresAt);
                var record = new StoreNotificationRecord(
                    Guid.CreateVersion7(),
                    PurchaseStore.GooglePlay,
                    key,
                    PlayRtdnTypes.ExpirySweep,
                    null,
                    null,
                    row.StoreKey,
                    null,
                    row.ExpiresAt,
                    SHA256.HashData(Encoding.UTF8.GetBytes(key)),
                    Processed: false,
                    LastError: null);
                inserted += await inbox.TryInsertAsync(record, cancellationToken) ? 1 : 0;
            }

            telemetry.Reconciled(RtdnTags.StepExpiry, RtdnTags.ReconcileOk);
            return new PlayReconcileRun(true, rows.Count, inserted, rows.Count - inserted);
        }
    }
}
