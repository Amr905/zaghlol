using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>What one reconciliation run did (counts only).</summary>
public sealed record AppleReconcileRun(bool Ran, int Read, int Inserted, int Failed);

/// <summary>
/// The daily <c>Get Notification History</c> job (T-134 design note §4): for production, and sandbox while <c>AllowSandbox</c> is on,
/// the last 7 days of notifications Apple failed to deliver (<c>onlyFailures</c>), at most <see cref="MaxPages"/> pages per
/// environment. Each <c>signedPayload</c> goes through the same <see cref="AppleNotificationIngest"/> as the endpoint, so dedupe is
/// the same insert. An entry failing verification is skipped and alerted (it came from Apple's API); rows it inserts are counted as
/// <c>recovered</c> (alerted: delivery is failing).
/// </summary>
public sealed class AppleNotificationHistoryJob(
    IAppleNotificationStore store,
    IAppStoreServerApi apple,
    AppleNotificationIngest ingest,
    AppStoreCatalog catalog,
    IAppleNotificationTelemetry telemetry,
    TimeProvider clock)
{
    public const string LockName = "apple-assn-history";

    public const int MaxPages = 20;

    public static readonly TimeSpan LookBack = TimeSpan.FromDays(7);

    /// <summary>The window ends a little before now, so a notification still being delivered isn't fetched as a failure.</summary>
    public static readonly TimeSpan EndMargin = TimeSpan.FromMinutes(5);

    public async Task<AppleReconcileRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        // Development with an empty Purchases:Apple section: nothing could be accepted, so nothing is fetched.
        if (catalog.BundleId.Length == 0)
        {
            return new AppleReconcileRun(false, 0, 0, 0);
        }

        var held = await store.TryLockAsync(LockName, cancellationToken);
        if (held is null)
        {
            return new AppleReconcileRun(false, 0, 0, 0);
        }

        await using (held)
        {
            int read = 0, inserted = 0, failed = 0;
            PurchaseEnvironment[] environments = catalog.AllowSandbox
                ? [PurchaseEnvironment.Production, PurchaseEnvironment.Sandbox]
                : [PurchaseEnvironment.Production];
            foreach (var environment in environments)
            {
                var (r, i, f) = await RunEnvironmentAsync(environment, cancellationToken);
                read += r;
                inserted += i;
                failed += f;
            }

            telemetry.Recovered(inserted);
            return new AppleReconcileRun(true, read, inserted, failed);
        }
    }

    private async Task<(int Read, int Inserted, int Failed)> RunEnvironmentAsync(PurchaseEnvironment environment, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var (start, end) = (now - LookBack, now - EndMargin);
        int read = 0, inserted = 0, failed = 0, pages = 0;
        Sensitive<string>? token = null;
        AppleNotificationHistoryPage page;
        do
        {
            try
            {
                page = await apple.GetNotificationHistoryAsync(environment, start, end, token, StoreLane.Notification, cancellationToken);
            }
            catch (AppStoreApiException)
            {
                // The next daily run covers the same window (7 days back), and the expiry sweep runs hourly.
                telemetry.Reconciled(AssnTags.StepHistory, AssnTags.ReconcileFailed);
                return (read, inserted, failed + 1);
            }

            pages++;
            foreach (var payload in page.SignedPayloads)
            {
                read++;
                switch (await ingest.IngestAsync(payload, cancellationToken))
                {
                    case AppleIngestOutcome.Stored:
                        inserted++;
                        break;
                    case AppleIngestOutcome.Unauthorized:
                        failed++;
                        telemetry.Reconciled(AssnTags.StepHistory, AssnTags.ReconcileInvalidEntry);
                        break;
                }
            }

            token = page.PaginationToken;
        }
        while (page.HasMore && token is not null && pages < MaxPages);

        telemetry.Reconciled(
            AssnTags.StepHistory,
            page.HasMore && token is not null ? AssnTags.ReconcileTruncated : AssnTags.ReconcileOk);
        return (read, inserted, failed);
    }
}

/// <summary>
/// The hourly expiry sweep (T-134 design note §4): up to <see cref="BatchSize"/> App Store subscriptions in an entitling state whose
/// expiry passed (10 min to 7 days ago) without a newer read, re-read and written exactly like a notification (<c>cause = sweep</c>,
/// no notification row). It catches renewals or expiries Apple never reported as failed, and sandbox rows whose notifications go to
/// another backend.
/// </summary>
public sealed class AppleExpirySweepJob(
    IAppleNotificationStore store,
    AppleStateRefresher refresher,
    IAppleNotificationTelemetry telemetry,
    TimeProvider clock)
{
    public const string LockName = "apple-expiry-sweep";

    public const int BatchSize = 100;

    public async Task<AppleReconcileRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var held = await store.TryLockAsync(LockName, cancellationToken);
        if (held is null)
        {
            return new AppleReconcileRun(false, 0, 0, 0);
        }

        await using (held)
        {
            var rows = await store.ListExpiredSubscriptionsAsync(clock.GetUtcNow(), BatchSize, cancellationToken);
            int written = 0, failed = 0;
            foreach (var row in rows)
            {
                var readAt = clock.GetUtcNow();
                AppleStoreRead read;
                try
                {
                    read = await refresher.ReadAsync(row, readAt, cancellationToken);
                }
                catch (AppleReadException error)
                {
                    if (!AppleStateRefresher.Classify(error).Counted)
                    {
                        // Apple 429, our budget or an open circuit: the rest would fail the same way; the next hour retries.
                        telemetry.Reconciled(AssnTags.StepExpiry, AssnTags.Deferred);
                        break;
                    }

                    failed++;
                    telemetry.Reconciled(AssnTags.StepExpiry, AssnTags.ReconcileFailed);
                    continue;
                }

                if (!read.Mapped.IsKnown)
                {
                    failed++;
                    telemetry.Reconciled(AssnTags.StepExpiry, AssnTags.ReconcileFailed);
                    continue;
                }

                var result = await store.ApplyAsync(
                    new AppleStateWrite(row.Id, read.Mapped.State!.Value, read.Mapped.ExpiresAt, read.Mapped.KeepStoredExpiry, read.ProductId, read.Plan, readAt, "sweep"),
                    null,
                    cancellationToken);
                written += result is AppleWriteResult.Applied or AppleWriteResult.Unchanged ? 1 : 0;
                telemetry.Reconciled(AssnTags.StepExpiry, result switch
                {
                    AppleWriteResult.Applied => AssnTags.Applied,
                    AppleWriteResult.Unchanged => AssnTags.Unchanged,
                    _ => AssnTags.Superseded,
                });
            }

            return new AppleReconcileRun(true, rows.Count, written, failed);
        }
    }
}
