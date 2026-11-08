using System.Diagnostics;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Routing;

namespace Zaghlol.Api.Observability;

/// <summary>
/// One <c>request completed</c> event per request with <c>method, route, status, durationMs, code, installHash</c>. It
/// replaces <c>UseSerilogRequestLogging()</c>, which logs the raw <c>RequestPath</c>. <c>route</c> is the endpoint's route
/// template or <c>unmatched</c>, never the path, the query string or a header. Runs outermost, so it sees the final status
/// after the exception handler and status pages.
/// </summary>
internal sealed partial class RequestLogMiddleware(RequestDelegate next, ILogger<RequestLogMiddleware> logger)
{
    public const string Unmatched = "unmatched";
    public const int ClientClosedRequest = 499;

    public async Task InvokeAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var started = Stopwatch.GetTimestamp();
        var failed = false;
        try
        {
            await next(context);
        }
        catch
        {
            failed = true;
            throw;
        }
        finally
        {
            Log(context, failed, started);
        }
    }

    private static string? Item(HttpContext context, string key) =>
        context.Items.TryGetValue(key, out var value) ? value as string : null;

    private void Log(HttpContext context, bool failed, long started)
    {
        var status = failed ? StatusCodes.Status500InternalServerError : context.Response.StatusCode;

        // A client that hung up is not a server error (499, as nginx logs it).
        if (status >= StatusCodes.Status500InternalServerError && context.RequestAborted.IsCancellationRequested)
        {
            status = ClientClosedRequest;
        }

        // The exception handler clears the endpoint before it writes the response; it keeps the original in its feature.
        var endpoint = context.Features.Get<IExceptionHandlerFeature>()?.Endpoint ?? context.GetEndpoint();
        var route = (endpoint as RouteEndpoint)?.RoutePattern.RawText ?? Unmatched;
        var durationMs = (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds;
        var code = Item(context, RequestLogItems.ProblemCode);
        var installHash = Item(context, RequestLogItems.InstallHash);

        // The fields travel as scope properties, so the message stays the constant "request completed".
        var fields = new Dictionary<string, object>
        {
            ["Method"] = context.Request.Method,
            ["Route"] = route,
            ["Status"] = status,
            ["DurationMs"] = durationMs,
        };
        if (code is not null)
        {
            fields["Code"] = code;
        }

        if (installHash is not null)
        {
            fields["InstallHash"] = installHash;
        }

        using (logger.BeginScope(fields))
        {
            if (status >= StatusCodes.Status500InternalServerError)
            {
                CompletedWithServerError(logger);
            }
            else
            {
                Completed(logger);
            }
        }
    }

    [LoggerMessage(EventId = 1000, Level = LogLevel.Information, Message = "request completed")]
    private static partial void Completed(ILogger logger);

    [LoggerMessage(EventId = 1001, Level = LogLevel.Error, Message = "request completed")]
    private static partial void CompletedWithServerError(ILogger logger);
}
