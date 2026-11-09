using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Flags;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>GET</c> and <c>PUT /admin/v1/flags/{key}</c> (backend-api §4.8, §5), role <c>flags_admin</c>. The routes are not
/// idempotency-keyed: <c>PUT</c> sets absolute state, so a retry is harmless (it only advances the version, and each call is
/// audited). Unknown keys are <c>404</c>; unknown members of the body or of <c>rules</c> are <c>400 UNKNOWN_FIELD</c>.
/// </summary>
internal static class FlagAdminEndpoints
{
    public static IEndpointRouteBuilder MapFlagAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1/flags").RequireOperatorRole(OperatorRoles.FlagsAdmin);
        group.MapGet("/{key}", GetAsync).WithName("adminGetFlag");
        group.MapPut("/{key}", PutAsync).WithName("adminPutFlag");
        return endpoints;
    }

    private static async Task<IResult> GetAsync(
        HttpContext context,
        string key,
        [FromServices] FlagAdminService flags,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (!FlagKeys.HasValidShape(key))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        return await flags.GetAsync(key, cancellationToken) is { } state
            ? StateResult(state)
            : ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound);
    }

    private static async Task<IResult> PutAsync(
        HttpContext context,
        string key,
        [FromServices] FlagAdminService flags,
        [FromServices] ZaghlolMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (!FlagKeys.HasValidShape(key))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        // An unknown key is 404 whatever the body holds, and before the body is read.
        if (!FlagKeys.IsKnown(key))
        {
            return ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound);
        }

        var read = await StrictJson.ReadAsync<FlagUpdateRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        FlagRules? rules = null;
        if (request.Rules is { } dto)
        {
            rules = new FlagRules(dto.Platforms, dto.MinAppVersion, dto.RolloutPercent);
            if (!FlagRulesValidator.IsValid(rules))
            {
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
            }
        }

        var state = await flags.UpdateAsync(key, request.Value, rules, OperatorAuthentication.OperatorIdOf(context.User), cancellationToken);
        if (state is null)
        {
            return ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound);
        }

        metrics.FlagChanged(key);
        return StateResult(state);
    }

    private static IResult StateResult(FlagState state) =>
        TypedResults.Json(
            new FlagStateDto
            {
                Key = state.Key,
                Value = state.Value,
                Rules = new FlagRulesDto
                {
                    Platforms = state.Rules.Platforms,
                    MinAppVersion = state.Rules.MinAppVersion,
                    RolloutPercent = state.Rules.RolloutPercent,
                },
                Version = state.Version,
                UpdatedAt = state.UpdatedAt,
            },
            ApiJsonContext.Default.FlagStateDto);
}
