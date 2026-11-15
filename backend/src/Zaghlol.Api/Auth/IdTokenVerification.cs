using System.Buffers.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Zaghlol.Application.Accounts;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;

namespace Zaghlol.Api.Auth;

/// <summary>
/// Apple's signing keys for Sign in with Apple ID tokens (T-135 design note): <see cref="OidcJwksCache"/> for
/// <c>https://appleid.apple.com</c> (the discovered <c>issuer</c> must equal it), refreshed every 24 h, RSA keys only.
/// </summary>
internal sealed class AppleKeyCache(
    IHttpClientFactory clients,
    TimeProvider clock,
    ILogger<AppleKeyCache> logger,
    IHostApplicationLifetime? lifetime = null) : OidcJwksCache(clients, HttpClientName, clock, logger, lifetime)
{
    public const string HttpClientName = "zaghlol-apple-oidc";

    public const string AppleIssuer = "https://appleid.apple.com";

    protected override string Issuer => AppleIssuer;

    protected override Uri DiscoveryUri { get; } = new(AppleIssuer + "/.well-known/openid-configuration");

    protected override TimeSpan RefreshEvery => TimeSpan.FromHours(24);

    protected override string Source => "apple";

    protected override bool Accepts(JsonWebKey key) =>
        IsUsableSigningKey(key) && string.Equals(key.Kty, "RSA", StringComparison.Ordinal);
}

/// <summary>
/// <see cref="IIdTokenVerifier"/> for Google and Apple ID tokens (backend-api §4.6 <i>Verification</i>), in order, each only if the
/// previous passed: at most <see cref="MaxTokenLength"/> characters and three segments; header <c>alg = RS256</c> (<c>jku</c>, <c>jwk</c>,
/// <c>x5u</c>, <c>x5c</c> ignored, never fetched); <c>kid</c> in the provider's JWKS (cached, an unknown <c>kid</c> refreshes at most once
/// per 5 minutes); the signature; <c>iss</c> (Google: either form; Apple: <c>https://appleid.apple.com</c>); <c>aud</c> a single string
/// among the configured client IDs (Google) or Services ID / bundle ID (Apple); <c>exp</c> (60 s skew); a non-empty <c>sub</c>.
/// <c>nonce</c> and <c>iat</c> are returned for <c>SignInService</c> to judge. With no usable key set at all the answer is
/// <see cref="IdTokenOutcome.Unavailable"/>, never a refusal. Nothing of the token is logged or echoed.
/// </summary>
internal sealed class IdTokenVerifier(GoogleKeyCache google, AppleKeyCache apple, AccountsOptions options, TimeProvider clock) : IIdTokenVerifier
{
    /// <summary>The OpenAPI <c>Jws</c> limit.</summary>
    public const int MaxTokenLength = 16384;

    public static readonly TimeSpan ExpirySkew = TimeSpan.FromSeconds(60);

    private static readonly JsonWebTokenHandler Handler = new() { MapInboundClaims = false };

    public async ValueTask<IdTokenResult> VerifyAsync(AccountProvider provider, Sensitive<string> idToken, CancellationToken cancellationToken)
    {
        var token = idToken.Reveal();
        if (token is not { Length: > 0 and <= MaxTokenLength } || token.Count(c => c == '.') != 2 || token.Any(c => c is < '!' or > '~'))
        {
            return IdTokenResult.Invalid;
        }

        JsonWebToken jwt;
        try
        {
            jwt = Handler.ReadJsonWebToken(token);
        }
#pragma warning disable CA1031 // Any parse failure of an untrusted token is a refusal, never a 500.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            return IdTokenResult.Invalid;
        }

        if (!string.Equals(jwt.Alg, SecurityAlgorithms.RsaSha256, StringComparison.Ordinal) || string.IsNullOrEmpty(jwt.Kid) || jwt.Kid.Length > 256)
        {
            return IdTokenResult.Invalid;
        }

        OidcJwksCache keys = provider == AccountProvider.Google ? google : apple;
        var key = await keys.FindAsync(jwt.Kid, cancellationToken).ConfigureAwait(false);
        if (key is null)
        {
            // No usable key set at all is our outage (503, the app retries); an unknown kid with keys in hand is a forgery.
            return keys.HasUsableKeys ? IdTokenResult.Invalid : IdTokenResult.Unavailable;
        }

        if (!string.Equals(key.Kty, "RSA", StringComparison.Ordinal))
        {
            return IdTokenResult.Invalid;
        }

