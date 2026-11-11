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

    // Security M-1: stuck rows are deferred and never starve a newer ackable row.

    [Fact]
    public async Task TwoHundredStuckRowsDoNotStarveANewerActivePurchase()
    {
        var stuck = new List<string>();
        for (var i = 0; i < 70; i++)
        {
            // Still pending at Play (slow payment).
            var token = AddRow(Play.Yearly, StoredPurchaseState.Pending, Play.Now.AddHours(-30).AddMinutes(i));
            play.Subscriptions[token] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Pending);
            stuck.Add(token);
        }

        for (var i = 0; i < 65; i++)
        {
            // A product that left the catalog: skipped without a Play call.
            stuck.Add(AddRow("zaghlol_gold_retired", StoredPurchaseState.Active, Play.Now.AddHours(-20).AddMinutes(i)));
        }

        for (var i = 0; i < 65; i++)
        {
            // Play answers 404 for these tokens (the fake has no read for them).
            stuck.Add(AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-10).AddMinutes(i)));
        }

        // An earlier run met all 200 and deferred every one of them.
        var earlier = await Job.RunOnceAsync(CancellationToken.None);
        Assert.Equal(200, earlier.Rows);
        Assert.All(stuck, t => Assert.NotNull(store.Rows[t].NextAttemptAt));

        // Then a newer purchase whose inline acknowledge failed.
        clock.Now = Play.Now.AddMinutes(15);
        var fresh = AddRow(Play.Monthly, StoredPurchaseState.Active, clock.Now.AddMinutes(-5));
        play.Subscriptions[fresh] = Play.Subscription(Play.NewInstall(), productId: Play.Monthly);
        play.Calls.Clear();

        var run = await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Acknowledged);
        Assert.True(store.Rows[fresh].Acknowledged);
        Assert.All(play.Calls, c => Assert.Equal(fresh, c.Subject));
    }

    [Fact]
    public async Task AckableRowsComeBeforePendingOnesEvenTheFirstTime()
    {
        for (var i = 0; i < PlayAckSweepJob.BatchSize; i++)
        {
            var pending = AddRow(Play.Yearly, StoredPurchaseState.Pending, Play.Now.AddHours(-40).AddMinutes(i));
            play.Subscriptions[pending] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Pending);
        }

        var fresh = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddMinutes(-1));
        play.Subscriptions[fresh] = Play.Subscription(Play.NewInstall());

        var run = await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Acknowledged);
        Assert.True(store.Rows[fresh].Acknowledged);
    }

    [Fact]
    public async Task RowsTheRunCantFinishAreDeferredByAge()
    {
        var pending = AddRow(Play.Yearly, StoredPurchaseState.Pending, Play.Now.AddHours(-4));
        play.Subscriptions[pending] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Pending);
        var retired = AddRow("zaghlol_gold_retired", StoredPurchaseState.Active, Play.Now.AddHours(-30));
        var notFound = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddMinutes(-20));
        var noExpiry = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-80));
        play.Subscriptions[noExpiry] = Play.Subscription(Play.NewInstall()) with { LineItems = [new PlayLineItem(Play.Yearly, null, null)] };
        var acked = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-1));
        play.Subscriptions[acked] = Play.Subscription(Play.NewInstall());
        var expired = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-1));
        play.Subscriptions[expired] = Play.Subscription(Play.NewInstall(), PlaySubscriptionState.Expired, expiry: Play.Now.AddDays(-1));

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(Play.Now.AddHours(1), store.Rows[pending].NextAttemptAt);
        Assert.Equal(Play.Now.AddHours(2), store.Rows[retired].NextAttemptAt);
        Assert.Equal(Play.Now.AddMinutes(15), store.Rows[notFound].NextAttemptAt);
        Assert.Equal(Play.Now.AddHours(24), store.Rows[noExpiry].NextAttemptAt);
        Assert.Equal(StoredPurchaseState.Active, store.Rows[noExpiry].State); // L-1: an unknown read is never written

        // Finished rows leave the queue without a stamp.
        Assert.Null(store.Rows[acked].NextAttemptAt);
        Assert.Null(store.Rows[expired].NextAttemptAt);
        Assert.Equal(4, store.Deferred);
    }

    [Fact]
    public async Task ARowLeftByAnExhaustedBudgetIsNotDeferred()
    {
        var first = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-3));
        play.Subscriptions[first] = Play.Subscription(Play.NewInstall());
        play.Fail(PlayApi.SubscriptionGet, PlayCallOutcome.BudgetDenied);

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Null(store.Rows[first].NextAttemptAt);
        Assert.Equal(0, store.Deferred);
    }

    [Fact]
    public async Task ARowPastTheRefundAgeNoLongerPages()
    {
        AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-73));
        var overdue = AddRow(Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-50));

        await Job.RunOnceAsync(CancellationToken.None);

        Assert.Equal((0L, 1L), (telemetry.Unacked!.Value.Fresh, telemetry.Unacked.Value.Overdue));
        Assert.Equal([store.Rows[overdue].Id], telemetry.Alerts);
    }

    private string AddRow(string productId, StoredPurchaseState state, DateTimeOffset createdAt)
    {
        var token = Play.NewToken();
        store.Rows[token] = new MemorySweepStore.Row(Guid.NewGuid(), productId, state, false, createdAt, null);
        return token;
    }

    /// <summary>The sweeper store over a dictionary, with the store's listing, deferral and summary rules.</summary>
    private sealed class MemorySweepStore : IPlayAckSweepStore
    {
        public Dictionary<string, Row> Rows { get; } = new(StringComparer.Ordinal);

        public bool LockHeldElsewhere { get; set; }

        public int Applied { get; private set; }

        public int Deferred { get; private set; }

        public Task<IAsyncDisposable?> TryLockAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IAsyncDisposable?>(LockHeldElsewhere ? null : new Held());

        public Task<IReadOnlyList<UnackedPurchase>> ListAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<UnackedPurchase>>([.. Rows
                .Where(r => !r.Value.Acknowledged && (r.Value.State == StoredPurchaseState.Pending || PlayStateMapping.IsAckable(r.Value.State)))
                .Where(r => PlayAckSweepSchedule.IsDue(r.Value.NextAttemptAt, now))
                .OrderBy(r => PlayAckSweepSchedule.SortKey(r.Value.State, r.Value.NextAttemptAt, r.Value.CreatedAt))
                .Take(limit)
                .Select(r => new UnackedPurchase(r.Value.Id, r.Value.ProductId, new Sensitive<string>(r.Key), r.Value.State, r.Value.CreatedAt))]);

        public Task DeferAsync(Guid id, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
        {
            Deferred++;
            var entry = Rows.Single(r => r.Value.Id == id);
            Rows[entry.Key] = entry.Value with { NextAttemptAt = nextAttemptAt };
            return Task.CompletedTask;
        }

        public Task<bool> ApplyAsync(SweepUpdate update, CancellationToken cancellationToken)
        {
            Applied++;
            var entry = Rows.Single(r => r.Value.Id == update.Id);
            Rows[entry.Key] = entry.Value with { State = update.State, Acknowledged = entry.Value.Acknowledged || update.Acknowledged };
            return Task.FromResult(true);
        }

        public Task<UnackedSummary> SummarizeAsync(DateTimeOffset now, int maxOverdue, CancellationToken cancellationToken)
        {
            var ackable = Rows.Values
                .Where(r => !r.Acknowledged && PlayStateMapping.IsAckable(r.State) && r.CreatedAt > now - PlayAckSweepSchedule.RefundAge)
                .ToList();
            var cutoff = now - PlayAckSweepJob.AlertAge;
            var overdue = ackable.Where(r => r.CreatedAt <= cutoff).OrderBy(r => r.CreatedAt).ToList();
            var oldest = ackable.Count == 0 ? TimeSpan.Zero : now - ackable.Min(r => r.CreatedAt);
            return Task.FromResult(new UnackedSummary(ackable.Count - overdue.Count, overdue.Count, oldest, [.. overdue.Take(maxOverdue).Select(r => r.Id)]));
        }

        public sealed record Row(Guid Id, string ProductId, StoredPurchaseState State, bool Acknowledged, DateTimeOffset CreatedAt, DateTimeOffset? NextAttemptAt);

        private sealed class Held : IAsyncDisposable
        {
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }
}
