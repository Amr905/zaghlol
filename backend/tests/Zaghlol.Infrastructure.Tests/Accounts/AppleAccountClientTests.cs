using System.Buffers.Text;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Accounts;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Accounts;

/// <summary>Sign in with Apple's token endpoint and the refresh-token vault (T-135), with a scripted HTTP handler and the fake KMS: no network.</summary>
public sealed class AppleAccountClientTests : IDisposable
{
    private const string Subject = "001234.abcdef.0001";
    private const string ClientId = "app.zaghlol.signin";

    private readonly ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private readonly ScriptedHandler handler = new();
    private readonly AppleAccountClient client;

    public AppleAccountClientTests()
    {
        var options = new AccountsOptions
        {
            AppleTeamId = "ABCDE12345",
            AppleKeyId = "FGHIJ67890",
            ApplePrivateKey = new Sensitive<string>(key.ExportPkcs8PrivateKeyPem()),
            AppleBaseUrl = new Uri("https://appleid.apple.com"),
        };
        client = new AppleAccountClient(new Factory(handler), options, TimeProvider.System, NullLogger<AppleAccountClient>.Instance);
    }

    public void Dispose()
    {
        client.Dispose();
        key.Dispose();
    }

    private sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }

    private sealed class ScriptedHandler : HttpMessageHandler
    {
        public Func<HttpRequestMessage, string, (HttpStatusCode Status, string Body)> Respond { get; set; } = (_, _) => (HttpStatusCode.OK, "{}");

        public List<(string Url, Dictionary<string, string> Form)> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = await request.Content!.ReadAsStringAsync(cancellationToken);
            var form = body.Split('&').Select(p => p.Split('=', 2)).ToDictionary(p => p[0], p => Uri.UnescapeDataString(p[1].Replace('+', ' ')));
            Requests.Add((request.RequestUri!.ToString(), form));
            var (status, text) = Respond(request, body);
            return new HttpResponseMessage(status) { Content = new StringContent(text, Encoding.UTF8, "application/json") };
        }
    }

    private static string IdTokenFor(string subject) =>
        "e30." + Base64Url.EncodeToString(Encoding.UTF8.GetBytes($"{{\"sub\":\"{subject}\"}}")) + ".c2ln";

    private static string ExchangeBody(string subject = Subject) =>
        JsonSerializer.Serialize(new Dictionary<string, string> { ["refresh_token"] = "r-token", ["id_token"] = IdTokenFor(subject), ["access_token"] = "a" });

    [Fact]
    public async Task ExchangePostsACodeWithASignedClientSecretAndKeepsTheRefreshTokenOfThisIdentity()
    {
        handler.Respond = (_, _) => (HttpStatusCode.OK, ExchangeBody());

        var token = await client.ExchangeCodeAsync(new Sensitive<string>("the-code"), ClientId, Subject, default);

        Assert.NotNull(token);
        Assert.Equal(ClientId, token.ClientId);
        Assert.Equal("r-token", token.Token.Reveal());
        var (url, form) = Assert.Single(handler.Requests);
        Assert.Equal("https://appleid.apple.com/auth/token", url);
        Assert.Equal("authorization_code", form["grant_type"]);
        Assert.Equal("the-code", form["code"]);
        Assert.Equal(ClientId, form["client_id"]);

        // The client secret is an ES256 JWT of the Sign in with Apple key: iss = team, sub = the client, aud = Apple, five minutes.
        var parts = form["client_secret"].Split('.');
        using var header = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[0]));
        using var payload = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1]));
        Assert.Equal("ES256", header.RootElement.GetProperty("alg").GetString());
        Assert.Equal("FGHIJ67890", header.RootElement.GetProperty("kid").GetString());
        Assert.Equal("ABCDE12345", payload.RootElement.GetProperty("iss").GetString());
        Assert.Equal(ClientId, payload.RootElement.GetProperty("sub").GetString());
        Assert.Equal("https://appleid.apple.com", payload.RootElement.GetProperty("aud").GetString());
        Assert.Equal(300, payload.RootElement.GetProperty("exp").GetInt64() - payload.RootElement.GetProperty("iat").GetInt64());
        Assert.True(key.VerifyData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), Base64Url.DecodeFromChars(parts[2]), HashAlgorithmName.SHA256));
    }

    [Fact]
    public async Task ACodeForAnotherIdentityOrAnUnusableAnswerKeepsNoToken()
    {
        handler.Respond = (_, _) => (HttpStatusCode.OK, ExchangeBody("somebody-else"));
        Assert.Null(await client.ExchangeCodeAsync(new Sensitive<string>("c"), ClientId, Subject, default));

        handler.Respond = (_, _) => (HttpStatusCode.OK, "{\"refresh_token\":\"r\"}");
        Assert.Null(await client.ExchangeCodeAsync(new Sensitive<string>("c"), ClientId, Subject, default));

        handler.Respond = (_, _) => (HttpStatusCode.OK, "not json");
        Assert.Null(await client.ExchangeCodeAsync(new Sensitive<string>("c"), ClientId, Subject, default));

        handler.Respond = (_, _) => (HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
        Assert.Null(await client.ExchangeCodeAsync(new Sensitive<string>("c"), ClientId, Subject, default));
    }

    [Fact]
    public async Task RevokePostsTheRefreshTokenWithItsOwnClientId()
    {
        var token = new AppleRefreshToken("app.zaghlol", new Sensitive<string>("r-token"));

        var outcome = await client.RevokeAsync(token, default);

        Assert.Equal(AppleRevokeOutcome.Revoked, outcome);
        var (url, form) = Assert.Single(handler.Requests);
        Assert.Equal("https://appleid.apple.com/auth/revoke", url);
        Assert.Equal("r-token", form["token"]);
        Assert.Equal("refresh_token", form["token_type_hint"]);
        Assert.Equal("app.zaghlol", form["client_id"]);
    }

    [Theory]
    [InlineData(HttpStatusCode.OK, "", AppleRevokeOutcome.Revoked)]
    [InlineData(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}", AppleRevokeOutcome.Revoked)]
    [InlineData(HttpStatusCode.BadRequest, "{\"error\":\"invalid_client\"}", AppleRevokeOutcome.Unavailable)]
    [InlineData(HttpStatusCode.TooManyRequests, "", AppleRevokeOutcome.Unavailable)]
    [InlineData(HttpStatusCode.InternalServerError, "", AppleRevokeOutcome.Unavailable)]
    [InlineData(HttpStatusCode.BadRequest, "garbage", AppleRevokeOutcome.Unavailable)]
    public async Task RevokeMapsAppleAnswers_OnlyDoneOrAlreadyGoneCountsAsRevoked(HttpStatusCode status, string body, AppleRevokeOutcome expected)
    {
        handler.Respond = (_, _) => (status, body);

        var outcome = await client.RevokeAsync(new AppleRefreshToken(ClientId, new Sensitive<string>("r")), default);

        Assert.Equal(expected, outcome);
    }

    [Fact]
    public async Task ANetworkFailureIsUnavailableNotAnException()
    {
        handler.Respond = (_, _) => throw new HttpRequestException("boom");

        Assert.Equal(AppleRevokeOutcome.Unavailable, await client.RevokeAsync(new AppleRefreshToken(ClientId, new Sensitive<string>("r")), default));
        Assert.Null(await client.ExchangeCodeAsync(new Sensitive<string>("c"), ClientId, Subject, default));
    }

    [Fact]
    public async Task WithoutTheAppleKeyNothingIsSentAndRevocationIsUnavailable()
    {
        using var unkeyed = new AppleAccountClient(new Factory(handler), new AccountsOptions(), TimeProvider.System, NullLogger<AppleAccountClient>.Instance);

        Assert.Null(await unkeyed.ExchangeCodeAsync(new Sensitive<string>("c"), ClientId, Subject, default));
        Assert.Equal(AppleRevokeOutcome.Unavailable, await unkeyed.RevokeAsync(new AppleRefreshToken(ClientId, new Sensitive<string>("r")), default));
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task TheVaultSealsUnderTheAccountSubject_AndAnotherSubjectOrATamperedBlobDoesNotOpen()
    {
        using var kms = FakeKms.CreateDefault();
        using var services = kms.BuildServices();
        var vault = new AppleTokenVault(services.GetRequiredService<IEnvelopeCipher>());
        var token = new AppleRefreshToken("app.zaghlol", new Sensitive<string>("refresh-secret"));

        var sealedToken = await vault.SealAsync(Subject, token, default);
        var opened = await vault.OpenAsync(Subject, sealedToken, default);
        var otherSubject = await vault.OpenAsync("another-subject", sealedToken, default);
        var tampered = (byte[])sealedToken.Clone();
        tampered[^1] ^= 0x01;
        var broken = await vault.OpenAsync(Subject, tampered, default);

        Assert.Equal("refresh-secret", opened!.Token.Reveal());
        Assert.Equal("app.zaghlol", opened.ClientId);
        Assert.Null(otherSubject);
        Assert.Null(broken);
        Assert.DoesNotContain("refresh-secret", Encoding.UTF8.GetString(sealedToken), StringComparison.Ordinal);
    }
}