        var parameters = new TokenValidationParameters
        {
            IssuerSigningKey = key,
            TryAllIssuerSigningKeys = false,
            ValidateIssuerSigningKey = false,
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
            RequireSignedTokens = true,

            // Issuer, audience and lifetime are checked below on the raw claims, with exact JSON types.
            ValidateIssuer = false,
            ValidateAudience = false,
            ValidateLifetime = false,
            RequireExpirationTime = false,
            RequireAudience = false,
            ValidateTokenReplay = false,
        };

        TokenValidationResult result;
        try
        {
            result = await Handler.ValidateTokenAsync(token, parameters).ConfigureAwait(false);
        }
#pragma warning disable CA1031 // The handler reports defects in the result; anything it throws is a refusal too.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            return IdTokenResult.Invalid;
        }

        return result.IsValid ? ReadClaims(token, provider) : IdTokenResult.Invalid;
    }

    private IdTokenResult ReadClaims(string token, AccountProvider provider)
    {
        var first = token.IndexOf('.', StringComparison.Ordinal);
        var second = token.IndexOf('.', first + 1);
        JsonDocument payload;
        try
        {
            payload = JsonDocument.Parse(Base64Url.DecodeFromChars(token.AsSpan(first + 1, second - first - 1)));
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            return IdTokenResult.Invalid;
        }

        using (payload)
        {
            var root = payload.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return IdTokenResult.Invalid;
            }

            IReadOnlyList<string> issuers = provider == AccountProvider.Google ? PubSubPushAuthentication.Issuers : [AppleKeyCache.AppleIssuer];
            IReadOnlyList<string> audiences = provider == AccountProvider.Google ? options.GoogleClientIds : options.AppleAudiences;

            // A single string audience: an array (even one holding ours) is refused.
            if (!String(root, "iss", out var issuer) || !issuers.Contains(issuer, StringComparer.Ordinal)
                || !String(root, "aud", out var audience) || !audiences.Contains(audience, StringComparer.Ordinal)
                || !String(root, "sub", out var subject) || subject.Length is 0 or > 255
                || !Integer(root, "exp", out var exp) || exp <= clock.GetUtcNow().ToUnixTimeSeconds() - (long)ExpirySkew.TotalSeconds)
            {
                return IdTokenResult.Invalid;
            }

            string? nonce = String(root, "nonce", out var n) ? n : null;
            DateTimeOffset? issuedAt = Integer(root, "iat", out var iat) ? DateTimeOffset.FromUnixTimeSeconds(iat) : null;
            string? email = String(root, "email", out var e) && e.Length is > 0 and <= 320 && Verified(root) ? e : null;
            return new IdTokenResult(IdTokenOutcome.Verified, new VerifiedIdToken(subject, email, audience, nonce, issuedAt, DateTimeOffset.FromUnixTimeSeconds(exp)));
        }
    }

    /// <summary><c>email_verified</c> as a JSON boolean (Google) or the string <c>"true"</c> (Apple).</summary>
    private static bool Verified(JsonElement root) =>
        root.TryGetProperty("email_verified", out var v)
        && (v.ValueKind == JsonValueKind.True || (v.ValueKind == JsonValueKind.String && v.GetString() == "true"));

    private static bool String(JsonElement root, string name, out string value)
    {
        value = string.Empty;
        if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = element.GetString()!;
        return true;
    }

    private static bool Integer(JsonElement root, string name, out long value)
    {
        value = 0;
        return root.TryGetProperty(name, out var element) && element.ValueKind == JsonValueKind.Number && element.TryGetInt64(out value) && value > 0;
    }
}

public static class IdTokenVerificationServiceCollectionExtensions
{
    /// <summary>
    /// The real ID-token verifier: Google's and Apple's key caches (each with its own HTTP client) and <see cref="IIdTokenVerifier"/>.
    /// Tests replace <see cref="IIdTokenVerifier"/> with a fake or point the two HTTP clients at <c>FakeOidcIssuer</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolIdTokenVerification(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        foreach (var name in new[] { GoogleKeyCache.HttpClientName, AppleKeyCache.HttpClientName })
        {
            services.AddHttpClient(name, client =>
            {
                client.Timeout = PubSubPushAuthentication.KeyFetchTimeout;
                client.MaxResponseContentBufferSize = OperatorAuthServiceCollectionExtensions.MaxIdpDocumentBytes;
            });
        }

        services.TryAddSingleton<GoogleKeyCache>();
        services.TryAddSingleton<AppleKeyCache>();
        services.TryAddSingleton<IIdTokenVerifier, IdTokenVerifier>();
        return services;
    }
}
