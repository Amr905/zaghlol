using Zaghlol.Testing;

namespace Zaghlol.LlmEval.Tests;

/// <summary>T-182 design note section 8: the harness and the production assemblies it uses carry no test support (the fake lives only in this test project).</summary>
public sealed class TestSupportExclusionTests
{
    [Fact]
    public void The_harness_and_the_production_assemblies_it_references_are_clean()
    {
        Assert.Empty(TestSupportExclusion.Offenders(typeof(EvalRunner).Assembly));
        Assert.Empty(TestSupportExclusion.Offenders(typeof(Zaghlol.Application.Llm.ILlmProvider).Assembly));
        Assert.Empty(TestSupportExclusion.Offenders(typeof(Zaghlol.Infrastructure.Llm.OpenAiResponsesProvider).Assembly));
    }
}
