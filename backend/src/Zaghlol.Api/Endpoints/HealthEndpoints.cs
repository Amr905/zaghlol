using Zaghlol.Application.Health;

namespace Zaghlol.Api.Endpoints;

// ServerTime is a UTC DateTime (not DateTimeOffset) so System.Text.Json writes the RFC 3339 "Z" suffix
// that the API contract requires, instead of "+00:00".
internal sealed record HealthResponse(string Status, DateTime ServerTime);

internal static class HealthEndpoints
{
    public static IEndpointRouteBuilder MapHealth(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/v1/health", (GetHealthHandler handler, HttpContext httpContext) =>
        {
            httpContext.Response.Headers.CacheControl = "no-store";
            var result = handler.Handle();
            return TypedResults.Ok(new HealthResponse(result.Status, TruncateToSecondUtc(result.ServerTime)));
        });

        return endpoints;
    }

    private static DateTime TruncateToSecondUtc(DateTimeOffset value)
    {
        var utc = value.UtcDateTime;
        return new DateTime(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), DateTimeKind.Utc);
    }
}
