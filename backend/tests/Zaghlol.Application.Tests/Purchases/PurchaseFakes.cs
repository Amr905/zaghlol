using System.Collections.Concurrent;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>A clock the tests set.</summary>
internal sealed class FixedClock(DateTimeOffset now) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = now;

    public override DateTimeOffset GetUtcNow() => Now;
}

/// <summary>
/// The Play Developer API stand-in for unit tests: answers by token from <see cref="Subscriptions"/>, <see cref="Products"/> and
/// <see cref="Orders"/>, or throws the queued <see cref="PlayApiException"/>; records every call.
/// </summary>
internal sealed class FakePlayDeveloperApi : IPlayDeveloperApi
{
    public Dictionary<string, PlaySubscription> Subscriptions { get; } = new(StringComparer.Ordinal);

    public Dictionary<string, PlayProduct> Products { get; } = new(StringComparer.Ordinal);

    public Dictionary<string, PlayOrder> Orders { get; } = new(StringComparer.Ordinal);

    /// <summary>Failures by API, consumed one per call (then the call succeeds).</summary>
    public Dictionary<PlayApi, Queue<PlayCallOutcome>> Failures { get; } = [];

    public ConcurrentQueue<(PlayApi Api, string Subject, string? ProductId, StoreLane Lane)> Calls { get; } = new();

    public void Fail(PlayApi api, PlayCallOutcome outcome, int times = 1)
    {
        if (!Failures.TryGetValue(api, out var queue))
        {
            Failures[api] = queue = new Queue<PlayCallOutcome>();
        }

        for (var i = 0; i < times; i++)
        {
            queue.Enqueue(outcome);
        }
    }

    public int CallsTo(PlayApi api) => Calls.Count(c => c.Api == api);

    public Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(PlayApi.SubscriptionGet, token.Reveal(), null, lane);
        return Subscriptions.TryGetValue(token.Reveal(), out var read)
            ? Task.FromResult(read)
            : throw new PlayApiException(PlayApi.SubscriptionGet, PlayCallOutcome.ClientError, 404);
    }

    public Task<PlayProduct> GetProductAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(PlayApi.ProductGet, token.Reveal(), null, lane);
        return Products.TryGetValue(token.Reveal(), out var read)
            ? Task.FromResult(read)
            : throw new PlayApiException(PlayApi.ProductGet, PlayCallOutcome.ClientError, 404);
    }

    public Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(PlayApi.SubscriptionAcknowledge, token.Reveal(), productId, lane);
        if (Subscriptions.TryGetValue(token.Reveal(), out var read))
        {
            Subscriptions[token.Reveal()] = read with { Acknowledged = true };
        }

        return Task.CompletedTask;
    }

    public Task AcknowledgeProductAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(PlayApi.ProductAcknowledge, token.Reveal(), productId, lane);
        if (Products.TryGetValue(token.Reveal(), out var read))
        {
            Products[token.Reveal()] = read with { Acknowledged = true };
        }

        return Task.CompletedTask;
    }

    public Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(PlayApi.OrderGet, orderId.Reveal(), null, lane);
        return Orders.TryGetValue(orderId.Reveal(), out var order)
            ? Task.FromResult(order)
            : throw new PlayApiException(PlayApi.OrderGet, PlayCallOutcome.ClientError, 404);
    }

    /// <summary>Pages of <c>voidedpurchases.list</c>, served in order (an empty listing when none is left).</summary>
    public Queue<PlayVoidedPage> VoidedPages { get; } = new();

    /// <summary>Every voided-list request: the window and the page token.</summary>
    public List<(DateTimeOffset From, DateTimeOffset Until, string? PageToken, StoreLane Lane)> VoidedRequests { get; } = [];

    public Task<PlayVoidedPage> ListVoidedPurchasesAsync(
        DateTimeOffset from,
        DateTimeOffset until,
        Sensitive<string>? pageToken,
        StoreLane lane,
        CancellationToken cancellationToken)
    {
        VoidedRequests.Add((from, until, pageToken?.Reveal(), lane));
        Record(PlayApi.VoidedList, "voided", null, lane);
        return Task.FromResult(VoidedPages.TryDequeue(out var page) ? page : new PlayVoidedPage([], null));
    }

    private void Record(PlayApi api, string subject, string? productId, StoreLane lane)
    {
        Calls.Enqueue((api, subject, productId, lane));
        if (Failures.TryGetValue(api, out var queue) && queue.TryDequeue(out var outcome))
        {
            throw new PlayApiException(api, outcome, outcome == PlayCallOutcome.ClientError ? 400 : 503);
        }
    }
}

