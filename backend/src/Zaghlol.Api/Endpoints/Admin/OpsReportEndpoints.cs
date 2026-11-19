using System.Globalization;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Reports;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// The operator read side of backend-api §5 (BUG-003): <c>GET /admin/v1/bank-requests</c> (<c>catalog_editor</c>; institutions
/// ranked by distinct installs, at most 500) and <c>GET /admin/v1/metrics/daily-active</c> (any operator role; <c>days</c> 1 to 90,
/// default 14, anything else including a repeated or unknown query parameter is <c>400 VALIDATION_FAILED</c>). Aggregates only,
/// never cached.
/// </summary>
internal static class OpsReportEndpoints
{
    public static IEndpointRouteBuilder MapOpsReports(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1");
        group.MapGet("/bank-requests", BankRequestsAsync)
            .RequireOperatorRole(OperatorRoles.CatalogEditor)
            .WithName("adminListBankRequests");
        group.MapGet("/metrics/daily-active", DailyActiveAsync)
            .RequireOperatorRole(OperatorRoles.Any)
            .WithName("adminDailyActive");
        return endpoints;
    }

    private static async Task<IResult> BankRequestsAsync(
        HttpContext context,
        [FromServices] IOpsReportStore store,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (context.Request.Query.Count > 0)
        {
            return Invalid();
        }

        var rows = await store.RankBankRequestsAsync(cancellationToken);
        return TypedResults.Json(
            new BankRequestRankingDto([.. rows.Select(r => new BankRequestRankDto(
                r.InstitutionName, r.Country, r.Channel, r.Count, Utc(r.LastRequestedAt)))]),
            ApiJsonContext.Default.BankRequestRankingDto);
    }

    private static async Task<IResult> DailyActiveAsync(
        HttpContext context,
        [FromServices] IOpsReportStore store,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var days = OpsReportRules.DefaultDailyActiveDays;
        foreach (var (key, values) in context.Request.Query)
        {
            if (!string.Equals(key, "days", StringComparison.Ordinal)
                || values.Count != 1
                || !TryParseDays(values[0], out days))
            {
                return Invalid();
            }
        }

        var rows = await store.DailyActiveAsync(days, cancellationToken);
        return TypedResults.Json(
            new DailyActiveMetricsDto([.. rows.Select(r => new DailyActiveDayDto(
                r.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), r.ActiveInstalls))]),
            ApiJsonContext.Default.DailyActiveMetricsDto);
    }

    /// <summary>ASCII digits only (no sign, no space, no other-script digits), 1 to 90.</summary>
    private static bool TryParseDays(string? text, out int days)
    {
        days = 0;
        return text is { Length: >= 1 and <= 2 }
            && text.All(char.IsAsciiDigit)
            && int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out days)
            && days is >= OpsReportRules.MinDailyActiveDays and <= OpsReportRules.MaxDailyActiveDays;
    }

    private static string Utc(DateTimeOffset instant) =>
        instant.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    private static ProblemHttpResult Invalid() => ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
}
