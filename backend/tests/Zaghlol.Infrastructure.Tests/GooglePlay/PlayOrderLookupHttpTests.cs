using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>
/// AC 6/7 over HTTP: the real client and <see cref="PlayOrderLookup"/> against WireMock bodies in Google's shape. R5-8: a body
/// whose only order field is the deprecated <c>latestOrderId</c> (holding the user's order ID) gives <c>fail</c>.
/// </summary>
[Collection(PlayClientGroup.Name)]
public sealed class PlayOrderLookupHttpTests : IDisposable
{
    private const string OrderId = "GPA.3301-2207-4415-12345";

    private readonly PlayWireMock play = new();

    public void Dispose() => play.Dispose();

    [Fact]
    public async Task OnlyLatestOrderIdWithTheUsersOrderIsAFail()
    {
        await using var host = PlayClientHost.Start(play);
        var token = "tok." + Guid.NewGuid().ToString("N");
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref", latestOrderId: OrderId));

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(host, PlayOrderLookupPath.Fallback, token));
        Assert.Equal(1, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task LatestSuccessfulOrderIdOnALinkedPredecessorIsAPass()
    {
        await using var host = PlayClientHost.Start(play);
        var head = "tok." + Guid.NewGuid().ToString("N");
        var old = "tok." + Guid.NewGuid().ToString("N");
        play.Get(PlayWireMock.SubscriptionPath(head), 200, PlayWireMock.SubscriptionBody("ref", linkedPurchaseToken: old, latestSuccessfulOrderId: "GPA.9999-9999-9999-99999"));
        play.Get(PlayWireMock.SubscriptionPath(old), 200, PlayWireMock.SubscriptionBody("ref", "SUBSCRIPTION_STATE_EXPIRED", expiry: DateTimeOffset.UtcNow.AddDays(-3), latestSuccessfulOrderId: OrderId));

        Assert.Equal(OwnershipOutcome.Pass, await CheckAsync(host, PlayOrderLookupPath.Fallback, head));
    }

    [Theory]
    [InlineData("REFUNDED", OwnershipOutcome.Fail)]
    [InlineData("CANCELED", OwnershipOutcome.Fail)]
    [InlineData("PENDING_REFUND", OwnershipOutcome.Fail)]
    [InlineData("PROCESSED", OwnershipOutcome.Pass)]
    public async Task TheOrdersPathReadsTheOrderState(string state, OwnershipOutcome expected)
    {
        await using var host = PlayClientHost.Start(play);
        var token = "tok." + Guid.NewGuid().ToString("N");
        play.Get(PlayWireMock.OrderPath(OrderId), 200, PlayWireMock.OrderBody(token, state));

        Assert.Equal(expected, await CheckAsync(host, PlayOrderLookupPath.Orders, token));
    }

    [Theory]
    [InlineData(PlayOrderLookupPath.Orders, 503)]
    [InlineData(PlayOrderLookupPath.Fallback, 500)]
    public async Task APlay5xxIsUnavailableAndA404IsAFail(PlayOrderLookupPath path, int status)
    {
        await using var host = PlayClientHost.Start(play);
        var token = "tok." + Guid.NewGuid().ToString("N");
        play.Get(PlayWireMock.OrderPath(OrderId), status);
        play.Get(PlayWireMock.SubscriptionPath(token), status);

        Assert.Equal(OwnershipOutcome.Unavailable, await CheckAsync(host, path, token));

        play.Get(PlayWireMock.OrderPath(OrderId), 404);
        play.Get(PlayWireMock.SubscriptionPath(token), 404);
        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(host, path, token));
    }

    private static Task<OwnershipOutcome> CheckAsync(PlayClientHost host, PlayOrderLookupPath path, string token) =>
        new PlayOrderLookup(host.Api, path, new NoTelemetry(), TimeProvider.System)
            .CheckAsync(new Sensitive<string>(OrderId), new OwnershipPurchase(PlayProductKind.Subscription, new Sensitive<string>(token), null), CancellationToken.None);

    private sealed class NoTelemetry : IPurchaseTelemetry
    {
        public void Verified(string store, string outcome, string code)
        {
        }

        public void Acknowledged(string channel, string outcome)
        {
        }

        public void TimeToAck(TimeSpan sincePurchase)
        {
        }

        public void SetUnacked(long lessThan48h, long atLeast48h, TimeSpan oldestAge)
        {
        }

        public void UnackedOver48h(Guid purchaseId)
        {
        }

        public void OwnershipChecked(string path, OwnershipOutcome outcome)
        {
        }
    }
}