/// <summary>
/// An in-memory <c>purchases</c> table with the writer's rules: the monotonic guard, insert-only install, App Store re-plan on an
/// applied update, <c>KeepStoredExpiry</c>, and the T-131 new-payment rule on <c>last_payment_at</c> (independent of the guard).
/// </summary>
internal sealed class FakePurchaseWriter : IPurchaseWriter
{
    private readonly Lock gate = new();

    public Dictionary<string, Row> Rows { get; } = new(StringComparer.Ordinal);

    public List<(Guid Purchase, StoredPurchaseState? From, StoredPurchaseState To, string Cause)> Events { get; } = [];

    public int Upserts { get; private set; }

    /// <summary>Upserts seen, for assertions on what the verifier passed.</summary>
    public List<PurchaseUpsert> Seen { get; } = [];

    public Task<PurchaseUpsertResult> UpsertAsync(PurchaseUpsert upsert, string cause, CancellationToken cancellationToken)
    {
        lock (gate)
        {
            Upserts++;
            Seen.Add(upsert);
            var key = upsert.StoreKey.Reveal();
            bool applied;
            var inserted = false;
            if (!Rows.TryGetValue(key, out var row))
            {
                row = new Row(Guid.NewGuid(), upsert.ProductId, upsert.InstallId, upsert.State, upsert.ExpiresAt, upsert.Acknowledged, upsert.Environment, upsert.LinkedPurchaseToken?.Reveal(), upsert.ReadAt)
                {
                    Plan = upsert.Plan,
                    ObfuscatedInstallRef = upsert.ObfuscatedInstallRef,
                };
                Rows[key] = row;
                Events.Add((row.Id, null, upsert.State, cause));
                applied = true;
                inserted = true;
            }
            else if (row.LastVerifiedAt < upsert.ReadAt)
            {
                if (row.State != upsert.State)
                {
                    Events.Add((row.Id, row.State, upsert.State, cause));
                }

                var apple = upsert.Store == PurchaseStore.AppStore;
                row = row with
                {
                    State = upsert.State,
                    ExpiresAt = upsert.KeepStoredExpiry ? row.ExpiresAt : upsert.ExpiresAt,
                    Acknowledged = row.Acknowledged || upsert.Acknowledged,
                    Environment = upsert.Environment,
                    LinkedPurchaseToken = upsert.LinkedPurchaseToken?.Reveal() ?? row.LinkedPurchaseToken,
                    LastVerifiedAt = upsert.ReadAt,
                    ProductId = apple ? upsert.ProductId : row.ProductId,
                    Plan = apple ? upsert.Plan : row.Plan,
                    ObfuscatedInstallRef = upsert.ObfuscatedInstallRef ?? row.ObfuscatedInstallRef,
                };
                Rows[key] = row;
                applied = true;
            }
            else
            {
                applied = false;
            }

            var newPayment = false;
            if (upsert.NewPaymentAt is { } paidAt && (row.LastPaymentAt is null || row.LastPaymentAt < paidAt))
            {
                row = row with { LastPaymentAt = paidAt };
                Rows[key] = row;
                newPayment = true;
            }

            Guid? predecessor = row.LinkedPurchaseToken is { } linked && Rows.TryGetValue(linked, out var previous) ? previous.Id : null;
            return Task.FromResult(new PurchaseUpsertResult(row.Id, applied, row.State, row.ExpiresAt, row.Acknowledged, predecessor, inserted, newPayment));
        }
    }

    public Task<bool> MarkAcknowledgedAsync(Guid purchaseId, CancellationToken cancellationToken)
    {
        var entry = Rows.FirstOrDefault(r => r.Value.Id == purchaseId);
        if (entry.Value is null || entry.Value.Acknowledged)
        {
            return Task.FromResult(false);
        }

        Rows[entry.Key] = entry.Value with { Acknowledged = true };
        return Task.FromResult(true);
    }

