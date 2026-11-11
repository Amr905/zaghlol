using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Purchases;

/// <summary>A migrated database with the App and Worker logins, as the API and the workers build them.</summary>
public sealed class PurchaseStoreFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IServiceProvider Services => services!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:App"] = Database.Api,
                ["ConnectionStrings:Worker"] = Database.Worker,
            })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Worker);
        collection.AddSingleton<PurchaseWriter>();
        collection.AddTransient<PlayAckSweepStore>();
        services = collection.BuildServiceProvider();
    }

    public async Task DisposeAsync()
    {
        if (services is not null)
        {
            await services.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }
}

/// <summary>T-130: <c>purchases</c> writes of verify (App login) and the sweeper (Worker login) against PostgreSQL 17.</summary>
public class PurchaseStoreTests(PurchaseStoreFixture fixture) : IClassFixture<PurchaseStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private PurchaseWriter Writer => fixture.Services.GetRequiredService<PurchaseWriter>();

    private PlayAckSweepStore Sweep => fixture.Services.GetRequiredService<PlayAckSweepStore>();

    [Fact]
    public async Task AnInsertRecordsTheBuyingInstallAndAVerifyEvent()
    {
        var install = await InstallAsync();
        var token = Token();

        var result = await Writer.UpsertAsync(Upsert(token, install, StoredPurchaseState.Pending, Now), "verify", CancellationToken.None);

        Assert.True(result.Applied);
        Assert.Equal(StoredPurchaseState.Pending, result.State);
        var row = await RowAsync(token);
        Assert.Equal(install.Value, row.InstallId);
        Assert.Equal("pending", row.State);
        Assert.Equal("sandbox", row.Environment);
        Assert.Equal(StoreBindingRef.Compute(install), row.Ref);
        Assert.Equal([(null, "pending", "verify")], await EventsAsync(result.PurchaseId));
    }

    [Fact]
    public async Task ANewerReadUpdatesAnOlderOneDoesNotAndTheBuyingInstallNeverChanges()
    {
        var buyer = await InstallAsync();
        var other = await InstallAsync();
        var token = Token();
        var inserted = await Writer.UpsertAsync(Upsert(token, buyer, StoredPurchaseState.Pending, Now), "verify", CancellationToken.None);

        var newer = await Writer.UpsertAsync(Upsert(token, other, StoredPurchaseState.Active, Now.AddMinutes(1)) with { Acknowledged = true }, "verify", CancellationToken.None);
        var older = await Writer.UpsertAsync(Upsert(token, buyer, StoredPurchaseState.Expired, Now.AddSeconds(30)), "verify", CancellationToken.None);

        Assert.True(newer.Applied);
        Assert.False(older.Applied);
        Assert.Equal(StoredPurchaseState.Active, older.State);
        Assert.True(older.Acknowledged);
        var row = await RowAsync(token);
        Assert.Equal("active", row.State);
        Assert.Equal(buyer.Value, row.InstallId);
        Assert.True(row.Acknowledged);
        Assert.Equal([(null, "pending", "verify"), ("pending", "active", "verify")], await EventsAsync(inserted.PurchaseId));

        // acknowledged never goes back to false.
        var later = await Writer.UpsertAsync(Upsert(token, buyer, StoredPurchaseState.Active, Now.AddMinutes(2)), "verify", CancellationToken.None);
        Assert.True(later.Acknowledged);
    }

    [Fact]
    public async Task ConcurrentUpsertsOfOneTokenMakeOneRow()
    {
        var install = await InstallAsync();
        var token = Token();

        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(i =>
            Writer.UpsertAsync(Upsert(token, install, StoredPurchaseState.Active, Now.AddMilliseconds(i)), "verify", CancellationToken.None)));

        Assert.Single(results.Select(r => r.PurchaseId).Distinct());
        Assert.Equal("active", (await RowAsync(token)).State);
    }

    [Fact]
    public async Task AKnownLinkedTokenIsReportedAsThePredecessorAndLeftUntouched()
    {
        var install = await InstallAsync();
        var old = Token();
        var successor = Token();
        var first = await Writer.UpsertAsync(Upsert(old, install, StoredPurchaseState.Active, Now), "verify", CancellationToken.None);
        var before = await RowAsync(old);

        var second = await Writer.UpsertAsync(Upsert(successor, install, StoredPurchaseState.Active, Now.AddMinutes(1)) with { LinkedPurchaseToken = new Sensitive<string>(old) }, "verify", CancellationToken.None);

        Assert.Equal(first.PurchaseId, second.PredecessorPurchaseId);
        Assert.Equal(before, await RowAsync(old));
        Assert.Null((await Writer.UpsertAsync(Upsert(Token(), install, StoredPurchaseState.Active, Now) with { LinkedPurchaseToken = new Sensitive<string>("unknown.token") }, "verify", CancellationToken.None)).PredecessorPurchaseId);
    }

    [Fact]
    public async Task MarkAcknowledgedIsOneWay()
    {
        var install = await InstallAsync();
        var token = Token();
        var result = await Writer.UpsertAsync(Upsert(token, install, StoredPurchaseState.Active, Now), "verify", CancellationToken.None);

        Assert.True(await Writer.MarkAcknowledgedAsync(result.PurchaseId, CancellationToken.None));
        Assert.False(await Writer.MarkAcknowledgedAsync(result.PurchaseId, CancellationToken.None));
        Assert.True((await RowAsync(token)).Acknowledged);
    }

    [Fact]
    public async Task OnlyOneSweeperHoldsTheLockAcrossInstances()
    {
        await using var first = await Sweep.TryLockAsync(CancellationToken.None);
        Assert.NotNull(first);

        // Another store instance (another replica) can't take it while the first holds it.
        var second = await fixture.Services.GetRequiredService<PlayAckSweepStore>().TryLockAsync(CancellationToken.None);
        Assert.Null(second);

        await first.DisposeAsync();
        await using var third = await Sweep.TryLockAsync(CancellationToken.None);
        Assert.NotNull(third);
    }

    [Fact]
    public async Task TheSweeperListsDueRowsAckableFirstAndSummarizesOnlyRowsPlayHasNotRefundedYet()
    {
        await ExecuteAsync("DELETE FROM zaghlol.purchases WHERE store = 'google_play'");
        var install = await InstallAsync();
        var overdue = await SeedAsync(install, "active", false, Now.AddHours(-50));
        var fresh = await SeedAsync(install, "in_grace", false, Now.AddHours(-2));
        var pending = await SeedAsync(install, "pending", false, Now.AddHours(-70));
        var deferredDue = await SeedAsync(install, "active", false, Now.AddHours(-3), next: Now.AddMinutes(-1));
        await SeedAsync(install, "canceled_active", false, Now.AddHours(-4), next: Now.AddHours(1));
        var pastRefund = await SeedAsync(install, "active", false, Now.AddHours(-80));
        await SeedAsync(install, "expired", false, Now.AddHours(-80));
        await SeedAsync(install, "active", true, Now.AddHours(-90));
        await SeedAsync(install, "refunded", false, Now.AddHours(-60));

        var rows = await Sweep.ListAsync(Now, 200, CancellationToken.None);
        var summary = await Sweep.SummarizeAsync(Now, 50, CancellationToken.None);

        // Ackable before pending, never deferred before deferred, oldest first; a row deferred into the future is left out.
        Assert.Equal([pastRefund, overdue, fresh, deferredDue, pending], rows.Select(r => r.Id));

        // The 80 h row is past Play's 72 h refund: it no longer pages.
        Assert.Equal(3, summary.LessThan48h);
        Assert.Equal(1, summary.AtLeast48h);
        Assert.Equal(TimeSpan.FromHours(50), summary.OldestAge);
        Assert.Equal([overdue], summary.Overdue);
    }

    [Fact]
    public async Task TwoHundredStuckRowsDoNotStarveANewerActivePurchaseOnTheWorkerLogin()
    {
        // Security M-1, against PostgreSQL and the Worker login: pending, retired-product and Play-404 rows at the head of the queue.
        await ExecuteAsync("DELETE FROM zaghlol.purchases WHERE store = 'google_play'");
        var install = await InstallAsync();
        var play = new ScriptedPlay();
        var stuck = new List<Guid>();
        for (var i = 0; i < 70; i++)
        {
            var key = Token();
            stuck.Add(await SeedAsync(install, "pending", false, Now.AddHours(-30).AddMinutes(i), key: key));
            play.Subscriptions[key] = ScriptedPlay.Subscription(PlaySubscriptionState.Pending);
        }

        for (var i = 0; i < 65; i++)
        {
            stuck.Add(await SeedAsync(install, "active", false, Now.AddHours(-20).AddMinutes(i), product: "zaghlol_gold_retired"));
        }

        for (var i = 0; i < 65; i++)
        {
            stuck.Add(await SeedAsync(install, "active", false, Now.AddHours(-10).AddMinutes(i))); // Play: 404
        }

        var clock = new SettableClock(Now);
        var job = new PlayAckSweepJob(Sweep, play, Catalog, new NoTelemetry(), clock);

        var earlier = await job.RunOnceAsync(CancellationToken.None);
        Assert.Equal(200, earlier.Rows);
        foreach (var id in stuck)
        {
            Assert.True(await NextAttemptAsync(id) > Now);
        }

        clock.Now = Now.AddMinutes(15);
        var freshKey = Token();
        var fresh = await SeedAsync(install, "active", false, clock.Now.AddMinutes(-5), key: freshKey);
        play.Subscriptions[freshKey] = ScriptedPlay.Subscription(PlaySubscriptionState.Active);
        play.Calls.Clear();

        var run = await job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Rows);
        Assert.Equal(1, run.Acknowledged);
        Assert.All(play.Calls, c => Assert.Equal(freshKey, c));
        Assert.True(await AcknowledgedAsync(fresh));
        Assert.Null(await NextAttemptAsync(fresh));
    }

    [Fact]
    public async Task ASweepUpdateHonoursTheMonotonicGuardAndRecordsASweepEvent()
    {
        var install = await InstallAsync();
        var token = Token();
        var result = await Writer.UpsertAsync(Upsert(token, install, StoredPurchaseState.Active, Now), "verify", CancellationToken.None);

        Assert.False(await Sweep.ApplyAsync(new SweepUpdate(result.PurchaseId, StoredPurchaseState.Expired, null, true, null, Now.AddSeconds(-1)), CancellationToken.None));
        Assert.True(await Sweep.ApplyAsync(new SweepUpdate(result.PurchaseId, StoredPurchaseState.Active, Now.AddDays(30), true, null, Now.AddMinutes(1)), CancellationToken.None));
        Assert.True(await Sweep.ApplyAsync(new SweepUpdate(result.PurchaseId, StoredPurchaseState.Refunded, null, false, null, Now.AddMinutes(2)), CancellationToken.None));

        var row = await RowAsync(token);
        Assert.Equal("refunded", row.State);
        Assert.True(row.Acknowledged);
        Assert.Equal([(null, "active", "verify"), ("active", "refunded", "sweep")], await EventsAsync(result.PurchaseId));
    }

    private static string Token() => "tok." + Guid.NewGuid().ToString("N");

    private static PurchaseUpsert Upsert(string token, InstallId install, StoredPurchaseState state, DateTimeOffset readAt) => new(
        PurchaseStore.GooglePlay,
        "zaghlol_gold_yearly",
        GoldPlan.Yearly,
        new Sensitive<string>(token),
        null,
        install,
        state,
        readAt.AddDays(30),
        false,
        PurchaseEnvironment.Sandbox,
        StoreBindingRef.Compute(install),
        readAt);

    private async Task<InstallId> InstallAsync()
    {
        var id = Guid.NewGuid();
        await ExecuteAsync(
            "INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@id, @hash, 'android', '1.0.0')",
            ("id", id),
            ("hash", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)));
        return InstallId.FromGuid(id);
    }

    private async Task<Guid> SeedAsync(
        InstallId install,
        string state,
        bool acknowledged,
        DateTimeOffset createdAt,
        DateTimeOffset? next = null,
        string product = "zaghlol_gold_yearly",
        string? key = null)
    {
        var id = Guid.NewGuid();
        await ExecuteAsync(
            """
            INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, install_id, state, acknowledged, environment, last_verified_at, created_at, ack_next_attempt_at)
            VALUES (@id, 'google_play', @product, 'yearly', @key, @install, @state, @ack, 'production', @created, @created, @next)
            """,
            ("id", id),
            ("product", product),
            ("key", key ?? Token()),
            ("install", install.Value),
            ("state", state),
            ("ack", acknowledged),
            ("created", createdAt),
            ("next", (object?)next ?? DBNull.Value));
        return id;
    }

    private async Task<DateTimeOffset?> NextAttemptAsync(Guid id)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT ack_next_attempt_at FROM zaghlol.purchases WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", id);
        return await command.ExecuteScalarAsync() is DateTime value ? new DateTimeOffset(value, TimeSpan.Zero) : (DateTimeOffset?)null;
    }

    private async Task<bool> AcknowledgedAsync(Guid id)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT acknowledged FROM zaghlol.purchases WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", id);
        return await command.ExecuteScalarAsync() is true;
    }

    private async Task<(string State, bool Acknowledged, Guid? InstallId, string Environment, string? Ref)> RowAsync(string token)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT state, acknowledged, install_id, environment, obfuscated_install_ref FROM zaghlol.purchases WHERE store_key = @k", connection);
        command.Parameters.AddWithValue("k", token);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetString(0), reader.GetBoolean(1), reader.IsDBNull(2) ? null : reader.GetGuid(2), reader.GetString(3), reader.IsDBNull(4) ? null : reader.GetString(4));
    }

    private async Task<List<(string? From, string To, string Cause)>> EventsAsync(Guid purchaseId)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT from_state, to_state, cause FROM zaghlol.purchase_events WHERE purchase_id = @p ORDER BY occurred_at, id", connection);
        command.Parameters.AddWithValue("p", purchaseId);
        await using var reader = await command.ExecuteReaderAsync();
        var events = new List<(string?, string, string)>();
        while (await reader.ReadAsync())
        {
            events.Add((reader.IsDBNull(0) ? null : reader.GetString(0), reader.GetString(1), reader.GetString(2)));
        }

        return events;
    }

    private async Task ExecuteAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        await command.ExecuteNonQueryAsync();
    }

    private static PlayProductCatalog Catalog { get; } = new("app.zaghlol", new Dictionary<string, PlayProductDefinition>(StringComparer.Ordinal)
    {
        ["zaghlol_gold_yearly"] = new(PlayProductKind.Subscription, GoldPlan.Yearly),
    });

    private sealed class SettableClock(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;

        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class NoTelemetry : IPurchaseTelemetry
    {
        public void Verified(string store, string outcome, string code)
        {
        }

        public void Acknowledged(string channel, string outcome)
        {
        }

        public void TimeToAck(TimeSpan sincePurchase)
        {
        }

        public void SetUnacked(long lessThan48h, long atLeast48h, TimeSpan oldestAge)
        {
        }

        public void UnackedOver48h(Guid purchaseId)
        {
        }

        public void OwnershipChecked(string path, OwnershipOutcome outcome)
        {
        }
    }

    /// <summary>Play as a dictionary: a token it doesn't hold is a 404 (a final client error).</summary>
    private sealed class ScriptedPlay : IPlayDeveloperApi
    {
        public Dictionary<string, PlaySubscription> Subscriptions { get; } = new(StringComparer.Ordinal);

        public System.Collections.Concurrent.ConcurrentQueue<string> Calls { get; } = new();

        public static PlaySubscription Subscription(PlaySubscriptionState state) =>
            new(state, [new PlayLineItem("zaghlol_gold_yearly", Now.AddDays(30), null)], null, false, false, null, Now.AddMinutes(-10));

        public Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
        {
            Calls.Enqueue(token.Reveal());
            return Subscriptions.TryGetValue(token.Reveal(), out var read)
                ? Task.FromResult(read)
                : throw new PlayApiException(PlayApi.SubscriptionGet, PlayCallOutcome.ClientError, 404);
        }

        public Task<PlayProduct> GetProductAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) =>
            throw new PlayApiException(PlayApi.ProductGet, PlayCallOutcome.ClientError, 404);

        public Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
        {
            Calls.Enqueue(token.Reveal());
            return Task.CompletedTask;
        }

        public Task AcknowledgeProductAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) =>
            throw new PlayApiException(PlayApi.ProductAcknowledge, PlayCallOutcome.ClientError, 404);

        public Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken) =>
            throw new PlayApiException(PlayApi.OrderGet, PlayCallOutcome.ClientError, 404);
    }
}
