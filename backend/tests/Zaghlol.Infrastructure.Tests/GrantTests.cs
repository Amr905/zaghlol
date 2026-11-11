using Npgsql;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>The privileges in the database equal <see cref="GrantMatrix.Current"/> exactly, and the roles can't exceed them.</summary>
[Collection(SchemaGroup.Name)]
public class GrantTests(SchemaFixture fixture)
{
    private static readonly string[] SchemaFunctions =
    [
        "accounts_before_delete", "count_daily_active", "installs_before_delete", "installs_before_update", "purchases_before_update",
    ];

    /// <summary>T-128: the one function a login may execute (the sync's daily-active increment), and who may.</summary>
    private const string CountDailyActive = "count_daily_active";

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

        // SEC F1: the direct read-only login can't bulk-read personal identifiers or bearer-like store tokens.
        { "zaghlol_ops_ro", "SELECT email FROM zaghlol.accounts" },
        { "zaghlol_ops_ro", "SELECT provider_subject FROM zaghlol.accounts" },
        { "zaghlol_ops_ro", "SELECT * FROM zaghlol.accounts" },
        { "zaghlol_ops_ro", "SELECT store_key FROM zaghlol.purchases" },
        { "zaghlol_ops_ro", "SELECT linked_purchase_token FROM zaghlol.purchases" },
        { "zaghlol_ops_ro", "SELECT store_key FROM zaghlol.store_notifications" },

        // SEC F10 / CR#11-12
        { "zaghlol_api", "SELECT merchant_norm, install_hash FROM zaghlol.merchant_contributions" },
        { "zaghlol_api", "SELECT institution_name_norm FROM zaghlol.bank_requests" },
        { "zaghlol_api", "UPDATE zaghlol.purchases SET dispute_frozen_until = NULL" },
        { "zaghlol_api", "INSERT INTO zaghlol.daily_active_counts (day, platform, app_version, installs) VALUES (current_date, 'ios', '1.0.0', 1)" },
        { "zaghlol_api", "SELECT * FROM zaghlol.daily_active_counts" },
        { "zaghlol_worker", "UPDATE zaghlol.installs SET token_hash = NULL" },
        { "zaghlol_worker", "UPDATE zaghlol.installs SET seat_key_trusted = true" },
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET account_id = NULL" },
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET account_linked_by = NULL" },
        { "zaghlol_admin", "SELECT * FROM zaghlol.replay_guard" },
        { "zaghlol_admin", "DELETE FROM zaghlol.installs" },
        { "zaghlol_admin", "SELECT apple_refresh_token_enc FROM zaghlol.accounts" },

        // T-128: only app_rw may add to the daily-active counter, and only through the function.
        { "zaghlol_api", "UPDATE zaghlol.daily_active_counts SET installs = 1000" },
        { "zaghlol_api", "DELETE FROM zaghlol.daily_active_counts" },
        { "zaghlol_admin", "SELECT zaghlol.count_daily_active('ios', '1.0.0')" },
        { "zaghlol_worker", "SELECT zaghlol.count_daily_active('ios', '1.0.0')" },
        { "zaghlol_ops_ro", "SELECT zaghlol.count_daily_active('ios', '1.0.0')" },

        // T-134: the worker never writes verify's binding/payment columns or seats, never inserts purchases; only the worker
        // schedules notification retries, and ops_ro can't read the back-off stamp.
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET last_payment_at = now() WHERE false" },
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET obfuscated_install_ref = NULL WHERE false" },
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET environment = 'sandbox' WHERE false" },
        { "zaghlol_worker", "UPDATE zaghlol.purchase_seats SET install_id = NULL WHERE false" },
        { "zaghlol_worker", "INSERT INTO zaghlol.purchases (id) SELECT gen_random_uuid() WHERE false" },
        { "zaghlol_api", "UPDATE zaghlol.store_notifications SET next_attempt_at = now() WHERE false" },
        { "zaghlol_ops_ro", "SELECT next_attempt_at FROM zaghlol.store_notifications" },

