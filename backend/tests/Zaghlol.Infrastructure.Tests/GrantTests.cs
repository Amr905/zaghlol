using Npgsql;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>The privileges in the database equal <see cref="GrantMatrix.Current"/> exactly, and the roles can't exceed them.</summary>
[Collection(SchemaGroup.Name)]
public class GrantTests(SchemaFixture fixture)
{
    private static readonly string[] TriggerFunctions = ["accounts_before_delete", "installs_before_delete"];

    public static TheoryData<string, string> Denied => new()
    {
        { "zaghlol_api", "UPDATE zaghlol.audit_log SET target = 'x'" },
        { "zaghlol_api", "CREATE TABLE zaghlol.t122_probe (id int)" },
        { "zaghlol_api", "CREATE TABLE public.t122_probe (id int)" },
        { "zaghlol_api", "INSERT INTO zaghlol.feature_flags (key, version, updated_at, updated_by) VALUES ('x', 1, now(), gen_random_uuid())" },
        { "zaghlol_api", "INSERT INTO zaghlol.audit_log (operator_id, action, target, details) VALUES (gen_random_uuid(), 'a', 't', '{}')" },
        { "zaghlol_api", "UPDATE zaghlol.catalog_categories SET deleted = true" },
        { "zaghlol_api", "DELETE FROM zaghlol.purchases" },
        { "zaghlol_api", "TRUNCATE zaghlol.installs" },
        { "zaghlol_admin", "UPDATE zaghlol.audit_log SET target = 'x'" },
        { "zaghlol_admin", "DELETE FROM zaghlol.audit_log" },
        { "zaghlol_admin", "UPDATE zaghlol.purchases SET state = 'active'" },
        { "zaghlol_admin", "UPDATE zaghlol.purchase_seats SET recent_rebinds = '{}'" },
        { "zaghlol_admin", "SELECT token_hash FROM zaghlol.installs" },
        { "zaghlol_admin", "SELECT response_body_enc FROM zaghlol.idempotency_records" },
        { "zaghlol_worker", "UPDATE zaghlol.audit_log SET target = 'x'" },
        { "zaghlol_worker", "INSERT INTO zaghlol.audit_log (operator_id, action, target, details) VALUES (gen_random_uuid(), 'a', 't', '{}')" },
        { "zaghlol_worker", "TRUNCATE zaghlol.audit_log" },
        { "zaghlol_worker", "UPDATE zaghlol.feature_flags SET enabled = true" },
        { "zaghlol_ops_ro", "SELECT token_hash FROM zaghlol.installs" },
        { "zaghlol_ops_ro", "SELECT apple_refresh_token_enc FROM zaghlol.accounts" },
        { "zaghlol_ops_ro", "SELECT response_body_enc FROM zaghlol.idempotency_records" },
        { "zaghlol_ops_ro", "UPDATE zaghlol.feature_flags SET enabled = true" },
        { "migrator", "CREATE ROLE t122_probe" },
        { "migrator", "CREATE DATABASE t122_probe" },
    };

    public static TheoryData<string, string> Allowed => new()
    {
        { "zaghlol_ops_ro", "SELECT id, platform, seat_key_trusted FROM zaghlol.installs" },
        { "zaghlol_ops_ro", "SELECT * FROM zaghlol.v_entitlements" },
        { "zaghlol_admin", "UPDATE zaghlol.purchases SET dispute_frozen_until = NULL WHERE false" },
        { "zaghlol_admin", "UPDATE zaghlol.purchase_seats SET next_move_at = NULL, last_moved_at = NULL WHERE false" },
        { "zaghlol_api", "SELECT * FROM zaghlol.v_entitlements" },
        { "zaghlol_worker", "DELETE FROM zaghlol.audit_log WHERE false" },
    };

    [Fact]
    public async Task TableAndColumnPrivilegesEqualTheGrantMatrix()
    {
        var tableLevel = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT coalesce(r.rolname, 'PUBLIC'), c.relname, a.privilege_type
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            CROSS JOIN LATERAL aclexplode(c.relacl) a
            LEFT JOIN pg_roles r ON r.oid = a.grantee
            WHERE n.nspname = 'zaghlol' AND c.relkind IN ('r', 'v', 'm', 'p', 'S') AND a.grantee <> c.relowner
              AND c.relname NOT LIKE '\_\_EF%'
            """);
        var columnLevel = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT coalesce(r.rolname, 'PUBLIC'), c.relname || '.' || att.attname, a.privilege_type
            FROM pg_attribute att
            JOIN pg_class c ON c.oid = att.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            CROSS JOIN LATERAL aclexplode(att.attacl) a
            LEFT JOIN pg_roles r ON r.oid = a.grantee
            WHERE n.nspname = 'zaghlol' AND att.attnum > 0 AND NOT att.attisdropped AND a.grantee <> c.relowner
            """);
        var actual = tableLevel.Concat(columnLevel).Select(r => $"{r[0]}|{r[1]}|{r[2]}").ToHashSet(StringComparer.Ordinal);
        var expected = GrantMatrix.Flatten(GrantMatrix.Current);

