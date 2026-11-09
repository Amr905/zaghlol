using System.Globalization;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Domain;

namespace Zaghlol.Api.Problems;

/// <summary>
/// RFC 9457 answers with a stable <c>code</c> (backend-api §6). Nothing from the request is ever put in them; the
/// customizer adds the correlation id.
/// </summary>
internal static class ApiProblems
{
    /// <summary>A problem result for an endpoint or filter to return.</summary>
    public static ProblemHttpResult Of(int status, string code) =>
        TypedResults.Problem(statusCode: status, extensions: new Dictionary<string, object?> { ["code"] = code });

    /// <summary><c>429 RATE_LIMITED</c> with <c>Retry-After</c> (whole seconds, at least 1) and <c>retryAfterSeconds</c>.</summary>
    public static ProblemHttpResult RateLimited(HttpContext context, int retryAfterSeconds)
    {
        ArgumentNullException.ThrowIfNull(context);

        var seconds = Math.Max(1, retryAfterSeconds);
        context.Response.Headers.RetryAfter = seconds.ToString(CultureInfo.InvariantCulture);
        return TypedResults.Problem(
            statusCode: StatusCodes.Status429TooManyRequests,
            extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.RateLimited, ["retryAfterSeconds"] = seconds });
    }

    /// <summary>Writes a problem directly (middleware, authentication handlers, the rate limiter).</summary>
    public static async ValueTask WriteAsync(HttpContext context, int status, string code, int? retryAfterSeconds = null)
    {
        ArgumentNullException.ThrowIfNull(context);

        context.Response.StatusCode = status;
        var problem = new ProblemDetails { Status = status };
        problem.Extensions["code"] = code;
        if (retryAfterSeconds is int seconds)
        {
            problem.Extensions["retryAfterSeconds"] = seconds;
        }

        var writer = context.RequestServices.GetRequiredService<IProblemDetailsService>();
        await writer.WriteAsync(new ProblemDetailsContext { HttpContext = context, ProblemDetails = problem });
    }
}
