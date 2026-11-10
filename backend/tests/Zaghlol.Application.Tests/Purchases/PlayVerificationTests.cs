using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-130 design note §1: the Android verify procedure over the fake Play API and an in-memory purchases table.</summary>
public class PlayVerificationTests
{
    private readonly FakePlayDeveloperApi play = new();
    private readonly FakePurchaseWriter writer = new();
    private readonly RecordingPurchaseTelemetry telemetry = new();
    private readonly FixedClock clock = new(Play.Now);

    private PlayVerification Verifier => new(play, Play.Catalog, writer, telemetry, clock);

    // AC 1: forged, replayed and foreign tokens.

    [Theory]
    [InlineData(PlayApi.SubscriptionGet)]
    public async Task ATokenPlayDoesNotKnowIsAFinalTokenInvalidAndWritesNothing(PlayApi api)
    {
        play.Fail(api, PlayCallOutcome.ClientError);

        var result = await VerifyAsync(Play.Yearly, Play.NewToken(), Play.NewInstall());

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, result.ProblemCode);
        Assert.Equal(VerifyStatus.Invalid, result.Status);
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task ATokenOfAnotherProductIsTokenInvalid()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, productId: Play.Monthly);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, result.ProblemCode);
        Assert.Equal(0, writer.Upserts);
        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
    }

    [Fact]
    public async Task ATokenBoundToAnotherInstallIsNotOwnedAndWritesNothing()
    {
        var buyer = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(buyer);

        var replayed = await VerifyAsync(Play.Yearly, token, Play.NewInstall());

        Assert.Equal(ErrorCodes.PurchaseNotOwned, replayed.ProblemCode);
        Assert.Equal(0, writer.Upserts);
        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
    }

    [Fact]
    public async Task ATokenWithoutABindingIsNotOwned()
    {
        // A promo code or out-of-app purchase carries no obfuscatedExternalAccountId: restore (attested) is the way in.
        var token = Play.NewToken();
        play.Products[token] = Play.Product(boundTo: null);

        var result = await VerifyAsync(Play.Lifetime, token, Play.NewInstall());

        Assert.Equal(ErrorCodes.PurchaseNotOwned, result.ProblemCode);
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task RestoreSkipsOnlyTheBindingCheckAndNeverSetsTheBuyingInstall()
    {
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), acknowledged: true);

        var result = await Verifier.VerifyAsync(new StorePurchaseRef(Play.Yearly, new Sensitive<string>(token)), Play.NewInstall(), BindingCheck.Skip, CancellationToken.None);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.Null(writer.Rows[token].InstallId);
    }

    [Fact]
    public async Task AnUnknownProductIsWrongAppWithoutAnyPlayCall()
    {
        var result = await VerifyAsync("com.other.app_gold", Play.NewToken(), Play.NewInstall());

        Assert.Equal(ErrorCodes.PurchaseWrongApp, result.ProblemCode);
        Assert.Empty(play.Calls);
    }

    [Theory]
    [InlineData(513)]
    [InlineData(2048)]
    public async Task ATokenLongerThan512IsTokenInvalidWithoutAnyPlayCall(int length)
    {
        var result = await VerifyAsync(Play.Yearly, new string('a', length), Play.NewInstall());

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, result.ProblemCode);
        Assert.Empty(play.Calls);
    }

    [Theory]
    [InlineData("..")]
    [InlineData(".")]
    [InlineData("a/b")]
    [InlineData("a%2Fb")]
    [InlineData("a b")]
    [InlineData("abc\n")]
    [InlineData("tök")]
    [InlineData("")]
    public async Task ATokenOutsideTheSafeAlphabetIsTokenInvalidWithoutAnyPlayCall(string token)
    {
        var result = await VerifyAsync(Play.Yearly, token, Play.NewInstall());

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, result.ProblemCode);
        Assert.Empty(play.Calls);
    }

    [Fact]
    public async Task A512CharacterTokenIsAccepted()
    {
        var install = Play.NewInstall();
        var token = new string('x', 511) + "1";
        play.Subscriptions[token] = Play.Subscription(install);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(VerifyStatus.Active, result.Status);
    }

    // AC 2: pending grants nothing.

    [Fact]
    public async Task APendingSubscriptionIsPendingIsStoredAndIsNeverAcknowledged()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, PlaySubscriptionState.Pending);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(VerifyStatus.Pending, result.Status);
        Assert.Null(result.ProblemCode);
        Assert.Equal(StoredPurchaseState.Pending, writer.Rows[token].State);
        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
        Assert.False(result.Acknowledged);
    }

    [Fact]
    public async Task APendingLifetimePurchaseIsPendingAndNeverAcknowledged()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Products[token] = Play.Product(install, PlayProductState.Pending);

        var result = await VerifyAsync(Play.Lifetime, token, install);

        Assert.Equal(VerifyStatus.Pending, result.Status);
        Assert.Equal(StoredPurchaseState.Pending, writer.Rows[token].State);
        Assert.Equal(0, play.CallsTo(PlayApi.ProductAcknowledge));
    }

    // AC 4: lifetime goes through productsv2.

    [Fact]
    public async Task LifetimeReadsProductsV2AndAcknowledgesWithThePlayProductId()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Products[token] = Play.Product(install, test: true);

        var result = await VerifyAsync(Play.Lifetime, token, install);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.Equal(GoldPlan.Lifetime, result.Plan);
        Assert.Equal(PurchaseEnvironment.Sandbox, result.Environment);
        Assert.Null(result.ExpiresAt);
        Assert.Equal(1, play.CallsTo(PlayApi.ProductGet));
        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionGet));
        var ack = Assert.Single(play.Calls, c => c.Api == PlayApi.ProductAcknowledge);
        Assert.Equal(Play.Lifetime, ack.ProductId);
        Assert.Equal(StoreLane.Ack, ack.Lane);
        Assert.True(result.Acknowledged);
        Assert.True(writer.Rows[token].Acknowledged);
    }

    // State mapping (design note §1 step 4).

    [Theory]
    [InlineData(PlaySubscriptionState.Active, 10, StoredPurchaseState.Active, VerifyStatus.Active)]
    [InlineData(PlaySubscriptionState.InGracePeriod, 2, StoredPurchaseState.InGrace, VerifyStatus.Active)]
    [InlineData(PlaySubscriptionState.Canceled, 5, StoredPurchaseState.CanceledActive, VerifyStatus.Active)]
    [InlineData(PlaySubscriptionState.Canceled, -1, StoredPurchaseState.Expired, VerifyStatus.Expired)]
    [InlineData(PlaySubscriptionState.OnHold, -1, StoredPurchaseState.OnHold, VerifyStatus.Expired)]
    [InlineData(PlaySubscriptionState.Paused, 3, StoredPurchaseState.Paused, VerifyStatus.Expired)]
    [InlineData(PlaySubscriptionState.Expired, -3, StoredPurchaseState.Expired, VerifyStatus.Expired)]
    public async Task SubscriptionStatesMapAsDesigned(PlaySubscriptionState state, int expiryDays, StoredPurchaseState stored, VerifyStatus status)
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, state, expiry: Play.Now.AddDays(expiryDays), acknowledged: true);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(status, result.Status);
        Assert.Equal(stored, writer.Rows[token].State);
        Assert.Equal(install, writer.Rows[token].InstallId);
    }

    [Fact]
    public async Task ACancelledLifetimePurchaseIsRefunded()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Products[token] = Play.Product(install, PlayProductState.Cancelled);

        var result = await VerifyAsync(Play.Lifetime, token, install);

        Assert.Equal(VerifyStatus.Refunded, result.Status);
        Assert.Equal(StoredPurchaseState.Refunded, writer.Rows[token].State);
        Assert.Equal(0, play.CallsTo(PlayApi.ProductAcknowledge));
    }

    [Fact]
    public async Task APendingPurchaseThatWasCancelledIsTokenInvalidAndNotWritten()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, PlaySubscriptionState.PendingPurchaseCanceled);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, result.ProblemCode);
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task AnUnknownStateIsAStoreFailureNeverAGrantAndWritesNothing()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, PlaySubscriptionState.Unknown);
        var lifetime = Play.NewToken();
        play.Products[lifetime] = Play.Product(install, PlayProductState.Unknown);

        var subscription = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(Play.Yearly, token, install));
        var product = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(Play.Lifetime, lifetime, install));

        Assert.Equal(StoreFailureKind.Store, subscription.Kind);
        Assert.Equal(StoreFailureKind.Store, product.Kind);
        Assert.Equal(0, writer.Upserts);
    }

    // Outages (design note §1 step 3, §2).

    [Theory]
    [InlineData(PlayCallOutcome.AuthError, StoreFailureKind.Store)]
    [InlineData(PlayCallOutcome.ServerError, StoreFailureKind.Store)]
    [InlineData(PlayCallOutcome.RateLimited, StoreFailureKind.Store)]
    [InlineData(PlayCallOutcome.Timeout, StoreFailureKind.Store)]
    [InlineData(PlayCallOutcome.CircuitOpen, StoreFailureKind.Store)]
    [InlineData(PlayCallOutcome.BudgetDenied, StoreFailureKind.Budget)]
    public async Task APlayOutageIsNeverARejectionAndWritesNothing(PlayCallOutcome outcome, StoreFailureKind kind)
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install);
        play.Fail(PlayApi.SubscriptionGet, outcome);

        var error = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(Play.Yearly, token, install));

        Assert.Equal(kind, error.Kind);
        Assert.True(error.RetryAfterSeconds >= 1);
        Assert.Equal(0, writer.Upserts);
        Assert.Equal(StoreUnavailableException.DefaultMessage, error.Message);
    }

    // Acknowledgement (design note §1 step 6).

    [Fact]
    public async Task AFailedInlineAcknowledgeStillGrantsAndLeavesTheRowForTheSweeper()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install);
        play.Fail(PlayApi.SubscriptionAcknowledge, PlayCallOutcome.ServerError);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.False(result.Acknowledged);
        Assert.False(writer.Rows[token].Acknowledged);
        Assert.Contains((PurchaseTags.ChannelVerify, PurchaseTags.AckFailed), telemetry.Acks);
    }

    [Fact]
    public async Task AnAcknowledgeErrorAnswerIsReReadAndAcknowledgedThereCountsAsSuccess()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install);
        play.Fail(PlayApi.SubscriptionAcknowledge, PlayCallOutcome.ClientError);

        // Someone (the sweeper, an earlier retry) acknowledged between our read and our acknowledge.
        var result = await new PlayVerification(new ReReadAcknowledged(play, token), Play.Catalog, writer, telemetry, clock)
            .VerifyAsync(new StorePurchaseRef(Play.Yearly, new Sensitive<string>(token)), install, BindingCheck.RequireCaller, CancellationToken.None);

        Assert.True(result.Acknowledged);
        Assert.True(writer.Rows[token].Acknowledged);
        Assert.Equal(2, play.CallsTo(PlayApi.SubscriptionGet));
        Assert.Contains((PurchaseTags.ChannelVerify, PurchaseTags.AckAlready), telemetry.Acks);
    }

    [Fact]
    public async Task AnAcknowledgeErrorAnswerWithAnUnacknowledgedReReadIsAFailureButStillGrants()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install);
        play.Fail(PlayApi.SubscriptionAcknowledge, PlayCallOutcome.ClientError);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.False(result.Acknowledged);
        Assert.Equal(2, play.CallsTo(PlayApi.SubscriptionGet));
        Assert.Contains((PurchaseTags.ChannelVerify, PurchaseTags.AckFailed), telemetry.Acks);
    }

    [Fact]
    public async Task AnAlreadyAcknowledgedPurchaseIsNotAcknowledgedAgain()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, acknowledged: true);

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.True(result.Acknowledged);
        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
    }

    [Fact]
    public async Task ASubscriptionAcknowledgeUsesThePlayReturnedProductIdAndTheAckLane()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, productId: Play.Monthly);

        await VerifyAsync(Play.Monthly, token, install);

        var ack = Assert.Single(play.Calls, c => c.Api == PlayApi.SubscriptionAcknowledge);
        Assert.Equal(Play.Monthly, ack.ProductId);
        Assert.Equal(StoreLane.Ack, ack.Lane);
        Assert.Equal(StoreLane.Verify, Assert.Single(play.Calls, c => c.Api == PlayApi.SubscriptionGet).Lane);
    }

    // Upsert rules (design note §1 step 5).

    [Fact]
    public async Task AReVerifyNeverChangesTheBuyingInstallAndAKnownPredecessorIsReported()
    {
        var install = Play.NewInstall();
        var old = Play.NewToken();
        play.Subscriptions[old] = Play.Subscription(install, acknowledged: true);
        var first = await VerifyAsync(Play.Yearly, old, install);

        var upgrade = Play.NewToken();
        play.Subscriptions[upgrade] = Play.Subscription(install, productId: Play.Yearly, linked: old, acknowledged: true);
        clock.Now = Play.Now.AddMinutes(1);
        var second = await VerifyAsync(Play.Yearly, upgrade, install);

        Assert.Equal(first.PurchaseId, second.PredecessorPurchaseId);
        Assert.Equal(install, writer.Rows[old].InstallId);
        Assert.Equal(old, writer.Rows[upgrade].LinkedPurchaseToken);
    }

    [Fact]
    public async Task AnOlderReadNeverOverwritesANewerOneAndTheAnswerFollowsTheStoredRow()
    {
        var install = Play.NewInstall();
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(install, acknowledged: true);
        await VerifyAsync(Play.Yearly, token, install);

        // A newer read (RTDN, sweeper) already stored "expired"; this verify's read is older.
        writer.Rows[token] = writer.Rows[token] with { State = StoredPurchaseState.Expired, LastVerifiedAt = Play.Now.AddMinutes(5) };

        var result = await VerifyAsync(Play.Yearly, token, install);

        Assert.Equal(StoredPurchaseState.Expired, writer.Rows[token].State);
        Assert.Equal(VerifyStatus.Expired, result.Status);
    }

    private Task<StoreVerificationResult> VerifyAsync(string productId, string token, InstallId caller) =>
        Verifier.VerifyAsync(new StorePurchaseRef(productId, new Sensitive<string>(token)), caller, BindingCheck.RequireCaller, CancellationToken.None);

    /// <summary>Answers the first read unacknowledged and every later read acknowledged (someone acked in between).</summary>
    private sealed class ReReadAcknowledged(FakePlayDeveloperApi inner, string token) : IPlayDeveloperApi
    {
        private int reads;

        public async Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> t, StoreLane lane, CancellationToken cancellationToken)
        {
            var read = await inner.GetSubscriptionAsync(t, lane, cancellationToken);
            return Interlocked.Increment(ref reads) > 1 && t.Reveal() == token ? read with { Acknowledged = true } : read;
        }

        public Task<PlayProduct> GetProductAsync(Sensitive<string> t, StoreLane lane, CancellationToken cancellationToken) =>
            inner.GetProductAsync(t, lane, cancellationToken);

        public Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> t, StoreLane lane, CancellationToken cancellationToken) =>
            inner.AcknowledgeSubscriptionAsync(productId, t, lane, cancellationToken);

        public Task AcknowledgeProductAsync(string productId, Sensitive<string> t, StoreLane lane, CancellationToken cancellationToken) =>
            inner.AcknowledgeProductAsync(productId, t, lane, cancellationToken);

        public Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken) =>
            inner.GetOrderAsync(orderId, lane, cancellationToken);
    }
}
