using System.Collections.Concurrent;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>An in-memory <c>store_notifications</c> insert with the unique (store, external_id) key.</summary>
internal sealed class FakeInbox : IStoreNotificationInbox
{
    public ConcurrentDictionary<string, StoreNotificationRecord> Rows { get; } = new(StringComparer.Ordinal);

    public int Calls { get; private set; }

    public Task<bool> TryInsertAsync(StoreNotificationRecord record, CancellationToken cancellationToken)
    {
        Calls++;
        return Task.FromResult(Rows.TryAdd(record.Store + "|" + record.ExternalId, record));
    }
}

/// <summary>Records the ASSN metrics.</summary>
internal sealed class RecordingNotificationTelemetry : IAppleNotificationTelemetry
{
    public ConcurrentQueue<(string Env, string Outcome)> Ingests { get; } = new();

    public ConcurrentQueue<(string Type, string Outcome)> Processed { get; } = new();

    public ConcurrentQueue<(string Step, string Outcome)> Reconciles { get; } = new();

    public int DeadLetters { get; private set; }

    public int RefundsNotReflected { get; private set; }

    public long RecoveredTotal { get; private set; }

    public (long Young, long Old)? Backlog { get; private set; }

    public int LagSamples { get; private set; }

    public void Ingested(string env, string outcome) => Ingests.Enqueue((env, outcome));

    void IAppleNotificationTelemetry.Processed(string type, string outcome) => Processed.Enqueue((type, outcome));

    public void Lag(TimeSpan lag) => LagSamples++;

    public void DeadLettered() => DeadLetters++;

    public void SetBacklog(long lessThan1h, long atLeast1h) => Backlog = (lessThan1h, atLeast1h);

    public void Reconciled(string job, string outcome) => Reconciles.Enqueue((job, outcome));

    public void Recovered(int count) => RecoveredTotal += count;

    public void RefundNotReflected() => RefundsNotReflected++;

    public int Heartbeats { get; private set; }

    public int BacklogFailures { get; private set; }

    public void Heartbeat() => Heartbeats++;

    public void BacklogFailed() => BacklogFailures++;
}

/// <summary>
/// The worker's rows in memory, with the database's rules: the monotonic guard, an event only on a state change, the processed
/// mark in the same "transaction", and a lock that can be held by someone else.
/// </summary>
internal sealed class FakeNotificationStore : IAppleNotificationStore
{
    public sealed class Notification
    {
        public required Guid Id { get; init; }

        public required string Type { get; init; }

        public string? StoreKey { get; init; }

        public PurchaseEnvironment? Environment { get; init; }

        public DateTimeOffset ReceivedAt { get; init; }

        public int Attempts { get; set; }

        public DateTimeOffset? NextAttemptAt { get; set; }

        public DateTimeOffset? ProcessedAt { get; set; }

        public string? LastError { get; set; }
    }

    public sealed class Purchase
    {
        public required Guid Id { get; init; }

        public required string StoreKey { get; init; }

        public required string ProductId { get; set; }

        public GoldPlan Plan { get; set; }

        public PurchaseEnvironment Environment { get; init; }

        public StoredPurchaseState State { get; set; }

        public DateTimeOffset? ExpiresAt { get; set; }

        public DateTimeOffset LastVerifiedAt { get; set; }
    }

    public FakeNotificationStore(TimeProvider clock) => Clock = clock;

    public TimeProvider Clock { get; }

    public bool LockTakenElsewhere { get; set; }

    public List<string> LocksTaken { get; } = [];

    public List<Notification> Notifications { get; } = [];

    public List<Purchase> Purchases { get; } = [];

    public List<(Guid Purchase, StoredPurchaseState From, StoredPurchaseState To, string Cause)> Events { get; } = [];

    public List<ApplePurchaseRow> Expired { get; } = [];

    public Notification Add(string type, string? storeKey, PurchaseEnvironment? environment = PurchaseEnvironment.Production, int attempts = 0)
    {
        var row = new Notification
        {
            Id = Guid.CreateVersion7(),
            Type = type,
            StoreKey = storeKey,
            Environment = environment,
            Attempts = attempts,
            ReceivedAt = Clock.GetUtcNow().AddSeconds(-30),
        };
        Notifications.Add(row);
        return row;
    }

    public Purchase AddPurchase(string storeKey, string productId, GoldPlan plan, StoredPurchaseState state, PurchaseEnvironment environment = PurchaseEnvironment.Production, DateTimeOffset? lastVerifiedAt = null)
    {
        var row = new Purchase
        {
            Id = Guid.CreateVersion7(),
            StoreKey = storeKey,
            ProductId = productId,
            Plan = plan,
            Environment = environment,
            State = state,
            ExpiresAt = Clock.GetUtcNow().AddDays(10),
            LastVerifiedAt = lastVerifiedAt ?? Clock.GetUtcNow().AddHours(-1),
        };
        Purchases.Add(row);
        return row;
    }

