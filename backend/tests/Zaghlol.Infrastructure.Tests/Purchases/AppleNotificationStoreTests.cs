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

/// <summary>PostgreSQL 17 with the App and Worker logins, the inbox on both and the ASSN worker store.</summary>
public sealed class AppleNotificationStoreFixture : IAsyncLifetime
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
        collection.AddSingleton<AppleNotificationStore>();
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
/// T-134 design note §1 step 6, §2 and §5 against PostgreSQL 17 (migration <c>AppleNotifications</c>): the idempotent insert on both
/// logins, the processor's pick and state, the worker statement under the monotonic guard, the columns it must never touch, and the
/// grant proofs (FU-092 item 1).
/// </summary>
public class AppleNotificationStoreTests(AppleNotificationStoreFixture fixture) : IClassFixture<AppleNotificationStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private AppleNotificationStore Store => fixture.Services.GetRequiredService<AppleNotificationStore>();

    private StoreNotificationInbox AppInbox => fixture.Services.GetRequiredKeyedService<StoreNotificationInbox>("app");

    private StoreNotificationInbox WorkerInbox => fixture.Services.GetRequiredKeyedService<StoreNotificationInbox>("worker");

    [Fact]
    public async Task TheInsertIsIdempotentAcrossBothLoginsAndStoresExactlyTheExtractedColumns()
    {
        var record = Record("REFUND", Original());

        Assert.True(await AppInbox.TryInsertAsync(record, CancellationToken.None));
        Assert.False(await WorkerInbox.TryInsertAsync(record with { Id = Guid.CreateVersion7() }, CancellationToken.None));
        Assert.False(await AppInbox.TryInsertAsync(record with { Id = Guid.CreateVersion7() }, CancellationToken.None));

        var row = Assert.Single(await Db.QueryAsync(
            fixture.Database.Superuser,
            "SELECT id, store, type, subtype, product_id, store_key, environment, event_time, processed_at, attempts, last_error, payload_digest, next_attempt_at "
            + "FROM zaghlol.store_notifications WHERE external_id = '" + record.ExternalId + "'"));
        Assert.Equal(record.Id, row[0]);
        Assert.Equal("app_store", row[1]);
        Assert.Equal("REFUND", row[2]);
        Assert.Equal("SUMMARY", row[3]);
        Assert.Equal("zaghlol_gold_yearly", row[4]);
        Assert.Equal(record.StoreKey!.Value.Reveal(), row[5]);
        Assert.Equal("production", row[6]);
        Assert.Equal(record.EventTime, At(row[7]));
        Assert.Null(row[8]);
        Assert.Equal(0, row[9]);
        Assert.Null(row[10]);
        Assert.Equal(record.PayloadDigest, row[11]);
        Assert.Null(row[12]);
    }

    [Fact]
    public async Task ARecordInsertedProcessedIsNeverPickedAndKeepsItsCode()
    {
        var record = Record("EXPIRED", null) with { Processed = true, LastError = AppleNotificationIngest.NoTransaction };
        await WorkerInbox.TryInsertAsync(record, CancellationToken.None);

        var due = await Store.ListDueAsync(DateTimeOffset.UtcNow.AddDays(1), 1000, CancellationToken.None);

        Assert.DoesNotContain(due, d => d.Id == record.Id);
        Assert.Equal("NO_TRANSACTION", (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT last_error FROM zaghlol.store_notifications WHERE id = '{record.Id}'")).Single()[0]);
    }

    [Theory]
    [InlineData("refund", null)]
    [InlineData("REFUND", "bad subtype")]
    [InlineData("", null)]
    public async Task TheTypeAndSubtypeChecksRefuseAnythingButStoreNames(string type, string? subtype)
    {
        var record = Record("REFUND", Original()) with { Type = type, Subtype = subtype };

        var error = await Assert.ThrowsAsync<PostgresException>(() => AppInbox.TryInsertAsync(record, CancellationToken.None));
        Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
    }

    [Fact]
    public async Task ThePickTakesNeverFailedFirstThenDueThenOldestAndSkipsFutureAndProcessedRows()
    {
        var at = DateTimeOffset.UtcNow.AddYears(5);
        var neverFailed = await InsertAsync(Record("DID_RENEW", Original()));
        var dueEarly = await InsertAsync(Record("DID_RENEW", Original()));
        var dueLate = await InsertAsync(Record("DID_RENEW", Original()));
        var future = await InsertAsync(Record("DID_RENEW", Original()));
        var done = await InsertAsync(Record("DID_RENEW", Original()));
        await Store.FailAsync(dueEarly, 1, at.AddMinutes(-10), AppleNotificationSchedule.StoreError, CancellationToken.None);
        await Store.FailAsync(dueLate, 2, at.AddMinutes(-5), AppleNotificationSchedule.StoreError, CancellationToken.None);
        await Store.DeferAsync(future, at.AddMinutes(5), CancellationToken.None);
        await Store.CompleteAsync(done, null, CancellationToken.None);

        var due = (await Store.ListDueAsync(at, 10000, CancellationToken.None)).Select(d => d.Id).ToList();

        Assert.True(due.IndexOf(neverFailed) < due.IndexOf(dueEarly));
        Assert.True(due.IndexOf(dueEarly) < due.IndexOf(dueLate));
        Assert.DoesNotContain(future, due);
        Assert.DoesNotContain(done, due);
    }

    [Fact]
    public async Task ACountedFailureKeepsTheRowOpenAndTheDeadLetterClosesIt()
    {
        var id = await InsertAsync(Record("DID_RENEW", Original()));
        var next = DateTimeOffset.UtcNow.AddMinutes(3);

        await Store.FailAsync(id, 3, next, AppleNotificationSchedule.StoreAuth, CancellationToken.None);
        var open = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT attempts, last_error, next_attempt_at, processed_at FROM zaghlol.store_notifications WHERE id = '{id}'")).Single();
        await Store.FailAsync(id, 10, null, AppleNotificationSchedule.Unmapped, CancellationToken.None);
        var dead = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT attempts, last_error, next_attempt_at, processed_at FROM zaghlol.store_notifications WHERE id = '{id}'")).Single();

        Assert.Equal(3, open[0]);
        Assert.Equal("STORE_AUTH", open[1]);
        Assert.Null(open[3]);
        Assert.Equal(10, dead[0]);
        Assert.Equal("UNMAPPED", dead[1]);
        Assert.Null(dead[2]);
        Assert.NotNull(dead[3]);
    }

    [Fact]
    public async Task TheWorkerWriteAppliesUnderTheGuardWithAnEventAndMarksTheNotificationInOneTransaction()
    {
        var install = await InstallAsync();
        var original = Original();
        var purchase = await VerifyAsync(original, install, Now);
        var notification = await InsertAsync(Record("REFUND", original));

        var applied = await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Refunded, Now.AddMinutes(1), keepExpiry: true), notification, CancellationToken.None);
        var stale = await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Active, Now.AddSeconds(30)), null, CancellationToken.None);
        var same = await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Refunded, Now.AddMinutes(2), keepExpiry: true), null, CancellationToken.None);

        Assert.Equal(AppleWriteResult.Applied, applied);
        Assert.Equal(AppleWriteResult.Superseded, stale);
        Assert.Equal(AppleWriteResult.Unchanged, same);
        var row = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT state, expires_at, last_verified_at FROM zaghlol.purchases WHERE id = '{purchase}'")).Single();
        Assert.Equal("refunded", row[0]);
        Assert.Equal(Now.AddDays(30), At(row[1]));
        Assert.Equal(Now.AddMinutes(2), At(row[2]));
        var events = await Db.QueryAsync(fixture.Database.Superuser, $"SELECT from_state, to_state, cause FROM zaghlol.purchase_events WHERE purchase_id = '{purchase}' ORDER BY occurred_at");
        Assert.Equal(["verify", "assn:REFUND"], events.Select(e => (string)e[2]!));
        Assert.Equal("refunded", events[1][1]);
        var processed = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT processed_at, last_error FROM zaghlol.store_notifications WHERE id = '{notification}'")).Single();
        Assert.NotNull(processed[0]);
        Assert.Null(processed[1]);
    }

    [Fact]
    public async Task AWriteForAVanishedPurchaseIsGoneAndRecordedNoPurchase()
    {
        var notification = await InsertAsync(Record("REFUND", Original()));

        var result = await Store.ApplyAsync(Write(Guid.NewGuid(), StoredPurchaseState.Refunded, Now), notification, CancellationToken.None);

        Assert.Equal(AppleWriteResult.Gone, result);
        Assert.Equal("NO_PURCHASE", (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT last_error FROM zaghlol.store_notifications WHERE id = '{notification}'")).Single()[0]);
    }

    [Fact]
    public async Task TheWorkerWriteNeverTouchesTheBindingPaymentAccountOrSeatColumns()
    {
        var install = await InstallAsync();
        var original = Original();
        var purchase = await VerifyAsync(original, install, Now, paidAt: Now.AddMinutes(-1));
        await Db.ExecuteAsync(fixture.Database.Superuser, $"INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at) VALUES ('{purchase}', '{install.Value}', 'binding', now())");
        const string Snapshot = """
            SELECT p.install_id, p.obfuscated_install_ref, p.environment, p.last_payment_at, p.acknowledged, p.account_id, p.account_linked_by,
                   p.attach_reclaim_used_at, p.dispute_frozen_until, p.support_link_notice_pending, p.linked_purchase_token, p.store_key,
                   s.install_id, s.proof, s.bound_at, s.next_move_at
            FROM zaghlol.purchases p JOIN zaghlol.purchase_seats s ON s.purchase_id = p.id WHERE p.id = '{0}'
            """;
        var before = (await Db.QueryAsync(fixture.Database.Superuser, string.Format(System.Globalization.CultureInfo.InvariantCulture, Snapshot, purchase))).Single();

        await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Revoked, Now.AddMinutes(1), product: "zaghlol_gold_monthly", plan: GoldPlan.Monthly), null, CancellationToken.None);

        var after = (await Db.QueryAsync(fixture.Database.Superuser, string.Format(System.Globalization.CultureInfo.InvariantCulture, Snapshot, purchase))).Single();
        Assert.Equal(before, after);
        var replanned = (await Db.QueryAsync(fixture.Database.Superuser, $"SELECT state, product_id, plan FROM zaghlol.purchases WHERE id = '{purchase}'")).Single();
        Assert.Equal(["revoked", "zaghlol_gold_monthly", "monthly"], replanned.Select(v => (string)v!));
    }

    // FU-092 item 1: the grants, proved on the Worker login.

    [Fact]
    public async Task TheWorkerLoginMayRunTheWorkerStatementButNotVerifysAppleUpdate()
    {
        var install = await InstallAsync();
        var purchase = await VerifyAsync(Original(), install, Now);
        var verifyStatement = (string)typeof(PurchaseWriter).GetField("UpdateAppleSql", BindingFlags.NonPublic | BindingFlags.Static)!.GetRawConstantValue()!;

        await using var worker = new NpgsqlConnection(fixture.Database.Worker);
        await worker.OpenAsync();
        await using var verify = new NpgsqlCommand(verifyStatement, worker);
        verify.Parameters.AddWithValue("id", purchase);
        verify.Parameters.AddWithValue("linked", DBNull.Value);
        verify.Parameters.AddWithValue("ref", DBNull.Value);
        verify.Parameters.AddWithValue("state", "active");
        verify.Parameters.AddWithValue("keep_expires", false);
        verify.Parameters.AddWithValue("expires", Now.AddDays(30));
        verify.Parameters.AddWithValue("environment", "production");
        verify.Parameters.AddWithValue("ack", true);
        verify.Parameters.AddWithValue("read_at", Now.AddHours(1));
        verify.Parameters.AddWithValue("product", "zaghlol_gold_yearly");
        verify.Parameters.AddWithValue("plan", "yearly");

        var denied = await Assert.ThrowsAsync<PostgresException>(() => verify.ExecuteNonQueryAsync());
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, denied.SqlState);
        Assert.Equal(AppleWriteResult.Applied, await Store.ApplyAsync(Write(purchase, StoredPurchaseState.Expired, Now.AddHours(2)), null, CancellationToken.None));
    }

    [Theory]
    [InlineData("UPDATE zaghlol.purchases SET last_payment_at = now() WHERE false")]
    [InlineData("UPDATE zaghlol.purchases SET obfuscated_install_ref = NULL WHERE false")]
    [InlineData("UPDATE zaghlol.purchases SET environment = 'sandbox' WHERE false")]
    [InlineData("UPDATE zaghlol.purchases SET install_id = NULL WHERE false")]
    [InlineData("UPDATE zaghlol.purchase_seats SET install_id = NULL WHERE false")]
    [InlineData("UPDATE zaghlol.purchase_seats SET next_move_at = NULL WHERE false")]
    [InlineData("INSERT INTO zaghlol.purchases (id) SELECT gen_random_uuid() WHERE false")]
    [InlineData("INSERT INTO zaghlol.purchase_seats (purchase_id) SELECT gen_random_uuid() WHERE false")]
    public async Task TheWorkerLoginCannotTouchVerifyOnlyColumnsSeatsOrInsertPurchases(string sql)
    {
        var error = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(fixture.Database.Worker, sql));

        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
    }

    [Fact]
    public async Task TheSweepListsExactlyTheEntitlingSubscriptionsWhoseExpiryPassedWithoutANewerRead()
    {
        var now = DateTimeOffset.UtcNow;
        var qualifying = await PurchaseAsync("active", "yearly", now.AddHours(-2), lastVerified: now.AddDays(-20));
        var grace = await PurchaseAsync("in_grace", "monthly", now.AddDays(-6), lastVerified: now.AddDays(-7));
        var fresh = await PurchaseAsync("active", "yearly", now.AddMinutes(-5), lastVerified: now.AddDays(-20));
        var old = await PurchaseAsync("active", "yearly", now.AddDays(-8), lastVerified: now.AddDays(-40));
        var reread = await PurchaseAsync("active", "yearly", now.AddHours(-2), lastVerified: now.AddHours(-1));
        var lifetime = await PurchaseAsync("active", "lifetime", now.AddHours(-2), lastVerified: now.AddDays(-20));
        var expired = await PurchaseAsync("expired", "yearly", now.AddHours(-2), lastVerified: now.AddDays(-20));

        var rows = (await Store.ListExpiredSubscriptionsAsync(now, 1000, CancellationToken.None)).Select(r => r.Id).ToList();

        Assert.Contains(qualifying, rows);
        Assert.Contains(grace, rows);
        Assert.DoesNotContain(fresh, rows);
        Assert.DoesNotContain(old, rows);
        Assert.DoesNotContain(reread, rows);
        Assert.DoesNotContain(lifetime, rows);
        Assert.DoesNotContain(expired, rows);
        Assert.True(rows.IndexOf(grace) < rows.IndexOf(qualifying));
        Assert.Single(await Store.ListExpiredSubscriptionsAsync(now, 1, CancellationToken.None));
    }

    [Fact]
    public async Task OnlyOneHolderOfEachAdvisoryLock()
    {
        await using var first = await Store.TryLockAsync(AppleNotificationProcessor.LockName, CancellationToken.None);
        var second = await Store.TryLockAsync(AppleNotificationProcessor.LockName, CancellationToken.None);
        await using var other = await Store.TryLockAsync(AppleNotificationHistoryJob.LockName, CancellationToken.None);

        Assert.NotNull(first);
        Assert.Null(second);
        Assert.NotNull(other);
        Assert.NotEqual(AppleNotificationStore.LockKey(AppleNotificationProcessor.LockName), AppleNotificationStore.LockKey(AppleExpirySweepJob.LockName));
    }

    /// <summary>Npgsql reads timestamptz as a UTC <see cref="DateTime"/>.</summary>
    private static DateTimeOffset At(object? value) => new(DateTime.SpecifyKind((DateTime)value!, DateTimeKind.Utc));

    private static string Original() => "2" + Random.Shared.NextInt64(100000000000000, 999999999999999).ToString(System.Globalization.CultureInfo.InvariantCulture);

    private static StoreNotificationRecord Record(string type, string? storeKey) => new(
        Guid.CreateVersion7(),
        PurchaseStore.AppStore,
        Guid.NewGuid().ToString("D"),
        type,
        "SUMMARY",
        "zaghlol_gold_yearly",
        storeKey is null ? null : new Sensitive<string>(storeKey),
        PurchaseEnvironment.Production,
        Now,
        System.Security.Cryptography.RandomNumberGenerator.GetBytes(32),
        false,
        null);

    private static AppleStateWrite Write(
        Guid purchase,
        StoredPurchaseState state,
        DateTimeOffset readAt,
        bool keepExpiry = false,
        string product = "zaghlol_gold_yearly",
        GoldPlan plan = GoldPlan.Yearly) =>
        new(purchase, state, Now.AddDays(60), keepExpiry, product, plan, readAt, "assn:REFUND");

    private async Task<Guid> InsertAsync(StoreNotificationRecord record)
    {
        Assert.True(await AppInbox.TryInsertAsync(record, CancellationToken.None));
        return record.Id;
    }

    private async Task<Guid> VerifyAsync(string original, InstallId install, DateTimeOffset readAt, DateTimeOffset? paidAt = null) =>
        (await fixture.Services.GetRequiredService<PurchaseWriter>().UpsertAsync(
            new PurchaseUpsert(
                PurchaseStore.AppStore,
                "zaghlol_gold_yearly",
                GoldPlan.Yearly,
                new Sensitive<string>(original),
                null,
                install,
                StoredPurchaseState.Active,
                Now.AddDays(30),
                true,
                PurchaseEnvironment.Production,
                StoreBindingRef.Compute(install),
                readAt,
                NewPaymentAt: paidAt),
            "verify",
            CancellationToken.None)).PurchaseId;

    private async Task<Guid> PurchaseAsync(string state, string plan, DateTimeOffset expires, DateTimeOffset lastVerified)
    {
        var id = Guid.CreateVersion7();
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, state, expires_at, acknowledged, environment, last_verified_at) "
            + "VALUES (@id, 'app_store', @product, @plan, @key, @state, @expires, true, 'production', @verified)",
            connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("product", "zaghlol_gold_" + plan);
        command.Parameters.AddWithValue("plan", plan);
        command.Parameters.AddWithValue("key", Original());
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
        await using var command = new NpgsqlCommand("INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@id, @hash, 'ios', '1.0.0')", connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("hash", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        await command.ExecuteNonQueryAsync();
        return InstallId.FromGuid(id);
    }
}
