using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Api.Auth;
using Zaghlol.Application.Flags;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>Maps test bearer tokens to operators (the OIDC validator is T-136's).</summary>
internal sealed class ContractOperatorValidator : IOperatorTokenValidator
{
    private readonly ConcurrentDictionary<string, OperatorIdentity> tokens = new(StringComparer.Ordinal);

    public string Issue(Guid operatorId, params string[] roles)
    {
        var token = "op-" + Guid.NewGuid().ToString("N");
        tokens[token] = new OperatorIdentity(operatorId, roles);
        return token;
    }

    public ValueTask<OperatorIdentity?> ValidateAsync(string bearerToken, CancellationToken cancellationToken) =>
        ValueTask.FromResult(tokens.GetValueOrDefault(bearerToken));
}

internal sealed class SilentOpsNotifier : IOpsNotifier
{
    public Task FlagChangedAsync(FlagState state, CancellationToken cancellationToken) => Task.CompletedTask;
}

/// <summary>The real API over a migrated PostgreSQL 17, with a fake operator validator, for the admin flag contract tests.</summary>
public sealed class FlagsContractFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private readonly ContractOperatorValidator operators = new();
    private ZaghlolTestDatabase? database;
    private WebApplicationFactory<Program>? factory;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", database.Api);
            builder.UseSetting("ConnectionStrings:Admin", database.Admin);
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.RemoveAll<IOperatorTokenValidator>();
                services.AddSingleton<IOperatorTokenValidator>(operators);
                services.RemoveAll<IOpsNotifier>();
                services.AddSingleton<IOpsNotifier>(new SilentOpsNotifier());
            });
        });
        Client = factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        Client?.Dispose();
        if (factory is not null)
        {
            await factory.DisposeAsync();
        }

        if (database is not null)
        {
            await database.DisposeAsync();
        }

        kms.Dispose();
    }

    /// <summary>A token for a new operator (with its <c>operators</c> row, which the audit log references).</summary>
    internal async Task<string> OperatorTokenAsync(params string[] roles)
    {
        var id = Guid.NewGuid();
        await ZaghlolTestDatabase.ExecuteAsync(
            database!.Migrator,
            string.Create(
                CultureInfo.InvariantCulture,
                $"INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ('{id}', 'sub-{id}', 'Contract test', ARRAY['{string.Join("','", roles)}'])"));
        return operators.Issue(id, roles);
    }
}

