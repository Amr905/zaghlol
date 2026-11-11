using System.Collections.Concurrent;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

internal sealed class RecordingPlayTelemetry : IPlayNotificationTelemetry
{
    public ConcurrentQueue<(string Kind, string Outcome)> Ingests { get; } = new();

    public ConcurrentQueue<(string Type, string Outcome)> Processed { get; } = new();

    public ConcurrentQueue<(string Step, string Outcome)> Reconciles { get; } = new();

    public int DeadLetters { get; private set; }

    public int RefundsNotReflected { get; private set; }

    public long RecoveredTotal { get; private set; }

    public (long Young, long Old)? Backlog { get; private set; }

    public int BacklogFailures { get; private set; }

    public int Heartbeats { get; private set; }

    public int LagSamples { get; private set; }

    public void Ingested(string kind, string outcome) => Ingests.Enqueue((kind, outcome));

    void IPlayNotificationTelemetry.Processed(string type, string outcome) => Processed.Enqueue((type, outcome));

    public void Lag(TimeSpan lag) => LagSamples++;

    public void DeadLettered() => DeadLetters++;

    public void SetBacklog(long lessThan1h, long atLeast1h) => Backlog = (lessThan1h, atLeast1h);

    public void BacklogFailed() => BacklogFailures++;

    public void Reconciled(string job, string outcome) => Reconciles.Enqueue((job, outcome));

    public void Recovered(int count) => RecoveredTotal += count;

    public void RefundNotReflected() => RefundsNotReflected++;

    public void Heartbeat() => Heartbeats++;
}

/// <summary>
/// The Google worker's rows in memory, with the database's rules: the monotonic guard, the label rule under the "lock", an event only
/// on a state change, the processed mark in the same "transaction", the sweep-key skip, and a lock that can be held elsewhere.
/// </summary>
internal sealed class FakePlayNotificationStore(TimeProvider clock) : IPlayNotificationStore, IStoreNotificationInbox
{
    public sealed class Notification
    {
        public required Guid Id { get; init; }

        public required string ExternalId { get; init; }

        public required string Type { get; init; }

        public string? Subtype { get; init; }

        public string? StoreKey { get; init; }

        public PurchaseEnvironment? Environment { get; init; }

        public DateTimeOffset ReceivedAt { get; init; }

        public int Attempts { get; set; }

        public DateTimeOffset? NextAttemptAt { get; set; }

        public DateTimeOffset? ProcessedAt { get; set; }

        public string? LastError { get; set; }

        public byte[] Digest { get; init; } = [];

        public DateTimeOffset EventTime { get; init; }
    }

    public sealed class Purchase
    {
        public required Guid Id { get; init; }

        public required string StoreKey { get; init; }

        public required string ProductId { get; init; }

        public PurchaseEnvironment Environment { get; init; }

        public StoredPurchaseState State { get; set; }

        public DateTimeOffset? ExpiresAt { get; set; }

        public DateTimeOffset LastVerifiedAt { get; set; }
    }

    public bool LockTakenElsewhere { get; set; }

    public List<string> LocksTaken { get; } = [];

    public List<Notification> Notifications { get; } = [];

    public List<Purchase> Purchases { get; } = [];

    public List<(Guid Purchase, StoredPurchaseState From, StoredPurchaseState To, string Cause)> Events { get; } = [];

    /// <summary>Throws from <see cref="FindPurchaseAsync"/> for this token (an unexpected per-row failure).</summary>
    public string? ThrowOnFind { get; set; }

    public bool BacklogThrows { get; set; }

    public int Inserts { get; private set; }

    public Notification Add(string type, string? storeKey, string? externalId = null, int attempts = 0, DateTimeOffset? receivedAt = null, PurchaseEnvironment? environment = null, string? subtype = null)
    {
        var row = new Notification
        {
            Id = Guid.CreateVersion7(),
            ExternalId = externalId ?? Guid.NewGuid().ToString("N"),
            Type = type,
            StoreKey = storeKey,
            Environment = environment,
            Subtype = subtype,
            Attempts = attempts,
            ReceivedAt = receivedAt ?? clock.GetUtcNow(),
        };
        Notifications.Add(row);
        return row;
    }

    public Purchase AddPurchase(string storeKey, string productId, StoredPurchaseState state, DateTimeOffset? expiresAt = null, PurchaseEnvironment environment = PurchaseEnvironment.Production, DateTimeOffset? lastVerifiedAt = null)
    {
        var purchase = new Purchase
        {
            Id = Guid.CreateVersion7(),
            StoreKey = storeKey,
            ProductId = productId,
            State = state,
            ExpiresAt = expiresAt,
            Environment = environment,
            LastVerifiedAt = lastVerifiedAt ?? clock.GetUtcNow().AddHours(-1),
        };
        Purchases.Add(purchase);
        return purchase;
    }

    public Task<IAsyncDisposable?> TryLockAsync(string name, CancellationToken cancellationToken)
    {
        LocksTaken.Add(name);
        return Task.FromResult<IAsyncDisposable?>(LockTakenElsewhere ? null : new Released());
    }

    public Task<IReadOnlyList<DuePlayNotification>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<DuePlayNotification>>(
        [
            .. Notifications
                .Where(n => n.ProcessedAt is null && (n.NextAttemptAt is null || n.NextAttemptAt <= now))
                .OrderBy(n => n.NextAttemptAt is null ? 0 : 1).ThenBy(n => n.NextAttemptAt).ThenBy(n => n.ReceivedAt)
                .Take(limit)
                .Select(n => new DuePlayNotification(n.Id, n.ExternalId, n.Type, n.Subtype, n.StoreKey is null ? null : new Sensitive<string>(n.StoreKey), n.Environment, n.Attempts, n.ReceivedAt)),
        ]);

