using System.Buffers.Text;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Primitives;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Auth;

/// <summary>
/// Google's signing keys for the Pub/Sub push OIDC tokens (T-133 design note §1 step 2): <see cref="OidcJwksCache"/> for
/// <c>https://accounts.google.com</c> (the discovered <c>issuer</c> must equal it), refreshed every 24 h, RSA keys only.
/// </summary>
internal sealed class GoogleKeyCache(
    IHttpClientFactory clients,
    TimeProvider clock,
    ILogger<GoogleKeyCache> logger,
    IHostApplicationLifetime? lifetime = null) : OidcJwksCache(clients, HttpClientName, clock, logger, lifetime)
{
    public const string HttpClientName = "zaghlol-google-oidc";

    public const string GoogleIssuer = "https://accounts.google.com";

    protected override string Issuer => GoogleIssuer;

    protected override Uri DiscoveryUri { get; } = new(GoogleIssuer + "/.well-known/openid-configuration");

    protected override TimeSpan RefreshEvery => TimeSpan.FromHours(24);

    protected override string Source => "google";

    /// <summary>Only RS256 is accepted, so only RSA keys are kept.</summary>
    protected override bool Accepts(JsonWebKey key) =>
        IsUsableSigningKey(key) && string.Equals(key.Kty, "RSA", StringComparison.Ordinal);
}

/// <summary>
/// The Pub/Sub push token checks (T-133 design note §1 step 2), in order, each only if the previous passed: exactly one
/// <c>Authorization: Bearer</c> header of at most <see cref="PubSubPushAuthentication.MaxHeaderLength"/> characters and three segments;
/// header <c>alg = RS256</c> (<c>jku</c>, <c>x5u</c>, <c>jwk</c>, <c>x5c</c> ignored, never fetched); <c>kid</c> in Google's JWKS;
/// the signature; <c>iss</c> one of Google's two forms; <c>aud</c> a single string equal to <c>Rtdn:Audience</c>; <c>email</c> equal
/// (ordinal) to <c>Rtdn:PushServiceAccount</c>; <c>email_verified</c> the JSON boolean <c>true</c>; <c>exp &gt; now − 60 s</c>;
/// <c>iat ≤ now + 5 min</c>. The result is one fixed outcome word (<see cref="RtdnTags.Auth"/>); the token is never logged or echoed.
/// </summary>
internal sealed class PubSubPushTokenValidator(GoogleKeyCache keys, PlayRtdnSettings settings, TimeProvider clock)
{
    private static readonly JsonWebTokenHandler Handler = new() { MapInboundClaims = false };

    public async ValueTask<string> ValidateAsync(StringValues authorization, CancellationToken cancellationToken)
    {
        if (authorization.Count == 0)
        {
            return RtdnTags.Auth.Missing;
        }

        if (!settings.IsConfigured)
        {
            // Development/Testing only: Production refuses to start without Rtdn:Audience and Rtdn:PushServiceAccount.
            return RtdnTags.Auth.NotConfigured;
        }

        const string Prefix = "Bearer ";
        if (authorization.Count != 1 || authorization[0] is not { } header
            || header.Length > PubSubPushAuthentication.MaxHeaderLength
            || !header.StartsWith(Prefix, StringComparison.Ordinal))
        {
            return RtdnTags.Auth.Malformed;
        }

        var token = header[Prefix.Length..];
        if (token.Count(c => c == '.') != 2 || token.Any(c => c is < '!' or > '~'))
        {
            return RtdnTags.Auth.Malformed;
        }

        JsonWebToken jwt;
        try
        {
            jwt = Handler.ReadJsonWebToken(token);
        }
#pragma warning disable CA1031 // Any parse failure of an untrusted token is a refusal (401), never a 500.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            return RtdnTags.Auth.Malformed;
        }

        if (!string.Equals(jwt.Alg, SecurityAlgorithms.RsaSha256, StringComparison.Ordinal))
        {
            return RtdnTags.Auth.BadAlg;
        }

