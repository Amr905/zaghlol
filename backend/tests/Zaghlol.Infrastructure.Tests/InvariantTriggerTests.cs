using Npgsql;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>SEC F9: the one-way invariants hold whatever role writes (BEFORE UPDATE triggers, SQLSTATE 23514).</summary>
[Collection(SchemaGroup.Name)]
public class InvariantTriggerTests(SchemaFixture fixture)
{
    [Fact]
    public async Task SeatKeyHashIsSetOnceAndClearedOnlyByTheTombstone()
    {
        var database = fixture.Database;
        var install = await Rows.InsertAsync(database, "installs", new Dictionary<string, object?> { ["seat_key_hash"] = Rows.Bytes() });

        var replaced = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Api, "UPDATE zaghlol.installs SET seat_key_hash = $1 WHERE id = $2", Rows.Bytes(), install["id"]));
        AssertInvariant(replaced, "installs_seat_key_hash_set_once");

        var cleared = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Api, "UPDATE zaghlol.installs SET seat_key_hash = NULL WHERE id = $1", install["id"]));
        AssertInvariant(cleared, "installs_seat_key_hash_set_once");

        // Same value again and unrelated columns are fine.
        Assert.Equal(1, await Db.ExecuteAsync(
            database.Api,
            "UPDATE zaghlol.installs SET seat_key_hash = $1, last_seen_at = now() WHERE id = $2",
            install["seat_key_hash"],
            install["id"]));

        // The tombstone clears it (worker, column-level UPDATE).
        Assert.Equal(1, await Db.ExecuteAsync(
            database.Worker, "UPDATE zaghlol.installs SET deleted_at = now(), seat_key_hash = NULL WHERE id = $1", install["id"]));
    }

    [Fact]
    public async Task ASeatKeyHashCanBeSetTheFirstTime()
    {
        var install = await Rows.InsertAsync(fixture.Database, "installs");

        Assert.Equal(1, await Db.ExecuteAsync(
            fixture.Database.Api, "UPDATE zaghlol.installs SET seat_key_hash = $1 WHERE id = $2", Rows.Bytes(), install["id"]));
    }

    [Fact]
    public async Task SeatKeyTrustedOnlyGoesFromFalseToTrue()
    {
        var database = fixture.Database;
        var install = await Rows.InsertAsync(database, "installs");

        Assert.Equal(1, await Db.ExecuteAsync(database.Api, "UPDATE zaghlol.installs SET seat_key_trusted = true WHERE id = $1", install["id"]));
        var reset = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Api, "UPDATE zaghlol.installs SET seat_key_trusted = false WHERE id = $1", install["id"]));
        AssertInvariant(reset, "installs_seat_key_trusted_one_way");
    }

    [Theory]
    [InlineData("zaghlol_api")]
    [InlineData("zaghlol_admin")]
    public async Task AttachReclaimUsedAtIsNeverClearedOrMoved(string login)
    {
        var database = fixture.Database;
        var purchase = await Rows.InsertAsync(database, "purchases");
        Assert.Equal(1, await Db.ExecuteAsync(
            database.For(login), "UPDATE zaghlol.purchases SET attach_reclaim_used_at = now() WHERE id = $1", purchase["id"]));

        var cleared = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.For(login), "UPDATE zaghlol.purchases SET attach_reclaim_used_at = NULL WHERE id = $1", purchase["id"]));
        AssertInvariant(cleared, "purchases_attach_reclaim_never_cleared");

        var moved = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.For(login),
            "UPDATE zaghlol.purchases SET attach_reclaim_used_at = now() - interval '1 day' WHERE id = $1",
            purchase["id"]));
        AssertInvariant(moved, "purchases_attach_reclaim_never_cleared");
    }

    private static void AssertInvariant(PostgresException error, string name)
    {
        Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
        Assert.Equal(name, error.ConstraintName);
    }
}
