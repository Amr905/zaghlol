using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>
/// T-134 design note §2-3: the processor re-reads Apple's current state for each due row and writes it under the monotonic guard;
/// retries, deferrals, the dead letter and the refund floor. Apple is <see cref="FakeAppStoreServerApi"/> with
/// <see cref="FakeAppleJwsVerifier"/>; the rows are <see cref="FakeNotificationStore"/>.
/// </summary>
public class AppleNotificationProcessorTests
{
    private readonly FixedClock clock = new(AppleScript.Now);
    private readonly AppleScript apple = new();
    private readonly RecordingPurchaseTelemetry purchaseTelemetry = new();
    private readonly RecordingNotificationTelemetry telemetry = new();
    private readonly FakeNotificationStore store;

    public AppleNotificationProcessorTests() => store = new FakeNotificationStore(clock);

    // AC 1.

    [Fact]
    public async Task ARefundOfASubscriptionMarksThePurchaseRefundedWithAnAssnEvent()
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        AppleSays(purchase, status: 5, revoked: true, refundReason: 1);
        var row = store.Add("REFUND", purchase.StoreKey);

        var run = await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Refunded, purchase.State);
        Assert.Equal((purchase.Id, StoredPurchaseState.Active, StoredPurchaseState.Refunded, "assn:REFUND"), Assert.Single(store.Events));
        Assert.NotNull(row.ProcessedAt);
        Assert.Null(row.LastError);
        Assert.Equal(1, run.Applied);
        Assert.Contains(("refund", AssnTags.Applied), telemetry.Processed);
        Assert.All(apple.Api.Calls, c => Assert.Equal(StoreLane.Notification, c.Lane));
    }

    [Fact]
    public async Task ARefundOfALifetimePurchaseMarksItRefunded()
    {
        var purchase = store.AddPurchase(AppleScript.NewId(), AppleScript.Lifetime, GoldPlan.Lifetime, StoredPurchaseState.Active);
        LifetimeSays(purchase, revoked: true);
        store.Add("REFUND", purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Refunded, purchase.State);
        Assert.Equal("assn:REFUND", Assert.Single(store.Events).Cause);
        Assert.Equal(1, apple.Api.CallsTo(AppStoreApi.TransactionInfo));
        Assert.Equal(0, apple.Api.CallsTo(AppStoreApi.SubscriptionStatuses));
    }

    // §2 expected-outcomes table: the write is always Apple's current answer.

    [Theory]
    [InlineData("SUBSCRIBED", 1, 1, null, StoredPurchaseState.Active)]
    [InlineData("DID_RENEW", 1, 1, null, StoredPurchaseState.Active)]
    [InlineData("OFFER_REDEEMED", 1, 1, null, StoredPurchaseState.Active)]
    [InlineData("RENEWAL_EXTENDED", 1, 1, null, StoredPurchaseState.Active)]
    [InlineData("DID_CHANGE_RENEWAL_STATUS", 1, 0, null, StoredPurchaseState.CanceledActive)]
    [InlineData("DID_FAIL_TO_RENEW", 4, 1, 3, StoredPurchaseState.InGrace)]
    [InlineData("DID_FAIL_TO_RENEW", 3, 1, null, StoredPurchaseState.OnHold)]
    [InlineData("GRACE_PERIOD_EXPIRED", 3, 1, null, StoredPurchaseState.OnHold)]
    [InlineData("GRACE_PERIOD_EXPIRED", 2, 0, null, StoredPurchaseState.Expired)]
    [InlineData("EXPIRED", 2, 0, null, StoredPurchaseState.Expired)]
    [InlineData("REVOKE", 5, 0, null, StoredPurchaseState.Revoked)]
    public async Task EachNotificationWritesApplesCurrentAnswer(string type, int status, int autoRenew, int? graceDays, StoredPurchaseState expected)
    {
        var start = expected == StoredPurchaseState.Active ? StoredPurchaseState.OnHold : StoredPurchaseState.Active;
        var purchase = Subscription(start);
        AppleSays(purchase, status, autoRenew, graceDays, revoked: type == "REVOKE");
        store.Add(type, purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(expected, purchase.State);
        Assert.Equal("assn:" + type, Assert.Single(store.Events).Cause);
    }

    [Fact]
    public async Task AnUpgradeRePlansTheRowFromTheLatestTransaction()
    {
        var purchase = Subscription(StoredPurchaseState.Active, AppleScript.Monthly, GoldPlan.Monthly);
        AppleSays(purchase, 1, 1, productId: AppleScript.Yearly);
        store.Add("DID_CHANGE_RENEWAL_PREF", purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(AppleScript.Yearly, purchase.ProductId);
        Assert.Equal(GoldPlan.Yearly, purchase.Plan);
        Assert.Contains(("did_change_renewal_pref", AssnTags.Unchanged), telemetry.Processed);
    }

    [Fact]
    public async Task OutOfOrderNotificationsConvergeOnApplesCurrentState()
    {
        // EXPIRED arrives after DID_RENEW; Apple now says active: the row stays active.
        var purchase = Subscription(StoredPurchaseState.Active);
        AppleSays(purchase, 1, 1);
        store.Add("DID_RENEW", purchase.StoreKey);
        await Processor().RunOnceAsync(CancellationToken.None);
        clock.Now = clock.Now.AddMinutes(1);
        store.Add("EXPIRED", purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Empty(store.Events);
        Assert.All(store.Notifications, n => Assert.NotNull(n.ProcessedAt));
    }

    [Fact]
    public async Task ARefundReversalRestoresGoldBecauseApplesAnswerWins()
    {
        // PO question 4 (provisional): refunded/revoked are not sticky.
        var purchase = Subscription(StoredPurchaseState.Refunded);
        AppleSays(purchase, 1, 1);
        store.Add("REFUND_REVERSED", purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Equal((purchase.Id, StoredPurchaseState.Refunded, StoredPurchaseState.Active, "assn:REFUND_REVERSED"), Assert.Single(store.Events));
    }

    [Fact]
    public async Task ANewerReadAlreadyStoredWinsAndTheRowIsStillProcessed()
    {
        var purchase = Subscription(StoredPurchaseState.Active, lastVerifiedAt: AppleScript.Now.AddSeconds(5));
        AppleSays(purchase, 2, 0);
        var row = store.Add("EXPIRED", purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.NotNull(row.ProcessedAt);
        Assert.Contains(("expired", AssnTags.Superseded), telemetry.Processed);
    }

    // §2 steps 1-2: no purchase, environment mismatch.

    [Fact]
    public async Task ANotificationWithoutAPurchaseIsRecordedAndNeverCallsApple()
    {
        var row = store.Add("SUBSCRIBED", AppleScript.NewId());

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(AppleNotificationSchedule.NoPurchase, row.LastError);
        Assert.NotNull(row.ProcessedAt);
        Assert.Empty(apple.Api.Calls);
        Assert.Empty(store.Purchases);
    }

    [Fact]
    public async Task AnEnvironmentMismatchIsRecordedAndNeverWritten()
    {
        var purchase = Subscription(StoredPurchaseState.Active, environment: PurchaseEnvironment.Sandbox);
        var row = store.Add("REFUND", purchase.StoreKey, PurchaseEnvironment.Production);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(AppleNotificationSchedule.EnvMismatch, row.LastError);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Empty(apple.Api.Calls);
        Assert.Contains(("refund", AssnTags.EnvMismatch), telemetry.Processed);
    }

    // §3 retries and the dead letter.

    [Fact]
    public async Task AnUnmappedAnswerIsRetriedOnTheScheduleAndDeadLetteredAtTheTenthFailure()
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        AppleSays(purchase, status: 99, autoRenew: 1);
        var row = store.Add("DID_RENEW", purchase.StoreKey);

        await Processor(jitter: 0.5).RunOnceAsync(CancellationToken.None);
        Assert.Equal(1, row.Attempts);
        Assert.Equal(AppleNotificationSchedule.Unmapped, row.LastError);
        Assert.Equal(clock.Now.AddMinutes(1), row.NextAttemptAt);
        Assert.Null(row.ProcessedAt);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);

        for (var attempt = 2; attempt <= 10; attempt++)
        {
            clock.Now = row.NextAttemptAt ?? clock.Now;
            await Processor(jitter: 0.5).RunOnceAsync(CancellationToken.None);
            Assert.Equal(attempt, row.Attempts);
        }

        Assert.NotNull(row.ProcessedAt);
        Assert.Null(row.NextAttemptAt);
        Assert.Equal(AppleNotificationSchedule.Unmapped, row.LastError);
        Assert.Equal(1, telemetry.DeadLetters);
        Assert.Contains(("did_renew", AssnTags.DeadLetter), telemetry.Processed);
        Assert.Empty(store.Events);
        Assert.InRange(clock.Now - AppleScript.Now, TimeSpan.FromHours(28), TimeSpan.FromHours(31));
    }

    public static TheoryData<AppStoreCallOutcome, int?, int?, string> CountedFailures => new()
    {
        { AppStoreCallOutcome.ServerError, 503, null, AppleNotificationSchedule.StoreError },
        { AppStoreCallOutcome.Timeout, null, null, AppleNotificationSchedule.StoreError },
        { AppStoreCallOutcome.ClientError, 400, null, AppleNotificationSchedule.StoreError },
        { AppStoreCallOutcome.AuthError, 401, null, AppleNotificationSchedule.StoreAuth },
        { AppStoreCallOutcome.ClientError, 404, AppStoreApiException.TransactionIdNotFound, AppleNotificationSchedule.NotFound },
    };

    [Theory]
    [MemberData(nameof(CountedFailures))]
    public async Task AStoreFailureIsACountedRetry(AppStoreCallOutcome outcome, int? status, int? errorCode, string code)
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        apple.Api.Errors[AppStoreApi.SubscriptionStatuses] = new AppStoreApiException(AppStoreApi.SubscriptionStatuses, outcome, status, errorCode);
        var row = store.Add("DID_RENEW", purchase.StoreKey, attempts: 2);

        await Processor(jitter: 0).RunOnceAsync(CancellationToken.None);

        Assert.Equal(3, row.Attempts);
        Assert.Equal(code, row.LastError);
        Assert.Equal(clock.Now + TimeSpan.FromMinutes(9 * 0.9), row.NextAttemptAt);
        Assert.Null(row.ProcessedAt);
    }

    [Fact]
    public async Task AFailedApiJwsOrAContradictionIsACountedRetry()
    {
        var bad = Subscription(StoredPurchaseState.Active);
        AppleSays(bad, 1, 1);
        apple.Jws.Failures["latest:" + bad.StoreKey] = AppleJwsFailure.Chain;
        var other = Subscription(StoredPurchaseState.Active);
        AppleSays(other, 1, 1);
        apple.Jws.Transactions["latest:" + other.StoreKey] = apple.Jws.Transactions["latest:" + other.StoreKey] with { BundleId = "com.other.app" };
        var badRow = store.Add("DID_RENEW", bad.StoreKey);
        var otherRow = store.Add("DID_RENEW", other.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(AppleNotificationSchedule.JwsApi, badRow.LastError);
        Assert.Equal(AppleNotificationSchedule.Contradiction, otherRow.LastError);
        Assert.Contains((JwsSource.Api, AppleJwsFailure.Chain), purchaseTelemetry.Jws);
        Assert.Contains((JwsSource.Api, AppleJwsFailure.Payload), purchaseTelemetry.Jws);
    }

    [Fact]
    public async Task AppleRateLimitingDefersByRetryAfterWithoutCountingAndStopsTheRun()
    {
        var first = Subscription(StoredPurchaseState.Active);
        var second = Subscription(StoredPurchaseState.Active);
        apple.Api.Errors[AppStoreApi.SubscriptionStatuses] = new AppStoreApiException(AppStoreApi.SubscriptionStatuses, AppStoreCallOutcome.RateLimited, 429, null, TimeSpan.FromSeconds(120));
        var a = store.Add("DID_RENEW", first.StoreKey, attempts: 3);
        var b = store.Add("DID_RENEW", second.StoreKey);

        var run = await Processor().RunOnceAsync(CancellationToken.None);

        Assert.True(run.Stopped);
        Assert.Equal(3, a.Attempts);
        Assert.Equal(clock.Now.AddSeconds(120), a.NextAttemptAt);
        Assert.Null(b.NextAttemptAt);
        Assert.Single(apple.Api.Calls);
        Assert.Contains(("did_renew", AssnTags.Deferred), telemetry.Processed);
    }

    [Theory]
    [InlineData(AppStoreCallOutcome.BudgetDenied)]
    [InlineData(AppStoreCallOutcome.CircuitOpen)]
    public async Task OurBudgetOrAnOpenCircuitDefersOneMinuteWithoutCounting(AppStoreCallOutcome outcome)
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        apple.Api.Errors[AppStoreApi.SubscriptionStatuses] = new AppStoreApiException(AppStoreApi.SubscriptionStatuses, outcome);
        var row = store.Add("DID_RENEW", purchase.StoreKey);

        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, row.Attempts);
        Assert.Equal(clock.Now.AddMinutes(1), row.NextAttemptAt);
    }

    [Theory]
    [InlineData(null, 60)]
    [InlineData(5, 60)]
    [InlineData(7200, 3600)]
    public void A429IsDeferredBetweenOneMinuteAndOneHour(int? retryAfterSeconds, int expectedSeconds) =>
        Assert.Equal(
            TimeSpan.FromSeconds(expectedSeconds),
            AppleNotificationSchedule.RateLimitedDelay(retryAfterSeconds is { } s ? TimeSpan.FromSeconds(s) : null));

    // §2 step 5: the refund floor.

    [Fact]
    public async Task ARefundApplesApiDoesNotYetReflectIsRetriedFourTimesThenAppliedAndAlerted()
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        AppleSays(purchase, 1, 1);
        var row = store.Add("REFUND", purchase.StoreKey);

        for (var attempt = 1; attempt <= AppleNotificationSchedule.RefundFloorAttempts; attempt++)
        {
            await Processor(jitter: 0.5).RunOnceAsync(CancellationToken.None);
            Assert.Equal(attempt, row.Attempts);
            Assert.Equal(AppleNotificationSchedule.RefundNotReflected, row.LastError);
            clock.Now = row.NextAttemptAt!.Value;
        }

        Assert.Equal(0, telemetry.RefundsNotReflected);
        await Processor().RunOnceAsync(CancellationToken.None);

        Assert.NotNull(row.ProcessedAt);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Equal(1, telemetry.RefundsNotReflected);
        Assert.InRange(clock.Now - AppleScript.Now, TimeSpan.FromMinutes(36), TimeSpan.FromMinutes(44));
    }

    // Concurrency and housekeeping.

    [Fact]
    public async Task OnlyTheAdvisoryLockHolderRuns()
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        var row = store.Add("REFUND", purchase.StoreKey);
        store.LockTakenElsewhere = true;

        var run = await Processor().RunOnceAsync(CancellationToken.None);

        Assert.False(run.Ran);
        Assert.Null(row.ProcessedAt);
        Assert.Empty(apple.Api.Calls);
        Assert.Equal(AppleNotificationProcessor.LockName, Assert.Single(store.LocksTaken));
    }

    [Fact]
    public async Task ARunStopsAtTheBatchSizeAndSetsTheBacklogGauge()
    {
        for (var i = 0; i < AppleNotificationProcessor.BatchSize + 3; i++)
        {
            store.Add("SUBSCRIBED", AppleScript.NewId());
        }

        var run = await Processor().RunOnceAsync(CancellationToken.None);

        Assert.Equal(AppleNotificationProcessor.BatchSize, run.Rows);
        Assert.Equal((3L, 0L), telemetry.Backlog);
    }

    [Fact]
    public async Task ACancelledCallLeavesTheRowToBePickedAgain()
    {
        var purchase = Subscription(StoredPurchaseState.Active);
        var row = store.Add("REFUND", purchase.StoreKey);
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();
        var cancelling = new AppleNotificationProcessor(store, new AppleStateRefresher(new AppleSubscriptionReader(apple.Jws, new CancellingApi(), AppleScript.Catalog(), purchaseTelemetry), AppleScript.Catalog()), telemetry, clock);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cancelling.RunOnceAsync(cancelled.Token));

        Assert.Null(row.ProcessedAt);
        Assert.Equal(0, row.Attempts);
        Assert.Null(row.NextAttemptAt);
    }

    [Fact]
    public void TheBackoffScheduleIsOneMinuteTimesThreeCappedAtEightHours()
    {
        double[] minutes = [1, 3, 9, 27, 81, 243, 480, 480, 480];
        for (var attempt = 1; attempt <= minutes.Length; attempt++)
        {
            Assert.Equal(TimeSpan.FromMinutes(minutes[attempt - 1]), AppleNotificationSchedule.Backoff(attempt));
        }

        var now = AppleScript.Now;
        Assert.Equal(now + TimeSpan.FromMinutes(27 * 0.9), AppleNotificationSchedule.NextAttemptAt(4, now, 0));
        Assert.Equal(now + TimeSpan.FromMinutes(27 * 1.1), AppleNotificationSchedule.NextAttemptAt(4, now, 1));
        Assert.Equal(TimeSpan.FromHours(8), AppleNotificationSchedule.Backoff(50));
    }

    private AppleNotificationProcessor Processor(double jitter = 0.5) =>
        new(store, new AppleStateRefresher(new AppleSubscriptionReader(apple.Jws, apple.Api, AppleScript.Catalog(), purchaseTelemetry), AppleScript.Catalog()), telemetry, clock, () => jitter);

    private FakeNotificationStore.Purchase Subscription(
        StoredPurchaseState state,
        string productId = AppleScript.Yearly,
        GoldPlan plan = GoldPlan.Yearly,
        PurchaseEnvironment environment = PurchaseEnvironment.Production,
        DateTimeOffset? lastVerifiedAt = null) =>
        store.AddPurchase(AppleScript.NewId(), productId, plan, state, environment, lastVerifiedAt);

    /// <summary>Apple's Get All Subscription Statuses answer for the purchase (queried by its originalTransactionId).</summary>
    private void AppleSays(
        FakeNotificationStore.Purchase purchase,
        int status,
        int autoRenew = 1,
        int? graceDays = null,
        bool revoked = false,
        int? refundReason = null,
        string? productId = null)
    {
        var latest = AppleScript.Tx(
            AppleScript.NewId(),
            purchase.StoreKey,
            null,
            productId ?? purchase.ProductId,
            purchase.Environment == PurchaseEnvironment.Sandbox ? AppleEnvironment.Sandbox : AppleEnvironment.Production,
            reason: AppleTransactionReason.Renewal,
            expiresDate: AppleScript.Now.AddDays(status is 1 or 4 ? 20 : -1),
            revocationDate: revoked ? AppleScript.Now.AddMinutes(-5) : null,
            revocationReason: refundReason);
        apple.Status(latest, status, autoRenew, graceDays is { } d ? AppleScript.Now.AddDays(d) : null, forTransactionId: purchase.StoreKey);
    }

    private void LifetimeSays(FakeNotificationStore.Purchase purchase, bool revoked)
    {
        var copy = AppleScript.Tx(
            purchase.StoreKey,
            purchase.StoreKey,
            null,
            AppleScript.Lifetime,
            type: AppleProductType.NonConsumable,
            revocationDate: revoked ? AppleScript.Now.AddMinutes(-5) : null,
            revocationReason: revoked ? 0 : null);
        apple.Jws.Transactions["api:" + purchase.StoreKey] = copy;
        apple.Api.TransactionInfo[(PurchaseEnvironment.Production, purchase.StoreKey)] = "api:" + purchase.StoreKey;
    }

    /// <summary>Honours cancellation like the real client (a crash or shutdown mid-call).</summary>
    private sealed class CancellingApi : IAppStoreServerApi
    {
        public Task<Sensitive<string>> GetTransactionInfoAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken) =>
            Task.FromCanceled<Sensitive<string>>(cancellationToken);

        public Task<IReadOnlyList<AppleLastTransaction>> GetAllSubscriptionStatusesAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken) =>
            Task.FromCanceled<IReadOnlyList<AppleLastTransaction>>(cancellationToken);

        public Task<AppleOrderLookupResult> LookUpOrderIdAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<AppleNotificationHistoryPage> GetNotificationHistoryAsync(PurchaseEnvironment environment, DateTimeOffset startDate, DateTimeOffset endDate, Sensitive<string>? paginationToken, StoreLane lane, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
