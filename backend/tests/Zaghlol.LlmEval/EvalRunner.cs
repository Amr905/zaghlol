using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Json.Schema;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Plans;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Spend;

namespace Zaghlol.LlmEval;

/// <summary>What happened to one question.</summary>
public enum ItemOutcome
{
    /// <summary>The validated plan is one the set accepts.</summary>
    Pass,

    /// <summary>A valid plan with the wrong plan id.</summary>
    WrongPlan,

    /// <summary>The right plan id, wrong params.</summary>
    WrongParams,

    /// <summary>The validator turned the reply into a fallback (counted as a schema/validator failure; it never reached the phone).</summary>
    ValidatorRejected,

    /// <summary>The provider's reply was unusable (cut off, malformed), refused, or the call failed.</summary>
    ProviderFailed,
}

/// <summary>One scored question. Holds no question text, no reply text, no key.</summary>
public sealed record ItemResult(
    string Id,
    string Group,
    bool IsSafetyItem,
    ItemOutcome Outcome,
    string? ActualPlan,
    string? ValidatorReason,
    string ProviderOutcome,
    bool SchemaInvalid,
    bool SchemaFailurePastValidator,
    LlmUsage Usage,
    decimal Cost,
    TimeSpan Latency)
{
    public bool Passed => Outcome == ItemOutcome.Pass;
}

/// <summary>
/// Runs every question through the real pipeline pieces: <see cref="QuestionScrubber"/>, prompt <c>ask-plan-v1</c> and the schema
/// (<see cref="LlmCall"/>), the adapter (<see cref="ILlmProvider"/>, live or a replay) and <see cref="PlanValidator"/>, in the same order
/// as <c>AskPlanService</c>. Sequential, so latency is per call. Provider exceptions become <see cref="ItemOutcome.ProviderFailed"/>; their
/// messages are dropped (they may quote the question).
/// </summary>
public sealed class EvalRunner(PlanValidator validator)
{
    private static readonly Lazy<JsonSchema> Schema = new(() => JsonSchema.FromText(AskPlanContract.Schema.GetRawText()));

    public async Task<IReadOnlyList<ItemResult>> RunAsync(EvalSet set, ILlmProvider provider, LlmPrices prices, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(set);
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(prices);

        var results = new List<ItemResult>(set.Questions.Count);
        foreach (var question in set.Questions)
        {
            results.Add(await RunOneAsync(question, provider, prices, cancellationToken).ConfigureAwait(false));
        }

        return results;
    }

    private async Task<ItemResult> RunOneAsync(EvalQuestion question, ILlmProvider provider, LlmPrices prices, CancellationToken cancellationToken)
    {
        var sent = QuestionScrubber.Scrub(question.Text);
        var call = new LlmCall(LlmFeature.Ask, LlmPromptIds.AskPlanV1, new LlmSensitive<string>(sent), question.Lang is "en" ? "en" : "ar", AskPlanContract.Schema, AskPlanService.MaxOutputTokens);
        var clock = Stopwatch.StartNew();
        LlmResult reply;
        try
        {
            reply = await provider.CompleteAsync(call, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // Any provider fault is a failed item; the message may quote the question and is dropped.
        catch (Exception ex)
#pragma warning restore CA1031
        {
            return Failed(question, ex is LlmServicePausedException ? "paused" : "exception", LlmUsage.None, clock.Elapsed, prices);
        }

        var latency = clock.Elapsed;
        if (reply.Outcome != LlmOutcome.Ok)
        {
            return Failed(question, reply.Outcome.ToString(), reply.Usage, latency, prices, schemaInvalid: reply.Outcome == LlmOutcome.Invalid);
        }

        JsonElement plan;
        try
        {
            using var doc = JsonDocument.Parse(reply.Json.Reveal());
            plan = doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            return Failed(question, "Invalid", reply.Usage, latency, prices, schemaInvalid: true);
        }

        var validated = validator.Validate(plan, sent, question.Lang is "en" ? "en" : "ar");
        var cost = LlmCostCalculator.Cost(reply.Usage, prices);
        if (!validated.IsValid)
        {
            var reason = validated.Reason?.Code();
            return new ItemResult(question.Id, question.Group, question.IsSafetyItem, ItemOutcome.ValidatorRejected, null, reason, "Ok",
                validated.Reason == PlanReason.SchemaInvalid, false, reply.Usage, cost, latency);
        }

        // Independent re-check of what would reach the phone: a valid plan that violates the schema is the failure the pass rule forbids.
        var pastValidator = !Schema.Value.Evaluate(validated.Plan, new EvaluationOptions { RequireFormatValidation = true }).IsValid;
        var planId = validated.Plan.GetProperty("plan").GetString()!;
        var p = JsonNode.Parse(validated.Plan.GetProperty("p").GetRawText());
        var outcome = question.Expect.Any(e => PlanMatcher.Matches(e, planId, p))
            ? ItemOutcome.Pass
            : question.Expect.Any(e => e.Plan == planId) ? ItemOutcome.WrongParams : ItemOutcome.WrongPlan;
        return new ItemResult(question.Id, question.Group, question.IsSafetyItem, outcome, planId, null, "Ok", false, pastValidator, reply.Usage, cost, latency);
    }

    private static ItemResult Failed(EvalQuestion question, string providerOutcome, LlmUsage usage, TimeSpan latency, LlmPrices prices, bool schemaInvalid = false) =>
        new(question.Id, question.Group, question.IsSafetyItem, ItemOutcome.ProviderFailed, null, null, providerOutcome, schemaInvalid, false, usage, LlmCostCalculator.Cost(usage, prices), latency);
}
