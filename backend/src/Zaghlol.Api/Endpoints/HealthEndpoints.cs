using Microsoft.AspNetCore.Http.HttpResults;
using Zaghlol.Application.Health;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints;

// ServerTime is a UTC DateTime (not DateTimeOffset) so System.Text.Json writes the RFC 3339 "Z" suffix
// that the API contract requires, instead of "+00:00".
internal sealed record HealthResponse(string Status, DateTime ServerTime);

internal static class HealthEndpoints
{
    public static IEndpointRouteBuilder MapHealth(this IEndpointRouteBuilder endpoints)
    {
        // Readiness (FU-003): 503 UPSTREAM_UNAVAILABLE while the database is unreachable. Liveness is a process check.
        endpoints.MapGet(
            "/v1/health",
            async Task<Results<Ok<HealthResponse>, ProblemHttpResult>> (
                GetHealthHandler handler,
                HttpContext httpContext,
                CancellationToken cancellationToken) =>
            {
                httpContext.Response.Headers.CacheControl = "no-store";
                var result = await handler.HandleAsync(cancellationToken);
                if (!result.Ready)
                {
                    return TypedResults.Problem(
                        statusCode: StatusCodes.Status503ServiceUnavailable,
                        extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.UpstreamUnavailable });
                }

                return TypedResults.Ok(new HealthResponse(GetHealthHandler.OkStatus, TruncateToSecondUtc(result.ServerTime)));
            });

        return endpoints;
    }

    private static DateTime TruncateToSecondUtc(DateTimeOffset value)
    {
        var utc = value.UtcDateTime;
        return new DateTime(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), DateTimeKind.Utc);
    }
}
