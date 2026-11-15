using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Accounts;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>Scripted ID tokens and Apple endpoint for the live contract run (the real verifier has its own tests against fake issuers).</summary>
public sealed class ScriptedAccounts : IIdTokenVerifier, IAppleAccountClient
{
    private readonly ConcurrentDictionary<string, IdTokenResult> tokens = new(StringComparer.Ordinal);

    public AppleRevokeOutcome Revoke { get; set; } = AppleRevokeOutcome.Revoked;

    public bool Down { get; set; }

    public (string Raw, string IdToken) Mint(string subject)
    {
        var raw = System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));
        var claim = Convert.ToHexStringLower(SHA256.HashData(Encoding.ASCII.GetBytes(raw)));
        var token = "eyJhbGciOiJSUzI1NiJ9." + Guid.NewGuid().ToString("N") + ".c2ln";
        var now = DateTimeOffset.UtcNow;
        tokens[token] = new IdTokenResult(IdTokenOutcome.Verified, new VerifiedIdToken(subject, null, "client", claim, now - TimeSpan.FromSeconds(3), now.AddHours(1)));
        return (raw, token);
    }

    public ValueTask<IdTokenResult> VerifyAsync(AccountProvider provider, Sensitive<string> idToken, CancellationToken cancellationToken) =>
        ValueTask.FromResult(Down ? IdTokenResult.Unavailable : tokens.GetValueOrDefault(idToken.Reveal(), IdTokenResult.Invalid));

    public Task<AppleRefreshToken?> ExchangeCodeAsync(Sensitive<string> code, string clientId, string expectedSubject, CancellationToken cancellationToken) =>
        Task.FromResult<AppleRefreshToken?>(new AppleRefreshToken(clientId, new Sensitive<string>("refresh-" + code.Reveal())));

    public Task<AppleRevokeOutcome> RevokeAsync(AppleRefreshToken token, CancellationToken cancellationToken) => Task.FromResult(Revoke);
}

/// <summary>The real API (<c>Program</c>) over PostgreSQL 17, with the ID-token verifier and Apple's token endpoint scripted.</summary>
public sealed class AccountsContractFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private ZaghlolTestDatabase? database;
    private WebApplicationFactory<Program>? factory;

    public ScriptedAccounts Accounts { get; } = new();

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", database.Api);
            builder.UseSetting("ConnectionStrings:Admin", database.Admin);
            builder.UseSetting("Accounts:AndroidPackage", "app.zaghlol.test");
            builder.UseSetting("RateLimits:PerToken:TokenLimit", "1000");
            builder.UseSetting("RateLimits:PerToken:TokensPerPeriod", "1000");
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.RemoveAll<IIdTokenVerifier>();
                services.AddSingleton<IIdTokenVerifier>(Accounts);
                services.RemoveAll<IAppleAccountClient>();
                services.AddSingleton<IAppleAccountClient>(Accounts);
            });
        });
        Client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
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
/// FU-011 for <c>signIn</c>, <c>signOut</c>, <c>deleteAccount</c> and <c>appleAndroidCallback</c> (T-135): every status the live endpoints
/// answer here is declared by the operation, every JSON body validates against its schema, and the signed 200s echo the time nonce.
/// </summary>
public class AccountsLiveContractTests(AccountsContractFixture fixture) : IClassFixture<AccountsContractFixture>
{
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Op(string id) => Spec.Operations().Single(o => o.Id == id);

