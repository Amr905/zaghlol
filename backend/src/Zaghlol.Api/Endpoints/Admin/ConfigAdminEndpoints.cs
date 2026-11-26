using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Config;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>GET /admin/v1/config</c>, <c>GET</c> and <c>PUT /admin/v1/config/{key}</c> (ask-llm.md section 4.5), role <c>flags_admin</c>.
/// <c>PUT</c> sets absolute state, so a retry is harmless (it only advances the version, and each call is audited). Unknown keys are
/// <c>404</c> before the body is read; a value of the wrong type or outside its range is <c>400 VALIDATION_FAILED</c> and is never echoed.
/// </summary>
internal static class ConfigAdminEndpoints
{
    public static IEndpointRouteBuilder MapConfigAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1/config").RequireOperatorRole(OperatorRoles.FlagsAdmin);
        group.MapGet(string.Empty, ListAsync).WithName("adminListConfig");
        group.MapGet("/{key}", GetAsync).WithName("adminGetConfig");
        group.MapPut("/{key}", PutAsync).WithName("adminPutConfig");
        return endpoints;
    }

    private static async Task<IResult> ListAsync(HttpContext context, [FromServices] RemoteConfigAdminService config, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var items = await config.ListAsync(cancellationToken);
        return TypedResults.Json(new ConfigListDto { Items = items.Select(ToDto).ToList() }, ApiJsonContext.Default.ConfigListDto);
    }

    private static async Task<IResult> GetAsync(HttpContext context, string key, [FromServices] RemoteConfigAdminService config, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (!RemoteConfigKeys.HasValidShape(key))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        return await config.GetAsync(key, cancellationToken) is { } state
            ? StateResult(state)
            : ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound);
    }

    private static async Task<IResult> PutAsync(HttpContext context, string key, [FromServices] RemoteConfigAdminService config, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (!RemoteConfigKeys.HasValidShape(key))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        // An unknown key is 404 whatever the body holds, and before the body is read.
        if (RemoteConfigKeys.Find(key) is null)
        {
            return ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound);
        }

        var read = await StrictJson.ReadAsync<ConfigUpdateRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        var result = await config.SetAsync(key, request.Value, OperatorAuthentication.OperatorIdOf(context.User), cancellationToken);
        return result.Status switch
        {
            ConfigSetStatus.Ok => StateResult(result.State!),
            ConfigSetStatus.UnknownKey => ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound),
            _ => ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed),
        };
    }

    private static JsonHttpResult<ConfigStateDto> StateResult(RemoteConfigState state) =>
        TypedResults.Json(ToDto(state), ApiJsonContext.Default.ConfigStateDto);

    private static ConfigStateDto ToDto(RemoteConfigState state) => new()
    {
        Key = state.Key,
        Value = state.Value,
        IsDefault = state.IsDefault,
        Version = state.Version,
        UpdatedAt = state.UpdatedAt,
    };
}
