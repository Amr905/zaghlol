using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;

namespace Zaghlol.Api.Auth;

/// <summary>An authenticated operator: the <c>operators.id</c> and the roles granted to it (backend-api §5).</summary>
internal sealed record OperatorIdentity(Guid OperatorId, IReadOnlyList<string> Roles);

/// <summary>
/// Where an operator's identity comes from. T-136 (OIDC with MFA) supplies the real implementation; until it lands the
/// default denies everyone, so every admin endpoint answers 401 in production. Tests supply a principal here.
/// </summary>
internal interface IOperatorAuthenticator
{
    /// <summary>The operator behind the request, or <c>null</c> when the request carries no valid operator credential.</summary>
    ValueTask<OperatorIdentity?> AuthenticateAsync(HttpContext context);
}

/// <summary>The default until T-136: nobody is an operator.</summary>
internal sealed class DenyAllOperatorAuthenticator : IOperatorAuthenticator
{
    public ValueTask<OperatorIdentity?> AuthenticateAsync(HttpContext context) => ValueTask.FromResult<OperatorIdentity?>(null);
}

/// <summary>
/// The <c>Operator</c> scheme and the role policies of the admin API. Admin endpoints never use the install-token scheme and
/// public endpoints never use this one (backend-api §5: operator endpoints are separate from the public app endpoints).
/// </summary>
internal static class OperatorAuthentication
{
    public const string Scheme = "Operator";
    public const string OperatorIdClaim = "zaghlol:oid";

    /// <summary>Role and policy name of the catalog editing endpoints (SRS role <c>catalog_editor</c>).</summary>
    public const string CatalogEditor = "catalog_editor";

    /// <summary>
    /// Registers the scheme (once, even when another task registered it too), the deny-all authenticator unless one is already
    /// set, and the <c>catalog_editor</c> policy. The install-token scheme stays the default scheme, as it was while it was the
    /// only one.
    /// </summary>
    public static IServiceCollection AddOperatorAuthentication(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IOperatorAuthenticator, DenyAllOperatorAuthenticator>();
        services.Configure<AuthenticationOptions>(options =>
        {
            options.DefaultScheme ??= InstallTokenAuthentication.Scheme;
            if (!options.SchemeMap.ContainsKey(Scheme))
            {
                options.AddScheme<OperatorAuthenticationHandler>(Scheme, displayName: null);
            }
        });
        services.AddAuthorizationBuilder()
            .AddPolicy(CatalogEditor, policy => policy.AddAuthenticationSchemes(Scheme).RequireAuthenticatedUser().RequireRole(CatalogEditor));
        return services;
    }

    /// <summary>The <c>operators.id</c> of the request's operator. Only valid on endpoints behind an operator policy.</summary>
    public static Guid OperatorIdOf(ClaimsPrincipal user)
    {
        ArgumentNullException.ThrowIfNull(user);

        return Guid.Parse(user.FindFirst(OperatorIdClaim)?.Value ?? throw new InvalidOperationException("The request is not operator-authenticated."));
    }
}

/// <summary>Asks the <see cref="IOperatorAuthenticator"/>; answers <c>401 UNAUTHORIZED</c> or <c>403 FORBIDDEN</c> as problems.</summary>
internal sealed class OperatorAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var authenticator = Context.RequestServices.GetRequiredService<IOperatorAuthenticator>();
        if (await authenticator.AuthenticateAsync(Context) is not { } identity)
        {
            return AuthenticateResult.NoResult();
        }

        var claims = new List<Claim> { new(OperatorAuthentication.OperatorIdClaim, identity.OperatorId.ToString("D")) };
        claims.AddRange(identity.Roles.Select(role => new Claim(ClaimTypes.Role, role)));
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name));
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
