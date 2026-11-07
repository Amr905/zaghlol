using System.Text.RegularExpressions;
using Zaghlol.Infrastructure.Persistence.Configurations;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>The migrated schema against backend-schema.md section 2, column by column, for every table.</summary>
[Collection(SchemaCollection.Name)]
public partial class SchemaTests(SchemaFixture fixture)
{
    // Acceptance criterion: these six are named explicitly; the diff below covers every documented table.
    public static readonly TheoryData<string> AcceptanceTables =
        ["installs", "purchases", "purchase_seats", "seat_claimants", "idempotency_records", "audit_log"];

    private const string ColumnsSql = """
        SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, a.atthasdef, a.attidentity <> ''
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'zaghlol' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
          AND c.relname NOT LIKE '\_\_EF%'
        ORDER BY c.relname, a.attnum
        """;

    private string Superuser => fixture.Database.Superuser;

    [Fact]
    public async Task EveryDocumentedTableExistsAndNoOtherTableDoes()
    {
        var documented = SchemaDocument.Tables().Keys.ToHashSet(StringComparer.Ordinal);
        var actual = (await Db.QueryAsync(Superuser, ColumnsSql)).Select(r => (string)r[0]!).ToHashSet(StringComparer.Ordinal);

        Assert.True(documented.Count >= 26, $"parser found only {documented.Count} tables in backend-schema.md");
        Assert.Empty(documented.Except(actual));
        Assert.Empty(actual.Except(documented));
    }

    [Fact]
    public async Task EveryColumnMatchesTheDocumentByNameTypeNullabilityDefaultAndIdentity()
    {
        var actual = (await Db.QueryAsync(Superuser, ColumnsSql))
            .GroupBy(r => (string)r[0]!)
            .ToDictionary(
                g => g.Key,
                g => g.ToDictionary(
                    r => (string)r[1]!,
                    r => new DocColumn((string)r[1]!, (string)r[2]!, (bool)r[3]!, (bool)r[4]!, (bool)r[5]!)),
                StringComparer.Ordinal);

        var problems = new List<string>();
        foreach (var table in SchemaDocument.Tables().Values)
        {
            if (!actual.TryGetValue(table.Name, out var columns))
            {
                problems.Add($"{table.Name}: missing table");
                continue;
            }

            foreach (var column in table.Columns)
            {
                if (!columns.TryGetValue(column.Name, out var db))
                {
                    problems.Add($"{table.Name}.{column.Name}: missing column");
                }
                else if (db != column)
                {
                    problems.Add($"{table.Name}.{column.Name}: documented {column}, database {db}");
                }
            }

            foreach (var extra in columns.Keys.Except(table.Columns.Select(c => c.Name)))
            {
                problems.Add($"{table.Name}.{extra}: column not in backend-schema.md");
            }
        }

        Assert.Empty(problems);
    }

    [Theory]
    [MemberData(nameof(AcceptanceTables))]
    public async Task AcceptanceTablesAreDocumentedAndDiffed(string table)
    {
        var documented = SchemaDocument.Tables();
        Assert.True(documented.ContainsKey(table));
        Assert.NotEmpty(documented[table].Columns);
        var count = await Db.ScalarAsync(
            Superuser,
            "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name = $1",
            table);
        Assert.Equal((long)documented[table].Columns.Count, count);
    }

    [Fact]
    public async Task EntitlementViewHasTheDocumentedColumns()
    {
        var columns = (await Db.QueryAsync(
                Superuser,
                "SELECT column_name FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name = 'v_entitlements' ORDER BY ordinal_position"))
            .Select(r => (string)r[0]!)
            .ToList();

        string[] expected = ["install_id", "purchase_id", "plan", "state", "expires_at", "store", "account_id", "proof", "next_move_at"];
        Assert.Equal(expected, columns);
    }

