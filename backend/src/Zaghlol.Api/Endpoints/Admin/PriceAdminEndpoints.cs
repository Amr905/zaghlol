using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Prices;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>PUT /admin/v1/prices/override</c> (backend-api §4.8, §5), role <c>prices_admin</c>. Not idempotency-keyed: it sets absolute
/// state (a retry only moves <c>asOf</c> and adds an audit row). Every validation failure is <c>400 VALIDATION_FAILED</c> with no
/// detail; unknown members of the body are <c>400 UNKNOWN_FIELD</c>.
/// </summary>
internal static class PriceAdminEndpoints
{
    public static IEndpointRouteBuilder MapPriceAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints
            .MapPut("/admin/v1/prices/override", PutAsync)
            .RequireOperatorRole(OperatorRoles.PricesAdmin)
            .WithName("adminOverridePrice");
        return endpoints;
    }

    private static async Task<IResult> PutAsync(
        HttpContext context,
        [FromServices] PriceOverrideService prices,
        [FromServices] ZaghlolMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var read = await StrictJson.ReadAsync<PriceOverrideRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        var result = await prices.SetAsync(
            new PriceOverrideInput(request.Symbol, request.Currency, request.Price, request.Reason, request.ExpiresAt),
            OperatorAuthentication.OperatorIdOf(context.User),
            cancellationToken);
        if (result.Invalid || result.Row is not { } row)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        metrics.PriceOverridden();
        return TypedResults.Json(
            new PriceOverrideResponse
            {
                Symbol = row.Symbol,
                Currency = row.Currency,
                Price = PriceWire.Format(row.Price),
                AsOf = row.AsOf,
            },
            ApiJsonContext.Default.PriceOverrideResponse);
    }
}
