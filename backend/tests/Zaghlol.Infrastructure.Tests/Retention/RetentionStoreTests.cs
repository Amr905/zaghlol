using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Retention;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Retention;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Retention;

/// <summary>A migrated database of its own and the purger on the Worker login, built the way the worker host builds it.</summary>
public sealed class RetentionFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IRetentionStore Store => services!.GetRequiredService<IRetentionStore>();

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:Worker"] = Database.Worker })
            .Build();
        var collection = new ServiceCollection();
        collection.AddLogging();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.Worker);
        collection.AddZaghlolRetention();
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

/// <summary>A clock that never moves.</summary>
internal sealed class FrozenClock(DateTimeOffset now) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => now;
}

internal sealed class CountingMetrics : IRetentionMetrics
{
    public Dictionary<string, long> PurgedByRule { get; } = [];

    public void Purged(string rule, long count) => PurgedByRule[rule] = PurgedByRule.GetValueOrDefault(rule) + count;

    public void Failed(string rule) => throw new InvalidOperationException("No rule may fail in these tests.");
}

/// <summary>T-139: every retention rule against PostgreSQL, run through the job on the worker login with a frozen clock.</summary>
public class RetentionStoreTests(RetentionFixture fixture) : IClassFixture<RetentionFixture>
{
    // The audit_log delete policy compares with the database clock, so the frozen clock starts at the real now and the
    // rows are placed a day either side of each boundary.
    private static readonly DateTimeOffset Now = Rows.Now();

    private static readonly TimeSpan Day = TimeSpan.FromDays(1);

    private async Task<RetentionRunResult> RunAsync(int batchSize = RetentionPurgeJob.DefaultBatchSize)
    {
        var job = new RetentionPurgeJob(fixture.Store, new CountingMetrics(), new FrozenClock(Now));
        var result = await job.RunOnceAsync(batchSize, CancellationToken.None);
        Assert.Empty(result.Failed);
        return result;
    }

    // Seeding goes through the owner so that old timestamps and audit rows can be written; the purge itself runs as worker_rw.
    private async Task<Dictionary<string, object?>> SeedAsync(string table, Dictionary<string, object?>? overrides = null)
    {
        var row = Rows.Base(table);
        foreach (var (column, value) in overrides ?? [])
        {
            row[column] = value;
        }

        row = await Rows.ResolveAsync(fixture.Database, row);
        await Db.InsertAsync(fixture.Database.Migrator, table, row);
        return row;
    }

    private async Task<bool> ExistsAsync(string table, string column, object? value) =>
        (long)(await Db.ScalarAsync(fixture.Database.Superuser, $"SELECT count(*) FROM zaghlol.{table} WHERE {column} = $1", value))! > 0;

    private static Dictionary<string, object?> Install(DateTimeOffset lastSeen, DateTimeOffset? deletedAt = null)
    {
        var row = Rows.Install(Guid.CreateVersion7());
        row["last_seen_at"] = lastSeen;
        row["first_seen_at"] = lastSeen;
        row["deleted_at"] = deletedAt;
        return row;
    }

