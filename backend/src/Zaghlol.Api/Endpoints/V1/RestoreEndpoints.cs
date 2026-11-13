using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Purchases.Restore;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/purchases/restore</c> (backend-api §4.3 Restore, T-185). Filters in order: install token, the restore bucket (5 an
/// hour per install, on top of the general ones), time nonce, response signature. No idempotency record: a restore binds one
/// attested body to one install, and a retry runs again with a fresh proof. The body is read once (<c>415</c>, <c>413</c>), parsed
/// strictly and bound once by <see cref="RestoreRequestParser"/>, and everything else is <see cref="RestoreService"/>. The only
/// <c>422</c> is <c>DEVICE_ATTESTATION_FAILED</c> and the only <c>409</c> is <c>MOVE_COOLDOWN</c>. No answer carries a token, key or
/// proof back, and nothing from the request is logged.
/// </summary>
internal static class RestoreEndpoints
{
    public static IEndpointRouteBuilder MapRestore(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapInstallScoped()
            .MapPost("/purchases/restore", RestoreAsync)
            .WithName("restorePurchases")
            .WithMetadata(RestoreRateLimitMetadata.Instance)
            .WithTimeNonce()
            .RequireResponseSignature();
        return endpoints;
    }

    private static async Task<IResult> RestoreAsync(
        HttpContext context,
        [FromServices] RestoreService restore,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var install = InstallTokenAuthentication.InstallIdOf(context.User);
        var parsed = RestoreRequestParser.Parse(body.Bytes, install);
        if (parsed.Request is not { } request)
        {
            return ApiProblems.Of(
                StatusCodes.Status400BadRequest,
                parsed.Failure == RestoreParseFailure.UnknownField ? ErrorCodes.UnknownField : ErrorCodes.ValidationFailed);
        }

        var result = await restore.RestoreAsync(request, install, SyncEndpoints.AccountHeader(context), cancellationToken);
        switch (result.Kind)
        {
            case RestoreResultKind.ValidationFailed:
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
            case RestoreResultKind.SeatKeyMismatch:
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.SeatKeyMismatch);
            case RestoreResultKind.AttestationFailed:
                return ApiProblems.Of(StatusCodes.Status422UnprocessableEntity, ErrorCodes.DeviceAttestationFailed);
            case RestoreResultKind.PurchaseRateLimited:
                return ApiProblems.RateLimited(context, result.RetryAfterSeconds);
            case RestoreResultKind.Unavailable:
                return Unavailable(context, StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable, result.RetryAfterSeconds);
            case RestoreResultKind.StoreUnavailable:
                return result.BudgetShort
                    ? Unavailable(context, StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable, result.RetryAfterSeconds)
                    : Unavailable(context, StatusCodes.Status502BadGateway, ErrorCodes.StoreUnavailable, result.RetryAfterSeconds);
            case RestoreResultKind.MoveCooldown:
                return TypedResults.Problem(
                    statusCode: StatusCodes.Status409Conflict,
                    type: "https://api.zaghlol.app/problems/move-cooldown",
                    title: "Move not yet possible",
                    extensions: new Dictionary<string, object?>
                    {
                        ["code"] = ErrorCodes.MoveCooldown,
                        ["nextMoveAt"] = result.NextMoveAt!.Value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
                    });
            default:
                var now = clock.GetUtcNow();
                var response = new PurchaseRestoreResponse
                {
                    Status = result.Status!,
                    RestoredCount = result.RestoredCount,
                    MovedFromOtherPhone = result.MovedFromOtherPhone,
                    Entitlement = result.EntitlementToken is { } token ? new PurchaseEntitlementDto { Token = token } : null,
                    ServerTime = new DateTimeOffset(now.UtcTicks - (now.UtcTicks % TimeSpan.TicksPerSecond), TimeSpan.Zero),
                    TimeNonce = context.TimeNonce(),
                };
                return new AnchoredJsonResult(response, JsonSerializer.SerializeToUtf8Bytes(response, ApiJsonContext.Default.PurchaseRestoreResponse));
        }
    }

    private static Microsoft.AspNetCore.Http.HttpResults.ProblemHttpResult Unavailable(HttpContext context, int status, string code, int retryAfterSeconds)
    {
        context.Response.Headers.RetryAfter = retryAfterSeconds.ToString(CultureInfo.InvariantCulture);
        return TypedResults.Problem(
            statusCode: status,
            extensions: new Dictionary<string, object?> { ["code"] = code, ["retryAfterSeconds"] = retryAfterSeconds });
    }
}
