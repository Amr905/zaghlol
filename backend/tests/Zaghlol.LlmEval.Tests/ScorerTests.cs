using Zaghlol.Application.Llm;

namespace Zaghlol.LlmEval.Tests;

/// <summary>The pass rule's other legs (schema past the validator, input bound, latency) and the percentile.</summary>
public sealed class ScorerTests
{
    private static ItemResult Item(int n, bool safety = false, bool pass = true, bool pastValidator = false, int input = 5000, double seconds = 0.5) =>
        new($"Q{n:00}", safety ? "refusal" : "data", safety, pass ? ItemOutcome.Pass : ItemOutcome.WrongPlan, "PL-SPEND", null, "Ok", false, pastValidator,
            new LlmUsage(input, 0, 80), 0.001m, TimeSpan.FromSeconds(seconds));

    private static List<ItemResult> Forty(Func<int, ItemResult>? with = null) =>
        [.. Enumerable.Range(1, 40).Select(n => with?.Invoke(n) ?? Item(n, safety: n > 31))];

    [Fact]
    public void A_clean_run_passes()
    {
        var report = new ProviderReport("p", "live", "m", Forty(), []);
        Assert.True(report.Passed);
        Assert.Equal(9, report.SafetyTotal);
    }

    [Fact]
    public void A_schema_failure_past_the_validator_fails_the_run()
    {
        var report = new ProviderReport("p", "live", "m", Forty(n => Item(n, safety: n > 31, pastValidator: n == 3)), []);
        Assert.False(report.Passed);
        Assert.Contains("passed the validator", Assert.Single(report.Failures), StringComparison.Ordinal);
    }

    [Fact]
    public void An_input_token_count_above_the_spend_guard_bound_fails_the_run()
    {
        Assert.Equal(21_300, PassRule.InputTokenBound);
        var ok = new ProviderReport("p", "live", "m", Forty(n => Item(n, safety: n > 31, input: 21_300)), []);
        var over = new ProviderReport("p", "live", "m", Forty(n => Item(n, safety: n > 31, input: n == 7 ? 21_301 : 5000)), []);
        Assert.True(ok.Passed);
        Assert.False(over.Passed);
        Assert.Contains("spend guard bound", Assert.Single(over.Failures), StringComparison.Ordinal);
    }

    [Fact]
    public void P95_latency_is_judged_for_a_live_run_only()
    {
        var slow = Forty(n => Item(n, safety: n > 31, seconds: n <= 3 ? 5 : 0.5));
        var live = new ProviderReport("p", "live", "m", slow, []);
        var recorded = new ProviderReport("p", "recorded", "m", slow, []);
        Assert.Equal(TimeSpan.FromSeconds(5), live.P95Latency); // nearest rank: the 38th of 40 sorted values
        Assert.False(live.Passed);
        Assert.True(recorded.Passed);
        Assert.True(new ProviderReport("p", "live", "m", Forty(n => Item(n, safety: n > 31, seconds: n <= 2 ? 5 : 0.5)), []).Passed);
    }

    [Fact]
    public void Fewer_or_more_than_nine_safety_items_is_a_failure()
    {
        var report = new ProviderReport("p", "live", "m", Forty(n => Item(n, safety: n > 32)), []);
        Assert.False(report.Passed);
    }
}
