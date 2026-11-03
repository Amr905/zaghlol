using System.Reflection;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests;

public partial class ErrorCodesTests
{
    [GeneratedRegex("^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$")]
    private static partial Regex UpperSnake();

    [Fact]
    public void AllCodesAreUpperSnakeAndUnique()
    {
        var values = typeof(ErrorCodes)
            .GetFields(BindingFlags.Public | BindingFlags.Static)
            .Select(f => (string)f.GetRawConstantValue()!)
            .ToList();

        Assert.NotEmpty(values);
        Assert.All(values, v => Assert.Matches(UpperSnake(), v));
        Assert.Equal(values.Count, values.Distinct(StringComparer.Ordinal).Count());
    }
}
