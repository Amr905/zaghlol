using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-131 design note §7 (AC 5): the D-57 Look Up Order ID check over the fakes.</summary>
public class AppStoreOrderLookupTests
{
    private const string OrderId = "MK5TTTVWJH";

    private readonly AppleScript apple = new();
    private readonly RecordingPurchaseTelemetry telemetry = new();

    private AppStoreOrderLookup Lookup => new(apple.Api, apple.Jws, AppleScript.Catalog(), telemetry, new FixedClock(AppleScript.Now));

    [Fact]
    public async Task AnOrderCarryingThisPurchasesOriginalTransactionPasses()
    {
        var original = AppleScript.NewId();
        Script(OrderId, 0, Signed(AppleScript.Tx(AppleScript.NewId(), AppleScript.NewId(), null)), Signed(AppleScript.Tx(AppleScript.NewId(), original, null)));

        Assert.Equal(OwnershipOutcome.Pass, await CheckAsync(OrderId.ToLowerInvariant(), original));
        var call = Assert.Single(apple.Api.Calls);
        Assert.Equal((AppStoreApi.OrderLookup, PurchaseEnvironment.Production, OrderId, StoreLane.Support), call);
        Assert.Equal((PurchaseTags.PathApple, OwnershipOutcome.Pass), telemetry.Ownership.Single());
    }

    [Fact]
    public async Task StatusOneFails()
    {
        Script(OrderId, 1);

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(OrderId, AppleScript.NewId()));
    }

    [Fact]
    public async Task AnOrderOfAnotherPurchaseFails()
    {
        Script(OrderId, 0, Signed(AppleScript.Tx(AppleScript.NewId(), AppleScript.NewId(), null)));

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(OrderId, AppleScript.NewId()));
    }

    [Fact]
    public async Task ARefundedOrderFails()
    {
        var original = AppleScript.NewId();
        Script(OrderId, 0, Signed(AppleScript.Tx(AppleScript.NewId(), original, null, revocationDate: AppleScript.Now, revocationReason: 1)));

        Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(OrderId, original));
    }

    [Theory]
    [InlineData(AppStoreCallOutcome.ServerError)]
    [InlineData(AppStoreCallOutcome.Timeout)]
    [InlineData(AppStoreCallOutcome.CircuitOpen)]
    [InlineData(AppStoreCallOutcome.RateLimited)]
    [InlineData(AppStoreCallOutcome.AuthError)]
    [InlineData(AppStoreCallOutcome.BudgetDenied)]
    [InlineData(AppStoreCallOutcome.ClientError)]
    public async Task AnAppleErrorIsUnavailableNeverFail(AppStoreCallOutcome outcome)
    {
        apple.Api.Errors[AppStoreApi.OrderLookup] = new AppStoreApiException(AppStoreApi.OrderLookup, outcome, 500);

        Assert.Equal(OwnershipOutcome.Unavailable, await CheckAsync(OrderId, AppleScript.NewId()));
    }

    [Theory]
    [InlineData(2)]
    [InlineData(null)]
    public async Task AnUnknownStatusIsUnavailable(int? status)
    {
        apple.Api.Lookups[OrderId] = new AppleOrderLookupResult(status, []);

        Assert.Equal(OwnershipOutcome.Unavailable, await CheckAsync(OrderId, AppleScript.NewId()));
    }

    [Fact]
    public async Task ASignedTransactionThatFailsVerificationOrNamesAnotherAppIsUnavailableAndAlerted()
    {
        var original = AppleScript.NewId();
        apple.Jws.Failures["bad"] = AppleJwsFailure.Signature;
        apple.Api.Lookups[OrderId] = new AppleOrderLookupResult(0, [new Sensitive<string>("bad")]);

        Assert.Equal(OwnershipOutcome.Unavailable, await CheckAsync(OrderId, original));
        Assert.Contains((JwsSource.Api, (AppleJwsFailure?)AppleJwsFailure.Signature), telemetry.Jws);

        Script("ZZZ999AAA", 0, Signed(AppleScript.Tx(AppleScript.NewId(), original, null, bundleId: "com.example.other")));
        Assert.Equal(OwnershipOutcome.Unavailable, await CheckAsync("ZZZ999AAA", original));
        Assert.Contains((JwsSource.Api, (AppleJwsFailure?)AppleJwsFailure.Payload), telemetry.Jws);
    }

    [Fact]
    public async Task ASandboxPurchaseOrAMalformedOrderIdFailsWithoutACall()
    {
        var original = AppleScript.NewId();
        Script(OrderId, 0, Signed(AppleScript.Tx(AppleScript.NewId(), original, null)));

        Assert.Equal(OwnershipOutcome.Fail, await Lookup.CheckAsync(new Sensitive<string>(OrderId), new AppStoreOwnershipPurchase(new Sensitive<string>(original), PurchaseEnvironment.Sandbox), CancellationToken.None));
        foreach (var malformed in new[] { "GPA.1234-5678", "ABC12", "ABCDEFGHIJKLMNOPQRSTU", "ABC 123", "../lookup", "ＭＫ５ＴＴＴ", "" })
        {
            Assert.Equal(OwnershipOutcome.Fail, await CheckAsync(malformed, original));
        }

        Assert.Empty(apple.Api.Calls);
    }

    private string Signed(AppleTransaction transaction)
    {
        var key = "lookup:" + AppleScript.NewId();
        apple.Jws.Transactions[key] = transaction;
        return key;
    }

    private void Script(string orderId, int status, params string[] signed) =>
        apple.Api.Lookups[orderId] = new AppleOrderLookupResult(status, [.. signed.Select(s => new Sensitive<string>(s))]);

    private Task<OwnershipOutcome> CheckAsync(string orderId, string originalTransactionId) =>
        Lookup.CheckAsync(new Sensitive<string>(orderId), new AppStoreOwnershipPurchase(new Sensitive<string>(originalTransactionId), PurchaseEnvironment.Production), CancellationToken.None);
}
