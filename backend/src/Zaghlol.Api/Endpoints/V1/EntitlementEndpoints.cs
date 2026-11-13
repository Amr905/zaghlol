using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Entitlements;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>GET /v1/entitlement</c> (backend-api §4.4, T-132). Filters in order: install token, time nonce, response signature. Issues
/// the install-bound token from the seats this install holds; never moves a seat. A <c>Zaghlol-Account</c> header that doesn't
/// validate counts as absent, so account-linked purchases are <c>paused</c> (the app asks the user to sign in again). The 200
/// carries <c>supportNotice</c> with a fresh token while the buying install has a pending notice (R4-7(2), R5-7).
/// </summary>
internal static class EntitlementEndpoints
{
    public static IEndpointRouteBuilder MapEntitlement(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapInstallScoped()
            .MapGet("/entitlement", GetAsync)
            .WithName("getEntitlement")
            .WithTimeNonce()
            .RequireResponseSignature();
        return endpoints;
    }

    private static async Task<IResult> GetAsync(
        HttpContext context,
        [FromServices] EntitlementService entitlement,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var install = InstallTokenAuthentication.InstallIdOf(context.User);
        var issue = await entitlement.GetAsync(install, SyncEndpoints.AccountHeader(context), cancellationToken);
        var response = new EntitlementResponse
        {
            Entitlement = new PurchaseEntitlementDto { Token = new Zaghlol.Domain.Sensitive<string>(issue.Token) },
            ServerTime = WholeSecond(clock.GetUtcNow()),
            TimeNonce = context.TimeNonce(),
            SupportNotice = issue.SupportNotice,
        };
        return new AnchoredJsonResult(response, JsonSerializer.SerializeToUtf8Bytes(response, ApiJsonContext.Default.EntitlementResponse));
    }

    private static DateTimeOffset WholeSecond(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }
}
