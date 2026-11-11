using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>One Play stand-in at a time: the meter listener and the circuit breaker are per test, never shared.</summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class PlayClientGroup
{
    public const string Name = "Play client";
}

/// <summary>T-130: the typed Play client over HTTP (WireMock): endpoints, parsing, error mapping, resilience and budget.</summary>
[Collection(PlayClientGroup.Name)]
public sealed class PlayDeveloperApiClientTests : IDisposable
{
    private readonly PlayWireMock play = new();

    public void Dispose() => play.Dispose();

    [Fact]
    public async Task ASubscriptionIsReadFromSubscriptionsV2WithOnlyTheFieldsWeUse()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(
            "binding-ref",
            "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
            acknowledged: true,
            test: true,
            linkedPurchaseToken: "older.token",
            latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
            latestOrderId: "GPA.0000-0000-0000-99999"));

        var read = await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);

        Assert.Equal(PlaySubscriptionState.InGracePeriod, read.State);
        Assert.True(read.Acknowledged);
        Assert.True(read.TestPurchase);
        Assert.Equal("binding-ref", read.ObfuscatedExternalAccountId);
        Assert.Equal("older.token", read.LinkedPurchaseToken?.Reveal());
        var item = Assert.Single(read.LineItems);
        Assert.Equal(PlayWireMock.Yearly, item.ProductId);
        Assert.Equal("GPA.1234-5678-9012-34567", item.LatestSuccessfulOrderId?.Reveal());
        Assert.NotNull(item.ExpiryTime); // nanosecond timestamps parse
        Assert.NotNull(read.StartTime);
        Assert.Equal(1, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task ALifetimePurchaseIsReadFromProductsV2AndTheV1EndpointIsNeverCalled()
    {
        // AC 4 at the HTTP level: no GET under /purchases/products/ (v1 products.get) ever leaves the client.
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.ProductPath(token), 200, PlayWireMock.ProductBody("binding-ref", test: true, orderId: "GPA.1111-2222-3333-44444"));
        play.Acknowledge(PlayWireMock.ProductAckPath(PlayWireMock.Lifetime, token));

        var read = await host.Api.GetProductAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);
        await host.Api.AcknowledgeProductAsync(PlayWireMock.Lifetime, new Sensitive<string>(token), StoreLane.Ack, CancellationToken.None);

        Assert.Equal(PlayProductState.Purchased, read.State);
        Assert.Equal([PlayWireMock.Lifetime], read.ProductIds);
        Assert.True(read.TestPurchase);
        Assert.Equal("GPA.1111-2222-3333-44444", read.OrderId?.Reveal());
        Assert.Equal(1, play.Count("GET", PlayWireMock.ProductPath(token)));
        Assert.Equal(1, play.Count("POST", PlayWireMock.ProductAckPath(PlayWireMock.Lifetime, token)));
        Assert.Equal(0, play.CountContaining("GET", "/purchases/products/"));
        Assert.Equal(0, play.CountContaining("GET", "/purchases/subscriptions/"));
    }

    [Fact]
    public async Task TheClientHasNoV1ReadMethodAtAll()
    {
        var methods = typeof(IPlayDeveloperApi).GetMethods().Select(m => m.Name).ToArray();
        Assert.Equal(
            ["AcknowledgeProductAsync", "AcknowledgeSubscriptionAsync", "GetOrderAsync", "GetProductAsync", "GetSubscriptionAsync", "ListVoidedPurchasesAsync"],
            methods.Order(StringComparer.Ordinal));
        Assert.Contains("/purchases/productsv2/tokens/", PlayDeveloperApiClient.ProductGetTemplate, StringComparison.Ordinal);
        Assert.Contains("/purchases/subscriptionsv2/tokens/", PlayDeveloperApiClient.SubscriptionGetTemplate, StringComparison.Ordinal);
        await Task.CompletedTask;
    }

    [Fact]
    public async Task ASubscriptionIsAcknowledgedByPostWithItsProductId()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Acknowledge(PlayWireMock.SubscriptionAckPath(PlayWireMock.Monthly, token));

        await host.Api.AcknowledgeSubscriptionAsync(PlayWireMock.Monthly, new Sensitive<string>(token), StoreLane.Ack, CancellationToken.None);

        Assert.Equal(1, play.Count("POST", PlayWireMock.SubscriptionAckPath(PlayWireMock.Monthly, token)));
    }

    [Fact]
    public async Task AnOrderIsReadFromOrdersGet()
    {
        await using var host = PlayClientHost.Start(play);
        play.Get(PlayWireMock.OrderPath("GPA.1234-5678-9012-34567"), 200, PlayWireMock.OrderBody("some.token", "PARTIALLY_REFUNDED"));

        var order = await host.Api.GetOrderAsync(new Sensitive<string>("GPA.1234-5678-9012-34567"), StoreLane.Support, CancellationToken.None);

        Assert.Equal(PlayOrderState.PartiallyRefunded, order.State);
        Assert.Equal("some.token", order.PurchaseToken?.Reveal());
    }

    [Theory]
    [InlineData(400, PlayCallOutcome.ClientError)]
    [InlineData(404, PlayCallOutcome.ClientError)]
    [InlineData(410, PlayCallOutcome.ClientError)]
    [InlineData(401, PlayCallOutcome.AuthError)]
    [InlineData(403, PlayCallOutcome.AuthError)]
    public async Task A4xxIsMappedAndNeverRetried(int status, PlayCallOutcome outcome)
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), status, "{\"error\":{\"message\":\"echo " + token + "\"}}");

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(outcome, error.Outcome);
        Assert.Equal(PlayApi.SubscriptionGet, error.Api);
        Assert.Equal(1, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
        Assert.Equal(PlayApiException.DefaultMessage, error.Message);
        Assert.DoesNotContain(token, error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task A503IsRetriedAndThenSucceeds()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.GetAfterFailures(PlayWireMock.SubscriptionPath(token), 1, 503, PlayWireMock.SubscriptionBody("ref"));

        var read = await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);

        Assert.Equal(PlaySubscriptionState.Active, read.State);
        Assert.Equal(2, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
        Assert.Contains(host.StoreCalls(), t => t["api"] == "sub_get" && t["outcome"] == "ok");
    }

    [Theory]
    [InlineData(500, PlayCallOutcome.ServerError)]
    [InlineData(429, PlayCallOutcome.RateLimited)]
    [InlineData(408, PlayCallOutcome.Timeout)]
    public async Task ARetryableFailureIsTriedFourTimesThenMapped(int status, PlayCallOutcome outcome)
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), status);

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(outcome, error.Outcome);
        Assert.Equal(4, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task ASlowAnswerIsATimeout()
    {
        await using var host = PlayClientHost.Start(play, new Dictionary<string, string?>
        {
            ["Purchases:Google:Resilience:AttemptTimeoutMs"] = "150",
            ["Purchases:Google:Resilience:TotalTimeoutMs"] = "600",
        });
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref"), delay: TimeSpan.FromSeconds(2));

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.Timeout, error.Outcome);
    }

    [Fact]
    public async Task RepeatedFailuresOpenTheCircuitAndThenNoRequestLeaves()
    {
        await using var host = PlayClientHost.Start(play, new Dictionary<string, string?>
        {
            ["Purchases:Google:Resilience:MinimumThroughput"] = "4",
            ["Purchases:Google:Resilience:SamplingDurationMs"] = "30000",
            ["Purchases:Google:Resilience:BreakDurationMs"] = "30000",
        });
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 503);

        var outcomes = new List<PlayCallOutcome>();
        for (var i = 0; i < 3; i++)
        {
            outcomes.Add((await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None))).Outcome);
        }

        var sent = play.Count("GET", PlayWireMock.SubscriptionPath(token));
        var open = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Contains(PlayCallOutcome.CircuitOpen, outcomes.Append(open.Outcome));
        Assert.Equal(PlayCallOutcome.CircuitOpen, open.Outcome);
        Assert.Equal(sent, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task AnExhaustedBudgetDeniesTheCallWithoutARequest()
    {
        await using var host = PlayClientHost.Start(play, new Dictionary<string, string?>
        {
            ["Purchases:Google:Budget:TokenLimit"] = "1",
            ["Purchases:Google:Budget:TokensPerPeriod"] = "1",
            ["Purchases:Google:Budget:PeriodSeconds"] = "3600",
        });
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref"));

        await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);
        var denied = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.BudgetDenied, denied.Outcome);
        Assert.Equal(1, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
        Assert.Contains(host.StoreCalls(), t => t["outcome"] == "budget_denied");
    }

    [Fact]
    public async Task EachAttemptCarriesTheBearerToken()
    {
        await using var host = PlayClientHost.Start(play, tokens: new FixedTokens("access-xyz"));
        var token = NewToken();
        play.GetAfterFailures(PlayWireMock.SubscriptionPath(token), 1, 503, PlayWireMock.SubscriptionBody("ref"));

        await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);

        var headers = play.Server.LogEntries.Select(e => e.RequestMessage!.Headers!["Authorization"].Single()).ToArray();
        Assert.Equal(["Bearer access-xyz", "Bearer access-xyz"], headers);
    }

    [Fact]
    public async Task ACredentialFailureIsAnAuthErrorWithoutARequest()
    {
        await using var host = PlayClientHost.Start(play, tokens: new FailingTokens());
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref"));

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.AuthError, error.Outcome);
        Assert.Empty(play.Received());
    }

    [Fact]
    public async Task AnUnparseableAnswerIsAServerErrorNeverAGrantOrARejection()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, "{not json");

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.ServerError, error.Outcome);
    }

    [Fact]
    public async Task AnOversizedAnswerIsAServerErrorAndIsNotParsed()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, "{\"pad\":\"" + new string('x', 300 * 1024) + "\"}");

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.ServerError, error.Outcome);
    }

    [Fact]
    public async Task UnknownEnumValuesAreUnknownNotADefaultState()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref", "SUBSCRIPTION_STATE_SOMETHING_NEW"));
        play.Get(PlayWireMock.ProductPath(token), 200, PlayWireMock.ProductBody("ref", "REFUND_IN_PROGRESS"));
        play.Get(PlayWireMock.OrderPath("GPA.1"), 200, PlayWireMock.OrderBody("t", "STATE_UNSPECIFIED"));

        Assert.Equal(PlaySubscriptionState.Unknown, (await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None)).State);
        Assert.Equal(PlayProductState.Unknown, (await host.Api.GetProductAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None)).State);
        Assert.Equal(PlayOrderState.Unknown, (await host.Api.GetOrderAsync(new Sensitive<string>("GPA.1"), StoreLane.Support, CancellationToken.None)).State);
    }

    [Fact]
    public async Task EveryStoreCallTagComesFromItsConstantSet()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref"));
        play.Get(PlayWireMock.ProductPath(token), 404);
        play.Acknowledge(PlayWireMock.SubscriptionAckPath(PlayWireMock.Yearly, token), 503);
        play.Get(PlayWireMock.OrderPath("GPA.2"), 403);

        await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);
        await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetProductAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));
        await Assert.ThrowsAsync<PlayApiException>(() => host.Api.AcknowledgeSubscriptionAsync(PlayWireMock.Yearly, new Sensitive<string>(token), StoreLane.Ack, CancellationToken.None));
        await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetOrderAsync(new Sensitive<string>("GPA.2"), StoreLane.Support, CancellationToken.None));

        var calls = host.StoreCalls();
        Assert.Equal(4, calls.Count);
        Assert.All(calls, tags =>
        {
            Assert.Equal(["api", "outcome", "store"], tags.Keys.Order(StringComparer.Ordinal));
            Assert.Equal("google_play", tags["store"]);
            Assert.Contains(tags["api"], StoreCallTags.Apis);
            Assert.Contains(tags["outcome"], StoreCallTags.Outcomes);
        });
        Assert.Equal(["auth_error", "client_error", "ok", "server_error"], calls.Select(t => t["outcome"]).Order(StringComparer.Ordinal));
    }

    private static string NewToken() => "tok." + Guid.NewGuid().ToString("N") + "_" + Guid.NewGuid().ToString("N");

    private sealed class FixedTokens(string value) : IPlayAccessTokenSource
    {
        public Task<Sensitive<string>?> GetTokenAsync(CancellationToken cancellationToken) => Task.FromResult<Sensitive<string>?>(new Sensitive<string>(value));
    }

    private sealed class FailingTokens : IPlayAccessTokenSource
    {
        public Task<Sensitive<string>?> GetTokenAsync(CancellationToken cancellationToken) => throw new PlayAccessTokenException();
    }
}
