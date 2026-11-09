using System.Data.Common;
using System.Globalization;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Api.Problems;

/// <summary>
/// Maps unhandled exceptions to RFC 9457 responses. Exception messages and stack traces are logged
/// server-side only and never reach the client. A KMS outage while signing is <c>503 UPSTREAM_UNAVAILABLE</c> with
/// <c>Retry-After: 5</c> (T-123): the transaction has committed, and a retry with the same Idempotency-Key replays it.
/// </summary>
internal sealed partial class GlobalExceptionHandler(
    IProblemDetailsService problemDetailsService,
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public const int KmsRetryAfterSeconds = 5;

    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var status = exception switch
        {
            BadHttpRequestException badRequest => badRequest.StatusCode,
            KmsUnavailableException => StatusCodes.Status503ServiceUnavailable,

            // The database is down or unreachable (T-124 design note): 503 UPSTREAM_UNAVAILABLE, never 500.
            _ when IsTransientDatabaseFailure(exception) => StatusCodes.Status503ServiceUnavailable,
            _ => StatusCodes.Status500InternalServerError,
        };

        if (status >= StatusCodes.Status500InternalServerError)
        {
            LogUnhandled(logger, exception);
        }

        httpContext.Response.StatusCode = status;

        var problem = new ProblemDetails { Status = status };
        if (exception is KmsUnavailableException)
        {
            httpContext.Response.Headers.RetryAfter = KmsRetryAfterSeconds.ToString(CultureInfo.InvariantCulture);
            problem.Extensions["retryAfterSeconds"] = KmsRetryAfterSeconds;
        }
        else if (status >= StatusCodes.Status500InternalServerError)
        {
            problem.Title = "An unexpected error occurred.";
        }

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = problem,
        });
    }

    /// <summary>
    /// A transient <see cref="DbException"/>, directly or as an inner exception: EF Core queries run through Npgsql's default
    /// execution strategy, which wraps a transient failure in an <see cref="InvalidOperationException"/>, while a directly
    /// opened transaction throws the <c>NpgsqlException</c> itself.
    /// </summary>
    internal static bool IsTransientDatabaseFailure(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
        {
            if (current is DbException { IsTransient: true })
            {
                return true;
            }
        }

        return false;
    }

    [LoggerMessage(Level = LogLevel.Error, Message = "Unhandled exception while processing request")]
    private static partial void LogUnhandled(ILogger logger, Exception exception);
}
