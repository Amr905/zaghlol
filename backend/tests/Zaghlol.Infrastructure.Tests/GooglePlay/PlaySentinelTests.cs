using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>
/// AC 8 (D-57): a sentinel order ID and a sentinel purchase token go through a success, a Polly retry (503 then 200) and
/// exception paths (404, 500 until retries run out, a timeout) of the real client, with every log category at Verbose, the
/// production log formatter and the real span pipeline. Neither sentinel appears in a log byte, a span or an exception text.
/// Positive controls show the calls, the retries and their logs happened.
/// </summary>
[Collection(PlayClientGroup.Name)]
public sealed class PlaySentinelTests : IDisposable
{
    private readonly PlayWireMock play = new();

    public void Dispose() => play.Dispose();

    [Fact]
    public async Task NeitherTheOrderIdNorTheTokenAppearsInLogsSpansOrExceptions()
    {
        var marker = Guid.NewGuid().ToString("N")[..12];
        var token = "SNTtok" + marker + ".x-y_z";
        var orderId = "GPA.SNTord" + marker;
        var missingToken = "SNTmissing" + marker;
        var missingOrder = "GPA.SNTgone" + marker;
        var failingToken = "SNTfail" + marker;
        var slowOrder = "GPA.SNTslow" + marker;

        await using var host = PlayClientHost.Start(play, new Dictionary<string, string?>
        {
            ["Purchases:Google:Resilience:AttemptTimeoutMs"] = "2000",
            ["Purchases:Google:Resilience:TotalTimeoutMs"] = "4000",

            // Keep the circuit closed here, so the last call is a real timeout (the open-circuit path has its own test).
            ["Purchases:Google:Resilience:MinimumThroughput"] = "100",
        });
        play.GetAfterFailures(PlayWireMock.SubscriptionPath(token), 1, 503, PlayWireMock.SubscriptionBody("ref", latestSuccessfulOrderId: orderId));
        play.GetAfterFailures(PlayWireMock.OrderPath(orderId), 1, 503, PlayWireMock.OrderBody(token, "PROCESSED"));
        play.Get(PlayWireMock.SubscriptionPath(missingToken), 404, "{\"error\":\"" + missingToken + "\"}");
        play.Get(PlayWireMock.OrderPath(missingOrder), 404, "{\"error\":\"" + missingOrder + "\"}");
        play.Get(PlayWireMock.ProductPath(failingToken), 500, "{\"error\":\"" + failingToken + "\"}");
        play.Get(PlayWireMock.OrderPath(slowOrder), 200, PlayWireMock.OrderBody(token, "PROCESSED"), delay: TimeSpan.FromSeconds(8));

        var sub = await host.Api.GetSubscriptionAsync(new Sensitive<string>(token), StoreLane.Verify, CancellationToken.None);
        var order = await host.Api.GetOrderAsync(new Sensitive<string>(orderId), StoreLane.Support, CancellationToken.None);
        var errors = new List<PlayApiException>
        {
            await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetSubscriptionAsync(new Sensitive<string>(missingToken), StoreLane.Verify, CancellationToken.None)),
            await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetOrderAsync(new Sensitive<string>(missingOrder), StoreLane.Support, CancellationToken.None)),
            await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetProductAsync(new Sensitive<string>(failingToken), StoreLane.Verify, CancellationToken.None)),
            await Assert.ThrowsAsync<PlayApiException>(() => host.Api.GetOrderAsync(new Sensitive<string>(slowOrder), StoreLane.Support, CancellationToken.None)),
        };

        // Positive controls: the success and retry paths ran, the failures are the expected kinds, and Polly logged its retries.
        Assert.Equal(orderId, sub.LineItems.Single().LatestSuccessfulOrderId?.Reveal());
        Assert.Equal(PlayOrderState.Processed, order.State);
        Assert.True(play.Count("GET", PlayWireMock.SubscriptionPath(token)) >= 2, "the token's read was retried");
        Assert.True(play.Count("GET", PlayWireMock.OrderPath(orderId)) >= 2, "the order's read was retried");
        Assert.Equal(4, play.Count("GET", PlayWireMock.ProductPath(failingToken)));
        Assert.Equal(
            [PlayCallOutcome.ClientError, PlayCallOutcome.ClientError, PlayCallOutcome.ServerError, PlayCallOutcome.Timeout],
            errors.Select(e => e.Outcome));
        var log = host.LogOutput;
        Assert.Contains("\"category\":\"Polly", log, StringComparison.Ordinal);
        Assert.Contains(host.Spans, s => s.Contains("url.template=/androidpublisher/v3/applications/{packageName}/orders/{orderId}", StringComparison.Ordinal));
        Assert.Contains(host.Spans, s => s.Contains("url.template=/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}", StringComparison.Ordinal));

        // The sentinels: nowhere.
        foreach (var secret in new[] { marker, token, orderId, missingToken, missingOrder, failingToken, slowOrder })
        {
            Assert.DoesNotContain(secret, log, StringComparison.Ordinal);
            Assert.DoesNotContain(host.Spans, s => s.Contains(secret, StringComparison.Ordinal));
            Assert.All(errors, e => Assert.DoesNotContain(secret, e.ToString(), StringComparison.Ordinal));
        }

        // The Sensitive wrappers never render their value either.
        Assert.Equal("***", sub.LineItems.Single().LatestSuccessfulOrderId.ToString());
        Assert.DoesNotContain(orderId, sub.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(token, order.ToString(), StringComparison.Ordinal);
    }
}
