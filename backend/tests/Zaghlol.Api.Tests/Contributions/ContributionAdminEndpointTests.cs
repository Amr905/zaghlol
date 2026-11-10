using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Flags;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Contributions;

/// <summary>T-129: the review queue and the two body-keyed decisions through the real pipeline.</summary>
[Collection(ApiHostGroup.Name)]
public partial class ContributionAdminEndpointTests(AdminFlagFixture fixture) : IClassFixture<AdminFlagFixture>
{
    private const string Editor = OperatorRoles.CatalogEditor;
    private const string List = "/admin/v1/contributions";
    private const string Promote = "/admin/v1/contributions:promote";
    private const string Reject = "/admin/v1/contributions:reject";

    private static string Unique(string prefix) =>
        prefix + " " + string.Concat(Guid.NewGuid().ToByteArray().Take(8).Select(b => (char)('a' + (b % 26))));

    private static string Key(string norm, string institution = "nbe") => $"{{\"merchantNorm\":\"{norm}\",\"institutionCode\":\"{institution}\"}}";

    private async Task SeedAggregateAsync(string norm, string status, int installs = 5, string category = "dining", string institution = "nbe") =>
        await ZaghlolTestDatabase.ExecuteAsync(
            fixture.Database.Migrator,
            $"INSERT INTO zaghlol.contribution_aggregates (merchant_norm, institution_code, distinct_installs, top_category_code, category_votes, status) VALUES ('{norm}', '{institution}', {installs}, '{category}', '{{\"{category}\": {installs}}}', '{status}')");

