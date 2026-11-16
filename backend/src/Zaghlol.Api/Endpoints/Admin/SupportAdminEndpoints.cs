using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>POST /admin/v1/support/entitlement:lookup</c> (backend-api §5.2, T-136), role <c>support_viewer</c>. The key travels
/// only in the body: <c>{installId}</c> or <c>{email}</c>, exactly one. Any other member is <c>400 UNKNOWN_FIELD</c>; both,
/// neither, a duplicate, a non-string or a malformed key is <c>400 VALIDATION_FAILED</c>, and no problem body echoes it.
/// Every call is audited (<c>support_lookup</c>), counts <c>zaghlol.support.lookup</c> and draws on the per-operator lookup
/// bucket. An e-mail that matches no account answers <c>200</c> with no purchases after the same queries as a match.
/// <para>
/// T-186: <c>POST /admin/v1/support/seat:move</c> and <c>purchase:detach</c> (<c>support_agent</c>), <c>purchase:unfreeze</c>
/// (<c>support_lead</c>). Strict bodies (<see cref="SupportWriteBodies"/>); the order ID is a <see cref="Sensitive{T}"/> that only the
/// ownership check reads. Answers: <c>404 NOT_FOUND</c>, <c>409 ADMIN_CONFLICT</c>, <c>422 OWNERSHIP_CHECK_FAILED</c>,
/// <c>503 UPSTREAM_UNAVAILABLE</c>; every call is audited by <see cref="SupportActionService"/>. Never idempotency-keyed.
/// </para>
/// </summary>
internal static class SupportAdminEndpoints
{
    public static IEndpointRouteBuilder MapSupportAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1/support");
        group.MapPost("/entitlement:lookup", LookupAsync)
            .RequireOperatorRole(OperatorRoles.SupportViewer)
            .WithMetadata(SupportLookupRateLimitMetadata.Instance)
            .WithName("adminLookupEntitlement");
        group.MapPost("/seat:move", MoveAsync)
            .RequireOperatorRole(OperatorRoles.SupportAgent)
            .WithName("adminMoveSeat");
        group.MapPost("/purchase:detach", DetachAsync)
            .RequireOperatorRole(OperatorRoles.SupportAgent)
            .WithName("adminDetachPurchase");
        group.MapPost("/purchase:unfreeze", UnfreezeAsync)
            .RequireOperatorRole(OperatorRoles.SupportLead)
            .WithName("adminUnfreezePurchase");
        return endpoints;
    }

    private static async Task<IResult> MoveAsync(HttpContext context, [FromServices] SupportActionService service, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var (command, error) = SupportWriteBodies.ParseMove(body.Bytes, OperatorAuthentication.OperatorIdOf(context.User));
        if (command is null)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, error!);
        }

        var result = await service.MoveSeatAsync(command, cancellationToken);
        return Answer(context, result, v => TypedResults.Json(
            new SupportSeatMoveResultDto(v.PurchaseId, v.Moved, v.Attached, v.NextMoveAt, v.AuditId), ApiJsonContext.Default.SupportSeatMoveResultDto));
    }

    private static async Task<IResult> DetachAsync(HttpContext context, [FromServices] SupportActionService service, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var (command, error) = SupportWriteBodies.ParseDetach(body.Bytes, OperatorAuthentication.OperatorIdOf(context.User));
        if (command is null)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, error!);
        }

        var result = await service.DetachAsync(command, cancellationToken);
        return Answer(context, result, v => TypedResults.Json(
            new SupportDetachResultDto(v.PurchaseId, v.Detached, v.AuditId), ApiJsonContext.Default.SupportDetachResultDto));
    }

    private static async Task<IResult> UnfreezeAsync(HttpContext context, [FromServices] SupportActionService service, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var (command, error) = SupportWriteBodies.ParseUnfreeze(body.Bytes, OperatorAuthentication.OperatorIdOf(context.User));
        if (command is null)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, error!);
        }

        var result = await service.UnfreezeAsync(command, cancellationToken);
        return Answer(context, result, v => TypedResults.Json(
            new SupportUnfreezeResultDto(v.PurchaseId, v.Unfrozen, v.AuditId), ApiJsonContext.Default.SupportUnfreezeResultDto));
    }

    private static IResult Answer<T>(HttpContext context, SupportActionResult<T> result, Func<T, IResult> ok)
        where T : class
    {
        switch (result.Status)
        {
            case SupportActionStatus.Ok:
                return ok(result.Value!);
            case SupportActionStatus.NotFound:
                return ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound);
            case SupportActionStatus.Conflict:
                return ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.AdminConflict);
            case SupportActionStatus.OwnershipFailed:
                return ApiProblems.Of(StatusCodes.Status422UnprocessableEntity, ErrorCodes.OwnershipCheckFailed);
            default:
                context.Response.Headers.RetryAfter = StoreRetryAfterSeconds;
                return ApiProblems.Of(StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable);
        }
    }

    private const string StoreRetryAfterSeconds = "30";

    private static async Task<IResult> LookupAsync(
        HttpContext context,
        [FromServices] ISupportLookupStore store,
        [FromServices] ZaghlolMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var key = SupportLookupKey.Parse(body.Bytes);
        if (key.Error is { } code)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, code);
        }

        var operatorId = OperatorAuthentication.OperatorIdOf(context.User);
        var view = key.Install is { } installId
            ? await store.LookupInstallAsync(operatorId, installId, cancellationToken)
            : await store.LookupEmailAsync(operatorId, key.Email!, cancellationToken);
        metrics.SupportLookup(OperatorRoles.SupportViewer);
        return TypedResults.Json(ToDto(view), ApiJsonContext.Default.SupportEntitlementDto);
    }

    private static SupportEntitlementDto ToDto(SupportEntitlementView view) => new(
        view.Status,
        [.. view.Purchases.Select(p => new SupportPurchaseDto(
            p.PurchaseId,
            p.Plan,
            p.State,
            p.Store,
            p.Seat,
            p.AccountLinked,
            p.LinkedBy,
            p.LastMovedAt,
            p.NextMoveAt,
            p.PendingClaimants,
            p.BuyingInstallSilent,
            p.IsBuyingInstall,
            p.DisputeFrozenUntil,
            p.RebindsLast30Days))],
        view.Plan,
        view.Exp,
        view.GraceUntil);
}

