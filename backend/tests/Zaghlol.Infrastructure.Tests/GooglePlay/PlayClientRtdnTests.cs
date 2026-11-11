using System.Net;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>
/// T-133 §4-§6 over HTTP (WireMock): <c>voidedpurchases.list</c>, the per-attempt and partitioned budget (FU-077 M-2, FU-098 code 4),
/// a long <c>Retry-After</c> deferred instead of retried, and its date form against the injected clock (FU-098 nit 7).
/// </summary>
[Collection(PlayClientGroup.Name)]
public sealed class PlayClientRtdnTests : IDisposable
{
    private readonly PlayWireMock play = new();

    public void Dispose() => play.Dispose();

    [Fact]
    public async Task TheVoidedListAsksForOneTimeAndSubscriptionVoidsAndFollowsThePageToken()
    {
        await using var host = PlayClientHost.Start(play, playPartition: PlayBudgetPartition.Worker);
        play.GetSequence(
            PlayWireMock.VoidedPath,
            PlayWireMock.VoidedBody("next/page+1", ("tok.a", "GPA.1", 1_793_000_000_000), ("tok.b", "GPA.2..0", 1_793_000_100_000)),
            PlayWireMock.VoidedBody(null));
        var from = DateTimeOffset.FromUnixTimeMilliseconds(1_790_000_000_000);
        var until = DateTimeOffset.FromUnixTimeMilliseconds(1_792_592_000_000);

        var first = await host.Api.ListVoidedPurchasesAsync(from, until, null, StoreLane.Notification, CancellationToken.None);
        var second = await host.Api.ListVoidedPurchasesAsync(from, until, first.NextPageToken, StoreLane.Notification, CancellationToken.None);

        Assert.Equal(2, first.Purchases.Count);
        Assert.Equal("tok.a", first.Purchases[0].PurchaseToken!.Value.Reveal());
        Assert.Equal("GPA.2..0", first.Purchases[1].OrderId!.Value.Reveal());
        Assert.Equal(1_793_000_100_000, first.Purchases[1].VoidedTimeMillis);
        Assert.Equal("next/page+1", first.NextPageToken!.Value.Reveal());
        Assert.Empty(second.Purchases);
        Assert.Null(second.NextPageToken);

        var queries = play.Queries(PlayWireMock.VoidedPath);
        Assert.Equal("?type=1&maxResults=1000&startTime=1790000000000&endTime=1792592000000", queries[0]);
        Assert.Equal("?type=1&maxResults=1000&startTime=1790000000000&endTime=1792592000000&token=next%2Fpage%2B1", queries[1]);
        Assert.Contains(host.StoreCalls(), t => t["api"] == "voided_list" && t["outcome"] == "ok");
        Assert.DoesNotContain("tok.a", host.LogOutput, StringComparison.Ordinal);
        Assert.DoesNotContain(host.Spans, s => s.Contains("startTime", StringComparison.Ordinal) || s.Contains("tok.a", StringComparison.Ordinal));
    }

    /// <summary>FU-077 M-2: every attempt costs a permit (1 + 3 retries = 4); the budget refuses a 5th call before any request.</summary>
    [Fact]
    public async Task EveryRetryCostsAPermit()
    {
        // TokenLimit 5, WorkerShare 0.2: the API partition holds 4 permits.
        await using var host = PlayClientHost.Start(play, Budget(5));
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 503);

        var failed = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));
        var denied = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.ServerError, failed.Outcome);
        Assert.Equal(PlayCallOutcome.BudgetDenied, denied.Outcome);
        Assert.Equal(4, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task ADenialMidRetryStopsTheRetries()
    {
        // TokenLimit 3: the API partition holds 2 permits.
        await using var host = PlayClientHost.Start(play, Budget(3));
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 503);

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.BudgetDenied, error.Outcome);
        Assert.Equal(2, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task EachPartitionRefusesTheOtherPartitionsLanesWithoutARequest()
    {
        await using var api = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody("ref"));

        var refused = await Assert.ThrowsAsync<PlayApiException>(() => api.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Notification, CancellationToken.None));

        Assert.Equal(PlayCallOutcome.BudgetDenied, refused.Outcome);
        Assert.Equal(0, play.Count("GET", PlayWireMock.SubscriptionPath(token)));

        await using var worker = PlayClientHost.Start(play, playPartition: PlayBudgetPartition.Worker);
        Assert.Equal(PlayCallOutcome.BudgetDenied, (await Assert.ThrowsAsync<PlayApiException>(() => worker.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None))).Outcome);
        await worker.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Notification, CancellationToken.None);
        await worker.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Ack, CancellationToken.None);
        Assert.Equal(2, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    /// <summary>§5 (as Apple's FU-092 item 3): a 429 asking for more than 5 s is not retried inline; the caller defers for Play's value.</summary>
    [Theory]
    [InlineData(429, PlayCallOutcome.RateLimited)]
    [InlineData(503, PlayCallOutcome.ServerError)]
    public async Task ALongRetryAfterIsNotRetriedInline(int status, PlayCallOutcome outcome)
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), status, retryAfter: "120");

        var error = await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(outcome, error.Outcome);
        Assert.Equal(TimeSpan.FromSeconds(120), error.RetryAfter);
        Assert.Equal(1, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task AShortRetryAfterIsStillRetriedInline()
    {
        await using var host = PlayClientHost.Start(play);
        var token = NewToken();
        play.Get(PlayWireMock.SubscriptionPath(token), 429, retryAfter: "0");

        await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(4, play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    /// <summary>FU-098 nit 7: the date form of <c>Retry-After</c> is measured against the injected clock, not the machine's.</summary>
    [Fact]
    public void TheRetryAfterDateUsesTheInjectedClock()
    {
        var now = new DateTimeOffset(2030, 1, 1, 0, 0, 0, TimeSpan.Zero);
        using var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
        response.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(now.AddMinutes(10));

        Assert.Equal(TimeSpan.FromMinutes(10), PlayDeveloperApiClient.RetryAfter(response, new At(now)));
        Assert.True(PurchasesServiceCollectionExtensions.ShouldRetry(Polly.Outcome.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)), new At(now)));

        using var late = new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
        late.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(now.AddSeconds(30));
        Assert.False(PurchasesServiceCollectionExtensions.ShouldRetry(Polly.Outcome.FromResult(late), new At(now)));
        Assert.True(PurchasesServiceCollectionExtensions.ShouldRetry(Polly.Outcome.FromResult(late), new At(now.AddSeconds(26))));
    }

    private static Dictionary<string, string?> Budget(int total) => new()
    {
        ["Purchases:Google:Budget:TokenLimit"] = total.ToString(System.Globalization.CultureInfo.InvariantCulture),
        ["Purchases:Google:Budget:TokensPerPeriod"] = "1",
        ["Purchases:Google:Budget:PeriodSeconds"] = "3600",
    };

    private static string NewToken() => "tok." + Guid.NewGuid().ToString("N");

    private sealed class At(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
