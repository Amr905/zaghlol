using Zaghlol.Testing;

namespace Zaghlol.Workers.Tests;

/// <summary>T-182 design note §8: no fake, test signer or <c>Zaghlol.Testing</c> type ships in the worker assembly.</summary>
public class TestSupportExclusionTests
{
    [Fact]
    public void TheWorkerAssemblyHasNoTestSupport()
    {
        Assert.Empty(TestSupportExclusion.Offenders(typeof(HeartbeatFile).Assembly));
    }
}
