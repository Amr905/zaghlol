using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Installs;

namespace Zaghlol.Api.Auth;

/// <summary>Names of the install-token scheme, its policy and claims.</summary>
internal static class InstallTokenAuthentication
{
    public const string Scheme = "InstallToken";
    public const string Policy = "InstallToken";
    public const string InstallIdClaim = "zaghlol:iid";

    /// <summary>Base64 of SHA-256(token): the per-token rate-limit partition and the rotation precondition. Memory only.</summary>
    public const string TokenHashClaim = "zaghlol:th";

    public const string InstallHeader = "Zaghlol-Install";

    /// <summary><c>HttpContext.Items</c> flag: the <c>Zaghlol-Install</c> header was malformed (400, not 401).</summary>
    internal const string MalformedInstallHeaderItem = "zaghlol.auth.malformedInstallHeader";

    /// <summary>The scheme, its policy, and the claims it sets. No default scheme is set for other endpoints.</summary>
    public static IServiceCollection AddInstallTokenAuthentication(this IServiceCollection services)
    {
        services.AddAuthentication().AddScheme<AuthenticationSchemeOptions, InstallTokenAuthenticationHandler>(Scheme, _ => { });
        services.AddAuthorizationBuilder()
            .AddPolicy(Policy, policy => policy.AddAuthenticationSchemes(Scheme).RequireAuthenticatedUser());
        return services;
    }

    /// <summary>
    /// Every endpoint of this builder needs <c>Authorization: Bearer &lt;installToken&gt;</c>: <c>401 INSTALL_TOKEN_INVALID</c>
    /// otherwise. Applied to the <c>/v1</c> install-scoped group.
    /// </summary>
    public static TBuilder RequireInstallToken<TBuilder>(this TBuilder builder)
        where TBuilder : IEndpointConventionBuilder =>
        builder.WithMetadata(InstallTokenRequiredMetadata.Instance).RequireAuthorization(Policy);

    /// <summary>The install the request's token authenticates. Only valid on endpoints that require the install token.</summary>
    public static InstallId InstallIdOf(ClaimsPrincipal user)
    {
        ArgumentNullException.ThrowIfNull(user);
        return InstallId.Parse(user.FindFirst(InstallIdClaim)?.Value ?? throw new InvalidOperationException("The request is not install-authenticated."));
    }

    /// <summary>SHA-256 of the request's install token. Only valid on endpoints that require the install token.</summary>
    public static byte[] TokenHashOf(ClaimsPrincipal user)
    {
        ArgumentNullException.ThrowIfNull(user);
        return Convert.FromBase64String(user.FindFirst(TokenHashClaim)?.Value ?? throw new InvalidOperationException("The request is not install-authenticated."));
    }
}

/// <summary>Endpoint metadata: this endpoint authenticates with the install token.</summary>
internal sealed class InstallTokenRequiredMetadata
{
    public static readonly InstallTokenRequiredMetadata Instance = new();

    private InstallTokenRequiredMetadata()
    {
    }
}

/// <summary>
/// The install-token scheme (T-124 design note). (1) <c>Authorization: Bearer</c> missing or malformed: 401 without any
/// database access. (2) Lookup by SHA-256(token) where <c>deleted_at IS NULL</c>; unknown and tombstoned tokens get the same
/// 401 body (no oracle). (3) An optional <c>Zaghlol-Install</c> header must be a lowercase UUID v4 (else
/// <c>400 VALIDATION_FAILED</c>) and name the token's install (else 401). (4) The install's first authenticated call clears
/// the registration columns (R3-6) in an UPDATE that also requires the token hash, so a racing registration replay and this
/// call can't both win. (5) <c>installHash</c> for the request log from the install ID of the database row. Endpoints
/// without <see cref="InstallTokenRequiredMetadata"/> are never authenticated here (no default-scheme lookups).
/// </summary>
internal sealed class InstallTokenAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    private const string Failure = "install token invalid";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (Context.GetEndpoint()?.Metadata.GetMetadata<InstallTokenRequiredMetadata>() is null)
        {
            return AuthenticateResult.NoResult();
        }

        // Resolved here, not injected: hosts without the install store (signing and observability test hosts) still build
        // this handler when the single registered scheme becomes the default.
        var installs = Context.RequestServices.GetRequiredService<IInstallStore>();
        var authorization = Request.Headers.Authorization;
        if (authorization.Count != 1 || !InstallTokens.TryReadBearer(authorization[0], out var token))
        {
            return AuthenticateResult.Fail(Failure);
        }

        var tokenHash = InstallTokens.Hash(token);
        var found = await installs.FindByTokenHashAsync(tokenHash, Context.RequestAborted);
        if (found is null)
        {
            return AuthenticateResult.Fail(Failure);
        }

        var claimed = Request.Headers[InstallTokenAuthentication.InstallHeader];
        if (claimed.Count > 0)
        {
            if (claimed.Count != 1 || !InstallId.TryParse(claimed[0], out var claimedId))
            {
                Context.Items[InstallTokenAuthentication.MalformedInstallHeaderItem] = true;
                return AuthenticateResult.Fail(Failure);
            }

            if (claimedId != found.InstallId)
            {
                return AuthenticateResult.Fail(Failure);
            }
        }

        if (found.RegistrationPending && !await installs.ConfirmFirstUseAsync(found.InstallId, tokenHash, Context.RequestAborted))
        {
            // A registration replay replaced this token (or the install was deleted) between the lookup and now.
            return AuthenticateResult.Fail(Failure);
        }

        await InstallLogHash.SetAsync(Context, found.InstallId);

        Claim[] claims =
        [
            new(InstallTokenAuthentication.InstallIdClaim, found.InstallId.ToString()),
            new(InstallTokenAuthentication.TokenHashClaim, Convert.ToBase64String(tokenHash)),
        ];
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name));
        return AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme.Name));
    }

    protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        if (Context.Items.ContainsKey(InstallTokenAuthentication.MalformedInstallHeaderItem))
        {
            await ApiProblems.WriteAsync(Context, StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
            return;
        }

        Response.Headers.WWWAuthenticate = "Bearer";
        await ApiProblems.WriteAsync(Context, StatusCodes.Status401Unauthorized, ErrorCodes.InstallTokenInvalid);
    }

    protected override async Task HandleForbiddenAsync(AuthenticationProperties properties) =>
        await ApiProblems.WriteAsync(Context, StatusCodes.Status403Forbidden, ErrorCodes.Forbidden);
}