    private async Task EnsureCategoryAsync(string token, string code)
    {
        using var response = await fixture.SendAsync(
            HttpMethod.Put,
            "/admin/v1/catalog/draft/categories/" + code,
            token,
            "{\"nameAr\":\"x\",\"nameEn\":\"Dining\",\"icon\":\"fork\",\"color\":\"#112233\",\"bucket\":\"wants\",\"sort\":1}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private async Task<string> AggregateStatusAsync(string norm) =>
        (string)(await Scalar("SELECT status FROM zaghlol.contribution_aggregates WHERE merchant_norm = '" + norm + "'"))!;

    private async Task<long> AuditCountAsync(Guid operatorId, string action)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id AND action = @action", connection);
        command.Parameters.AddWithValue("id", operatorId);
        command.Parameters.AddWithValue("action", action);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    private async Task<object?> Scalar(string sql)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        return await command.ExecuteScalarAsync();
    }

    private static async Task<string> CodeAsync(HttpResponseMessage response)
    {
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return json.RootElement.GetProperty("code").GetString()!;
    }

    [GeneratedRegex("\"correlationId\":\"[^\"]*\"", RegexOptions.CultureInvariant)]
    private static partial Regex CorrelationId();

    /// <summary>The wire bytes of a problem, with the per-request correlation id (the only member that differs) blanked.</summary>
    private static async Task<(int Status, string Type, string Body)> ProblemBytesAsync(HttpResponseMessage response) =>
        ((int)response.StatusCode, response.Content.Headers.ContentType!.ToString(), CorrelationId().Replace(await response.Content.ReadAsStringAsync(), "\"correlationId\":\"-\""));

    // ---- GET -----------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task TheQueueListsReadyAggregatesByDefaultAndNeverACollectingOne()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        var ready = Unique("queue ready");
        var collecting = Unique("queue collecting");
        var promoted = Unique("queue promoted");
        await SeedAggregateAsync(ready, "ready_for_review", 7);
        await SeedAggregateAsync(collecting, "collecting", 4);
        await SeedAggregateAsync(promoted, "promoted");

        using var response = await fixture.SendAsync(HttpMethod.Get, List, token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        var text = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(text);
        var items = json.RootElement.GetProperty("items").EnumerateArray().ToList();
        var item = Assert.Single(items, i => i.GetProperty("merchantNorm").GetString() == ready);
        Assert.Equal("nbe", item.GetProperty("institutionCode").GetString());
        Assert.Equal("dining", item.GetProperty("categoryCode").GetString());
        Assert.Equal(7, item.GetProperty("distinctInstalls").GetInt32());
        Assert.Equal("ready_for_review", item.GetProperty("status").GetString());
        Assert.DoesNotContain(collecting, text, StringComparison.Ordinal);
        Assert.DoesNotContain(promoted, text, StringComparison.Ordinal);
        Assert.DoesNotContain("collecting", text, StringComparison.Ordinal);
    }

    [Fact]
    public async Task TheStatusFilterSelectsDecidedAggregatesAndRefusesCollectingAndJunk()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        var promoted = Unique("filter promoted");
        await SeedAggregateAsync(promoted, "promoted");

        using var done = await fixture.SendAsync(HttpMethod.Get, List + "?status=promoted", token);
        using var collecting = await fixture.SendAsync(HttpMethod.Get, List + "?status=collecting", token);
        using var junk = await fixture.SendAsync(HttpMethod.Get, List + "?status=nope", token);
        using var twice = await fixture.SendAsync(HttpMethod.Get, List + "?status=promoted&status=rejected", token);
        using var other = await fixture.SendAsync(HttpMethod.Get, List + "?limit=5", token);

        Assert.Equal(HttpStatusCode.OK, done.StatusCode);
        Assert.Contains(promoted, await done.Content.ReadAsStringAsync(), StringComparison.Ordinal);
        foreach (var refused in new[] { collecting, junk, twice, other })
        {
            Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);
            Assert.Equal("VALIDATION_FAILED", await CodeAsync(refused));
        }
    }

    [Fact]
    public async Task OnlyCatalogEditorsAuthenticatedOperatorsMayUseIt()
    {
        var (_, wrongRole) = await fixture.NewOperatorAsync(OperatorRoles.PricesAdmin);

        using var anonymous = await fixture.SendAsync(HttpMethod.Get, List, null);
        using var forbidden = await fixture.SendAsync(HttpMethod.Get, List, wrongRole);
        using var forbiddenPromote = await fixture.SendAsync(HttpMethod.Post, Promote, wrongRole, Key("x y"));
        using var forbiddenReject = await fixture.SendAsync(HttpMethod.Post, Reject, wrongRole, Key("x y"));

        Assert.Equal(HttpStatusCode.Unauthorized, anonymous.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, forbiddenPromote.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, forbiddenReject.StatusCode);
    }

    // ---- promote and reject -----------------------------------------------------------------------------------------

    [Fact]
    public async Task PromoteIs200WithTheNewDraftMerchantAndTheAggregateBecomesPromoted()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        await EnsureCategoryAsync(token, "dining");
        var norm = Unique("promote me");
        await SeedAggregateAsync(norm, "ready_for_review");

        using var response = await fixture.SendAsync(HttpMethod.Post, Promote, token, Key(norm));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(norm, json.RootElement.GetProperty("merchantNorm").GetString());
        Assert.Equal("nbe", json.RootElement.GetProperty("institutionCode").GetString());
        Assert.Equal("promoted", json.RootElement.GetProperty("status").GetString());
        var merchantId = json.RootElement.GetProperty("merchantId").GetInt32();
        Assert.True(merchantId >= 1);
        Assert.Equal("promoted", await AggregateStatusAsync(norm));
        Assert.Equal(
            norm,
            await Scalar($"SELECT body ->> 'canonical' FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND entry_key = '{merchantId}'"));
        Assert.Equal(1, await AuditCountAsync(operatorId, "contribution_promote"));
    }

    [Fact]
    public async Task PromoteWithAMerchantIdAttachesTheAliasAndAnUnknownMerchantIsConflict()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        await EnsureCategoryAsync(token, "dining");
        using var created = await fixture.SendAsync(
            HttpMethod.Post,
            "/admin/v1/catalog/draft/merchants",
            token,
            $"{{\"canonical\":\"{Unique("target")}\",\"nameAr\":\"m\",\"category\":\"dining\"}}");
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        using var createdJson = JsonDocument.Parse(await created.Content.ReadAsStringAsync());
        var merchantId = createdJson.RootElement.GetProperty("id").GetInt32();
        var norm = Unique("attach me");
        var other = Unique("attach other");
        await SeedAggregateAsync(norm, "ready_for_review");
        await SeedAggregateAsync(other, "ready_for_review");

        using var ok = await fixture.SendAsync(
            HttpMethod.Post, Promote, token, $"{{\"merchantNorm\":\"{norm}\",\"institutionCode\":\"nbe\",\"merchantId\":{merchantId}}}");
        using var missing = await fixture.SendAsync(
            HttpMethod.Post, Promote, token, $"{{\"merchantNorm\":\"{other}\",\"institutionCode\":\"nbe\",\"merchantId\":2000000000}}");

        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        using var json = JsonDocument.Parse(await ok.Content.ReadAsStringAsync());
        Assert.Equal(merchantId, json.RootElement.GetProperty("merchantId").GetInt32());
        Assert.Equal(HttpStatusCode.Conflict, missing.StatusCode);
        Assert.Equal("ADMIN_CONFLICT", await CodeAsync(missing));
        Assert.Equal("ready_for_review", await AggregateStatusAsync(other));
    }

    [Fact]
    public async Task RejectIs200WithoutAMerchantAndMarksTheAggregateRejected()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var norm = Unique("reject me");
        await SeedAggregateAsync(norm, "ready_for_review");

        using var response = await fixture.SendAsync(HttpMethod.Post, Reject, token, Key(norm));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("rejected", json.RootElement.GetProperty("status").GetString());
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("merchantId").ValueKind);
        Assert.Equal("rejected", await AggregateStatusAsync(norm));
        Assert.Equal(1, await AuditCountAsync(operatorId, "contribution_reject"));
    }

    [Fact]
    public async Task DecidingAnAlreadyDecidedAggregateIsAdminConflict()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        await EnsureCategoryAsync(token, "dining");
        var norm = Unique("decided twice");
        await SeedAggregateAsync(norm, "ready_for_review");
        using var first = await fixture.SendAsync(HttpMethod.Post, Promote, token, Key(norm));
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        using var promoteAgain = await fixture.SendAsync(HttpMethod.Post, Promote, token, Key(norm));
        using var rejectAfter = await fixture.SendAsync(HttpMethod.Post, Reject, token, Key(norm));

        Assert.Equal(HttpStatusCode.Conflict, promoteAgain.StatusCode);
        Assert.Equal("ADMIN_CONFLICT", await CodeAsync(promoteAgain));
        Assert.Equal(HttpStatusCode.Conflict, rejectAfter.StatusCode);
        Assert.Equal("ADMIN_CONFLICT", await CodeAsync(rejectAfter));
    }

    [Theory]
    [InlineData(Promote)]
    [InlineData(Reject)]
    public async Task ACollectingKeyAndAnAbsentKeyGetByteIdenticalNotFoundAnswers(string path)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(Editor);
        var collecting = Unique("secret collecting");
        await SeedAggregateAsync(collecting, "collecting", 4);

        using var forCollecting = await fixture.SendAsync(HttpMethod.Post, path, token, Key(collecting));
        using var forAbsent = await fixture.SendAsync(HttpMethod.Post, path, token, Key(Unique("secret absent")));

        Assert.Equal(HttpStatusCode.NotFound, forCollecting.StatusCode);
        Assert.Equal("NOT_FOUND", await CodeAsync(forCollecting));
        Assert.Equal(await ProblemBytesAsync(forAbsent), await ProblemBytesAsync(forCollecting));
        Assert.Equal(forAbsent.Headers.CacheControl?.ToString(), forCollecting.Headers.CacheControl?.ToString());
        Assert.Equal(forAbsent.Content.Headers.ContentLength, forCollecting.Content.Headers.ContentLength);
        Assert.Equal("collecting", await AggregateStatusAsync(collecting));
        Assert.Equal(0, await AuditCountAsync(operatorId, "contribution_promote") + await AuditCountAsync(operatorId, "contribution_reject"));
    }

    [Theory]
    [InlineData(Promote)]
    [InlineData(Reject)]
    public async Task ABodyWithAnUnknownMemberIsUnknownFieldAndMalformedKeysAreValidationFailed(string path)
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);

        using var unknown = await fixture.SendAsync(HttpMethod.Post, path, token, "{\"merchantNorm\":\"koshary\",\"institutionCode\":\"nbe\",\"installCount\":5}");
        using var missing = await fixture.SendAsync(HttpMethod.Post, path, token, "{\"merchantNorm\":\"koshary\"}");
        using var badInstitution = await fixture.SendAsync(HttpMethod.Post, path, token, Key("koshary", "NBE"));
        using var shortNorm = await fixture.SendAsync(HttpMethod.Post, path, token, Key("k"));
        using var longNorm = await fixture.SendAsync(HttpMethod.Post, path, token, Key(new string('k', 81)));
        using var numberNorm = await fixture.SendAsync(HttpMethod.Post, path, token, "{\"merchantNorm\":5,\"institutionCode\":\"nbe\"}");
        using var wrongType = await fixture.SendAsync(HttpMethod.Post, path, token, "{}", "text/plain");

        Assert.Equal(HttpStatusCode.BadRequest, unknown.StatusCode);
        Assert.Equal("UNKNOWN_FIELD", await CodeAsync(unknown));
        foreach (var refused in new[] { missing, badInstitution, shortNorm, longNorm, numberNorm })
        {
            Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);
            Assert.Equal("VALIDATION_FAILED", await CodeAsync(refused));
        }

        Assert.Equal(HttpStatusCode.UnsupportedMediaType, wrongType.StatusCode);
    }

    [Fact]
    public async Task PromoteRefusesAnInvalidMerchantIdOrCategoryCode()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);

        using var zero = await fixture.SendAsync(HttpMethod.Post, Promote, token, "{\"merchantNorm\":\"koshary\",\"institutionCode\":\"nbe\",\"merchantId\":0}");
        using var text = await fixture.SendAsync(HttpMethod.Post, Promote, token, "{\"merchantNorm\":\"koshary\",\"institutionCode\":\"nbe\",\"merchantId\":\"7\"}");
        using var badCategory = await fixture.SendAsync(HttpMethod.Post, Promote, token, "{\"merchantNorm\":\"koshary\",\"institutionCode\":\"nbe\",\"categoryCode\":\"Not A Code\"}");

        foreach (var refused in new[] { zero, text, badCategory })
        {
            Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);
            Assert.Equal("VALIDATION_FAILED", await CodeAsync(refused));
        }
    }

    [Fact]
    public async Task ANotFoundAnswerNeverEchoesTheKey()
    {
        var (_, token) = await fixture.NewOperatorAsync(Editor);
        var norm = Unique("never logged");

        using var response = await fixture.SendAsync(HttpMethod.Post, Promote, token, Key(norm));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.DoesNotContain(norm, await response.Content.ReadAsStringAsync(), StringComparison.Ordinal);
    }
}
