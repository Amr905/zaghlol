namespace Zaghlol.Application.Llm.Spend;

/// <summary>
/// Counters only (FR-LLM-62). Every tag value comes from a fixed set (feature, outcome, plan name, reason code, bucket name, provider id
/// pattern); nothing derived from a question, an install or an account ever becomes a tag. Cost is a <see cref="decimal"/> counter.
/// </summary>
public interface ILlmMetrics
{
    /// <summary>One provider call (counted or not): the request, its latency, tokens and cost.</summary>
    void ProviderCall(LlmFeature feature, string providerId, LlmOutcome outcome, TimeSpan latency, LlmUsage usage, decimal costUsd);

    /// <summary>A valid plan, by its closed plan name (unknown names are tagged <c>other</c>).</summary>
    void Plan(LlmFeature feature, string planName);

    void Fallback(LlmFeature feature);

    void Refusal(LlmFeature feature, string reason);

    void ValidationFailure(LlmFeature feature, string reason);

    /// <summary>A 429 by bucket name (<c>install</c>, <c>account</c>, <c>network</c>, <c>global</c>).</summary>
    void RateLimited(LlmFeature feature, string bucket);

    void QuotaHit(LlmFeature feature);

    /// <summary>One request used the system prompt whose text hashes to <paramref name="promptHashPrefix"/> (12 hex characters): a prompt change shows in the metrics. Other values are tagged <c>other</c>.</summary>
    void Prompt(LlmFeature feature, string promptHashPrefix);

    /// <summary>The guard refused a call because the cap is reached or the ledger could not be read or written.</summary>
    void Paused(LlmFeature feature, string reason);
}

/// <summary>The tag keys the LLM metrics may use; a test enumerates every emitted key against this list.</summary>
public static class LlmMetricTags
{
    public const string Feature = "feature";
    public const string Provider = "provider";
    public const string Outcome = "outcome";
    public const string Plan = "plan";
    public const string Reason = "reason";
    public const string Bucket = "bucket";
    public const string Prompt = "prompt";

    public static IReadOnlyList<string> AllowedKeys { get; } = [Feature, Provider, Outcome, Plan, Reason, Bucket, Prompt];
}

/// <summary>Does nothing; the default when no meter is registered.</summary>
public sealed class NullLlmMetrics : ILlmMetrics
{
    public void ProviderCall(LlmFeature feature, string providerId, LlmOutcome outcome, TimeSpan latency, LlmUsage usage, decimal costUsd)
    {
    }

    public void Plan(LlmFeature feature, string planName)
    {
    }

    public void Fallback(LlmFeature feature)
    {
    }

    public void Refusal(LlmFeature feature, string reason)
    {
    }

    public void ValidationFailure(LlmFeature feature, string reason)
    {
    }

    public void RateLimited(LlmFeature feature, string bucket)
    {
    }

    public void QuotaHit(LlmFeature feature)
    {
    }

    public void Prompt(LlmFeature feature, string promptHashPrefix)
    {
    }

    public void Paused(LlmFeature feature, string reason)
    {
    }
}
