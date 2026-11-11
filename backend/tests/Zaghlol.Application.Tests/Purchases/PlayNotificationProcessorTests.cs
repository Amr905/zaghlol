using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>
/// T-133 design note §3 and §5: the Google processor re-reads Play for every reconcile-set row and writes Play's answer under the guard,
/// the label rule chooses refunded/revoked, step 0 refuses non-ingest rows without a call, one throwing row never stops the run, and the
/// refund floor is time-based.
/// </summary>
public class PlayNotificationProcessorTests
{
    private readonly FixedClock clock = new(Play.Now);
    private readonly FakePlayDeveloperApi play = new();
    private readonly RecordingPlayTelemetry telemetry = new();
    private readonly FakePlayNotificationStore store;

    public PlayNotificationProcessorTests() => store = new FakePlayNotificationStore(clock);

    private PlayNotificationProcessor Processor => new(store, new PlayPurchaseReader(play), Play.Catalog, telemetry, clock, () => 0.5);

    public static TheoryData<string, PlaySubscriptionState, int, StoredPurchaseState, StoredPurchaseState> SubscriptionTable => new()
    {
        // type, Play state, expiry offset (days), stored before, expected after
        { "SUBSCRIPTION_RENEWED", PlaySubscriptionState.Active, 30, StoredPurchaseState.InGrace, StoredPurchaseState.Active },
        { "SUBSCRIPTION_RECOVERED", PlaySubscriptionState.Active, 30, StoredPurchaseState.OnHold, StoredPurchaseState.Active },
        { "SUBSCRIPTION_RESTARTED", PlaySubscriptionState.Active, 30, StoredPurchaseState.CanceledActive, StoredPurchaseState.Active },
        { "SUBSCRIPTION_PURCHASED", PlaySubscriptionState.Active, 30, StoredPurchaseState.Pending, StoredPurchaseState.Active },
        { "SUBSCRIPTION_DEFERRED", PlaySubscriptionState.Active, 60, StoredPurchaseState.Active, StoredPurchaseState.Active },
        { "SUBSCRIPTION_CANCELED", PlaySubscriptionState.Canceled, 10, StoredPurchaseState.Active, StoredPurchaseState.CanceledActive },
        { "SUBSCRIPTION_CANCELED", PlaySubscriptionState.Canceled, -1, StoredPurchaseState.Active, StoredPurchaseState.Expired },
        { "SUBSCRIPTION_IN_GRACE_PERIOD", PlaySubscriptionState.InGracePeriod, 3, StoredPurchaseState.Active, StoredPurchaseState.InGrace },
        { "SUBSCRIPTION_ON_HOLD", PlaySubscriptionState.OnHold, -1, StoredPurchaseState.InGrace, StoredPurchaseState.OnHold },
        { "SUBSCRIPTION_PAUSED", PlaySubscriptionState.Paused, -1, StoredPurchaseState.Active, StoredPurchaseState.Paused },
        { "SUBSCRIPTION_EXPIRED", PlaySubscriptionState.Expired, -1, StoredPurchaseState.Active, StoredPurchaseState.Expired },
        { "SUBSCRIPTION_REVOKED", PlaySubscriptionState.Expired, -1, StoredPurchaseState.Active, StoredPurchaseState.Revoked },
        { "VOIDED_PURCHASE", PlaySubscriptionState.Expired, -1, StoredPurchaseState.Active, StoredPurchaseState.Refunded },
        { "SUBSCRIPTION_OTHER", PlaySubscriptionState.Expired, -1, StoredPurchaseState.Active, StoredPurchaseState.Expired },
    };

