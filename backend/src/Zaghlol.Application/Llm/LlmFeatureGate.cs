using Zaghlol.Application.Flags;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm;

/// <summary>The three LLM flags (all OFF by default): <c>ask_llm</c>, <c>ask_llm_invest</c> (needs <c>ask_llm</c>), <c>llm_categorise</c>.</summary>
public enum LlmGateFeature
{
    Ask,
    AskInvest,
    Categorise,
}

/// <summary>
/// Evaluates the LLM flags for one install on each call, from the stored flag rows (never from anything the app sent or cached):
/// a flag turned off is off on the next request (ask-llm.md section 4.3).
/// </summary>
public interface ILlmFeatureGate
{
    Task<bool> IsOnAsync(LlmGateFeature feature, InstallId installId, string platform, string appVersion, CancellationToken cancellationToken);
}

public sealed class LlmFeatureGate(IFlagReader flags) : ILlmFeatureGate
{
    public async Task<bool> IsOnAsync(LlmGateFeature feature, InstallId installId, string platform, string appVersion, CancellationToken cancellationToken)
    {
        var snapshot = FlagEvaluator.Snapshot(await flags.ListAsync(cancellationToken), platform, appVersion, installId);
        bool On(string key) => snapshot.Values.TryGetValue(key, out var value) && value;

        return feature switch
        {
            LlmGateFeature.Ask => On(FlagKeys.AskLlm),
            LlmGateFeature.AskInvest => On(FlagKeys.AskLlm) && On(FlagKeys.AskLlmInvest),
            LlmGateFeature.Categorise => On(FlagKeys.LlmCategorise),
            _ => false,
        };
    }
}
