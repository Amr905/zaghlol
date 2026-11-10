using Zaghlol.Application.Flags;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Flags;

/// <summary>FU-056: strict reading of stored rules (corrupt rules are OFF for everyone) and the pinned rollout-hash vectors.</summary>
public class FlagStrictRulesTests
{
    private static readonly InstallId One = InstallId.Parse("00000000-0000-4000-8000-000000000001");
    private static readonly DateTimeOffset At = new(2026, 11, 10, 0, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"platforms\":[\"android\"]}")]
    [InlineData("{\"platforms\":[\"android\",\"ios\"],\"min_app_version\":\"1.4.0\",\"rollout_percent\":10}")]
    [InlineData("{\"rollout_percent\":0}")]
    [InlineData("{\"rollout_percent\":100}")]
    public void WellFormedRulesParse(string json)
    {
        Assert.True(FlagRulesJson.TryParseStrict(json, out var rules));
        Assert.Equal(FlagRulesJson.Serialize(rules), FlagRulesJson.Serialize(FlagRulesJson.Parse(json)));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not json")]
    [InlineData("[]")]
    [InlineData("null")]
    [InlineData("{\"audience\":\"beta\"}")]
    [InlineData("{\"rollout_percent\":10,\"audience\":\"beta\"}")]
    [InlineData("{\"rolloutPercent\":10}")]
    [InlineData("{\"platforms\":\"android\"}")]
    [InlineData("{\"platforms\":[]}")]
    [InlineData("{\"platforms\":[\"android\",\"android\"]}")]
    [InlineData("{\"platforms\":[\"windows\"]}")]
    [InlineData("{\"platforms\":[1]}")]
    [InlineData("{\"min_app_version\":1}")]
    [InlineData("{\"min_app_version\":\"1.4\"}")]
    [InlineData("{\"min_app_version\":\"1.4.0-beta\"}")]
    [InlineData("{\"rollout_percent\":\"10\"}")]
    [InlineData("{\"rollout_percent\":10.5}")]
    [InlineData("{\"rollout_percent\":-1}")]
    [InlineData("{\"rollout_percent\":101}")]
    [InlineData("{\"rollout_percent\":10,\"rollout_percent\":20}")]
    public void EveryMalformedMemberFailsTheStrictParse(string? json)
    {
        Assert.False(FlagRulesJson.TryParseStrict(json, out var rules));
        Assert.Null(rules);
    }

    [Fact]
    public void AFlagWithCorruptRulesIsOffForEveryoneAndReported()
    {
        // Value ON, rules corrupt: without the strict parse, the lenient one would have dropped the bad member and served ON.
        var corrupt = new FlagState("zakah", true, FlagRules.None, 4, At, RulesInvalid: true);
        var healthy = new FlagState("smart_roi", true, FlagRules.None, 2, At);

        var snapshot = FlagEvaluator.Snapshot([corrupt, healthy], "android", "1.0.0", One);

        Assert.False(snapshot.Values["zakah"]);
        Assert.True(snapshot.Values["smart_roi"]);
        Assert.Equal("zakah", Assert.Single(snapshot.InvalidRules));
        Assert.Equal(6, snapshot.Version);
        Assert.False(FlagEvaluator.IsEnabled(corrupt, "ios", "9.9.9", One));
    }

    [Fact]
    public void ASnapshotWithoutCorruptRulesReportsNothing()
    {
        Assert.Empty(FlagEvaluator.Snapshot([], "ios", "1.0.0", One).InvalidRules);
    }

    /// <summary>
    /// backend-api §4.8: the text hashed is <c>zaghlol.flag.v1:&lt;key&gt;:&lt;installId&gt;</c> with the install ID as a lowercase
    /// hyphenated UUID. Expected values computed independently with <c>sha256sum</c> (first 4 bytes big-endian, mod 100), not
    /// with the code under test.
    /// </summary>
    [Theory]
    [InlineData("00000000-0000-4000-8000-000000000001", "zakah", 69)]
    [InlineData("00000000-0000-4000-8000-000000000001", "smart_roi", 9)]
    [InlineData("00000000-0000-4000-8000-000000000001", "roi_named_products", 71)]
    [InlineData("123e4567-e89b-42d3-a456-426614174000", "zakah", 53)]
    [InlineData("123e4567-e89b-42d3-a456-426614174000", "smart_roi", 12)]
    [InlineData("123e4567-e89b-42d3-a456-426614174000", "roi_named_products", 19)]
    public void RolloutBucketsMatchThePinnedVectors(string installId, string key, int bucket)
    {
        var id = InstallId.Parse(installId);

        Assert.Equal(installId, id.ToString());
        Assert.Equal(bucket, FlagEvaluator.Bucket(key, id));
    }
}
