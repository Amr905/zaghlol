using System.Text.Json;
using Zaghlol.Application.Llm.Plans;

namespace Zaghlol.Application.Tests.Llm.Ask;

/// <summary>FU-404 (batch 91): what .NET's <c>$</c> accepted and the nested what-if of PL-INVEST.</summary>
public class PlanValidatorFollowUpTests
{
    private static PlanValidationResult Validate(string plan, string sent)
    {
        using var document = JsonDocument.Parse(plan);
        return new PlanValidator().Validate(document.RootElement, sent, "en");
    }

    private static string Spend(string filter) =>
        $$"""{"v":1,"plan":"PL-SPEND","p":{"period":{"k":"cycle","o":0,"n":null,"m":null,"y":null},"filter":{{filter}}},"t":null}""";

    [Theory]
    [InlineData("""{"slug":null,"ref":"⟦CARD_1⟧\n","mention":null,"currency":null}""")]
    [InlineData("""{"slug":null,"ref":null,"mention":null,"currency":"EGP\n"}""")]
    [InlineData("""{"slug":null,"ref":null,"mention":"uber\n","currency":null}""")]
    public void ATrailingNewlineInAStringOfPIsASchemaFailure(string filter)
    {
        var result = Validate(Spend(filter), "spend on ⟦CARD_1⟧ at uber");

        Assert.False(result.IsValid);
        Assert.Equal(PlanReason.SchemaInvalid, result.Reason);
    }

    [Fact]
    public void ATrailingNewlineInAnAmountIsASchemaFailure()
    {
        const string plan = """{"v":1,"plan":"PL-WHATIF-SAVE","p":{"amount":{"amount":"500\n","currency":null},"months":12},"t":null}""";

        Assert.Equal(PlanReason.SchemaInvalid, Validate(plan, "if I save 500 for a year").Reason);
    }

    [Fact]
    public void ACleanRefStillPasses() =>
        Assert.True(Validate(Spend("""{"slug":null,"ref":"⟦CARD_1⟧","mention":null,"currency":null}"""), "spend on ⟦CARD_1⟧").IsValid);

    [Fact]
    public void ACurrencyOnTheWhatIfNestedInAnInvestPlanIsRefusedLikeOnPlWhatifCut()
    {
        const string nested = """{"v":1,"plan":"PL-INVEST","p":{"source":{"kind":"whatIf","whatIf":{"target":{"slug":"dining","ref":null,"mention":null,"currency":"USD"},"mode":{"kind":"percent","percent":50,"amount":null,"currency":null},"months":12},"amount":null},"instruments":["gold"],"horizonMonths":12},"t":null}""";

        var result = Validate(nested, "cut dining 50% and invest in gold");
        Assert.Equal(PlanReason.TargetCurrencySet, result.Reason);

        var clean = Validate(nested.Replace("\"currency\":\"USD\"", "\"currency\":null", StringComparison.Ordinal), "cut dining 50% and invest in gold");
        Assert.True(clean.IsValid);
    }
}