/// <summary>
/// FU-011: live response-vs-spec tests for <c>adminGetFlag</c> and <c>adminPutFlag</c>, including
/// <c>400 UNKNOWN_FIELD</c> for an unknown member of <c>rules</c>. Every status answered is declared by the operation, and
/// every body validates against its schema.
/// </summary>
public class FlagsLiveContractTests(FlagsContractFixture fixture) : IClassFixture<FlagsContractFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Get => Spec.Operations().Single(o => o.Id == "adminGetFlag");

    private static SpecOperation Put => Spec.Operations().Single(o => o.Id == "adminPutFlag");

    [Fact]
    public async Task Get200ConformsToFlagState()
    {
        var token = await fixture.OperatorTokenAsync("flags_admin");

        using var response = await Send(HttpMethod.Get, "/admin/v1/flags/roi_named_products", token);

        var body = await AssertDeclared(response, Get, HttpStatusCode.OK, "application/json");
        Assert.False(body!["value"]!.GetValue<bool>());
        Assert.Equal(0, body["version"]!.GetValue<int>());
    }

    [Fact]
    public async Task Put200WithRulesConformsToFlagStateAndRoundTripsThroughGet()
    {
        var token = await fixture.OperatorTokenAsync("flags_admin");
        const string Request = "{\"value\":true,\"rules\":{\"platforms\":[\"android\"],\"minAppVersion\":\"1.4.0\",\"rolloutPercent\":10}}";
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Put)!, JsonNode.Parse(Request)));

        using var put = await Send(HttpMethod.Put, "/admin/v1/flags/zakah", token, Request);
        using var get = await Send(HttpMethod.Get, "/admin/v1/flags/zakah", token);

        var putBody = await AssertDeclared(put, Put, HttpStatusCode.OK, "application/json");
        var getBody = await AssertDeclared(get, Get, HttpStatusCode.OK, "application/json");
        Assert.Equal(putBody!["rules"]!.ToJsonString(), getBody!["rules"]!.ToJsonString());
        Assert.Equal(10, getBody["rules"]!["rolloutPercent"]!.GetValue<int>());
        Assert.Equal("1.4.0", getBody["rules"]!["minAppVersion"]!.GetValue<string>());
    }

    [Fact]
    public async Task PutUnknownMemberInRulesIsTheDeclared400UnknownField()
    {
        var token = await fixture.OperatorTokenAsync("flags_admin");
        const string Request = "{\"value\":true,\"rules\":{\"rolloutPercent\":10,\"audience\":\"beta\"}}";
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Put)!, JsonNode.Parse(Request)));

        using var response = await Send(HttpMethod.Put, "/admin/v1/flags/smart_roi", token, Request);

        var body = await AssertDeclared(response, Put, HttpStatusCode.BadRequest, "application/problem+json");
        Assert.Equal("UNKNOWN_FIELD", body!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task PutAndGetValidationAndLookupErrorsAreDeclared()
    {
        var token = await fixture.OperatorTokenAsync("flags_admin");

        using var badRollout = await Send(HttpMethod.Put, "/admin/v1/flags/smart_roi", token, "{\"value\":true,\"rules\":{\"rolloutPercent\":101}}");
        using var badKeyGet = await Send(HttpMethod.Get, "/admin/v1/flags/Bad-Key", token);
        using var unknownGet = await Send(HttpMethod.Get, "/admin/v1/flags/not_a_flag", token);
        using var unknownPut = await Send(HttpMethod.Put, "/admin/v1/flags/not_a_flag", token, "{\"value\":true}");
        using var wrongType = await Send(HttpMethod.Put, "/admin/v1/flags/smart_roi", token, "{\"value\":true}", "text/plain");
        using var tooLarge = await Send(HttpMethod.Put, "/admin/v1/flags/smart_roi", token, "{\"value\":true,\"x\":\"" + new string('a', 70_000) + "\"}");

        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(badRollout, Put, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(badKeyGet, Get, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
        Assert.Equal("NOT_FOUND", (await AssertDeclared(unknownGet, Get, HttpStatusCode.NotFound, "application/problem+json"))!["code"]!.GetValue<string>());
        Assert.Equal("NOT_FOUND", (await AssertDeclared(unknownPut, Put, HttpStatusCode.NotFound, "application/problem+json"))!["code"]!.GetValue<string>());
        await AssertDeclared(wrongType, Put, HttpStatusCode.UnsupportedMediaType, "application/problem+json");
        await AssertDeclared(tooLarge, Put, HttpStatusCode.RequestEntityTooLarge, "application/problem+json");
    }

    [Fact]
    public async Task AuthenticationAndAuthorizationErrorsAreDeclaredForBothOperations()
    {
        var wrongRole = await fixture.OperatorTokenAsync("catalog_editor");

        foreach (var operation in new[] { Get, Put })
        {
            var method = operation.Method == "get" ? HttpMethod.Get : HttpMethod.Put;
            var body = method == HttpMethod.Put ? "{\"value\":true}" : null;
            using var anonymous = await Send(method, "/admin/v1/flags/zakah", token: null, body);
            using var forbidden = await Send(method, "/admin/v1/flags/zakah", wrongRole, body);

            Assert.Equal("UNAUTHORIZED", (await AssertDeclared(anonymous, operation, HttpStatusCode.Unauthorized, "application/problem+json"))!["code"]!.GetValue<string>());
            Assert.Equal("FORBIDDEN", (await AssertDeclared(forbidden, operation, HttpStatusCode.Forbidden, "application/problem+json"))!["code"]!.GetValue<string>());
        }
    }

    [Fact]
    public void TheServerSidePatternsAreTheSpecsPatterns()
    {
        Assert.Equal(FlagKeys.Pattern, Spec.Schemas["FlagKey"]!["pattern"]!.GetValue<string>());
        Assert.Equal(
            FlagRulesValidator.MinAppVersionPattern,
            Spec.Schemas["FlagRules"]!["properties"]!["minAppVersion"]!["pattern"]!.GetValue<string>());
        Assert.Equal(
            FlagRulesValidator.Platforms,
            Spec.Schemas["Platform"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToList());
        var rollout = Spec.Schemas["FlagRules"]!["properties"]!["rolloutPercent"]!;
        Assert.Equal(0, rollout["minimum"]!.GetValue<int>());
        Assert.Equal(100, rollout["maximum"]!.GetValue<int>());
    }

    private static bool Declared(SpecOperation operation, string status) =>
        operation.Body["responses"]!.AsObject().ContainsKey(status);

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, SpecOperation operation, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);

        Assert.True(Declared(operation, code), $"{operation.Label} does not declare {code}");
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
