using Zaghlol.Application.Health;

namespace Zaghlol.Api.Endpoints;

internal sealed record HealthResponse(string Status, DateTimeOffset ServerTime);

internal static class HealthEndpoints
{
    public static IEndpointRouteBuilder MapHealth(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/v1/health", (GetHealthHandler handler, HttpContext httpContext) =>
        {
            httpContext.Response.Headers.CacheControl = "no-store";
            var result = handler.Handle();
            return TypedResults.Ok(new HealthResponse(result.Status, result.ServerTime));
        });

        return endpoints;
    }
}
