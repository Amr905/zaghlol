using System.Globalization;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm.Categorise.Review;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// The operator review of AI categories (llm-categorise §6), all behind the <c>catalog_editor</c> policy, never cached. The two
/// <c>query</c> operations are POST reads (a body carries the page); they audit nothing. Each <c>resolve</c> leaves exactly one audit
/// row. A promote edits the draft catalog only; a <c>custom</c> user category can't be promoted (400). A problem body is fixed apart
/// from the per-request ids; no merchant text is logged. No route uses the idempotency filter: a repeated decision is a <c>409</c>.
/// </summary>
internal static class LlmCatReviewEndpoints
{
    public static IEndpointRouteBuilder MapLlmCatReviewAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1/llm-cat").RequireOperatorRole(OperatorRoles.CatalogEditor);
        group.MapPost("/corrections/query", QueryCorrectionsAsync).WithName("adminQueryLlmCatCorrections");
        group.MapPost("/corrections/resolve", ResolveCorrectionAsync).WithName("adminResolveLlmCatCorrection");
        group.MapPost("/confirmed/query", QueryConfirmedAsync).WithName("adminQueryLlmCatConfirmed");
        group.MapPost("/confirmed/resolve", ResolveConfirmedAsync).WithName("adminResolveLlmCatConfirmed");
        return endpoints;
    }

    private static async Task<IResult> QueryCorrectionsAsync(HttpContext context, [FromServices] ILlmCatReviewStore store, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var read = await StrictJson.ReadAsync<LlmCatCorrectionsQueryRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!LlmCatReviewWire.IsPage(request.Limit)
            || !LlmCatReviewWire.TryParseCursor(request.Cursor, out var offset)
            || (request.Status is not null && !LlmCatReviewWire.CorrectionStatuses.Contains(request.Status)))
        {
            return Invalid();
        }

        var page = await store.QueryCorrectionsAsync(request.Status, request.Limit ?? LlmCatReviewWire.DefaultLimit, offset, cancellationToken);
        return TypedResults.Json(
            new LlmCatCorrectionPageDto(
                [.. page.Items.Select(g => new LlmCatCorrectionGroupDto(g.MerchantNorm, g.AiCategory, g.UserCategory, g.Votes, Day(g.FirstSeen), Day(g.LastSeen), g.Status))],
                page.NextCursor),
            ApiJsonContext.Default.LlmCatCorrectionPageDto);
    }

    private static async Task<IResult> QueryConfirmedAsync(
        HttpContext context,
        [FromServices] ILlmCatReviewStore store,
        [FromServices] IRemoteConfigService config,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var read = await StrictJson.ReadAsync<LlmCatConfirmedQueryRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!LlmCatReviewWire.IsPage(request.Limit) || !LlmCatReviewWire.TryParseCursor(request.Cursor, out var offset))
        {
            return Invalid();
        }

        var confirmN = (await config.GetAsync(cancellationToken)).GetInt(RemoteConfigKeys.CatConfirmN);
        var page = await store.QueryConfirmedAsync(confirmN, request.Limit ?? LlmCatReviewWire.DefaultLimit, offset, cancellationToken);
        return TypedResults.Json(
            new LlmCatConfirmedPageDto(
                [.. page.Items.Select(g => new LlmCatConfirmedGroupDto(g.MerchantNorm, g.Category, g.Votes, Day(g.FirstSeen), Day(g.LastSeen)))],
                page.NextCursor),
            ApiJsonContext.Default.LlmCatConfirmedPageDto);
    }

    private static async Task<IResult> ResolveCorrectionAsync(HttpContext context, [FromServices] ILlmCatReviewStore store, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var read = await StrictJson.ReadAsync<LlmCatCorrectionResolveRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!LlmCatReviewWire.IsValidMerchant(request.MerchantNorm)
            || !CatalogKeys.IsCategoryCode(request.AiCategory)
            || request.AiCategory == LlmCatReviewWire.Custom
            || !(request.UserCategory == LlmCatReviewWire.Custom || CatalogKeys.IsCategoryCode(request.UserCategory))
            || !LlmCatReviewWire.TryParse(request.Action, out CorrectionAction action)
            || (action == CorrectionAction.Promote && request.UserCategory == LlmCatReviewWire.Custom))
        {
            return Invalid();
        }

        var decision = await store.ResolveCorrectionAsync(
            OperatorAuthentication.OperatorIdOf(context.User), request.MerchantNorm, request.AiCategory, request.UserCategory, action, cancellationToken);
        return Respond(decision, LlmCatReviewWire.Wire(action));
    }

    private static async Task<IResult> ResolveConfirmedAsync(
        HttpContext context,
        [FromServices] ILlmCatReviewStore store,
        [FromServices] IRemoteConfigService config,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var read = await StrictJson.ReadAsync<LlmCatConfirmedResolveRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!LlmCatReviewWire.IsValidMerchant(request.MerchantNorm)
            || !CatalogKeys.IsCategoryCode(request.Category)
            || request.Category == LlmCatReviewWire.Custom
            || !LlmCatReviewWire.TryParse(request.Action, out ConfirmedAction action))
        {
            return Invalid();
        }

        var confirmN = (await config.GetAsync(cancellationToken)).GetInt(RemoteConfigKeys.CatConfirmN);
        var decision = await store.ResolveConfirmedAsync(
            OperatorAuthentication.OperatorIdOf(context.User), request.MerchantNorm, request.Category, action, confirmN, cancellationToken);
        return Respond(decision, LlmCatReviewWire.Wire(action));
    }

    private static IResult Respond(LlmCatDecision decision, string status) => decision.Outcome switch
    {
        LlmCatOutcome.NotFound => ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound),
        LlmCatOutcome.Conflict => ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.AdminConflict),
        _ => TypedResults.Json(new LlmCatResolveResultDto(status, decision.Rows, decision.MerchantId), ApiJsonContext.Default.LlmCatResolveResultDto),
    };

    private static string Day(DateOnly day) => day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static ProblemHttpResult Invalid() => ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
}
