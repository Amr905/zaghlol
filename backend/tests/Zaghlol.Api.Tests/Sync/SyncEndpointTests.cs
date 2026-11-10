using System.Buffers.Text;
using System.Globalization;
using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Signing;
using Zaghlol.Application.Sync;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Api.Tests.Sync;

/// <summary>
/// T-128 acceptance against the real pipeline and PostgreSQL: the 2 KB up-to-date answer, phone numbers dropped, the signed
/// throttle with only three members, the R4-2 nonce echo, failure modes, intake dedupe, daily-active counting and log privacy.
/// Every test uses installs (and app versions) of its own; the clock only moves forward.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class SyncEndpointTests(SyncHostFixture fixture) : IClassFixture<SyncHostFixture>
{
    private static readonly TimeSpan Window = TimeSpan.FromHours(24);

    private static readonly string[] ThrottleKeys = ["nextSyncNotBefore", "serverTime", "timeNonce"];

    private static readonly string[] FullKeys =
    [
        "accepted", "accountToken", "catalog", "entitlement", "flags", "nextSyncNotBefore", "prices", "serverTime", "supportNotice",
        "timeNonce",
    ];

    // ---- AC1: up to date is under 2 KB ---------------------------------------------------------------------------------

    [Fact]
    public async Task AnUpToDateResponseIsUnder2KbWithEveryBlockNull()
    {
        var appVersion = SyncHostFixture.UniqueAppVersion();
        var (_, token) = await fixture.NewInstallAsync(appVersion);
        var app = SyncHostFixture.AppHeader(appVersion);

        using var first = await fixture.SyncAsync(token, SyncHostFixture.Body(), app: app);
        var full = await ReadAsync(first);
        Assert.Equal(CatalogModes.Full, full.GetProperty("catalog").GetProperty("mode").GetString());
        var catalogVersion = full.GetProperty("catalog").GetProperty("toVersion").GetInt32();
        var flagsVersion = full.GetProperty("flags").GetProperty("version").GetInt32();
        var pricesAsOf = full.GetProperty("prices").GetProperty("asOf").GetString()!;

        fixture.Clock.Advance(Window);
        using var second = await fixture.SyncAsync(token, SyncHostFixture.Body(catalogVersion, flagsVersion, pricesAsOf), SyncHostFixture.NewNonce(), app);
        var bytes = await second.Content.ReadAsByteArrayAsync();

        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.True(bytes.Length < 2048, $"{bytes.Length} bytes");
        var body = JsonDocument.Parse(bytes).RootElement;
        Assert.Equal(FullKeys, Keys(body));
        foreach (var block in new[] { "catalog", "flags", "prices", "entitlement", "accountToken", "supportNotice" })
        {
            Assert.Equal(JsonValueKind.Null, body.GetProperty(block).ValueKind);
        }

        Assert.Equal(0, body.GetProperty("accepted").GetProperty("contributions").GetInt32());
        Assert.Equal(0, body.GetProperty("accepted").GetProperty("bankRequests").GetInt32());
    }

    [Fact]
    public async Task AFullAnswerCarriesPricesAsDecimalStringsAndAStaleFlag()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body());
        var prices = (await ReadAsync(response)).GetProperty("prices");

        Assert.Equal("4820.00", prices.GetProperty("gold")[0].GetProperty("price").GetString());
        Assert.Equal("USD", prices.GetProperty("fx").GetProperty("base").GetString());
        Assert.Equal("48.95", prices.GetProperty("fx").GetProperty("rates").GetProperty("EGP").GetString());
        Assert.True(prices.GetProperty("stale").ValueKind is JsonValueKind.True or JsonValueKind.False);
        Assert.EndsWith("Z", prices.GetProperty("asOf").GetString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ACatalogDeltaCarriesTheOpsOfTheNewerVersions()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(catalogVersion: 1));
        var catalog = (await ReadAsync(response)).GetProperty("catalog");

        Assert.Equal("delta", catalog.GetProperty("mode").GetString());
        Assert.Equal(1, catalog.GetProperty("fromVersion").GetInt32());
        Assert.Equal(2, catalog.GetProperty("toVersion").GetInt32());
        Assert.Equal(JsonValueKind.Null, catalog.GetProperty("fullUrl").ValueKind);
        var op = Assert.Single(catalog.GetProperty("ops").EnumerateArray());
        Assert.Equal("category", op.GetProperty("t").GetString());
        Assert.Equal("groceries", op.GetProperty("code").GetString());
    }

    [Fact]
    public async Task AFirstSyncGetsTheFullModeUrl()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body());
        var catalog = (await ReadAsync(response)).GetProperty("catalog");

        Assert.Equal("full", catalog.GetProperty("mode").GetString());
        Assert.Equal(SyncHostFixture.FullUrl2, catalog.GetProperty("fullUrl").GetString());
        Assert.Empty(catalog.GetProperty("ops").EnumerateArray());
        Assert.Equal(0, catalog.GetProperty("fromVersion").GetInt32());
    }

    // ---- AC2: a contribution with a phone number is dropped ----------------------------------------------------------------

    [Fact]
    public async Task ContributionsWithPhoneNumbersOrAddressesAreDroppedAndACleanOneIsAccepted()
    {
        var (_, token) = await fixture.NewInstallAsync();
        string[] dirty = ["010 1234 5678", "٠١٠١٢٣٤٥٦٧٨", "+20 100 123 4567", "user@bank", "pay me 01012345678"];
        var clean = SyncHostFixture.UniqueName("clean");
        var items = dirty.Select(d => (d, "nbe", "dining")).Append((clean, "nbe", "dining")).ToArray();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: SyncHostFixture.Contributions(items)));
        var body = await ReadAsync(response);

        Assert.Equal(1, body.GetProperty("accepted").GetProperty("contributions").GetInt32());
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1", clean));
        foreach (var text in dirty)
        {
            Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1", text));
        }

        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm ~ '[0-9٠-٩]{6}' OR merchant_norm LIKE '%@%'"));
    }

    [Fact]
    public async Task CustomCategoriesAndBadBankRequestsAreDroppedSilently()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var bank = SyncHostFixture.UniqueName("bank");

        using var response = await fixture.SyncAsync(
            token,
            SyncHostFixture.Body(extra:
                SyncHostFixture.Contributions(("t128 custom", "nbe", "my_own_category"))
                + SyncHostFixture.BankRequests((bank, "EG", "sms"), ("call 0101234567", "EG", "sms"), (bank, "XX1", "sms"))));
        var accepted = (await ReadAsync(response)).GetProperty("accepted");

        Assert.Equal(0, accepted.GetProperty("contributions").GetInt32());
        Assert.Equal(1, accepted.GetProperty("bankRequests").GetInt32());
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.bank_requests WHERE institution_name_norm = $1", bank));
    }

    // ---- AC3: the signed throttle ----------------------------------------------------------------------------------------

    [Fact]
    public async Task ASecondCallWithin24HoursIsASignedThrottleWithOnlyThreeMembersAndWritesNothing()
    {
        var appVersion = SyncHostFixture.UniqueAppVersion();
        var (installId, token) = await fixture.NewInstallAsync(appVersion);
        var app = SyncHostFixture.AppHeader(appVersion);
        using var first = await fixture.SyncAsync(token, SyncHostFixture.Body(), app: app);
        var firstTime = DateTimeOffset.Parse((await ReadAsync(first)).GetProperty("serverTime").GetString()!, CultureInfo.InvariantCulture);
        var lastSeen = await fixture.ScalarAsync("SELECT last_seen_at FROM zaghlol.installs WHERE id = $1", Guid.Parse(installId));
        var merchant = SyncHostFixture.UniqueName("throttled");

        fixture.Clock.Advance(Window - TimeSpan.FromMinutes(1));
        var nonce = SyncHostFixture.NewNonce();
        using var throttled = await fixture.SyncAsync(
            token,
            SyncHostFixture.Body(extra: SyncHostFixture.Contributions((merchant, "nbe", "dining"))),
            nonce,
            app);
        var bytes = await throttled.Content.ReadAsByteArrayAsync();

        Assert.Equal(HttpStatusCode.OK, throttled.StatusCode);
        var body = JsonDocument.Parse(bytes).RootElement;
        Assert.Equal(ThrottleKeys, Keys(body));
        Assert.Equal(nonce, body.GetProperty("timeNonce").GetString());
        Assert.Equal(firstTime + Window, DateTimeOffset.Parse(body.GetProperty("nextSyncNotBefore").GetString()!, CultureInfo.InvariantCulture));
        AssertSigned(throttled, bytes);

        // Nothing written: no intake, no daily-active increment, no last_seen_at.
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1", merchant));
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT sum(installs)::bigint FROM zaghlol.daily_active_counts WHERE app_version = $1", appVersion));
        Assert.Equal(lastSeen, await fixture.ScalarAsync("SELECT last_seen_at FROM zaghlol.installs WHERE id = $1", Guid.Parse(installId)));

        fixture.Clock.Advance(TimeSpan.FromMinutes(1));
        using var again = await fixture.SyncAsync(token, SyncHostFixture.Body(), app: app);
        Assert.Equal(FullKeys, Keys(await ReadAsync(again)));
    }

    [Fact]
    public async Task AFullAnswerIsSignedToo()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(), SyncHostFixture.NewNonce());

        AssertSigned(response, await response.Content.ReadAsByteArrayAsync());
    }

    [Fact]
    public async Task TwoSimultaneousSyncsGiveOneFullAnswerAndOneDailyActive()
    {
        var appVersion = SyncHostFixture.UniqueAppVersion();
        var (_, token) = await fixture.NewInstallAsync(appVersion);
        var app = SyncHostFixture.AppHeader(appVersion);

        var responses = await Task.WhenAll(Enumerable.Range(0, 2).Select(_ => fixture.SyncAsync(token, SyncHostFixture.Body(), app: app)));
        var bodies = new List<JsonElement>();
        foreach (var response in responses)
        {
            using (response)
            {
                bodies.Add(await ReadAsync(response));
            }
        }

        Assert.Single(bodies, b => b.TryGetProperty("accepted", out _));
        Assert.Single(bodies, b => Keys(b).SequenceEqual(ThrottleKeys));
        Assert.Equal(1L, await fixture.DailyActiveAsync(appVersion));
    }

    [Fact]
    public async Task ADeletedInstallIs401()
    {
        var (_, token) = await fixture.NewInstallAsync();
        using (var delete = new HttpRequestMessage(HttpMethod.Delete, "/v1/installs/me"))
        {
            delete.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
            using var deleted = await fixture.Client.SendAsync(delete);
            Assert.Equal(HttpStatusCode.Accepted, deleted.StatusCode);
        }

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body());

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal("INSTALL_TOKEN_INVALID", await CodeAsync(response));
    }

    // ---- AC4: R4-2 nonce echo ----------------------------------------------------------------------------------------------

    [Fact]
    public async Task TheNonceIsEchoedExactlyAndAnAbsentOneIsAnExplicitNull()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var nonce = SyncHostFixture.NewNonce();

        using var full = await fixture.SyncAsync(token, SyncHostFixture.Body(), nonce);
        using var throttledWithout = await fixture.SyncAsync(token, SyncHostFixture.Body());

        Assert.Equal(nonce, (await ReadAsync(full)).GetProperty("timeNonce").GetString());
        var throttle = await ReadAsync(throttledWithout);
        Assert.True(throttle.TryGetProperty("timeNonce", out var echo));
        Assert.Equal(JsonValueKind.Null, echo.ValueKind);
    }

    [Fact]
    public async Task AMalformedNonceIs400AndAnotherInstallsNonceIsNeverEchoed()
    {
        var (_, tokenA) = await fixture.NewInstallAsync();
        var (_, tokenB) = await fixture.NewInstallAsync();
        var nonceA = SyncHostFixture.NewNonce();
        var nonceB = SyncHostFixture.NewNonce();

        using var malformed = await fixture.SyncAsync(tokenA, SyncHostFixture.Body(), "not-a-nonce");
        using var a = await fixture.SyncAsync(tokenA, SyncHostFixture.Body(), nonceA);
        using var b = await fixture.SyncAsync(tokenB, SyncHostFixture.Body(), nonceB);
        using var aThrottled = await fixture.SyncAsync(tokenA, SyncHostFixture.Body(), nonceA);

        Assert.Equal(HttpStatusCode.BadRequest, malformed.StatusCode);
        var textA = await a.Content.ReadAsStringAsync();
        var textThrottled = await aThrottled.Content.ReadAsStringAsync();
        Assert.Contains(nonceA, textA, StringComparison.Ordinal);
        Assert.DoesNotContain(nonceB, textA, StringComparison.Ordinal);
        Assert.Contains(nonceA, textThrottled, StringComparison.Ordinal);
        Assert.DoesNotContain(nonceB, textThrottled, StringComparison.Ordinal);
        Assert.Equal(nonceB, (await ReadAsync(b)).GetProperty("timeNonce").GetString());
    }

    // ---- Request validation ------------------------------------------------------------------------------------------------

    [Theory]
    [InlineData("{\"catalogVersion\":0,\"flagsVersion\":0,\"messages\":[]}", "UNKNOWN_FIELD")]
    [InlineData("{\"catalogVersion\":0,\"flagsVersion\":0,\"contributions\":[{\"merchantNorm\":\"ab\",\"institutionCode\":\"nbe\",\"categoryCode\":\"dining\",\"amount\":\"10\"}]}", "UNKNOWN_FIELD")]
    [InlineData("{\"catalogVersion\":0,\"flagsVersion\":0,\"bankRequests\":[{\"institutionName\":\"ab\",\"country\":\"EG\",\"channel\":\"sms\",\"sms\":\"x\"}]}", "UNKNOWN_FIELD")]
    [InlineData("{\"catalogVersion\":0}", "VALIDATION_FAILED")]
    [InlineData("{\"catalogVersion\":-1,\"flagsVersion\":0}", "VALIDATION_FAILED")]
    [InlineData("{\"catalogVersion\":\"1\",\"flagsVersion\":0}", "VALIDATION_FAILED")]
    [InlineData("{\"catalogVersion\":0,\"flagsVersion\":0,\"pricesAsOf\":\"2026-11-03T18:22:01+02:00\"}", "VALIDATION_FAILED")]
    public async Task MalformedBodiesAre400EvenWhenTheCallWouldBeThrottled(string body, string code)
    {
        var (_, token) = await fixture.NewInstallAsync();
        using var first = await fixture.SyncAsync(token, SyncHostFixture.Body());
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        using var response = await fixture.SyncAsync(token, body);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(code, await CodeAsync(response));
    }

    [Fact]
    public async Task OverTheCapsIsTheWholeCall400()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var contributions = SyncHostFixture.Contributions([.. Enumerable.Range(0, 51).Select(i => ("m" + i, "nbe", "dining"))]);
        var banks = SyncHostFixture.BankRequests([.. Enumerable.Range(0, 11).Select(i => ("bank " + (char)('a' + i), "EG", "sms"))]);

        using var tooManyContributions = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: contributions));
        using var tooManyBanks = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: banks));
        using var ok = await fixture.SyncAsync(token, SyncHostFixture.Body());

        Assert.Equal(HttpStatusCode.BadRequest, tooManyContributions.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, tooManyBanks.StatusCode);
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode); // the rejected calls claimed nothing
        Assert.Contains("accepted", await ok.Content.ReadAsStringAsync(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("android/1.0.0")]
    [InlineData("android/1.0 (42)")]
    [InlineData("windows/1.0.0 (42)")]
    public async Task AMissingOrMalformedAppHeaderIs400(string? app)
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(), app: app);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("VALIDATION_FAILED", await CodeAsync(response));
    }

    [Theory]
    [InlineData("android/1.0.0 (42)", "1.0.0")]
    [InlineData("ios/12.4.1-beta.2 (9000)", "12.4.1-beta.2")]
    [InlineData("android/1.0.0+build.7 (x)", "1.0.0+build.7")]
    [InlineData("android/1.0.0 (42)\n", null)]
    [InlineData("android/\u0661.0.0 (42)", null)]
    [InlineData("android/1.0.0  (42)", null)]
    [InlineData("android/1.0.0.0 (42)", null)]
    [InlineData("android/1.0.0 ()", null)]
    [InlineData("", null)]
    public void TheAppHeaderYieldsTheVersionOnlyInItsExactForm(string header, string? version)
    {
        Assert.Equal(version is not null, Endpoints.V1.SyncEndpoints.TryReadAppVersion(new Microsoft.Extensions.Primitives.StringValues(header), out var read));
        Assert.Equal(version ?? string.Empty, read);
        Assert.False(Endpoints.V1.SyncEndpoints.TryReadAppVersion(new Microsoft.Extensions.Primitives.StringValues(["android/1.0.0 (1)", "android/1.0.0 (2)"]), out _));
    }

    [Fact]
    public async Task TheHeaderPlatformIsIgnoredAndTheRowsIsUsed()
    {
        var appVersion = SyncHostFixture.UniqueAppVersion();
        var (_, token) = await fixture.NewInstallAsync(appVersion, "ios");

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(), app: SyncHostFixture.AppHeader(appVersion, "android"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(
            1L,
            await fixture.ScalarAsync(
                "SELECT installs::bigint FROM zaghlol.daily_active_counts WHERE platform = 'ios' AND app_version = $1",
                appVersion));
    }

    // ---- Failure modes -----------------------------------------------------------------------------------------------------

    [Fact]
    public async Task ACatalogFailureIs503WithoutConsumingTheWindow()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        fixture.Faults.Catalog = true;
        try
        {
            using var failed = await fixture.SyncAsync(token, SyncHostFixture.Body());
            Assert.Equal(HttpStatusCode.ServiceUnavailable, failed.StatusCode);
            Assert.Equal("30", failed.Headers.RetryAfter?.ToString());
            Assert.Equal("UPSTREAM_UNAVAILABLE", await CodeAsync(failed));
            Assert.Null(await fixture.ScalarAsync("SELECT last_sync_at FROM zaghlol.installs WHERE id = $1", Guid.Parse(installId)));
        }
        finally
        {
            fixture.Faults.Catalog = false;
        }

        using var retry = await fixture.SyncAsync(token, SyncHostFixture.Body());
        Assert.Equal(FullKeys, Keys(await ReadAsync(retry)));
    }

    [Fact]
    public async Task APriceFailureDegradesToNullPrices()
    {
        var (_, token) = await fixture.NewInstallAsync();
        fixture.Faults.Prices = true;
        try
        {
            using var response = await fixture.SyncAsync(token, SyncHostFixture.Body());
            var body = await ReadAsync(response);

            Assert.Equal(JsonValueKind.Null, body.GetProperty("prices").ValueKind);
            Assert.Equal(JsonValueKind.Object, body.GetProperty("catalog").ValueKind);
        }
        finally
        {
            fixture.Faults.Prices = false;
        }
    }

    [Fact]
    public async Task AnEntitlementBlockFailureIs503()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        fixture.Faults.Entitlement.Fail = true;
        try
        {
            using var response = await fixture.SyncAsync(token, SyncHostFixture.Body());

            Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
            Assert.Null(await fixture.ScalarAsync("SELECT last_sync_at FROM zaghlol.installs WHERE id = $1", Guid.Parse(installId)));
        }
        finally
        {
            fixture.Faults.Entitlement.Fail = false;
        }
    }

    [Fact]
    public async Task AHasherOutageDropsTheIntakeButTheSyncSucceeds()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var merchant = SyncHostFixture.UniqueName("nohash");
        fixture.Faults.Hasher = true;
        try
        {
            using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: SyncHostFixture.Contributions((merchant, "nbe", "dining"))));
            var body = await ReadAsync(response);

            Assert.Equal(0, body.GetProperty("accepted").GetProperty("contributions").GetInt32());
            Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1", merchant));
        }
        finally
        {
            fixture.Faults.Hasher = false;
        }
    }

    // ---- Extension point, dedupe, daily-active ------------------------------------------------------------------------------

    [Fact]
    public async Task TheEntitlementBlockReceivesEntitlementIssuedAtAndItsBlocksAreSent()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        fixture.Faults.Entitlement.Result = new SyncEntitlementResult("eyJh.eyJz.c2ln", "eyJh.eyJh.c2ln", "gold_linked_by_support");
        try
        {
            using var response = await fixture.SyncAsync(
                token,
                SyncHostFixture.Body(extra: ",\"entitlementIssuedAt\":\"2026-10-30T10:00:00Z\""));
            var body = await ReadAsync(response);

            Assert.Equal("eyJh.eyJz.c2ln", body.GetProperty("entitlement").GetProperty("token").GetString());
            Assert.Equal("eyJh.eyJh.c2ln", body.GetProperty("accountToken").GetString());
            Assert.Equal("gold_linked_by_support", body.GetProperty("supportNotice").GetString());
            var context = fixture.Faults.Entitlement.LastContext!;
            Assert.Equal(installId, context.InstallId.ToString());
            Assert.Equal(new DateTimeOffset(2026, 10, 30, 10, 0, 0, TimeSpan.Zero), context.EntitlementIssuedAt);
        }
        finally
        {
            fixture.Faults.Entitlement.Result = SyncEntitlementResult.None;
        }
    }

    [Fact]
    public async Task TheSameContributionTwiceInOneCallAndAcrossDaysIsOneRow()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var merchant = SyncHostFixture.UniqueName("dedupe");
        var items = SyncHostFixture.Contributions((merchant, "nbe", "dining"), (merchant.ToUpperInvariant(), "nbe", "groceries"));

        using var first = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: items));
        fixture.Clock.Advance(Window);
        using var second = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: items));

        Assert.Equal(1, (await ReadAsync(first)).GetProperty("accepted").GetProperty("contributions").GetInt32());
        Assert.Equal(0, (await ReadAsync(second)).GetProperty("accepted").GetProperty("contributions").GetInt32());
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1", merchant));
    }

    [Fact]
    public async Task DailyActiveCountsAddOnePerInstallPerDayAndVersion()
    {
        var appVersion = SyncHostFixture.UniqueAppVersion();
        var app = SyncHostFixture.AppHeader(appVersion);
        var (_, tokenA) = await fixture.NewInstallAsync(appVersion);
        var (_, tokenB) = await fixture.NewInstallAsync(appVersion);

        using var a = await fixture.SyncAsync(tokenA, SyncHostFixture.Body(), app: app);
        using var b = await fixture.SyncAsync(tokenB, SyncHostFixture.Body(), app: app);
        using var aAgain = await fixture.SyncAsync(tokenA, SyncHostFixture.Body(), app: app);

        Assert.Equal(2L, await fixture.DailyActiveAsync(appVersion));
    }

    [Fact]
    public async Task AnAppUpdateSendsFlagsAndIsStored()
    {
        var oldVersion = SyncHostFixture.UniqueAppVersion();
        var (installId, token) = await fixture.NewInstallAsync(oldVersion);
        using var first = await fixture.SyncAsync(token, SyncHostFixture.Body(), app: SyncHostFixture.AppHeader(oldVersion));
        var flagsVersion = (await ReadAsync(first)).GetProperty("flags").GetProperty("version").GetInt32();

        fixture.Clock.Advance(Window);
        using var updated = await fixture.SyncAsync(token, SyncHostFixture.Body(flagsVersion: flagsVersion), app: "android/9.9.9 (100)");

        Assert.Equal(JsonValueKind.Object, (await ReadAsync(updated)).GetProperty("flags").ValueKind);
        Assert.Equal("9.9.9", await fixture.ScalarAsync("SELECT app_version FROM zaghlol.installs WHERE id = $1", Guid.Parse(installId)));
    }

    // ---- Privacy and wiring --------------------------------------------------------------------------------------------------

    [Fact]
    public async Task LogsNeverContainContributionTextTheNonceOrEntitlementIssuedAt()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var merchant = SyncHostFixture.UniqueName("logcheck");
        var nonce = SyncHostFixture.NewNonce();
        fixture.Faults.Prices = true; // also exercises the SYNC_BLOCK_FAILED log line
        try
        {
            using var response = await fixture.SyncAsync(
                token,
                SyncHostFixture.Body(extra:
                    SyncHostFixture.Contributions(("01012345678", "nbe", "dining"), (merchant, "nbe", "dining"))
                    + SyncHostFixture.BankRequests(("t128 bank logcheck", "EG", "sms"))
                    + ",\"entitlementIssuedAt\":\"2026-10-29T07:06:05Z\""),
                nonce);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
        finally
        {
            fixture.Faults.Prices = false;
        }

        var logs = string.Join('\n', fixture.LogSink.Entries);
        Assert.Contains("SYNC_BLOCK_FAILED", logs, StringComparison.Ordinal);
        foreach (var secret in new[] { "01012345678", merchant, "t128 bank logcheck", nonce, "2026-10-29", token })
        {
            Assert.DoesNotContain(secret, logs, StringComparison.Ordinal);
        }
    }

    [Fact]
    public async Task TheResponseNeverEchoesRequestData()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var merchant = SyncHostFixture.UniqueName("echo");

        using var response = await fixture.SyncAsync(
            token,
            SyncHostFixture.Body(extra: SyncHostFixture.Contributions((merchant, "nbe", "dining")) + ",\"registryVersion\":987654"));
        var text = await response.Content.ReadAsStringAsync();

        Assert.DoesNotContain(merchant, text, StringComparison.Ordinal);
        Assert.DoesNotContain("987654", text, StringComparison.Ordinal);
    }

    [Fact]
    public void TheEndpointRequiresTheInstallTokenAndASignature()
    {
        var endpoint = fixture.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .Single(e => e.Metadata.GetMetadata<IEndpointNameMetadata>()?.EndpointName == "sync");

        Assert.NotNull(endpoint.Metadata.GetMetadata<InstallTokenRequiredMetadata>());
        Assert.NotNull(endpoint.Metadata.GetMetadata<RequireResponseSignatureMetadata>());
    }

    [Fact]
    public async Task ThereIsNoIdempotencyReplayTheThrottleIsTheMechanism()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        var key = new Dictionary<string, string> { ["Idempotency-Key"] = Installs.InstallsHostFixture.NewKey() };

        using var first = await fixture.SyncAsync(token, SyncHostFixture.Body(), SyncHostFixture.NewNonce(), headers: key);
        using var second = await fixture.SyncAsync(token, SyncHostFixture.Body(), SyncHostFixture.NewNonce(), headers: key);

        Assert.Equal(FullKeys, Keys(await ReadAsync(first)));
        Assert.Equal(ThrottleKeys, Keys(await ReadAsync(second))); // a replay would have returned the stored full body
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.idempotency_records WHERE install_id = $1", Guid.Parse(installId)));
    }

    private static async Task<JsonElement> ReadAsync(HttpResponseMessage response)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, $"{(int)response.StatusCode}: {text}");
        return JsonDocument.Parse(text).RootElement.Clone();
    }

    private static async Task<string?> CodeAsync(HttpResponseMessage response)
    {
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return json.RootElement.GetProperty("code").GetString();
    }

    private static string[] Keys(JsonElement body) => [.. body.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)];

    private void AssertSigned(HttpResponseMessage response, byte[] body)
    {
        var header = string.Join(",", response.Headers.GetValues(ResponseSigningMiddleware.HeaderName));
        var parts = header.Split("; ");
        Assert.Equal(3, parts.Length);
        var kid = parts[0]["kid=".Length..];
        var key = fixture.SyncKeys.Single(k => k.Kid == kid);
        Assert.Equal(SigningPurpose.Sync, key.Purpose);
        Assert.True(SignatureCheck.Verifies(key.PublicJwk, body, Base64Url.DecodeFromChars(parts[2].AsSpan("sig=".Length))));
    }
}
