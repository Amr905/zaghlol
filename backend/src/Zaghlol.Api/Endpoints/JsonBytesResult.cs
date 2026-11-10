namespace Zaghlol.Api.Endpoints;

/// <summary>
/// A response whose JSON body was already written to bytes (the catalog ops are written by hand so the same ops always give the
/// same bytes). Writes through <c>Response.Body</c>, so the response-signing buffer sees every byte.
/// </summary>
internal sealed class JsonBytesResult(byte[] body, int statusCode = StatusCodes.Status200OK) : IResult
{
    public async Task ExecuteAsync(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);

        httpContext.Response.StatusCode = statusCode;
        httpContext.Response.ContentType = "application/json; charset=utf-8";
        httpContext.Response.ContentLength = body.Length;
        await httpContext.Response.Body.WriteAsync(body, httpContext.RequestAborted);
    }
}