    private static async Task<JsonNode?> Declared(SpecOperation operation, HttpResponseMessage response, HttpStatusCode status, string? mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);
        Assert.True(operation.Body["responses"]!.AsObject().ContainsKey(code), $"{operation.Label} does not declare {code}");
        if (mediaType is null)
        {
            Assert.Empty(text);
            return null;
        }

        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(operation, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private async Task<string> NewInstallAsync(string platform = "android")
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Headers.Add("Idempotency-Key", Key());
        request.Content = new StringContent("{\"installId\":\"" + Guid.NewGuid().ToString("D") + "\",\"platform\":\"" + platform + "\",\"appVersion\":\"1.0.0\"}", Encoding.UTF8, Json);
        using var response = await fixture.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync())!["installToken"]!.GetValue<string>();
    }

    private static string Key() => string.Concat(RandomNumberGenerator.GetBytes(26).Select(b => "0123456789ABCDEFGHJKMNPQRSTVWXYZ"[b % 32]));

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, string? token, string? body = null, string? accountToken = null, string? nonce = null, bool key = false)
    {
        using var request = new HttpRequestMessage(method, path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (accountToken is not null)
        {
            request.Headers.Add("Zaghlol-Account", accountToken);
        }

        if (nonce is not null)
        {
            request.Headers.Add("Zaghlol-Time-Nonce", nonce);
        }

        if (key)
        {
            request.Headers.Add("Idempotency-Key", Key());
        }

        request.Headers.Add("Zaghlol-App", "android/1.0.0 (1)");
        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8, Json);
        }

        return await fixture.Client.SendAsync(request);
    }

    private static string SignInBody(string provider, string idToken, string nonce, string? code = null) =>
        "{\"provider\":\"" + provider + "\",\"idToken\":\"" + idToken + "\",\"nonce\":\"" + nonce + "\"" + (code is null ? "" : ",\"authorizationCode\":\"" + code + "\"") + "}";

    [Fact]
    public async Task SignInSignOutAndDeleteAnswerWithDeclaredStatusesAndConformingBodies()
    {
        var signIn = Op("signIn");
        var signOut = Op("signOut");
        var delete = Op("deleteAccount");
        var token = await NewInstallAsync();
        var (raw, idToken) = fixture.Accounts.Mint("contract-" + Guid.NewGuid().ToString("N"));
        var body = SignInBody("apple", idToken, raw, "contractcode");
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(signIn)!, JsonNode.Parse(body)));
        var nonce = System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

        using var ok = await SendAsync(HttpMethod.Post, "/v1/accounts/signin", token, body, nonce: nonce, key: true);
        var signedIn = await Declared(signIn, ok, HttpStatusCode.OK, Json);
        Assert.True(ok.Headers.Contains("Zaghlol-Signature"));
        Assert.Equal(nonce, signedIn!["timeNonce"]!.GetValue<string>());
        Assert.NotNull(signedIn["entitlement"]!["token"]);
        var accountToken = signedIn["accountToken"]!.GetValue<string>();

        using var replayed = await SendAsync(HttpMethod.Post, "/v1/accounts/signin", token, body, key: true);
        Assert.Equal("ID_TOKEN_INVALID", (await Declared(signIn, replayed, HttpStatusCode.UnprocessableEntity, Problem))!["code"]!.GetValue<string>());

        var other = fixture.Accounts.Mint("contract-" + Guid.NewGuid().ToString("N"));
        using var conflict = await SendAsync(HttpMethod.Post, "/v1/accounts/signin", token, SignInBody("google", other.IdToken, other.Raw), key: true);
        Assert.Equal("INSTALL_LINKED_TO_OTHER_ACCOUNT", (await Declared(signIn, conflict, HttpStatusCode.Conflict, Problem))!["code"]!.GetValue<string>());

        using var unknown = await SendAsync(HttpMethod.Post, "/v1/accounts/signin", token, body.Replace("{", "{\"extra\":1,", StringComparison.Ordinal), key: true);
        Assert.Equal("UNKNOWN_FIELD", (await Declared(signIn, unknown, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());

        var outNonce = System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));
        using var signedOut = await SendAsync(HttpMethod.Post, "/v1/accounts/signout", token, accountToken: accountToken, nonce: outNonce);
        var signOutBody = await Declared(signOut, signedOut, HttpStatusCode.OK, Json);
        Assert.True(signedOut.Headers.Contains("Zaghlol-Signature"));
        Assert.Equal(outNonce, signOutBody!["timeNonce"]!.GetValue<string>());

        using var expired = await SendAsync(HttpMethod.Post, "/v1/accounts/signout", token, accountToken: accountToken);
        Assert.Equal("ACCOUNT_TOKEN_EXPIRED", (await Declared(signOut, expired, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
        using var noInstall = await SendAsync(HttpMethod.Post, "/v1/accounts/signout", null);
        await Declared(signOut, noInstall, HttpStatusCode.Unauthorized, Problem);

        // A fresh sign-in, then delete: 204 even while Apple can't revoke (the token is queued), 401 once the account is gone.
        var again = fixture.Accounts.Mint("contract-" + Guid.NewGuid().ToString("N"));
        using var second = await SendAsync(HttpMethod.Post, "/v1/accounts/signin", token, SignInBody("apple", again.IdToken, again.Raw, "code2"), key: true);
        var secondToken = (await Declared(signIn, second, HttpStatusCode.OK, Json))!["accountToken"]!.GetValue<string>();
        fixture.Accounts.Revoke = AppleRevokeOutcome.Unavailable;
        using var deleted = await SendAsync(HttpMethod.Delete, "/v1/accounts/me", token, accountToken: secondToken);
        fixture.Accounts.Revoke = AppleRevokeOutcome.Revoked;
        await Declared(delete, deleted, HttpStatusCode.NoContent, null);
        using var gone = await SendAsync(HttpMethod.Delete, "/v1/accounts/me", token, accountToken: secondToken);
        Assert.Equal("ACCOUNT_TOKEN_EXPIRED", (await Declared(delete, gone, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task SignInWithAnUnavailableProviderIsADeclared503()
    {
        var token = await NewInstallAsync();
        var (raw, idToken) = fixture.Accounts.Mint("contract-" + Guid.NewGuid().ToString("N"));
        fixture.Accounts.Down = true;
        try
        {
            using var down = await SendAsync(HttpMethod.Post, "/v1/accounts/signin", token, SignInBody("google", idToken, raw), key: true);
            Assert.Equal("UPSTREAM_UNAVAILABLE", (await Declared(Op("signIn"), down, HttpStatusCode.ServiceUnavailable, Problem))!["code"]!.GetValue<string>());
            Assert.NotNull(down.Headers.RetryAfter);
        }
        finally
        {
            fixture.Accounts.Down = false;
        }
    }

    [Fact]
    public async Task TheAppleCallbackAnswers303WithADeclaredLocationAnd400ForABadForm()
    {
        var callback = Op("appleAndroidCallback");
        var form = new Dictionary<string, string>
        {
            ["code"] = "c1a0b2d3e4f5",
            ["id_token"] = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln",
            ["state"] = "01JC8ZQ4V7M2X9K3B5N6P8R0TA",
        };
        var formSchema = callback.Body["requestBody"]?["content"]?["application/x-www-form-urlencoded"]?["schema"];
        Assert.NotNull(formSchema);
        Assert.Null(Spec.Validate(formSchema, JsonNode.Parse(System.Text.Json.JsonSerializer.Serialize(form))));

        using var ok = new HttpRequestMessage(HttpMethod.Post, "/v1/apple/android-callback") { Content = new FormUrlEncodedContent(form) };
        using var redirect = await fixture.Client.SendAsync(ok);
        using var badRequest = new HttpRequestMessage(HttpMethod.Post, "/v1/apple/android-callback") { Content = new FormUrlEncodedContent(new Dictionary<string, string> { ["state"] = "x" }) };
        using var bad = await fixture.Client.SendAsync(badRequest);

        Assert.Equal(HttpStatusCode.SeeOther, redirect.StatusCode);
        Assert.True(callback.Body["responses"]!.AsObject().ContainsKey("303"));
        var location = string.Concat(redirect.Headers.NonValidated["Location"]);
        Assert.Equal(
            "intent://callback?code=c1a0b2d3e4f5&id_token=eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln&state=01JC8ZQ4V7M2X9K3B5N6P8R0TA#Intent;package=app.zaghlol.test;scheme=signinwithapple;end",
            location);
        Assert.True(location.Length <= 12288);
        Assert.Equal("VALIDATION_FAILED", (await Declared(callback, bad, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
    }
}
