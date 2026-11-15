using Zaghlol.Application.Accounts;
using Zaghlol.Application.Tests.Entitlements;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Accounts;

/// <summary>The worker pass over pending Apple revocations (Lead decision: deletion is never blocked; retry up to 30 days, then drop).</summary>
public class AppleRevocationRetryJobTests
{
    private static readonly DateTimeOffset T0 = EntitlementTestKit.Now;

    private readonly MemoryPendingStore store = new();
    private readonly RecordingApple apple = new();
    private readonly ManualClock clock = new(T0);

    private AppleRevocationRetryJob Job() => new(store, new IdentityVault(), apple, clock);

    private static byte[] Blob(string token = "refresh-1") => System.Text.Encoding.UTF8.GetBytes("services.id\n" + token);

    private PendingAppleRevocation Add(DateTimeOffset next, DateTimeOffset expires, int attempts = 0, byte[]? blob = null)
    {
        var row = new PendingAppleRevocation(Guid.NewGuid(), blob ?? Blob(), attempts);
        store.Rows[row.Id] = (row, next, expires);
        return row;
    }

    [Fact]
    public async Task ASuccessfulRevocationRemovesTheRow()
    {
        Add(T0, T0.AddDays(30));

        var run = await Job().RunOnceAsync(default);

        Assert.Equal(1, run.Revoked);
        Assert.Empty(store.Rows);
        Assert.Equal("refresh-1", Assert.Single(apple.Revoked).Token.Reveal());
    }

    [Fact]
    public async Task WhileAppleIsDownTheRowStaysAndBacksOffExponentially()
    {
        var row = Add(T0, T0.AddDays(30));
        apple.Outcome = AppleRevokeOutcome.Unavailable;

        var first = await Job().RunOnceAsync(default);

        Assert.Equal(1, first.Deferred);
        var (kept, next, _) = store.Rows[row.Id];
        Assert.Equal(1, kept.Attempts);
        Assert.Equal(T0 + PendingAppleRevocationPolicy.DelayAfter(1), next);

        // Not due yet: nothing is attempted.
        var idle = await Job().RunOnceAsync(default);
        Assert.Equal(0, idle.Deferred + idle.Revoked);

        clock.Now += PendingAppleRevocationPolicy.DelayAfter(1);
        await Job().RunOnceAsync(default);
        Assert.Equal(2, store.Rows[row.Id].Row.Attempts);
    }

    [Fact]
    public async Task ARowPastTheWindowIsDroppedWithoutAnotherAttempt()
    {
        Add(T0.AddDays(-1), T0.AddMinutes(-1), attempts: 40);
        apple.Outcome = AppleRevokeOutcome.Unavailable;

        var run = await Job().RunOnceAsync(default);

        Assert.Equal(1, run.GaveUp);
        Assert.Empty(store.Rows);
        Assert.Empty(apple.Revoked);
    }

    [Fact]
    public async Task ARowThatSucceedsAfterSeveralFailuresIsRemoved()
    {
        var row = Add(T0, T0.AddDays(30));
        apple.Outcome = AppleRevokeOutcome.Unavailable;
        await Job().RunOnceAsync(default);
        apple.Outcome = AppleRevokeOutcome.Revoked;
        clock.Now += TimeSpan.FromDays(1);

        var run = await Job().RunOnceAsync(default);

        Assert.Equal(1, run.Revoked);
        Assert.False(store.Rows.ContainsKey(row.Id));
    }

    [Fact]
    public void TheBackOffDoublesAndIsCappedAtADay()
    {
        Assert.Equal(TimeSpan.FromMinutes(30), PendingAppleRevocationPolicy.DelayAfter(1));
        Assert.Equal(TimeSpan.FromHours(1), PendingAppleRevocationPolicy.DelayAfter(2));
        Assert.Equal(PendingAppleRevocationPolicy.MaxDelay, PendingAppleRevocationPolicy.DelayAfter(500));
    }

    private sealed class MemoryPendingStore : IPendingAppleRevocationStore
    {
        public Dictionary<Guid, (PendingAppleRevocation Row, DateTimeOffset Next, DateTimeOffset Expires)> Rows { get; } = [];

        public Task<int> DeleteExpiredAsync(DateTimeOffset now, CancellationToken cancellationToken)
        {
            var gone = Rows.Where(r => r.Value.Expires <= now).Select(r => r.Key).ToList();
            gone.ForEach(id => Rows.Remove(id));
            return Task.FromResult(gone.Count);
        }

        public Task<IReadOnlyList<PendingAppleRevocation>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<PendingAppleRevocation>>(
                [.. Rows.Values.Where(r => r.Next <= now && r.Expires > now).OrderBy(r => r.Next).Take(limit).Select(r => r.Row)]);

        public Task DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            Rows.Remove(id);
            return Task.CompletedTask;
        }

        public Task DeferAsync(Guid id, int attempts, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
        {
            Rows[id] = (Rows[id].Row with { Attempts = attempts }, nextAttemptAt, Rows[id].Expires);
            return Task.CompletedTask;
        }
    }
}
