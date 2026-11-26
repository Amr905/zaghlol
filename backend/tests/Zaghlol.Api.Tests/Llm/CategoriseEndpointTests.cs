using System.Net;
using System.Text.Json;
using Npgsql;
using Zaghlol.Application.Llm;

namespace Zaghlol.Api.Tests.Llm;

/// <summary>
/// T-352: <c>POST /v1/categorise</c> through the real pipeline over PostgreSQL (the shared gate chain, the published catalog, the answer cache and the quota
/// counters), with the recorded fake provider. Each test makes its own install; the config, clock, flags and replies are reset before each.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class CategoriseEndpointTests(AskHostFixture fixture) : IClassFixture<AskHostFixture>, IAsyncLifetime
{
    private static readonly SemaphoreSlim Seeded = new(1, 1);
    private static readonly HashSet<string> SeededDatabases = [];

    public async Task InitializeAsync()
    {
        fixture.Reset();
        await fixture.SetFlagAsync("llm_categorise", true);
        await fixture.SetConfigAsync("cat.quota_free", "15");
        await fixture.SetConfigAsync("cat.batch_max", "20");
        await fixture.SetConfigAsync("cat.min_confidence", "60");
        await SeedCatalogAsync();
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private static string Unique(string prefix) => prefix + string.Concat(Guid.NewGuid().ToByteArray().Select(b => (char)('a' + (b % 26))));

    private static JsonElement Json(string text) => JsonDocument.Parse(text).RootElement.Clone();

    private static string Reply(params (int I, string C, int P)[] items) =>
        "{\"r\":[" + string.Join(',', items.Select(x => $"{{\"i\":{x.I},\"c\":{JsonSerializer.Serialize(x.C)},\"p\":{x.P}}}")) + "]}";

    private static string[] Results(JsonElement body) =>
        [.. body.GetProperty("results").EnumerateArray().Select(r => r.GetProperty("status").GetString() + (r.GetProperty("source").ValueKind == JsonValueKind.Null ? string.Empty : "/" + r.GetProperty("source").GetString()))];

    private async Task SeedCatalogAsync()
    {
        await Seeded.WaitAsync();
        try
        {
            if (!SeededDatabases.Add(fixture.Database.Superuser))
            {
                return;
            }

            await Zaghlol.Testing.ZaghlolTestDatabase.ExecuteAsync(
                fixture.Database.Superuser,
                """
                INSERT INTO zaghlol.catalog_categories (code, name_ar, name_en, icon, color, bucket, sort, version) VALUES
                  ('dining', 'مطاعم', 'Dining', 'fork', '#0F7A55', 'wants', 1, 1),
                  ('health', 'صحة', 'Health', 'pill', '#0F7A55', 'needs', 2, 1),
                  ('education', 'تعليم', 'Education', 'book', '#0F7A55', 'needs', 3, 1);
                INSERT INTO zaghlol.catalog_versions (version, published_at, published_by, full_snapshot_url, full_snapshot_sha256) VALUES
                  (1, now(), gen_random_uuid(), 'https://cdn.zaghlol.test/v1/catalog/1/full', decode(repeat('00', 32), 'hex'));
                INSERT INTO zaghlol.catalog_merchants (canonical, name_ar, name_en, category_code, version) VALUES ('green leaf pharmacy', 'صيدلية', 'Green Leaf Pharmacy', 'health', 1);
                INSERT INTO zaghlol.catalog_aliases (merchant_id, alias_norm, match, version)
                  SELECT id, 'green leaf pharmacy', 'exact', 1 FROM zaghlol.catalog_merchants WHERE canonical = 'green leaf pharmacy';
                """);
        }
        finally
        {
            Seeded.Release();
        }
    }

    private Task PutCacheAsync(string key, string code, int confidence) => Zaghlol.Testing.ZaghlolTestDatabase.ExecuteAsync(
        fixture.Database.Superuser,
        $"INSERT INTO zaghlol.llm_cat_answer_cache (merchant_norm, category_code, confidence, provider_id, prompt_version, created_at, expires_at) VALUES ('{key}', '{code}', {confidence}, 'fake-a', 'cat-v1', now(), now() + interval '30 days') ON CONFLICT (merchant_norm) DO NOTHING");

    private async Task<(HttpResponseMessage Response, string Text)> CatAsync(string installId, string token, string[] merchants, string? requestId = null, string? extra = null)
    {
        var response = await fixture.PostCatAsync(token, AskHostFixture.CatBody(installId, merchants, requestId, extra: extra ?? string.Empty));
        return (response, await response.Content.ReadAsStringAsync());
    }

    private static void AssertProblem(HttpResponseMessage response, string text, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(code, Json(text).GetProperty("code").GetString());
    }

    private async Task<long> CacheHitsAsync(string key)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT hits FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", connection);
        command.Parameters.Add(new NpgsqlParameter { Value = key });
        return Convert.ToInt64(await command.ExecuteScalarAsync() ?? -1L);
    }

    // AC 1: a catalog hit and a cache hit are free; the counter and the provider are untouched.
    [Fact]
    public async Task ACatalogHitAndACacheHitAreFreeAndTheCounterAndTheProviderAreUntouched()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var cached = Unique("cachedcafe");
        await PutCacheAsync(cached, "dining", 90);
        var calls = fixture.Provider.Calls;

        var (response, text) = await CatAsync(id, token, ["Green Leaf  Pharmacy", cached]);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("no-store", response.Headers.CacheControl?.ToString());
        var body = Json(text);
        Assert.Equal(["ok/catalog", "ok/cache"], Results(body));
        var first = body.GetProperty("results")[0];
        Assert.Equal("Green Leaf  Pharmacy", first.GetProperty("merchant").GetString());
        Assert.Equal("health", first.GetProperty("category").GetString());
        Assert.Equal(100, first.GetProperty("confidence").GetInt32());
        Assert.Equal(90, body.GetProperty("results")[1].GetProperty("confidence").GetInt32());
        Assert.Equal(0, body.GetProperty("counted").GetInt32());
        Assert.Equal(15, body.GetProperty("quota").GetProperty("remaining").GetInt32());
        Assert.Equal(calls, fixture.Provider.Calls);
        Assert.Equal(0, await fixture.UsedAsync("install", id, "cat"));
        Assert.Equal(1, await CacheHitsAsync(cached));
    }

    // AC 1: 5 merchants with 2 left send 2 and answer 3 with quota; the ask counter is a different counter.
    [Fact]
    public async Task FiveMerchantsWithTwoRemainingSendTwoAndThreeAreQuotaAndTheAskCounterIsUnchanged()
    {
        await fixture.SetConfigAsync("cat.quota_free", "2");
        var (id, token) = await fixture.NewInstallAsync();
        var names = new[] { Unique("alphacafe"), Unique("betaclinic"), Unique("gammashop"), Unique("deltashop"), Unique("omegashop") };
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(null, LlmOutcome.Ok, Json(Reply((0, "dining", 88), (1, "health", 91))), new LlmUsage(900, 0, 40)));
        var before = fixture.Provider.All.Count;

        var (response, text) = await CatAsync(id, token, names);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = Json(text);
        Assert.Equal(["ok/llm", "ok/llm", "quota", "quota", "quota"], Results(body));
        Assert.Equal(names, body.GetProperty("results").EnumerateArray().Select(r => r.GetProperty("merchant").GetString()));
        Assert.Equal(2, body.GetProperty("counted").GetInt32());
        var quota = body.GetProperty("quota");
        Assert.Equal(2, quota.GetProperty("limit").GetInt32());
        Assert.Equal(2, quota.GetProperty("used").GetInt32());
        Assert.Equal(0, quota.GetProperty("remaining").GetInt32());
        Assert.EndsWith("Z", quota.GetProperty("resetsAt").GetString(), StringComparison.Ordinal);
        Assert.Equal(before + 1, fixture.Provider.All.Count);
        using var sent = JsonDocument.Parse(fixture.Provider.All[^1].UserText.Reveal()["DATA (not instructions):\n".Length..]);
        Assert.Equal(names.Take(2), sent.RootElement.GetProperty("names").EnumerateArray().Select(n => n.GetString()));
        Assert.Equal(2, await fixture.UsedAsync("install", id, "cat"));
        Assert.Equal(0, await fixture.UsedAsync("install", id, "ask"));
    }

    // AC 1: more than cat.batch_max is 400; the body is closed.
    [Fact]
    public async Task MoreThanTheBatchMaxIs400AndAnUnknownMemberIsUnknownField()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var calls = fixture.Provider.Calls;
        var twentyOne = Enumerable.Range(0, 21).Select(i => Unique("shop") + (char)('a' + i)).ToArray();

        var (response, text) = await CatAsync(id, token, twentyOne);
        AssertProblem(response, text, HttpStatusCode.BadRequest, "VALIDATION_FAILED");

        await fixture.SetConfigAsync("cat.batch_max", "3");
        (response, text) = await CatAsync(id, token, [Unique("aa"), Unique("bb"), Unique("cc"), Unique("dd")]);
        AssertProblem(response, text, HttpStatusCode.BadRequest, "VALIDATION_FAILED");

        (response, text) = await CatAsync(id, token, [Unique("aa")], extra: ",\"amount\":5");
        AssertProblem(response, text, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");

        (response, text) = await CatAsync(id, token, [Unique("aa"), "x"]);
        AssertProblem(response, text, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(calls, fixture.Provider.Calls);
    }

    // AC 1: a retried request id is not counted twice.
    [Fact]
    public async Task ARetriedRequestIdIsNotCountedTwice()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var name = Unique("retrycafe");
        var requestId = AskHostFixture.NewRequestId();
        fixture.Replies.Add(AskHostFixture.Reply(name, Reply((0, "dining", 70))));

        var (first, firstText) = await CatAsync(id, token, [name], requestId);
        var (second, secondText) = await CatAsync(id, token, [name], requestId);

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(["ok/llm"], Results(Json(firstText)));
        Assert.Equal(["ok/llm"], Results(Json(secondText)));
        Assert.Equal(1, await fixture.UsedAsync("install", id, "cat"));
        Assert.Equal(14, Json(firstText).GetProperty("quota").GetProperty("remaining").GetInt32());
        Assert.Equal(14, Json(secondText).GetProperty("quota").GetProperty("remaining").GetInt32());
    }

    // AC 2: answers outside the closed set are no answer for that merchant, and nothing is counted or cached.
    [Fact]
    public async Task AFreeTextCategoryAnOutOfRangeIndexADuplicateIndexAndAnEchoedNameAreUnknown()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var echoed = Unique("echoname");
        var cases = new Dictionary<string, string>
        {
            ["free text"] = Reply((0, "Food & Drinks", 95)),
            ["out of range"] = Reply((5, "dining", 95)),
            ["duplicate"] = Reply((0, "dining", 95), (0, "health", 95)),
            ["echoed"] = Reply((0, echoed, 95)),
        };

        foreach (var (label, reply) in cases)
        {
            var name = Unique("closedset");
            fixture.Replies.Clear();
            fixture.Replies.Add(AskHostFixture.Reply(name, reply));

            var (response, text) = await CatAsync(id, token, [name]);

            Assert.True(response.StatusCode == HttpStatusCode.OK, label);
            Assert.Equal(["unknown"], Results(Json(text)));
            Assert.Equal(0, Json(text).GetProperty("counted").GetInt32());
            Assert.DoesNotContain(echoed, text, StringComparison.Ordinal);
        }

        Assert.Equal(0, await fixture.UsedAsync("install", id, "cat"));
        Assert.DoesNotContain("llm_cat_answer_cache", await fixture.TablesContainingAsync("closedset"));
    }

    // Negative proof 1 (AC 3): at quota 0 the provider is never called and free hits still answer ok (200, never 403).
    [Fact]
    public async Task ABatchAtQuotaZeroMakesNoProviderCallAndCatalogAndCacheHitsStillAnswerOk()
    {
        await fixture.SetConfigAsync("cat.quota_free", "0");
        var (id, token) = await fixture.NewInstallAsync();
        var cached = Unique("zerocache");
        await PutCacheAsync(cached, "education", 85);
        var calls = fixture.Provider.Calls;

        var (response, text) = await CatAsync(id, token, ["green leaf pharmacy", cached, Unique("unseenshop")]);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = Json(text);
        Assert.Equal(["ok/catalog", "ok/cache", "quota"], Results(body));
        Assert.Equal(0, body.GetProperty("quota").GetProperty("remaining").GetInt32());
        Assert.Equal(calls, fixture.Provider.Calls);
        Assert.Equal(0, await fixture.UsedAsync("install", id, "cat"));
    }

    // AC 6: the same problem codes as Ask, and never a call to the provider.
    [Fact]
    public async Task FlagOffPausedConsentMismatchAndAMissingProofAreRefusedLikeAskAndNeverReachTheProvider()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var name = Unique("gaterow");
        fixture.Replies.Add(AskHostFixture.Reply(name, Reply((0, "dining", 95))));
        var calls = fixture.Provider.Calls;

        var consent = await fixture.PostCatAsync(token, AskHostFixture.CatBody(id, [name], provider: "other-provider"));
        AssertProblem(consent, await consent.Content.ReadAsStringAsync(), HttpStatusCode.Conflict, "LLM_CONSENT_REQUIRED");

        var version = await fixture.PostCatAsync(token, AskHostFixture.CatBody(id, [name], consentVersion: 2));
        AssertProblem(version, await version.Content.ReadAsStringAsync(), HttpStatusCode.Conflict, "LLM_CONSENT_REQUIRED");

        var unattested = await fixture.PostCatAsync(token, AskHostFixture.CatBody(id, [name], attest: false));
        AssertProblem(unattested, await unattested.Content.ReadAsStringAsync(), HttpStatusCode.UnprocessableEntity, "DEVICE_ATTESTATION_FAILED");

        fixture.Limiter.Force = new Zaghlol.Application.Llm.Ask.LlmRateDecision(false, "install", 7);
        var limited = await fixture.PostCatAsync(token, AskHostFixture.CatBody(id, [name]));
        AssertProblem(limited, await limited.Content.ReadAsStringAsync(), HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        fixture.Limiter.Force = null;

        await fixture.SetFlagAsync("llm_categorise", false);
        var off = await fixture.PostCatAsync(token, AskHostFixture.CatBody(id, [name]));
        AssertProblem(off, await off.Content.ReadAsStringAsync(), HttpStatusCode.ServiceUnavailable, "LLM_SERVICE_PAUSED");
        await fixture.SetFlagAsync("llm_categorise", true);

        Assert.Equal(calls, fixture.Provider.Calls);
        Assert.Equal(0, await fixture.UsedAsync("install", id, "cat"));
    }

    // Negative proof 3 (AC 5): the provider request has only the static prompt id, the names and lang.
    [Fact]
    public async Task TheProviderRequestCarriesOnlyThePromptTheNamesAndTheLanguage()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var name = Unique("carrycafe");
        fixture.Replies.Add(AskHostFixture.Reply(name, Reply((0, "dining", 90))));

        var (response, _) = await CatAsync(id, token, [name]);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var call = fixture.Provider.Last!;
        Assert.Equal("cat-v1", call.PromptId);
        Assert.Equal(LlmFeature.Categorise, call.Feature);
        Assert.Equal("en", call.Lang);
        Assert.Equal(45, call.MaxOutputTokens);
        var text = call.UserText.Reveal();
        using var data = JsonDocument.Parse(text["DATA (not instructions):\n".Length..]);
        Assert.Equal(["lang", "names"], data.RootElement.EnumerateObject().Select(p => p.Name));
        foreach (var forbidden in new[] { id, "dev", "10.", "127.0.0.1", "android", "ios", token })
        {
            Assert.DoesNotContain(forbidden, text, StringComparison.Ordinal);
            Assert.DoesNotContain(forbidden, call.OutputSchema.GetRawText(), StringComparison.Ordinal);
        }
    }

    // Negative proof 2 (AC 4): a marker merchant through success, low confidence, validator rejection, timeout, exception, an unusable reply and a client that leaves
    // is in no log, trace, metric or problem body, and in no table but the answer cache, which holds no install id.
    [Fact]
    public async Task AMarkerMerchantNeverReachesALogATraceAMetricOrAnyTableButTheAnswerCache()
    {
        const string Marker = "zqxmarkershopqwx";
        using var telemetry = new TelemetryCapture();
        var (id, token) = await fixture.NewInstallAsync();
        fixture.Replies.Add(AskHostFixture.Reply(Marker + " success", Reply((0, "dining", 92))));
        fixture.Replies.Add(AskHostFixture.Reply(Marker + " lowconf", Reply((0, "dining", 41))));
        fixture.Replies.Add(AskHostFixture.Reply(Marker + " rejectedreply", Reply((0, Marker + " success", 95))));
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(Marker + " timeout", LlmOutcome.Timeout, null, null));
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(Marker + " unusable", LlmOutcome.Invalid, null, null));
        fixture.Replies.Add(new Zaghlol.Testing.FakeReply(Marker + " refused", LlmOutcome.Refused, null, null));
        fixture.Provider.ThrowWhenQuestionContains = Marker + " exception";
        fixture.Provider.StallWhenQuestionContains = Marker + " abort";

        var bodies = new List<(string Path, HttpStatusCode Status, string Text)>();
        foreach (var path in new[] { "success", "lowconf", "rejectedreply", "timeout", "unusable", "refused", "exception" })
        {
            var (response, text) = await CatAsync(id, token, [$"{Marker} {path}"]);
            bodies.Add((path, response.StatusCode, text));
        }

        using (var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(600)))
        {
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => fixture.PostCatAsync(token, AskHostFixture.CatBody(id, [$"{Marker} abort"]), cancellationToken: cts.Token));
        }

        // a rejected name: the marker next to an identifier shape is never sent, cached or stored
        var (rejectedResponse, rejectedText) = await CatAsync(id, token, [$"{Marker} 123456"]);
        await Task.Delay(500);

        Assert.Equal(["ok/llm"], Results(Json(bodies[0].Text)));
        Assert.Equal(1, fixture.Provider.Throws);
        Assert.Equal(HttpStatusCode.BadGateway, bodies[3].Status);
        Assert.Equal(HttpStatusCode.BadGateway, bodies[6].Status);
        Assert.Equal(["rejected"], Results(Json(rejectedText)));
        Assert.Equal(HttpStatusCode.OK, rejectedResponse.StatusCode);
        foreach (var (path, status, text) in bodies.Skip(1))
        {
            Assert.DoesNotContain(Marker, text, StringComparison.Ordinal);
            Assert.True(status is HttpStatusCode.OK or HttpStatusCode.BadGateway, path);
        }

        var logs = string.Join('\n', fixture.LogSink.Entries);
        var metrics = string.Join('\n', telemetry.Lines);
        Assert.DoesNotContain(Marker, logs, StringComparison.Ordinal);
        Assert.DoesNotContain(Marker, metrics, StringComparison.Ordinal);
        Assert.Contains("zaghlol.llm", metrics, StringComparison.Ordinal);
        Assert.Equal(["llm_cat_answer_cache"], await fixture.TablesContainingAsync(Marker));
        Assert.Equal(1, await CacheRowsAsync(Marker));

        // the cache row has no column that could name an install, an account, an address or a version, and no install id inside
        Assert.Empty(await CacheColumnsAsync("install", "account", "ip", "version", "token"));
        Assert.DoesNotContain(id, await DumpCacheAsync(), StringComparison.OrdinalIgnoreCase);
    }

    // AC 2 / FR-LCAT-10: a free-text reply for a name that the cache then answers; and only answers at the cache threshold are cached.
    [Fact]
    public async Task OnlyAConfidentAnswerIsCachedAndTheNextBatchGetsItFromTheCacheForFree()
    {
        var (id, token) = await fixture.NewInstallAsync();
        var high = Unique("highconf");
        var mid = Unique("midconf");
        fixture.Replies.Add(AskHostFixture.Reply(high, Reply((0, "education", 80))));
        fixture.Replies.Add(AskHostFixture.Reply(mid, Reply((0, "education", 79))));

        await CatAsync(id, token, [high]);
        await CatAsync(id, token, [mid]);
        var (_, text) = await CatAsync(id, token, [high]);

        Assert.Equal(["ok/cache"], Results(Json(text)));
        Assert.Equal(2, await fixture.UsedAsync("install", id, "cat"));
        Assert.Equal(1, await CacheRowsAsync(high));
        Assert.Equal(0, await CacheRowsAsync(mid));
    }

    private async Task<long> CacheRowsAsync(string like)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm LIKE $1", connection);
        command.Parameters.Add(new NpgsqlParameter { Value = like + "%" });
        return (long)(await command.ExecuteScalarAsync())!;
    }

    private async Task<IReadOnlyList<string>> CacheColumnsAsync(params string[] fragments)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT column_name FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name = 'llm_cat_answer_cache'", connection);
        var columns = new List<string>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            columns.Add(reader.GetString(0));
        }

        return [.. columns.Where(c => fragments.Any(f => c.Contains(f, StringComparison.OrdinalIgnoreCase)))];
    }

    private async Task<string> DumpCacheAsync()
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT coalesce(string_agg(row_to_json(t)::text, E'\\n'), '') FROM zaghlol.llm_cat_answer_cache t", connection);
        return (string)(await command.ExecuteScalarAsync())!;
    }
}
