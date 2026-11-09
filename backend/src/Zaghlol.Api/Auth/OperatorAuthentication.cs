using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;

namespace Zaghlol.Api.Auth;

/// <summary>The operator roles (<c>x-required-roles</c> in the OpenAPI file, backend-api §5.1).</summary>
internal static class OperatorRoles
{
    public const string FlagsAdmin = "flags_admin";
}

/// <summary>A validated operator token: who, and with which roles.</summary>
internal sealed record OperatorIdentity(Guid OperatorId, IReadOnlyCollection<string> Roles);

/// <summary>
/// Turns an operator bearer token into an identity: OIDC signature, issuer, audience, lifetime (at most 1 hour), the MFA
/// signal, the operator row and its roles (backend-api §3). The real validator is T-136's. Until it replaces the default
/// below, every operator call is refused.
/// </summary>
internal interface IOperatorTokenValidator
{
    /// <summary>The identity, or <c>null</c> for any token that must not be accepted (including a missing MFA signal).</summary>
    ValueTask<OperatorIdentity?> ValidateAsync(string bearerToken, CancellationToken cancellationToken);
}

/// <summary>The default validator: accepts nothing, so <c>/admin/v1/*</c> is closed (401) until operator auth is configured.</summary>
internal sealed class RejectAllOperatorTokenValidator : IOperatorTokenValidator
{
    public ValueTask<OperatorIdentity?> ValidateAsync(string bearerToken, CancellationToken cancellationToken) =>
        ValueTask.FromResult<OperatorIdentity?>(null);
}

/// <summary>The operator scheme (<c>operatorOidc</c>), its per-role policies and claims.</summary>
internal static class OperatorAuthentication
{
    public const string Scheme = "OperatorOidc";
    public const string OperatorIdClaim = "zaghlol:op";

    private const int MaxTokenLength = 8192;

    public static string PolicyFor(string role) => "operator:" + role;

    /// <summary>
    /// The operator scheme and one policy per role. It never becomes the default scheme: only endpoints that name it (through
    /// <c>RequireOperatorRole</c>) are authenticated by it, so <c>/v1</c> can't be reached with an operator token.
    /// </summary>
    public static IServiceCollection AddOperatorAuthentication(this IServiceCollection services)
    {
        services.TryAddSingleton<IOperatorTokenValidator, RejectAllOperatorTokenValidator>();
        services.AddAuthentication().AddScheme<AuthenticationSchemeOptions, OperatorAuthenticationHandler>(Scheme, _ => { });
        services.AddAuthorizationBuilder().AddPolicy(
            PolicyFor(OperatorRoles.FlagsAdmin),
            policy => policy.AddAuthenticationSchemes(Scheme).RequireAuthenticatedUser().RequireClaim(ClaimTypes.Role, OperatorRoles.FlagsAdmin));
        return services;
    }

    public static TBuilder RequireOperatorRole<TBuilder>(this TBuilder builder, string role)
        where TBuilder : IEndpointConventionBuilder =>
        builder.RequireAuthorization(PolicyFor(role));

    /// <summary>The operator the request's token authenticates. Only valid on endpoints that require an operator role.</summary>
    public static Guid OperatorIdOf(ClaimsPrincipal user)
    {
        ArgumentNullException.ThrowIfNull(user);
        return Guid.Parse(user.FindFirst(OperatorIdClaim)?.Value ?? throw new InvalidOperationException("The request is not operator-authenticated."));
    }

    internal static bool TryReadBearer(string? header, out string token)
    {
        token = string.Empty;
        const string Prefix = "Bearer ";
        if (header is null
            || !header.StartsWith(Prefix, StringComparison.Ordinal)
            || header.Length == Prefix.Length
            || header.Length > Prefix.Length + MaxTokenLength)
        {
            return false;
        }

        token = header[Prefix.Length..];
        return !token.Any(c => c is < '!' or > '~');
    }
}

/// <summary>
/// The operator scheme: <c>Authorization: Bearer</c> goes to <see cref="IOperatorTokenValidator"/>. A missing, malformed or
/// refused token is <c>401 UNAUTHORIZED</c> with one body (no oracle); a valid token without the endpoint's role is
/// <c>403 FORBIDDEN</c>. The token is never logged.
/// </summary>
internal sealed class OperatorAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    IOperatorTokenValidator validator) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var authorization = Request.Headers.Authorization;
        if (authorization.Count != 1 || !OperatorAuthentication.TryReadBearer(authorization[0], out var token))
        {
            return AuthenticateResult.NoResult();
        }

        if (await validator.ValidateAsync(token, Context.RequestAborted) is not { } identity)
        {
            return AuthenticateResult.Fail("operator token refused");
        }

        var claims = new List<Claim> { new(OperatorAuthentication.OperatorIdClaim, identity.OperatorId.ToString("D")) };
        claims.AddRange(identity.Roles.Select(role => new Claim(ClaimTypes.Role, role)));
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name, nameType: null, roleType: ClaimTypes.Role));
        return AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme.Name));
    }

    protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.Headers.WWWAuthenticate = "Bearer";
        await ApiProblems.WriteAsync(Context, StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized);
    }

    protected override async Task HandleForbiddenAsync(AuthenticationProperties properties) =>
        await ApiProblems.WriteAsync(Context, StatusCodes.Status403Forbidden, ErrorCodes.Forbidden);
}