        if (string.IsNullOrEmpty(jwt.Kid) || jwt.Kid.Length > 256)
        {
            return RtdnTags.Auth.UnknownKid;
        }

        var key = await keys.FindAsync(jwt.Kid, cancellationToken);
        if (key is null)
        {
            // No usable key set at all is our outage (503, Pub/Sub retries); an unknown kid with keys in hand is a forgery (401).
            return keys.HasUsableKeys ? RtdnTags.Auth.UnknownKid : RtdnTags.Auth.KeysUnavailable;
        }

        if (!string.Equals(key.Kty, "RSA", StringComparison.Ordinal))
        {
            return RtdnTags.Auth.UnknownKid;
        }

        var parameters = new TokenValidationParameters
        {
            IssuerSigningKey = key,
            TryAllIssuerSigningKeys = false,
            ValidateIssuerSigningKey = false,
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
            RequireSignedTokens = true,

            // Issuer, audience, e-mail and lifetime are checked below with the exact rules of the design note.
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
            result = await Handler.ValidateTokenAsync(token, parameters);
        }
#pragma warning disable CA1031 // The handler reports defects in the result; anything it throws is a refusal too.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            return RtdnTags.Auth.BadSignature;
        }

        if (!result.IsValid)
        {
            return RtdnTags.Auth.BadSignature;
        }

        return CheckClaims(token, clock.GetUtcNow().ToUnixTimeSeconds());
    }

    /// <summary>The claims straight from the signed payload, with exact JSON types (no library coercion).</summary>
    private string CheckClaims(string token, long now)
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
            return RtdnTags.Auth.Malformed;
        }

        using (payload)
        {
            var root = payload.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return RtdnTags.Auth.Malformed;
            }

            if (!IsString(root, "iss", out var issuer) || !PubSubPushAuthentication.Issuers.Contains(issuer, StringComparer.Ordinal))
            {
                return RtdnTags.Auth.BadIssuer;
            }

            // A single string: an array audience (even one holding ours) is refused.
            if (!IsString(root, "aud", out var audience) || !string.Equals(audience, settings.Audience, StringComparison.Ordinal))
            {
                return RtdnTags.Auth.BadAudience;
            }

            if (!IsString(root, "email", out var email) || !string.Equals(email, settings.PushServiceAccount, StringComparison.Ordinal))
            {
                return RtdnTags.Auth.BadSender;
            }

            if (!root.TryGetProperty("email_verified", out var verified) || verified.ValueKind != JsonValueKind.True)
            {
                return RtdnTags.Auth.UnverifiedSender;
            }

            if (!IsInteger(root, "exp", out var exp) || exp <= now - (long)PubSubPushAuthentication.ExpirySkew.TotalSeconds)
            {
                return RtdnTags.Auth.Expired;
            }

            if (!IsInteger(root, "iat", out var iat) || iat > now + (long)PubSubPushAuthentication.MaxIssuedInFuture.TotalSeconds)
            {
                return RtdnTags.Auth.Expired;
            }

            return RtdnTags.Auth.Ok;
        }
    }

    private static bool IsString(JsonElement root, string name, out string value)
    {
        value = string.Empty;
        if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = element.GetString()!;
        return true;
    }

    private static bool IsInteger(JsonElement root, string name, out long value)
    {
        value = 0;
        return root.TryGetProperty(name, out var element)
            && element.ValueKind == JsonValueKind.Number
            && element.TryGetInt64(out value)
            && value > 0;
    }
}

/// <summary>The Pub/Sub push scheme (<c>googlePubSubOidc</c> in the OpenAPI file) and its policy.</summary>
internal static class PubSubPushAuthentication
{
    public const string Scheme = "PubSubPush";
    public const string Policy = "pubsub-push";

    /// <summary>The longest <c>Authorization</c> header value accepted (Google's tokens are about 1 KB).</summary>
    public const int MaxHeaderLength = 4096;