    public sealed record Row(
        Guid Id,
        string ProductId,
        InstallId? InstallId,
        StoredPurchaseState State,
        DateTimeOffset? ExpiresAt,
        bool Acknowledged,
        PurchaseEnvironment Environment,
        string? LinkedPurchaseToken,
        DateTimeOffset LastVerifiedAt)
    {
        public GoldPlan Plan { get; init; }

        public string? ObfuscatedInstallRef { get; init; }

        public DateTimeOffset? LastPaymentAt { get; init; }
    }
}

/// <summary>Records every telemetry call.</summary>
internal sealed class RecordingPurchaseTelemetry : IPurchaseTelemetry
{
    public List<(string Channel, string Outcome)> Acks { get; } = [];

    public List<Guid> Alerts { get; } = [];

    public List<(string Path, OwnershipOutcome Outcome)> Ownership { get; } = [];

    public (long Fresh, long Overdue, TimeSpan Oldest)? Unacked { get; private set; }

    public int TimeToAckCount { get; private set; }

    public void Verified(string store, string outcome, string code)
    {
    }

    public void Acknowledged(string channel, string outcome) => Acks.Add((channel, outcome));

    public void TimeToAck(TimeSpan sincePurchase) => TimeToAckCount++;

    public void SetUnacked(long lessThan48h, long atLeast48h, TimeSpan oldestAge) => Unacked = (lessThan48h, atLeast48h, oldestAge);

    public void UnackedOver48h(Guid purchaseId) => Alerts.Add(purchaseId);

    public void OwnershipChecked(string path, OwnershipOutcome outcome) => Ownership.Add((path, outcome));

    public List<(string Store, PurchaseEnvironment Environment)> Environments { get; } = [];

    public List<(JwsSource Source, AppleJwsFailure? Failure)> Jws { get; } = [];

    public void EnvironmentSeen(string store, PurchaseEnvironment environment)
    {
        lock (Environments)
        {
            Environments.Add((store, environment));
        }
    }

    public void AppleJwsChecked(JwsSource source, AppleJwsFailure? failure)
    {
        lock (Jws)
        {
            Jws.Add((source, failure));
        }
    }
}

/// <summary>Common fixtures: the three Gold products and Play reads bound to an install.</summary>
internal static class Play
{
    public const string Package = "app.zaghlol";
    public const string Monthly = "zaghlol_gold_monthly";
    public const string Yearly = "zaghlol_gold_yearly";
    public const string Lifetime = "zaghlol_gold_lifetime";

    public static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    public static PlayProductCatalog Catalog { get; } = new(Package, new Dictionary<string, PlayProductDefinition>(StringComparer.Ordinal)
    {
        [Monthly] = new(PlayProductKind.Subscription, GoldPlan.Monthly),
        [Yearly] = new(PlayProductKind.Subscription, GoldPlan.Yearly),
        [Lifetime] = new(PlayProductKind.OneTime, GoldPlan.Lifetime),
    });

    public static InstallId NewInstall() => InstallId.FromGuid(Guid.NewGuid());

    public static string NewToken() => "tok." + Guid.NewGuid().ToString("N") + "-" + Guid.NewGuid().ToString("N");

    public static PlaySubscription Subscription(
        InstallId? boundTo,
        PlaySubscriptionState state = PlaySubscriptionState.Active,
        string productId = Yearly,
        DateTimeOffset? expiry = null,
        bool acknowledged = false,
        bool test = false,
        string? linked = null,
        string? latestSuccessfulOrderId = null) =>
        new(
            state,
            [new PlayLineItem(productId, expiry ?? Now.AddDays(30), latestSuccessfulOrderId is null ? null : new Sensitive<string>(latestSuccessfulOrderId))],
            linked is null ? null : new Sensitive<string>(linked),
            acknowledged,
            test,
            boundTo is { } id ? StoreBindingRef.Compute(id) : null,
            Now.AddMinutes(-2));

    public static PlayProduct Product(
        InstallId? boundTo,
        PlayProductState state = PlayProductState.Purchased,
        string productId = Lifetime,
        bool acknowledged = false,
        bool test = false,
        string? orderId = null) =>
        new(
            [productId],
            state,
            test,
            orderId is null ? null : new Sensitive<string>(orderId),
            boundTo is { } id ? StoreBindingRef.Compute(id) : null,
            acknowledged,
            Now.AddMinutes(-2));
}
