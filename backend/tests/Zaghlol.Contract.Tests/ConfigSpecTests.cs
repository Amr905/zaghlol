using Zaghlol.Application.Config;

namespace Zaghlol.Contract.Tests;

/// <summary>T-334: the remote config contract of the spec and the closed key catalogue agree (no database needed).</summary>
public class ConfigSpecTests
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    [Fact]
    public void TheConfigKeyPatternAndTheAdminOperationsAreInTheSpec()
    {
        Assert.Equal(RemoteConfigKeys.Pattern, Spec.Schemas["ConfigKey"]!["pattern"]!.GetValue<string>());
        var ids = Spec.Operations().Select(o => o.Id).ToList();
        Assert.Contains("adminListConfig", ids);
        Assert.Contains("adminGetConfig", ids);
        Assert.Contains("adminPutConfig", ids);
        Assert.False(Spec.Schemas["ConfigUpdateRequest"]!["additionalProperties"]!.GetValue<bool>());
        Assert.Equal("string", Spec.Schemas["ConfigUpdateRequest"]!["properties"]!["value"]!["type"]!.GetValue<string>());
    }

    [Fact]
    public void EveryKeyFitsTheConfigBlockValueLimitAndNoDefaultIsANumberType()
    {
        var max = (int)Spec.Schemas["ConfigBlock"]!["properties"]!["values"]!["additionalProperties"]!["maxLength"]!.GetValue<long>();

        foreach (var definition in RemoteConfigKeys.All)
        {
            Assert.Matches(RemoteConfigKeys.Pattern, definition.Key);
            Assert.True(definition.Default.Length <= max, definition.Key);
        }
    }

    [Fact]
    public void ServerOnlyKeysAreExactlyTheOnesTheSpecDescribesAsNeverSent()
    {
        var serverOnly = RemoteConfigKeys.All.Where(d => !d.SentToApp).Select(d => d.Key).Order(StringComparer.Ordinal).ToList();

        Assert.Equal(["cat.cache_min_confidence", "cat.confirm_n", "llm.spend_cap_usd"], serverOnly);
    }
}
