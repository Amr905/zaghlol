using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Idempotency;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>The real API (<c>Program</c>) over a migrated PostgreSQL 17, for the install endpoints' live contract tests.</summary>
public sealed class InstallsContractFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
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

            builder.ConfigureServices(kms.Use);
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
}

/// <summary>
/// FU-011: live response-vs-spec tests for <c>registerInstall</c> and <c>deleteInstall</c>, including <c>400 UNKNOWN_FIELD</c>.
/// Every status the endpoints answer is declared by the operation, and every body validates against its schema.
/// </summary>
public class InstallsLiveContractTests(InstallsContractFixture fixture) : IClassFixture<InstallsContractFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Register => Spec.Operations().Single(o => o.Id == "registerInstall");

    private static SpecOperation Delete => Spec.Operations().Single(o => o.Id == "deleteInstall");

    [Fact]
    public async Task Register201ConformsToInstallResponse()
    {
        var request = Body(NewInstallId());
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Register)!, JsonNode.Parse(request)));

        using var response = await Post(request, NewKey());

        var body = await AssertDeclared(response, Register, HttpStatusCode.Created, "application/json");
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.EndsWith("Z", body!["serverTime"]!.GetValue<string>(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RegisterUnknownFieldIsTheDeclared400()
    {
        var request = "{\"installId\":\"" + NewInstallId() + "\",\"platform\":\"android\",\"appVersion\":\"1.0.0\",\"messages\":[]}";
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Register)!, JsonNode.Parse(request)));

        using var response = await Post(request, NewKey());

        var body = await AssertDeclared(response, Register, HttpStatusCode.BadRequest, "application/problem+json");
        Assert.Equal("UNKNOWN_FIELD", body!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task RegisterValidationFailureIsTheDeclared400()
    {
        using var response = await Post(Body("not-a-uuid"), NewKey());

        var body = await AssertDeclared(response, Register, HttpStatusCode.BadRequest, "application/problem+json");
        Assert.Equal("VALIDATION_FAILED", body!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task RegisterConflictsAreTheDeclared409()
    {
        var installId = NewInstallId();
        var key = NewKey();
        using var created = await Post(Body(installId), key);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        using var exists = await Post(Body(installId), NewKey());
        using var reused = await Post(Body(installId, "1.0.1"), key);

        var existsBody = await AssertDeclared(exists, Register, HttpStatusCode.Conflict, "application/problem+json");
        var reusedBody = await AssertDeclared(reused, Register, HttpStatusCode.Conflict, "application/problem+json");
        Assert.Equal("INSTALL_EXISTS", existsBody!["code"]!.GetValue<string>());
        Assert.Equal("IDEMPOTENCY_KEY_REUSED", reusedBody!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task RegisterMediaTypeAndSizeErrorsAreTheDeclaredProblems()
    {
        using var wrongType = await Post(Body(NewInstallId()), NewKey(), "text/plain");
        using var tooLarge = await Post("{\"installId\":\"" + new string('a', 70_000) + "\"}", NewKey());

        await AssertDeclared(wrongType, Register, HttpStatusCode.UnsupportedMediaType, "application/problem+json");
        await AssertDeclared(tooLarge, Register, HttpStatusCode.RequestEntityTooLarge, "application/problem+json");
    }

    [Fact]
    public async Task Delete202HasNoBodyAndTheTokenThen401sAsDeclared()
    {
        var installId = NewInstallId();
        using var created = await Post(Body(installId), NewKey());
        var token = JsonNode.Parse(await created.Content.ReadAsStringAsync())!["installToken"]!.GetValue<string>();

        using var deleted = await SendDelete(token, installId);
        Assert.Equal(HttpStatusCode.Accepted, deleted.StatusCode);
        Assert.True(Declared(Delete, "202"));
        Assert.Empty(await deleted.Content.ReadAsByteArrayAsync());

        using var again = await SendDelete(token, installId);
        var body = await AssertDeclared(again, Delete, HttpStatusCode.Unauthorized, "application/problem+json");
        Assert.Equal("INSTALL_TOKEN_INVALID", body!["code"]!.GetValue<string>());
        Assert.Equal("Bearer", again.Headers.WwwAuthenticate.ToString());
    }

    [Fact]
    public void TheServerSidePatternsAreTheSpecsPatterns()
    {
        var request = Spec.Schemas["InstallRequest"]!["properties"]!;
        var appVersion = request["appVersion"]!;
        Assert.Equal(InstallEndpoints.AppVersionPattern, appVersion["pattern"]!.GetValue<string>());
        Assert.Equal(InstallEndpoints.AppVersionMaxLength, appVersion["maxLength"]!.GetValue<int>());
        Assert.Equal(
            InstallEndpoints.Platforms,
            Spec.Schemas["Platform"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToList());
        var key = Spec.Root["components"]!["parameters"]!["IdempotencyKey"]!["schema"]!["pattern"]!.GetValue<string>();
        Assert.Equal(IdempotencyKeys.Pattern, key);
    }

    private static bool Declared(SpecOperation operation, string status) =>
        operation.Body["responses"]!.AsObject().ContainsKey(status);

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, SpecOperation operation, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);

        // 413 and 415 are declared on the operation too (backend-api §6: on every operation that takes a body).
        Assert.True(Declared(operation, code), $"{operation.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(operation, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private static string NewInstallId() => Guid.NewGuid().ToString("D");

    private static string NewKey()
    {
        const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        return string.Concat(System.Security.Cryptography.RandomNumberGenerator.GetBytes(26).Select(b => Alphabet[b % 32]));
    }

    private static string Body(string installId, string appVersion = "1.0.0") =>
        "{\"installId\":\"" + installId + "\",\"platform\":\"android\",\"appVersion\":\"" + appVersion + "\"}";

    private async Task<HttpResponseMessage> Post(string body, string key, string mediaType = "application/json")
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Headers.Add("Zaghlol-App", "android/1.0.0 (1)");
        request.Headers.Add(IdempotencyKeys.HeaderName, key);
        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return await fixture.Client.SendAsync(request);
    }

    private async Task<HttpResponseMessage> SendDelete(string token, string installId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, "/v1/installs/me");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        request.Headers.Add("Zaghlol-App", "android/1.0.0 (1)");
        request.Headers.Add("Zaghlol-Install", installId);
        return await fixture.Client.SendAsync(request);
    }
}