        Assert.Empty(expected.Except(actual));
        Assert.Empty(actual.Except(expected));
    }

    [Fact]
    public async Task MigratorOwnsTheSchemaAndEveryObjectInIt()
    {
        var notOwned = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'zaghlol' AND pg_get_userbyid(c.relowner) <> 'migrator'
            UNION ALL
            SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'zaghlol' AND pg_get_userbyid(p.proowner) <> 'migrator'
            UNION ALL
            SELECT nspname FROM pg_namespace WHERE nspname = 'zaghlol' AND pg_get_userbyid(nspowner) <> 'migrator'
            """);

        Assert.Empty(notOwned);
    }

    [Fact]
    public async Task OnlyTheFourGroupsMayUseTheSchemaAndNobodyMayUsePublic()
    {
        var acl = (await Db.QueryAsync(
                fixture.Database.Superuser,
                """
                SELECT n.nspname || '|' || coalesce(r.rolname, 'PUBLIC') || '|' || a.privilege_type
                FROM pg_namespace n
                CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
                LEFT JOIN pg_roles r ON r.oid = a.grantee
                WHERE n.nspname IN ('zaghlol', 'public') AND a.grantee <> n.nspowner
                """))
            .Select(r => (string)r[0]!)
            .ToHashSet(StringComparer.Ordinal);

        var expected = GrantMatrix.GroupRoles.Select(g => $"zaghlol|{g}|USAGE").ToHashSet(StringComparer.Ordinal);
        Assert.Equal(expected.Order(StringComparer.Ordinal), acl.Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task TriggerFunctionsAreSecurityDefinerWithAFixedSearchPathAndNotExecutableByAnyone()
    {
        var functions = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT p.proname, p.prosecdef, array_to_string(p.proconfig, ','),
                   (SELECT count(*) FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee <> p.proowner)
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'zaghlol' ORDER BY p.proname
            """);

        Assert.Equal(TriggerFunctions, functions.Select(f => (string)f[0]!));
        Assert.All(functions, f =>
        {
            Assert.True((bool)f[1]!);
            Assert.Equal("search_path=zaghlol, pg_temp", f[2]);
            Assert.Equal(0L, f[3]);
        });
    }

    [Fact]
    public async Task LoginsBelongToExactlyOneGroupAndHaveNoAttributes()
    {
        var logins = (await Db.QueryAsync(
                fixture.Database.Superuser,
                """
                SELECT r.rolname, r.rolcanlogin, r.rolsuper OR r.rolcreaterole OR r.rolcreatedb OR r.rolreplication OR r.rolbypassrls,
                       coalesce((SELECT string_agg(g.rolname, ',') FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid
                                 WHERE m.member = r.oid), '')
                FROM pg_roles r
                WHERE r.rolname IN ('migrator', 'zaghlol_api', 'zaghlol_admin', 'zaghlol_worker', 'zaghlol_ops_ro',
                                    'app_rw', 'ops_rw', 'worker_rw', 'ops_ro')
                """))
            .ToDictionary(r => (string)r[0]!, r => r, StringComparer.Ordinal);

        Assert.Equal(9, logins.Count);
        Assert.All(logins.Values, r => Assert.False((bool)r[2]!));
        foreach (var group in GrantMatrix.GroupRoles)
        {
            Assert.False((bool)logins[group][1]!);
        }

        Assert.True((bool)logins["migrator"][1]!);
        Assert.Equal(string.Empty, logins["migrator"][3]);
        Assert.Equal("app_rw", logins["zaghlol_api"][3]);
        Assert.Equal("ops_rw", logins["zaghlol_admin"][3]);
        Assert.Equal("worker_rw", logins["zaghlol_worker"][3]);
        Assert.Equal("ops_ro", logins["zaghlol_ops_ro"][3]);
    }

    [Theory]
    [MemberData(nameof(Denied))]
    public async Task RoleIsDenied(string login, string sql)
    {
        var error = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(fixture.Database.For(login), sql));

        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
    }

    [Theory]
    [MemberData(nameof(Allowed))]
    public async Task RoleIsAllowed(string login, string sql)
    {
        await Db.ExecuteAsync(fixture.Database.For(login), sql);
    }
}
