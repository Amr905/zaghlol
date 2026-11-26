using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Llm.Plans;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Ask;

/// <summary>The quota snapshot of an answer or a 403 (the lower of the install and account counters; <c>resetsAt</c> is UTC).</summary>
public sealed record LlmQuotaView(int Limit, int Used, int Remaining, DateTimeOffset ResetsAt)
{
    public static LlmQuotaView From(LlmQuotaCheck check) => new(check.Limit, check.Used, check.Remaining, check.ResetsAt);
}

public enum AskPlanKind
{
    /// <summary>200: <see cref="AskPlanResult.Answer"/> is set (counted or not).</summary>
    Answered,

    /// <summary>A gate refused: see <see cref="AskPlanResult.Gate"/>.</summary>
    Refused,

    /// <summary><c>502 UPSTREAM_UNAVAILABLE</c>: the provider timed out, failed or its circuit is open. Not counted.</summary>
    Upstream,

    /// <summary><c>503 LLM_SERVICE_PAUSED</c>: paused after the gates (spend reservation, key, quota store).</summary>
    Paused,

    /// <summary><c>403 LLM_QUOTA_EXHAUSTED</c>: the commit found a counter at its limit (a race over the burst); the plan is withheld.</summary>
    QuotaExhausted,
}

/// <summary>The plan envelope JSON is sensitive (it may echo the question): only the endpoint reveals it, to write the response.</summary>
public sealed record AskPlanAnswer(LlmSensitive<byte[]> PlanJson, bool Counted, LlmQuotaView Quota);

public sealed record AskPlanResult(AskPlanKind Kind, LlmGateResult Gate, AskPlanAnswer? Answer = null, LlmQuotaView? Quota = null);

