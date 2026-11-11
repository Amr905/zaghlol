using System.Buffers.Text;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
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
/// <c>idem/v2/&lt;installId&gt;/&lt;operation&gt;/&lt;b64u(SHA-256(key))&gt;</c> (S-6), and the signing middleware signs a replay with
/// the current key.
/// <para>
/// T-130 (FU-052 S-2): the key is claimed by a short transaction (a <c>status = 0</c> row with a 60 s lease), the handler runs
/// with no connection held and a hard 30 s timeout (shorter than the lease, so a live handler keeps it), and a second short
/// transaction replaces the claim with the final row. A concurrent request with the same key gets <c>429</c> with
/// <c>Retry-After: 1</c>; a 429, 5xx or exception releases the claim so a retry runs at once; a claim whose lease expired
/// (a crashed request) is taken over. A 2xx body carrying a non-null <c>rotateInstallToken</c> is never stored (S-3).
/// </para>
/// </summary>
internal sealed partial class IdempotencyFilter(IdempotentOperation operation) : IEndpointFilter
{
    public static readonly TimeSpan Ttl = TimeSpan.FromHours(24);

    /// <summary>The hard handler timeout; must stay below the claim lease (<c>IdempotencyStore.Lease</c>, 60 s).</summary>
    public static readonly TimeSpan HandlerTimeout = TimeSpan.FromSeconds(30);

    /// <summary><c>Retry-After</c> of the 503 answered when the handler hit <see cref="HandlerTimeout"/>.</summary>
    public const int TimeoutRetryAfterSeconds = 5;

    public IdempotentOperation Operation { get; } = operation;

    /// <summary>The envelope context that binds a stored body to its install, operation and key (S-6).</summary>
    public static string EnvelopeContext(InstallId installId, IdempotentOperation operation, string idempotencyKey)
    {
        ArgumentNullException.ThrowIfNull(idempotencyKey);
        return "idem/v2/" + installId + "/" + DbEnumMaps.IdempotentOperations.ToDb(operation) + "/"
            + Base64Url.EncodeToString(SHA256.HashData(Encoding.ASCII.GetBytes(idempotencyKey)));
    }

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
        var metrics = services.GetService<ZaghlolMetrics>();
        var installId = InstallTokenAuthentication.InstallIdOf(http.User);
        var bodyHash = SHA256.HashData(body.Bytes.Span);
        var envelopeContext = EnvelopeContext(installId, Operation, key);
        var requestAborted = http.RequestAborted;

        var claim = await store.TryClaimAsync(installId, Operation, key, bodyHash, clock.GetUtcNow(), requestAborted);
        switch (claim.Kind)
        {
            case IdempotencyClaimKind.Stored:
                var stored = claim.Stored!;
                if (!CryptographicOperations.FixedTimeEquals(stored.BodySha256.Span, bodyHash))
                {
                    metrics?.IdempotencyClaim(IdempotencyClaimOutcomes.Reused);
                    return ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.IdempotencyKeyReused);
                }

                metrics?.IdempotencyClaim(IdempotencyClaimOutcomes.Replayed);
                var replay = await cipher.DecryptAsync(stored.ResponseBodyEnc, envelopeContext, requestAborted);
                return new ReplayedResult(stored.Status, replay);

            case IdempotencyClaimKind.InProgress:
                metrics?.IdempotencyClaim(IdempotencyClaimOutcomes.InProgress);
                metrics?.RateLimited("idempotency");
                return ApiProblems.RateLimited(http, 1);

