using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Accounts;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Accounts;

/// <summary>
/// The real <see cref="IIdTokenVerifier"/> against in-process Google and Apple issuers (discovery and JWKS through a message handler,
/// no network): RS256 only, the issuer forms, a single-string audience among the configured IDs, expiry, and the difference between
/// "unknown key" (a forgery, 422) and "no keys at all" (our outage, 503).
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class IdTokenVerifierTests : IDisposable
{
    private const string GoogleClient = "1234567890-abc.apps.googleusercontent.com";
    private const string AppleServices = "app.zaghlol.signin";
    private const string AppleBundle = "app.zaghlol";

    private readonly FakeOidcIssuer google = new(GoogleKeyCache.GoogleIssuer, "https://www.googleapis.com/oauth2/v3/certs");
    private readonly FakeOidcIssuer apple = new(AppleKeyCache.AppleIssuer, "https://appleid.apple.com/auth/keys");
    private readonly ManualClock clock = new();
    private readonly ServiceProvider services;
    private readonly IIdTokenVerifier verifier;

    public IdTokenVerifierTests()
    {
        var collection = new ServiceCollection();
        collection.AddLogging();
        collection.AddSingleton<TimeProvider>(clock);
        collection.AddSingleton(new AccountsOptions { GoogleClientIds = [GoogleClient], AppleAudiences = [AppleServices, AppleBundle] });
        collection.AddZaghlolIdTokenVerification();
        collection.AddHttpClient(GoogleKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(google.CreateHandler);
        collection.AddHttpClient(AppleKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(apple.CreateHandler);
        services = collection.BuildServiceProvider();
        verifier = services.GetRequiredService<IIdTokenVerifier>();
    }

    public void Dispose()
    {
        services.Dispose();
        google.Dispose();
        apple.Dispose();
    }

    private static OperatorTokenSpec Spec(string issuer, string audience, Action<Dictionary<string, JsonNode?>>? extra = null)
    {
        var claims = new Dictionary<string, JsonNode?> { ["nonce"] = "abc123" };
        extra?.Invoke(claims);
        return new OperatorTokenSpec { Subject = "subject-1", Amr = null, Issuer = issuer, Audience = audience, Extra = claims };
    }

    private async Task<IdTokenResult> VerifyAsync(AccountProvider provider, string token) =>
        await verifier.VerifyAsync(provider, new Sensitive<string>(token), CancellationToken.None);

    [Fact]
    public async Task AGoogleTokenOfOurClientVerifiesAndReturnsTheClaimsSignInNeeds()
    {
        var token = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient, c => { c["email"] = "person@example.test"; c["email_verified"] = true; }), clock.Now);

        var result = await VerifyAsync(AccountProvider.Google, token);

        Assert.Equal(IdTokenOutcome.Verified, result.Outcome);
        Assert.Equal("subject-1", result.Token!.Subject);
        Assert.Equal("abc123", result.Token.Nonce);
        Assert.Equal(GoogleClient, result.Token.Audience);
        Assert.Equal("person@example.test", result.Token.Email);
        Assert.Equal(clock.Now.ToUnixTimeSeconds(), result.Token.IssuedAt!.Value.ToUnixTimeSeconds());
        Assert.Equal("***", result.Token.ToString());
    }

    [Fact]
    public async Task BothGoogleIssuerFormsAreAccepted_AnUnverifiedEmailIsDropped()
    {
        var bare = google.Mint(Spec("accounts.google.com", GoogleClient, c => { c["email"] = "x@example.test"; c["email_verified"] = false; }), clock.Now);

        var result = await VerifyAsync(AccountProvider.Google, bare);

        Assert.Equal(IdTokenOutcome.Verified, result.Outcome);
        Assert.Null(result.Token!.Email);
    }

    [Fact]
    public async Task AnAppleTokenOfOurServicesIdOrBundleIdVerifies_WithAStringVerifiedEmail()
    {
        var services = apple.Mint(Spec(AppleKeyCache.AppleIssuer, AppleServices, c => { c["email"] = "relay@privaterelay.example.test"; c["email_verified"] = "true"; }), clock.Now);
        var bundle = apple.Mint(Spec(AppleKeyCache.AppleIssuer, AppleBundle), clock.Now);

        var first = await VerifyAsync(AccountProvider.Apple, services);
        var second = await VerifyAsync(AccountProvider.Apple, bundle);

        Assert.Equal(AppleServices, first.Token!.Audience);
        Assert.Equal("relay@privaterelay.example.test", first.Token.Email);
        Assert.Equal(AppleBundle, second.Token!.Audience);
    }

    [Fact]
    public async Task ATokenWithoutNonceOrIatStillVerifies_SignInJudgesThose()
    {
        var token = google.Mint(
            new OperatorTokenSpec { Subject = "s", Amr = null, Issuer = GoogleKeyCache.GoogleIssuer, Audience = GoogleClient, OmitIssuedAt = true },
            clock.Now);

        var result = await VerifyAsync(AccountProvider.Google, token);

        Assert.Equal(IdTokenOutcome.Verified, result.Outcome);
        Assert.Null(result.Token!.Nonce);
        Assert.Null(result.Token.IssuedAt);
    }

    [Fact]
    public async Task EveryDefectIsInvalid()
    {
        var cases = new Dictionary<string, string>
        {
            ["wrong audience"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, "someone-else"), clock.Now),
            ["apple client as google"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, AppleServices), clock.Now),
            ["array audience"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient, c => c["aud"] = new JsonArray(GoogleClient)), clock.Now),
            ["wrong issuer"] = google.Mint(Spec("https://evil.example.test", GoogleClient), clock.Now),
            ["expired"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { LifetimeSeconds = -120 }, clock.Now),
            ["no expiry"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { OmitExpiry = true }, clock.Now),
            ["empty subject"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { Subject = string.Empty }, clock.Now),
            ["ES256"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { Algorithm = "ES256" }, clock.Now),
            ["alg none"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { Algorithm = "none" }, clock.Now),
            ["HS256 keyed with the public key"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { Algorithm = "HS256" }, clock.Now),
            ["unknown kid"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { Kid = "not-a-key" }, clock.Now),
            ["no kid"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { Kid = string.Empty }, clock.Now),
            ["jku in the header is never followed"] = google.Mint(
                Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { ExtraHeader = new Dictionary<string, JsonNode?> { ["jku"] = "https://evil.example.test/keys" }, Kid = "not-a-key" },
                clock.Now),
            ["not a token"] = "aaa.bbb",
            ["too long"] = "a." + new string('b', IdTokenVerifier.MaxTokenLength) + ".c",
        };
        using var attacker = RSA.Create(2048);
        cases["forged signature"] = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient) with { ForeignKey = attacker }, clock.Now);

        foreach (var (name, token) in cases)
        {
            var result = await VerifyAsync(AccountProvider.Google, token);
            Assert.True(result.Outcome == IdTokenOutcome.Invalid, name);
            Assert.Null(result.Token);
        }
    }

    [Fact]
    public async Task AGoogleTokenIsNeverAcceptedAsApple_AndAnAppleTokenNeverAsGoogle()
    {
        var google = this.google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient), clock.Now);
        var apple = this.apple.Mint(Spec(AppleKeyCache.AppleIssuer, AppleServices), clock.Now);

        Assert.Equal(IdTokenOutcome.Invalid, (await VerifyAsync(AccountProvider.Apple, google)).Outcome);
        Assert.Equal(IdTokenOutcome.Invalid, (await VerifyAsync(AccountProvider.Google, apple)).Outcome);
    }

    [Fact]
    public async Task WithNoUsableKeysTheAnswerIsUnavailableNotInvalid_AndItRecovers()
    {
        var token = google.Mint(Spec(GoogleKeyCache.GoogleIssuer, GoogleClient), clock.Now);
        google.Failing = true;

        var down = await VerifyAsync(AccountProvider.Google, token);
        google.Failing = false;
        clock.Advance(OidcJwksCache.RefreshThrottle + TimeSpan.FromSeconds(1));
        var up = await VerifyAsync(AccountProvider.Google, token);

        Assert.Equal(IdTokenOutcome.Unavailable, down.Outcome);
        Assert.Equal(IdTokenOutcome.Verified, up.Outcome);
    }
}
