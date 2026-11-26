using System.Net;
using System.Text.Json.Nodes;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Flags;
using Zaghlol.Testing;
using TestProblems = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Llm;

/// <summary>
/// T-354: the operator review of AI categories through the real pipeline. AC1 groups only (no hash, no per-install row); AC2 a custom
/// correction can't be promoted and a promote reaches the draft only; AC3 the confirmed list at three distinct installs and hidden by an
/// open correction; AC4 one audit row per resolve and 403 without the role.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class LlmCatReviewEndpointTests(AdminFlagFixture fixture) : IClassFixture<AdminFlagFixture>
{
    private const string Editor = OperatorRoles.CatalogEditor;
    private const string CorrectionsQuery = "/admin/v1/llm-cat/corrections/query";
    private const string CorrectionsResolve = "/admin/v1/llm-cat/corrections/resolve";
    private const string ConfirmedQuery = "/admin/v1/llm-cat/confirmed/query";
    private const string ConfirmedResolve = "/admin/v1/llm-cat/confirmed/resolve";

    private static string Unique(string prefix) =>
        prefix + " " + string.Concat(Guid.NewGuid().ToByteArray().Take(8).Select(b => (char)('a' + (b % 26))));

    private static string Code() => "t354" + string.Concat(Guid.NewGuid().ToByteArray().Take(6).Select(b => (char)('a' + (b % 26))));

    private async Task ExecuteAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        await command.ExecuteNonQueryAsync();
    }

    private async Task SeedCorrectionsAsync(string norm, string ai, string user, int installs, string status = "open")
    {
        for (var i = 0; i < installs; i++)
        {
            await ExecuteAsync(
                "INSERT INTO zaghlol.llm_cat_corrections (id, merchant_norm, ai_category, user_category, source, install_hash, created_at, status) "
                + "VALUES (gen_random_uuid(), @norm, @ai, @user, 'llm', decode(md5(random()::text) || md5(random()::text), 'hex'), date_trunc('day', now()) - make_interval(days => @age), @status)",
                ("norm", norm), ("ai", ai), ("user", user), ("age", i), ("status", status));
        }
    }

    private async Task SeedConfirmationsAsync(string norm, string category, int installs)
    {
        for (var i = 0; i < installs; i++)
        {
            await ExecuteAsync(
                "INSERT INTO zaghlol.llm_cat_confirmations (id, merchant_norm, category_code, source, install_hash, created_at) "
                + "VALUES (gen_random_uuid(), @norm, @category, 'llm', decode(md5(random()::text) || md5(random()::text), 'hex'), date_trunc('day', now()))",
                ("norm", norm), ("category", category));
        }
    }

    private async Task EnsureCategoryAsync(string token, string code)
    {
        using var response = await fixture.SendAsync(
            HttpMethod.Put,
            "/admin/v1/catalog/draft/categories/" + code,
            token,
            "{\"nameAr\":\"x\",\"nameEn\":\"Test\",\"icon\":\"fork\",\"color\":\"#112233\",\"bucket\":\"wants\",\"sort\":1}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private async Task<JsonNode> PostAsync(string path, string token, string body, HttpStatusCode expected = HttpStatusCode.OK)
    {
        using var response = await fixture.SendAsync(HttpMethod.Post, path, token, body);
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == expected, $"{path}: {(int)response.StatusCode} {text}");
        Assert.True(response.Headers.CacheControl?.NoStore);
        return JsonNode.Parse(text)!;
    }

    private async Task<JsonArray> CorrectionGroupsAsync(string token, string marker)
    {
        var page = await PostAsync(CorrectionsQuery, token, "{\"limit\":100}");
        return new JsonArray([.. page["items"]!.AsArray().Where(i => i!["merchantNorm"]!.GetValue<string>().StartsWith(marker, StringComparison.Ordinal)).Select(i => JsonNode.Parse(i!.ToJsonString()))]);
    }

    private async Task<object?> ScalarAsync(string sql, params (string, object)[] parameters)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        return await command.ExecuteScalarAsync();
    }

    private Task<long> AuditAsync(Guid operatorId, string action) =>
        ScalarAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id AND action = @action", ("id", operatorId), ("action", action)).ContinueWith(t => (long)t.Result!);

    private Task<long> CountAsync(string sql, params (string, object)[] parameters) => ScalarAsync(sql, parameters).ContinueWith(t => (long)t.Result!);

    private static string Resolve(string norm, string ai, string user, string action) =>
        $"{{\"merchantNorm\":\"{norm}\",\"aiCategory\":\"{ai}\",\"userCategory\":\"{user}\",\"action\":\"{action}\"}}";

    private static string ResolveConfirmed(string norm, string category, string action) =>
        $"{{\"merchantNorm\":\"{norm}\",\"category\":\"{category}\",\"action\":\"{action}\"}}";

    // ---- AC1 -------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task TheCorrectionsQueryReturnsGroupsOnlyOpenFirstByVotesAndNoHash()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        var marker = Unique("t354 q");
        await SeedCorrectionsAsync(marker + " big", "dining", "education", 3);
        await SeedCorrectionsAsync(marker + " small", "dining", "groceries", 1);
        await SeedCorrectionsAsync(marker + " done", "dining", "custom", 5, "rejected");

        var items = await CorrectionGroupsAsync(token, marker);

        Assert.Equal([marker + " big", marker + " small", marker + " done"], items.Select(i => i!["merchantNorm"]!.GetValue<string>()));
        Assert.Equal([3, 1, 5], items.Select(i => i!["votes"]!.GetValue<int>()));
        Assert.Equal(["open", "open", "rejected"], items.Select(i => i!["status"]!.GetValue<string>()));
        var big = items[0]!.AsObject();
        Assert.Equal(
            ["aiCategory", "firstSeen", "lastSeen", "merchantNorm", "status", "userCategory", "votes"],
            big.Select(p => p.Key).Order(StringComparer.Ordinal));
        Assert.Matches(@"^\d{4}-\d{2}-\d{2}$", big["firstSeen"]!.GetValue<string>());
        Assert.True(string.CompareOrdinal(big["firstSeen"]!.GetValue<string>(), big["lastSeen"]!.GetValue<string>()) <= 0);

        var raw = (await PostAsync(CorrectionsQuery, token, "{\"limit\":100}")).ToJsonString();
        Assert.DoesNotContain("hash", raw, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("install", raw, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TheStatusFilterAndThePagingWork()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        var marker = Unique("t354 p");
        for (var i = 0; i < 3; i++)
        {
            await SeedCorrectionsAsync($"{marker} {i}", "dining", "education", 1, "prompt_issue");
        }

        var seen = new List<string>();
        string? cursor = null;
        for (var guard = 0; guard < 200; guard++)
        {
            var body = cursor is null ? "{\"status\":\"prompt_issue\",\"limit\":2}" : $"{{\"status\":\"prompt_issue\",\"limit\":2,\"cursor\":\"{cursor}\"}}";
            var page = await PostAsync(CorrectionsQuery, token, body);
            Assert.True(page["items"]!.AsArray().Count <= 2);
            Assert.All(page["items"]!.AsArray(), i => Assert.Equal("prompt_issue", i!["status"]!.GetValue<string>()));
            seen.AddRange(page["items"]!.AsArray().Select(i => i!["merchantNorm"]!.GetValue<string>()));
            cursor = page["nextCursor"]?.GetValue<string>();
            if (cursor is null)
            {
                break;
            }
        }

        Assert.Equal(3, seen.Count(m => m.StartsWith(marker, StringComparison.Ordinal)));
    }

    [Theory]
    [InlineData(CorrectionsQuery, "{\"status\":\"collecting\"}")]
    [InlineData(CorrectionsQuery, "{\"limit\":0}")]
    [InlineData(CorrectionsQuery, "{\"limit\":101}")]
    [InlineData(CorrectionsQuery, "{\"cursor\":\"-1\"}")]
    [InlineData(CorrectionsQuery, "{\"cursor\":\"1234567890\"}")]
    [InlineData(ConfirmedQuery, "{\"limit\":0}")]
    [InlineData(ConfirmedQuery, "{\"cursor\":\"x\"}")]
    [InlineData(CorrectionsResolve, "{\"merchantNorm\":\"x\",\"aiCategory\":\"dining\",\"userCategory\":\"education\",\"action\":\"promote\"}")]
    [InlineData(CorrectionsResolve, "{\"merchantNorm\":\"zawya coffee\",\"aiCategory\":\"Dining\",\"userCategory\":\"education\",\"action\":\"promote\"}")]
    [InlineData(CorrectionsResolve, "{\"merchantNorm\":\"zawya coffee\",\"aiCategory\":\"custom\",\"userCategory\":\"education\",\"action\":\"reject\"}")]
    [InlineData(CorrectionsResolve, "{\"merchantNorm\":\"zawya coffee\",\"aiCategory\":\"dining\",\"userCategory\":\"education\",\"action\":\"delete\"}")]
    [InlineData(ConfirmedResolve, "{\"merchantNorm\":\"zawya coffee\",\"category\":\"dining\",\"action\":\"prompt_issue\"}")]
    [InlineData(ConfirmedResolve, "{\"merchantNorm\":\"zawya coffee\",\"category\":\"custom\",\"action\":\"promote\"}")]
    public async Task AMalformedBodyIs400ValidationFailed(string path, string body)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);

        using var response = await fixture.SendAsync(HttpMethod.Post, path, token, body);

        await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id", ("id", operatorId)));
    }

    [Theory]
    [InlineData(CorrectionsQuery, "{\"installHash\":\"x\"}")]
    [InlineData(ConfirmedQuery, "{\"status\":\"open\"}")]
    [InlineData(CorrectionsResolve, "{\"merchantNorm\":\"zawya coffee\",\"aiCategory\":\"dining\",\"userCategory\":\"education\",\"action\":\"reject\",\"extra\":1}")]
    public async Task AnUnknownMemberIs400UnknownField(string path, string body)
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);

        using var response = await fixture.SendAsync(HttpMethod.Post, path, token, body);

        await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
    }

    // ---- AC2 -------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task PromotingACustomCorrectionIs400AndChangesNothingButRejectAndPromptIssueWork()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var norm = Unique("t354 custom");
        await SeedCorrectionsAsync(norm, "dining", "custom", 2);

        using var promote = await fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, token, Resolve(norm, "dining", "custom", "promote"));

        await TestProblems.AssertAsync(promote, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(2L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @n AND status = 'open'", ("n", norm)));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id", ("id", operatorId)));

        var issue = await PostAsync(CorrectionsResolve, token, Resolve(norm, "dining", "custom", "prompt_issue"));
        Assert.Equal("prompt_issue", issue["status"]!.GetValue<string>());
        Assert.Equal(2, issue["rows"]!.GetValue<int>());
        Assert.Null(issue["merchantId"]);

        var other = Unique("t354 custom2");
        await SeedCorrectionsAsync(other, "dining", "custom", 1);
        var rejected = await PostAsync(CorrectionsResolve, token, Resolve(other, "dining", "custom", "reject"));
        Assert.Equal("rejected", rejected["status"]!.GetValue<string>());
        Assert.Equal(1L, await AuditAsync(operatorId, "llmcat_correction_prompt_issue"));
        Assert.Equal(1L, await AuditAsync(operatorId, "llmcat_correction_reject"));
    }

    [Fact]
    public async Task APromoteWritesTheDraftCatalogOnlyAndNeverPublishes()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var category = Code();
        await EnsureCategoryAsync(token, category);
        var norm = Unique("t354 promote");
        await SeedCorrectionsAsync(norm, "dining", category, 3);
        var versionsBefore = await CountAsync("SELECT count(*) FROM zaghlol.catalog_versions");

        var result = await PostAsync(CorrectionsResolve, token, Resolve(norm, "dining", category, "promote"));

        Assert.Equal("promoted", result["status"]!.GetValue<string>());
        Assert.Equal(3, result["rows"]!.GetValue<int>());
        var merchantId = result["merchantId"]!.GetValue<int>();
        Assert.True(merchantId >= 1);
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND NOT deleted AND body ->> 'canonical' = @n AND body ->> 'category' = @c", ("n", norm), ("c", category)));
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'aliases' AND NOT deleted AND entry_key LIKE @k", ("k", merchantId + ":%")));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_merchants WHERE canonical = @n", ("n", norm)));
        Assert.Equal(versionsBefore, await CountAsync("SELECT count(*) FROM zaghlol.catalog_versions"));
        Assert.Equal(3L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @n AND status = 'promoted' AND operator_id = @op AND resolved_at IS NOT NULL", ("n", norm), ("op", operatorId)));
        Assert.Equal(1L, await AuditAsync(operatorId, "llmcat_correction_promote"));
    }

    [Fact]
    public async Task APromoteReusesTheDraftMerchantOfTheSameCategoryAndRefusesAnotherCategory()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var category = Code();
        var otherCategory = Code();
        await EnsureCategoryAsync(token, category);
        await EnsureCategoryAsync(token, otherCategory);
        var norm = Unique("t354 reuse");
        await SeedCorrectionsAsync(norm, "dining", category, 1);
        var first = await PostAsync(CorrectionsResolve, token, Resolve(norm, "dining", category, "promote"));

        await SeedCorrectionsAsync(norm, "groceries", category, 1);
        var second = await PostAsync(CorrectionsResolve, token, Resolve(norm, "groceries", category, "promote"));
        Assert.Equal(first["merchantId"]!.GetValue<int>(), second["merchantId"]!.GetValue<int>());
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND body ->> 'canonical' = @n", ("n", norm)));

        await SeedCorrectionsAsync(norm, "dining", otherCategory, 1);
        using var conflict = await fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, token, Resolve(norm, "dining", otherCategory, "promote"));
        await TestProblems.AssertAsync(conflict, HttpStatusCode.Conflict, "ADMIN_CONFLICT");
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @n AND user_category = @c AND status = 'open'", ("n", norm), ("c", otherCategory)));
        Assert.Equal(2L, await AuditAsync(operatorId, "llmcat_correction_promote"));
    }

    [Fact]
    public async Task APromoteIntoACategoryThatIsNotInTheDraftIs409AndLeavesTheRowsOpen()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var norm = Unique("t354 nocat");
        await SeedCorrectionsAsync(norm, "dining", "zz_not_in_draft", 1);

        using var response = await fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, token, Resolve(norm, "dining", "zz_not_in_draft", "promote"));

        await TestProblems.AssertAsync(response, HttpStatusCode.Conflict, "ADMIN_CONFLICT");
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @n AND status = 'open'", ("n", norm)));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE body ->> 'canonical' = @n", ("n", norm)));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id", ("id", operatorId)));
    }

    // ---- AC3 -------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task AMerchantIsConfirmedAtThreeDistinctInstallsAndHiddenWhileACorrectionIsOpen()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var marker = Unique("t354 c");
        var two = marker + " two";
        var three = marker + " three";
        var blocked = marker + " blocked";
        await SeedConfirmationsAsync(two, "dining", 2);
        await SeedConfirmationsAsync(three, "dining", 3);
        await SeedConfirmationsAsync(blocked, "dining", 4);
        await SeedCorrectionsAsync(blocked, "dining", "education", 1);

        async Task<List<JsonNode>> ListedAsync()
        {
            var page = await PostAsync(ConfirmedQuery, token, "{\"limit\":100}");
            return [.. page["items"]!.AsArray().Where(i => i!["merchantNorm"]!.GetValue<string>().StartsWith(marker, StringComparison.Ordinal)).Select(i => i!)];
        }

        var listed = await ListedAsync();
        Assert.Equal([three], listed.Select(i => i["merchantNorm"]!.GetValue<string>()));
        Assert.Equal(3, listed[0]["votes"]!.GetValue<int>());
        Assert.Equal(["category", "firstSeen", "lastSeen", "merchantNorm", "votes"], listed[0].AsObject().Select(p => p.Key).Order(StringComparer.Ordinal));
        Assert.DoesNotContain("hash", listed[0].ToJsonString(), StringComparison.OrdinalIgnoreCase);

        // Resolving the open correction (reject) shows the merchant.
        await PostAsync(CorrectionsResolve, token, Resolve(blocked, "dining", "education", "reject"));
        Assert.Equal([blocked, three], (await ListedAsync()).Select(i => i["merchantNorm"]!.GetValue<string>()).Order(StringComparer.Ordinal));
        Assert.Equal(1L, await AuditAsync(operatorId, "llmcat_correction_reject"));
    }

    [Fact]
    public async Task ConfirmedResolvePromotesToTheDraftOrRejectsAndRechecksTheRule()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var category = Code();
        await EnsureCategoryAsync(token, category);
        var promoted = Unique("t354 cp");
        var rejected = Unique("t354 cr");
        var short_ = Unique("t354 cs");
        var blocked = Unique("t354 cb");
        await SeedConfirmationsAsync(promoted, category, 3);
        await SeedConfirmationsAsync(rejected, category, 3);
        await SeedConfirmationsAsync(short_, category, 2);
        await SeedConfirmationsAsync(blocked, category, 3);
        await SeedCorrectionsAsync(blocked, category, "education", 1);

        var done = await PostAsync(ConfirmedResolve, token, ResolveConfirmed(promoted, category, "promote"));
        Assert.Equal("promoted", done["status"]!.GetValue<string>());
        Assert.Equal(3, done["rows"]!.GetValue<int>());
        Assert.True(done["merchantId"]!.GetValue<int>() >= 1);
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND body ->> 'canonical' = @n", ("n", promoted)));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_merchants WHERE canonical = @n", ("n", promoted)));
        Assert.Equal(3L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = @n AND status = 'promoted'", ("n", promoted)));

        var no = await PostAsync(ConfirmedResolve, token, ResolveConfirmed(rejected, category, "reject"));
        Assert.Equal("rejected", no["status"]!.GetValue<string>());
        Assert.Null(no["merchantId"]);
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE body ->> 'canonical' = @n", ("n", rejected)));

        foreach (var norm in new[] { short_, blocked })
        {
            using var response = await fixture.SendAsync(HttpMethod.Post, ConfirmedResolve, token, ResolveConfirmed(norm, category, "promote"));
            await TestProblems.AssertAsync(response, HttpStatusCode.Conflict, "ADMIN_CONFLICT");
            Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = @n AND status <> 'collecting'", ("n", norm)));
        }

        using var missing = await fixture.SendAsync(HttpMethod.Post, ConfirmedResolve, token, ResolveConfirmed(Unique("t354 none"), category, "promote"));
        await TestProblems.AssertAsync(missing, HttpStatusCode.NotFound, "NOT_FOUND");
        Assert.Equal(1L, await AuditAsync(operatorId, "llmcat_confirmed_promote"));
        Assert.Equal(1L, await AuditAsync(operatorId, "llmcat_confirmed_reject"));
    }

    // ---- AC4 -------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task ARepeatedOrUnknownCorrectionResolveIs409Or404AndAuditsNothingMore()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var norm = Unique("t354 twice");
        await SeedCorrectionsAsync(norm, "dining", "education", 1);

        await PostAsync(CorrectionsResolve, token, Resolve(norm, "dining", "education", "reject"));
        using var again = await fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, token, Resolve(norm, "dining", "education", "prompt_issue"));
        using var unknown = await fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, token, Resolve(Unique("t354 nope"), "dining", "education", "reject"));

        await TestProblems.AssertAsync(again, HttpStatusCode.Conflict, "ADMIN_CONFLICT");
        await TestProblems.AssertAsync(unknown, HttpStatusCode.NotFound, "NOT_FOUND");
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id", ("id", operatorId)));
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @n AND status = 'rejected'", ("n", norm)));
    }

    [Fact]
    public async Task TwoOperatorsResolvingOneGroupAtOnceGetOneWinnerAndOneAuditRow()
    {
        var (first, firstToken) = await fixture.NewOperatorAsync(Editor);
        var (second, secondToken) = await fixture.NewOperatorAsync(Editor);
        var norm = Unique("t354 race");
        await SeedCorrectionsAsync(norm, "dining", "education", 3);

        var results = await Task.WhenAll(
            fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, firstToken, Resolve(norm, "dining", "education", "reject")),
            fixture.SendAsync(HttpMethod.Post, CorrectionsResolve, secondToken, Resolve(norm, "dining", "education", "prompt_issue")));
        try
        {
            Assert.Equal([HttpStatusCode.OK, HttpStatusCode.Conflict], results.Select(r => r.StatusCode).Order());
            var audits = await CountAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id IN (@a, @b)", ("a", first), ("b", second));
            Assert.Equal(1L, audits);
            Assert.Equal(1L, await CountAsync("SELECT count(DISTINCT status) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @n", ("n", norm)));
        }
        finally
        {
            foreach (var result in results)
            {
                result.Dispose();
            }
        }
    }

    [Fact]
    public async Task EveryOperationNeedsTheCatalogEditorRole()
    {
        var bodies = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [CorrectionsQuery] = "{}",
            [ConfirmedQuery] = "{}",
            [CorrectionsResolve] = Resolve("zawya coffee", "dining", "education", "reject"),
            [ConfirmedResolve] = ResolveConfirmed("zawya coffee", "dining", "reject"),
        };
        foreach (var role in new[] { OperatorRoles.FlagsAdmin, OperatorRoles.PricesAdmin, OperatorRoles.SupportViewer, OperatorRoles.SupportAgent, OperatorRoles.SupportLead })
        {
            var (operatorId, token) = await fixture.NewOperatorAsync(role);
            foreach (var (path, body) in bodies)
            {
                using var response = await fixture.SendAsync(HttpMethod.Post, path, token, body);
                Assert.True(response.StatusCode == HttpStatusCode.Forbidden, $"{role} {path}: {(int)response.StatusCode}");
            }

            Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id", ("id", operatorId)));
        }

        foreach (var (path, body) in bodies)
        {
            using var anonymous = await fixture.SendAsync(HttpMethod.Post, path, null, body);
            Assert.Equal(HttpStatusCode.Unauthorized, anonymous.StatusCode);
        }
    }
}
