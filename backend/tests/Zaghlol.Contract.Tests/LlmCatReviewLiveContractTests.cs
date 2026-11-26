using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-354: live response-vs-spec tests for the four <c>/admin/v1/llm-cat</c> operations: every status answered is declared and every body
/// validates against its schema; the request schemas are closed and carry the server's limits.
/// </summary>
public class LlmCatReviewLiveContractTests(FlagsContractFixture fixture) : IClassFixture<FlagsContractFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private const string Editor = "catalog_editor";

    private static SpecOperation Operation(string id) => Spec.Operations().Single(o => o.Id == id);

    private static string Unique(string prefix) =>
        prefix + " " + string.Concat(Guid.NewGuid().ToByteArray().Take(8).Select(b => (char)('a' + (b % 26))));

    private static Task SeedAsync(FlagsContractFixture f, string table, string norm, string category, int installs) =>
        ZaghlolTestDatabase.ExecuteAsync(
            f.Migrator,
            string.Concat(Enumerable.Range(0, installs).Select(_ => table == "corrections"
                ? $"INSERT INTO zaghlol.llm_cat_corrections (id, merchant_norm, ai_category, user_category, source, install_hash, created_at) VALUES (gen_random_uuid(), '{norm}', 'dining', '{category}', 'llm', decode(md5(random()::text) || md5(random()::text), 'hex'), date_trunc('day', now()));"
                : $"INSERT INTO zaghlol.llm_cat_confirmations (id, merchant_norm, category_code, source, install_hash, created_at) VALUES (gen_random_uuid(), '{norm}', '{category}', 'llm', decode(md5(random()::text) || md5(random()::text), 'hex'), date_trunc('day', now()));")));

    [Fact]
    public async Task BothQueriesAnswerTheirPageSchemaAndTheSpecExamplesAreValidRequests()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        var corrections = Operation("adminQueryLlmCatCorrections");
        var confirmed = Operation("adminQueryLlmCatConfirmed");
        var norm = Unique("contract llm");
        await SeedAsync(fixture, "corrections", norm, "education", 2);
        await SeedAsync(fixture, "confirmations", norm + " c", "dining", 3);
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(corrections)!, JsonNode.Parse("{\"status\":\"open\",\"limit\":50}")));
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(confirmed)!, JsonNode.Parse("{\"limit\":50}")));

        using var first = await Send(HttpMethod.Post, "/admin/v1/llm-cat/corrections/query", token, "{\"limit\":100}");
        using var second = await Send(HttpMethod.Post, "/admin/v1/llm-cat/confirmed/query", token, "{\"limit\":100}");

        var page = await AssertDeclared(corrections, first, HttpStatusCode.OK, "application/json");
        await AssertDeclared(confirmed, second, HttpStatusCode.OK, "application/json");
        Assert.Contains(page!["items"]!.AsArray(), i => i!["merchantNorm"]!.GetValue<string>() == norm && i["votes"]!.GetValue<int>() == 2);
    }

    [Fact]
    public async Task BothResolvesAnswerTheirResultSchemaAndTheDeclaredErrors()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        var wrongRole = await fixture.OperatorTokenAsync("prices_admin");
        var resolveCorrection = Operation("adminResolveLlmCatCorrection");
        var resolveConfirmed = Operation("adminResolveLlmCatConfirmed");
        var norm = Unique("contract llm r");
        await SeedAsync(fixture, "corrections", norm, "custom", 1);
        await SeedAsync(fixture, "confirmations", norm, "dining", 3);
        var correction = $"{{\"merchantNorm\":\"{norm}\",\"aiCategory\":\"dining\",\"userCategory\":\"custom\",\"action\":\"prompt_issue\"}}";
        var confirm = $"{{\"merchantNorm\":\"{norm}\",\"category\":\"dining\",\"action\":\"reject\"}}";
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(resolveCorrection)!, JsonNode.Parse(correction)));
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(resolveConfirmed)!, JsonNode.Parse(confirm)));

        foreach (var (operation, path, body) in new[]
        {
            (resolveCorrection, "/admin/v1/llm-cat/corrections/resolve", correction),
            (resolveConfirmed, "/admin/v1/llm-cat/confirmed/resolve", confirm),
        })
        {
            using var ok = await Send(HttpMethod.Post, path, token, body);
            using var again = await Send(HttpMethod.Post, path, token, body);
            using var absent = await Send(HttpMethod.Post, path, token, body.Replace(norm, Unique("contract llm none"), StringComparison.Ordinal));
            using var invalid = await Send(HttpMethod.Post, path, token, body.Replace("\"action\":\"", "\"action\":\"x", StringComparison.Ordinal));
            using var unknown = await Send(HttpMethod.Post, path, token, body.TrimEnd('}') + ",\"extra\":1}");
            using var wrongType = await Send(HttpMethod.Post, path, token, "{}", "text/plain");
            using var anonymous = await Send(HttpMethod.Post, path, null, "{}");
            using var forbidden = await Send(HttpMethod.Post, path, wrongRole, "{}");

            await AssertDeclared(operation, ok, HttpStatusCode.OK, "application/json");
            Assert.Equal("ADMIN_CONFLICT", (await AssertDeclared(operation, again, HttpStatusCode.Conflict, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("NOT_FOUND", (await AssertDeclared(operation, absent, HttpStatusCode.NotFound, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(operation, invalid, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("UNKNOWN_FIELD", (await AssertDeclared(operation, unknown, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
            await AssertDeclared(operation, wrongType, HttpStatusCode.UnsupportedMediaType, "application/problem+json");
            await AssertDeclared(operation, anonymous, HttpStatusCode.Unauthorized, "application/problem+json");
            await AssertDeclared(operation, forbidden, HttpStatusCode.Forbidden, "application/problem+json");
        }
    }

    [Fact]
    public void TheRequestSchemasAreClosedAndNoSchemaCarriesAHashOrInstallMember()
    {
        foreach (var name in new[] { "LlmCatCorrectionsQueryRequest", "LlmCatConfirmedQueryRequest", "LlmCatCorrectionResolveRequest", "LlmCatConfirmedResolveRequest" })
        {
            Assert.False(Spec.Schemas[name]!["additionalProperties"]!.GetValue<bool>(), name);
        }

        foreach (var name in new[] { "LlmCatCorrectionGroup", "LlmCatConfirmedGroup", "LlmCatCorrectionPage", "LlmCatConfirmedPage", "LlmCatResolveResult" })
        {
            var members = Spec.Schemas[name]!["properties"]!.AsObject().Select(p => p.Key).ToList();
            Assert.DoesNotContain(members, m => m.Contains("hash", StringComparison.OrdinalIgnoreCase) || m.Contains("install", StringComparison.OrdinalIgnoreCase));
        }

        Assert.Equal(64L, Spec.Schemas["LlmCatCorrectionResolveRequest"]!["properties"]!["merchantNorm"]!["maxLength"]!.GetValue<long>());
    }

    private static async Task<JsonNode?> AssertDeclared(SpecOperation operation, HttpResponseMessage response, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);

        Assert.True(operation.Body["responses"]!.AsObject().ContainsKey(code), $"{operation.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(operation, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private async Task<HttpResponseMessage> Send(HttpMethod method, string path, string? token, string? body = null, string mediaType = "application/json")
    {
        using var request = new HttpRequestMessage(method, path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        }

        return await fixture.Client.SendAsync(request);
    }
}
