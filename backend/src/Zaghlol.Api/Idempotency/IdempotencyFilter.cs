using System.Security.Cryptography;
using Microsoft.AspNetCore.Http.Features;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Installs;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Api.Idempotency;

/// <summary>
/// The idempotency store for <c>verifyPurchase</c> and <c>signIn</c> (backend-api §1, R2-8, R3-6). Runs after install
/// authentication and after <see cref="Signing.TimeNonceFilter"/>. A record is keyed by (install from the token, operation,
/// key) and holds SHA-256 of the body bytes; it is served only when all four match and <c>expires_at &gt; now</c> (clock
/// from <see cref="TimeProvider"/>). A different body is <c>409 IDEMPOTENCY_KEY_REUSED</c>, never the stored body; another
/// install's same key is a new request. Only final results are stored (2xx, 409, 422), never 429 or 5xx, and only after the
/// handler; the stored bytes are the unsigned body, envelope-encrypted with the context
/// <c>idem/v1/&lt;installId&gt;/&lt;operation&gt;</c>, and the signing middleware signs a replay with the current key.
/// Two concurrent requests with one key: the loser gets <c>429</c> with <c>Retry-After: 1</c> and nothing is stored.
/// </summary>
internal sealed class IdempotencyFilter(IdempotentOperation operation) : IEndpointFilter
{
    public static readonly TimeSpan Ttl = TimeSpan.FromHours(24);

    public IdempotentOperation Operation { get; } = operation;

    /// <summary>The envelope context that binds a stored body to its install and operation.</summary>
    public static string EnvelopeContext(InstallId installId, IdempotentOperation operation) =>
        "idem/v1/" + installId + "/" + DbEnumMaps.IdempotentOperations.ToDb(operation);

    /// <summary>Statuses whose result is final and stored (backend-api §1).</summary>
    public static bool IsStored(int status) =>
        status is (>= 200 and < 300) or StatusCodes.Status409Conflict or StatusCodes.Status422UnprocessableEntity;

    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(next);

        var http = context.HttpContext;
        if (!IdempotencyKeys.TryRead(http.Request.Headers, out var key))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var body = await StrictJson.ReadBodyAsync(http);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var services = http.RequestServices;
        var store = services.GetRequiredService<IIdempotencyStore>();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var clock = services.GetRequiredService<TimeProvider>();
        var installId = InstallTokenAuthentication.InstallIdOf(http.User);
        var bodyHash = SHA256.HashData(body.Bytes.Span);
        var envelopeContext = EnvelopeContext(installId, Operation);
        var cancellationToken = http.RequestAborted;

        await using var session = await store.TryBeginAsync(installId, Operation, key, cancellationToken);
        if (session is null)
        {
            services.GetService<ZaghlolMetrics>()?.RateLimited("idempotency");
            return ApiProblems.RateLimited(http, 1);
        }

        var now = clock.GetUtcNow();
        if (await session.FindLiveAsync(now, cancellationToken) is { } stored)
        {
            if (!CryptographicOperations.FixedTimeEquals(stored.BodySha256.Span, bodyHash))
            {
                return ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.IdempotencyKeyReused);
            }

            var replay = await cipher.DecryptAsync(stored.ResponseBodyEnc, envelopeContext, cancellationToken);
            return new ReplayedResult(stored.Status, replay);
        }

        var result = await next(context);
        if (result is not IResult handlerResult)
        {
            throw new InvalidOperationException("Idempotent endpoints must return an IResult.");
        }

        var captured = await CapturedResult.CaptureAsync(http, handlerResult);
        if (IsStored(captured.StatusCode))
        {
            var encrypted = await cipher.EncryptAsync(captured.Body, envelopeContext, cancellationToken);
            await session.SaveAsync(bodyHash, captured.StatusCode, encrypted, now, now + Ttl, cancellationToken);
        }

        return captured;
    }
}

/// <summary>
/// A handler result executed once into memory, so its exact bytes can be stored, then written to the client. It exposes the
/// original result through <see cref="INestedHttpResult"/>, so the time-nonce echo check still sees it.
/// </summary>
internal sealed class CapturedResult : IResult, INestedHttpResult, IStatusCodeHttpResult
{
    private CapturedResult(IResult result, int statusCode, string? contentType, byte[] body)
    {
        Result = result;
        StatusCode = statusCode;
        ContentType = contentType;
        Body = body;
    }

    public IResult Result { get; }

    public int StatusCode { get; }

    public string? ContentType { get; }

    public ReadOnlyMemory<byte> Body { get; }

    int? IStatusCodeHttpResult.StatusCode => StatusCode;

    public static async Task<CapturedResult> CaptureAsync(HttpContext context, IResult result)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(result);

        var original = context.Features.GetRequiredFeature<IHttpResponseBodyFeature>();
        await using var buffer = new MemoryStream();
        var capture = new StreamResponseBodyFeature(buffer);
        context.Features.Set<IHttpResponseBodyFeature>(capture);
        try
        {
            await result.ExecuteAsync(context);
            await capture.CompleteAsync();
        }
        finally
        {
            context.Features.Set(original);
        }

        return new CapturedResult(result, context.Response.StatusCode, context.Response.ContentType, buffer.ToArray());
    }

    public async Task ExecuteAsync(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);

        httpContext.Response.StatusCode = StatusCode;
        httpContext.Response.ContentType = ContentType;
        httpContext.Response.ContentLength = Body.Length;
        if (Body.Length > 0)
        {
            await httpContext.Response.Body.WriteAsync(Body, httpContext.RequestAborted);
        }
    }
}

/// <summary>A stored result served again: the original status and unsigned body bytes (signed again on the way out).</summary>
internal sealed class ReplayedResult(int statusCode, byte[] body) : IResult, IStatusCodeHttpResult
{
    public int StatusCode { get; } = statusCode;

    int? IStatusCodeHttpResult.StatusCode => StatusCode;

    public async Task ExecuteAsync(HttpContext httpContext)
    {
        ArgumentNullException.ThrowIfNull(httpContext);

        httpContext.Response.StatusCode = StatusCode;
        httpContext.Response.ContentType = StatusCode is >= 200 and < 300 ? "application/json; charset=utf-8" : "application/problem+json";
        httpContext.Response.ContentLength = body.Length;
        if (body.Length > 0)
        {
            await httpContext.Response.Body.WriteAsync(body, httpContext.RequestAborted);
        }
    }
}

internal static class IdempotencyEndpointExtensions
{
    /// <summary>Adds <see cref="IdempotencyFilter"/>. Call it after <c>WithTimeNonce</c> on an install-scoped endpoint.</summary>
    public static RouteHandlerBuilder WithIdempotency(this RouteHandlerBuilder builder, IdempotentOperation operation) =>
        builder.AddEndpointFilter(new IdempotencyFilter(operation));
}
