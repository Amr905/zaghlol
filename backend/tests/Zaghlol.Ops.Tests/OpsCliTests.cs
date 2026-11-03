using Zaghlol.Ops;

namespace Zaghlol.Ops.Tests;

public class OpsCliTests
{
    [Fact]
    public void NoArgsPrintsUsageAndSucceeds()
    {
        using var output = new StringWriter();
        using var error = new StringWriter();

        var code = OpsCli.Run([], output, error);

        Assert.Equal(OpsCli.Success, code);
        Assert.Contains("Usage", output.ToString(), StringComparison.Ordinal);
        Assert.Equal(string.Empty, error.ToString());
    }

    [Fact]
    public void UnknownCommandIsUsageError()
    {
        using var output = new StringWriter();
        using var error = new StringWriter();

        var code = OpsCli.Run(["nope"], output, error);

        Assert.Equal(OpsCli.UsageError, code);
        Assert.NotEqual(string.Empty, error.ToString());
    }
}
