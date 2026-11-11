using Zaghlol.Testing;

namespace Zaghlol.Ops.Tests;

/// <summary>T-182 design note §8: no fake, test signer or <c>Zaghlol.Testing</c> type ships in the ops assembly.</summary>
public class TestSupportExclusionTests
{
    [Fact]
    public void TheOpsAssemblyHasNoTestSupport()
    {
        Assert.Empty(TestSupportExclusion.Offenders(typeof(OpsCli).Assembly));
    }
}
