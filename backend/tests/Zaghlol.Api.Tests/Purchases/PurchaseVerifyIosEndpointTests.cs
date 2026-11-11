using System.Net;
using System.Text.Json;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>
/// T-131 end to end: <c>POST /v1/purchases/verify</c> (iOS) through the real pipeline, a migrated PostgreSQL, the real JWS verifier
/// over a test PKI and WireMock App Store servers for both environments.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class PurchaseVerifyIosEndpointTests(PurchasesHostFixture fixture) : IClassFixture<PurchasesHostFixture>
{
    private AppleWireMock Apple => fixture.Apple;

    [Fact]
    public async Task AnActiveSubscriptionIsVerifiedSignedGrantedAndReplayedWithoutAnotherAppleCall()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        fixture.Grant.AlwaysGrantFor(installId);
        var (jws, transactionId, original) = fixture.ApplePurchase(Ref(installId));
        var key = InstallsHostFixture.NewKey();
        var nonce = PurchasesHostFixture.Nonce();

        using var first = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws), key, nonce);
        using var replay = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws), key, PurchasesHostFixture.Nonce());

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.True(first.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        var text = await first.Content.ReadAsStringAsync();
        using (var json = JsonDocument.Parse(text))
        {
            Assert.Equal("active", json.RootElement.GetProperty("status").GetString());
            Assert.Equal(GrantingVerifyGrant.Token, json.RootElement.GetProperty("entitlement").GetProperty("token").GetString());
            Assert.Equal(nonce, json.RootElement.GetProperty("timeNonce").GetString());
        }

        Assert.Equal(text, await replay.Content.ReadAsStringAsync());
        Assert.Equal(1, Apple.Count(false, AppleWireMock.TransactionPath(transactionId)));
        Assert.Equal(1, Apple.Count(false, AppleWireMock.SubscriptionsPath(transactionId)));
        var row = (await fixture.AppleRowAsync(original))!.Value;
        Assert.Equal("active", row.State);
        Assert.True(row.Acknowledged);
        Assert.Equal(Guid.Parse(installId), row.InstallId);
        Assert.Equal("production", row.Environment);
        Assert.Equal(Ref(installId), row.Ref);
        Assert.NotNull(row.LastPaymentAt);
        Assert.Contains(fixture.Grant.Calls, c => c.Install == Guid.Parse(installId) && c.Status == VerifyStatus.Active);
    }

    [Fact]
    public async Task ASandboxPurchaseGoesOnlyToTheSandboxServerAndIsRecordedAsSandbox()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var (jws, transactionId, original) = fixture.ApplePurchase(Ref(installId), "Sandbox");

        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, Apple.Count(true, AppleWireMock.TransactionPath(transactionId)));
        Assert.Equal(0, Apple.Count(false, AppleWireMock.TransactionPath(transactionId)));
        Assert.Equal("sandbox", (await fixture.AppleRowAsync(original))!.Value.Environment);
    }

    [Fact]
    public async Task AnotherInstallsOrNoBindingIsNotOwnedAndNothingIsWritten()
    {
        var (buyerId, _) = await fixture.NewInstallAsync();
        var (_, caller) = await fixture.NewInstallAsync();
        var foreign = fixture.ApplePurchase(Ref(buyerId));
        var unbound = fixture.ApplePurchase(null);

        using var a = await fixture.VerifyAsync(caller, PurchasesHostFixture.IosBody(foreign.Jws));
        using var b = await fixture.VerifyAsync(caller, PurchasesHostFixture.IosBody(unbound.Jws));

        await ProblemAssert.AssertAsync(a, HttpStatusCode.UnprocessableEntity, "PURCHASE_NOT_OWNED");
        await ProblemAssert.AssertAsync(b, HttpStatusCode.UnprocessableEntity, "PURCHASE_NOT_OWNED");
        Assert.Null(await fixture.AppleRowAsync(foreign.OriginalTransactionId));
        Assert.Null(await fixture.AppleRowAsync(unbound.OriginalTransactionId));
    }

    [Fact]
    public async Task ATamperedJwsIsTokenInvalidWithNoAppleCall()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var (jws, transactionId, original) = fixture.ApplePurchase(Ref(installId));
        var parts = jws.Split('.');
        var tampered = parts[0] + "." + parts[1] + "." + (parts[2][0] == 'A' ? 'B' : 'A') + parts[2][1..];

        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(tampered));

        await ProblemAssert.AssertAsync(response, HttpStatusCode.UnprocessableEntity, "PURCHASE_TOKEN_INVALID");
        Assert.Equal(0, Apple.Count(false, AppleWireMock.TransactionPath(transactionId)));
        Assert.Null(await fixture.AppleRowAsync(original));
    }

    [Fact]
    public async Task AnAppleOutageIs502WithRetryAfterAndARetryRunsAgain()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var (jws, transactionId, original) = fixture.ApplePurchase(Ref(installId));
        Apple.Get(false, AppleWireMock.TransactionPath(transactionId), 503);
        var key = InstallsHostFixture.NewKey();

        using var first = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws), key);
        await ProblemAssert.AssertAsync(first, HttpStatusCode.BadGateway, "STORE_UNAVAILABLE");
        Assert.NotNull(first.Headers.RetryAfter);
        Assert.Null(await fixture.AppleRowAsync(original));

        Apple.Get(false, AppleWireMock.TransactionPath(transactionId), 200, AppleWireMock.TransactionInfoBody(jws));
        using var retry = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws), key);
        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
    }

    [Fact]
    public async Task AnExpiredSubscriptionAnswersExpiredAndNeverReachesTheGrant()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        fixture.Grant.AlwaysGrantFor(installId);
        var (jws, _, original) = fixture.ApplePurchase(Ref(installId), status: 2, autoRenew: 0, expires: DateTimeOffset.UtcNow.AddDays(-2));

        using var response = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("expired", json.RootElement.GetProperty("status").GetString());
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("entitlement").ValueKind);
        Assert.Equal("expired", (await fixture.AppleRowAsync(original))!.Value.State);
        Assert.DoesNotContain(fixture.Grant.Calls, c => c.Install == Guid.Parse(installId));
    }

    [Fact]
    public async Task SeatKeysArePassedThroughUntouchedAndAndroidFieldsAreRefused()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var (jws, _, _) = fixture.ApplePurchase(Ref(installId));
        var withSeatKey = "{\"platform\":\"ios\",\"signedTransaction\":\"" + jws + "\",\"seatKeys\":[{\"publicKey\":\"BPx\",\"signature\":\"Mz\"}]}";

        using var accepted = await fixture.VerifyAsync(install, withSeatKey);
        using var productId = await fixture.VerifyAsync(install, "{\"platform\":\"ios\",\"signedTransaction\":\"" + jws + "\",\"productId\":\"zaghlol_gold_yearly\"}");
        using var empty = await fixture.VerifyAsync(install, "{\"platform\":\"ios\",\"signedTransaction\":\"\"}");

        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        await ProblemAssert.AssertAsync(productId, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
        await ProblemAssert.AssertAsync(empty, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task NoIdentifierOrJwsReachesTheApiLogs()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var (jws, transactionId, original) = fixture.ApplePurchase(Ref(installId));
        var (foreignJws, foreignId, foreignOriginal) = fixture.ApplePurchase(Ref(Guid.NewGuid().ToString("D")));

        using var ok = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws));
        using var notOwned = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(foreignJws));
        using var forged = await fixture.VerifyAsync(install, PurchasesHostFixture.IosBody(jws[..^2] + "AA"));

        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, notOwned.StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, forged.StatusCode);
        Assert.NotEmpty(fixture.LogSink.Entries);
        foreach (var secret in new[] { jws, jws.Split('.')[1], transactionId, original, foreignJws, foreignId, foreignOriginal, Ref(installId) })
        {
            Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(secret, StringComparison.Ordinal));
        }
    }

    private static string Ref(string installId) => StoreBindingRef.Compute(InstallId.Parse(installId));
}
