using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-130 design note §3: the acknowledge sweeper's decisions over a fake Play API and an in-memory store (AC 3).</summary>
public class PlayAckSweepJobTests
{
    private readonly FakePlayDeveloperApi play = new();
    private readonly RecordingPurchaseTelemetry telemetry = new();
    private readonly FixedClock clock = new(Play.Now);
    private readonly MemorySweepStore store = new();

    private PlayAckSweepJob Job => new(store, play, Play.Catalog, telemetry, clock);

    [Fact]
    public async Task AnActiveUnacknowledgedPurchaseIsAcknowledgedWithThePlayProductId()
    {
        var token = AddRow(Play.Monthly, StoredPurchaseState.Active, Play.Now.AddHours(-1));
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), productId: Play.Monthly);

        var run = await Job.RunOnceAsync(CancellationToken.None);

        Assert.True(run.Ran);
        Assert.Equal(1, run.Acknowledged);
        var ack = Assert.Single(play.Calls, c => c.Api == PlayApi.SubscriptionAcknowledge);
        Assert.Equal(Play.Monthly, ack.ProductId);
        Assert.Equal(StoreLane.Ack, ack.Lane);
        Assert.True(store.Rows[token].Acknowledged);
        Assert.Contains((PurchaseTags.ChannelSweeper, PurchaseTags.AckAcked), telemetry.Acks);
    }

    [Fact]
    public async Task APurchasePlayAlreadyShowsAcknowledgedIsMarkedWithoutAnAcknowledgeCall()
    {
        var token = AddRow(Play.Lifetime, StoredPurchaseState.Active, Play.Now.AddHours(-2));
        play.Products[token] = Play.Product(Play.NewInstall(), acknowledged: true);

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, play.CallsTo(PlayApi.ProductAcknowledge));
        Assert.True(store.Rows[token].Acknowledged);
        Assert.Contains((PurchaseTags.ChannelSweeper, PurchaseTags.AckAlready), telemetry.Acks);
    }

    [Theory]
    [InlineData(PlaySubscriptionState.Expired, StoredPurchaseState.Expired)]
    [InlineData(PlaySubscriptionState.OnHold, StoredPurchaseState.OnHold)]
    [InlineData(PlaySubscriptionState.PendingPurchaseCanceled, StoredPurchaseState.Expired)]
    public async Task ACancelledOrExpiredSubscriptionIsRecordedAndNeverAcknowledged(PlaySubscriptionState state, StoredPurchaseState stored)
    {
        var token = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-3));
        play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), state, expiry: Play.Now.AddDays(-1));

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
        Assert.Equal(stored, store.Rows[token].State);
        Assert.False(store.Rows[token].Acknowledged);
    }

    [Fact]
    public async Task ARefundedLifetimePurchaseIsRecordedAndNeverAcknowledged()
    {
        var token = AddRow(Play.Lifetime, StoredPurchaseState.Active, Play.Now.AddHours(-3));
        play.Products[token] = Play.Product(Play.NewInstall(), PlayProductState.Cancelled);

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, play.CallsTo(PlayApi.ProductAcknowledge));
        Assert.Equal(StoredPurchaseState.Refunded, store.Rows[token].State);
    }

    [Fact]
    public async Task APendingPurchaseWaitsAndOneThatBecamePurchasedIsAcknowledged()
    {
        var waiting = AddRow(Play.Yearly, StoredPurchaseState.Pending, Play.Now.AddHours(-5));
        var completed = AddRow(Play.Lifetime, StoredPurchaseState.Pending, Play.Now.AddHours(-4));
        play.Subscriptions[waiting] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Pending);
        play.Products[completed] = Play.Product(Play.NewInstall(), PlayProductState.Purchased);

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Pending, store.Rows[waiting].State);
        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
        Assert.Equal(StoredPurchaseState.Active, store.Rows[completed].State);
        Assert.True(store.Rows[completed].Acknowledged);
    }

    [Fact]
    public async Task APurchaseUnacknowledgedFor48HoursSetsTheGaugeAndRaisesTheAlert()
    {
        var overdue = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-49));
        var fresh = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-1));
        AddRow(Play.Yearly, StoredPurchaseState.Pending, Play.Now.AddHours(-60));

        // Play is down for both: nothing gets acknowledged this run.
        play.Fail(PlayApi.SubscriptionGet, PlayCallOutcome.ServerError, times: 3);

        var run = await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(3, run.Failed);
        Assert.Equal((1L, 1L), (telemetry.Unacked!.Value.Fresh, telemetry.Unacked.Value.Overdue));
        Assert.Equal(TimeSpan.FromHours(49), telemetry.Unacked.Value.Oldest);
        Assert.Equal([store.Rows[overdue].Id], telemetry.Alerts);
        Assert.DoesNotContain(store.Rows[fresh].Id, telemetry.Alerts);
    }

    [Fact]
    public async Task AnExhaustedAckBudgetEndsTheRunEarly()
    {
        var first = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-3));
        var second = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-2));
        play.Subscriptions[first] = Play.Subscription(Play.NewInstall());
        play.Subscriptions[second] = Play.Subscription(Play.NewInstall());
        play.Fail(PlayApi.SubscriptionGet, PlayCallOutcome.BudgetDenied);

        var run = await Job.RunOnceAsync(CancellationToken.None);

        Assert.True(run.BudgetExhausted);
        Assert.Equal(1, play.CallsTo(PlayApi.SubscriptionGet));
        Assert.False(store.Rows[second].Acknowledged);
    }

    [Fact]
    public async Task ARunThatCantTakeTheLockDoesNothing()
    {
        AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-3));
        store.LockHeldElsewhere = true;

        var run = await Job.RunOnceAsync(CancellationToken.None);

        Assert.False(run.Ran);
        Assert.Empty(play.Calls);
        Assert.Null(telemetry.Unacked);
    }

    [Fact]
    public async Task AnUnknownStateOrAProductMismatchIsLeftAlone()
    {
        var unknown = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-3));
        var mismatch = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-2));
        play.Subscriptions[unknown] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Unknown);
        play.Subscriptions[mismatch] = Play.Subscription(Play.NewInstall(), productId: Play.Monthly);

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, play.CallsTo(PlayApi.SubscriptionAcknowledge));
        Assert.Equal(0, store.Applied);
    }

    private string AddRow(string productId, StoredPurchaseState state, DateTimeOffset createdAt)
    {
        var token = Play.NewToken();
        store.Rows[token] = new MemorySweepStore.Row(Guid.NewGuid(), productId, state, false, createdAt);
        return token;
    }

    /// <summary>The sweeper store over a dictionary, with the store's listing and summary rules.</summary>
    private sealed class MemorySweepStore : IPlayAckSweepStore
    {
        public Dictionary<string, Row> Rows { get; } = new(StringComparer.Ordinal);

        public bool LockHeldElsewhere { get; set; }

        public int Applied { get; private set; }

        public Task<IAsyncDisposable?> TryLockAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IAsyncDisposable?>(LockHeldElsewhere ? null : new Held());

        public Task<IReadOnlyList<UnackedPurchase>> ListAsync(int limit, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<UnackedPurchase>>([.. Rows
                .Where(r => !r.Value.Acknowledged && (r.Value.State == StoredPurchaseState.Pending || PlayStateMapping.IsAckable(r.Value.State)))
                .OrderBy(r => r.Value.CreatedAt)
                .Take(limit)
                .Select(r => new UnackedPurchase(r.Value.Id, r.Value.ProductId, new Sensitive<string>(r.Key), r.Value.State, r.Value.CreatedAt))]);

        public Task<bool> ApplyAsync(SweepUpdate update, CancellationToken cancellationToken)
        {
            Applied++;
            var entry = Rows.Single(r => r.Value.Id == update.Id);
            Rows[entry.Key] = entry.Value with { State = update.State, Acknowledged = entry.Value.Acknowledged || update.Acknowledged };
            return Task.FromResult(true);
        }

        public Task<UnackedSummary> SummarizeAsync(DateTimeOffset now, int maxOverdue, CancellationToken cancellationToken)
        {
            var ackable = Rows.Values.Where(r => !r.Acknowledged && PlayStateMapping.IsAckable(r.State)).ToList();
            var cutoff = now - PlayAckSweepJob.AlertAge;
            var overdue = ackable.Where(r => r.CreatedAt <= cutoff).OrderBy(r => r.CreatedAt).ToList();
            var oldest = ackable.Count == 0 ? TimeSpan.Zero : now - ackable.Min(r => r.CreatedAt);
            return Task.FromResult(new UnackedSummary(ackable.Count - overdue.Count, overdue.Count, oldest, [.. overdue.Take(maxOverdue).Select(r => r.Id)]));
        }

        public sealed record Row(Guid Id, string ProductId, StoredPurchaseState State, bool Acknowledged, DateTimeOffset CreatedAt);

        private sealed class Held : IAsyncDisposable
        {
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }
}
