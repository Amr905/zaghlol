using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Application.Prices;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// FU-011: live response-vs-spec tests for <c>adminOverridePrice</c>, including <c>400 UNKNOWN_FIELD</c>. Every status answered
/// is declared by the operation, and every body validates against its schema.
/// </summary>
public class PricesLiveContractTests(FlagsContractFixture fixture) : IClassFixture<FlagsContractFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Override => Spec.Operations().Single(o => o.Id == "adminOverridePrice");

    private const string Path = "/admin/v1/prices/override";

    [Fact]
    public async Task Put200ConformsToPriceOverrideResponseAndTheSpecExampleIsAccepted()
    {
        var token = await fixture.OperatorTokenAsync("prices_admin");
        const string Request = "{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"4217.50\",\"reason\":\"Feed outage, using bullion dealer quote\"}";
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Override)!, JsonNode.Parse(Request)));

        using var response = await Send(HttpMethod.Put, token, Request);

        var body = await AssertDeclared(response, HttpStatusCode.OK, "application/json");
        Assert.Equal("4217.50", body!["price"]!.GetValue<string>());
        Assert.Equal("XAU21_G", body["symbol"]!.GetValue<string>());
    }

    [Fact]
    public async Task Put200WithAnExplicitExpiryConforms()
    {
        var token = await fixture.OperatorTokenAsync("prices_admin");
        var expires = DateTimeOffset.UtcNow.AddDays(3).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", CultureInfo.InvariantCulture);
        var request = $"{{\"symbol\":\"XAU18_G\",\"currency\":\"USD\",\"price\":\"70\",\"reason\":\"Manual quote\",\"expiresAt\":\"{expires}\"}}";
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Override)!, JsonNode.Parse(request)));

        using var response = await Send(HttpMethod.Put, token, request);

        var body = await AssertDeclared(response, HttpStatusCode.OK, "application/json");
        Assert.Equal("70.00", body!["price"]!.GetValue<string>());
    }

    [Fact]
    public async Task PutUnknownMemberIsTheDeclared400UnknownField()
    {
        var token = await fixture.OperatorTokenAsync("prices_admin");
        const string Request = "{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"10\",\"reason\":\"A reason\",\"note\":\"x\"}";
        Assert.NotNull(Spec.Validate(OpenApiSpec.RequestSchema(Override)!, JsonNode.Parse(Request)));

        using var response = await Send(HttpMethod.Put, token, Request);

        var body = await AssertDeclared(response, HttpStatusCode.BadRequest, "application/problem+json");
        Assert.Equal("UNKNOWN_FIELD", body!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task PutExpiryBeyondSevenDaysIsTheDeclared400ValidationFailedAlthoughTheSchemaAllowsIt()
    {
        var token = await fixture.OperatorTokenAsync("prices_admin");
        var expires = DateTimeOffset.UtcNow.AddDays(8).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", CultureInfo.InvariantCulture);
        var request = $"{{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"10\",\"reason\":\"A reason\",\"expiresAt\":\"{expires}\"}}";
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Override)!, JsonNode.Parse(request)));

        using var response = await Send(HttpMethod.Put, token, request);

        var body = await AssertDeclared(response, HttpStatusCode.BadRequest, "application/problem+json");
        Assert.Equal("VALIDATION_FAILED", body!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task PutValidationAndMediaErrorsAndAuthErrorsAreDeclared()
    {
        var token = await fixture.OperatorTokenAsync("prices_admin");
        var wrongRole = await fixture.OperatorTokenAsync("flags_admin");

        using var zero = await Send(HttpMethod.Put, token, "{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"0\",\"reason\":\"A reason\"}");
        using var numberPrice = await Send(HttpMethod.Put, token, "{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":10,\"reason\":\"A reason\"}");
        using var wrongType = await Send(HttpMethod.Put, token, "{}", "text/plain");
        using var tooLarge = await Send(HttpMethod.Put, token, "{\"reason\":\"" + new string('a', 70_000) + "\"}");
        using var anonymous = await Send(HttpMethod.Put, null, "{}");
        using var forbidden = await Send(HttpMethod.Put, wrongRole, "{}");

        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(zero, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(numberPrice, HttpStatusCode.BadRequest, "application/problem+json"))!["code"]!.GetValue<string>());
        await AssertDeclared(wrongType, HttpStatusCode.UnsupportedMediaType, "application/problem+json");
        await AssertDeclared(tooLarge, HttpStatusCode.RequestEntityTooLarge, "application/problem+json");
        Assert.Equal("UNAUTHORIZED", (await AssertDeclared(anonymous, HttpStatusCode.Unauthorized, "application/problem+json"))!["code"]!.GetValue<string>());
        Assert.Equal("FORBIDDEN", (await AssertDeclared(forbidden, HttpStatusCode.Forbidden, "application/problem+json"))!["code"]!.GetValue<string>());
    }

    [Fact]
    public void TheServerSideLimitsAreTheSpecsLimits()
    {
        var request = Spec.Schemas["PriceOverrideRequest"]!["properties"]!;
        Assert.Equal(PriceOverrideService.ReasonMin, request["reason"]!["minLength"]!.GetValue<int>());
        Assert.Equal(PriceOverrideService.ReasonMax, request["reason"]!["maxLength"]!.GetValue<int>());
        Assert.False(Spec.Schemas["PriceOverrideRequest"]!["additionalProperties"]!.GetValue<bool>());

        // Every symbol and currency the service accepts is also valid by the spec's patterns.
        var symbolPattern = new System.Text.RegularExpressions.Regex(request["symbol"]!["pattern"]!.GetValue<string>());
        var currencyPattern = new System.Text.RegularExpressions.Regex(Spec.Schemas["CurrencyCode"]!["pattern"]!.GetValue<string>());
        Assert.All(PriceSymbols.Gold, s => Assert.Matches(symbolPattern, s));
        Assert.All(PriceSymbols.GoldCurrencies, c => Assert.Matches(currencyPattern, c));
    }

    private static bool Declared(string status) => Override.Body["responses"]!.AsObject().ContainsKey(status);

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);

        Assert.True(Declared(code), $"{Override.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(Override, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private async Task<HttpResponseMessage> Send(HttpMethod method, string? token, string body, string mediaType = "application/json")
    {
        using var request = new HttpRequestMessage(method, Path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return await fixture.Client.SendAsync(request);
    }
}
