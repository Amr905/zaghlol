using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-134 design note §4: the daily Get Notification History job and the hourly expiry sweep.</summary>
public class AppleReconciliationJobTests
{
    private readonly FixedClock clock = new(AppleScript.Now);
    private readonly AppleScript apple = new();
    private readonly FakeInbox inbox = new();
    private readonly RecordingPurchaseTelemetry purchaseTelemetry = new();
    private readonly RecordingNotificationTelemetry telemetry = new();
    private readonly FakeNotificationStore store;

    public AppleReconciliationJobTests() => store = new FakeNotificationStore(clock);

    [Fact]
    public async Task HistoryFollowsPagesThroughTheSameIngestAndCountsOnlyNewRowsAsRecovered()
    {
        var known = Notification("DID_RENEW");
        var fresh = Notification("REFUND");
        var ingest = Ingest();
        await ingest.IngestAsync(new Sensitive<string>(known), CancellationToken.None);
        apple.Api.History[PurchaseEnvironment.Production] =
        [
            new([new(known)], true, new Sensitive<string>("1")),
            new([new(fresh)], false, null),
        ];

        var run = await History(allowSandbox: false, ingest).RunOnceAsync(CancellationToken.None);

        Assert.True(run.Ran);
        Assert.Equal(2, run.Read);
        Assert.Equal(1, run.Inserted);
        Assert.Equal(1, telemetry.RecoveredTotal);
        Assert.Equal(2, inbox.Rows.Count);
        var requests = apple.Api.HistoryRequests.ToList();
        Assert.Equal(2, requests.Count);
        Assert.All(requests, r => Assert.Equal(PurchaseEnvironment.Production, r.Environment));
        Assert.Equal([null, "1"], requests.Select(r => r.Token));
        Assert.All(requests, r => Assert.Equal(AppleScript.Now.AddDays(-7), r.Start));
        Assert.All(requests, r => Assert.Equal(AppleScript.Now.AddMinutes(-5), r.End));
        Assert.All(apple.Api.Calls, c => Assert.Equal(StoreLane.Notification, c.Lane));
        Assert.Contains((AssnTags.StepHistory, AssnTags.ReconcileOk), telemetry.Reconciles);
    }

