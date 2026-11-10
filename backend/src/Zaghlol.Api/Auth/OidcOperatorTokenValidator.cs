using System.Collections.Concurrent;
using System.Buffers.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Zaghlol.Application.Operators;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Auth;

/// <summary>
/// The operator token validator (T-136 design note §2–§3). Every rule fails closed to <c>null</c> (one 401 body):
/// <list type="bullet">
/// <item>compact JWS only (three segments); <c>alg</c> in the allow-list (RS256, ES256); <c>kid</c> required; the key comes
/// from the IdP's pinned JWKS and must match the algorithm's key type, so <c>none</c>, HS* (including HS256 keyed with the
/// public key) and header-supplied keys can't verify;</item>
/// <item><c>iss</c> and <c>aud</c> exact; <c>exp</c>, <c>iat</c> and <c>nbf</c> present; 60 s skew; <c>exp - iat</c> at most
/// one hour; <c>iat</c> at most 60 s in the future;</item>
/// <item><c>amr</c> contains an accepted MFA value (default <c>mfa</c>); a missing <c>amr</c> is refusal;</item>
/// <item><c>sub</c> is the only identity key; the <c>operators</c> row must exist and not be disabled, and its roles (known
/// ones only) are the operator's roles. Token group claims are ignored. Rows are cached 30 s per subject (hit or miss, at
/// most 1000 subjects), so a disable takes effect within 30 s;</item>
/// <item><c>support_agent</c> and <c>support_lead</c>: in <see cref="PhishingResistantMode.Enforced"/> the token's
/// <c>acrs</c> must contain <c>RequiredAcrs</c> or the role is dropped (the policy answers 403); in
/// <see cref="PhishingResistantMode.Advisory"/> the role stays and the diag counter counts the request.</item>
/// </list>
/// The token is never logged; a refusal logs a fixed reason word only.
/// </summary>
internal sealed partial class OidcOperatorTokenValidator(
    IOptions<OperatorAuthOptions> options,
    OidcKeyCache keys,
    IOperatorDirectory directory,
    ZaghlolMetrics metrics,
    TimeProvider clock,
    ILogger<OidcOperatorTokenValidator> logger) : IOperatorTokenValidator
{
    public const int MaxCachedSubjects = 1000;
    public const int MaxSubjectLength = 255;

    private static readonly JsonWebTokenHandler Handler = new() { MapInboundClaims = false };

    private readonly ConcurrentDictionary<string, CachedOperator> operators = new(StringComparer.Ordinal);

    public async ValueTask<OperatorIdentity?> ValidateAsync(string bearerToken, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(bearerToken);

        var token = await ValidateTokenAsync(bearerToken, cancellationToken);
        if (token is null)
        {
            return null;
        }

        // Database failures propagate (503), unlike token defects (401).
        var row = await FindOperatorAsync(token.Subject, cancellationToken);
        if (row is null || row.Disabled)
        {
            LogRefused(logger, row is null ? "unknown_operator" : "disabled_operator");
            return null;
        }

        var settings = options.Value;
        var proven = !string.IsNullOrWhiteSpace(settings.RequiredAcrs)
                     && token.Acrs.Contains(settings.RequiredAcrs, StringComparer.Ordinal);
        var roles = new List<string>(row.Roles.Count);
        foreach (var role in row.Roles.Distinct(StringComparer.Ordinal))
        {
            if (!Application.Operators.OperatorRoles.IsKnown(role))
            {
                metrics.OperatorUnknownRole();
                continue;
            }

            if (Application.Operators.OperatorRoles.PhishingResistant.Contains(role, StringComparer.Ordinal) && !proven)
            {
                if (settings.PhishingResistantMode == PhishingResistantMode.Enforced)
                {
                    LogRoleDropped(logger, role);
                    continue;
                }

                metrics.OperatorPhishingResistantUnproven(role);
            }

            roles.Add(role);
        }

        return new OperatorIdentity(row.Id, roles);
    }

    /// <summary>The checks of the token itself; <c>null</c> for any defect. Never throws for a malformed token.</summary>
    internal async ValueTask<ValidatedToken?> ValidateTokenAsync(string token, CancellationToken cancellationToken)
    {
        var settings = options.Value;
        JsonWebToken jwt;
        try
        {
            if (token.Count(c => c == '.') != 2 || !Handler.CanReadToken(token))
            {
                return Refuse("malformed");
            }

            jwt = Handler.ReadJsonWebToken(token);
        }
#pragma warning disable CA1031 // Any parse failure of an untrusted token is a refusal (401), never a 500.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            return Refuse("malformed");
        }

        var algorithms = settings.EffectiveAlgorithms();
        if (!algorithms.Contains(jwt.Alg, StringComparer.Ordinal))
        {
            return Refuse("algorithm");
        }

        if (string.IsNullOrEmpty(jwt.Kid))
        {
            return Refuse("kid");
        }

        var key = await keys.FindAsync(jwt.Kid, cancellationToken);
        if (key is null || !KeyFits(key, jwt.Alg))
        {
            return Refuse("key");
        }

        var parameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = settings.Issuer,
            ValidateAudience = true,
            ValidAudiences = settings.Audiences,
            RequireAudience = true,
            IssuerSigningKey = key,
            TryAllIssuerSigningKeys = false,
            ValidateIssuerSigningKey = false,
            ValidAlgorithms = algorithms,
            RequireSignedTokens = true,

            // Lifetime is checked below against the injected clock, with the exact rules of the design note.
            ValidateLifetime = false,
            RequireExpirationTime = false,
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
            return Refuse("signature");
        }

        if (!result.IsValid)
        {
            return Refuse("signature");
        }

        // Belt and braces: exact (ordinal) issuer and audience, whatever the library's matching rules are.
        if (!string.Equals(jwt.Issuer, settings.Issuer, StringComparison.Ordinal))
        {
            return Refuse("issuer");
        }

        if (!jwt.Audiences.Any(a => settings.Audiences.Contains(a, StringComparer.Ordinal)))
        {
            return Refuse("audience");
        }

        if (!TryReadNumericDates(token, out var exp, out var iat, out var nbf))
        {
            return Refuse("lifetime_claims");
        }

        var now = clock.GetUtcNow().ToUnixTimeSeconds();
        var skew = settings.ClockSkewSeconds;
        if (now >= exp + skew || nbf > now + skew || iat > now + skew || exp <= iat || exp - iat > settings.MaxLifetimeSeconds)
        {
            return Refuse("lifetime");
        }

        var amr = Values(jwt, "amr");
        if (!amr.Any(a => settings.EffectiveAcceptedAmr().Contains(a, StringComparer.Ordinal)))
        {
            return Refuse("mfa");
        }

        var subject = jwt.Subject;
        if (string.IsNullOrEmpty(subject) || subject.Length > MaxSubjectLength)
        {
            return Refuse("subject");
        }

        return new ValidatedToken(subject, Values(jwt, "acrs"));
    }

    /// <summary>RS256 needs an RSA key and ES256 a P-256 key (no algorithm confusion across key types).</summary>
    private static bool KeyFits(JsonWebKey key, string alg) => alg switch
    {
        "RS256" => string.Equals(key.Kty, "RSA", StringComparison.Ordinal),
        "ES256" => string.Equals(key.Kty, "EC", StringComparison.Ordinal) && string.Equals(key.Crv, "P-256", StringComparison.Ordinal),
        _ => false,
    };

    /// <summary>
    /// <c>exp</c>, <c>iat</c> and <c>nbf</c> straight from the signed payload: each must be present once as a JSON integer
    /// (a string, fraction or array is a refusal, whatever the library would coerce).
    /// </summary>
    private static bool TryReadNumericDates(string token, out long exp, out long iat, out long nbf)
    {
        exp = iat = nbf = 0;
        var first = token.IndexOf('.', StringComparison.Ordinal);
        var second = token.IndexOf('.', first + 1);
        try
        {
            using var payload = JsonDocument.Parse(Base64Url.DecodeFromChars(token.AsSpan(first + 1, second - first - 1)));
            var root = payload.RootElement;
            return root.ValueKind == JsonValueKind.Object
                && TryInteger(root, JwtRegisteredClaimNames.Exp, out exp)
                && TryInteger(root, JwtRegisteredClaimNames.Iat, out iat)
                && TryInteger(root, JwtRegisteredClaimNames.Nbf, out nbf);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            return false;
        }
    }

    private static bool TryInteger(JsonElement root, string name, out long value)
    {
        value = 0;
        return root.TryGetProperty(name, out var element)
            && element.ValueKind == JsonValueKind.Number
            && element.TryGetInt64(out value)
            && value > 0;
    }

    /// <summary>The values of a string or string-array claim (each array element is one claim).</summary>
    private static List<string> Values(JsonWebToken jwt, string claim) =>
        jwt.Claims.Where(c => string.Equals(c.Type, claim, StringComparison.Ordinal)).Select(c => c.Value).ToList();

    private ValidatedToken? Refuse(string reason)
    {
        LogRefused(logger, reason);
        return null;
    }

    private async ValueTask<OperatorRecord?> FindOperatorAsync(string subject, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        if (operators.TryGetValue(subject, out var cached) && cached.Until > now)
        {
            return cached.Row;
        }

        var row = await directory.FindBySubjectAsync(subject, cancellationToken);
        var ttl = TimeSpan.FromSeconds(options.Value.OperatorCacheSeconds);
        if (ttl > TimeSpan.Zero)
        {
            if (operators.Count >= MaxCachedSubjects)
            {
                foreach (var (key, entry) in operators)
                {
                    if (entry.Until <= now)
                    {
                        operators.TryRemove(key, out _);
                    }
                }

                if (operators.Count >= MaxCachedSubjects)
                {
                    operators.Clear();
                }
            }

            operators[subject] = new CachedOperator(row, now + ttl);
        }

        return row;
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Operator token refused ({Reason})")]
    private static partial void LogRefused(ILogger logger, string reason);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Operator role {Role} dropped: phishing-resistant MFA not proven by acrs")]
    private static partial void LogRoleDropped(ILogger logger, string role);

    private sealed record CachedOperator(OperatorRecord? Row, DateTimeOffset Until);
}

/// <summary>What the token proves once every check passed: the subject and the <c>acrs</c> values.</summary>
internal sealed record ValidatedToken(string Subject, IReadOnlyList<string> Acrs);
