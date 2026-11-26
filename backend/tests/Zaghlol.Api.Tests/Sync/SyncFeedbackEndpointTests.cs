using System.Net;
using System.Text.Json;
using Zaghlol.Api.Tests.Llm;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Sync;

/// <summary>
/// T-353 through the real pipeline and PostgreSQL: feedback in <c>POST /v1/sync</c> is stored by verdict while the install's
/// <c>llm_categorise</c> flag is on, ignored while it is off, and a marker merchant reaches no log, trace, metric or table but the two feedback tables.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class SyncFeedbackEndpointTests(SyncHostFixture fixture) : IClassFixture<SyncHostFixture>
{
    private static string Item(string merchant, string verdict, string ai, string user, string source = "llm") =>
        "{\"merchantNorm\":" + JsonSerializer.Serialize(merchant) + ",\"verdict\":\"" + verdict + "\",\"aiCategory\":\"" + ai + "\",\"userCategory\":\"" + user + "\",\"source\":\"" + source + "\"}";

    private static string Feedback(params string[] items) => ",\"llmCatFeedback\":[" + string.Join(',', items) + "]";

    private Task SetFlagAsync(bool on) => ZaghlolTestDatabase.ExecuteAsync(
        fixture.Database.Superuser,
        $"INSERT INTO zaghlol.feature_flags (key, enabled, rules, version, updated_at, updated_by) VALUES ('llm_categorise', {(on ? "true" : "false")}, '{{}}'::jsonb, 1, now(), gen_random_uuid()) " +
        $"ON CONFLICT (key) DO UPDATE SET enabled = {(on ? "true" : "false")}, version = zaghlol.feature_flags.version + 1");

    private static async Task<JsonElement> AcceptedAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return document.RootElement.GetProperty("accepted").Clone();
    }

    // B97-M1: the install has made an attested categorise call (its counter row for the current Cairo month).
    private Task AttestAsync(string installId) => ZaghlolTestDatabase.ExecuteAsync(
        fixture.Database.Superuser,
        "INSERT INTO zaghlol.llm_quota_counters (feature, subject_kind, subject_id, month_key, used, updated_at) " +
        $"VALUES ('cat', 'install', '{Guid.Parse(installId):D}', {Zaghlol.Application.Llm.Quota.CairoMonth.MonthKey(DateTimeOffset.UtcNow)}, 1, now())");

    [Fact]
    public async Task FeedbackFromAnInstallThatNeverAttestedIsDroppedAndNotCounted()
    {
        await SetFlagAsync(true);
        var (_, token) = await fixture.NewInstallAsync();
        var merchant = SyncHostFixture.UniqueName("fbunattested");

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: Feedback(Item(merchant, "right", "dining", "dining"), Item(merchant + " x", "wrong", "dining", "groceries"))));
        var accepted = await AcceptedAsync(response);

        Assert.Equal(0, accepted.GetProperty("llmCatFeedback").GetInt32());
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm LIKE $1", "%fbunattested%"));
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm LIKE $1", "%fbunattested%"));
    }

    // AC 1, 2, 4 and 5 (negative proofs 1 and 2 of the task)
    [Fact]
    public async Task FeedbackIsStoredByVerdictWithOnlyTheHashAndTheMarkerNeverReachesALogATraceAMetricOrAnotherTable()
    {
        await SetFlagAsync(true);
        using var telemetry = new TelemetryCapture();
        var appVersion = SyncHostFixture.UniqueAppVersion();
        var (installId, token) = await fixture.NewInstallAsync(appVersion);
        await AttestAsync(installId);
        var right = SyncHostFixture.UniqueName("fbright");
        var wrong = SyncHostFixture.UniqueName("fbwrong");
        var custom = SyncHostFixture.UniqueName("fbcustom");
        var phone = SyncHostFixture.UniqueName("fbphone") + " 01012345678";
        var badCode = SyncHostFixture.UniqueName("fbbadcode");

        using var response = await fixture.SyncAsync(
            token,
            SyncHostFixture.Body(extra: Feedback(
                Item(right, "right", "dining", "dining", "llm"),
                Item(wrong, "wrong", "dining", "groceries", "cache"),
                Item(custom, "wrong", "dining", "custom", "catalog"),
                Item(phone, "right", "dining", "dining"),
                Item(badCode, "wrong", "dining", "madeup_code"))),
            app: SyncHostFixture.AppHeader(appVersion));
        var accepted = await AcceptedAsync(response);

        Assert.Equal(3, accepted.GetProperty("llmCatFeedback").GetInt32());
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = $1 AND category_code = 'dining' AND source = 'llm'", right));
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = $1 AND ai_category = 'dining' AND user_category = 'groceries' AND status = 'open'", wrong));
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = $1 AND user_category = 'custom'", custom));
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm LIKE $1", "%fbphone%")); // parameters: the test's own SQL text is a traced span too
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm LIKE $1", "%fbbadcode%"));

        // negative proof 1: a dump of both tables holds no install id, app version, IP or token
        var dump = (string)(await fixture.ScalarAsync(
            "SELECT coalesce((SELECT string_agg(row_to_json(t)::text, E'\\n') FROM zaghlol.llm_cat_confirmations t), '') || coalesce((SELECT string_agg(row_to_json(t)::text, E'\\n') FROM zaghlol.llm_cat_corrections t), '')"))!;
        Assert.Contains(right, dump, StringComparison.Ordinal);
        foreach (var secret in new[] { installId, appVersion, "127.0.0.1", token })
        {
            Assert.DoesNotContain(secret, dump, StringComparison.OrdinalIgnoreCase);
        }

        // negative proof 2: the markers are in no log, trace or metric
        var logs = string.Join('\n', fixture.LogSink.Entries);
        var metrics = string.Join('\n', telemetry.Lines);
        foreach (var marker in new[] { right, wrong, custom, "fbphone", "fbbadcode", "01012345678" })
        {
            Assert.DoesNotContain(marker, logs, StringComparison.Ordinal);
            Assert.DoesNotContain(marker, metrics, StringComparison.Ordinal);
        }

        Assert.Contains("llm_cat_correction", metrics, StringComparison.Ordinal);
    }

    // AC 2
    [Fact]
    public async Task WithTheFlagOffFeedbackIsIgnoredAndTheCountIsZero()
    {
        await SetFlagAsync(false);
        var (_, token) = await fixture.NewInstallAsync();
        var merchant = SyncHostFixture.UniqueName("fboff");

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body(extra: Feedback(Item(merchant, "right", "dining", "dining"))));
        var accepted = await AcceptedAsync(response);

        Assert.Equal(0, accepted.GetProperty("llmCatFeedback").GetInt32());
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = $1", merchant));
    }

    [Fact]
    public async Task WithoutTheMemberTheAcceptedBlockHasNoFeedbackCount()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var response = await fixture.SyncAsync(token, SyncHostFixture.Body());
        var accepted = await AcceptedAsync(response);

        Assert.False(accepted.TryGetProperty("llmCatFeedback", out _));
    }
}
