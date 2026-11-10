using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Idempotency;
using Zaghlol.Application.Sync;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// FU-011 for <c>sync</c>: the real API over PostgreSQL, every answer checked against the OpenAPI operation (full, delta,
/// full-mode and throttle 200s; 400 <c>UNKNOWN_FIELD</c> at every level; caps; auth and media errors), and the BR-SYNC-03
/// member allow-list of the request types. One class, so its tests run one after another over the fixture's database.
/// </summary>
public class SyncLiveContractTests(CatalogContractFixture fixture) : IClassFixture<CatalogContractFixture>
{
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    /// <summary>BR-SYNC-03: the only members the app may send in a sync body (beyond headers and the install token).</summary>
    private static readonly string[] SyncRequestMembers =
        ["bankRequests", "catalogVersion", "contributions", "entitlementIssuedAt", "flagsVersion", "pricesAsOf", "registryVersion"];

    private static readonly string[] ContributionMembers = ["categoryCode", "institutionCode", "merchantNorm"];

    private static readonly string[] BankRequestMembers = ["channel", "country", "institutionName"];

    private static readonly string[] ThrottleMembers = ["nextSyncNotBefore", "serverTime", "timeNonce"];

    private string latestCategory = "dining";

    private static SpecOperation Sync => Spec.Operations().Single(o => o.Id == "sync");

    [Fact]
    public async Task FullModeThenThrottleConformAndTheThrottleHasExactlyThreeMembers()
    {
        await PublishAsync();
        var token = await NewInstallAsync();
        var nonce = Nonce();

        using var full = await SendAsync(token, Body(0), nonce);
        using var throttled = await SendAsync(token, Body(0), nonce);

        var fullBody = await AssertDeclared(full, HttpStatusCode.OK, Json);
        Assert.Equal("full", fullBody!["catalog"]!["mode"]!.GetValue<string>());
        Assert.StartsWith(CatalogContractFixture.BaseUrl, fullBody["catalog"]!["fullUrl"]!.GetValue<string>(), StringComparison.Ordinal);
        Assert.Equal(nonce, fullBody["timeNonce"]!.GetValue<string>());
        Assert.True(full.Headers.Contains("Zaghlol-Signature"));

        var throttleBody = await AssertDeclared(throttled, HttpStatusCode.OK, Json);
        Assert.Equal(ThrottleMembers, throttleBody!.AsObject().Select(p => p.Key).Order(StringComparer.Ordinal));
        Assert.Equal(nonce, throttleBody["timeNonce"]!.GetValue<string>());
        Assert.True(throttled.Headers.Contains("Zaghlol-Signature"));
    }