/// <summary>The parsed lookup body: an install ID, a normalised e-mail, or the error code to answer.</summary>
internal readonly record struct SupportLookupKey(InstallId? Install, string? Email, string? Error)
{
    public const string InstallIdMember = "installId";
    public const string EmailMember = "email";

    private const int MaxDepth = 4;

    // Never rendered with the e-mail (debuggers, accidental logging).
    public override string ToString() => nameof(SupportLookupKey);

    public static SupportLookupKey Parse(ReadOnlyMemory<byte> utf8)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, new JsonDocumentOptions { MaxDepth = MaxDepth });
        }
        catch (JsonException)
        {
            return Invalid;
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return Invalid;
            }

            var members = root.EnumerateObject().ToList();
            if (members.Exists(m => m.Name is not (InstallIdMember or EmailMember)))
            {
                return new SupportLookupKey(null, null, ErrorCodes.UnknownField);
            }

            if (members.Count != 1 || members[0].Value.ValueKind != JsonValueKind.String)
            {
                return Invalid;
            }

            var member = members[0];
            if (string.Equals(member.Name, InstallIdMember, StringComparison.Ordinal))
            {
                return InstallId.TryParse(member.Value.GetString(), out var installId)
                    ? new SupportLookupKey(installId, null, null)
                    : Invalid;
            }

            return SupportEmail.TryNormalize(member.Value.GetString(), out var email)
                ? new SupportLookupKey(null, email, null)
                : Invalid;
        }
    }

    private static SupportLookupKey Invalid => new(null, null, ErrorCodes.ValidationFailed);
}
