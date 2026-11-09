using Zaghlol.Application.Flags;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Flags;

public class FlagEvaluatorTests
{
    private static readonly InstallId One = InstallId.Parse("00000000-0000-4000-8000-000000000001");
    private static readonly InstallId Two = InstallId.Parse("00000000-0000-4000-8000-000000000002");
    private static readonly DateTimeOffset At = new(2026, 11, 10, 0, 0, 0, TimeSpan.Zero);

    private static FlagState Flag(string key, bool value, FlagRules? rules = null, int version = 1) =>
        new(key, value, rules ?? FlagRules.None, version, At);

    [Theory]
    [InlineData("zakah", "00000000-0000-4000-8000-000000000001", 69)]
    [InlineData("zakah", "00000000-0000-4000-8000-000000000002", 30)]
    [InlineData("smart_roi", "00000000-0000-4000-8000-000000000001", 9)]
    public void TheBucketMatchesTheDocumentedHash(string key, string installId, int expected)
    {
        // Vectors computed independently: SHA-256("zaghlol.flag.v1:<key>:<installId>"), first 4 bytes big-endian, mod 100.
        Assert.Equal(expected, FlagEvaluator.Bucket(key, InstallId.Parse(installId)));
    }

    [Fact]
    public void RolloutIsStablePerInstallAcrossCalls()
    {
        var flag = Flag("zakah", true, new FlagRules(null, null, 50));

        var results = Enumerable.Range(0, 20).Select(_ => FlagEvaluator.IsEnabled(flag, "android", "1.0.0", One)).Distinct().ToList();

        Assert.Single(results);
        Assert.False(results[0]); // bucket 69 is not below 50
        Assert.True(FlagEvaluator.IsEnabled(flag, "android", "1.0.0", Two)); // bucket 30
    }

    [Fact]
    public void RaisingTheRolloutOnlyAddsInstalls()
    {
        var ids = Enumerable.Range(0, 500).Select(i => InstallId.Parse($"00000000-0000-4000-8000-{i:D12}")).ToList();
        var previous = new HashSet<InstallId>();
        foreach (var percent in new[] { 0, 10, 25, 50, 75, 100 })
        {
            var flag = Flag("smart_roi", true, new FlagRules(null, null, percent));
            var current = ids.Where(id => FlagEvaluator.IsEnabled(flag, "ios", "1.0.0", id)).ToHashSet();
            Assert.True(previous.IsSubsetOf(current), $"{percent}% dropped an install");
            previous = current;
        }

        Assert.Empty(ids.Where(id => FlagEvaluator.IsEnabled(Flag("smart_roi", true, new FlagRules(null, null, 0)), "ios", "1.0.0", id)));
        Assert.Equal(ids.Count, previous.Count);
    }

    [Fact]
    public void TheRolloutShareIsRoughlyTheConfiguredPercent()
    {
        var flag = Flag("zakah", true, new FlagRules(null, null, 30));
        var enabled = Enumerable.Range(0, 2000)
            .Count(i => FlagEvaluator.IsEnabled(flag, "android", "1.0.0", InstallId.Parse($"00000000-0000-4000-8000-{i:D12}")));

        Assert.InRange(enabled, 480, 720);
    }

    [Fact]
    public void AFlagThatIsOffIsOffWhateverTheRules()
    {
        Assert.False(FlagEvaluator.IsEnabled(Flag("zakah", false, new FlagRules(null, null, 100)), "android", "9.9.9", One));
    }

    [Fact]
    public void PlatformsRestrictToTheListedPlatforms()
    {
        var flag = Flag("zakah", true, new FlagRules(["android"], null, null));

        Assert.True(FlagEvaluator.IsEnabled(flag, "android", "1.0.0", One));
        Assert.False(FlagEvaluator.IsEnabled(flag, "ios", "1.0.0", One));
    }

    [Theory]
    [InlineData("1.4.0", "1.4.0", true)]
    [InlineData("1.4.1", "1.4.0", true)]
    [InlineData("1.10.0", "1.4.0", true)]
    [InlineData("2.0.0", "1.99.99", true)]
    [InlineData("1.3.9", "1.4.0", false)]
    [InlineData("0.9.9", "1.0.0", false)]
    [InlineData("1.4.0-beta.1", "1.4.0", true)]
    [InlineData("1.4.0+7", "1.4.0", true)]
    [InlineData("1.3.0-rc1", "1.4.0", false)]
    [InlineData("garbage", "1.0.0", false)]
    public void MinAppVersionComparesNumericallyAndFailsClosed(string installed, string minimum, bool expected)
    {
        var flag = Flag("zakah", true, new FlagRules(null, minimum, null));

        Assert.Equal(expected, FlagEvaluator.IsEnabled(flag, "android", installed, One));
    }

    [Fact]
    public void AllPresentRulesMustHold()
    {
        var flag = Flag("zakah", true, new FlagRules(["ios"], "1.4.0", 100));

        Assert.True(FlagEvaluator.IsEnabled(flag, "ios", "1.4.0", One));
        Assert.False(FlagEvaluator.IsEnabled(flag, "android", "1.4.0", One));
        Assert.False(FlagEvaluator.IsEnabled(flag, "ios", "1.3.0", One));
    }

    [Fact]
    public void ADefaultFlagIsOffAndEveryKnownFlagIsInTheSnapshot()
    {
        var snapshot = FlagEvaluator.Snapshot([], "android", "1.0.0", One);

        Assert.Equal(FlagKeys.Known.ToArray(), snapshot.Values.Keys.ToArray());
        Assert.All(snapshot.Values.Values, Assert.False);
        Assert.Equal(0, snapshot.Version);
        Assert.False(FlagState.Default("zakah").Value);
    }

    [Fact]
    public void TheSnapshotUsesStoredFlagsAndTheSumOfTheirVersions()
    {
        var snapshot = FlagEvaluator.Snapshot(
            [Flag("zakah", true, version: 3), Flag("smart_roi", false, version: 2), Flag("not_a_known_flag", true, version: 50)],
            "android",
            "1.0.0",
            One);

        Assert.True(snapshot.Values["zakah"]);
        Assert.False(snapshot.Values["smart_roi"]);
        Assert.False(snapshot.Values["roi_named_products"]);
        Assert.False(snapshot.Values.ContainsKey("not_a_known_flag"));
        Assert.Equal(5, snapshot.Version);
    }
}
