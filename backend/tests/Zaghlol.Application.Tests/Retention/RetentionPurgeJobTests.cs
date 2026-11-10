using Zaghlol.Application.Retention;

namespace Zaghlol.Application.Tests.Retention;

public class RetentionPurgeJobTests
{
    private sealed class ScriptedStore(Func<string, int, int> next) : IRetentionStore
    {
        public List<(string Rule, DateTimeOffset Now, int Batch)> Calls { get; } = [];

        private readonly Dictionary<string, int> counts = [];

        public Task<int> PurgeBatchAsync(string rule, DateTimeOffset now, int batchSize, CancellationToken cancellationToken)
        {
            Calls.Add((rule, now, batchSize));
            var n = counts[rule] = counts.GetValueOrDefault(rule) + 1;
            return Task.FromResult(next(rule, n));
        }
    }

    private sealed class RecordingMetrics : IRetentionMetrics
    {
        public Dictionary<string, long> Purges { get; } = [];

        public List<string> Failures { get; } = [];

        public void Purged(string rule, long count) => Purges[rule] = count;

        public void Failed(string rule) => Failures.Add(rule);
    }

    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private static readonly DateTimeOffset Now = new(2026, 11, 10, 3, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task EveryRuleRunsOnceWithTheSameInstantAndStopsWhenABatchIsShort()
    {
        var store = new ScriptedStore((_, _) => 0);

        var result = await new RetentionPurgeJob(store, new RecordingMetrics(), new FixedClock(Now)).RunOnceAsync(10, CancellationToken.None);

        Assert.Equal(RetentionRules.All, store.Calls.Select(c => c.Rule));
        Assert.All(store.Calls, c => Assert.Equal(Now, c.Now));
        Assert.Empty(result.Failed);
    }

    [Fact]
    public async Task AFullBatchIsFollowedByAnotherAndTheTotalIsReported()
    {
        var store = new ScriptedStore((rule, n) => rule == RetentionRules.ReplayGuard ? (n < 3 ? 10 : 4) : 0);
        var metrics = new RecordingMetrics();

        var result = await new RetentionPurgeJob(store, metrics, new FixedClock(Now)).RunOnceAsync(10, CancellationToken.None);

        Assert.Equal(24, result.Purged[RetentionRules.ReplayGuard]);
        Assert.Equal(24, metrics.Purges[RetentionRules.ReplayGuard]);
        Assert.Single(metrics.Purges);
    }

    [Fact]
    public async Task AFailingRuleIsCountedByNameAndTheOthersStillRun()
    {
        var store = new ScriptedStore((rule, _) => rule == RetentionRules.StoreNotifications ? throw new InvalidOperationException("203.0.113.9 down") : 1);
        var metrics = new RecordingMetrics();

        var result = await new RetentionPurgeJob(store, metrics, new FixedClock(Now)).RunOnceAsync(10, CancellationToken.None);

        Assert.Equal([RetentionRules.StoreNotifications], result.Failed);
        Assert.Equal([RetentionRules.StoreNotifications], metrics.Failures);
        Assert.Equal(RetentionRules.All.Count - 1, metrics.Purges.Count);
    }

    [Fact]
    public async Task ARuleStopsAfterTheBatchCapSoOneRunIsBounded()
    {
        var store = new ScriptedStore((_, _) => 10);

        await new RetentionPurgeJob(store, new RecordingMetrics(), new FixedClock(Now)).RunOnceAsync(10, CancellationToken.None);

        Assert.Equal(RetentionRules.All.Count * RetentionPurgeJob.MaxBatchesPerRule, store.Calls.Count);
    }

    [Fact]
    public async Task CancellationIsNotSwallowed()
    {
        using var cts = new CancellationTokenSource();
        var store = new ScriptedStore((_, _) =>
        {
            cts.Cancel();
            throw new OperationCanceledException(cts.Token);
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new RetentionPurgeJob(store, new RecordingMetrics(), new FixedClock(Now)).RunOnceAsync(10, cts.Token));
    }

    [Fact]
    public void TheSupportAuditActionsAreTheFourOfDecisionD47()
    {
        Assert.Equal(["support_lookup", "support_seat_move", "support_detach", "support_unfreeze"], RetentionAuditActions.OneYear);
    }
}
