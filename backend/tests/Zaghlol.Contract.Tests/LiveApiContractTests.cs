using System.Globalization;
using System.Net;
using System.Text.Json.Nodes;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Calls the real, in-process API and checks the actual responses against <c>zaghlol-v1.yaml</c>.
/// Endpoints that are not implemented yet are covered here as they land.
/// </summary>
public class LiveApiContractTests(ContractApiFixture fixture) : IClassFixture<ContractApiFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static JsonNode ProblemSchema => JsonNode.Parse("{\"$ref\":\"#/components/schemas/Problem\"}")!;

    [Fact]
    public async Task HealthResponseConformsToTheSpec()
    {
        var operation = Spec.Operations().Single(o => o.Id == "getHealth");
        var schema = Spec.ResponseSchema(operation, "200", "application/json");
        Assert.NotNull(schema);

        using var response = await fixture.Client.GetAsync(new Uri("/v1/health", UriKind.Relative));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        Assert.True(response.Headers.CacheControl?.NoStore);
        var body = JsonNode.Parse(await response.Content.ReadAsStringAsync());
        Assert.Null(Spec.Validate(schema, body));
        Assert.EndsWith("Z", body!["serverTime"]!.GetValue<string>(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task UnknownRouteReturnsSpecProblem()
    {
        using var response = await fixture.Client.GetAsync(new Uri("/v1/does-not-exist", UriKind.Relative));

        await AssertProblem(response, HttpStatusCode.NotFound, "NOT_FOUND");
    }

    [Fact]
    public async Task WrongMethodReturnsSpecProblem()
    {
        using var response = await fixture.Client.PostAsync(new Uri("/v1/health", UriKind.Relative), content: null);

        await AssertProblem(response, HttpStatusCode.MethodNotAllowed, "METHOD_NOT_ALLOWED");
    }

    [Fact]
    public async Task UnhandledExceptionReturnsSpecProblemWithoutLeakingDetails()
    {
        using var response = await fixture.Client.GetAsync(new Uri("/test/boom", UriKind.Relative));

        var body = await AssertProblem(response, HttpStatusCode.InternalServerError, "INTERNAL");
        Assert.DoesNotContain(FaultEndpointsStartupFilter.Secret, body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task BadRequestReturnsSpecProblemWithoutEchoingMessage()
    {
        using var response = await fixture.Client.GetAsync(new Uri("/test/bad-request", UriKind.Relative));

        var body = await AssertProblem(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.DoesNotContain(FaultEndpointsStartupFilter.Secret, body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EveryStatusUsedByLiveProblemsIsDeclaredByTheSpec()
    {
        // The generic statuses (404, 405, 500) are documented in the info description and as shared responses.
        var declared = Spec.Operations()
            .SelectMany(o => o.Body["responses"]!.AsObject().Select(r => r.Key))
            .ToHashSet(StringComparer.Ordinal);

        using var missing = await fixture.Client.GetAsync(new Uri("/v1/does-not-exist", UriKind.Relative));
        using var boom = await fixture.Client.GetAsync(new Uri("/test/boom", UriKind.Relative));
        using var bad = await fixture.Client.GetAsync(new Uri("/test/bad-request", UriKind.Relative));

        Assert.Contains(((int)missing.StatusCode).ToString(CultureInfo.InvariantCulture), declared);
        Assert.Contains(((int)boom.StatusCode).ToString(CultureInfo.InvariantCulture), declared);
        Assert.Contains(((int)bad.StatusCode).ToString(CultureInfo.InvariantCulture), declared);
    }

    private static async Task<string> AssertProblem(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var text = await response.Content.ReadAsStringAsync();
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(ProblemSchema, body));
        Assert.Equal(code, body!["code"]!.GetValue<string>());
        Assert.Equal((int)status, body["status"]!.GetValue<int>());
        return text;
    }
}