    public Task<IAsyncDisposable?> TryLockAsync(string name, CancellationToken cancellationToken)
    {
        LocksTaken.Add(name);
        return Task.FromResult<IAsyncDisposable?>(LockTakenElsewhere ? null : new Held());
    }

    public Task<IReadOnlyList<DueAppleNotification>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<DueAppleNotification>>(
        [
            .. Notifications.Where(n => n.ProcessedAt is null && (n.NextAttemptAt is null || n.NextAttemptAt <= now))
                .OrderBy(n => n.NextAttemptAt is null ? 0 : 1).ThenBy(n => n.NextAttemptAt).ThenBy(n => n.ReceivedAt)
                .Take(limit)
                .Select(n => new DueAppleNotification(n.Id, n.Type, n.StoreKey is null ? null : new Sensitive<string>(n.StoreKey), n.Environment, n.Attempts, n.ReceivedAt)),
        ]);

    public Task<ApplePurchaseRow?> FindPurchaseAsync(Sensitive<string> storeKey, CancellationToken cancellationToken) =>
        Task.FromResult(Purchases.FirstOrDefault(p => p.StoreKey == storeKey.Reveal()) is { } p ? Row(p) : null);

    public Task<AppleWriteResult> ApplyAsync(AppleStateWrite write, Guid? notificationId, CancellationToken cancellationToken)
    {
        var purchase = Purchases.FirstOrDefault(p => p.Id == write.PurchaseId);
        AppleWriteResult result;
        if (purchase is null)
        {
            result = AppleWriteResult.Gone;
        }
        else if (purchase.LastVerifiedAt >= write.ReadAt)
        {
            result = AppleWriteResult.Superseded;
        }
        else
        {
            var from = purchase.State;
            purchase.State = write.State;
            purchase.ExpiresAt = write.KeepStoredExpiry ? purchase.ExpiresAt : write.ExpiresAt;
            purchase.ProductId = write.ProductId;
            purchase.Plan = write.Plan;
            purchase.LastVerifiedAt = write.ReadAt;
            if (from != write.State)
            {
                Events.Add((purchase.Id, from, write.State, write.Cause));
                result = AppleWriteResult.Applied;
            }
            else
            {
                result = AppleWriteResult.Unchanged;
            }
        }

        if (notificationId is { } id)
        {
            var row = Notifications.Single(n => n.Id == id);
            row.ProcessedAt = Clock.GetUtcNow();
            row.LastError = result == AppleWriteResult.Gone ? AppleNotificationSchedule.NoPurchase : null;
        }

        return Task.FromResult(result);
    }

    public Task CompleteAsync(Guid notificationId, string? code, CancellationToken cancellationToken)
    {
        var row = Notifications.Single(n => n.Id == notificationId);
        row.ProcessedAt = Clock.GetUtcNow();
        row.LastError = code;
        return Task.CompletedTask;
    }

    public Task FailAsync(Guid notificationId, int attempts, DateTimeOffset? nextAttemptAt, string code, CancellationToken cancellationToken)
    {
        var row = Notifications.Single(n => n.Id == notificationId);
        row.Attempts = attempts;
        row.LastError = code;
        row.NextAttemptAt = nextAttemptAt;
        row.ProcessedAt = nextAttemptAt is null ? Clock.GetUtcNow() : null;
        return Task.CompletedTask;
    }

    public Task DeferAsync(Guid notificationId, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
    {
        Notifications.Single(n => n.Id == notificationId).NextAttemptAt = nextAttemptAt;
        return Task.CompletedTask;
    }

    public Task<(long LessThan1h, long AtLeast1h)> BacklogAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        var open = Notifications.Where(n => n.ProcessedAt is null).ToList();
        return Task.FromResult(((long)open.Count(n => n.ReceivedAt > now.AddHours(-1)), (long)open.Count(n => n.ReceivedAt <= now.AddHours(-1))));
    }

    public Task<IReadOnlyList<ApplePurchaseRow>> ListExpiredSubscriptionsAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<ApplePurchaseRow>>([.. Expired.Take(limit)]);

    public static ApplePurchaseRow Row(Purchase p) => new(p.Id, new Sensitive<string>(p.StoreKey), p.ProductId, p.Plan, p.Environment, p.State);

    private sealed class Held : IAsyncDisposable
    {
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