    [Fact]
    public async Task AnEntryFailingVerificationIsSkippedAndAlerted()
    {
        apple.Jws.Failures["tampered"] = AppleJwsFailure.Signature;
        var good = Notification("EXPIRED");
        apple.Api.History[PurchaseEnvironment.Production] = [new([new("tampered"), new(good)], false, null)];

        var run = await History(allowSandbox: false).RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Inserted);
        Assert.Equal(1, run.Failed);
        Assert.Contains((AssnTags.StepHistory, AssnTags.ReconcileInvalidEntry), telemetry.Reconciles);
    }

    [Theory]
    [InlineData(false, 1)]
    [InlineData(true, 2)]
    public async Task SandboxIsQueriedOnlyWhileSandboxIsAllowed(bool allowSandbox, int environments)
    {
        await History(allowSandbox).RunOnceAsync(CancellationToken.None);

        var queried = apple.Api.HistoryRequests.Select(r => r.Environment).Distinct().ToList();
        Assert.Equal(environments, queried.Count);
        Assert.Equal(allowSandbox, queried.Contains(PurchaseEnvironment.Sandbox));
    }

    [Fact]
    public async Task MoreThanTwentyPagesStopsAtTheCapAndAlerts()
    {
        apple.Api.History[PurchaseEnvironment.Production] =
            [.. Enumerable.Range(0, 30).Select(i => new AppleNotificationHistoryPage([], true, new Sensitive<string>((i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture))))];

        await History(allowSandbox: false).RunOnceAsync(CancellationToken.None);

        Assert.Equal(AppleNotificationHistoryJob.MaxPages, apple.Api.HistoryRequests.Count);
        Assert.Contains((AssnTags.StepHistory, AssnTags.ReconcileTruncated), telemetry.Reconciles);
    }

    [Fact]
    public async Task AnAppleFailureEndsTheEnvironmentAndIsCounted()
    {
        apple.Api.Errors[AppStoreApi.NotificationHistory] = new AppStoreApiException(AppStoreApi.NotificationHistory, AppStoreCallOutcome.ServerError, 500);

        var run = await History(allowSandbox: true).RunOnceAsync(CancellationToken.None);

        Assert.Equal(2, run.Failed);
        Assert.Equal(2, telemetry.Reconciles.Count(r => r == (AssnTags.StepHistory, AssnTags.ReconcileFailed)));
    }

    [Fact]
    public async Task WithoutABundleIdNothingIsFetched()
    {
        var catalog = new AppStoreCatalog(string.Empty, AppleScript.Catalog().Products, true);
        var job = new AppleNotificationHistoryJob(store, apple.Api, Ingest(), catalog, telemetry, clock);

        Assert.False((await job.RunOnceAsync(CancellationToken.None)).Ran);
        Assert.Empty(apple.Api.Calls);
    }

    [Fact]
    public async Task TheExpirySweepWritesApplesAnswerWithCauseSweep()
    {
        var renewed = store.AddPurchase(AppleScript.NewId(), AppleScript.Yearly, GoldPlan.Yearly, StoredPurchaseState.Active);
        var expired = store.AddPurchase(AppleScript.NewId(), AppleScript.Monthly, GoldPlan.Monthly, StoredPurchaseState.CanceledActive);
        Says(renewed, 1, 1);
        Says(expired, 2, 0);
        store.Expired.AddRange([FakeNotificationStore.Row(renewed), FakeNotificationStore.Row(expired)]);

        var run = await Sweep().RunOnceAsync(CancellationToken.None);

        Assert.Equal(2, run.Inserted);
        Assert.Equal(StoredPurchaseState.Active, renewed.State);
        Assert.Equal(StoredPurchaseState.Expired, expired.State);
        Assert.Equal((expired.Id, StoredPurchaseState.CanceledActive, StoredPurchaseState.Expired, "sweep"), Assert.Single(store.Events));
        Assert.Empty(store.Notifications);
        Assert.Equal(AppleExpirySweepJob.LockName, Assert.Single(store.LocksTaken));
    }

    [Fact]
    public async Task TheExpirySweepStopsOnADeferralAndSkipsAFailure()
    {
        var failing = store.AddPurchase(AppleScript.NewId(), AppleScript.Yearly, GoldPlan.Yearly, StoredPurchaseState.Active);
        apple.Jws.Failures["latest:" + failing.StoreKey] = AppleJwsFailure.Chain;
        Says(failing, 1, 1);
        apple.Jws.Failures["latest:" + failing.StoreKey] = AppleJwsFailure.Chain;
        store.Expired.Add(FakeNotificationStore.Row(failing));

        var run = await Sweep().RunOnceAsync(CancellationToken.None);
        Assert.Equal(1, run.Failed);
        Assert.Equal(StoredPurchaseState.Active, failing.State);

        apple.Api.Errors[AppStoreApi.SubscriptionStatuses] = new AppStoreApiException(AppStoreApi.SubscriptionStatuses, AppStoreCallOutcome.RateLimited, 429);
        store.Expired.Add(FakeNotificationStore.Row(failing));
        var before = apple.Api.Calls.Count;
        await Sweep().RunOnceAsync(CancellationToken.None);

        Assert.Equal(before + 1, apple.Api.Calls.Count);
        Assert.Contains((AssnTags.StepExpiry, AssnTags.Deferred), telemetry.Reconciles);
    }

    private AppleNotificationIngest Ingest(bool allowSandbox = true) =>
        new(apple.Jws, AppleScript.Catalog(allowSandbox), inbox, purchaseTelemetry, telemetry, clock);

    private AppleNotificationHistoryJob History(bool allowSandbox, AppleNotificationIngest? ingest = null) =>
        new(store, apple.Api, ingest ?? Ingest(allowSandbox), AppleScript.Catalog(allowSandbox), telemetry, clock);

    private AppleExpirySweepJob Sweep() =>
        new(store, new AppleStateRefresher(new AppleSubscriptionReader(apple.Jws, apple.Api, AppleScript.Catalog(), purchaseTelemetry), AppleScript.Catalog()), telemetry, clock);

    /// <summary>A verified-looking ASSN payload for the fake verifier; returns its key.</summary>
    private string Notification(string type)
    {
        var uuid = Guid.NewGuid();
        var original = AppleScript.NewId();
        apple.Jws.Transactions["ntx:" + uuid] = AppleScript.Tx(AppleScript.NewId(), original, null);
        apple.Jws.Notifications["n:" + uuid] = new AppleNotification(
            type,
            null,
            uuid.ToString("D"),
            "2.0",
            AppleScript.Now.AddDays(-2),
            new AppleNotificationData(AppleScript.Bundle, "Production", 1, new Sensitive<string>("ntx:" + uuid), null));
        return "n:" + uuid;
    }

    private void Says(FakeNotificationStore.Purchase purchase, int status, int autoRenew)
    {
        var latest = AppleScript.Tx(
            AppleScript.NewId(),
            purchase.StoreKey,
            null,
            purchase.ProductId,
            reason: AppleTransactionReason.Renewal,
            expiresDate: AppleScript.Now.AddDays(status == 1 ? 30 : -1));
        apple.Status(latest, status, autoRenew, forTransactionId: purchase.StoreKey);
    }
}