            case IdempotencyClaimKind.NoInstall:
                // Deleted after authentication: the same answer as an unknown token.
                http.Response.Headers.WWWAuthenticate = "Bearer";
                return ApiProblems.Of(StatusCodes.Status401Unauthorized, ErrorCodes.InstallTokenInvalid);
        }

        metrics?.IdempotencyClaim(claim.TakenOver ? IdempotencyClaimOutcomes.TakenOver : IdempotencyClaimOutcomes.Claimed);

        CapturedResult captured;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(requestAborted);
            timeout.CancelAfter(HandlerTimeout);
            var result = await RunHandlerAsync(context, next, timeout.Token);
            if (result is not IResult handlerResult)
            {
                throw new InvalidOperationException("Idempotent endpoints must return an IResult.");
            }

            captured = await CapturedResult.CaptureAsync(http, handlerResult);
        }
        catch (OperationCanceledException) when (!requestAborted.IsCancellationRequested)
        {
            await ReleaseAsync(store, installId, key, claim.ClaimId);
            http.Response.Headers.RetryAfter = TimeoutRetryAfterSeconds.ToString(CultureInfo.InvariantCulture);
            return TypedResults.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.UpstreamUnavailable, ["retryAfterSeconds"] = TimeoutRetryAfterSeconds });
        }
        catch
        {
            await ReleaseAsync(store, installId, key, claim.ClaimId);
            throw;
        }

        var rotation = captured.StatusCode is >= 200 and < 300 && CarriesRotationToken(captured.Body.Span);
        if (!IsStored(captured.StatusCode) || rotation)
        {
            await ReleaseAsync(store, installId, key, claim.ClaimId);
            if (rotation)
            {
                // S-3: a rotated install token must never sit in a replayable store. Idempotent handlers don't rotate (an
                // architecture test); this is the backstop: loud in Development and Testing, logged by type in Production.
                var environment = services.GetRequiredService<IHostEnvironment>();
                if (environment.IsDevelopment() || environment.IsEnvironment("Testing"))
                {
                    throw new InvalidOperationException("An idempotent handler returned rotateInstallToken; it is never stored.");
                }

                LogRotationNotStored(services.GetRequiredService<ILogger<IdempotencyFilter>>());
            }

            return captured;
        }

        bool completed;
        try
        {
            var encrypted = await cipher.EncryptAsync(captured.Body, envelopeContext, CancellationToken.None);
            completed = await store.CompleteAsync(
                installId, Operation, key, claim.ClaimId, bodyHash, captured.StatusCode, encrypted, clock.GetUtcNow() + Ttl, CancellationToken.None);
        }
        catch
        {
            // KMS or database down after the handler: free the key so the app's retry runs again instead of waiting out the lease.
            await ReleaseAsync(store, installId, key, claim.ClaimId);
            throw;
        }

        if (!completed)
        {
            // The lease expired and another request took the key over, or the install was deleted: answer, don't store.
            metrics?.IdempotencyClaim(IdempotencyClaimOutcomes.LeaseLost);
        }

        return captured;
    }

    /// <summary>True when the top-level JSON object has a non-null <c>rotateInstallToken</c> member.</summary>
    internal static bool CarriesRotationToken(ReadOnlySpan<byte> json)
    {
        try
        {
            var reader = new Utf8JsonReader(json);
            if (!reader.Read() || reader.TokenType != JsonTokenType.StartObject)
            {
                return false;
            }

            while (reader.Read() && reader.TokenType == JsonTokenType.PropertyName)
            {
                var isRotation = reader.ValueTextEquals("rotateInstallToken"u8);
                reader.Read();
                if (isRotation && reader.TokenType != JsonTokenType.Null)
                {
                    return true;
                }

                reader.Skip();
            }
        }
        catch (JsonException)
        {
            return false;
        }

        return false;
    }

    /// <summary>
    /// Runs the handler with <paramref name="token"/> as its cancellation token: <c>HttpContext.RequestAborted</c> and any bound
    /// <see cref="CancellationToken"/> argument are swapped for the call and restored after.
    /// </summary>
    private static async ValueTask<object?> RunHandlerAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next, CancellationToken token)
    {
        var http = context.HttpContext;
        var original = http.RequestAborted;
        var swapped = new List<int>();
        for (var i = 0; i < context.Arguments.Count; i++)
        {
            if (context.Arguments[i] is CancellationToken)
            {
                context.Arguments[i] = token;
                swapped.Add(i);
            }
        }

        http.RequestAborted = token;
        try
        {
            return await next(context);
        }
        finally
        {
            http.RequestAborted = original;
            foreach (var i in swapped)
            {
                context.Arguments[i] = original;
            }
        }
    }

    private async Task ReleaseAsync(IIdempotencyStore store, InstallId installId, string key, Guid claimId)
    {
        try
        {
            await store.ReleaseAsync(installId, Operation, key, claimId, CancellationToken.None);
        }
#pragma warning disable CA1031 // Best effort: the 60 s lease releases the key anyway; the original outcome must reach the client.
        catch (Exception)
#pragma warning restore CA1031
        {
        }
    }

    [LoggerMessage(Level = LogLevel.Error, Message = "An idempotent handler returned rotateInstallToken; the result was not stored")]
    private static partial void LogRotationNotStored(ILogger logger);
}

/// <summary>Tag values of <c>zaghlol.idempotency.claim</c> (a fixed set).</summary>
internal static class IdempotencyClaimOutcomes
{
    public const string Claimed = "claimed";
    public const string Replayed = "replayed";
    public const string Reused = "reused";
    public const string InProgress = "in_progress";
    public const string TakenOver = "taken_over";
    public const string LeaseLost = "lease_lost";

    public static IReadOnlyList<string> All { get; } = [Claimed, Replayed, Reused, InProgress, TakenOver, LeaseLost];
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

/// <summary>Marks an endpoint as idempotency-keyed (an architecture test checks its handler never rotates the install token, S-3).</summary>
internal sealed record IdempotentEndpointMetadata(IdempotentOperation Operation);

internal static class IdempotencyEndpointExtensions
{
    /// <summary>Adds <see cref="IdempotencyFilter"/>. Call it after <c>WithTimeNonce</c> on an install-scoped endpoint.</summary>
    public static RouteHandlerBuilder WithIdempotency(this RouteHandlerBuilder builder, IdempotentOperation operation) =>
        builder.WithMetadata(new IdempotentEndpointMetadata(operation)).AddEndpointFilter(new IdempotencyFilter(operation));
}