    /// <summary>§3 "Expected outcomes": each reconcile type ends in Play's state (with the label rule), one Play call, one event.</summary>
    [Theory]
    [MemberData(nameof(SubscriptionTable))]
    public async Task EachSubscriptionTypeEndsInPlaysCurrentState(string type, PlaySubscriptionState playState, int expiryDays, StoredPurchaseState before, StoredPurchaseState after)
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, before, Play.Now.AddDays(-1));
        var expiry = Play.Now.AddDays(expiryDays);
        play.Subscriptions[token] = Play.Subscription(null, playState, expiry: expiry);
        var row = store.Add(type, token);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(after, purchase.State);
        Assert.Equal(expiry, purchase.ExpiresAt);
        Assert.Equal(Play.Now, purchase.LastVerifiedAt);
        Assert.NotNull(row.ProcessedAt);
        Assert.Null(row.LastError);
        var call = Assert.Single(play.Calls);
        Assert.Equal(StoreLane.Notification, call.Lane);
        if (before != after)
        {
            Assert.Equal("rtdn:" + type, Assert.Single(store.Events).Cause);
        }
        else
        {
            Assert.Empty(store.Events);
        }
    }

    /// <summary>AC 1: a voided lifetime purchase (or ONE_TIME_PRODUCT_CANCELED) ends refunded; ONE_TIME_PRODUCT_PURCHASED ends active.</summary>
    [Theory]
    [InlineData("VOIDED_PURCHASE", PlayProductState.Cancelled, StoredPurchaseState.Refunded)]
    [InlineData("ONE_TIME_PRODUCT_CANCELED", PlayProductState.Cancelled, StoredPurchaseState.Refunded)]
    [InlineData("ONE_TIME_PRODUCT_PURCHASED", PlayProductState.Purchased, StoredPurchaseState.Active)]
    public async Task OneTimeProductsFollowPlay(string type, PlayProductState playState, StoredPurchaseState expected)
    {
        var token = Play.NewToken();
        var before = expected == StoredPurchaseState.Active ? StoredPurchaseState.Pending : StoredPurchaseState.Active;
        var purchase = store.AddPurchase(token, Play.Lifetime, before);
        play.Products[token] = Play.Product(null, playState);
        store.Add(type, token);
        clock.Now = Play.Now.AddHours(1);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(expected, purchase.State);
        Assert.Null(purchase.ExpiresAt);
        Assert.Equal(1, play.CallsTo(PlayApi.ProductGet));
    }

    [Fact]
    public async Task OutOfOrderMessagesConvergeOnPlaysAnswer()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Active);

        // An EXPIRED that arrives after a RENEWED, while Play already says ACTIVE: stays active.
        store.Add("SUBSCRIPTION_RENEWED", token);
        store.Add("SUBSCRIPTION_EXPIRED", token);
        await Processor.RunOnceAsync(CancellationToken.None);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);

        // The reverse: a late RENEWED after Play reports EXPIRED: expired.
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1));
        clock.Now = Play.Now.AddMinutes(1);
        store.Add("SUBSCRIPTION_RENEWED", token);
        await Processor.RunOnceAsync(CancellationToken.None);
        Assert.Equal(StoredPurchaseState.Expired, purchase.State);
    }

    [Fact]
    public async Task ANewerStoredReadSupersedesTheWorkerWrite()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active, lastVerifiedAt: Play.Now.AddSeconds(1));
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1));
        var row = store.Add("SUBSCRIPTION_EXPIRED", token);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.NotNull(row.ProcessedAt);
        Assert.Contains(telemetry.Processed, p => p.Outcome == RtdnTags.Superseded);
    }

    /// <summary>FU-092 item 9: no purchase row → NO_PURCHASE, no Play call, nothing inserted (verify decides "new payment").</summary>
    [Fact]
    public async Task ANotificationForAnUnknownTokenIsNoPurchaseWithoutAPlayCall()
    {
        var row = store.Add("SUBSCRIPTION_PURCHASED", Play.NewToken());

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.NoPurchase, row.LastError);
        Assert.NotNull(row.ProcessedAt);
        Assert.Empty(play.Calls);
        Assert.Empty(store.Purchases);
    }

    [Fact]
    public async Task ATestPurchaseForAProductionRowIsEnvMismatchAndNeverWritten()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1), test: true);
        var row = store.Add("SUBSCRIPTION_EXPIRED", token);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Equal(PlayNotificationSchedule.EnvMismatch, row.LastError);
        Assert.Contains(telemetry.Processed, p => p.Outcome == RtdnTags.EnvMismatch);
    }

    public static TheoryData<string> Refusals => new()
    {
        "type_outside_reconcile_set", "environment_set", "subtype_set", "bad_token", "no_token", "voided_key_wrong_type",
        "sweep_key_wrong_type", "plain_key_expiry_sweep", "sweep_key_other_purchase", "voided_key_malformed",
    };

    /// <summary>§3 step 0 (FU-098 I-2): a row the ingest and jobs never produce is REFUSED, alerted, with no Play call and no write.</summary>
    [Theory]
    [MemberData(nameof(Refusals))]
    public async Task ARowTheIngestNeverProducesIsRefusedWithoutAPlayCall(string refusal)
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active, Play.Now.AddDays(-1));
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1));
        var row = refusal switch
        {
            "type_outside_reconcile_set" => store.Add("TEST", token),
            "environment_set" => store.Add("SUBSCRIPTION_EXPIRED", token, environment: PurchaseEnvironment.Production),
            "subtype_set" => store.Add("SUBSCRIPTION_EXPIRED", token, subtype: "X"),
            "bad_token" => store.Add("SUBSCRIPTION_EXPIRED", "../" + token),
            "no_token" => store.Add("SUBSCRIPTION_EXPIRED", null),
            "voided_key_wrong_type" => store.Add("SUBSCRIPTION_EXPIRED", token, "voided:" + new string('a', 64)),
            "sweep_key_wrong_type" => store.Add("SUBSCRIPTION_EXPIRED", token, PlayJobKeys.Sweep(purchase.Id, Play.Now)),
            "plain_key_expiry_sweep" => store.Add("EXPIRY_SWEEP", token, "abc123"),
            "sweep_key_other_purchase" => store.Add("EXPIRY_SWEEP", token, PlayJobKeys.Sweep(Guid.CreateVersion7(), Play.Now)),
            "voided_key_malformed" => store.Add("VOIDED_PURCHASE", token, "voided:XYZ"),
            _ => throw new ArgumentOutOfRangeException(nameof(refusal)),
        };

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.Refused, row.LastError);
        Assert.NotNull(row.ProcessedAt);
        Assert.Empty(play.Calls);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Contains(telemetry.Processed, p => p.Outcome == RtdnTags.Refused);
    }

    [Fact]
    public async Task TheJobKeysAreAcceptedForTheirTypes()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-1));
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddHours(-1));
        var sweep = store.Add("EXPIRY_SWEEP", token, PlayJobKeys.Sweep(purchase.Id, Play.Now.AddHours(-1)));

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Null(sweep.LastError);
        Assert.Equal(StoredPurchaseState.Expired, purchase.State);
        Assert.Equal("sweep", Assert.Single(store.Events).Cause);
    }

    /// <summary>FU-098 code 2: an exception on row 1 is INTERNAL (counted); row 2 is still applied; the gauge and heartbeat are refreshed.</summary>
    [Fact]
    public async Task OneThrowingRowIsInternalAndTheRunGoesOn()
    {
        var bad = Play.NewToken();
        var good = Play.NewToken();
        store.ThrowOnFind = bad;
        var purchase = store.AddPurchase(good, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[good] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1));
        var first = store.Add("SUBSCRIPTION_EXPIRED", bad, receivedAt: Play.Now.AddMinutes(-2));
        store.Add("SUBSCRIPTION_EXPIRED", good, receivedAt: Play.Now.AddMinutes(-1));

        var run = await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.Internal, first.LastError);
        Assert.Equal(1, first.Attempts);
        Assert.Null(first.ProcessedAt);
        Assert.Equal(StoredPurchaseState.Expired, purchase.State);
        Assert.Equal(2, run.Rows);
        Assert.Equal(1, run.Failed);
        Assert.NotNull(telemetry.Backlog);
        Assert.Equal(1, telemetry.Heartbeats);
    }

    [Fact]
    public async Task AFailingBacklogQueryIsCountedAndNeverHidesTheRun()
    {
        store.BacklogThrows = true;

        var run = await Processor.RunOnceAsync(CancellationToken.None);

        Assert.True(run.Ran);
        Assert.Equal(1, telemetry.BacklogFailures);
    }

    [Fact]
    public async Task ALockHeldElsewhereStillBeatsTheHeartbeat()
    {
        store.LockTakenElsewhere = true;

        var run = await Processor.RunOnceAsync(CancellationToken.None);

        Assert.False(run.Ran);
        Assert.Equal(1, telemetry.Heartbeats);
        Assert.Equal([PlayNotificationProcessor.LockName], store.LocksTaken);
    }

    /// <summary>
    /// §3 step 5 (FU-098 nit 6): a void whose read still entitles is retried for 40 minutes from receipt, even after earlier store
    /// errors used attempts up; after that Play's answer is applied and the warning raised.
    /// </summary>
    [Fact]
    public async Task TheRefundFloorIsByTimeNotByAttempts()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Active);
        var row = store.Add("VOIDED_PURCHASE", token, attempts: 6, receivedAt: Play.Now.AddMinutes(-39));

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.RefundNotReflected, row.LastError);
        Assert.Equal(7, row.Attempts);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Equal(0, telemetry.RefundsNotReflected);

        clock.Now = Play.Now.AddMinutes(1);
        row.NextAttemptAt = clock.Now;
        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Null(row.LastError);
        Assert.NotNull(row.ProcessedAt);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
        Assert.Equal(1, telemetry.RefundsNotReflected);
    }

    [Fact]
    public async Task AGoneTokenIsProcessedWithoutAWriteAndAlertedOnlyWhenItStillEntitles()
    {
        var entitling = Play.NewToken();
        var expired = Play.NewToken();
        var a = store.AddPurchase(entitling, Play.Yearly, StoredPurchaseState.Active);
        store.AddPurchase(expired, Play.Yearly, StoredPurchaseState.Expired);
        var first = store.Add("SUBSCRIPTION_EXPIRED", entitling, receivedAt: Play.Now.AddMinutes(-2));
        var second = store.Add("SUBSCRIPTION_EXPIRED", expired, receivedAt: Play.Now.AddMinutes(-1));
        play.Throws.Enqueue(new PlayApiException(PlayApi.SubscriptionGet, PlayCallOutcome.ClientError, 410));
        play.Throws.Enqueue(new PlayApiException(PlayApi.SubscriptionGet, PlayCallOutcome.ClientError, 410));

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.TokenGone, first.LastError);
        Assert.Equal(PlayNotificationSchedule.TokenGone, second.LastError);
        Assert.Equal(StoredPurchaseState.Active, a.State);
        Assert.Equal([RtdnTags.TokenGone, RtdnTags.Unchanged], telemetry.Processed.Select(p => p.Outcome));
    }

    [Theory]
    [InlineData(PlayCallOutcome.ClientError, 404, "NOT_FOUND")]
    [InlineData(PlayCallOutcome.ClientError, 400, "NOT_FOUND")]
    [InlineData(PlayCallOutcome.AuthError, 403, "STORE_AUTH")]
    [InlineData(PlayCallOutcome.ServerError, 503, "STORE_ERROR")]
    [InlineData(PlayCallOutcome.Timeout, null, "STORE_ERROR")]
    public async Task CountedStoreFailuresRetryWithTheSharedSchedule(PlayCallOutcome outcome, int? status, string code)
    {
        var token = Play.NewToken();
        store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        var row = store.Add("SUBSCRIPTION_RENEWED", token);
        play.Throws.Enqueue(new PlayApiException(PlayApi.SubscriptionGet, outcome, status));

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(code, row.LastError);
        Assert.Equal(1, row.Attempts);
        Assert.Equal(Play.Now + StoreNotificationSchedule.Backoff(1), row.NextAttemptAt);
        Assert.Null(row.ProcessedAt);
    }

    [Theory]
    [InlineData(PlayCallOutcome.RateLimited, 120, 120)]
    [InlineData(PlayCallOutcome.BudgetDenied, null, 60)]
    [InlineData(PlayCallOutcome.CircuitOpen, null, 60)]
    public async Task ThrottlesDeferWithoutCountingAndStopTheRun(PlayCallOutcome outcome, int? retryAfterSeconds, int deferSeconds)
    {
        var token = Play.NewToken();
        store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        var first = store.Add("SUBSCRIPTION_RENEWED", token, receivedAt: Play.Now.AddMinutes(-2));
        var second = store.Add("SUBSCRIPTION_RENEWED", token, receivedAt: Play.Now.AddMinutes(-1));
        play.Throws.Enqueue(new PlayApiException(PlayApi.SubscriptionGet, outcome, 429, retryAfterSeconds is { } s ? TimeSpan.FromSeconds(s) : null));

        var run = await Processor.RunOnceAsync(CancellationToken.None);

        Assert.True(run.Stopped);
        Assert.Equal(0, first.Attempts);
        Assert.Equal(Play.Now.AddSeconds(deferSeconds), first.NextAttemptAt);
        Assert.Null(second.NextAttemptAt);
        Assert.Null(second.ProcessedAt);
        Assert.Single(play.Calls);
    }

    [Fact]
    public async Task AnUnmappedStateDeadLettersAtTheTenthAttempt()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Unknown);
        var row = store.Add("SUBSCRIPTION_RENEWED", token, attempts: 9);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.Unmapped, row.LastError);
        Assert.Equal(10, row.Attempts);
        Assert.NotNull(row.ProcessedAt);
        Assert.Equal(1, telemetry.DeadLetters);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
    }

    [Fact]
    public async Task AnotherProductsTokenIsAContradiction()
    {
        var token = Play.NewToken();
        store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, productId: Play.Monthly);
        var row = store.Add("SUBSCRIPTION_EXPIRED", token);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.Contradiction, row.LastError);
    }

    [Fact]
    public async Task AStoredProductOutsideTheCatalogIsUnmappedWithoutACall()
    {
        var token = Play.NewToken();
        store.AddPurchase(token, "zaghlol_gold_removed", StoredPurchaseState.Active);
        var row = store.Add("SUBSCRIPTION_EXPIRED", token);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayNotificationSchedule.Unmapped, row.LastError);
        Assert.Empty(play.Calls);
    }

    [Theory]
    [InlineData(StoredPurchaseState.Pending, StoredPurchaseState.Expired)]
    [InlineData(StoredPurchaseState.Active, StoredPurchaseState.Active)]
    public async Task APendingPurchaseCancelWritesExpiredOnlyFromPending(StoredPurchaseState before, StoredPurchaseState after)
    {
        var token = Play.NewToken();
        var expiry = Play.Now.AddDays(3);
        var purchase = store.AddPurchase(token, Play.Yearly, before, expiry);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.PendingPurchaseCanceled);
        var row = store.Add("SUBSCRIPTION_PENDING_PURCHASE_CANCELED", token);

        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Equal(after, purchase.State);
        Assert.Equal(expiry, purchase.ExpiresAt);
        Assert.NotNull(row.ProcessedAt);
    }

    /// <summary>A later plain EXPIRED re-read never erases the refunded/revoked label (§3 step 6); an entitling read restores Gold.</summary>
    [Fact]
    public async Task TheLabelSurvivesALaterExpiredReadAndAnEntitlingReadWins()
    {
        var token = Play.NewToken();
        var purchase = store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1));
        store.Add("VOIDED_PURCHASE", token);
        await Processor.RunOnceAsync(CancellationToken.None);
        Assert.Equal(StoredPurchaseState.Refunded, purchase.State);

        clock.Now = Play.Now.AddMinutes(1);
        store.Add("SUBSCRIPTION_EXPIRED", token);
        await Processor.RunOnceAsync(CancellationToken.None);
        Assert.Equal(StoredPurchaseState.Refunded, purchase.State);

        // Provisional (PO question 3c): Play reporting the purchase entitling again brings Gold back.
        clock.Now = Play.Now.AddMinutes(2);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Active);
        store.Add("SUBSCRIPTION_RECOVERED", token);
        await Processor.RunOnceAsync(CancellationToken.None);
        Assert.Equal(StoredPurchaseState.Active, purchase.State);
    }

    [Fact]
    public async Task TheSameMessageTwiceIsOneRowAndOnePlayCall()
    {
        var token = Play.NewToken();
        store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.Subscriptions[token] = Play.Subscription(null, PlaySubscriptionState.Active);
        var record = new StoreNotificationRecord(Guid.CreateVersion7(), PurchaseStore.GooglePlay, "m1", "SUBSCRIPTION_RENEWED", null, null, new Sensitive<string>(token), null, Play.Now, new byte[32], false, null);

        Assert.True(await store.TryInsertAsync(record, CancellationToken.None));
        Assert.False(await store.TryInsertAsync(record with { Id = Guid.CreateVersion7() }, CancellationToken.None));
        await Processor.RunOnceAsync(CancellationToken.None);
        await Processor.RunOnceAsync(CancellationToken.None);

        Assert.Single(play.Calls);
    }

    [Fact]
    public void TheSharedScheduleAndCodesAreTheDesignedOnes()
    {
        Assert.Equal(TimeSpan.FromMinutes(40), PlayNotificationSchedule.RefundFloor);
        Assert.Equal(10, StoreNotificationSchedule.MaxAttempts);
        Assert.Equal(["STORE_ERROR", "STORE_AUTH", "NOT_FOUND", "UNMAPPED", "REFUND_NOT_REFLECTED", "CONTRADICTION", "INTERNAL"], PlayNotificationSchedule.FailureCodes);
        Assert.All(PlayNotificationSchedule.FailureCodes.Concat(["NO_PURCHASE", "ENV_MISMATCH", "REFUSED", "TOKEN_GONE"]), c => Assert.Matches("^[A-Z0-9_]{1,64}$", c));
        Assert.Equal(AppleNotificationSchedule.Backoff(5), StoreNotificationSchedule.Backoff(5));
        Assert.All(PlayRtdnTypes.Tags, t => Assert.Matches("^[A-Za-z0-9_:.-]{1,40}$", t));
    }
}

