using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Api.Idempotency;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// FU-011 and T-132 AC "R4-2" for <c>getEntitlement</c> and the entitlement part of <c>verifyPurchase</c>: the real API over
/// PostgreSQL with the real seat service and a fake KMS; responses are checked against the OpenAPI operation, are signed, echo the
/// time nonce, and carry a token whose <c>sub</c> is the calling install.
/// </summary>
public class EntitlementLiveContractTests(VerifyContractFixture fixture) : IClassFixture<VerifyContractFixture>
{
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Get => Spec.Operations().Single(o => o.Id == "getEntitlement");

    [Fact]
    public async Task GetEntitlementConformsIsSignedAndEchoesTheNonceForAnInstallWithoutGold()
    {
        var (installId, token) = await NewInstallAsync();
        var nonce = Base64Url(RandomNumberGenerator.GetBytes(16));

        using var response = await GetAsync(token, nonce);

        var body = await AssertDeclared(response, HttpStatusCode.OK, Json);
        Assert.True(response.Headers.Contains("Zaghlol-Signature"));
        Assert.Equal(nonce, body!["timeNonce"]!.GetValue<string>());
        Assert.Null(body["supportNotice"]);
        Assert.Null(body["rotateInstallToken"]);
        var claims = Claims(body["entitlement"]!["token"]!.GetValue<string>());
        Assert.Equal(installId, claims["sub"]!.GetValue<string>());
        Assert.Equal("none", claims["status"]!.GetValue<string>());
        Assert.Equal("zaghlol", claims["iss"]!.GetValue<string>());
        Assert.Equal(1, claims["v"]!.GetValue<int>());
    }

    [Fact]
    public async Task AVerifiedPlayPurchaseBindsTheSeatAndBothVerifyAndGetEntitlementCarryAnActiveInstallBoundToken()
    {
        var (installId, token) = await NewInstallAsync();
        var purchaseToken = "tok." + Guid.NewGuid().ToString("N");
        fixture.Play.Get(PlayWireMock.SubscriptionPath(purchaseToken), 200, PlayWireMock.SubscriptionBody(StoreBindingRef.Compute(InstallId.Parse(installId)), acknowledged: true));
        var nonce = Base64Url(RandomNumberGenerator.GetBytes(16));

        using var verify = await VerifyAsync(token, purchaseToken, nonce);
        var verified = await AssertVerifyDeclared(verify);

        Assert.Equal("active", verified!["status"]!.GetValue<string>());
        Assert.Equal(nonce, verified["timeNonce"]!.GetValue<string>());
        Assert.True(verify.Headers.Contains("Zaghlol-Signature"));
        Assert.False(verified["seatHeldElsewhere"]!.GetValue<bool>());
        Assert.False(verified["accountRequired"]!.GetValue<bool>());
        var fromVerify = Claims(verified["entitlement"]!["token"]!.GetValue<string>());
        Assert.Equal(installId, fromVerify["sub"]!.GetValue<string>());
        Assert.Equal("active", fromVerify["status"]!.GetValue<string>());
        Assert.Equal("yearly", fromVerify["plan"]!.GetValue<string>());
        Assert.InRange(fromVerify["exp"]!.GetValue<long>() - fromVerify["iat"]!.GetValue<long>(), 1, 3 * 86_400);
        Assert.Equal(4 * 86_400, fromVerify["graceUntil"]!.GetValue<long>() - fromVerify["exp"]!.GetValue<long>());

        using var get = await GetAsync(token, null);
        var fromGet = Claims((await AssertDeclared(get, HttpStatusCode.OK, Json))!["entitlement"]!["token"]!.GetValue<string>());
        Assert.Equal("active", fromGet["status"]!.GetValue<string>());
        Assert.Equal(installId, fromGet["sub"]!.GetValue<string>());

        // Another install never gets Gold from it.
        var (otherId, otherToken) = await NewInstallAsync();
        using var other = await GetAsync(otherToken, null);
        var otherClaims = Claims((await AssertDeclared(other, HttpStatusCode.OK, Json))!["entitlement"]!["token"]!.GetValue<string>());
        Assert.Equal(otherId, otherClaims["sub"]!.GetValue<string>());
        Assert.Equal("none", otherClaims["status"]!.GetValue<string>());
    }

    [Fact]
    public async Task GetEntitlementErrorsAreDeclaredProblems()
    {
        var (_, token) = await NewInstallAsync();

        using var anonymous = await GetAsync(null, null);
        using var badNonce = await GetAsync(token, "short");

        Assert.Equal("INSTALL_TOKEN_INVALID", (await AssertDeclared(anonymous, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(badNonce, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
    }

    private static JsonNode Claims(string jws)
    {
        var parts = jws.Split('.');
        Assert.Equal(3, parts.Length);
        var header = JsonNode.Parse(System.Buffers.Text.Base64Url.DecodeFromChars(parts[0]))!;
        Assert.Equal("ES256", header["alg"]!.GetValue<string>());
        Assert.Matches("^e[0-9]{4}[a-z]$", header["kid"]!.GetValue<string>());
        return JsonNode.Parse(System.Buffers.Text.Base64Url.DecodeFromChars(parts[1]))!;
    }

    private static string Base64Url(byte[] bytes) => System.Buffers.Text.Base64Url.EncodeToString(bytes);

    private static string NewKey()
    {
        const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        return string.Concat(RandomNumberGenerator.GetBytes(26).Select(b => Alphabet[b % 32]));
    }

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, HttpStatusCode status, string mediaType) =>
        await AssertAgainstAsync(Get, response, status, mediaType);

    private static async Task<JsonNode?> AssertVerifyDeclared(HttpResponseMessage response) =>
        await AssertAgainstAsync(Spec.Operations().Single(o => o.Id == "verifyPurchase"), response, HttpStatusCode.OK, Json);

    private static async Task<JsonNode?> AssertAgainstAsync(SpecOperation operation, HttpResponseMessage response, HttpStatusCode status, string mediaType)
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

    private async Task<HttpResponseMessage> GetAsync(string? token, string? nonce)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/entitlement");
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (nonce is not null)
        {
            request.Headers.TryAddWithoutValidation("Zaghlol-Time-Nonce", nonce);
        }

        request.Headers.Add("Zaghlol-App", "android/1.0.0 (1)");
        return await fixture.Client.SendAsync(request);
    }

    private async Task<HttpResponseMessage> VerifyAsync(string token, string purchaseToken, string? nonce)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/purchases/verify");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        request.Headers.Add(IdempotencyKeys.HeaderName, NewKey());
        if (nonce is not null)
        {
            request.Headers.Add("Zaghlol-Time-Nonce", nonce);
        }

        request.Headers.Add("Zaghlol-App", "android/1.0.0 (1)");
        request.Content = new StringContent(
            "{\"platform\":\"android\",\"productId\":\"" + PlayWireMock.Yearly + "\",\"purchaseToken\":\"" + purchaseToken + "\"}",
            Encoding.UTF8,
            Json);
        return await fixture.Client.SendAsync(request);
    }
}