    [Fact]
    public async Task NoColumnCanHoldARawSeatKeyOrderIdNonceOrDeviceIdentifier()
    {
        var columns = (await Db.QueryAsync(
                Superuser,
                "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'zaghlol'"))
            .Select(r => $"{r[0]}.{r[1]}")
            .ToList();
        string[] allowed = ["accounts.email", "app_attest_keys.public_key"];

        var flagged = columns.Where(c => ForbiddenColumn().IsMatch(c.Split('.')[1])).ToList();

        Assert.NotEmpty(columns);
        Assert.Equal(allowed.Order(StringComparer.Ordinal), flagged.Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task OnlyPlpgsqlIsInstalledSoNoCryptoRunsInTheDatabase()
    {
        var extensions = (await Db.QueryAsync(Superuser, "SELECT extname FROM pg_extension")).Select(r => (string)r[0]!);

        Assert.Equal(new[] { "plpgsql" }, extensions);
    }

    [Fact]
    public async Task NothingIsCreatedInThePublicSchema()
    {
        var count = await Db.ScalarAsync(
            Superuser,
            "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public'");

        Assert.Equal(0L, count);
    }

    [Fact]
    public async Task SeatKeyTrustedDefaultsToFalseAndCarriesTheDocumentedR52Comment()
    {
        var row = (await Db.QueryAsync(
            Superuser,
            """
            SELECT c.column_default, c.is_nullable, col_description('zaghlol.installs'::regclass, c.ordinal_position::int)
            FROM information_schema.columns c
            WHERE c.table_schema = 'zaghlol' AND c.table_name = 'installs' AND c.column_name = 'seat_key_trusted'
            """)).Single();

        Assert.Equal("false", row[0]);
        Assert.Equal("NO", row[1]);
        Assert.Equal(SchemaDocument.ColumnComment("installs", "seat_key_trusted"), row[2]);
        Assert.Equal(InstallConfiguration.SeatKeyTrustedComment, row[2]);

        // A row inserted without it (as the API's role) is untrusted.
        var id = Guid.CreateVersion7();
        await Db.InsertAsync(fixture.Database.Api, "installs", Rows.Install(id));
        Assert.False((bool)(await Db.ScalarAsync(Superuser, "SELECT seat_key_trusted FROM zaghlol.installs WHERE id = $1", id))!);
    }

    [Fact]
    public async Task SupportLinkNoticeIatSitsNextToSupportLinkNoticePending()
    {
        var columns = (await Db.QueryAsync(
                Superuser,
                "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name = 'purchases' ORDER BY ordinal_position"))
            .ToList();
        var names = columns.Select(r => (string)r[0]!).ToList();

        var pending = names.IndexOf("support_link_notice_pending");
        var iat = names.IndexOf("support_link_notice_iat");
        Assert.True(pending >= 0 && iat >= 0);
        Assert.Equal("timestamp with time zone", columns[iat][1]);
        Assert.Equal("YES", columns[iat][2]);
        Assert.Equal("boolean", columns[pending][1]);
        Assert.Equal("NO", columns[pending][2]);
    }

    [Fact]
    public async Task DocumentedAndRetentionIndexesExist()
    {
        var indexes = (await Db.QueryAsync(
                Superuser,
                "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'zaghlol'"))
            .ToDictionary(r => (string)r[0]!, r => (string)r[1]!, StringComparer.Ordinal);

        // name -> fragment the definition must contain
        var expected = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["ix_installs_last_seen"] = "(last_seen_at)",
            ["ix_installs_deleted_at"] = "WHERE (deleted_at IS NOT NULL)",
            ["ix_installs_registration_pending"] = "WHERE (registration_key_hash IS NOT NULL)",
            ["ix_purchases_install"] = "(install_id)",
            ["ix_purchases_account"] = "(account_id)",
            ["ix_purchases_unacked"] = "WHERE ((store = 'google_play'::text) AND (acknowledged = false))",
            ["ix_purchase_seats_install"] = "(install_id)",
            ["ix_idempotency_account"] = "WHERE (account_id IS NOT NULL)",
            ["ix_idempotency_records_expires_at"] = "(expires_at)",
            ["ix_store_notifications_received_at"] = "(received_at)",
            ["ix_merchant_contributions_received_at"] = "(received_at)",
            ["ix_bank_requests_received_at"] = "(received_at)",
            ["ix_audit_log_at"] = "(at)",
            ["ix_audit_log_support_at"] = "'support_unfreeze'",
            ["ix_replay_guard_expires_at"] = "(expires_at)",
            ["ix_seat_claimants_claimed_at"] = "(claimed_at)",
        };

        foreach (var (name, fragment) in expected)
        {
            Assert.True(indexes.ContainsKey(name), $"missing index {name}");
            Assert.Contains(fragment, indexes[name], StringComparison.Ordinal);
        }
    }

    [GeneratedRegex("order_id|nonce|seat_key$|public_key|imei|android_id|idfa|idfv|ad_id|serial|phone|device_id|email")]
    private static partial Regex ForbiddenColumn();
}
