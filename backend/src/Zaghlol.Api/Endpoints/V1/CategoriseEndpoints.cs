using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Llm.Categorise;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/categorise</c> (llm-categorise §3, T-352). The same order as <see cref="AskEndpoints"/>: network bucket, install token and <c>Zaghlol-App</c>,
/// the body read once (415, 413; 4 KB, 16 KB only with an <c>attestationObject</c>), the closed parse (<c>UNKNOWN_FIELD</c>, 400 above
/// <c>cat.batch_max</c> merchants), the body binding, then <see cref="CategoriseService"/>. Quota is a per-merchant status, never a 403. The answer is not
/// signed and not cached. The merchant names are written only into the response to the phone that sent them; they never reach a log, a metric, a
/// problem body or any table other than the answer cache.
/// </summary>
internal static class CategoriseEndpoints
{
    public const string Route = "/categorise";

    public static IEndpointRouteBuilder MapCategorise(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapInstallScoped()
            .MapPost(Route, CategoriseAsync)
            .WithName("categorise");
        return endpoints;
    }

    private static async Task<IResult> CategoriseAsync(
        HttpContext context,
        [FromServices] CategoriseService service,
        [FromServices] IRemoteConfigService config,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var body = await StrictJson.ReadBodyAsync(context, AskPlanRequestParser.MaxBodyBytesWithAttestationObject);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var batchMax = (await config.GetAsync(cancellationToken)).GetInt(RemoteConfigKeys.CatBatchMax);
        var parsed = CategoriseRequestParser.Parse(body.Bytes, batchMax);
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
        if (LlmBinding.BodyHash(LlmFeature.Categorise, install, document.RootElement) is not { } bodyHash)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var header = context.Request.Headers[SyncEndpoints.AppHeader].ToString();
        SyncEndpoints.TryReadAppVersion(context.Request.Headers[SyncEndpoints.AppHeader], out var appVersion);
        var platform = header.StartsWith("ios/", StringComparison.Ordinal) ? "ios" : "android";

        var gate = new LlmGateRequest(
            LlmFeature.Categorise,
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

        var result = await service.CategoriseAsync(gate, request, cancellationToken);
        return result.Kind switch
        {
            CategoriseKind.Answered => new JsonBytesResult(Response(clock.GetUtcNow(), result.Answer!)),
            CategoriseKind.Upstream => AskEndpoints.Unavailable(context, StatusCodes.Status502BadGateway, ErrorCodes.UpstreamUnavailable),
            CategoriseKind.Paused => AskEndpoints.Paused(),
            _ => AskEndpoints.Refused(context, result.Gate),
        };
    }

    /// <summary>{ serverTime, counted, results, quota }: one result per requested merchant, in request order.</summary>
    private static byte[] Response(DateTimeOffset now, CategoriseAnswer answer)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteString("serverTime", AskEndpoints.Utc(now));
            writer.WriteNumber("counted", answer.Counted);
            writer.WriteStartArray("results");
            foreach (var item in answer.Items)
            {
                writer.WriteStartObject();
                writer.WriteString("merchant", item.Merchant.Reveal());
                writer.WriteString("status", item.Status);
                WriteOrNull(writer, "category", item.Category);
                if (item.Confidence is { } confidence)
                {
                    writer.WriteNumber("confidence", confidence);
                }
                else
                {
                    writer.WriteNull("confidence");
                }

                WriteOrNull(writer, "source", item.Source);
                writer.WriteEndObject();
            }

            writer.WriteEndArray();
            writer.WriteStartObject("quota");
            writer.WriteNumber("limit", answer.Quota.Limit);
            writer.WriteNumber("used", answer.Quota.Used);
            writer.WriteNumber("remaining", answer.Quota.Remaining);
            writer.WriteString("resetsAt", AskEndpoints.Utc(answer.Quota.ResetsAt));
            writer.WriteEndObject();
            writer.WriteEndObject();
        }

        return stream.ToArray();
    }

    private static void WriteOrNull(Utf8JsonWriter writer, string name, string? value)
    {
        if (value is null)
        {
            writer.WriteNull(name);
        }
        else
        {
            writer.WriteString(name, value);
        }
    }
}
