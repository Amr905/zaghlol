namespace Zaghlol.Infrastructure.Tests;

/// <summary>FK actions plus the two BEFORE DELETE triggers keep the documented CHECKs true (T-122 design note).</summary>
[Collection(SchemaGroup.Name)]
public class CascadeTests(SchemaFixture fixture)
{
    [Fact]
    public async Task DeletingAnAccountClearsTheLinkAndItsSourceButKeepsTheReclaimMarker()
    {
        var database = fixture.Database;
        var account = await Rows.InsertAsync(database, "accounts");
        var reclaimedAt = Rows.Now();
        var signin = await Rows.InsertAsync(database, "purchases", new Dictionary<string, object?>
        {
            ["account_id"] = account["id"],
            ["account_linked_by"] = "signin",
            ["attach_reclaim_used_at"] = reclaimedAt,
            ["install_id"] = new Ref("installs"),
        });
        var support = await Rows.InsertAsync(database, "purchases", new Dictionary<string, object?>
        {
            ["account_id"] = account["id"],
            ["account_linked_by"] = "support",
        });

        // As the API's own role (account deletion is a /v1 endpoint); it has no UPDATE right it doesn't already need.
        Assert.Equal(1, await Db.ExecuteAsync(database.Api, "DELETE FROM zaghlol.accounts WHERE id = $1", account["id"]));

        var rows = await Db.QueryAsync(
            database.Superuser,
            "SELECT id, account_id, account_linked_by, attach_reclaim_used_at, install_id FROM zaghlol.purchases WHERE id = ANY($1)",
            new[] { (Guid)signin["id"]!, (Guid)support["id"]! });
        Assert.Equal(2, rows.Count);
        Assert.All(rows, r =>
        {
            Assert.Null(r[1]);
            Assert.Null(r[2]);
        });
        var first = rows.Single(r => (Guid)r[0]! == (Guid)signin["id"]!);
        Assert.Equal(reclaimedAt.UtcDateTime, (DateTime)first[3]!);
        Assert.Equal(signin["install_id"], first[4]);
    }

    [Fact]
    public async Task DeletingAnInstallCascadesClaimantsAndAttestKeysAndVacatesTheSeatKeepingTheDeviceKey()
    {
        var database = fixture.Database;
        var holder = await Rows.InsertAsync(database, "installs");
        var other = await Rows.InsertAsync(database, "installs");
        var account = await Rows.InsertAsync(database, "accounts");
        var purchase = await Rows.InsertAsync(database, "purchases", new Dictionary<string, object?> { ["install_id"] = holder["id"] });
        var deviceKeyHash = Rows.Bytes();
        var lastMoved = Rows.Now();
        var nextMove = Rows.WholeHour();
        await Rows.InsertAsync(database, "purchase_seats", new Dictionary<string, object?>
        {
            ["purchase_id"] = purchase["id"],
            ["install_id"] = holder["id"],
            ["proof"] = "device",
            ["bound_at"] = Rows.Now(),
            ["device_key_hash"] = deviceKeyHash,
            ["device_key_trusted"] = true,
            ["last_moved_at"] = lastMoved,
            ["next_move_at"] = nextMove,
            ["recent_rebinds"] = new[] { lastMoved },
        });
        await Rows.InsertAsync(database, "seat_claimants", new Dictionary<string, object?>
        {
            ["purchase_id"] = purchase["id"],
            ["install_id"] = holder["id"],
        });
        await Rows.InsertAsync(database, "seat_claimants", new Dictionary<string, object?>
        {
            ["purchase_id"] = purchase["id"],
            ["install_id"] = other["id"],
        });
        await Rows.InsertAsync(database, "app_attest_keys", new Dictionary<string, object?> { ["install_id"] = holder["id"] });
        await Db.InsertAsync(database.Api, "account_installs", new Dictionary<string, object?>
        {
            ["account_id"] = account["id"],
            ["install_id"] = holder["id"],
        });

        // As the worker (RetentionPurger), which has DELETE on installs but no UPDATE on purchase_seats.
        Assert.Equal(1, await Db.ExecuteAsync(database.Worker, "DELETE FROM zaghlol.installs WHERE id = $1", holder["id"]));

        var seat = (await Db.QueryAsync(
            database.Superuser,
            """
            SELECT install_id, proof, bound_at, device_key_hash, device_key_trusted, last_moved_at, next_move_at,
                   cardinality(recent_rebinds)
            FROM zaghlol.purchase_seats WHERE purchase_id = $1
            """,
            purchase["id"])).Single();
        Assert.Null(seat[0]);
        Assert.Null(seat[1]);
        Assert.Null(seat[2]);
        Assert.Equal(deviceKeyHash, (byte[])seat[3]!);
        Assert.True((bool)seat[4]!);
        Assert.NotNull(seat[5]);
        Assert.NotNull(seat[6]);
        Assert.Equal(1, seat[7]);

        Assert.Equal(0L, await Db.ScalarAsync(database.Superuser, "SELECT count(*) FROM zaghlol.seat_claimants WHERE install_id = $1", holder["id"]));
        Assert.Equal(1L, await Db.ScalarAsync(database.Superuser, "SELECT count(*) FROM zaghlol.seat_claimants WHERE install_id = $1", other["id"]));
        Assert.Equal(0L, await Db.ScalarAsync(database.Superuser, "SELECT count(*) FROM zaghlol.app_attest_keys WHERE install_id = $1", holder["id"]));
        Assert.Equal(0L, await Db.ScalarAsync(database.Superuser, "SELECT count(*) FROM zaghlol.account_installs WHERE install_id = $1", holder["id"]));
        Assert.Null(await Db.ScalarAsync(database.Superuser, "SELECT install_id FROM zaghlol.purchases WHERE id = $1", purchase["id"]));
    }

    [Fact]
    public async Task DeletingAPurchaseDeletesItsSeatEventsAndClaimants()
    {
        var database = fixture.Database;
        var purchase = await Rows.InsertAsync(database, "purchases");
        await Rows.InsertAsync(database, "purchase_seats", new Dictionary<string, object?> { ["purchase_id"] = purchase["id"] });
        await Rows.InsertAsync(database, "purchase_events", new Dictionary<string, object?> { ["purchase_id"] = purchase["id"] });
        await Rows.InsertAsync(database, "seat_claimants", new Dictionary<string, object?> { ["purchase_id"] = purchase["id"] });

        // Nobody but the owner deletes purchases (store reconciliation keeps them); the owner checks the FK actions.
        await Db.ExecuteAsync(database.Migrator, "DELETE FROM zaghlol.purchases WHERE id = $1", purchase["id"]);

        foreach (var table in new[] { "purchase_seats", "purchase_events", "seat_claimants" })
        {
            Assert.Equal(0L, await Db.ScalarAsync(database.Superuser, $"SELECT count(*) FROM zaghlol.{table} WHERE purchase_id = $1", purchase["id"]));
        }
    }
}