    /// <summary>Set on the request when no Google key set is usable: the challenge answers 503 instead of 401.</summary>
    public const string KeysUnavailableItem = "zaghlol.rtdn.keys_unavailable";

    public static readonly TimeSpan ExpirySkew = TimeSpan.FromSeconds(60);

    public static readonly TimeSpan MaxIssuedInFuture = TimeSpan.FromMinutes(5);

    /// <summary>The longest wait for Google's discovery document or JWKS.</summary>
    public static readonly TimeSpan KeyFetchTimeout = TimeSpan.FromSeconds(10);

    /// <summary>The two <c>iss</c> forms Google uses.</summary>
    public static IReadOnlyList<string> Issuers { get; } = [GoogleKeyCache.GoogleIssuer, "accounts.google.com"];

    /// <summary>
    /// The scheme, its policy, Google's key cache (with its own HTTP client) and the validator. The scheme never becomes the default:
    /// only <c>POST /v1/notifications/google</c> names it.
    /// </summary>
    public static IServiceCollection AddPubSubPushAuthentication(this IServiceCollection services)
    {
        services.TryAddSingleton(TimeProvider.System);
        services.AddHttpClient(GoogleKeyCache.HttpClientName, client =>
        {
            client.Timeout = KeyFetchTimeout;
            client.MaxResponseContentBufferSize = OperatorAuthServiceCollectionExtensions.MaxIdpDocumentBytes;
        });
        services.TryAddSingleton<GoogleKeyCache>();
        services.TryAddSingleton<PubSubPushTokenValidator>();
        services.AddAuthentication().AddScheme<AuthenticationSchemeOptions, PubSubPushAuthenticationHandler>(Scheme, _ => { });
        services.AddAuthorizationBuilder()
            .AddPolicy(Policy, policy => policy.AddAuthenticationSchemes(Scheme).RequireAuthenticatedUser());
        return services;
    }
}

/// <summary>
/// The Pub/Sub push scheme. It reads only the <c>Authorization</c> header and never touches <c>Request.Body</c>, so a request that
/// fails here is answered without the body being read or buffered (T-133 AC 3). Any failure is one generic <c>401 UNAUTHORIZED</c>;
/// with no usable Google key set the answer is <c>503 UPSTREAM_UNAVAILABLE</c> so Pub/Sub retries (fail closed, recoverable). Every
/// attempt is counted in <c>zaghlol.rtdn.auth{outcome}</c>.
/// </summary>
internal sealed class PubSubPushAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    PubSubPushTokenValidator validator,
    ZaghlolMetrics metrics) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    private const string Failure = "pubsub push token refused";

    /// <summary>Seconds Pub/Sub is asked to wait when Google's keys are unavailable.</summary>
    public const int KeysUnavailableRetryAfterSeconds = 30;

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var outcome = await validator.ValidateAsync(Request.Headers.Authorization, Context.RequestAborted);
        metrics.RtdnAuth(outcome);
        if (outcome == RtdnTags.Auth.Ok)
        {
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.Name, "pubsub")], Scheme.Name);
            return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name));
        }

        if (outcome == RtdnTags.Auth.KeysUnavailable)
        {
            Context.Items[PubSubPushAuthentication.KeysUnavailableItem] = true;
        }

        return AuthenticateResult.Fail(Failure);
    }

    protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        if (Context.Items.ContainsKey(PubSubPushAuthentication.KeysUnavailableItem))
        {
            Response.Headers.RetryAfter = KeysUnavailableRetryAfterSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture);
            await ApiProblems.WriteAsync(Context, StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable, KeysUnavailableRetryAfterSeconds);
            return;
        }

        Response.Headers.WWWAuthenticate = "Bearer";
        await ApiProblems.WriteAsync(Context, StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized);
    }

    protected override async Task HandleForbiddenAsync(AuthenticationProperties properties) =>
        await ApiProblems.WriteAsync(Context, StatusCodes.Status403Forbidden, ErrorCodes.Forbidden);
}
