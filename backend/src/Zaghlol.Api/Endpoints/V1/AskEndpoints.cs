using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/ask/plan</c> (ask-llm §4.1, T-349). Order: network bucket, install token and <c>Zaghlol-App</c> (the pipeline and the group), the
/// body read once (415, 413; 4 KB, 16 KB only with an <c>attestationObject</c>), the closed parse (<c>UNKNOWN_FIELD</c>), the body binding, then
/// <see cref="AskPlanService"/> (flag, spend pause, consent, buckets, attestation, quota, provider, validator, commit). The answer is not signed and
/// not cached. The question, the plan and the template never reach a log, a metric, a problem body or the database; every problem carries a fixed code
/// and only the documented members (<c>quota</c>, <c>providerId</c>, <c>retryAfterSeconds</c>).
/// </summary>
internal static class AskEndpoints
{
    public const string Route = "/ask/plan";

    private const int RetryAfterSeconds = 10;

    public static IEndpointRouteBuilder MapAsk(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapInstallScoped()
            .MapPost(Route, PlanAsync)
            .WithName("askPlan");
        return endpoints;
    }

    private static async Task<IResult> PlanAsync(
        HttpContext context,
        [FromServices] AskPlanService service,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var body = await StrictJson.ReadBodyAsync(context, AskPlanRequestParser.MaxBodyBytesWithAttestationObject);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var parsed = AskPlanRequestParser.Parse(body.Bytes);
        using var document = parsed.Document;
        if (parsed.Request is not { } request || document is null)
        {
            return ApiProblems.Of(
                StatusCodes.Status400BadRequest,
                parsed.Failure == AskParseFailure.UnknownField ? ErrorCodes.UnknownField : ErrorCodes.ValidationFailed);
        }

        if (!request.HasAttestationObject && body.Bytes.Length > AskPlanRequestParser.MaxBodyBytes)
        {
            return ApiProblems.Of(StatusCodes.Status413PayloadTooLarge, ErrorCodes.PayloadTooLarge);
        }

        var install = InstallTokenAuthentication.InstallIdOf(context.User);
        if (LlmBinding.BodyHash(LlmFeature.Ask, install, document.RootElement) is not { } bodyHash)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        // The header was validated by the group filter; the platform is its prefix (ask-llm §4.1: platform and version come from Zaghlol-App).
        var header = context.Request.Headers[SyncEndpoints.AppHeader].ToString();
        SyncEndpoints.TryReadAppVersion(context.Request.Headers[SyncEndpoints.AppHeader], out var appVersion);
        var platform = header.StartsWith("ios/", StringComparison.Ordinal) ? "ios" : "android";

        var gate = new LlmGateRequest(
            LlmFeature.Ask,
            install,
            platform,
            appVersion,
            SyncEndpoints.AccountHeader(context),
            ClientNetwork.Of(context.Connection.RemoteIpAddress),
            request.ConsentProvider,
            request.ConsentVersion,
            request.RequestId,
            bodyHash,
            request.Proof);

        var result = await service.PlanAsync(gate, request, cancellationToken);
        switch (result.Kind)
        {
            case AskPlanKind.Answered:
                return new JsonBytesResult(Response(clock.GetUtcNow(), result.Answer!));
            case AskPlanKind.Upstream:
                return Unavailable(context, StatusCodes.Status502BadGateway, ErrorCodes.UpstreamUnavailable);
            case AskPlanKind.Paused:
                return Paused();
            case AskPlanKind.QuotaExhausted:
                return QuotaExhausted(result.Quota!);
            default:
                return Refused(context, result.Gate);
        }
    }

    internal static ProblemHttpResult Refused(HttpContext context, LlmGateResult gate) => gate.Outcome switch
    {
        LlmGateOutcome.Paused => Paused(),
        LlmGateOutcome.ConsentRequired => TypedResults.Problem(
            statusCode: StatusCodes.Status409Conflict,
            type: "https://zaghlol.app/problems/llm-consent-required",
            title: "Consent for the active provider is required.",
            extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.LlmConsentRequired, ["providerId"] = gate.ProviderId }),
        LlmGateOutcome.RateLimited => ApiProblems.RateLimited(context, gate.RetryAfterSeconds),
        LlmGateOutcome.AttestationFailed => ApiProblems.Of(StatusCodes.Status422UnprocessableEntity, ErrorCodes.DeviceAttestationFailed),
        LlmGateOutcome.AttestationUnavailable => Unavailable(context, StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable),
        LlmGateOutcome.QuotaExhausted => QuotaExhausted(LlmQuotaView.From(gate.Quota!)),
        _ => ApiProblems.Of(StatusCodes.Status500InternalServerError, ErrorCodes.Internal),
    };

    internal static ProblemHttpResult Paused() => TypedResults.Problem(
        statusCode: StatusCodes.Status503ServiceUnavailable,
        type: "https://zaghlol.app/problems/llm-service-paused",
        title: "The helper is paused.",
        extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.LlmServicePaused });

    private static ProblemHttpResult QuotaExhausted(LlmQuotaView quota) => TypedResults.Problem(
        statusCode: StatusCodes.Status403Forbidden,
        type: "https://zaghlol.app/problems/llm-quota-exhausted",
        title: "Monthly question limit reached.",
        extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.LlmQuotaExhausted, ["quota"] = QuotaObject(quota) });

    internal static ProblemHttpResult Unavailable(HttpContext context, int status, string code)
    {
        context.Response.Headers.RetryAfter = RetryAfterSeconds.ToString(CultureInfo.InvariantCulture);
        return TypedResults.Problem(
            statusCode: status,
            extensions: new Dictionary<string, object?> { ["code"] = code, ["retryAfterSeconds"] = RetryAfterSeconds });
    }

    internal static Dictionary<string, object?> QuotaObject(LlmQuotaView quota) => new()
    {
        ["limit"] = quota.Limit,
        ["used"] = quota.Used,
        ["remaining"] = quota.Remaining,
        ["resetsAt"] = Utc(quota.ResetsAt),
    };

    internal static string Utc(DateTimeOffset value) => value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    /// <summary>{ serverTime, plan, counted, quota }. The plan bytes are revealed only here, to be written to the caller who sent the question.</summary>
    private static byte[] Response(DateTimeOffset now, AskPlanAnswer answer)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteString("serverTime", Utc(now));
            writer.WritePropertyName("plan");
            writer.WriteRawValue(answer.PlanJson.Reveal());
            writer.WriteBoolean("counted", answer.Counted);
            writer.WriteStartObject("quota");
            writer.WriteNumber("limit", answer.Quota.Limit);
            writer.WriteNumber("used", answer.Quota.Used);
            writer.WriteNumber("remaining", answer.Quota.Remaining);
            writer.WriteString("resetsAt", Utc(answer.Quota.ResetsAt));
            writer.WriteEndObject();
            writer.WriteEndObject();
        }

        return stream.ToArray();
    }
}