    public Task<PlayPurchaseRow?> FindPurchaseAsync(Sensitive<string> storeKey, CancellationToken cancellationToken)
    {
        if (ThrowOnFind is not null && storeKey.Reveal() == ThrowOnFind)
        {
            throw new InvalidOperationException("boom");
        }

        var p = Purchases.SingleOrDefault(p => p.StoreKey == storeKey.Reveal());
        return Task.FromResult(p is null ? null : new PlayPurchaseRow(p.Id, new Sensitive<string>(p.StoreKey), p.ProductId, p.Environment, p.State));
    }

    public Task<PlayWriteResult> ApplyAsync(PlayStateWrite write, Guid notificationId, CancellationToken cancellationToken)
    {
        var p = Purchases.SingleOrDefault(p => p.Id == write.PurchaseId);
        PlayWriteResult result;
        if (p is null)
        {
            result = PlayWriteResult.Gone;
        }
        else if (p.LastVerifiedAt >= write.ReadAt)
        {
            result = PlayWriteResult.Superseded;
        }
        else if (write.OnlyFromPending && p.State != StoredPurchaseState.Pending)
        {
            result = PlayWriteResult.Unchanged;
        }
        else
        {
            var state = PlayStateMapping.Settle(p.State, write.Read, write.SettleType);
            var from = p.State;
            p.State = state;
            p.ExpiresAt = write.KeepStoredExpiry ? p.ExpiresAt : write.ExpiresAt;
            p.LastVerifiedAt = write.ReadAt;
            if (from == state)
            {
                result = PlayWriteResult.Unchanged;
            }
            else
            {
                Events.Add((p.Id, from, state, write.Cause));
                result = PlayWriteResult.Applied;
            }
        }

        var n = Notifications.Single(n => n.Id == notificationId);
        n.ProcessedAt = clock.GetUtcNow();
        n.LastError = result == PlayWriteResult.Gone ? PlayNotificationSchedule.NoPurchase : null;
        return Task.FromResult(result);
    }

    public Task CompleteAsync(Guid notificationId, string? code, CancellationToken cancellationToken)
    {
        var n = Notifications.Single(n => n.Id == notificationId);
        n.ProcessedAt = clock.GetUtcNow();
        n.LastError = code;
        return Task.CompletedTask;
    }

    public Task FailAsync(Guid notificationId, int attempts, DateTimeOffset? nextAttemptAt, string code, CancellationToken cancellationToken)
    {
        var n = Notifications.Single(n => n.Id == notificationId);
        n.Attempts = attempts;
        n.LastError = code;
        n.NextAttemptAt = nextAttemptAt;
        n.ProcessedAt = nextAttemptAt is null ? clock.GetUtcNow() : null;
        return Task.CompletedTask;
    }

    public Task DeferAsync(Guid notificationId, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
    {
        Notifications.Single(n => n.Id == notificationId).NextAttemptAt = nextAttemptAt;
        return Task.CompletedTask;
    }

    public Task<(long LessThan1h, long AtLeast1h)> BacklogAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (BacklogThrows)
        {
            throw new InvalidOperationException("backlog");
        }

        var open = Notifications.Where(n => n.ProcessedAt is null).ToList();
        return Task.FromResult(((long)open.Count(n => n.ReceivedAt > now.AddHours(-1)), (long)open.Count(n => n.ReceivedAt <= now.AddHours(-1))));
    }

    public Task<IReadOnlyList<PlayExpiredSubscription>> ListExpiredSubscriptionsAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<PlayExpiredSubscription>>(
        [
            .. Purchases
                .Where(p => p.ProductId != Play.Lifetime && PlayStateMapping.IsEntitling(p.State) && p.ExpiresAt is { } e
                    && e >= now.AddDays(-7) && e <= now.AddMinutes(-10) && p.LastVerifiedAt < e
                    && !Notifications.Any(n => n.ExternalId == PlayJobKeys.Sweep(p.Id, e)))
                .OrderBy(p => p.ExpiresAt)
                .Take(limit)
                .Select(p => new PlayExpiredSubscription(p.Id, new Sensitive<string>(p.StoreKey), p.ExpiresAt!.Value)),
        ]);

    public Task<bool> HasRtdnVoidedAsync(Sensitive<string> storeKey, CancellationToken cancellationToken) =>
        Task.FromResult(Notifications.Any(n => n.Type == PlayRtdnTypes.VoidedPurchase && n.StoreKey == storeKey.Reveal()
            && !n.ExternalId.StartsWith(PlayJobKeys.VoidedPrefix, StringComparison.Ordinal)));

    public Task<bool> TryInsertAsync(StoreNotificationRecord record, CancellationToken cancellationToken)
    {
        Inserts++;
        if (Notifications.Any(n => n.ExternalId == record.ExternalId))
        {
            return Task.FromResult(false);
        }

        Notifications.Add(new Notification
        {
            Id = record.Id,
            ExternalId = record.ExternalId,
            Type = record.Type,
            Subtype = record.Subtype,
            StoreKey = record.StoreKey?.Reveal(),
            Environment = record.Environment,
            ReceivedAt = clock.GetUtcNow(),
            ProcessedAt = record.Processed ? clock.GetUtcNow() : null,
            LastError = record.LastError,
            Digest = record.PayloadDigest,
            EventTime = record.EventTime,
        });
        return Task.FromResult(true);
    }

    private sealed class Released : IAsyncDisposable
    {
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
