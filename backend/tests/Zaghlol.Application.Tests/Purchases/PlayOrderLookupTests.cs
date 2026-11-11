using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-130 design note §6: the support order-ID check, both paths (AC 6, AC 7).</summary>
public class PlayOrderLookupTests
{
    private const string OrderId = "GPA.3301-2207-4415-12345";

    private readonly FakePlayDeveloperApi play = new();
    private readonly RecordingPurchaseTelemetry telemetry = new();

    // AC 6: the fallback path (R4-7, R5-8).

    [Fact]
    public async Task FallbackPassesOnTheTokensOwnLatestSuccessfulOrderId()
    {
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), latestSuccessfulOrderId: OrderId);

        Assert.Equal(OwnershipOutcome.Pass, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, Subscription(token)));
        Assert.Equal((PurchaseTags.PathFallback, OwnershipOutcome.Pass), Assert.Single(telemetry.Ownership));
        Assert.All(play.Calls, c => Assert.Equal(StoreLane.Support, c.Lane));
    }

    [Fact]
    public async Task FallbackPassesWhenOnlyALinkedPredecessorCarriesTheOrder()
    {
        var install = Play.NewInstall();
        var oldest = Play.NewToken();
        var middle = Play.NewToken();
        var head = Play.NewToken();
        play.Subscriptions[oldest] = Play.Subscription(install, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-40), latestSuccessfulOrderId: OrderId);
        play.Subscriptions[middle] = Play.Subscription(install, PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-5), linked: oldest, latestSuccessfulOrderId: "GPA.1111-2222-3333-44444");
        play.Subscriptions[head] = Play.Subscription(install, linked: middle, latestSuccessfulOrderId: "GPA.9999-8888-7777-66666");

        Assert.Equal(OwnershipOutcome.Pass, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, Subscription(head, linked: middle)));
        Assert.Equal(3, play.CallsTo(PlayApi.SubscriptionGet));
    }

    [Fact]
    public async Task FallbackNeverReadsTheDeprecatedLatestOrderId()
    {
        // R5-8: Play's body carries the user's order ID only as latestOrderId. The DTO has no member for it, so the value can't
        // reach the comparison; here the line item has no latestSuccessfulOrderId at all.
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), latestSuccessfulOrderId: null);

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, Subscription(token)));
        Assert.DoesNotContain(typeof(PlayLineItem).GetProperties(), p => p.Name == "LatestOrderId");
        Assert.DoesNotContain(typeof(PlaySubscription).GetProperties(), p => p.Name == "LatestOrderId");
    }

    [Fact]
    public async Task FallbackStopsAtACycleInTheChain()
    {
        var install = Play.NewInstall();
        var a = Play.NewToken();
        var b = Play.NewToken();
        play.Subscriptions[a] = Play.Subscription(install, linked: b);
        play.Subscriptions[b] = Play.Subscription(install, PlaySubscriptionState.Expired, linked: a);

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, Subscription(a)));
        Assert.Equal(2, play.CallsTo(PlayApi.SubscriptionGet));
    }

    [Fact]
    public async Task FallbackReadsAtMostTenTokens()
    {
        var install = Play.NewInstall();
        var tokens = Enumerable.Range(0, 15).Select(_ => Play.NewToken()).ToArray();
        for (var i = 0; i < tokens.Length; i++)
        {
            play.Subscriptions[tokens[i]] = Play.Subscription(
                install,
                i == 0 ? PlaySubscriptionState.Active : PlaySubscriptionState.Expired,
                linked: i + 1 < tokens.Length ? tokens[i + 1] : null,
                latestSuccessfulOrderId: i == 14 ? OrderId : null);
        }

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, Subscription(tokens[0])));
        Assert.Equal(PlayOrderLookup.MaxChainDepth, play.CallsTo(PlayApi.SubscriptionGet));
    }

    [Fact]
    public async Task FallbackFailsWhenThePurchaseNoLongerEntitlesEvenIfTheOrderMatches()
    {
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1), latestSuccessfulOrderId: OrderId);

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, Subscription(token)));
    }

    [Theory]
    [InlineData(PlayProductState.Purchased, OrderId, OwnershipOutcome.Pass)]
    [InlineData(PlayProductState.Cancelled, OrderId, OwnershipOutcome.Fail)]
    [InlineData(PlayProductState.Pending, OrderId, OwnershipOutcome.Fail)]
    [InlineData(PlayProductState.Purchased, "GPA.0000-0000-0000-00000", OwnershipOutcome.Fail)]
    public async Task FallbackForLifetimeComparesTheProductsV2OrderId(PlayProductState state, string playOrderId, OwnershipOutcome expected)
    {
        var token = Play.NewToken();
        play.Products[token] = Play.Product(Play.NewInstall(), state, orderId: playOrderId);

        Assert.Equal(expected, await CheckAsync(PlayOrderLookupPath.Fallback, OrderId, new OwnershipPurchase(PlayProductKind.OneTime, new Sensitive<string>(token), null)));
    }

    // AC 7: refunded or cancelled orders fail; outages are unavailable.

    [Theory]
    [InlineData(PlayOrderState.Refunded, OwnershipOutcome.Fail)]
    [InlineData(PlayOrderState.Canceled, OwnershipOutcome.Fail)]
    [InlineData(PlayOrderState.PendingRefund, OwnershipOutcome.Fail)]
    [InlineData(PlayOrderState.Pending, OwnershipOutcome.Fail)]
    [InlineData(PlayOrderState.Unknown, OwnershipOutcome.Fail)]
    [InlineData(PlayOrderState.Processed, OwnershipOutcome.Pass)]
    [InlineData(PlayOrderState.PartiallyRefunded, OwnershipOutcome.Pass)]
    public async Task OrdersPathChecksTheOrderState(PlayOrderState state, OwnershipOutcome expected)
    {
        var token = Play.NewToken();
        play.Orders[OrderId] = new PlayOrder(new Sensitive<string>(token), state);

        Assert.Equal(expected, await CheckAsync(PlayOrderLookupPath.Orders, OrderId, Subscription(token)));
        Assert.Equal(PurchaseTags.PathOrders, Assert.Single(telemetry.Ownership).Path);
    }

    [Fact]
    public async Task OrdersPathPassesForATokenFurtherBackInTheChainAndFailsForAStrangersToken()
    {
        var install = Play.NewInstall();
        var old = Play.NewToken();
        var head = Play.NewToken();
        play.Subscriptions[head] = Play.Subscription(install, linked: old);
        play.Subscriptions[old] = Play.Subscription(install, PlaySubscriptionState.Expired);
        play.Orders[OrderId] = new PlayOrder(new Sensitive<string>(old), PlayOrderState.Processed);
        play.Orders["GPA.5555-5555-5555-55555"] = new PlayOrder(new Sensitive<string>(Play.NewToken()), PlayOrderState.Processed);

        Assert.Equal(OwnershipOutcome.Pass, await CheckAsync(PlayOrderLookupPath.Orders, OrderId, Subscription(head)));
        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Orders, "GPA.5555-5555-5555-55555", Subscription(head)));
    }

    [Fact]
    public async Task AnUnknownOrderIsAFail()
    {
        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Orders, OrderId, Subscription(Play.NewToken())));
    }

    [Theory]
    [InlineData(PlayOrderLookupPath.Orders, PlayApi.OrderGet, PlayCallOutcome.ServerError)]
    [InlineData(PlayOrderLookupPath.Orders, PlayApi.OrderGet, PlayCallOutcome.Timeout)]
    [InlineData(PlayOrderLookupPath.Orders, PlayApi.OrderGet, PlayCallOutcome.CircuitOpen)]
    [InlineData(PlayOrderLookupPath.Orders, PlayApi.OrderGet, PlayCallOutcome.BudgetDenied)]
    [InlineData(PlayOrderLookupPath.Orders, PlayApi.OrderGet, PlayCallOutcome.AuthError)]
    [InlineData(PlayOrderLookupPath.Fallback, PlayApi.SubscriptionGet, PlayCallOutcome.ServerError)]
    [InlineData(PlayOrderLookupPath.Fallback, PlayApi.SubscriptionGet, PlayCallOutcome.Timeout)]
    [InlineData(PlayOrderLookupPath.Fallback, PlayApi.SubscriptionGet, PlayCallOutcome.CircuitOpen)]
    [InlineData(PlayOrderLookupPath.Fallback, PlayApi.SubscriptionGet, PlayCallOutcome.BudgetDenied)]
    public async Task AnOutageIsUnavailableNeverFail(PlayOrderLookupPath path, PlayApi api, PlayCallOutcome outcome)
    {
        var token = Play.NewToken();
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), latestSuccessfulOrderId: OrderId);
        play.Orders[OrderId] = new PlayOrder(new Sensitive<string>(token), PlayOrderState.Processed);
        play.Fail(api, outcome);

        Assert.Equal(OwnershipOutcome.Unavailable, await CheckAsync(path, OrderId, Subscription(token)));
        Assert.Equal(OwnershipOutcome.Unavailable, Assert.Single(telemetry.Ownership).Outcome);
    }

    [Theory]
    [InlineData("")]
    [InlineData("..")]
    [InlineData("GPA.1/../x")]
    public async Task AMalformedOrderIdFailsWithoutAnyCall(string orderId)
    {
        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(PlayOrderLookupPath.Orders, orderId, Subscription(Play.NewToken())));
        Assert.Empty(play.Calls);
    }

    private static OwnershipPurchase Subscription(string token, string? linked = null) =>
        new(PlayProductKind.Subscription, new Sensitive<string>(token), linked is null ? null : new Sensitive<string>(linked));

    private Task<OwnershipOutcome> CheckAsync(PlayOrderLookupPath path, string orderId, OwnershipPurchase purchase) =>
        new PlayOrderLookup(play, path, telemetry, new FixedClock(Play.Now)).CheckAsync(new Sensitive<string>(orderId), purchase, CancellationToken.None);
}
