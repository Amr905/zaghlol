using Zaghlol.Application.Audit;
using Zaghlol.Application.Contributions;
using Zaghlol.Application.Tests.Prices;

namespace Zaghlol.Application.Tests.Contributions;

/// <summary>T-129 domain rules: the status enum, key validation, the aggregation job's cutoff and events, the audit rows.</summary>
public class ContributionReviewTests
{
    [Fact]
    public void TheThresholdIsFiveDistinctInstallsAndRawRowsLiveAtMost180Days()
    {
        Assert.Equal(5, ContributionRules.MinDistinctInstalls);
        Assert.Equal(180, ContributionRules.RawRetentionDays);
    }

    [Theory]
    [InlineData("ready_for_review", ContributionReviewStatus.ReadyForReview)]
    [InlineData("promoted", ContributionReviewStatus.Promoted)]
    [InlineData("rejected", ContributionReviewStatus.Rejected)]
    public void EveryExposedStatusRoundTrips(string wire, ContributionReviewStatus status)
    {
        Assert.True(ContributionStatuses.TryParse(wire, out var parsed));
        Assert.Equal(status, parsed);
        Assert.Equal(wire, ContributionStatuses.Wire(status));
    }

    [Theory]
    [InlineData("collecting")]
    [InlineData("Promoted")]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("all")]
    public void CollectingAndAnythingElseIsNotAStatus(string? text)
    {
        Assert.False(ContributionStatuses.TryParse(text, out _));
    }

    [Fact]
    public void TheEnumHasNoCollectingMember()
    {
        Assert.DoesNotContain(Enum.GetNames<ContributionReviewStatus>(), n => n.Contains("Collecting", StringComparison.Ordinal));
        Assert.Equal(3, Enum.GetValues<ContributionReviewStatus>().Length);
    }

    [Theory]
    [InlineData("koshary el tahrir", "nbe", true)]
    [InlineData("كشري التحرير", "nbe", true)]
    [InlineData("ab", "cib", true)]
    [InlineData("a", "nbe", false)]
    [InlineData("", "nbe", false)]
    [InlineData("koshary", "NBE", false)]
    [InlineData("koshary", "n", false)]
    [InlineData("koshary", "has space", false)]
    [InlineData("kos\u0000hary", "nbe", false)]
    public void KeysAreValidatedBeforeAnyLookup(string merchant, string institution, bool valid)
    {
        Assert.Equal(valid, ContributionKeys.IsValidKey(merchant, institution));
    }

    [Fact]
    public void AKeyOver80CharactersIsInvalidAndNullIsInvalid()
    {
        Assert.True(ContributionKeys.IsValidKey(new string('a', ContributionRules.MaxKeyLength), "nbe"));
        Assert.False(ContributionKeys.IsValidKey(new string('a', ContributionRules.MaxKeyLength + 1), "nbe"));
        Assert.False(ContributionKeys.IsValidKey(null, "nbe"));
        Assert.False(ContributionKeys.IsValidKey("koshary", null));
    }

    [Fact]
    public async Task TheJobPurgesAt180DaysAndCountsOnlyWhatHappened()
    {
        var now = new DateTimeOffset(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);
        var store = new FakeStore(new AggregationRun(7, 2, 5, 0));
        var metrics = new RecordingMetrics();

        var run = await new ContributionAggregationJob(store, metrics, new TestClock(now)).RunOnceAsync(CancellationToken.None);

        Assert.Equal(now.AddDays(-180), store.Cutoff);
        Assert.Equal(ContributionRules.MinDistinctInstalls, store.Threshold);
        Assert.Equal(7, run.Updated);
        Assert.Equal(3, metrics.Events.Count);
        Assert.Contains((ContributionEvents.Ready, 2), metrics.Events);
        Assert.Contains((ContributionEvents.PurgedDecided, 5), metrics.Events);
        Assert.Contains((ContributionEvents.PurgedExpired, 0), metrics.Events);
    }

    [Fact]
    public async Task AFailedRunReportsNothing()
    {
        var metrics = new RecordingMetrics();
        var job = new ContributionAggregationJob(new FakeStore(null), metrics, new TestClock(DateTimeOffset.UnixEpoch));

        await Assert.ThrowsAsync<InvalidOperationException>(() => job.RunOnceAsync(CancellationToken.None));

        Assert.Empty(metrics.Events);
    }

    [Fact]
    public void TheDecisionAuditNamesTheActionAndKeepsTheTextEncoded()
    {
        var promote = new ContributionDecisionAudit(ContributionDecisionKind.Promote, "nbe", "a29zaGFyeQ", 812, "dining");
        var reject = new ContributionDecisionAudit(ContributionDecisionKind.Reject, "nbe", "a29zaGFyeQ", null, null);

        Assert.Equal("contribution_promote", promote.Action);
        Assert.Equal("contribution/nbe:a29zaGFyeQ", promote.Target);
        Assert.Equal("{\"institution\":\"nbe\",\"merchant_id\":812,\"category\":\"dining\"}", promote.Details());
        Assert.Equal("contribution_reject", reject.Action);
        Assert.Equal("{\"institution\":\"nbe\"}", reject.Details());
    }

    private sealed class FakeStore(AggregationRun? result) : IContributionAggregationStore
    {
        public DateTimeOffset Cutoff { get; private set; }

        public int Threshold { get; private set; }

        public Task<AggregationRun> RunAsync(int minDistinctInstalls, DateTimeOffset rawCutoff, CancellationToken cancellationToken)
        {
            Threshold = minDistinctInstalls;
            Cutoff = rawCutoff;
            return result is { } run ? Task.FromResult(run) : throw new InvalidOperationException("db down");
        }
    }

    private sealed class RecordingMetrics : IContributionMetrics
    {
        public List<(string, int)> Events { get; } = [];

        public void Event(string name, int count) => Events.Add((name, count));
    }
}
