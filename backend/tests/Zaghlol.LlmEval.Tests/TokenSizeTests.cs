using System.Text;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Spend;

namespace Zaghlol.LlmEval.Tests;

/// <summary>FU-429: the real prompt and schema against the spend guard's input bound.</summary>
public sealed class TokenSizeTests
{
    [Fact]
    public void The_real_prompt_and_schema_fit_the_guards_budget_even_at_one_token_per_byte()
    {
        var prompt = new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.AskPlanV1);
        var bytes = Encoding.UTF8.GetByteCount(prompt) + Encoding.UTF8.GetByteCount(Program.ProviderSchemaText());

        // The schema as the adapters send it (compact, comment members stripped), one token per byte: an upper bound for any tokenizer.
        Assert.True(bytes <= SpendGuardOptions.PromptAndSchemaTokens, $"prompt+schema is {bytes} bytes, above {SpendGuardOptions.PromptAndSchemaTokens}");
        Assert.True(bytes + SpendGuardOptions.MaxQuestionChars + SpendGuardOptions.ProviderOverheadTokens <= PassRule.InputTokenBound);
        Assert.Equal(21_300, SpendGuardOptions.DefaultMaxInputTokens);
        Assert.Contains("bytes", Program.PromptSizeNote(), StringComparison.Ordinal);
    }
}
