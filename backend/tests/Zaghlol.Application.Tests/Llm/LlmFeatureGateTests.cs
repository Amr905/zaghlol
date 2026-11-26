using Zaghlol.Application.Flags;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Llm;

/// <summary>T-334: the per-install LLM flags are evaluated from the stored rows on every call.</summary>
public class LlmFeatureGateTests
{
    private static readonly InstallId Install = InstallId.Parse("00000000-0000-4000-8000-000000000001");
    private static readonly DateTimeOffset Now = new(2026, 11, 26, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void TheThreeFlagsAreKnownAndOffByDefault()
    {
        Assert.Contains(FlagKeys.AskLlm, FlagKeys.Known);
        Assert.Contains(FlagKeys.AskLlmInvest, FlagKeys.Known);
        Assert.Contains(FlagKeys.LlmCategorise, FlagKeys.Known);
        Assert.False(FlagState.Default(FlagKeys.AskLlm).Value);
        Assert.False(FlagState.Default(FlagKeys.AskLlmInvest).Value);
        Assert.False(FlagState.Default(FlagKeys.LlmCategorise).Value);
    }

    [Fact]
    public async Task NothingStoredMeansEveryFeatureIsOff()
    {
        var gate = new LlmFeatureGate(new Flags());

        foreach (var feature in Enum.GetValues<LlmGateFeature>())
        {
            Assert.False(await gate.IsOnAsync(feature, Install, "android", "1.0.0", default));
        }
    }

    [Fact]
    public async Task TurningAFlagOffIsSeenOnTheNextCall()
    {
        var flags = new Flags(On(FlagKeys.AskLlm), On(FlagKeys.AskLlmInvest), On(FlagKeys.LlmCategorise));
        var gate = new LlmFeatureGate(flags);

        Assert.True(await gate.IsOnAsync(LlmGateFeature.Ask, Install, "android", "1.0.0", default));
        Assert.True(await gate.IsOnAsync(LlmGateFeature.AskInvest, Install, "android", "1.0.0", default));
        Assert.True(await gate.IsOnAsync(LlmGateFeature.Categorise, Install, "ios", "1.0.0", default));

        flags.Stored = [Off(FlagKeys.AskLlm), On(FlagKeys.AskLlmInvest), On(FlagKeys.LlmCategorise)];

        Assert.False(await gate.IsOnAsync(LlmGateFeature.Ask, Install, "android", "1.0.0", default));
        Assert.False(await gate.IsOnAsync(LlmGateFeature.AskInvest, Install, "android", "1.0.0", default)); // needs ask_llm
        Assert.True(await gate.IsOnAsync(LlmGateFeature.Categorise, Install, "android", "1.0.0", default));
    }

    [Fact]
    public async Task TargetingRulesApplyPerInstall()
    {
        var rules = new FlagRules(["ios"], null, null);
        var gate = new LlmFeatureGate(new Flags(new FlagState(FlagKeys.AskLlm, true, rules, 1, Now)));

        Assert.True(await gate.IsOnAsync(LlmGateFeature.Ask, Install, "ios", "1.0.0", default));
        Assert.False(await gate.IsOnAsync(LlmGateFeature.Ask, Install, "android", "1.0.0", default));
    }

    private static FlagState On(string key) => new(key, true, FlagRules.None, 1, Now);

    private static FlagState Off(string key) => new(key, false, FlagRules.None, 2, Now);

    private sealed class Flags(params FlagState[] stored) : IFlagReader
    {
        public IReadOnlyList<FlagState> Stored { get; set; } = stored;

        public Task<IReadOnlyList<FlagState>> ListAsync(CancellationToken cancellationToken) => Task.FromResult(Stored);
    }
}