/// <summary>
/// <c>POST /v1/ask/plan</c> after the body is parsed (ask-llm §1, §4.1; design note in <c>docs/04-tasks/tasks/T-349.md</c>): the shared gate chain, the
/// spend reservation, the provider call with the <c>ask-plan-v1</c> prompt, the validator, the <c>ask_llm_invest</c> gate and the quota commit. The
/// question, the provider reply and the plan are <see cref="LlmSensitive{T}"/>; logs carry fixed codes only and a provider exception's message is dropped.
/// </summary>
public sealed partial class AskPlanService(
    LlmGateChain gates,
    ILlmFeatureGate flags,
    ILlmProviderRegistry registry,
    ILlmPromptCatalog prompts,
    ISpendGuard spend,
    PlanValidator validator,
    ILlmQuotaStore quota,
    ILlmMetrics metrics,
    ILogger<AskPlanService> logger)
{
    public const int MaxOutputTokens = 300;

    private static readonly byte[] FallbackPlan = """{"v":1,"plan":"PL-FALLBACK","p":{"reason":"unsupported"},"t":null}"""u8.ToArray();

    public async Task<AskPlanResult> PlanAsync(LlmGateRequest gate, AskPlanRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(gate);
        ArgumentNullException.ThrowIfNull(request);

        var admitted = await gates.AdmitAsync(gate, cancellationToken).ConfigureAwait(false);
        if (!admitted.IsAdmitted)
        {
            return new AskPlanResult(AskPlanKind.Refused, admitted);
        }

        ILlmProvider provider;
        string systemPrompt;
        try
        {
            provider = registry.Resolve(admitted.ProviderId);
            systemPrompt = prompts.GetSystemPrompt(LlmPromptIds.AskPlanV1);
        }
        catch (LlmConfigurationException)
        {
            // An active id with no adapter, or a missing prompt: nothing can be asked (fail closed, no hint to the caller).
            metrics.Paused(LlmFeature.Ask, "provider_unknown");
            return new AskPlanResult(AskPlanKind.Paused, admitted);
        }

        // Defence in depth behind the phone's scrub; the provider and the validator see only this text.
        var sent = QuestionScrubber.Scrub(request.Question.Reveal());
        var call = new LlmCall(LlmFeature.Ask, LlmPromptIds.AskPlanV1, new LlmSensitive<string>(sent), request.Lang, AskPlanContract.Schema, MaxOutputTokens);
        metrics.Prompt(LlmFeature.Ask, EmbeddedLlmPromptCatalog.HashPrefix(systemPrompt));

        SpendReservation reservation;
        try
        {
            reservation = await spend.ReserveAsync(LlmFeature.Ask, admitted.ProviderId, MaxOutputTokens, cancellationToken).ConfigureAwait(false);
        }
        catch (LlmServicePausedException)
        {
            return new AskPlanResult(AskPlanKind.Paused, admitted);
        }

        LlmResult reply;
        await using (reservation.ConfigureAwait(false))
        {
            var clock = Stopwatch.StartNew();
            try
            {
                reply = await provider.CompleteAsync(call, cancellationToken).ConfigureAwait(false);
            }
            catch (LlmServicePausedException)
            {
                await reservation.SettleAsync(LlmOutcome.Upstream, LlmUsage.None, clock.Elapsed).ConfigureAwait(false);
                metrics.Paused(LlmFeature.Ask, "no_key");
                return new AskPlanResult(AskPlanKind.Paused, admitted);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                // Stop before the provider answered: not counted. The disposed reservation is charged at its worst case.
                throw;
            }
#pragma warning disable CA1031 // Any other provider fault is an upstream failure; the exception (its message may quote the question) is dropped.
            catch (Exception)
#pragma warning restore CA1031
            {
                await reservation.SettleAsync(LlmOutcome.Upstream, LlmUsage.None, clock.Elapsed).ConfigureAwait(false);
                LogProviderFailed(logger, "exception");
                return new AskPlanResult(AskPlanKind.Upstream, admitted);
            }

            await reservation.SettleAsync(reply.Outcome, reply.Usage, clock.Elapsed).ConfigureAwait(false);
        }

        switch (reply.Outcome)
        {
            case LlmOutcome.Timeout:
            case LlmOutcome.Upstream:
                LogProviderFailed(logger, reply.Outcome == LlmOutcome.Timeout ? "timeout" : "upstream");
                return new AskPlanResult(AskPlanKind.Upstream, admitted);
            case LlmOutcome.Refused:
                metrics.Refusal(LlmFeature.Ask, "provider_refused");
                return NotCounted(admitted);
            case LlmOutcome.Invalid:
                return Rejected(admitted, PlanReason.SchemaInvalid);
        }

        // Validator (steps 1 to 6). The reply is parsed here only; every failure is a reason code.
        PlanValidationResult validated;
        try
        {
            using var document = JsonDocument.Parse(reply.Json.Reveal(), new JsonDocumentOptions { MaxDepth = 16, AllowDuplicateProperties = false });
            validated = validator.Validate(document.RootElement, sent, request.Lang);
        }
        catch (JsonException)
        {
            return Rejected(admitted, PlanReason.SchemaInvalid);
        }

        if (!validated.IsValid)
        {
            return Rejected(admitted, validated.Reason ?? PlanReason.SchemaInvalid);
        }

        var name = validated.Plan.GetProperty("plan").GetString() ?? string.Empty;
        if (name == "PL-INVEST" && !await flags.IsOnAsync(LlmGateFeature.AskInvest, gate.Install, gate.Platform, gate.AppVersion, CancellationToken.None).ConfigureAwait(false))
        {
            metrics.Fallback(LlmFeature.Ask);
            return NotCounted(admitted);
        }

        metrics.Plan(LlmFeature.Ask, name);
        if (name == "PL-FALLBACK")
        {
            metrics.Fallback(LlmFeature.Ask);
        }
        else if (name == "PL-REFUSE")
        {
            metrics.Refusal(LlmFeature.Ask, validated.Plan.GetProperty("p").GetProperty("reason").GetString() ?? "other");
        }

        // Commit after the validated reply, never cancelled by a Stop that arrives now (FR-LLM-10).
        var commit = await quota.CommitAsync(LlmFeature.Ask, gate.Install, admitted.Account, gate.RequestId, 1, CancellationToken.None).ConfigureAwait(false);
        var pre = admitted.Quota!;
        switch (commit.Kind)
        {
            case LlmQuotaCheckKind.Unavailable:
                metrics.Paused(LlmFeature.Ask, "quota_unavailable");
                return new AskPlanResult(AskPlanKind.Paused, admitted);
            case LlmQuotaCheckKind.Exhausted:
                metrics.QuotaHit(LlmFeature.Ask);
                return new AskPlanResult(AskPlanKind.QuotaExhausted, admitted, Quota: new LlmQuotaView(pre.Limit, pre.Limit, 0, pre.ResetsAt));
        }

        var view = new LlmQuotaView(pre.Limit, Math.Max(0, pre.Limit - commit.Remaining), commit.Remaining, pre.ResetsAt);
        return new AskPlanResult(AskPlanKind.Answered, admitted, new AskPlanAnswer(new LlmSensitive<byte[]>(Envelope(validated)), true, view));
    }

    private AskPlanResult Rejected(LlmGateResult admitted, PlanReason reason)
    {
        metrics.ValidationFailure(LlmFeature.Ask, reason.Code().ToLowerInvariant());
        metrics.Fallback(LlmFeature.Ask);
        LogPlanRejected(logger, reason);
        return NotCounted(admitted);
    }

    private static AskPlanResult NotCounted(LlmGateResult admitted) =>
        new(AskPlanKind.Answered, admitted, new AskPlanAnswer(new LlmSensitive<byte[]>(FallbackPlan), false, LlmQuotaView.From(admitted.Quota!)));

    /// <summary>The response plan: the validated plan with <c>t</c> replaced by the template that passed step 6, or null.</summary>
    private static byte[] Envelope(PlanValidationResult validated)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteNumber("v", validated.Plan.GetProperty("v").GetInt32());
            writer.WriteString("plan", validated.Plan.GetProperty("plan").GetString());
            writer.WritePropertyName("p");
            validated.Plan.GetProperty("p").WriteTo(writer);
            if (validated.Template is { } template)
            {
                writer.WriteStartObject("t");
                writer.WriteString("lang", template.Lang);
                writer.WriteString("text", template.Text);
                writer.WriteEndObject();
            }
            else
            {
                writer.WriteNull("t");
            }

            writer.WriteEndObject();
        }

        return stream.ToArray();
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Warning, Message = "ask_plan_provider_failed {Kind}")]
    private static partial void LogProviderFailed(ILogger logger, string kind);

    [LoggerMessage(EventId = 2, Level = LogLevel.Information, Message = "ask_plan_rejected {Reason}")]
    private static partial void LogPlanRejected(ILogger logger, PlanReason reason);
}