    [Fact]
    public async Task AnInstallInactiveForOverTwelveMonthsIsDeletedAndItsSeatBecomesVacantKeepingTheDeviceKey()
    {
        var old = await SeedAsync("installs", Install(Now.AddMonths(-12) - Day));
        var recent = await SeedAsync("installs", Install(Now.AddMonths(-12) + Day));
        var oldId = (Guid)old["id"]!;
        var deviceKey = Rows.Bytes();
        var purchase = await SeedAsync("purchases", new() { ["install_id"] = oldId });
        var purchaseId = (Guid)purchase["id"]!;
        await SeedAsync("purchase_seats", new() { ["purchase_id"] = purchaseId, ["install_id"] = oldId, ["device_key_hash"] = deviceKey });
        await SeedAsync("idempotency_records", new() { ["install_id"] = oldId });

        var result = await RunAsync();

        Assert.False(await ExistsAsync("installs", "id", oldId));
        Assert.True(await ExistsAsync("installs", "id", recent["id"]));
        Assert.Equal(1, result.Purged[RetentionRules.InactiveInstalls]);
        var seat = (await Db.QueryAsync(
            fixture.Database.Superuser,
            "SELECT install_id, proof, device_key_hash FROM zaghlol.purchase_seats WHERE purchase_id = $1",
            purchaseId)).Single();
        Assert.Null(seat[0]);
        Assert.Null(seat[1]);
        Assert.Equal(deviceKey, (byte[])seat[2]!);
        Assert.Null(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT install_id FROM zaghlol.purchases WHERE id = $1", purchaseId));
        Assert.False(await ExistsAsync("idempotency_records", "install_id", oldId));
    }

    [Fact]
    public async Task ATombstonedInstallIsDeletedAfterThirtyDaysAndNotBefore()
    {
        var fresh = DateTimeOffset.UtcNow;
        var due = await SeedAsync("installs", Install(fresh, Now.AddDays(-30) - Day));
        var notDue = await SeedAsync("installs", Install(fresh, Now.AddDays(-30) + Day));

        await RunAsync();

        Assert.False(await ExistsAsync("installs", "id", due["id"]));
        Assert.True(await ExistsAsync("installs", "id", notDue["id"]));
    }

    [Theory]
    [InlineData("support_unfreeze")]
    [InlineData("support_detach")]
    [InlineData("support_seat_move")]
    [InlineData("support_lookup")]
    public async Task ASupportAuditRowIsDeletedOneYearAndADayOldAndKeptOneYearLessADay(string action)
    {
        var due = await SeedAuditAsync(action, Now.AddYears(-1) - Day);
        var notDue = await SeedAuditAsync(action, Now.AddYears(-1) + Day);

        var result = await RunAsync();

        Assert.False(await ExistsAsync("audit_log", "id", due));
        Assert.True(await ExistsAsync("audit_log", "id", notDue));
        Assert.True(result.Purged[RetentionRules.AuditSupport] >= 1);
    }

    [Fact]
    public async Task OtherAuditRowsKeepThreeYears()
    {
        var due = await SeedAuditAsync("catalog_publish", Now.AddYears(-3) - Day);
        var twoYears = await SeedAuditAsync("catalog_publish", Now.AddYears(-2));
        var supportNotDue = await SeedAuditAsync("support_lookup", Now.AddMonths(-6));

        await RunAsync();

        Assert.False(await ExistsAsync("audit_log", "id", due));
        Assert.True(await ExistsAsync("audit_log", "id", twoYears));
        Assert.True(await ExistsAsync("audit_log", "id", supportNotDue));
    }

    [Fact]
    public async Task AClockAheadOfTheDatabaseCannotEraseAnAuditRowBeforeItsAge()
    {
        var recent = await SeedAuditAsync("support_lookup", Now.AddMonths(-6));
        var aheadClock = new FrozenClock(Now.AddYears(5));
        var job = new RetentionPurgeJob(fixture.Store, new CountingMetrics(), aheadClock);

        await job.RunOnceAsync(RetentionPurgeJob.DefaultBatchSize, CancellationToken.None);

        Assert.True(await ExistsAsync("audit_log", "id", recent)); // row-level security still holds
    }

    private async Task<long> SeedAuditAsync(string action, DateTimeOffset at)
    {
        var row = await Rows.ResolveAsync(fixture.Database, Rows.Base("audit_log"));
        row["action"] = action;
        row["at"] = at;
        row.Remove("id");
        await Db.InsertAsync(fixture.Database.Migrator, "audit_log", row);
        return (long)(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT max(id) FROM zaghlol.audit_log"))!;
    }

    [Fact]
    public async Task ClaimantsOlderThanSevenDaysExpiredIdempotencyRowsAndExpiredReplayGuardRowsAreRemoved()
    {
        var purchase = await SeedAsync("purchases");
        var oldInstall = await SeedAsync("installs");
        var newInstall = await SeedAsync("installs");
        await SeedAsync("seat_claimants", new() { ["purchase_id"] = purchase["id"], ["install_id"] = oldInstall["id"], ["claimed_at"] = Now.AddDays(-7) - Day });
        await SeedAsync("seat_claimants", new() { ["purchase_id"] = purchase["id"], ["install_id"] = newInstall["id"], ["claimed_at"] = Now.AddDays(-7) + Day });
        var expiredIdem = await SeedAsync("idempotency_records", new() { ["expires_at"] = Now.AddMinutes(-1) });
        var liveIdem = await SeedAsync("idempotency_records", new() { ["expires_at"] = Now.AddHours(1) });
        var expiredGuard = await SeedAsync("replay_guard", new() { ["expires_at"] = Now.AddMinutes(-1) });
        var liveGuard = await SeedAsync("replay_guard", new() { ["expires_at"] = Now.AddMinutes(10) });

        await RunAsync();

        Assert.False(await ExistsAsync("seat_claimants", "install_id", oldInstall["id"]));
        Assert.True(await ExistsAsync("seat_claimants", "install_id", newInstall["id"]));
        Assert.False(await ExistsAsync("idempotency_records", "idempotency_key", expiredIdem["idempotency_key"]));
        Assert.True(await ExistsAsync("idempotency_records", "idempotency_key", liveIdem["idempotency_key"]));
        Assert.False(await ExistsAsync("replay_guard", "key_hash", expiredGuard["key_hash"]));
        Assert.True(await ExistsAsync("replay_guard", "key_hash", liveGuard["key_hash"]));
    }

    [Fact]
    public async Task RegistrationColumnsAreClearedAfterTwentyFourHoursAndTheInstallIsKept()
    {
        var stale = Install(DateTimeOffset.UtcNow);
        stale["first_seen_at"] = Now.AddHours(-24) - TimeSpan.FromMinutes(1);
        stale["registration_key_hash"] = Rows.Bytes();
        stale["registration_body_sha256"] = Rows.Bytes();
        var young = Install(DateTimeOffset.UtcNow);
        young["first_seen_at"] = Now.AddHours(-23);
        young["registration_key_hash"] = Rows.Bytes();
        young["registration_body_sha256"] = Rows.Bytes();
        var staleRow = await SeedAsync("installs", stale);
        var youngRow = await SeedAsync("installs", young);

        await RunAsync();

        const string Sql = "SELECT registration_key_hash IS NULL, registration_body_sha256 IS NULL FROM zaghlol.installs WHERE id = $1";
        Assert.Equal([true, true], (await Db.QueryAsync(fixture.Database.Superuser, Sql, staleRow["id"])).Single());
        Assert.Equal([false, false], (await Db.QueryAsync(fixture.Database.Superuser, Sql, youngRow["id"])).Single());
    }

    [Fact]
    public async Task NotificationsContributionsAndBankRequestsFollowTheirAges()
    {
        var oldNotification = await SeedAsync("store_notifications", new() { ["received_at"] = Now.AddDays(-90) - Day });
        var newNotification = await SeedAsync("store_notifications", new() { ["received_at"] = Now.AddDays(-90) + Day });
        var oldContribution = await SeedAsync("merchant_contributions", new() { ["merchant_norm"] = "old shop", ["received_at"] = Now.AddDays(-180) - Day });
        var newContribution = await SeedAsync("merchant_contributions", new() { ["merchant_norm"] = "new shop", ["received_at"] = Now.AddDays(-180) + Day });
        var promoted = await SeedAsync("contribution_aggregates", new() { ["merchant_norm"] = "promoted shop", ["status"] = "promoted" });
        var rejected = await SeedAsync("contribution_aggregates", new() { ["merchant_norm"] = "rejected shop", ["status"] = "rejected" });
        var collecting = await SeedAsync("contribution_aggregates", new() { ["merchant_norm"] = "collecting shop", ["status"] = "collecting" });
        foreach (var aggregate in new[] { promoted, rejected, collecting })
        {
            await SeedAsync("merchant_contributions", new() { ["merchant_norm"] = aggregate["merchant_norm"], ["institution_code"] = aggregate["institution_code"] });
        }

        var oldBank = await SeedAsync("bank_requests", new() { ["institution_name_norm"] = "old bank", ["received_at"] = Now.AddMonths(-24) - Day });
        var newBank = await SeedAsync("bank_requests", new() { ["institution_name_norm"] = "new bank", ["received_at"] = Now.AddMonths(-24) + Day });

        await RunAsync();

        Assert.False(await ExistsAsync("store_notifications", "external_id", oldNotification["external_id"]));
        Assert.True(await ExistsAsync("store_notifications", "external_id", newNotification["external_id"]));
        Assert.False(await ExistsAsync("merchant_contributions", "merchant_norm", "old shop"));
        Assert.True(await ExistsAsync("merchant_contributions", "merchant_norm", "new shop"));
        Assert.False(await ExistsAsync("merchant_contributions", "merchant_norm", "promoted shop"));
        Assert.False(await ExistsAsync("merchant_contributions", "merchant_norm", "rejected shop"));
        Assert.True(await ExistsAsync("merchant_contributions", "merchant_norm", "collecting shop"));
        Assert.False(await ExistsAsync("bank_requests", "institution_name_norm", oldBank["institution_name_norm"]));
        Assert.True(await ExistsAsync("bank_requests", "institution_name_norm", newBank["institution_name_norm"]));
        Assert.True(await ExistsAsync("contribution_aggregates", "merchant_norm", "promoted shop")); // aggregates stay
    }

    [Fact]
    public async Task ABacklogLargerThanOneBatchIsPurgedInSeveralBatches()
    {
        for (var i = 0; i < 7; i++)
        {
            await SeedAsync("replay_guard", new() { ["expires_at"] = Now.AddMinutes(-5) });
        }

        var result = await RunAsync(batchSize: 3);

        Assert.Equal(7, result.Purged[RetentionRules.ReplayGuard]);
        Assert.Equal(0L, await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.replay_guard WHERE expires_at < $1", Now));
    }
}
