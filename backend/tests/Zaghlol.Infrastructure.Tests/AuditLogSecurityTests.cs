using Npgsql;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>SEC F4: <c>audit_log</c> is append-only and only rows past their retention age can be purged.</summary>
[Collection(SchemaGroup.Name)]
public class AuditLogSecurityTests(SchemaFixture fixture)
{
    private const string Delete = "DELETE FROM zaghlol.audit_log WHERE id = $1";

    [Fact]
    public async Task RowLevelSecurityIsEnabledWithExactlyTheDocumentedPolicies()
    {
        var enabled = await Db.ScalarAsync(fixture.Database.Superuser, "SELECT relrowsecurity FROM pg_class WHERE oid = 'zaghlol.audit_log'::regclass");
        var policies = (await Db.QueryAsync(
                fixture.Database.Superuser,
                "SELECT policyname || ':' || cmd || ':' || array_to_string(roles, ',') FROM pg_policies WHERE schemaname = 'zaghlol' ORDER BY 1"))
            .Select(r => (string)r[0]!)
            .ToList();

        Assert.True((bool)enabled!);
        Assert.Equal(ExpectedPolicies, policies);
    }

    private static readonly string[] ExpectedPolicies =
    [
        "audit_log_append:INSERT:ops_rw",
        "audit_log_read:SELECT:ops_ro,ops_rw,worker_rw",
        "audit_log_retention_delete:DELETE:worker_rw",
    ];

    [Fact]
    public async Task TheWorkerCannotDeleteAFreshRow()
    {
        var id = await InsertAsOwnerAsync("support_lookup", TimeSpan.Zero);

        Assert.Equal(0, await Db.ExecuteAsync(fixture.Database.Worker, Delete, id));
        Assert.Equal(1L, await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.audit_log WHERE id = $1", id));
    }

    [Theory]
    [InlineData("support_lookup", 360, 0)]
    [InlineData("support_lookup", 370, 1)]
    [InlineData("support_seat_move", 370, 1)]
    [InlineData("support_unfreeze", 370, 1)]
    [InlineData("catalog_publish", 370, 0)]
    [InlineData("catalog_publish", 1090, 0)]
    [InlineData("catalog_publish", 1100, 1)]
    public async Task TheWorkerDeletesOnlyRowsPastTheirRetentionAge(string action, int ageDays, int deleted)
    {
        var id = await InsertAsOwnerAsync(action, TimeSpan.FromDays(ageDays));

        Assert.Equal(deleted, await Db.ExecuteAsync(fixture.Database.Worker, Delete, id));
    }

    [Fact]
    public async Task OperatorsAppendFreshRowsButCannotBackdateThem()
    {
        await Rows.InsertAsync(fixture.Database, "audit_log");

        var backdated = await Assert.ThrowsAsync<PostgresException>(() => Rows.InsertAsync(
            fixture.Database,
            "audit_log",
            new Dictionary<string, object?> { ["at"] = Rows.Now().AddYears(-2) }));

        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, backdated.SqlState);
    }

    [Theory]
    [InlineData(-30, true)]
    [InlineData(30, true)]
    [InlineData(-90, false)]
    [InlineData(90, false)]
    [InlineData(3600, false)]
    public async Task OperatorsMayStampRowsOnlyWithinAMinuteOfNow(int offsetSeconds, bool allowed)
    {
        // FU-026: the append policy's window is now() ± 1 minute; a future-dated row can't be planted either.
        var insert = Rows.InsertAsync(fixture.Database, "audit_log", new Dictionary<string, object?> { ["at"] = Rows.Now().AddSeconds(offsetSeconds) });

        if (allowed)
        {
            await insert;
            return;
        }

        var error = await Assert.ThrowsAsync<PostgresException>(() => insert);
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
    }

    [Fact]
    public async Task ARowMustNameARealOperator()
    {
        var error = await Assert.ThrowsAsync<PostgresException>(() => Rows.InsertAsync(
            fixture.Database,
            "audit_log",
            new Dictionary<string, object?> { ["operator_id"] = Guid.CreateVersion7() }));

        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, error.SqlState);
        Assert.Equal("fk_audit_log_operators_operator_id", error.ConstraintName);
    }

    [Fact]
    public async Task ReadersSeeTheLog()
    {
        await Rows.InsertAsync(fixture.Database, "audit_log");

        foreach (var login in new[] { fixture.Database.OpsRo, fixture.Database.Admin, fixture.Database.Worker })
        {
            Assert.True((long)(await Db.ScalarAsync(login, "SELECT count(*) FROM zaghlol.audit_log"))! >= 1);
        }
    }

    private async Task<long> InsertAsOwnerAsync(string action, TimeSpan age)
    {
        var row = await Rows.ResolveAsync(fixture.Database, Rows.Base("audit_log"));
        row["action"] = action;
        row["at"] = Rows.Now() - age;
        var columns = row.Keys.ToList();
        var sql = $"INSERT INTO zaghlol.audit_log ({string.Join(", ", columns)}) VALUES ({string.Join(", ", columns.Select((_, i) => $"${i + 1}"))}) RETURNING id";

        // The owner isn't subject to RLS: it stands in for rows written long ago.
        return (long)(await Db.ScalarAsync(fixture.Database.Migrator, sql, [.. columns.Select(c => row[c])]))!;
    }
}
