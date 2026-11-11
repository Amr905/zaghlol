using System.Reflection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Purchases;

/// <summary>PostgreSQL 17 with the App and Worker logins: the inbox on both, the verify writer and the RTDN worker store.</summary>
public sealed class PlayNotificationStoreFixture : IAsyncLifetime
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
        collection.AddSingleton<PlayNotificationStore>();
        collection.AddKeyedSingleton("app", (provider, _) => new StoreNotificationInbox(provider.GetRequiredService<IAppDbContextFactory>().CreateDbContext));
        collection.AddKeyedSingleton("worker", (provider, _) =>
        {
            var factory = provider.GetRequiredService<IZaghlolDbContextFactory>();
            return new StoreNotificationInbox(() => factory.CreateDbContext(DatabaseRole.Worker));
        });
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

/// <summary>
/// T-133 design note §2-§4 against PostgreSQL 17 (migration <c>GoogleNotifications</c>): Google rows (no environment), the processor's
/// pick, the Google worker statement under the guard with the label rule, the columns it never touches, the sweep candidates and their
/// SQL key matching the C# key, and the worker-login denials.
/// </summary>
public class PlayNotificationStoreTests(PlayNotificationStoreFixture fixture) : IClassFixture<PlayNotificationStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private PlayNotificationStore Store => fixture.Services.GetRequiredService<PlayNotificationStore>();

    private StoreNotificationInbox AppInbox => fixture.Services.GetRequiredKeyedService<StoreNotificationInbox>("app");

    private StoreNotificationInbox WorkerInbox => fixture.Services.GetRequiredKeyedService<StoreNotificationInbox>("worker");

    [Fact]
    public async Task AGoogleRecordIsStoredWithoutEnvironmentOnBothLoginsOnce()
    {
        var record = Record("SUBSCRIPTION_RENEWED", Token());

        Assert.True(await AppInbox.TryInsertAsync(record, CancellationToken.None));
        Assert.False(await WorkerInbox.TryInsertAsync(record with { Id = Guid.CreateVersion7() }, CancellationToken.None));

        var row = Assert.Single(await Db.QueryAsync(
            fixture.Database.Superuser,
            $"SELECT store, type, subtype, environment, store_key, processed_at FROM zaghlol.store_notifications WHERE id = '{record.Id}'"));
        Assert.Equal("google_play", row[0]);
        Assert.Equal("SUBSCRIPTION_RENEWED", row[1]);
        Assert.Null(row[2]);
        Assert.Null(row[3]);
        Assert.Equal(record.StoreKey!.Value.Reveal(), row[4]);
        Assert.Null(row[5]);
    }

    [Fact]
    public async Task ThePickReadsOnlyDueGoogleRowsWithTheirShapeColumns()
    {
        var due = Record("SUBSCRIPTION_EXPIRED", Token());
        var processed = Record("TEST", null) with { Processed = true };
        await AppInbox.TryInsertAsync(due, CancellationToken.None);
        await AppInbox.TryInsertAsync(processed, CancellationToken.None);

        var rows = await Store.ListDueAsync(DateTimeOffset.UtcNow.AddDays(1), 1000, CancellationToken.None);

        var row = Assert.Single(rows, r => r.Id == due.Id);
        Assert.Equal(due.ExternalId, row.ExternalId);
        Assert.Null(row.Environment);
        Assert.Null(row.Subtype);
        Assert.DoesNotContain(rows, r => r.Id == processed.Id);
        Assert.True(PlayNotificationProcessor.IsIngestShaped(row));
    }

    [Fact]
    public async Task TheWorkerWriteSettlesTheLabelUnderTheGuardWithAnEventAndTheProcessedMark()
    {
        var install = await InstallAsync();
        var token = Token();
        var purchase = await VerifyAsync(token, install, Now, StoredPurchaseState.Active);
        var voided = await InsertAsync(Record("VOIDED_PURCHASE", token));
        var expired = await InsertAsync(Record("SUBSCRIPTION_EXPIRED", token));
        var stale = await InsertAsync(Record("SUBSCRIPTION_RENEWED", token));

        Assert.Equal(PlayWriteResult.Applied, await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Expired, Now.AddMinutes(1), "VOIDED_PURCHASE"), voided, CancellationToken.None));
        Assert.Equal(PlayWriteResult.Unchanged, await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Expired, Now.AddMinutes(2), "SUBSCRIPTION_EXPIRED"), expired, CancellationToken.None));
        Assert.Equal(PlayWriteResult.Superseded, await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Active, Now.AddSeconds(30), "SUBSCRIPTION_RENEWED"), stale, CancellationToken.None));

        var row = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT state, expires_at, last_verified_at FROM zaghlol.purchases WHERE id = '{purchase}'")).Single();
        Assert.Equal("refunded", row[0]);
        Assert.Equal(Now.AddDays(-1), At(row[1]));
        Assert.Equal(Now.AddMinutes(2), At(row[2]));
        var events = await Db.QueryAsync(fixture.Database.Superuser, $"SELECT to_state, cause FROM zaghlol.purchase_events WHERE purchase_id = '{purchase}' ORDER BY occurred_at");
        Assert.Equal(["verify", "rtdn:VOIDED_PURCHASE"], events.Select(e => (string)e[1]!));
        var marks = await Db.QueryAsync(fixture.Database.Superuser, $"SELECT count(*) FROM zaghlol.store_notifications WHERE id IN ('{voided}', '{expired}', '{stale}') AND processed_at IS NOT NULL AND last_error IS NULL");
        Assert.Equal(3L, marks[0][0]);
    }

    /// <summary>§3 step 6: verify (the App writer) reading EXPIRED after a refund keeps 'refunded'; an ACTIVE read wins.</summary>
    [Fact]
    public async Task VerifyReadingExpiredAfterARefundKeepsTheLabelAndAnActiveReadWins()
    {
        var install = await InstallAsync();
        var token = Token();
        var purchase = await VerifyAsync(token, install, Now, StoredPurchaseState.Active);
        await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Expired, Now.AddMinutes(1), "SUBSCRIPTION_REVOKED"), await InsertAsync(Record("SUBSCRIPTION_REVOKED", token)), CancellationToken.None);

        var afterExpired = await VerifyAsync(token, install, Now.AddMinutes(2), StoredPurchaseState.Expired);
        Assert.Equal("revoked", await StateAsync(afterExpired));

        await VerifyAsync(token, install, Now.AddMinutes(3), StoredPurchaseState.Active);
        Assert.Equal("active", await StateAsync(afterExpired));
    }

    [Theory]
    [InlineData("pending", "expired")]
    [InlineData("active", "active")]
    public async Task APendingCancelWritesOnlyFromPending(string before, string after)
    {
        var id = await PurchaseAsync(before, "yearly", Now.AddDays(3), Now.AddDays(-1), out var token);
        var notification = await InsertAsync(Record("SUBSCRIPTION_PENDING_PURCHASE_CANCELED", token));

        await Store.ApplyAsync(
            new PlayStateWrite(id, StoredPurchaseState.Expired, null, true, "SUBSCRIPTION_PENDING_PURCHASE_CANCELED", true, Now, "rtdn:SUBSCRIPTION_PENDING_PURCHASE_CANCELED"),
            notification,
            CancellationToken.None);

        var row = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT state, expires_at FROM zaghlol.purchases WHERE id = '{id}'")).Single();
        Assert.Equal(after, row[0]);
        Assert.Equal(Now.AddDays(3), At(row[1]));
    }

    [Fact]
    public async Task AWriteForAVanishedPurchaseIsGoneAndRecordedNoPurchase()
    {
        var notification = await InsertAsync(Record("SUBSCRIPTION_EXPIRED", Token()));

        Assert.Equal(PlayWriteResult.Gone, await Store.ApplyAsync(Write(Guid.NewGuid(), StoredPurchaseState.Expired, Now, null), notification, CancellationToken.None));
        Assert.Equal("NO_PURCHASE", (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT last_error FROM zaghlol.store_notifications WHERE id = '{notification}'")).Single()[0]);
    }

    /// <summary>§9 snapshot: the Google worker statement leaves every verify-only, account and seat column as it was.</summary>
    [Fact]
    public async Task TheWorkerWriteNeverTouchesProductPlanBindingPaymentAccountOrSeatColumns()
    {
        var install = await InstallAsync();
        var token = Token();
        var purchase = await VerifyAsync(token, install, Now, StoredPurchaseState.Active);
        await Db.ExecuteAsync(fixture.Database.Superuser, $"INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at) VALUES ('{purchase}', '{install.Value}', 'binding', now())");
        const string Snapshot = """
            SELECT p.install_id, p.obfuscated_install_ref, p.environment, p.product_id, p.plan, p.last_payment_at, p.acknowledged, p.account_id,
                   p.account_linked_by, p.attach_reclaim_used_at, p.dispute_frozen_until, p.support_link_notice_pending, p.linked_purchase_token,
                   p.store_key, s.install_id, s.proof, s.bound_at, s.next_move_at
            FROM zaghlol.purchases p JOIN zaghlol.purchase_seats s ON s.purchase_id = p.id WHERE p.id = '{0}'
            """;
        var before = (await Db.QueryAsync(fixture.Database.Superuser, string.Format(System.Globalization.CultureInfo.InvariantCulture, Snapshot, purchase))).Single();

        await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Expired, Now.AddMinutes(1), "SUBSCRIPTION_REVOKED"), await InsertAsync(Record("SUBSCRIPTION_REVOKED", token)), CancellationToken.None);

        var after = (await Db.QueryAsync(fixture.Database.Superuser, string.Format(System.Globalization.CultureInfo.InvariantCulture, Snapshot, purchase))).Single();
        Assert.Equal(before, after);
        Assert.Equal("revoked", await StateAsync(purchase));
    }

    [Fact]
    public async Task TheWorkerLoginMayRunTheGoogleWorkerStatement()
    {
        var statement = (string)typeof(PlayNotificationStore).GetField("UpdateSql", BindingFlags.NonPublic | BindingFlags.Static)!.GetRawConstantValue()!;
        var id = await PurchaseAsync("active", "yearly", Now.AddDays(1), Now.AddDays(-1), out _);

        await using var worker = new NpgsqlConnection(fixture.Database.Worker);
        await worker.OpenAsync();
        await using var command = new NpgsqlCommand(statement, worker);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("state", "expired");
        command.Parameters.AddWithValue("keep_expires", true);
        command.Parameters.AddWithValue("expires", DBNull.Value);
        command.Parameters.AddWithValue("read_at", Now);

        Assert.Equal(1, await command.ExecuteNonQueryAsync());
    }

    [Theory]
    [InlineData("UPDATE zaghlol.purchases SET install_id = NULL WHERE false")]
    [InlineData("UPDATE zaghlol.purchases SET obfuscated_install_ref = NULL WHERE false")]
    [InlineData("UPDATE zaghlol.purchases SET environment = 'sandbox' WHERE false")]
    [InlineData("UPDATE zaghlol.purchases SET last_payment_at = now() WHERE false")]
    [InlineData("UPDATE zaghlol.purchase_seats SET proof = 'basic' WHERE false")]
    [InlineData("INSERT INTO zaghlol.purchases (id) SELECT gen_random_uuid() WHERE false")]
    public async Task TheWorkerLoginCannotTouchVerifyOnlyColumnsSeatsOrInsertPurchases(string sql)
    {
        var error = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(fixture.Database.Worker, sql));

        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
    }

    /// <summary>§4 (FU-098 code 3): the SQL sweep key equals <see cref="PlayJobKeys.Sweep"/>, so an enqueued, done or dead-lettered row skips its purchase.</summary>
    [Fact]
    public async Task TheSweepListsCandidatesUntilTheirKeyedRowExistsAndAgainAfterARenewal()
    {
        var now = DateTimeOffset.UtcNow;
        var expiry = new DateTimeOffset(now.AddHours(-2).UtcTicks - (now.UtcTicks % TimeSpan.TicksPerSecond) + 123_4567, TimeSpan.Zero);
        var id = await PurchaseAsync("active", "yearly", expiry, now.AddDays(-20), out var token);
        var lifetime = await PurchaseAsync("active", "lifetime", expiry, now.AddDays(-20), out _);
        var appStore = await PurchaseAsync("active", "yearly", expiry, now.AddDays(-20), out _, "app_store");

        var first = await Store.ListExpiredSubscriptionsAsync(now, 1000, CancellationToken.None);
        var candidate = Assert.Single(first, r => r.PurchaseId == id);
        Assert.Equal(token, candidate.StoreKey.Reveal());
        Assert.DoesNotContain(first, r => r.PurchaseId == lifetime || r.PurchaseId == appStore);

        var key = PlayJobKeys.Sweep(id, candidate.ExpiresAt);
        var sweep = Record(PlayRtdnTypes.ExpirySweep, token) with { ExternalId = key };
        Assert.True(await WorkerInbox.TryInsertAsync(sweep, CancellationToken.None));
        Assert.DoesNotContain(await Store.ListExpiredSubscriptionsAsync(now, 1000, CancellationToken.None), r => r.PurchaseId == id);

        await Store.FailAsync(sweep.Id, 10, null, "STORE_ERROR", CancellationToken.None);
        Assert.DoesNotContain(await Store.ListExpiredSubscriptionsAsync(now, 1000, CancellationToken.None), r => r.PurchaseId == id);

        await Db.ExecuteAsync(fixture.Database.Superuser, $"UPDATE zaghlol.purchases SET expires_at = expires_at + interval '1 hour' WHERE id = '{id}'");
        Assert.Contains(await Store.ListExpiredSubscriptionsAsync(now, 1000, CancellationToken.None), r => r.PurchaseId == id);
    }

    [Fact]
    public async Task OnlyAnRtdnVoidedRowCountsAsDelivered()
    {
        var token = Token();
        await InsertAsync(Record("VOIDED_PURCHASE", token) with { ExternalId = "voided:" + new string('a', 64) });
        Assert.False(await Store.HasRtdnVoidedAsync(new Sensitive<string>(token), CancellationToken.None));

        await InsertAsync(Record("VOIDED_PURCHASE", token));
        Assert.True(await Store.HasRtdnVoidedAsync(new Sensitive<string>(token), CancellationToken.None));
    }

    [Fact]
    public async Task TheBacklogCountsOnlyOpenGoogleRows()
    {
        var before = await Store.BacklogAsync(DateTimeOffset.UtcNow, CancellationToken.None);
        await InsertAsync(Record("SUBSCRIPTION_RENEWED", Token()));

        var after = await Store.BacklogAsync(DateTimeOffset.UtcNow, CancellationToken.None);

        Assert.Equal(before.LessThan1h + 1, after.LessThan1h);
    }

    [Fact]
    public async Task OnlyOneHolderOfEachGoogleLock()
    {
        await using var first = await Store.TryLockAsync(PlayNotificationProcessor.LockName, CancellationToken.None);
        var second = await Store.TryLockAsync(PlayNotificationProcessor.LockName, CancellationToken.None);
        await using var voided = await Store.TryLockAsync(PlayVoidedReconcileJob.LockName, CancellationToken.None);
        await using var sweep = await Store.TryLockAsync(PlayExpirySweepJob.LockName, CancellationToken.None);

        Assert.NotNull(first);
        Assert.Null(second);
        Assert.NotNull(voided);
        Assert.NotNull(sweep);
    }

    private static DateTimeOffset At(object? value) => new(DateTime.SpecifyKind((DateTime)value!, DateTimeKind.Utc));

    private static string Token() => "tok." + Guid.NewGuid().ToString("N");

    private static StoreNotificationRecord Record(string type, string? storeKey) => new(
        Guid.CreateVersion7(),
        PurchaseStore.GooglePlay,
        Guid.NewGuid().ToString("N"),
        type,
        null,
        null,
        storeKey is null ? null : new Sensitive<string>(storeKey),
        null,
        Now,
        System.Security.Cryptography.RandomNumberGenerator.GetBytes(32),
        false,
        null);

    private static PlayStateWrite Write(Guid purchase, StoredPurchaseState read, DateTimeOffset readAt, string? type) =>
        new(purchase, read, Now.AddDays(-1), false, type, false, readAt, "rtdn:" + (type ?? "SUBSCRIPTION_OTHER"));

    private async Task<Guid> InsertAsync(StoreNotificationRecord record)
    {
        Assert.True(await AppInbox.TryInsertAsync(record, CancellationToken.None));
        return record.Id;
    }

    private async Task<string> StateAsync(Guid purchase) =>
        (string)(await Db.QueryAsync(fixture.Database.Superuser, $"SELECT state FROM zaghlol.purchases WHERE id = '{purchase}'")).Single()[0]!;

    private async Task<Guid> VerifyAsync(string token, InstallId install, DateTimeOffset readAt, StoredPurchaseState state) =>
        (await fixture.Services.GetRequiredService<PurchaseWriter>().UpsertAsync(
            new PurchaseUpsert(
                PurchaseStore.GooglePlay,
                "zaghlol_gold_yearly",
                GoldPlan.Yearly,
                new Sensitive<string>(token),
                null,
                install,
                state,
                Now.AddDays(30),
                true,
                PurchaseEnvironment.Production,
                StoreBindingRef.Compute(install),
                readAt),
            "verify",
            CancellationToken.None)).PurchaseId;

    private Task<Guid> PurchaseAsync(string state, string plan, DateTimeOffset expires, DateTimeOffset lastVerified, out string token, string store = "google_play")
    {
        token = Token();
        return InsertPurchaseAsync(state, plan, expires, lastVerified, token, store);
    }

    private async Task<Guid> InsertPurchaseAsync(string state, string plan, DateTimeOffset expires, DateTimeOffset lastVerified, string token, string store)
    {
        var id = Guid.CreateVersion7();
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, state, expires_at, acknowledged, environment, last_verified_at) "
            + "VALUES (@id, @store, @product, @plan, @key, @state, @expires, true, 'production', @verified)",
            connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("store", store);
        command.Parameters.AddWithValue("product", "zaghlol_gold_" + plan);
        command.Parameters.AddWithValue("plan", plan);
        command.Parameters.AddWithValue("key", token);
        command.Parameters.AddWithValue("state", state);
        command.Parameters.AddWithValue("expires", plan == "lifetime" ? DBNull.Value : expires);
        command.Parameters.AddWithValue("verified", lastVerified);
        await command.ExecuteNonQueryAsync();
        return id;
    }

    private async Task<InstallId> InstallAsync()
    {
        var id = Guid.NewGuid();
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@id, @hash, 'android', '1.0.0')", connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("hash", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        await command.ExecuteNonQueryAsync();
        return InstallId.FromGuid(id);
    }
}
