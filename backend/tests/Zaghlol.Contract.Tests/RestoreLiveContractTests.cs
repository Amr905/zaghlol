using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Api.Idempotency;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>The real API (<c>Program</c>) over PostgreSQL 17 and WireMock Play, with the Play Integrity verifier faked (T-181's fake).</summary>
public sealed class RestoreContractFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private ZaghlolTestDatabase? database;
    private WebApplicationFactory<Program>? factory;

    public PlayWireMock Play { get; } = new();

    public FakePlayIntegrityVerifier Integrity { get; } = new();

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

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.RemoveAll<IPlayIntegrityVerifier>();
                services.AddSingleton<IPlayIntegrityVerifier>(Integrity);
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

        Play.Dispose();
        kms.Dispose();
    }
}

/// <summary>
/// FU-011 for <c>restorePurchases</c> (T-185): every status the live endpoint answers here is declared by the operation and every
/// body validates against its schema: 200 (signed, echoing the time nonce), 409 <c>MOVE_COOLDOWN</c>, 400 <c>UNKNOWN_FIELD</c> and
/// <c>VALIDATION_FAILED</c>, 422 <c>DEVICE_ATTESTATION_FAILED</c>, 503, 429 and 401.
/// </summary>
public class RestoreLiveContractTests(RestoreContractFixture fixture) : IClassFixture<RestoreContractFixture>
{
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Restore => Spec.Operations().Single(o => o.Id == "restorePurchases");

    [Fact]
    public async Task A200IsSignedEchoesTheNonceAndConformsAndASecondPhoneGetsTheDeclared409()
    {
        var holder = await NewInstallAsync();
        var other = await NewInstallAsync();
        var token = NewPlayToken();
        fixture.Play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(StoreBindingRef.Compute(InstallId.Parse(holder.InstallId)), acknowledged: true));
        var body = AndroidBody(token);
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Restore)!, JsonNode.Parse(body)));
        var nonce = System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

        using var first = await SendAsync(holder.Token, body, nonce);
        using var second = await SendAsync(other.Token, body);

        var ok = await AssertDeclared(first, HttpStatusCode.OK, Json);
        Assert.Equal("active", ok!["status"]!.GetValue<string>());
        Assert.Equal(1, ok["restoredCount"]!.GetValue<int>());
        Assert.Equal(nonce, ok["timeNonce"]!.GetValue<string>());
        Assert.NotNull(ok["entitlement"]!["token"]);
        Assert.True(first.Headers.Contains("Zaghlol-Signature"));
        var cooldown = await AssertDeclared(second, HttpStatusCode.Conflict, Problem);
        Assert.Equal("MOVE_COOLDOWN", cooldown!["code"]!.GetValue<string>());
        var next = DateTimeOffset.Parse(cooldown["nextMoveAt"]!.GetValue<string>(), CultureInfo.InvariantCulture);
        Assert.Equal(TimeSpan.Zero, new TimeSpan(next.Minute, next.Second, 0));
    }

    [Fact]
    public async Task UnknownFieldValidationAndAttestationFailuresAreDeclaredProblems()
    {
        var install = await NewInstallAsync();
        var unknown = AndroidBody(NewPlayToken()).Replace("\"platform\"", "\"extra\":1,\"platform\"", StringComparison.Ordinal);
        var duplicate = AndroidBody(NewPlayToken()).Replace("\"platform\":\"android\"", "\"platform\":\"android\",\"platform\":\"android\"", StringComparison.Ordinal);

        using var unknownField = await SendAsync(install.Token, unknown);
        using var validation = await SendAsync(install.Token, duplicate);
        fixture.Integrity.Result = AttestationResult.Failed(AttestationFailure.Stale);
        using var attestation = await SendAsync(install.Token, AndroidBody(NewPlayToken()));
        fixture.Integrity.Result = AttestationResult.Unavailable;
        using var outage = await SendAsync(install.Token, AndroidBody(NewPlayToken()));
        fixture.Integrity.Result = AttestationResult.Verified(ProofLevel.Device);

        Assert.Equal("UNKNOWN_FIELD", (await AssertDeclared(unknownField, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(validation, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("DEVICE_ATTESTATION_FAILED", (await AssertDeclared(attestation, HttpStatusCode.UnprocessableEntity, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("UPSTREAM_UNAVAILABLE", (await AssertDeclared(outage, HttpStatusCode.ServiceUnavailable, Problem))!["code"]!.GetValue<string>());
        Assert.NotNull(outage.Headers.RetryAfter);
    }

    [Fact]
    public async Task TheSixthRestoreInAnHourIs429AndNoTokenIs401()
    {
        var install = await NewInstallAsync();
        var statuses = new List<HttpStatusCode>();
        HttpResponseMessage? sixth = null;
        for (var i = 0; i < 6; i++)
        {
            sixth?.Dispose();
            sixth = await SendAsync(install.Token, "{}");
            statuses.Add(sixth.StatusCode);
        }

        using (sixth)
        {
            Assert.All(statuses.Take(5), s => Assert.Equal(HttpStatusCode.BadRequest, s));
            Assert.Equal("RATE_LIMITED", (await AssertDeclared(sixth!, HttpStatusCode.TooManyRequests, Problem))!["code"]!.GetValue<string>());
            Assert.NotNull(sixth!.Headers.RetryAfter);
        }

        using var none = await SendAsync(null, AndroidBody(NewPlayToken()));
        await AssertDeclared(none, HttpStatusCode.Unauthorized, Problem);
    }

    private static string NewPlayToken() => "tok." + Guid.NewGuid().ToString("N");

    private static string AndroidBody(string token) =>
        "{\"platform\":\"android\",\"purchases\":[{\"productId\":\"" + PlayWireMock.Yearly + "\",\"purchaseToken\":\"" + token + "\"}],"
        + "\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef.0123456789abcdef\"}}";

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);
        Assert.True(Restore.Body["responses"]!.AsObject().ContainsKey(code), $"{Restore.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(Restore, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private async Task<(string InstallId, string Token)> NewInstallAsync()
    {
        var installId = Guid.NewGuid().ToString("D");
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Headers.Add(IdempotencyKeys.HeaderName, string.Concat(RandomNumberGenerator.GetBytes(26).Select(b => "0123456789ABCDEFGHJKMNPQRSTVWXYZ"[b % 32])));
        request.Content = new StringContent("{\"installId\":\"" + installId + "\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}", Encoding.UTF8, Json);
        using var response = await fixture.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (installId, JsonNode.Parse(await response.Content.ReadAsStringAsync())!["installToken"]!.GetValue<string>());
    }

    private async Task<HttpResponseMessage> SendAsync(string? token, string body, string? nonce = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/purchases/restore");
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
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
