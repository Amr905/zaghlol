using System.Net;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>
/// T-130 end to end: <c>POST /v1/purchases/verify</c> (Android) through the real pipeline, a migrated PostgreSQL and a WireMock
/// Play Developer API, plus the acknowledge sweeper on the Worker login (AC 1-4, the 502 path, idempotency).
/// </summary>
[Collection(ApiHostGroup.Name)]
public class PurchaseVerifyEndpointTests(PurchasesHostFixture fixture) : IClassFixture<PurchasesHostFixture>
{
    private PlayWireMock Play => fixture.Play;

    // AC 1.

    [Theory]
    [InlineData(400)]
    [InlineData(404)]
    [InlineData(410)]
    public async Task ATokenPlayRejectsIsAFinal422TokenInvalidThatIsReplayed(int status)
    {
        var (_, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(token), status);
        var key = InstallsHostFixture.NewKey();
        var body = PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, token);

        using var first = await fixture.VerifyAsync(install, body, key);
        using var replay = await fixture.VerifyAsync(install, body, key);

        await ProblemAssert.AssertAsync(first, HttpStatusCode.UnprocessableEntity, "PURCHASE_TOKEN_INVALID");
        await ProblemAssert.AssertAsync(replay, HttpStatusCode.UnprocessableEntity, "PURCHASE_TOKEN_INVALID");
        Assert.Equal(1, Play.Count("GET", PlayWireMock.SubscriptionPath(token)));
        Assert.Null(await fixture.RowAsync(token));
    }

    [Fact]
    public async Task AnotherProductsTokenIsTokenInvalid()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(Ref(installId), productId: PlayWireMock.Monthly));

        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, token));

        await ProblemAssert.AssertAsync(response, HttpStatusCode.UnprocessableEntity, "PURCHASE_TOKEN_INVALID");
        Assert.Null(await fixture.RowAsync(token));
    }

    [Fact]
    public async Task ATokenBoundToAnotherInstallOrToNoneIsNotOwnedAndNothingIsWritten()
    {
        var (buyerId, _) = await fixture.NewInstallAsync();
        var (_, replayer) = await fixture.NewInstallAsync();
        var bound = PurchasesHostFixture.NewPlayToken();
        var unbound = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(bound), 200, PlayWireMock.SubscriptionBody(Ref(buyerId)));
        Play.Get(PlayWireMock.ProductPath(unbound), 200, PlayWireMock.ProductBody(obfuscatedAccountId: null));

        using var replayed = await fixture.VerifyAsync(replayer, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, bound));
        using var noBinding = await fixture.VerifyAsync(replayer, PurchasesHostFixture.AndroidBody(PlayWireMock.Lifetime, unbound));

        await ProblemAssert.AssertAsync(replayed, HttpStatusCode.UnprocessableEntity, "PURCHASE_NOT_OWNED");
        await ProblemAssert.AssertAsync(noBinding, HttpStatusCode.UnprocessableEntity, "PURCHASE_NOT_OWNED");
        Assert.Null(await fixture.RowAsync(bound));
        Assert.Null(await fixture.RowAsync(unbound));
        Assert.Equal(0, Play.CountContaining("POST", ":acknowledge"));
    }

    [Fact]
    public async Task AnUnknownProductOrAnOverlongTokenIs422WithoutAnyPlayCall()
    {
        var (_, install) = await fixture.NewInstallAsync();
        var before = Play.Received().Count;

        using var wrongApp = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody("com.other.gold", PurchasesHostFixture.NewPlayToken()));
        using var tooLong = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, new string('a', 513)));
        using var dots = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, ".."));

        await ProblemAssert.AssertAsync(wrongApp, HttpStatusCode.UnprocessableEntity, "PURCHASE_WRONG_APP");
        await ProblemAssert.AssertAsync(tooLong, HttpStatusCode.UnprocessableEntity, "PURCHASE_TOKEN_INVALID");
        await ProblemAssert.AssertAsync(dots, HttpStatusCode.UnprocessableEntity, "PURCHASE_TOKEN_INVALID");
        Assert.Equal(before, Play.Received().Count);
    }

    // AC 2.

    [Fact]
    public async Task APendingPurchaseGrantsNothingAndIsNeverAcknowledged()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var subscription = PurchasesHostFixture.NewPlayToken();
        var lifetime = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(subscription), 200, PlayWireMock.SubscriptionBody(Ref(installId), "SUBSCRIPTION_STATE_PENDING"));
        Play.Get(PlayWireMock.ProductPath(lifetime), 200, PlayWireMock.ProductBody(Ref(installId), "PENDING"));

        using var sub = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, subscription));
        using var prod = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Lifetime, lifetime));

        foreach (var response in new[] { sub, prod })
        {
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("pending", json.RootElement.GetProperty("status").GetString());
            Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("entitlement").ValueKind);
        }

        Assert.Equal("pending", (await fixture.RowAsync(subscription))!.Value.State);
        Assert.Equal("pending", (await fixture.RowAsync(lifetime))!.Value.State);
        Assert.Equal(0, Play.Count("POST", PlayWireMock.SubscriptionAckPath(PlayWireMock.Yearly, subscription)));
        Assert.Equal(0, Play.Count("POST", PlayWireMock.ProductAckPath(PlayWireMock.Lifetime, lifetime)));
    }

    // AC 3: the inline acknowledge fails, the sweeper acknowledges.

    [Fact]
    public async Task AFailedInlineAcknowledgeStillAnswersActiveAndTheSweeperAcknowledgesOnce()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        var ackPath = PlayWireMock.SubscriptionAckPath(PlayWireMock.Monthly, token);
        Play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(Ref(installId), productId: PlayWireMock.Monthly));
        Play.Acknowledge(ackPath, 500);

        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Monthly, token));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using (var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync()))
        {
            Assert.Equal("active", json.RootElement.GetProperty("status").GetString());
        }

        Assert.Equal(4, Play.Count("POST", ackPath)); // 1 + 3 retries, all 500
        Assert.False((await fixture.RowAsync(token))!.Value.Acknowledged);

        // Play recovers; the sweeper acknowledges with the Play-returned product ID, once.
        Play.Acknowledge(ackPath, 200);
        fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        var run = await fixture.SweeperAsync();

        Assert.True(run.Ran);
        Assert.Equal(5, Play.Count("POST", ackPath));
        Assert.True((await fixture.RowAsync(token))!.Value.Acknowledged);
    }

    [Fact]
    public async Task APurchaseUnacknowledgedFor48HoursSetsTheGaugeAndFiresTheAuditAlert()
    {
        var (installId, _) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        await fixture.ExecuteAsync(
            """
            INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, install_id, state, acknowledged, environment, last_verified_at, created_at)
            VALUES (@id, 'google_play', 'zaghlol_gold_yearly', 'yearly', @key, @install, 'active', false, 'production', @verified, @created)
            """,
            ("id", Guid.NewGuid()),
            ("key", token),
            ("install", Guid.Parse(installId)),
            ("verified", fixture.Clock.GetUtcNow().AddHours(-49)),
            ("created", fixture.Clock.GetUtcNow().AddHours(-49)));
        Play.Get(PlayWireMock.SubscriptionPath(token), 503);
        fixture.StartMeters();

        await using var services = fixture.SweeperServices();
        var run = await services.GetRequiredService<PlayAckSweepJob>().RunOnceAsync(CancellationToken.None);
        fixture.RecordGauges();

        Assert.True(run.Ran);
        Assert.False((await fixture.RowAsync(token))!.Value.Acknowledged);
        Assert.Contains(fixture.Measurements, m => m.Instrument == "zaghlol.purchase.unacked" && m.Tags["age"] == "ge_48h" && m.Value >= 1);
        Assert.Contains(fixture.Measurements, m => m.Instrument == "zaghlol.audit_alert.fired" && m.Tags["rule"] == "purchase_unacked_48h" && m.Value == 1);
    }

    // AC 4.

    [Fact]
    public async Task ALifetimePurchaseUsesProductsV2AndNeverTheV1Endpoint()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.ProductPath(token), 200, PlayWireMock.ProductBody(Ref(installId), test: true));
        Play.Acknowledge(PlayWireMock.ProductAckPath(PlayWireMock.Lifetime, token));

        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Lifetime, token));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, Play.Count("GET", PlayWireMock.ProductPath(token)));
        Assert.Equal(1, Play.Count("POST", PlayWireMock.ProductAckPath(PlayWireMock.Lifetime, token)));
        Assert.Equal(0, Play.CountContaining("GET", "/purchases/products/"));
        var row = (await fixture.RowAsync(token))!.Value;
        Assert.Equal("active", row.State);
        Assert.Equal("sandbox", row.Environment);
        Assert.True(row.Acknowledged);
        Assert.Equal(Guid.Parse(installId), row.InstallId);
    }

    // Outages: 502, never stored, the retry runs again.

    [Theory]
    [InlineData(503)]
    [InlineData(401)]
    [InlineData(403)]
    public async Task APlayFailureIs502StoreUnavailableAndARetryRunsAgain(int status)
    {
        var (_, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(token), status);
        var key = InstallsHostFixture.NewKey();
        var body = PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, token);

        using var first = await fixture.VerifyAsync(install, body, key);
        var calls = Play.Count("GET", PlayWireMock.SubscriptionPath(token));
        using var retry = await fixture.VerifyAsync(install, body, key);

        await ProblemAssert.AssertAsync(first, HttpStatusCode.BadGateway, "STORE_UNAVAILABLE");
        Assert.NotNull(first.Headers.RetryAfter?.Delta);
        await ProblemAssert.AssertAsync(retry, HttpStatusCode.BadGateway, "STORE_UNAVAILABLE");
        Assert.True(Play.Count("GET", PlayWireMock.SubscriptionPath(token)) > calls);
        Assert.Null(await fixture.RowAsync(token));
    }

    [Fact]
    public async Task IosIs503UntilT131()
    {
        var (_, install) = await fixture.NewInstallAsync();

        using var response = await fixture.VerifyAsync(install, "{\"platform\":\"ios\",\"signedTransaction\":\"eyJhbGciOiJFUzI1NiJ9.e30.c2ln\"}");

        await ProblemAssert.AssertAsync(response, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE");
    }

    [Theory]
    [InlineData("{\"platform\":\"android\",\"productId\":\"zaghlol_gold_yearly\",\"purchaseToken\":\"t1\",\"amount\":\"9.99\"}", "UNKNOWN_FIELD")]
    [InlineData("{\"platform\":\"android\",\"productId\":\"zaghlol_gold_yearly\",\"purchaseToken\":\"t1\",\"signedTransaction\":\"x\"}", "UNKNOWN_FIELD")]
    [InlineData("{\"platform\":\"android\",\"productId\":\"zaghlol_gold_yearly\"}", "VALIDATION_FAILED")]
    [InlineData("{\"platform\":\"windows\",\"productId\":\"zaghlol_gold_yearly\",\"purchaseToken\":\"t1\"}", "VALIDATION_FAILED")]
    [InlineData("{\"platform\":\"android\",\"productId\":\"Zaghlol Gold\",\"purchaseToken\":\"t1\"}", "VALIDATION_FAILED")]
    public async Task AMalformedBodyIs400(string body, string code)
    {
        var (_, install) = await fixture.NewInstallAsync();

        using var response = await fixture.VerifyAsync(install, body);

        await ProblemAssert.AssertAsync(response, HttpStatusCode.BadRequest, code);
    }

    [Fact]
    public async Task AnActiveAnswerIsSignedEchoesTheNonceAndIsReplayedWithoutAnotherPlayCall()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(Ref(installId), "SUBSCRIPTION_STATE_CANCELED", expiry: DateTimeOffset.UtcNow.AddDays(3), acknowledged: true));
        var key = InstallsHostFixture.NewKey();
        var nonce = PurchasesHostFixture.Nonce();
        var body = PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, token);

        using var first = await fixture.VerifyAsync(install, body, key, nonce);
        using var replay = await fixture.VerifyAsync(install, body, key, PurchasesHostFixture.Nonce());

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.True(first.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        var text = await first.Content.ReadAsStringAsync();
        using (var json = JsonDocument.Parse(text))
        {
            Assert.Equal("active", json.RootElement.GetProperty("status").GetString()); // canceled_active keeps Gold
            Assert.Equal(nonce, json.RootElement.GetProperty("timeNonce").GetString());
            Assert.False(json.RootElement.TryGetProperty("rotateInstallToken", out _));
        }

        Assert.Equal("canceled_active", (await fixture.RowAsync(token))!.Value.State);
        Assert.Equal(text, await replay.Content.ReadAsStringAsync());
        Assert.Equal(1, Play.Count("GET", PlayWireMock.SubscriptionPath(token)));
    }

    [Fact]
    public async Task TheSameKeyRunningTwiceGivesOne200AndOne429()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var token = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(Ref(installId), acknowledged: true), delay: TimeSpan.FromSeconds(1));
        var key = InstallsHostFixture.NewKey();
        var body = PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, token);

        var slow = fixture.VerifyAsync(install, body, key);
        await Task.Delay(300);
        using var second = await fixture.VerifyAsync(install, body, key);
        using var winner = await slow;

        Assert.Equal(HttpStatusCode.OK, winner.StatusCode);
        await ProblemAssert.AssertAsync(second, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        Assert.Equal(TimeSpan.FromSeconds(1), second.Headers.RetryAfter?.Delta);
    }

    [Fact]
    public async Task AnUpgradeRecordsItsPredecessorAndNeverTouchesIt()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var old = PurchasesHostFixture.NewPlayToken();
        var upgrade = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(old), 200, PlayWireMock.SubscriptionBody(Ref(installId), productId: PlayWireMock.Monthly, acknowledged: true));
        Play.Get(PlayWireMock.SubscriptionPath(upgrade), 200, PlayWireMock.SubscriptionBody(Ref(installId), linkedPurchaseToken: old, acknowledged: true));

        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Monthly, old)))
        {
        }

        var before = (await fixture.RowAsync(old))!.Value;
        fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, upgrade));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(old, (await fixture.RowAsync(upgrade))!.Value.Linked);
        Assert.Equal(before, (await fixture.RowAsync(old))!.Value);
    }

    private static string Ref(string installId) => StoreBindingRef.Compute(InstallId.Parse(installId));
}
