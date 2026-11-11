using System.Data.Common;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// The Pub/Sub push envelope (Google defines it, so it is open: <c>x-third-party-body: true</c>). Exactly the fields read:
/// <c>message</c> and <c>subscription</c>; no <c>[JsonExtensionData]</c>, <c>JsonElement</c>, <c>JsonNode</c>, <c>object</c> or
/// dictionary member, so <c>attributes</c>, <c>orderingKey</c>, <c>deliveryAttempt</c> and unknown fields are never kept, stored or
/// logged (backend-api §4.5, T-133 AC 4-5).
/// </summary>
internal sealed class PubSubEnvelopeRequest
{
    public PubSubMessageRequest? Message { get; init; }

    public string? Subscription { get; init; }

    public override string ToString() => nameof(PubSubEnvelopeRequest);
}

/// <summary><c>message</c>: only <c>data</c>, <c>messageId</c> and <c>publishTime</c> (never <c>message_id</c>, <c>publish_time</c>).</summary>
internal sealed class PubSubMessageRequest
{
    public string? Data { get; init; }

    public string? MessageId { get; init; }

    public string? PublishTime { get; init; }

    public override string ToString() => nameof(PubSubMessageRequest);
}

/// <summary>
/// The envelope's own context (T-133 design note §1 step 4): unknown members skipped, duplicate members refused, case-sensitive names,
/// strict numbers. The global strict policy (unknown field → 400) does not apply to this body.
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
    NumberHandling = JsonNumberHandling.Strict,
    AllowDuplicateProperties = false,
    PropertyNameCaseInsensitive = false,
    MaxDepth = 16)]
[JsonSerializable(typeof(PubSubEnvelopeRequest))]
internal sealed partial class PubSubEnvelopeJsonContext : JsonSerializerContext;

/// <summary>
/// <c>POST /v1/notifications/google</c> (backend-api §4.5, T-133 design note §1). Order: the <c>notifications-google</c> rate limit;
/// the <see cref="PubSubPushAuthentication"/> scheme, which reads only the <c>Authorization</c> header and answers 401 (503 without
/// Google's keys) before the body is touched; then the body (≤ 256 KB, <c>application/json</c>), the envelope and
/// <see cref="PlayNotificationIngest"/>. <b>After authentication every outcome is 204</b>, including an oversized, non-JSON or
/// malformed body (acknowledged, not stored, counted): a nack would back off the whole Pub/Sub subscription. Only a database failure
/// answers 503, and Pub/Sub redelivers. The request path never calls Play.
/// </summary>
internal static class GoogleNotificationEndpoints
{
    public const string Route = "/v1/notifications/google";

    /// <summary>Seconds Pub/Sub is asked to wait after a database failure.</summary>
    public const int DatabaseRetryAfterSeconds = 10;

    /// <summary>
    /// The endpoint's services: the ingest and its App-login inbox (Infrastructure), the push authentication scheme with Google's key
    /// cache, and the startup check. Call after <c>AddZaghlolHttp</c>, <c>AddZaghlolDatabase</c> with the App role and
    /// <c>AddZaghlolApiTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolGoogleNotifications(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolPlayNotificationIngest();
        services.AddPubSubPushAuthentication();
        services.AddHostedService<GoogleRtdnStartupCheck>();
        return services;
    }

    public static IEndpointRouteBuilder MapGoogleNotifications(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapPost(Route, IngestAsync)
            .WithName("ingestGoogleNotification")
            .WithMetadata(GoogleNotificationRateLimitMetadata.Instance)
            .RequireAuthorization(PubSubPushAuthentication.Policy);
        return endpoints;
    }

    private static async Task<IResult> IngestAsync(
        HttpContext context,
        [FromServices] PlayNotificationIngest ingest,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var body = await StrictJson.ReadBodyAsync(context, StrictJson.MaxNotificationBodyBytes);
        if (body.Error is not null)
        {
            ingest.Malformed();
            return Results.NoContent();
        }

        PubSubEnvelopeRequest? envelope;
        try
        {
            envelope = JsonSerializer.Deserialize(body.Bytes.Span, PubSubEnvelopeJsonContext.Default.PubSubEnvelopeRequest);
        }
        catch (JsonException)
        {
            envelope = null;
        }

        if (envelope?.Message is not { } message)
        {
            ingest.Malformed();
            return Results.NoContent();
        }

        try
        {
            await ingest.IngestAsync(new PubSubPush(message.Data, message.MessageId, message.PublishTime, envelope.Subscription), cancellationToken);
        }
        catch (DbException)
        {
            // Nothing stored: Pub/Sub must redeliver. The exception (never the payload) reaches no log here.
            context.Response.Headers.RetryAfter = DatabaseRetryAfterSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture);
            return ApiProblems.Of(StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable);
        }

        return Results.NoContent();
    }
}

/// <summary>
/// Reads <c>Purchases:Google:Rtdn:*</c> when the host starts (a malformed value stops it in every environment) and, in Production,
/// refuses to start without <c>Audience</c> and <c>PushServiceAccount</c> (T-133 design note §1 step 2): a push endpoint that would
/// answer 401 to Google forever must not ship. Nothing is echoed.
/// </summary>
internal sealed class GoogleRtdnStartupCheck(PlayRtdnSettings settings, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (environment.IsProduction() && !settings.IsConfigured)
        {
            throw new PurchasesConfigurationException("Purchases:Google:Rtdn:Audience and Purchases:Google:Rtdn:PushServiceAccount must be set in Production.");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
