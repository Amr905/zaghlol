using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.Tests.GooglePlay;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>
/// T-131 §6: the App Store Server API client over HTTP (two WireMock servers, one per environment): routing, parsing, error mapping,
/// the bearer token, the per-attempt budget and the call metric.
/// </summary>
[Collection(PlayClientGroup.Name)]
public sealed class AppStoreClientTests : IDisposable
{
    private readonly PlayWireMock play = new();
    private readonly AppleWireMock apple = new();

    public void Dispose()
    {
        play.Dispose();
        apple.Dispose();
    }

    [Theory]
    [InlineData(PurchaseEnvironment.Production)]
    [InlineData(PurchaseEnvironment.Sandbox)]
    public async Task EachEnvironmentGoesOnlyToItsOwnServerWithAnAppleBearerToken(PurchaseEnvironment environment)
    {
        await using var host = Start();
        var sandbox = environment == PurchaseEnvironment.Sandbox;
        var id = AppleWireMock.NewTransactionId();
        apple.Get(sandbox, AppleWireMock.TransactionPath(id), 200, AppleWireMock.TransactionInfoBody("a.b.c"));

        var signed = await host.AppStore.GetTransactionInfoAsync(environment, new Sensitive<string>(id), StoreLane.Verify, CancellationToken.None);

        Assert.Equal("a.b.c", signed.Reveal());
        var request = Assert.Single(apple.Received());
        Assert.Equal(sandbox ? "sandbox" : "production", request.Environment);
        Assert.StartsWith("Bearer ", request.Authorization, StringComparison.Ordinal);
        var jwt = request.Authorization!["Bearer ".Length..].Split('.');
        using var claims = JsonDocument.Parse(Base64Url.DecodeFromChars(jwt[1]));
        Assert.Equal(AppleWireMock.BundleId, claims.RootElement.GetProperty("bid").GetString());
        Assert.True(apple.ApiKey.VerifyData(Encoding.ASCII.GetBytes(jwt[0] + "." + jwt[1]), Base64Url.DecodeFromChars(jwt[2]), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
        Assert.Contains(host.StoreCalls(), t => t["api"] == "tx_get" && t["outcome"] == "ok" && t["env"] == (sandbox ? "sandbox" : "production") && t["store"] == "app_store");
    }

    [Fact]
    public async Task StatusesAndLookupsAreReadWithOnlyTheFieldsWeUse()
    {
        await using var host = Start();
        var id = AppleWireMock.NewTransactionId();
        apple.Get(false, AppleWireMock.SubscriptionsPath(id), 200, AppleWireMock.StatusBody("Production", (4, "2000000000000001", "t.t.t", "r.r.r"), (2, "2000000000000002", "u.u.u", "s.s.s")));
        apple.Get(false, AppleWireMock.LookupPath("MK5TTTVWJH"), 200, AppleWireMock.LookupBody(0, "x.x.x", "y.y.y"));

        var items = await host.AppStore.GetAllSubscriptionStatusesAsync(PurchaseEnvironment.Production, new Sensitive<string>(id), StoreLane.Verify, CancellationToken.None);
        var lookup = await host.AppStore.LookUpOrderIdAsync(new Sensitive<string>("MK5TTTVWJH"), StoreLane.Support, CancellationToken.None);

        Assert.Equal(2, items.Count);
        Assert.Equal(4, items[0].Status);
        Assert.Equal("2000000000000001", items[0].OriginalTransactionId?.Reveal());
        Assert.Equal("t.t.t", items[0].SignedTransactionInfo?.Reveal());
        Assert.Equal("r.r.r", items[0].SignedRenewalInfo?.Reveal());
        Assert.Equal(0, lookup.Status);
        Assert.Equal(["x.x.x", "y.y.y"], lookup.SignedTransactions.Select(s => s.Reveal()));
        Assert.Empty(apple.Sandbox.LogEntries);
    }

    [Theory]
    [InlineData(404, 4040010L, AppStoreCallOutcome.ClientError, 1)]
    [InlineData(400, 4000006L, AppStoreCallOutcome.ClientError, 1)]
    [InlineData(404, null, AppStoreCallOutcome.ClientError, 1)]
    [InlineData(401, null, AppStoreCallOutcome.AuthError, 1)]
    [InlineData(500, null, AppStoreCallOutcome.ServerError, 4)]
    [InlineData(429, 4290000L, AppStoreCallOutcome.RateLimited, 4)]
    public async Task ErrorsMapToOutcomesAndOnlyTransientOnesAreRetried(int status, long? code, AppStoreCallOutcome outcome, int attempts)
    {
        await using var host = Start();
        var id = AppleWireMock.NewTransactionId();
        apple.Get(false, AppleWireMock.TransactionPath(id), status, code is { } c ? AppleWireMock.ErrorBody(c) : null);

        var error = await Assert.ThrowsAsync<AppStoreApiException>(() =>
            host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(id), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(outcome, error.Outcome);
        Assert.Equal(status, error.HttpStatus);
        Assert.Equal(attempts, apple.Count(false, AppleWireMock.TransactionPath(id)));
        Assert.Equal(status == 404 && code == 4040010, error.IsTransactionNotFound);
        Assert.Equal(status == 400 && code == 4000006, error.IsInvalidTransactionId);
        Assert.Equal(0, apple.Count(true, AppleWireMock.TransactionPath(id)));
    }

    [Fact]
    public async Task EveryHttpAttemptRetriesIncludedIsChargedToTheBudget()
    {
        // Three permits per replica and no notification reserve to speak of: a call retried twice spends all three.
        await using var host = Start(new Dictionary<string, string?>
        {
            ["Purchases:Apple:Budget:TokenLimit"] = "3",
            ["Purchases:Apple:Budget:TokensPerPeriod"] = "1",
            ["Purchases:Apple:Budget:PeriodSeconds"] = "3600",
        });
        var retried = AppleWireMock.NewTransactionId();
        var next = AppleWireMock.NewTransactionId();
        apple.GetAfterFailures(false, AppleWireMock.TransactionPath(retried), 2, 503, AppleWireMock.TransactionInfoBody("a.b.c"));
        apple.Get(false, AppleWireMock.TransactionPath(next), 200, AppleWireMock.TransactionInfoBody("d.e.f"));

        await host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(retried), StoreLane.Verify, CancellationToken.None);
        var denied = await Assert.ThrowsAsync<AppStoreApiException>(() =>
            host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(next), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(3, apple.Count(false, AppleWireMock.TransactionPath(retried)));
        Assert.Equal(AppStoreCallOutcome.BudgetDenied, denied.Outcome);
        Assert.Equal(0, apple.Count(false, AppleWireMock.TransactionPath(next)));
    }

    [Fact]
    public async Task AnUnparsableSuccessIsAServerErrorNeverAnAnswer()
    {
        await using var host = Start();
        var id = AppleWireMock.NewTransactionId();
        apple.Get(false, AppleWireMock.TransactionPath(id), 200, "{\"signedTransactionInfo\":42}");

        var error = await Assert.ThrowsAsync<AppStoreApiException>(() =>
            host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(id), StoreLane.Verify, CancellationToken.None));

        Assert.Equal(AppStoreCallOutcome.ServerError, error.Outcome);
    }

    private PlayClientHost Start(Dictionary<string, string?>? extra = null)
    {
        var settings = new Dictionary<string, string?>(apple.Settings());
        foreach (var (key, value) in extra ?? [])
        {
            settings[key] = value;
        }

        return PlayClientHost.Start(play, settings);
    }
}

/// <summary>
/// AC 6 (D-57): sentinel order ID, transaction ID, original transaction ID, appAccountToken, JWS and bearer token go through a
/// success, a Polly retry (503 then 200) and exception paths (an error body echoing them, 500 until retries run out, a timeout) of
/// the real client, with every log category at Verbose, the production log formatter and the real span pipeline. None appears in a
/// log byte, a span or an exception text. Positive controls show the calls, retries and their logs happened.
/// </summary>
[Collection(PlayClientGroup.Name)]
public sealed class AppStoreSentinelTests : IDisposable
{
    private readonly PlayWireMock play = new();
    private readonly AppleWireMock apple = new();

    public void Dispose()
    {
        play.Dispose();
        apple.Dispose();
    }

    [Fact]
    public async Task NoIdentifierTokenOrJwsAppearsInLogsSpansOrExceptions()
    {
        var digits = string.Concat(RandomNumberGenerator.GetBytes(12).Select(b => (char)('0' + (b % 10))));
        var transactionId = "7" + digits + "31";
        var originalTransactionId = "7" + digits + "47";
        var missingId = "7" + digits + "59";
        var failingId = "7" + digits + "61";
        var slowId = "7" + digits + "73";
        var orderId = "SNTL" + digits[..10] + "Q";
        var install = InstallId.FromGuid(Guid.NewGuid());
        var appAccountToken = Zaghlol.Application.Purchases.StoreBindingRef.Compute(install);
        var jws = apple.Pki.Sign(AppleTestPki.Transaction(AppleWireMock.BundleId, AppleWireMock.Yearly, transactionId, originalTransactionId, appAccountToken));

        var settings = new Dictionary<string, string?>(apple.Settings())
        {
            ["Purchases:Apple:Resilience:AttemptTimeoutMs"] = "2000",
            ["Purchases:Apple:Resilience:TotalTimeoutMs"] = "4000",
        };
        await using var host = PlayClientHost.Start(play, settings);
        var bearer = host.Services.GetRequiredService<IAppStoreApiTokenSource>().GetToken()!.Value.Reveal();

        apple.GetAfterFailures(false, AppleWireMock.TransactionPath(transactionId), 1, 503, AppleWireMock.TransactionInfoBody(jws));
        apple.GetAfterFailures(false, AppleWireMock.LookupPath(orderId), 1, 503, AppleWireMock.LookupBody(0, jws));
        apple.Get(false, AppleWireMock.TransactionPath(missingId), 404, "{\"errorCode\":4040010,\"errorMessage\":\"" + missingId + " " + orderId + " " + jws + "\"}");
        apple.Get(false, AppleWireMock.SubscriptionsPath(failingId), 500, "{\"errorMessage\":\"" + failingId + appAccountToken + "\"}");
        apple.Get(false, AppleWireMock.TransactionPath(slowId), 200, AppleWireMock.TransactionInfoBody(jws), delay: TimeSpan.FromSeconds(8));

        var signed = await host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(transactionId), StoreLane.Verify, CancellationToken.None);
        var lookup = await host.AppStore.LookUpOrderIdAsync(new Sensitive<string>(orderId), StoreLane.Support, CancellationToken.None);
        var verified = new AppleJwsVerifier(apple.Pki.RootDer).VerifyTransaction(signed, JwsSource.Api, DateTimeOffset.UtcNow);
        var errors = new List<Exception>
        {
            await Assert.ThrowsAsync<AppStoreApiException>(() => host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(missingId), StoreLane.Verify, CancellationToken.None)),
            await Assert.ThrowsAsync<AppStoreApiException>(() => host.AppStore.GetAllSubscriptionStatusesAsync(PurchaseEnvironment.Production, new Sensitive<string>(failingId), StoreLane.Verify, CancellationToken.None)),
            await Assert.ThrowsAsync<AppStoreApiException>(() => host.AppStore.GetTransactionInfoAsync(PurchaseEnvironment.Production, new Sensitive<string>(slowId), StoreLane.Verify, CancellationToken.None)),
            Assert.Throws<AppleJwsException>(() => new AppleJwsVerifier(apple.Pki.RootDer).VerifyTransaction(new Sensitive<string>(jws + "x"), JwsSource.App, DateTimeOffset.UtcNow)),
        };

        // Positive controls.
        Assert.Equal(jws, signed.Reveal());
        Assert.Equal(appAccountToken, verified.AppAccountToken?.Reveal());
        Assert.Equal(jws, lookup.SignedTransactions.Single().Reveal());
        Assert.Equal(2, apple.Count(false, AppleWireMock.TransactionPath(transactionId)));
        Assert.Equal(2, apple.Count(false, AppleWireMock.LookupPath(orderId)));
        Assert.Equal(4, apple.Count(false, AppleWireMock.SubscriptionsPath(failingId)));
        Assert.True(((AppStoreApiException)errors[0]).IsTransactionNotFound);
        Assert.Equal(AppStoreCallOutcome.Timeout, ((AppStoreApiException)errors[2]).Outcome);
        Assert.All(apple.Received(), r => Assert.Equal("Bearer " + bearer, r.Authorization));
        var log = host.LogOutput;
        Assert.Contains("\"category\":\"Polly", log, StringComparison.Ordinal);
        Assert.Contains(host.Spans, s => s.Contains("url.template=" + AppStoreServerApiClient.TransactionTemplate, StringComparison.Ordinal));
        Assert.Contains(host.Spans, s => s.Contains("url.template=" + AppStoreServerApiClient.LookupTemplate, StringComparison.Ordinal));

        // The sentinels: nowhere.
        var sentinels = new[] { transactionId, originalTransactionId, missingId, failingId, slowId, orderId, appAccountToken, jws, jws.Split('.')[1], bearer };
        foreach (var secret in sentinels)
        {
            Assert.DoesNotContain(secret, log, StringComparison.Ordinal);
            Assert.DoesNotContain(host.Spans, s => s.Contains(secret, StringComparison.Ordinal));
            Assert.All(errors, e => Assert.DoesNotContain(secret, e.ToString(), StringComparison.Ordinal));
        }

        Assert.DoesNotContain(transactionId, verified.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(appAccountToken, verified.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(jws, lookup.ToString(), StringComparison.Ordinal);
    }
}
