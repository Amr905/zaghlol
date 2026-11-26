using System.Net;
using System.Text;
using System.Text.Json;
using Zaghlol.Application.Llm;

namespace Zaghlol.Api.Tests.Llm;

/// <summary>
/// T-349: <c>POST /v1/ask/plan</c> through the real pipeline over PostgreSQL, with the recorded fake provider. Each test makes its own install, so
/// the per-install counters never leak between tests; the clock, flags, replies and the forced limiter are reset before each.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class AskPlanEndpointTests(AskHostFixture fixture) : IClassFixture<AskHostFixture>, IAsyncLifetime
{
    private const string Breakdown = """{"v":1,"plan":"PL-BREAKDOWN","p":{"period":{"k":"cycle","o":0,"n":null,"m":null,"y":null},"by":"category","limit":5},"t":null}""";
    private const string Fallback = """{"v":1,"plan":"PL-FALLBACK","p":{"reason":"ambiguous"},"t":null}""";
    private const string Refuse = """{"v":1,"plan":"PL-REFUSE","p":{"reason":"offTopic","selfHarm":false},"t":null}""";
    private const string Invest = """{"v":1,"plan":"PL-INVEST","p":{"source":{"kind":"savedLastPeriod","whatIf":null,"amount":null},"instruments":["gold"],"horizonMonths":12},"t":null}""";

    public async Task InitializeAsync()
    {
        fixture.Reset();
        await fixture.SetFlagAsync("ask_llm", true);
        await fixture.SetFlagAsync("ask_llm_invest", true);
        await fixture.SetConfigAsync("ask.quota_free", "5");
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private static string Unique(string prefix) => prefix + string.Concat(Guid.NewGuid().ToByteArray().Select(b => (char)('a' + (b % 26))));

    private static JsonElement Json(string text) => JsonDocument.Parse(text).RootElement.Clone();

    private async Task<(string InstallId, string Token)> InstallAsync() => await fixture.NewInstallAsync();

    private static void AssertProblem(HttpResponseMessage response, string text, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = Json(text);
        Assert.Equal(code, body.GetProperty("code").GetString());
        Assert.Equal((int)status, body.GetProperty("status").GetInt32());
    }

    private async Task<(HttpResponseMessage Response, string Text)> AskAsync(string installId, string token, string question, string? requestId = null, string? account = null) =>
        await fixture.AskAsync(token, installId, question, requestId, account);

    // AC 1: the happy row of the table.
    [Fact]
    public async Task AValidQuestionIsAnsweredWithThePlanCountedAndTheQuotaSnapshot()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("spend");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));

        var (response, text) = await AskAsync(id, token, q);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("no-store", response.Headers.CacheControl?.ToString());
        var body = Json(text);
        Assert.Equal("PL-BREAKDOWN", body.GetProperty("plan").GetProperty("plan").GetString());
        Assert.Equal(JsonValueKind.Null, body.GetProperty("plan").GetProperty("t").ValueKind);
        Assert.True(body.GetProperty("counted").GetBoolean());
        var quota = body.GetProperty("quota");
        Assert.Equal(5, quota.GetProperty("limit").GetInt32());
        Assert.Equal(1, quota.GetProperty("used").GetInt32());
        Assert.Equal(4, quota.GetProperty("remaining").GetInt32());
        Assert.EndsWith("Z", quota.GetProperty("resetsAt").GetString(), StringComparison.Ordinal);
        Assert.EndsWith("Z", body.GetProperty("serverTime").GetString(), StringComparison.Ordinal);
        Assert.Equal(1, await fixture.UsedAsync("install", id));
    }

    // AC 1 + negative proof 2 (AC 4): every refusing row of the table, and the provider never reached.
    [Fact]
    public async Task EveryRefusingRowOfTheErrorTableHasItsStatusCodeAndMembersAndNeverReachesTheProvider()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("refuse");
        var calls = fixture.Provider.Calls;

        // 401: no token (the pipeline, before the endpoint).
        using (var noToken = await fixture.Client.PostAsync("/v1/ask/plan", new StringContent(AskHostFixture.Body(id, q), Encoding.UTF8, "application/json")))
        {
            AssertProblem(noToken, await noToken.Content.ReadAsStringAsync(), HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");
        }

        // 400: an unknown member (no financial data is accepted) and a bad value; 415; 413.
        using (var unknown = await fixture.PostAsync(token, AskHostFixture.Body(id, q, extra: ",\"amount\":500")))
        {
            AssertProblem(unknown, await unknown.Content.ReadAsStringAsync(), HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
        }

        using (var badLang = await fixture.PostAsync(token, AskHostFixture.Body(id, q, lang: "fr")))
        {
            AssertProblem(badLang, await badLang.Content.ReadAsStringAsync(), HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        }

        using (var wrongType = await fixture.PostAsync(token, AskHostFixture.Body(id, q), mediaType: "text/plain"))
        {
            AssertProblem(wrongType, await wrongType.Content.ReadAsStringAsync(), HttpStatusCode.UnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE");
        }

        using (var large = await fixture.PostAsync(token, AskHostFixture.Body(id, q) + new string(' ', 5000)))
        {
            AssertProblem(large, await large.Content.ReadAsStringAsync(), HttpStatusCode.RequestEntityTooLarge, "PAYLOAD_TOO_LARGE");
        }

        // 16 KB is allowed only with an attestationObject: 6 KB of it passes the size gate and then fails as a wrong-type proof (422, not 413).
        var appAttest = AskHostFixture.Body(id, q, attest: false)[..^1]
            + $",\"attestation\":{{\"type\":\"app_attest\",\"keyId\":\"{new string('A', 43)}=\",\"assertion\":\"{new string('A', 32)}\",\"attestationObject\":\"{new string('A', 6000)}\"}}}}";
        using (var withObject = await fixture.PostAsync(token, appAttest))
        {
            AssertProblem(withObject, await withObject.Content.ReadAsStringAsync(), HttpStatusCode.UnprocessableEntity, "DEVICE_ATTESTATION_FAILED");
        }

        // 422: no attestation member at all (reaches the verifier as null: 422, not 400), and a proof bound to another body.
        using (var missing = await fixture.PostAsync(token, AskHostFixture.Body(id, q, attest: false)))
        {
            AssertProblem(missing, await missing.Content.ReadAsStringAsync(), HttpStatusCode.UnprocessableEntity, "DEVICE_ATTESTATION_FAILED");
        }

        var other = AskHostFixture.Body(id, "another " + q);
        var swapped = AskHostFixture.Body(id, q, attest: false)[..^1] + other[other.IndexOf(",\"attestation\"", StringComparison.Ordinal)..];
        using (var replayed = await fixture.PostAsync(token, swapped))
        {
            AssertProblem(replayed, await replayed.Content.ReadAsStringAsync(), HttpStatusCode.UnprocessableEntity, "DEVICE_ATTESTATION_FAILED");
        }

        // 409: another provider or consent version, with the active provider id.
        foreach (var body in new[] { AskHostFixture.Body(id, q, provider: "other-provider"), AskHostFixture.Body(id, q, consentVersion: 2) })
        {
            using var consent = await fixture.PostAsync(token, body);
            var text = await consent.Content.ReadAsStringAsync();
            AssertProblem(consent, text, HttpStatusCode.Conflict, "LLM_CONSENT_REQUIRED");
            Assert.Equal(AskHostFixture.ProviderId, Json(text).GetProperty("providerId").GetString());
            Assert.Equal("https://zaghlol.app/problems/llm-consent-required", Json(text).GetProperty("type").GetString());
        }

        // 429: a bucket refusal, with Retry-After and retryAfterSeconds.
        fixture.Limiter.Force = new Zaghlol.Application.Llm.Ask.LlmRateDecision(false, "install", 20);
        using (var limited = await fixture.PostAsync(token, AskHostFixture.Body(id, q)))
        {
            var text = await limited.Content.ReadAsStringAsync();
            AssertProblem(limited, text, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
            Assert.Equal(20, Json(text).GetProperty("retryAfterSeconds").GetInt32());
            Assert.Equal("20", limited.Headers.RetryAfter?.Delta?.TotalSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }

        fixture.Limiter.Force = null;

        // 503: the flag is off for this install.
        await fixture.SetFlagAsync("ask_llm", false);
        using (var paused = await fixture.PostAsync(token, AskHostFixture.Body(id, q)))
        {
            var text = await paused.Content.ReadAsStringAsync();
            AssertProblem(paused, text, HttpStatusCode.ServiceUnavailable, "LLM_SERVICE_PAUSED");
            Assert.Equal("https://zaghlol.app/problems/llm-service-paused", Json(text).GetProperty("type").GetString());
        }

        Assert.Equal(calls, fixture.Provider.Calls);
        Assert.Equal(0, await fixture.UsedAsync("install", id));
    }

    [Fact]
    public async Task ATimeoutOrAFailingProviderIs502AndNotCounted()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("slow");
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(q, LlmOutcome.Timeout, null, null));

        var (response, text) = await AskAsync(id, token, q);

        AssertProblem(response, text, HttpStatusCode.BadGateway, "UPSTREAM_UNAVAILABLE");
        Assert.True(Json(text).TryGetProperty("retryAfterSeconds", out _));
        Assert.Equal(0, await fixture.UsedAsync("install", id));
    }

    // AC 1: counted or not per outcome, one install, cumulative counter.
    [Fact]
    public async Task OnlyAValidPlanIncludingFallbackAndRefuseIsCounted()
    {
        var (id, token) = await InstallAsync();
        var expected = 0;

        async Task<JsonElement> Step(string reply, bool counted, string plan, LlmOutcome outcome = LlmOutcome.Ok, string? text = null)
        {
            var q = Unique("step");
            fixture.Replies.Add(AskHostFixture.Reply(q, reply, outcome));
            var (response, body) = await AskAsync(id, token, q);
            Assert.True(response.StatusCode == HttpStatusCode.OK, plan + ": " + (int)response.StatusCode);
            var json = Json(body);
            Assert.Equal(plan, json.GetProperty("plan").GetProperty("plan").GetString());
            Assert.Equal(counted, json.GetProperty("counted").GetBoolean());
            expected += counted ? 1 : 0;
            Assert.Equal(expected, await fixture.UsedAsync("install", id));
            Assert.Equal(5 - expected, json.GetProperty("quota").GetProperty("remaining").GetInt32());
            return json;
        }

        await Step(Breakdown, true, "PL-BREAKDOWN");
        await Step(Fallback, true, "PL-FALLBACK");
        await Step(Refuse, true, "PL-REFUSE");

        // A validator failure: a ref the question never held.
        var badRef = """{"v":1,"plan":"PL-BALANCE","p":{"ref":"⟦CARD_7⟧"},"t":null}""";
        await Step(badRef, false, "PL-FALLBACK");

        // PL-INVEST while ask_llm_invest is off, then on.
        await fixture.SetFlagAsync("ask_llm_invest", false);
        await Step(Invest, false, "PL-FALLBACK");
        await fixture.SetFlagAsync("ask_llm_invest", true);
        await Step(Invest, true, "PL-INVEST");
    }

    // AC 1: a duplicate requestId in parallel is counted once.
    [Fact]
    public async Task TheSameRequestIdInParallelCountsOnce()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("twin");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));
        var requestId = AskHostFixture.NewRequestId();

        var both = await Task.WhenAll(AskAsync(id, token, q, requestId), AskAsync(id, token, q, requestId));

        Assert.All(both, r => Assert.Equal(HttpStatusCode.OK, r.Response.StatusCode));
        Assert.Equal(1, await fixture.UsedAsync("install", id));
    }

    // AC 1: the sixth Free question is refused (with the quota) and a retry of the fifth stays free.
    [Fact]
    public async Task TheSixthFreeQuestionIsRefusedAndARetryOfTheFifthIsNotCountedTwice()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("five");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));
        string fifth = string.Empty;
        for (var i = 0; i < 5; i++)
        {
            fifth = AskHostFixture.NewRequestId();
            var (response, _) = await AskAsync(id, token, q, fifth);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }

        var (retry, retryText) = await AskAsync(id, token, q, fifth);
        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
        Assert.Equal(0, Json(retryText).GetProperty("quota").GetProperty("remaining").GetInt32());
        Assert.Equal(5, await fixture.UsedAsync("install", id));

        var calls = fixture.Provider.Calls;
        var (sixth, text) = await AskAsync(id, token, q);
        AssertProblem(sixth, text, HttpStatusCode.Forbidden, "LLM_QUOTA_EXHAUSTED");
        var quota = Json(text).GetProperty("quota");
        Assert.Equal(5, quota.GetProperty("limit").GetInt32());
        Assert.Equal(5, quota.GetProperty("used").GetInt32());
        Assert.Equal(0, quota.GetProperty("remaining").GetInt32());
        Assert.Equal("https://zaghlol.app/problems/llm-quota-exhausted", Json(text).GetProperty("type").GetString());
        Assert.Equal(calls, fixture.Provider.Calls);
    }

    // AC 1: the month is the Cairo calendar month: refused at 30 Nov 23:50 Cairo, allowed at 1 Dec 00:05 Cairo.
    [Fact]
    public async Task TheMonthResetsAtMidnightInCairoNotUtc()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("cairo");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));

        fixture.SetClock(new DateTimeOffset(2026, 11, 30, 21, 50, 0, TimeSpan.Zero)); // 23:50 in Cairo (UTC+2)
        for (var i = 0; i < 5; i++)
        {
            var (response, _) = await AskAsync(id, token, q);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }

        var (sixth, text) = await AskAsync(id, token, q);
        AssertProblem(sixth, text, HttpStatusCode.Forbidden, "LLM_QUOTA_EXHAUSTED");
        Assert.Equal("2026-11-30T22:00:00Z", Json(text).GetProperty("quota").GetProperty("resetsAt").GetString());

        fixture.SetClock(new DateTimeOffset(2026, 11, 30, 22, 5, 0, TimeSpan.Zero)); // 00:05 on 1 December in Cairo
        var (next, nextText) = await AskAsync(id, token, q);
        Assert.Equal(HttpStatusCode.OK, next.StatusCode);
        var quota = Json(nextText).GetProperty("quota");
        Assert.Equal(1, quota.GetProperty("used").GetInt32());
        Assert.Equal("2026-12-31T22:00:00Z", quota.GetProperty("resetsAt").GetString());
    }

    // AC 1: the account counter spans installs (FR-LLM-11); only a validated token counts.
    [Fact]
    public async Task TheAccountCounterIsSharedAcrossTwoInstalls()
    {
        await fixture.SetConfigAsync("ask.quota_free", "2");
        var account = Guid.NewGuid();
        var header = "acct:" + account;
        var (idA, tokenA) = await InstallAsync();
        var (idB, tokenB) = await InstallAsync();
        var q = Unique("acct");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));

        Assert.Equal(HttpStatusCode.OK, (await AskAsync(idA, tokenA, q, account: header)).Response.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await AskAsync(idB, tokenB, q, account: header)).Response.StatusCode);
        Assert.Equal(2, await fixture.UsedAsync("account", account.ToString()));

        // Install A is at 1 of 2 itself, but the account is at its limit.
        var (third, text) = await AskAsync(idA, tokenA, q, account: header);
        AssertProblem(third, text, HttpStatusCode.Forbidden, "LLM_QUOTA_EXHAUSTED");
        Assert.Equal(1, await fixture.UsedAsync("install", idA));

        // Without a valid account token the install counter alone decides (a forged token is no account, never an error).
        var (withoutAccount, _) = await AskAsync(idA, tokenA, q);
        Assert.Equal(HttpStatusCode.OK, withoutAccount.StatusCode);
        var (forged, _) = await AskAsync(idB, tokenB, q, account: "forged");
        Assert.Equal(HttpStatusCode.OK, forged.StatusCode);
        Assert.Equal(2, await fixture.UsedAsync("account", account.ToString()));
    }

    // AC 2: the flag turned off while the app's cache says on.
    [Fact]
    public async Task AFlagTurnedOffIsSeenOnTheNextRequest()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("flag");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));
        Assert.Equal(HttpStatusCode.OK, (await AskAsync(id, token, q)).Response.StatusCode);
        var calls = fixture.Provider.Calls;

        await fixture.SetFlagAsync("ask_llm", false);
        var (response, text) = await AskAsync(id, token, q);

        AssertProblem(response, text, HttpStatusCode.ServiceUnavailable, "LLM_SERVICE_PAUSED");
        Assert.Equal(calls, fixture.Provider.Calls);
    }

    // AC 2: the spend cap reached pauses the same way, and a cap that is no longer reached resumes.
    [Fact]
    public async Task TheSpendCapReachedAnswersPausedAndNeverReachesTheProvider()
    {
        var (id, token) = await InstallAsync();
        var q = Unique("cap");
        fixture.Replies.Add(AskHostFixture.Reply(q, Breakdown));
        fixture.SetClock(new DateTimeOffset(2026, 10, 15, 12, 0, 0, TimeSpan.Zero));
        await ZaghlolTestDatabase_ExecuteAsync("INSERT INTO zaghlol.llm_spend_daily (day, feature, provider_id, model, calls, input_tokens, cached_tokens, output_tokens, cost_usd) VALUES ('2026-10-15', 'ask', 'fake-a', 'model-x', 1, 0, 0, 0, 10.00)");
        fixture.Clock.Advance(TimeSpan.FromMinutes(2)); // past the 60 s cache of the month total
        var calls = fixture.Provider.Calls;

        var (response, text) = await AskAsync(id, token, q);

        AssertProblem(response, text, HttpStatusCode.ServiceUnavailable, "LLM_SERVICE_PAUSED");
        Assert.Equal(calls, fixture.Provider.Calls);

        await ZaghlolTestDatabase_ExecuteAsync("DELETE FROM zaghlol.llm_spend_daily WHERE day = '2026-10-15'");
        fixture.Clock.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(HttpStatusCode.OK, (await AskAsync(id, token, q)).Response.StatusCode);
    }

    // AC 5: what the provider is given, after the server-side scrub.
    [Fact]
    public async Task TheProviderRequestCarriesOnlyThePromptTheScrubbedTextAndTheLanguage()
    {
        var (id, token) = await InstallAsync();
        var marker = Unique("scrubbed");
        fixture.Replies.Add(AskHostFixture.Reply(marker, Breakdown));

        var (response, _) = await AskAsync(id, token, $"{marker} call me 01001234567 or ahmed@example.com about ⟦CARD_1⟧");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var call = fixture.Provider.Last!;
        Assert.Equal($"{marker} call me ⟦PHONE⟧ or ⟦EMAIL⟧ about ⟦CARD_1⟧", call.UserText.Reveal());
        Assert.Equal("ask-plan-v1", call.PromptId);
        Assert.Equal("en", call.Lang);
        Assert.Equal(LlmFeature.Ask, call.Feature);
        Assert.Equal(300, call.MaxOutputTokens);
    }

    // Negative proof 1 (AC 3): a marker question and a marker template through success, fallback, validation failure, timeout, exception and an unusable reply.
    [Fact]
    public async Task AMarkerQuestionAndTemplateNeverReachALogAMetricATraceOrATable()
    {
        const string QuestionMarker = "MarkerQuestionQwx";
        const string TemplateMarker = "MarkerTemplateQwx";
        using var telemetry = new TelemetryCapture();
        var (id, token) = await InstallAsync();
        var whatIf = """{"v":1,"plan":"PL-WHATIF-CUT","p":{"target":{"slug":"dining","ref":null,"mention":null,"currency":null},"mode":{"kind":"percent","percent":50,"amount":null,"currency":null},"months":12},"t":{"lang":"en","text":"MarkerTemplateQwx {target} {pct}"}}""";
        var badMention = """{"v":1,"plan":"PL-SPEND","p":{"period":{"k":"cycle","o":0,"n":null,"m":null,"y":null},"filter":{"slug":null,"ref":null,"mention":"MarkerTemplateQwx","currency":null}},"t":null}""";
        fixture.Replies.Add(AskHostFixture.Reply(QuestionMarker + " success", whatIf));
        fixture.Replies.Add(AskHostFixture.Reply(QuestionMarker + " fallback", Fallback));
        fixture.Replies.Add(AskHostFixture.Reply(QuestionMarker + " invalid-plan", badMention));
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(QuestionMarker + " timeout", LlmOutcome.Timeout, null, null));
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(QuestionMarker + " unusable", LlmOutcome.Invalid, null, null));
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(QuestionMarker + " refused", LlmOutcome.Refused, null, null));
        fixture.Provider.ThrowWhenQuestionContains = QuestionMarker + " exception";

        var bodies = new List<(string Path, HttpStatusCode Status, string Text)>();
        foreach (var path in new[] { "success", "fallback", "invalid-plan", "timeout", "unusable", "refused", "exception" })
        {
            var (response, text) = await AskAsync(id, token, $"{QuestionMarker} {path} what if I cut dining 50% for 12 months");
            bodies.Add((path, response.StatusCode, text));
        }

        Assert.Equal(HttpStatusCode.OK, bodies[0].Status);
        Assert.Contains(TemplateMarker, bodies[0].Text, StringComparison.Ordinal); // the success body is the one place the template legitimately appears
        Assert.Equal(1, fixture.Provider.Throws);
        Assert.Equal(HttpStatusCode.BadGateway, bodies[3].Status);
        Assert.Equal(HttpStatusCode.BadGateway, bodies[6].Status);
        foreach (var (path, status, text) in bodies.Skip(1))
        {
            Assert.DoesNotContain(QuestionMarker, text, StringComparison.Ordinal);
            Assert.DoesNotContain(TemplateMarker, text, StringComparison.Ordinal);
            Assert.True(status is HttpStatusCode.OK or HttpStatusCode.BadGateway, path);
        }

        var logs = string.Join('\n', fixture.LogSink.Entries);
        var metrics = string.Join('\n', telemetry.Lines);
        var tables = await fixture.DumpAllTablesAsync();
        foreach (var marker in new[] { QuestionMarker, TemplateMarker })
        {
            Assert.DoesNotContain(marker, logs, StringComparison.Ordinal);
            Assert.DoesNotContain(marker, metrics, StringComparison.Ordinal);
            Assert.DoesNotContain(marker, tables, StringComparison.Ordinal);
        }

        Assert.Contains("zaghlol.llm", metrics, StringComparison.Ordinal); // the capture saw the LLM metrics at all
    }

    private Task ZaghlolTestDatabase_ExecuteAsync(string sql) => Zaghlol.Testing.ZaghlolTestDatabase.ExecuteAsync(fixture.Database.Superuser, sql);
}
