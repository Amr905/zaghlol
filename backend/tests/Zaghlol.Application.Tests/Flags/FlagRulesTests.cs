using Zaghlol.Application.Flags;

namespace Zaghlol.Application.Tests.Flags;

public class FlagRulesTests
{
    [Fact]
    public void ValidRulesPass()
    {
        Assert.True(FlagRulesValidator.IsValid(FlagRules.None));
        Assert.True(FlagRulesValidator.IsValid(new FlagRules(["android", "ios"], "0.0.0", 0)));
        Assert.True(FlagRulesValidator.IsValid(new FlagRules(["ios"], "9999.9999.9999", 100)));
    }

    [Fact]
    public void InvalidRulesFail()
    {
        Assert.False(FlagRulesValidator.IsValid(new FlagRules([], null, null)));
        Assert.False(FlagRulesValidator.IsValid(new FlagRules(["android", "android"], null, null)));
        Assert.False(FlagRulesValidator.IsValid(new FlagRules(["windows"], null, null)));
        Assert.False(FlagRulesValidator.IsValid(new FlagRules(["Android"], null, null)));
        Assert.False(FlagRulesValidator.IsValid(new FlagRules(null, null, -1)));
        Assert.False(FlagRulesValidator.IsValid(new FlagRules(null, null, 101)));
    }

    [Theory]
    [InlineData("1.4")]
    [InlineData("1.4.0.1")]
    [InlineData("1.4.0-beta")]
    [InlineData("v1.4.0")]
    [InlineData("1.4.0\n")]
    [InlineData("12345.0.0")]
    [InlineData("")]
    [InlineData("١.٤.٠")]
    public void MinAppVersionMustBeThreeAsciiNumbers(string version)
    {
        Assert.False(FlagRulesValidator.IsValid(new FlagRules(null, version, null)));
    }

    [Fact]
    public void RulesRoundTripThroughTheStoredJsonWithSnakeCaseMembers()
    {
        var rules = new FlagRules(["android", "ios"], "1.4.0", 10);

        var json = FlagRulesJson.Serialize(rules);

        Assert.Equal("{\"platforms\":[\"android\",\"ios\"],\"min_app_version\":\"1.4.0\",\"rollout_percent\":10}", json);
        var back = FlagRulesJson.Parse(json);
        Assert.Equal("android,ios", string.Join(',', back.Platforms!));
        Assert.Equal("1.4.0", back.MinAppVersion);
        Assert.Equal(10, back.RolloutPercent);
    }

    [Fact]
    public void AbsentMembersAreOmittedAndParseBackAsAbsent()
    {
        Assert.Equal("{}", FlagRulesJson.Serialize(FlagRules.None));
        Assert.Equal("{\"rollout_percent\":0}", FlagRulesJson.Serialize(new FlagRules(null, null, 0)));

        var empty = FlagRulesJson.Parse("{}");
        Assert.True(empty.IsEmpty);
        Assert.Equal(0, FlagRulesJson.Parse("{\"rollout_percent\":0}").RolloutPercent);
    }

    [Fact]
    public void FlagKeysAreAClosedSetWithAnAsciiShape()
    {
        Assert.Equal("zakah,smart_roi,roi_named_products", string.Join(',', FlagKeys.Known));
        Assert.True(FlagKeys.IsKnown("zakah"));
        Assert.False(FlagKeys.IsKnown("Zakah"));
        Assert.False(FlagKeys.IsKnown("other"));
        Assert.True(FlagKeys.HasValidShape("other_flag_2"));
        Assert.False(FlagKeys.HasValidShape("zakah\n"));
        Assert.False(FlagKeys.HasValidShape("2zakah"));
        Assert.False(FlagKeys.HasValidShape("a"));
        Assert.False(FlagKeys.HasValidShape(new string('a', 65)));
        Assert.False(FlagKeys.HasValidShape("za-kah"));
    }
}
