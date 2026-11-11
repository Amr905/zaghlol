using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// The ASSN V2 body (Apple defines it, so it is open: <c>x-third-party-body: true</c>). Exactly the one field read; no
/// <c>[JsonExtensionData]</c>, <c>JsonElement</c>, <c>JsonNode</c>, <c>object</c> or dictionary member, so nothing else of the body
/// is ever kept, stored or logged (backend-api §4.5, T-134 AC 4).
/// </summary>
internal sealed class AppleNotificationRequest
{
    public string? SignedPayload { get; init; }

    // Never render the payload (debuggers, accidental logging).
    public override string ToString() => nameof(AppleNotificationRequest);
}

/// <summary>
/// The open envelope's own context (T-134 design note §1 step 2): unknown members skipped, duplicate members refused, numbers never
/// read from strings, case-sensitive names. The global strict policy (unknown field → 400) does not apply to this body.
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
    NumberHandling = JsonNumberHandling.Strict,
    AllowDuplicateProperties = false,
    PropertyNameCaseInsensitive = false)]
[JsonSerializable(typeof(AppleNotificationRequest))]
internal sealed partial class AppleNotificationJsonContext : JsonSerializerContext;

/// <summary>
/// <c>POST /v1/notifications/apple</c> (backend-api §4.5, T-134 design note §1). No install or account token is accepted: the JWS
/// chain inside <c>signedPayload</c> authenticates it. Order: 256 KB cap and <c>application/json</c> (413/415); the envelope
/// (400 <c>VALIDATION_FAILED</c>: not a JSON object, duplicate keys, <c>signedPayload</c> missing or not a non-empty string); then
/// <see cref="AppleNotificationIngest"/>, where every failure is a generic <c>401 UNAUTHORIZED</c> that never says which check
/// failed. Stored, duplicate and ignored payloads answer <c>200</c> with no body after the commit; a database failure is a 500 and
/// Apple retries. The request path never calls Apple.
/// </summary>
internal static class AppleNotificationEndpoints
{
    public const string Route = "/v1/notifications/apple";

    public static IEndpointRouteBuilder MapAppleNotifications(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapPost(Route, IngestAsync)
            .WithName("ingestAppleNotification")
            .WithMetadata(AppleNotificationRateLimitMetadata.Instance);
        return endpoints;
    }

    private static async Task<IResult> IngestAsync(
        HttpContext context,
        [FromServices] AppleNotificationIngest ingest,
        [FromServices] IAppleNotificationTelemetry telemetry,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var body = await StrictJson.ReadBodyAsync(context, StrictJson.MaxNotificationBodyBytes);
        if (body.Error is not null)
        {
            telemetry.Ingested(AssnTags.EnvNone, AssnTags.BadRequest);
            return body.Error;
        }

        AppleNotificationRequest? request;
        try
        {
            request = JsonSerializer.Deserialize(body.Bytes.Span, AppleNotificationJsonContext.Default.AppleNotificationRequest);
        }
        catch (JsonException)
        {
            request = null;
        }

        if (request?.SignedPayload is not { Length: > 0 } signedPayload)
        {
            telemetry.Ingested(AssnTags.EnvNone, AssnTags.BadRequest);
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var outcome = await ingest.IngestAsync(new Sensitive<string>(signedPayload), cancellationToken);
        return outcome == AppleIngestOutcome.Unauthorized
            ? ApiProblems.Of(StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized)
            : Results.Ok();
    }
}
