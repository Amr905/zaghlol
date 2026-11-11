using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Zaghlol.Api.Idempotency;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>The real API (<c>Program</c>, Development) over PostgreSQL 17 and a WireMock Play Developer API.</summary>
public sealed class VerifyContractFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private ZaghlolTestDatabase? database;
    private WebApplicationFactory<Program>? factory;

    public PlayWireMock Play { get; } = new();

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", database.Api);
            builder.UseSetting("ConnectionStrings:Admin", database.Admin);
            foreach (var (key, value) in kms.Settings().Concat(Play.Settings()))
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

        Play.Dispose();
        kms.Dispose();
    }
}

/// <summary>
/// FU-011 for <c>verifyPurchase</c> (Android, T-130 AC 9): every status the live endpoint answers is declared by the operation and
/// every body validates against its schema: 200 active and pending, 409, the three 422s, 502, 503 (iOS until T-131), 400
/// <c>UNKNOWN_FIELD</c>, 400 for a missing key, and 401.
/// </summary>
public class VerifyLiveContractTests(VerifyContractFixture fixture) : IClassFixture<VerifyContractFixture>
{
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Verify => Spec.Operations().Single(o => o.Id == "verifyPurchase");

    private PlayWireMock Play => fixture.Play;

    [Fact]
    public async Task ActiveAndPending200sConformToPurchaseVerifyResponse()
    {
        var (installId, token) = await NewInstallAsync();
        var active = NewPlayToken();
        var pending = NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(active), 200, PlayWireMock.SubscriptionBody(Ref(installId), acknowledged: true));
        Play.Get(PlayWireMock.ProductPath(pending), 200, PlayWireMock.ProductBody(Ref(installId), "PENDING"));
        var activeBody = Body(PlayWireMock.Yearly, active);
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Verify)!, JsonNode.Parse(activeBody)));
        var nonce = Base64Url(RandomNumberGenerator.GetBytes(16));

        using var activeResponse = await SendAsync(token, activeBody, NewKey(), nonce);
        using var pendingResponse = await SendAsync(token, Body(PlayWireMock.Lifetime, pending), NewKey());

        var a = await AssertDeclared(activeResponse, HttpStatusCode.OK, Json);
        Assert.Equal("active", a!["status"]!.GetValue<string>());
        Assert.Equal(nonce, a["timeNonce"]!.GetValue<string>());
        Assert.True(activeResponse.Headers.Contains("Zaghlol-Signature"));
        var p = await AssertDeclared(pendingResponse, HttpStatusCode.OK, Json);
        Assert.Equal("pending", p!["status"]!.GetValue<string>());
        Assert.Null(p["entitlement"]);
    }

    [Fact]
    public async Task The422sThe409AndThe502AreDeclaredProblems()
    {
        var (installId, token) = await NewInstallAsync();
        var (_, otherToken) = await NewInstallAsync();
        var rejected = NewPlayToken();
        var foreign = NewPlayToken();
        var down = NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(rejected), 410);
        Play.Get(PlayWireMock.SubscriptionPath(foreign), 200, PlayWireMock.SubscriptionBody(Ref(installId)));
        Play.Get(PlayWireMock.SubscriptionPath(down), 503);

        using var tokenInvalid = await SendAsync(token, Body(PlayWireMock.Yearly, rejected), NewKey());
        using var notOwned = await SendAsync(otherToken, Body(PlayWireMock.Yearly, foreign), NewKey());
        using var wrongApp = await SendAsync(token, Body("other.app.gold", NewPlayToken()), NewKey());
        using var unavailable = await SendAsync(token, Body(PlayWireMock.Yearly, down), NewKey());
        var key = NewKey();
        using (await SendAsync(token, Body(PlayWireMock.Yearly, rejected), key))
        {
        }

        using var reused = await SendAsync(token, Body(PlayWireMock.Monthly, rejected), key);

        Assert.Equal("PURCHASE_TOKEN_INVALID", (await AssertDeclared(tokenInvalid, HttpStatusCode.UnprocessableEntity, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("PURCHASE_NOT_OWNED", (await AssertDeclared(notOwned, HttpStatusCode.UnprocessableEntity, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("PURCHASE_WRONG_APP", (await AssertDeclared(wrongApp, HttpStatusCode.UnprocessableEntity, Problem))!["code"]!.GetValue<string>());
        var store = await AssertDeclared(unavailable, HttpStatusCode.BadGateway, Problem);
        Assert.Equal("STORE_UNAVAILABLE", store!["code"]!.GetValue<string>());
        Assert.NotNull(unavailable.Headers.RetryAfter);
        Assert.Equal("IDEMPOTENCY_KEY_REUSED", (await AssertDeclared(reused, HttpStatusCode.Conflict, Problem))!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task BadRequestsIosAndAuthAreDeclaredProblems()
    {
        var (_, token) = await NewInstallAsync();
        var unknownField = "{\"platform\":\"android\",\"productId\":\"zaghlol_gold_yearly\",\"purchaseToken\":\"t1\",\"balance\":\"1200.00\"}";
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Verify)!, JsonNode.Parse(unknownField)));

        using var unknown = await SendAsync(token, unknownField, NewKey());
        using var noKey = await SendAsync(token, Body(PlayWireMock.Yearly, NewPlayToken()), key: null);
        using var ios = await SendAsync(token, "{\"platform\":\"ios\",\"signedTransaction\":\"eyJhbGciOiJFUzI1NiJ9.e30.c2ln\"}", NewKey());
        using var anonymous = await SendAsync(null, Body(PlayWireMock.Yearly, NewPlayToken()), NewKey());

        Assert.Equal("UNKNOWN_FIELD", (await AssertDeclared(unknown, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(noKey, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("UPSTREAM_UNAVAILABLE", (await AssertDeclared(ios, HttpStatusCode.ServiceUnavailable, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("INSTALL_TOKEN_INVALID", (await AssertDeclared(anonymous, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
    }

    [Fact]
    public void TheSpecTokenLimitMatchesTheServerAndTheStoreKeyColumn()
    {
        // Lead decision 2 (2026-11-11): 512 everywhere.
        foreach (var schema in new[] { "PurchaseVerifyAndroidRequest", "AndroidPurchaseRef" })
        {
            Assert.Equal(PlayStateMapping.MaxTokenLength, Spec.Schemas[schema]!["properties"]!["purchaseToken"]!["maxLength"]!.GetValue<long>());
        }
    }

    private static string Ref(string installId) => StoreBindingRef.Compute(InstallId.Parse(installId));

    private static string Body(string productId, string token) =>
        "{\"platform\":\"android\",\"productId\":\"" + productId + "\",\"purchaseToken\":\"" + token + "\"}";

    private static string NewPlayToken() => "tok." + Guid.NewGuid().ToString("N");

    private static string NewKey()
    {
        const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        return string.Concat(RandomNumberGenerator.GetBytes(26).Select(b => Alphabet[b % 32]));
    }

    private static string Base64Url(byte[] bytes) => System.Buffers.Text.Base64Url.EncodeToString(bytes);

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);
        Assert.True(Verify.Body["responses"]!.AsObject().ContainsKey(code), $"{Verify.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(Verify, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private async Task<(string InstallId, string Token)> NewInstallAsync()
    {
        var installId = Guid.NewGuid().ToString("D");
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Headers.Add(IdempotencyKeys.HeaderName, NewKey());
        request.Content = new StringContent("{\"installId\":\"" + installId + "\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}", Encoding.UTF8, Json);
        using var response = await fixture.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (installId, JsonNode.Parse(await response.Content.ReadAsStringAsync())!["installToken"]!.GetValue<string>());
    }

    private async Task<HttpResponseMessage> SendAsync(string? token, string body, string? key, string? nonce = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/purchases/verify");
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (key is not null)
        {
            request.Headers.Add(IdempotencyKeys.HeaderName, key);
        }

        if (nonce is not null)
        {
            request.Headers.Add("Zaghlol-Time-Nonce", nonce);
        }

        request.Headers.Add("Zaghlol-App", "android/1.0.0 (1)");
        request.Content = new StringContent(body, Encoding.UTF8, Json);
        return await fixture.Client.SendAsync(request);
    }
}