        // T-133: no new grant. The Google worker statement never needs more; the worker still can't touch verify-only columns or
        // seats, or insert purchases.
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET install_id = NULL WHERE false" },
        { "zaghlol_worker", "UPDATE zaghlol.purchase_seats SET proof = 'basic' WHERE false" },
    };

    public static TheoryData<string, string> Allowed => new()
    {
        { "zaghlol_ops_ro", "SELECT id, platform, seat_key_trusted FROM zaghlol.installs" },
        { "zaghlol_ops_ro", "SELECT * FROM zaghlol.v_entitlements" },
        { "zaghlol_ops_ro", "SELECT id, provider, created_at FROM zaghlol.accounts" },
        { "zaghlol_ops_ro", "SELECT id, state, store FROM zaghlol.purchases" },
        { "zaghlol_admin", "UPDATE zaghlol.purchases SET dispute_frozen_until = NULL WHERE false" },
        { "zaghlol_admin", "UPDATE zaghlol.purchase_seats SET next_move_at = NULL, last_moved_at = NULL WHERE false" },
        { "zaghlol_admin", "SELECT email, provider_subject FROM zaghlol.accounts" },
        { "zaghlol_admin", "SELECT store_key, linked_purchase_token FROM zaghlol.purchases" },
        { "zaghlol_api", "SELECT * FROM zaghlol.v_entitlements" },
        { "zaghlol_api", "UPDATE zaghlol.purchases SET state = 'active', support_link_notice_pending = false WHERE false" },
        {
            "zaghlol_api",
            "INSERT INTO zaghlol.merchant_contributions (id, merchant_norm, institution_code, category_code, install_hash) "
            + "VALUES (gen_random_uuid(), 'grant probe', 'cib', 'groceries', decode(md5(random()::text) || md5(random()::text), 'hex')) "
            + "RETURNING received_at"
        },
        { "zaghlol_worker", "DELETE FROM zaghlol.audit_log WHERE false" },
        { "zaghlol_worker", "UPDATE zaghlol.installs SET deleted_at = now(), registration_key_hash = NULL WHERE false" },
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET state = 'expired', acknowledged = true WHERE false" },
        { "zaghlol_api", "SELECT zaghlol.count_daily_active('ios', '1.0.0')" },
        { "zaghlol_api", "UPDATE zaghlol.installs SET last_sync_at = now() WHERE false" },

        // T-134: the worker statement and the history job's insert.
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET state = 'refunded', expires_at = expires_at, product_id = product_id, plan = plan, last_verified_at = now() WHERE false" },
        {
            "zaghlol_worker",
            "INSERT INTO zaghlol.store_notifications (id, store, external_id, type, payload_digest) "
            + "SELECT gen_random_uuid(), 'app_store', 'grant-probe', 'TEST', sha256('x'::bytea) WHERE false ON CONFLICT (store, external_id) DO NOTHING"
        },
        { "zaghlol_worker", "UPDATE zaghlol.store_notifications SET attempts = 1, next_attempt_at = now(), last_error = 'STORE_ERROR' WHERE false" },
        { "zaghlol_api", "INSERT INTO zaghlol.store_notifications (id, store, external_id, type, payload_digest) SELECT gen_random_uuid(), 'app_store', 'grant-probe', 'TEST', sha256('x'::bytea) WHERE false ON CONFLICT (store, external_id) DO NOTHING" },

        // T-133: the Google worker statement and the voided/sweep enqueue on the worker login.
        { "zaghlol_worker", "UPDATE zaghlol.purchases SET state = 'refunded', expires_at = expires_at, last_verified_at = now() WHERE store = 'google_play' AND false" },
        {
            "zaghlol_worker",
            "INSERT INTO zaghlol.store_notifications (id, store, external_id, type, store_key, event_time, payload_digest) "
            + "SELECT gen_random_uuid(), 'google_play', 'voided:' || encode(sha256('x'::bytea), 'hex'), 'VOIDED_PURCHASE', 'tok', now(), sha256('x'::bytea) WHERE false ON CONFLICT (store, external_id) DO NOTHING"
        },
    };

    [Fact]
    public async Task OnlyTheFiveLoginsMayConnectToTheDatabase()
    {
        var acl = (await Db.QueryAsync(
                fixture.Database.Superuser,
                """
                SELECT coalesce(r.rolname, 'PUBLIC') || '|' || a.privilege_type
                FROM pg_database d
                CROSS JOIN LATERAL aclexplode(coalesce(d.datacl, acldefault('d', d.datdba))) a
                LEFT JOIN pg_roles r ON r.oid = a.grantee
                WHERE d.datname = current_database() AND a.grantee <> d.datdba
                """))
            .Select(r => (string)r[0]!)
            .Order(StringComparer.Ordinal)
            .ToList();

        Assert.Equal(ExpectedDatabaseAcl, acl);
    }

    private static readonly string[] ExpectedDatabaseAcl =
    [
        "migrator|CONNECT", "zaghlol_admin|CONNECT", "zaghlol_api|CONNECT", "zaghlol_ops_ro|CONNECT", "zaghlol_worker|CONNECT",
    ];

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
    public async Task FunctionsHaveAFixedSearchPathAndOnlyTheDeleteBackstopsAndTheCounterAreSecurityDefiner()
    {
        var functions = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT p.proname, p.prosecdef, array_to_string(p.proconfig, ','),
                   (SELECT coalesce(string_agg(coalesce(r.rolname, 'PUBLIC') || ':' || a.privilege_type, ','), '')
                    FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    LEFT JOIN pg_roles r ON r.oid = a.grantee
                    WHERE a.grantee <> p.proowner)
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'zaghlol' ORDER BY p.proname
            """);

        Assert.Equal(SchemaFunctions, functions.Select(f => (string)f[0]!));
        Assert.All(functions, f =>
        {
            var name = (string)f[0]!;
            var counter = name == CountDailyActive;

            // The delete backstops update another table and the counter writes a table app_rw has no grant on, so they run
            // as the owner; the update invariants only read OLD and NEW and run as the caller.
            Assert.Equal(name.EndsWith("_before_delete", StringComparison.Ordinal) || counter, (bool)f[1]!);
            Assert.Equal("search_path=zaghlol, pg_temp", f[2]);
            Assert.Equal(counter ? "app_rw:EXECUTE" : string.Empty, f[3]);
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

    [Fact]
    public async Task NoRoleHoldsAnyPrivilegeOnASequence()
    {
        // FU-026: identity columns need no sequence grant (INSERT on the table is enough), so no login may read, bump
        // or reset a sequence (which would leak row counts or burn ids).
        var sequences = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT c.relname, (SELECT count(*) FROM aclexplode(c.relacl) a WHERE a.grantee <> c.relowner)
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'zaghlol' AND c.relkind = 'S'
            """);

        Assert.NotEmpty(sequences);
        Assert.All(sequences, s => Assert.Equal(0L, s[1]));

        var auditSequence = (string)(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT pg_get_serial_sequence('zaghlol.audit_log', 'id')"))!;
        foreach (var login in new[] { fixture.Database.Api, fixture.Database.Admin, fixture.Database.Worker, fixture.Database.OpsRo })
        {
            foreach (var sql in SequenceProbes)
            {
                var error = await Assert.ThrowsAsync<PostgresException>(() => Db.ScalarAsync(login, string.Format(System.Globalization.CultureInfo.InvariantCulture, sql, auditSequence)));
                Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
            }
        }
    }

    private static readonly string[] SequenceProbes =
    [
        "SELECT nextval('{0}')", "SELECT setval('{0}', 1)", "SELECT last_value FROM {0}",
    ];

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