    [Fact]
    public async Task ADeltaWithOpsAndAcceptedCountsConforms()
    {
        await PublishAsync();
        var latest = await PublishAsync();
        var token = await NewInstallAsync();
        var body = Body(
            latest - 1,
            ",\"contributions\":[{\"merchantNorm\":\"koshary el tahrir\",\"institutionCode\":\"nbe\",\"categoryCode\":\"" + latestCategory + "\"}]"
            + ",\"bankRequests\":[{\"institutionName\":\"Banque du Caire\",\"country\":\"EG\",\"channel\":\"sms\"}]"
            + ",\"pricesAsOf\":\"2026-11-02T09:00:00Z\",\"entitlementIssuedAt\":\"2026-10-30T10:00:00Z\",\"registryVersion\":12");
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Sync)!, JsonNode.Parse(body)));

        using var response = await SendAsync(token, body, null);

        var answer = await AssertDeclared(response, HttpStatusCode.OK, Json);
        Assert.Equal("delta", answer!["catalog"]!["mode"]!.GetValue<string>());
        Assert.NotEmpty(answer["catalog"]!["ops"]!.AsArray());
        Assert.Equal(1, answer["accepted"]!["contributions"]!.GetValue<int>());
        Assert.Equal(1, answer["accepted"]!["bankRequests"]!.GetValue<int>());
        Assert.Null(answer["timeNonce"]);
        Assert.True(answer.AsObject().ContainsKey("timeNonce"));
    }

    [Theory]
    [InlineData(",\"messages\":[\"x\"]")]
    [InlineData(",\"contributions\":[{\"merchantNorm\":\"koshary\",\"institutionCode\":\"nbe\",\"categoryCode\":\"dining\",\"amount\":\"120.50\"}]")]
    [InlineData(",\"bankRequests\":[{\"institutionName\":\"Some Bank\",\"country\":\"EG\",\"channel\":\"sms\",\"sms\":\"x\"}]")]
    public async Task AnExtraMemberAtAnyLevelIsTheDeclared400UnknownField(string extra)
    {
        var token = await NewInstallAsync();
        var body = Body(0, extra);
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Sync)!, JsonNode.Parse(body)));

        using var response = await SendAsync(token, body, null);

        var problem = await AssertDeclared(response, HttpStatusCode.BadRequest, Problem);
        Assert.Equal("UNKNOWN_FIELD", problem!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task CapsValidationAuthAndMediaErrorsAreDeclared()
    {
        var token = await NewInstallAsync();
        var contributions = string.Join(',', Enumerable.Range(0, 51).Select(i => "{\"merchantNorm\":\"m" + i + "\",\"institutionCode\":\"nbe\",\"categoryCode\":\"dining\"}"));
        var banks = string.Join(',', Enumerable.Range(0, 11).Select(i => "{\"institutionName\":\"b" + i + "\",\"country\":\"EG\",\"channel\":\"sms\"}"));

        using var tooManyContributions = await SendAsync(token, Body(0, ",\"contributions\":[" + contributions + "]"), null);
        using var tooManyBanks = await SendAsync(token, Body(0, ",\"bankRequests\":[" + banks + "]"), null);
        using var noApp = await SendAsync(token, Body(0), null, app: null);
        using var badNonce = await SendAsync(token, Body(0), "nope");
        using var anonymous = await SendAsync(null, Body(0), null);
        using var wrongType = await SendAsync(token, Body(0), null, mediaType: "text/plain");
        using var tooLarge = await SendAsync(token, "{\"catalogVersion\":0,\"flagsVersion\":0,\"x\":\"" + new string('a', 70_000) + "\"}", null);

        foreach (var response in new[] { tooManyContributions, tooManyBanks, noApp, badNonce })
        {
            var problem = await AssertDeclared(response, HttpStatusCode.BadRequest, Problem);
            Assert.Equal("VALIDATION_FAILED", problem!["code"]!.GetValue<string>());
        }

        Assert.Equal("INSTALL_TOKEN_INVALID", (await AssertDeclared(anonymous, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
        await AssertDeclared(wrongType, HttpStatusCode.UnsupportedMediaType, Problem);
        await AssertDeclared(tooLarge, HttpStatusCode.RequestEntityTooLarge, Problem);
    }

    [Fact]
    public void TheRequestTypesCarryExactlyTheBrSync03Members()
    {
        Assert.Equal(SyncRequestMembers, JsonMembers(typeof(SyncRequest)));
        Assert.Equal(ContributionMembers, JsonMembers(typeof(SyncContributionInput)));
        Assert.Equal(BankRequestMembers, JsonMembers(typeof(SyncBankRequestInput)));

        Assert.Equal(SyncRequestMembers, SpecMembers("SyncRequest"));
        Assert.Equal(ContributionMembers, SpecMembers("ContributionInput"));
        Assert.Equal(BankRequestMembers, SpecMembers("BankRequestInput"));
        foreach (var schema in new[] { "SyncRequest", "ContributionInput", "BankRequestInput" })
        {
            Assert.False(Spec.Schemas[schema]!["additionalProperties"]!.GetValue<bool>());
        }

        Assert.Equal((long)SyncRequest.MaxContributions, Spec.Schemas["SyncRequest"]!["properties"]!["contributions"]!["maxItems"]!.GetValue<long>());
        Assert.Equal((long)SyncRequest.MaxBankRequests, Spec.Schemas["SyncRequest"]!["properties"]!["bankRequests"]!["maxItems"]!.GetValue<long>());
        Assert.Equal(SyncIntake.InstitutionCodePattern, Spec.Schemas["InstitutionCode"]!["pattern"]!.GetValue<string>());
        Assert.Equal(SyncIntake.CountryPattern, Spec.Schemas["BankRequestInput"]!["properties"]!["country"]!["pattern"]!.GetValue<string>());
        Assert.Equal(
            SyncIntake.Channels,
            Spec.Schemas["BankRequestInput"]!["properties"]!["channel"]!["enum"]!.AsArray().Select(v => v!.GetValue<string>()));
    }

    [Fact]
    public void SyncIsNotAThirdPartyBodyAndHasNoIdempotencyKey()
    {
        Assert.Null(Sync.Body["x-third-party-body"]);
        var parameters = Sync.Body["parameters"]!.AsArray().Select(p => p!["$ref"]?.GetValue<string>()).ToList();
        Assert.DoesNotContain("#/components/parameters/IdempotencyKey", parameters);
    }

    private static string[] JsonMembers(Type type) =>
        [.. type.GetProperties(BindingFlags.Instance | BindingFlags.Public).Select(p => JsonNamingPolicy.CamelCase.ConvertName(p.Name)).Order(StringComparer.Ordinal)];

    private static string[] SpecMembers(string schema) =>
        [.. Spec.Schemas[schema]!["properties"]!.AsObject().Select(p => p.Key).Order(StringComparer.Ordinal)];

    private static string Body(int catalogVersion, string extra = "") =>
        "{\"catalogVersion\":" + catalogVersion.ToString(CultureInfo.InvariantCulture) + ",\"flagsVersion\":0" + extra + "}";

    private static string Nonce() => System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

    /// <summary>Creates a new category draft and publishes it; returns the new version.</summary>
    private async Task<int> PublishAsync()
    {
        latestCategory = "c" + Guid.NewGuid().ToString("N")[..10];
        using var put = await AdminAsync(
            HttpMethod.Put,
            "/admin/v1/catalog/draft/categories/" + latestCategory,
            "{\"nameAr\":\"اختبار\",\"nameEn\":\"Test\",\"icon\":\"tag\",\"color\":\"#0F7A55\",\"bucket\":\"wants\",\"sort\":1}");
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        using var publish = await AdminAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{}");
        Assert.Equal(HttpStatusCode.OK, publish.StatusCode);
        return JsonNode.Parse(await publish.Content.ReadAsStringAsync())!["version"]!.GetValue<int>();
    }

    private async Task<HttpResponseMessage> AdminAsync(HttpMethod method, string path, string body)
    {
        using var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CatalogTestOperatorValidator.TokenFor(CatalogContractFixture.EditorRole));
        request.Content = new StringContent(body, Encoding.UTF8, Json);
        return await fixture.Client.SendAsync(request);
    }

    private async Task<string> NewInstallAsync()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Content = new StringContent(
            "{\"installId\":\"" + Guid.NewGuid().ToString("D") + "\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}",
            Encoding.UTF8,
            Json);
        request.Headers.Add(IdempotencyKeys.HeaderName, NewKey());
        using var response = await fixture.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync())!["installToken"]!.GetValue<string>();
    }

    private static string NewKey()
    {
        const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        return string.Concat(RandomNumberGenerator.GetBytes(26).Select(b => Alphabet[b % 32]));
    }

    private async Task<HttpResponseMessage> SendAsync(string? token, string body, string? nonce, string? app = "android/1.0.0 (42)", string mediaType = Json)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/sync");
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (nonce is not null)
        {
            request.Headers.TryAddWithoutValidation("Zaghlol-Time-Nonce", nonce);
        }

        if (app is not null)
        {
            request.Headers.TryAddWithoutValidation("Zaghlol-App", app);
        }

        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return await fixture.Client.SendAsync(request);
    }

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);
        Assert.True(Sync.Body["responses"]!.AsObject().ContainsKey(code), $"{Sync.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(Sync, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }
}