/// <summary>§3 step 6: the label rule as a pure table.</summary>
public class PlayStateSettleTests
{
    public static TheoryData<StoredPurchaseState?, StoredPurchaseState, string?, StoredPurchaseState> Table => new()
    {
        { StoredPurchaseState.Active, StoredPurchaseState.Expired, "VOIDED_PURCHASE", StoredPurchaseState.Refunded },
        { StoredPurchaseState.Active, StoredPurchaseState.Expired, "SUBSCRIPTION_REVOKED", StoredPurchaseState.Revoked },
        { StoredPurchaseState.Active, StoredPurchaseState.Expired, "SUBSCRIPTION_EXPIRED", StoredPurchaseState.Expired },
        { StoredPurchaseState.Refunded, StoredPurchaseState.Expired, null, StoredPurchaseState.Refunded },
        { StoredPurchaseState.Revoked, StoredPurchaseState.Expired, "SUBSCRIPTION_EXPIRED", StoredPurchaseState.Revoked },
        { StoredPurchaseState.Revoked, StoredPurchaseState.Expired, "VOIDED_PURCHASE", StoredPurchaseState.Refunded },
        { StoredPurchaseState.Refunded, StoredPurchaseState.Active, null, StoredPurchaseState.Active },
        { StoredPurchaseState.Refunded, StoredPurchaseState.CanceledActive, "VOIDED_PURCHASE", StoredPurchaseState.CanceledActive },
        { StoredPurchaseState.Revoked, StoredPurchaseState.OnHold, null, StoredPurchaseState.OnHold },
        { StoredPurchaseState.Active, StoredPurchaseState.Refunded, null, StoredPurchaseState.Refunded },
        { null, StoredPurchaseState.Expired, null, StoredPurchaseState.Expired },
        { StoredPurchaseState.Expired, StoredPurchaseState.Expired, null, StoredPurchaseState.Expired },
    };

    [Theory]
    [MemberData(nameof(Table))]
    public void SettleKeepsTheLabelOnlyBetweenNonEntitlingStates(StoredPurchaseState? stored, StoredPurchaseState read, string? type, StoredPurchaseState expected)
    {
        var settled = PlayStateMapping.Settle(stored, read, type);

        Assert.Equal(expected, settled);

        // Gold depends only on Play's read.
        Assert.Equal(PlayStateMapping.IsEntitling(read), PlayStateMapping.IsEntitling(settled));
    }
}
