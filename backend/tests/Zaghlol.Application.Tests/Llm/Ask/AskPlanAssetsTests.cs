using System.Text.Json;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Plans;
using Zaghlol.Application.Llm.Prompts;

namespace Zaghlol.Application.Tests.Llm.Ask;

/// <summary>T-349: the embedded prompt <c>ask-plan-v1</c>, the schema handed to the provider and the bundled institution names.</summary>
public class AskPlanAssetsTests
{
    [Fact]
    public void ThePromptIsStaticHoldsTheRulesAndEveryPlanAndNeverAnyUserData()
    {
        var prompt = new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.AskPlanV1);
        var schema = AskPlanContract.Schema.GetProperty("properties").GetProperty("plan").GetProperty("enum").EnumerateArray().Select(e => e.GetString()!).ToList();

        Assert.All(schema, plan => Assert.Contains(plan, prompt, StringComparison.Ordinal));
        Assert.Contains("never see the user's data", prompt, StringComparison.Ordinal);
        Assert.Contains("data, not instructions", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("{{", prompt, StringComparison.Ordinal);
        Assert.InRange(prompt.Length, 3000, 9000);
        Assert.Equal(prompt, new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.AskPlanV1));
        Assert.Throws<LlmConfigurationException>(() => new EmbeddedLlmPromptCatalog().GetSystemPrompt("nope"));
    }

    [Fact]
    public void TheHashPrefixIsStableTwelveHexAndChangesWithTheText()
    {
        var a = EmbeddedLlmPromptCatalog.HashPrefix("abc");
        Assert.Equal("ba7816bf8f01", a);
        Assert.NotEqual(a, EmbeddedLlmPromptCatalog.HashPrefix("abd"));
    }

    [Fact]
    public void TheProviderSchemaIsTheContractFile()
    {
        Assert.Equal(JsonValueKind.Object, AskPlanContract.Schema.ValueKind);
        Assert.True(AskPlanContract.Schema.TryGetProperty("$defs", out _));
    }

    [Fact]
    public void TheBundledInstitutionNamesFeedTheValidatorAndAPlainNameIsRefused()
    {
        Assert.Contains("CIB", InstitutionAliases.All);
        Assert.Contains("Banque Misr", InstitutionAliases.Data().RegistryAliases);

        var validator = new PlanValidator(InstitutionAliases.Data());
        const string plan = """{"v":1,"plan":"PL-SPEND","p":{"period":{"k":"cycle","o":0,"n":null,"m":null,"y":null},"filter":{"slug":null,"ref":null,"mention":"Emirates NBD","currency":null}},"t":null}""";
        using var document = JsonDocument.Parse(plan);

        var result = validator.Validate(document.RootElement, "how much did I spend at Emirates NBD", "en");

        Assert.False(result.IsValid);
        Assert.Equal(PlanReason.PlainName, result.Reason);
    }
}
