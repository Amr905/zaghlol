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
        Client = factory.CreateDefaultClient(new AppHeaderHandler());
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
        Assert.Equal(InstallEndpoints.AppVersionMaxLength, (int)appVersion["maxLength"]!.GetValue<long>());
        Assert.Equal(
            InstallEndpoints.Platforms,
            Spec.Schemas["Platform"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToList());
        var key = Spec.Root["components"]!["parameters"]!["IdempotencyKey"]!["schema"]!["pattern"]!.GetValue<string>();
        Assert.Equal(IdempotencyKeys.Pattern, key);
    }

    /// <summary>The operations whose spec marks <c>Zaghlol-App</c> as required (the <c>ZaghlolApp</c> parameter reference).</summary>
    public static TheoryData<string> AppHeaderOperationIds()
    {
        var data = new TheoryData<string>();
        foreach (var operation in Spec.Operations().Where(o => o.Path.StartsWith("/v1/", StringComparison.Ordinal) && RequiresAppHeader(o)))
        {
            data.Add(operation.Id);
        }

        return data;
    }

    /// <summary>
    /// BUG-004: every <c>/v1</c> operation that declares the required <c>Zaghlol-App</c> parameter answers <c>400 VALIDATION_FAILED</c>
    /// when it is absent or malformed (for the install-scoped ones, after authentication succeeds).
    /// </summary>
    [Theory]
    [MemberData(nameof(AppHeaderOperationIds))]
    public async Task EveryOperationThatRequiresTheAppHeaderRejectsAMissingOrMalformedOne(string operationId)
    {
        var operation = Spec.Operations().Single(o => o.Id == operationId);
        Assert.DoesNotContain('{', operation.Path); // path parameters would need a fixture of their own
        Assert.True(Declared(operation, "400"), $"{operation.Label} does not declare 400");

        var installId = NewInstallId();
        using var created = await Post(Body(installId), NewKey());
        var token = JsonNode.Parse(await created.Content.ReadAsStringAsync())!["installToken"]!.GetValue<string>();

        foreach (var app in new string?[] { null, "android 1.0", "android/1.0.0" })
        {
            using var request = new HttpRequestMessage(new HttpMethod(operation.Method.ToUpperInvariant()), operation.Path);
            request.Options.Set(AppHeaderHandler.Omit, true);
            if (app is not null)
            {
                request.Headers.TryAddWithoutValidation("Zaghlol-App", app);
            }

            request.Headers.Add(IdempotencyKeys.HeaderName, NewKey());
            if (operationId != "registerInstall")
            {
                request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
                request.Headers.Add("Zaghlol-Install", installId);
            }

            if (operation.Body["requestBody"] is not null)
            {
                // A schema-valid body, so the only thing wrong with the call is the header (F1 of batch 43).
                Assert.True(ValidBodies.TryGetValue(operationId, out var valid), $"{operation.Label} takes a body but the test has no valid one for it");
                request.Content = new StringContent(valid!, Encoding.UTF8, "application/json");
            }

            using var response = await fixture.Client.SendAsync(request);

            var body = await AssertDeclared(response, operation, HttpStatusCode.BadRequest, "application/problem+json");
            Assert.Equal("VALIDATION_FAILED", body!["code"]!.GetValue<string>());
        }
    }

    /// <summary>Minimal schema-valid request bodies for the operations that take one and require the app header.</summary>
    private static readonly Dictionary<string, string> ValidBodies = new()
    {
        ["registerInstall"] = Body("00000000-0000-4000-8000-000000000001"),
        ["sync"] = """{"catalogVersion":0,"flagsVersion":0}""",
        ["verifyPurchase"] = """{"platform":"android","productId":"zaghlol_gold_yearly","purchaseToken":"opaque-token-from-play"}""",
        ["restorePurchases"] = """{"platform":"android","purchases":[{"productId":"zaghlol_gold_lifetime","purchaseToken":"opaque-token-from-play"}],"attestation":{"type":"play_integrity","token":"AAAAAAAAAAAAAAAAAAAA"}}""",
        ["signIn"] = """{"provider":"google","idToken":"aaaa.bbbb.cccc","nonce":"AAAAAAAAAAAAAAAAAAAAAA"}""",
    };

    private static bool RequiresAppHeader(SpecOperation operation) =>
        operation.Body["parameters"] is JsonArray parameters
        && parameters.Any(p => p is JsonObject o && o["$ref"]?.GetValue<string>() == "#/components/parameters/ZaghlolApp");

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
