using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Contributions;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// The contribution review queue of backend-api §5 and §5.2, all behind the <c>catalog_editor</c> policy, never cached.
/// <c>GET</c> lists aggregates (never <c>collecting</c> ones: the status filter has no such value). <c>:promote</c> and
/// <c>:reject</c> carry the key in the body and answer an absent key and a <c>collecting</c> key with the same
/// <c>404 NOT_FOUND</c> from one store query. A problem body is fixed apart from the per-request <c>correlationId</c>.
/// No route uses the idempotency filter (FU-052 S-2): a repeated decision is refused with <c>409</c>.
/// </summary>
internal static class ContributionAdminEndpoints
{
    public static IEndpointRouteBuilder MapContributionAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        // The colon is part of the last segment, so the routes are mapped under "/admin/v1" (a group would insert a "/").
        var group = endpoints.MapGroup("/admin/v1").RequireOperatorRole(OperatorRoles.CatalogEditor);
        group.MapGet("/contributions", ListAsync).WithName("adminListContributions");
        group.MapPost("/contributions:promote", PromoteAsync).WithName("adminPromoteContribution");
        group.MapPost("/contributions:reject", RejectAsync).WithName("adminRejectContribution");
        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        HttpContext context,
        [FromServices] IContributionAdminStore store,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var status = ContributionReviewStatus.ReadyForReview;
        if (context.Request.Query.TryGetValue("status", out var values)
            && (values.Count != 1 || !ContributionStatuses.TryParse(values[0], out status)))
        {
            return Invalid();
        }

        // Any other query parameter is refused rather than ignored, like an unknown member of a body.
        if (context.Request.Query.Keys.Any(k => !string.Equals(k, "status", StringComparison.Ordinal)))
        {
            return Invalid();
        }

        var rows = await store.ListAsync(status, cancellationToken);
        return TypedResults.Json(
            new ContributionQueueDto([.. rows.Select(r => new ContributionAggregateDto(
                r.MerchantNorm, r.InstitutionCode, r.CategoryCode, r.DistinctInstalls, ContributionStatuses.Wire(r.Status)))]),
            ApiJsonContext.Default.ContributionQueueDto);
    }

    private static async Task<IResult> PromoteAsync(
        HttpContext context,
        [FromServices] IContributionAdminStore store,
        [FromServices] IContributionMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var read = await StrictJson.ReadAsync<ContributionPromoteRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!ContributionKeys.IsValidKey(request.MerchantNorm, request.InstitutionCode)
            || request.MerchantId is < 1
            || (request.CategoryCode is not null && !CatalogKeys.IsCategoryCode(request.CategoryCode)))
        {
            return Invalid();
        }

        var key = new ContributionKey(request.MerchantNorm, request.InstitutionCode);
        var decision = await store.PromoteAsync(
            OperatorAuthentication.OperatorIdOf(context.User), key, request.MerchantId, request.CategoryCode, cancellationToken);
        if (decision.Outcome == ContributionOutcome.Ok)
        {
            metrics.Event(ContributionEvents.Promoted, 1);
        }

        return Respond(key, decision);
    }

    private static async Task<IResult> RejectAsync(
        HttpContext context,
        [FromServices] IContributionAdminStore store,
        [FromServices] IContributionMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var read = await StrictJson.ReadAsync<ContributionKeyRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!ContributionKeys.IsValidKey(request.MerchantNorm, request.InstitutionCode))
        {
            return Invalid();
        }

        var key = new ContributionKey(request.MerchantNorm, request.InstitutionCode);
        var decision = await store.RejectAsync(OperatorAuthentication.OperatorIdOf(context.User), key, cancellationToken);
        if (decision.Outcome == ContributionOutcome.Ok)
        {
            metrics.Event(ContributionEvents.Rejected, 1);
        }

        return Respond(key, decision);
    }

    private static IResult Respond(ContributionKey key, ContributionDecision decision) => decision.Outcome switch
    {
        ContributionOutcome.NotFound => ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound),
        ContributionOutcome.Conflict => ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.AdminConflict),
        _ => TypedResults.Json(
            new ContributionDecisionDto(key.MerchantNorm, key.InstitutionCode, ContributionStatuses.Wire(decision.Status), decision.MerchantId),
            ApiJsonContext.Default.ContributionDecisionDto),
    };

    private static ProblemHttpResult Invalid() => ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
}
