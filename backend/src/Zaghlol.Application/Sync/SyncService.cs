using Zaghlol.Application.Catalog;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Prices;
using Zaghlol.Domain;

namespace Zaghlol.Application.Sync;

/// <summary>
/// <c>POST /v1/sync</c> after the API checked the body (T-128 design note §2-§5). Order: (1) one indexed read of the install
/// and the throttle pre-check; (2) the read phase, with no transaction and no connection held across awaits: catalog, flags,
/// prices, the entitlement extension point; (3) intake preparation and one keyed hash; (4) one short write transaction that
/// claims the window with a conditional UPDATE, inserts the intake and counts the install as active today. Nothing is written
/// before (4), so any failure before it leaves the window unconsumed. A lost claim race becomes the throttle answer.
/// </summary>
public sealed class SyncService(
    ISyncStore store,
    ICatalogReader catalog,
    IFlagReader flags,
    PriceReadService prices,
    ISyncEntitlementBlock entitlement,
    IInstallHasher hasher,
    ISyncTelemetry telemetry,
    SyncOptions options,
    TimeProvider clock)
{
    public async Task<SyncResult> SyncAsync(InstallId installId, string appVersion, SyncRequestData request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(appVersion);
        ArgumentNullException.ThrowIfNull(request);

        // Whole seconds: serverTime, nextSyncNotBefore and the stored last_sync_at agree with the wire precision.
        var now = SyncComposer.WholeSecond(clock.GetUtcNow());
        var window = options.ThrottleWindow;

        var install = await store.FindInstallAsync(installId, cancellationToken);
        if (install is null)
        {
            return SyncInstallGone.Instance;
        }

        if (!SyncComposer.ThrottleAllows(install.LastSyncAt, now, window))
        {
            return Throttle(now, install.LastSyncAt, window);
        }

        // Read phase. Catalog, flags and the entitlement block are required: a failure is a 503 with nothing written, never
        // a null block that the app would read as "up to date". Prices degrade to null.
        var catalogBlock = await RequiredAsync(SyncTags.CatalogBlock, () => CatalogAsync(request.CatalogVersion, cancellationToken));
        var stored = await RequiredAsync(SyncTags.FlagsBlock, () => flags.ListAsync(cancellationToken));
        var snapshot = FlagEvaluator.Snapshot(stored, install.Platform, appVersion, installId);
        foreach (var key in snapshot.InvalidRules)
        {
            telemetry.FlagRulesInvalid(key);
        }

        var pricesBlock = await PricesAsync(cancellationToken);
        var categoryCodes = request.Contributions.Count == 0
            ? (IReadOnlySet<string>)new HashSet<string>(StringComparer.Ordinal)
            : await RequiredAsync(SyncTags.CatalogBlock, () => catalog.CategoryCodesAsync(cancellationToken));
        var entitlementResult = await RequiredAsync(
            SyncTags.EntitlementBlock,
            () => entitlement.ComposeAsync(new SyncEntitlementContext(installId, request.EntitlementIssuedAt, now, request.AccountToken), cancellationToken));

        // Intake preparation: CPU only, then one keyed hash when there is anything to store.
        // Nothing is counted until the claim wins (FU-061): a call that turns into the throttle answer, or a retry after a 503,
        // would otherwise count the same items again.
        var intake = SyncIntake.Prepare(request.Contributions, request.BankRequests, categoryCodes);
        var hasherDroppedContributions = 0;
        var hasherDroppedBankRequests = 0;
        byte[]? installHash = null;
        if (!intake.IsEmpty)
        {
            installHash = await HashAsync(installId, cancellationToken);
            if (installHash is null)
            {
                hasherDroppedContributions = intake.Contributions.Count;
                hasherDroppedBankRequests = intake.BankRequests.Count;
                intake = intake with { Contributions = [], BankRequests = [] };
            }
        }

        var claim = await store.ClaimAsync(
            new SyncClaim(
                installId,
                now,
                window,
                request.CatalogVersion,
                install.Platform,
                appVersion,
                installHash is null ? (ReadOnlyMemory<byte>?)null : new ReadOnlyMemory<byte>(installHash),
                intake.Contributions,
                intake.BankRequests),
            cancellationToken);
        if (!claim.Claimed)
        {
            // A concurrent sync of this install won the window (or the install was deleted meanwhile).
            var current = await store.FindInstallAsync(installId, cancellationToken);
            return current is null ? SyncInstallGone.Instance : Throttle(now, current.LastSyncAt, window);
        }

        ReportDrops(SyncTags.Contribution, intake.ContributionDrops);
        ReportDrops(SyncTags.BankRequest, intake.BankRequestDrops);
        telemetry.Intake(SyncTags.Contribution, SyncTags.DroppedHasher, hasherDroppedContributions);
        telemetry.Intake(SyncTags.BankRequest, SyncTags.DroppedHasher, hasherDroppedBankRequests);
        telemetry.Intake(SyncTags.Contribution, SyncTags.Accepted, claim.ContributionsInserted);
        telemetry.Intake(SyncTags.Contribution, SyncTags.Duplicate, intake.Contributions.Count - claim.ContributionsInserted);
        telemetry.Intake(SyncTags.BankRequest, SyncTags.Accepted, claim.BankRequestsInserted);
        telemetry.Intake(SyncTags.BankRequest, SyncTags.Duplicate, intake.BankRequests.Count - claim.BankRequestsInserted);
        telemetry.Catalog(catalogBlock?.Mode ?? CatalogModes.None);
        telemetry.Request(SyncTags.Ok);

        return new SyncCompleted(
            now,
            now + window,
            catalogBlock,
            SyncComposer.SendFlags(snapshot, request.FlagsVersion, appVersion, install.AppVersion) ? snapshot : null,
            SyncComposer.SendPrices(pricesBlock, request.PricesAsOf) ? pricesBlock : null,
            entitlementResult,
            new SyncAcceptedCounts(claim.ContributionsInserted, claim.BankRequestsInserted));
    }

    private SyncThrottled Throttle(DateTimeOffset now, DateTimeOffset? lastSyncAt, TimeSpan window)
    {
        telemetry.Request(SyncTags.Throttled);
        return new SyncThrottled(now, lastSyncAt is { } last ? SyncComposer.WholeSecond(last + window) : now + window);
    }

    private async Task<SyncCatalogBlock?> CatalogAsync(int clientVersion, CancellationToken cancellationToken)
    {
        var latest = await catalog.LatestVersionAsync(cancellationToken);
        var mode = SyncComposer.CatalogMode(clientVersion, latest);
        if (mode == CatalogModes.None)
        {
            return null;
        }

        if (mode == CatalogModes.Delta)
        {
            var ops = await catalog.DeltaAsync(clientVersion, latest, cancellationToken);
            if (!SyncComposer.DeltaTooLarge(ops.Count, options.MaxDeltaOps))
            {
                return new SyncCatalogBlock(clientVersion, latest, CatalogModes.Delta, null, ops);
            }
        }

        // A missing version row for the latest published version is a broken catalog, not "nothing to send".
        var info = await catalog.FindVersionAsync(latest, cancellationToken) ?? throw new SyncSourceUnavailableException();
        return new SyncCatalogBlock(clientVersion, latest, CatalogModes.Full, info.SnapshotUrl, []);
    }

    private async Task<PricesBlock?> PricesAsync(CancellationToken cancellationToken)
    {
        try
        {
            return await prices.GetBlockAsync(cancellationToken);
        }
#pragma warning disable CA1031 // Prices are advisory (design note §5): any failure degrades the block to null.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            telemetry.BlockFailed(SyncTags.PricesBlock, ex.GetType().Name);
            return null;
        }
    }

    private async Task<byte[]?> HashAsync(InstallId installId, CancellationToken cancellationToken)
    {
        try
        {
            return await hasher.HashAsync(installId, cancellationToken);
        }
#pragma warning disable CA1031 // A KMS outage drops this call's intake (the app resends next window); the sync succeeds.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            telemetry.InstallHashUnavailable();
            return null;
        }
    }

    private async Task<T> RequiredAsync<T>(string block, Func<Task<T>> read)
    {
        try
        {
            return await read();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            telemetry.BlockFailed(block, ex.GetType().Name);
            throw new SyncSourceUnavailableException(SyncSourceUnavailableException.DefaultMessage, ex);
        }
    }

    private void ReportDrops(string kind, IntakeCounts drops)
    {
        telemetry.Intake(kind, SyncTags.Filtered, drops.Filtered);
        telemetry.Intake(kind, SyncTags.InvalidCode, drops.InvalidCode);
        telemetry.Intake(kind, SyncTags.Duplicate, drops.Duplicate);
    }
}
