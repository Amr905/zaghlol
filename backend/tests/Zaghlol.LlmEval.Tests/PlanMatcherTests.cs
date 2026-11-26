using System.Text.Json.Nodes;

namespace Zaghlol.LlmEval.Tests;

/// <summary>The scoring rule for "exact plan + params" (T-350 design note).</summary>
public sealed class PlanMatcherTests
{
    private static ExpectedPlan Expect(string plan, string? p) => new(plan, p is null ? null : JsonNode.Parse(p));

    [Theory]
    [InlineData("""{"months":12,"mode":{"kind":"percent","percent":50}}""", """{"target":{"slug":"dining"},"mode":{"kind":"percent","percent":50,"amount":null},"months":12}""", true)]
    [InlineData("""{"months":12}""", """{"months":6}""", false)]
    [InlineData("""{"amount":{"amount":"500"}}""", """{"amount":{"amount":"500.00","currency":"EGP"}}""", true)]
    [InlineData("""{"amount":{"amount":"500"}}""", """{"amount":{"amount":"5000"}}""", false)]
    [InlineData("""{"i":{"$set":["gold","usd"]}}""", """{"i":["usd","gold"]}""", true)]
    [InlineData("""{"i":{"$set":["gold","usd"]}}""", """{"i":["usd","gold","index"]}""", false)]
    [InlineData("""{"ref":"⟦CARD_1⟧"}""", """{"ref":"⟦CARD_2⟧"}""", false)]
    [InlineData("""{"selfHarm":true}""", """{"reason":"unsafe","selfHarm":false}""", false)]
    [InlineData("""{"slug":null}""", """{"slug":"dining"}""", false)]
    [InlineData("""{"n":5}""", """{"n":"5"}""", false)]
    public void Subset_rule(string expected, string actual, bool match) =>
        Assert.Equal(match, PlanMatcher.Subset(JsonNode.Parse(expected), JsonNode.Parse(actual)));

    [Fact]
    public void A_different_plan_id_never_matches_even_with_no_params()
    {
        Assert.False(PlanMatcher.Matches(Expect("PL-SPEND", null), "PL-INCOME", JsonNode.Parse("{}")));
        Assert.True(PlanMatcher.Matches(Expect("PL-SPEND", null), "PL-SPEND", JsonNode.Parse("{}")));
    }
}
