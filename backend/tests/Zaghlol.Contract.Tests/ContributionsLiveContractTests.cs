using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// FU-011: live response-vs-spec tests for <c>adminListContributions</c>, <c>adminPromoteContribution</c> and
/// <c>adminRejectContribution</c>, including <c>400 UNKNOWN_FIELD</c>. Every status answered is declared by the operation and every
/// body validates against its schema.
/// </summary>
public class ContributionsLiveContractTests(FlagsContractFixture fixture) : IClassFixture<FlagsContractFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private const string Editor = "catalog_editor";
    private const string Base = "/admin/v1/contributions";

    private static SpecOperation List => Operation("adminListContributions");

    private static SpecOperation Promote => Operation("adminPromoteContribution");

    private static SpecOperation Reject => Operation("adminRejectContribution");

    private static SpecOperation Operation(string id) => Spec.Operations().Single(o => o.Id == id);

    private static string Unique(string prefix) =>
        prefix + " " + string.Concat(Guid.NewGuid().ToByteArray().Take(8).Select(b => (char)('a' + (b % 26))));

    private static string Key(string norm, string institution = "nbe") => $"{{\"merchantNorm\":\"{norm}\",\"institutionCode\":\"{institution}\"}}";

    private async Task SeedAsync(string norm, string status, int installs = 5) =>
        await ZaghlolTestDatabase.ExecuteAsync(
            fixture.Migrator,
            string.Create(
                CultureInfo.InvariantCulture,
                $"INSERT INTO zaghlol.contribution_aggregates (merchant_norm, institution_code, distinct_installs, top_category_code, category_votes, status) VALUES ('{norm}', 'nbe', {installs}, 'dining', '{{\"dining\": {installs}}}', '{status}')"));

    private async Task EnsureCategoryAsync(string token)
    {
        using var response = await Send(
            HttpMethod.Put,
            "/admin/v1/catalog/draft/categories/dining",
            token,
            "{\"nameAr\":\"x\",\"nameEn\":\"Dining\",\"icon\":\"fork\",\"color\":\"#112233\",\"bucket\":\"wants\",\"sort\":1}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task List200ConformsToContributionQueueAndShowsNoCollectingAggregate()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        var ready = Unique("contract ready");
        var collecting = Unique("contract collecting");
        await SeedAsync(ready, "ready_for_review", 6);
        await SeedAsync(collecting, "collecting", 4);

        using var response = await Send(HttpMethod.Get, Base, token);

        var body = await AssertDeclared(List, response, HttpStatusCode.OK, "application/json");
        var items = body!["items"]!.AsArray();
        Assert.Contains(items, i => i!["merchantNorm"]!.GetValue<string>() == ready && i["distinctInstalls"]!.GetValue<int>() == 6);
        Assert.DoesNotContain(items, i => i!["merchantNorm"]!.GetValue<string>() == collecting);
        Assert.DoesNotContain("collecting", body.ToJsonString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ListWithEachDeclaredStatusConforms()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        foreach (var status in new[] { "ready_for_review", "promoted", "rejected" })
        {
            using var response = await Send(HttpMethod.Get, Base + "?status=" + status, token);
            await AssertDeclared(List, response, HttpStatusCode.OK, "application/json");
        }

        using var collecting = await Send(HttpMethod.Get, Base + "?status=collecting", token);
        await AssertDeclared(List, collecting, HttpStatusCode.BadRequest, "application/problem+json");
    }

    [Fact]
    public async Task Promote200ConformsToContributionDecisionAndTheSpecExampleShapeIsAccepted()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        await EnsureCategoryAsync(token);
        var norm = Unique("contract promote");
        await SeedAsync(norm, "ready_for_review");
        var request = Key(norm);
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Promote)!, JsonNode.Parse(request)));
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Promote)!, JsonNode.Parse("{\"merchantNorm\":\"koshary el tahrir\",\"institutionCode\":\"nbe\",\"merchantId\":812}")));

        using var response = await Send(HttpMethod.Post, Base + ":promote", token, request);

        var body = await AssertDeclared(Promote, response, HttpStatusCode.OK, "application/json");
        Assert.Equal("promoted", body!["status"]!.GetValue<string>());
        Assert.Equal(norm, body["merchantNorm"]!.GetValue<string>());
        Assert.True(body["merchantId"]!.GetValue<int>() >= 1);
    }

    [Fact]
    public async Task Reject200ConformsToContributionDecision()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        var norm = Unique("contract reject");
        await SeedAsync(norm, "ready_for_review");
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Reject)!, JsonNode.Parse(Key(norm))));

        using var response = await Send(HttpMethod.Post, Base + ":reject", token, Key(norm));

        var body = await AssertDeclared(Reject, response, HttpStatusCode.OK, "application/json");
        Assert.Equal("rejected", body!["status"]!.GetValue<string>());
    }

    [Fact]
    public async Task NotFoundAndAdminConflictAreDeclaredAndConformOnBothDecisions()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        await EnsureCategoryAsync(token);
        var collecting = Unique("contract hidden");
        await SeedAsync(collecting, "collecting", 3);
        var decided = Unique("contract decided");
        await SeedAsync(decided, "ready_for_review");
        using var first = await Send(HttpMethod.Post, Base + ":promote", token, Key(decided));
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        foreach (var (operation, path) in new[] { (Promote, Base + ":promote"), (Reject, Base + ":reject") })
        {
            using var absent = await Send(HttpMethod.Post, path, token, Key(Unique("contract absent")));
            using var hidden = await Send(HttpMethod.Post, path, token, Key(collecting));
            using var again = await Send(HttpMethod.Post, path, token, Key(decided));

            Assert.Equal("NOT_FOUND", (await AssertDeclared(operation, absent, HttpStatusCode.NotFound, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("NOT_FOUND", (await AssertDeclared(operation, hidden, HttpStatusCode.NotFound, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("ADMIN_CONFLICT", (await AssertDeclared(operation, again, HttpStatusCode.Conflict, "application/problem+json"))!["code"]!.GetValue<string>());
        }
    }

    [Fact]
    public async Task UnknownMembersAreTheDeclared400UnknownFieldOnBothDecisions()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        const string Request = "{\"merchantNorm\":\"koshary\",\"institutionCode\":\"nbe\",\"note\":\"x\"}";
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Promote)!, JsonNode.Parse(Request)));
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Reject)!, JsonNode.Parse(Request)));

        foreach (var (operation, path) in new[] { (Promote, Base + ":promote"), (Reject, Base + ":reject") })
        {
            using var response = await Send(HttpMethod.Post, path, token, Request);

            var body = await AssertDeclared(operation, response, HttpStatusCode.BadRequest, "application/problem+json");
            Assert.Equal("UNKNOWN_FIELD", body!["code"]!.GetValue<string>());
        }
    }

    [Fact]
    public async Task ValidationMediaAndAuthErrorsAreDeclaredOnBothDecisionsAndTheList()
    {
        var token = await fixture.OperatorTokenAsync(Editor);
        var wrongRole = await fixture.OperatorTokenAsync("prices_admin");

        foreach (var (operation, path) in new[] { (Promote, Base + ":promote"), (Reject, Base + ":reject") })
        {
            using var invalid = await Send(HttpMethod.Post, path, token, Key("koshary", "NBE"));
            using var wrongType = await Send(HttpMethod.Post, path, token, "{}", "text/plain");
            using var tooLarge = await Send(HttpMethod.Post, path, token, "{\"merchantNorm\":\"" + new string('a', 70_000) + "\"}");
            using var anonymous = await Send(HttpMethod.Post, path, null, "{}");
            using var forbidden = await Send(HttpMethod.Post, path, wrongRole, "{}");

            Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(operation, invalid, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
            await AssertDeclared(operation, wrongType, HttpStatusCode.UnsupportedMediaType, "application/problem+json");
            await AssertDeclared(operation, tooLarge, HttpStatusCode.RequestEntityTooLarge, "application/problem+json");
            Assert.Equal("UNAUTHORIZED", (await AssertDeclared(operation, anonymous, HttpStatusCode.Unauthorized, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("FORBIDDEN", (await AssertDeclared(operation, forbidden, HttpStatusCode.Forbidden, "application/problem+json"))!["code"]!.GetValue<string>());
        }

        using var listAnonymous = await Send(HttpMethod.Get, Base, null, null);
        using var listForbidden = await Send(HttpMethod.Get, Base, wrongRole, null);
        await AssertDeclared(List, listAnonymous, HttpStatusCode.Unauthorized, "application/problem+json");
        await AssertDeclared(List, listForbidden, HttpStatusCode.Forbidden, "application/problem+json");
    }

    [Fact]
    public void TheServerSideLimitsAreTheSpecsLimits()
    {
        var key = Spec.Schemas["ContributionKey"]!["properties"]!["merchantNorm"]!;
        Assert.Equal((long)Zaghlol.Application.Contributions.ContributionRules.MinKeyLength, key["minLength"]!.GetValue<long>());
        Assert.Equal((long)Zaghlol.Application.Contributions.ContributionRules.MaxKeyLength, key["maxLength"]!.GetValue<long>());
        Assert.False(Spec.Schemas["ContributionKey"]!["additionalProperties"]!.GetValue<bool>());
        Assert.False(Spec.Schemas["ContributionPromoteRequest"]!["additionalProperties"]!.GetValue<bool>());
        var statuses = Spec.Schemas["ContributionStatus"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToList();
        Assert.Equal(new[] { "ready_for_review", "promoted", "rejected" }, statuses);
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
