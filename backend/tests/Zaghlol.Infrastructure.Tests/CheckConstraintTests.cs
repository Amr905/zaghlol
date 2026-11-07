using Npgsql;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// One negative test per CHECK (SQLSTATE 23514 and the constraint's name), written by the role that writes the table in
/// production. A guard test fails if a CHECK exists that no case here exercises.
/// </summary>
[Collection(SchemaCollection.Name)]
public class CheckConstraintTests(SchemaFixture fixture)
{
    private static readonly string LongText = new('a', 65);

    private static readonly Dictionary<string, (string Table, Dictionary<string, object?> Overrides, string Constraint)> Cases =
        new(StringComparer.Ordinal)
        {
            // installs
            ["installs: unknown platform"] = ("installs", Set("platform", "windows"), "ck_installs_platform"),
            ["installs: token_hash not 32 bytes"] = ("installs", Set("token_hash", Rows.Bytes(31)), "ck_installs_token_hash_length"),
            ["installs: registration_key_hash not 32 bytes"] = ("installs", Set("registration_key_hash", Rows.Bytes(33)), "ck_installs_registration_key_hash_length"),
            ["installs: registration_body_sha256 not 32 bytes"] = ("installs", Set("registration_body_sha256", Rows.Bytes(16)), "ck_installs_registration_body_sha256_length"),
            ["installs: seat_key_hash not 32 bytes"] = ("installs", Set("seat_key_hash", Rows.Bytes(65)), "ck_installs_seat_key_hash_length"),

            // accounts
            ["accounts: unknown provider"] = ("accounts", Set("provider", "facebook"), "ck_accounts_provider"),

            // purchases
            ["purchases: unknown store"] = ("purchases", Set("store", "amazon"), "ck_purchases_store"),
            ["purchases: unknown plan"] = ("purchases", Set("plan", "weekly"), "ck_purchases_plan"),
            ["purchases: unknown state"] = ("purchases", Set("state", "active_ish"), "ck_purchases_state"),
            ["purchases: unknown environment"] = ("purchases", Set("environment", "staging"), "ck_purchases_environment"),
            ["purchases: unknown account_linked_by"] = ("purchases", Set(("account_id", new Ref("accounts")), ("account_linked_by", "operator")), "ck_purchases_account_linked_by"),
            ["purchases: account_id without account_linked_by"] = ("purchases", Set("account_id", new Ref("accounts")), "ck_purchases_account_link_pair"),
            ["purchases: account_linked_by without account_id"] = ("purchases", Set("account_linked_by", "signin"), "ck_purchases_account_link_pair"),

            // purchase_events
            ["purchase_events: unknown cause"] = ("purchase_events", Set("cause", "bogus"), "ck_purchase_events_cause"),
            ["purchase_events: seat_move with an undocumented channel"] = ("purchase_events", Set("cause", "seat_move:sweep"), "ck_purchase_events_cause"),
            ["purchase_events: seat_rebind via support"] = ("purchase_events", Set("cause", "seat_rebind:support"), "ck_purchase_events_cause"),
            ["purchase_events: rtdn without a type"] = ("purchase_events", Set("cause", "rtdn:"), "ck_purchase_events_cause"),
            ["purchase_events: rtdn type longer than 64"] = ("purchase_events", Set("cause", "rtdn:" + new string('X', 65)), "ck_purchase_events_cause"),
            ["purchase_events: assn type with a dash"] = ("purchase_events", Set("cause", "assn:DID-RENEW"), "ck_purchase_events_cause"),
            ["purchase_events: free text after a valid cause"] = ("purchase_events", Set("cause", "verify by alice@example.com"), "ck_purchase_events_cause"),
            ["purchase_events: upper-case prefix"] = ("purchase_events", Set("cause", "RTDN:4"), "ck_purchase_events_cause"),

            // store_notifications
            ["store_notifications: unknown environment"] = ("store_notifications", Set("environment", "xcode"), "ck_store_notifications_environment"),
            ["store_notifications: payload_digest not 32 bytes"] = ("store_notifications", Set("payload_digest", Rows.Bytes(20)), "ck_store_notifications_payload_digest_length"),

            // purchase_seats (acceptance criteria: holder without proof, whole hour, 3 rebinds, last_moved_at alone)
            ["purchase_seats: holder without proof"] = ("purchase_seats", Set("proof", null), "ck_purchase_seats_holder_proof"),
            ["purchase_seats: proof without holder"] = ("purchase_seats", Set("install_id", null), "ck_purchase_seats_holder_proof"),
            ["purchase_seats: unknown proof"] = ("purchase_seats", Set("proof", "trust_me"), "ck_purchase_seats_proof"),
            ["purchase_seats: next_move_at not on a whole hour"] = ("purchase_seats", Set(("last_moved_at", Rows.Now()), ("next_move_at", Rows.WholeHour().AddMinutes(30))), "ck_purchase_seats_next_move_whole_hour"),
            ["purchase_seats: next_move_at one microsecond past the hour"] = ("purchase_seats", Set(("last_moved_at", Rows.Now()), ("next_move_at", Rows.WholeHour().AddTicks(10))), "ck_purchase_seats_next_move_whole_hour"),
            ["purchase_seats: three recent rebinds"] = ("purchase_seats", Set("recent_rebinds", new[] { Rows.Now(), Rows.Now(), Rows.Now() }), "ck_purchase_seats_recent_rebinds_cap"),
            ["purchase_seats: last_moved_at without next_move_at"] = ("purchase_seats", Set("last_moved_at", Rows.Now()), "ck_purchase_seats_move_pair"),
            ["purchase_seats: next_move_at without last_moved_at"] = ("purchase_seats", Set("next_move_at", Rows.WholeHour()), "ck_purchase_seats_move_pair"),
            ["purchase_seats: device_key_hash not 32 bytes"] = ("purchase_seats", Set("device_key_hash", Rows.Bytes(31)), "ck_purchase_seats_device_key_hash_length"),

            // seat_claimants
            ["seat_claimants: unknown channel"] = ("seat_claimants", Set("channel", "support"), "ck_seat_claimants_channel"),
            ["seat_claimants: device_key_hash not 32 bytes"] = ("seat_claimants", Set("device_key_hash", Rows.Bytes(31)), "ck_seat_claimants_device_key_hash_length"),

            // app_attest_keys
            ["app_attest_keys: unknown environment"] = ("app_attest_keys", Set("environment", "sandbox"), "ck_app_attest_keys_environment"),
            ["app_attest_keys: key_id not 32 bytes"] = ("app_attest_keys", Set("key_id", Rows.Bytes(20)), "ck_app_attest_keys_key_id_length"),

            // replay_guard
            ["replay_guard: unknown kind"] = ("replay_guard", Set("kind", "signin_facebook"), "ck_replay_guard_kind"),
            ["replay_guard: key_hash not 32 bytes"] = ("replay_guard", Set("key_hash", Rows.Bytes(64)), "ck_replay_guard_key_hash_length"),

            // idempotency_records
            ["idempotency_records: registerInstall is not stored here"] = ("idempotency_records", Set("operation_id", "registerInstall"), "ck_idempotency_records_operation_id"),
            ["idempotency_records: key of 25 characters"] = ("idempotency_records", Set("idempotency_key", new string('0', 25)), "ck_idempotency_records_idempotency_key_length"),
            ["idempotency_records: key of 27 characters"] = ("idempotency_records", Set("idempotency_key", new string('0', 27)), "ck_idempotency_records_idempotency_key_length"),
            ["idempotency_records: body_sha256 not 32 bytes"] = ("idempotency_records", Set("body_sha256", Rows.Bytes(31)), "ck_idempotency_records_body_sha256_length"),

            // catalog_versions
            ["catalog_versions: full_snapshot_sha256 not 32 bytes"] = ("catalog_versions", Set("full_snapshot_sha256", Rows.Bytes(31)), "ck_catalog_versions_full_snapshot_sha256_length"),

            // merchant_contributions (privacy CHECKs)
            ["merchant_contributions: merchant_norm over 64 characters"] = ("merchant_contributions", Set("merchant_norm", LongText), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: merchant_norm with a 6-digit run"] = ("merchant_contributions", Set("merchant_norm", "transfer 123456"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: merchant_norm with a phone number"] = ("merchant_contributions", Set("merchant_norm", "pay 01001234567"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: institution_code over 64 characters"] = ("merchant_contributions", Set("institution_code", LongText), "ck_merchant_contributions_code_lengths"),
            ["merchant_contributions: category_code over 64 characters"] = ("merchant_contributions", Set("category_code", LongText), "ck_merchant_contributions_code_lengths"),
            ["merchant_contributions: install_hash not 32 bytes"] = ("merchant_contributions", Set("install_hash", Rows.Bytes(16)), "ck_merchant_contributions_install_hash_length"),

            // contribution_aggregates
            ["contribution_aggregates: unknown status"] = ("contribution_aggregates", Set("status", "approved"), "ck_contribution_aggregates_status"),

            // bank_requests (privacy CHECKs)
            ["bank_requests: name over 64 characters"] = ("bank_requests", Set("institution_name_norm", LongText), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: name with a 6-digit run"] = ("bank_requests", Set("institution_name_norm", "acct 9876543"), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: unknown channel"] = ("bank_requests", Set("channel", "email"), "ck_bank_requests_channel"),
            ["bank_requests: install_hash not 32 bytes"] = ("bank_requests", Set("install_hash", Rows.Bytes(31)), "ck_bank_requests_install_hash_length"),

            // audit_log
            ["audit_log: details with email"] = ("audit_log", Set("details", new Jsonb("{\"email\": \"someone@example.com\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: details with order_id"] = ("audit_log", Set("details", new Jsonb("{\"order_id\": \"GPA.0000-0000-0000-00000\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: details with orderId"] = ("audit_log", Set("details", new Jsonb("{\"orderId\": \"GPA.0000-0000-0000-00000\"}")), "ck_audit_log_details_no_identifiers"),
        };

    public static TheoryData<string> CaseNames => [.. Cases.Keys];

    public static TheoryData<string> Tables => [.. Cases.Values.Select(c => c.Table).Distinct()];

    public static TheoryData<string> ValidCauses =>
    [
        "verify", "restore", "seat_bind", "sweep",
        "seat_move:restore", "seat_move:signin", "seat_move:support", "seat_move:account_attach", "seat_move:verify",
        "seat_rebind:restore", "seat_rebind:signin", "seat_rebind_over_cap:restore", "seat_rebind_over_cap:signin",
        "rtdn:4", "rtdn:SUBSCRIPTION_RENEWED", "assn:DID_RENEW", "assn:" + new string('A', 64),
    ];

    [Theory]
    [MemberData(nameof(CaseNames))]
    public async Task CheckRejectsTheRow(string name)
    {
        var (table, overrides, constraint) = Cases[name];

        var error = await Assert.ThrowsAsync<PostgresException>(() => Rows.InsertAsync(fixture.Database, table, overrides));

        Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
        Assert.Equal(constraint, error.ConstraintName);
    }

    [Theory]
    [MemberData(nameof(Tables))]
    public async Task TheBaseRowIsValidSoEachNegativeCaseFailsOnlyForItsOverride(string table)
    {
        var row = await Rows.InsertAsync(fixture.Database, table);

        Assert.NotEmpty(row);
    }

    [Fact]
    public async Task EveryCheckConstraintInTheSchemaHasANegativeCase()
    {
        var inSchema = (await Db.QueryAsync(
                fixture.Database.Superuser,
                """
                SELECT con.conname FROM pg_constraint con
                JOIN pg_namespace n ON n.oid = con.connamespace
                WHERE n.nspname = 'zaghlol' AND con.contype = 'c'
                """))
            .Select(r => (string)r[0]!)
            .ToHashSet(StringComparer.Ordinal);
        var tested = Cases.Values.Select(c => c.Constraint).ToHashSet(StringComparer.Ordinal);

        Assert.Equal(39, inSchema.Count);
        Assert.Empty(inSchema.Except(tested));
        Assert.Empty(tested.Except(inSchema));
    }

    [Theory]
    [MemberData(nameof(ValidCauses))]
    public async Task EveryDocumentedCauseIsAccepted(string cause)
    {
        await Rows.InsertAsync(fixture.Database, "purchase_events", Set("cause", cause));
    }

    [Fact]
    public async Task ContributionsJustInsideThePrivacyLimitsAreAccepted()
    {
        await Rows.InsertAsync(fixture.Database, "merchant_contributions", Set("merchant_norm", new string('b', 64)));
        await Rows.InsertAsync(fixture.Database, "merchant_contributions", Set("merchant_norm", "branch 12345"));
        await Rows.InsertAsync(fixture.Database, "bank_requests", Set("institution_name_norm", new string('c', 64)));
    }

    [Fact]
    public async Task TwoRecentRebindsAndAWholeUtcHourAreAccepted()
    {
        await Rows.InsertAsync(
            fixture.Database,
            "purchase_seats",
            Set(("recent_rebinds", new[] { Rows.Now(), Rows.Now() }), ("last_moved_at", Rows.Now()), ("next_move_at", Rows.WholeHour())));
    }

    [Fact]
    public async Task AWholeUtcHourIsAcceptedInASessionWithAHalfHourTimeZoneOffset()
    {
        // The two-argument date_trunc would truncate in Asia/Kolkata (UTC+05:30) and reject a whole UTC hour.
        var row = await Rows.ResolveAsync(fixture.Database, Rows.Base("purchase_seats"));
        row["last_moved_at"] = Rows.Now();
        row["next_move_at"] = Rows.WholeHour();

        await using var connection = await Db.OpenAsync(fixture.Database.Api);
        await using (var zone = new NpgsqlCommand("SET TIME ZONE 'Asia/Kolkata'", connection))
        {
            await zone.ExecuteNonQueryAsync();
        }

        var columns = row.Keys.ToList();
        await using var insert = Db.Command(
            connection,
            $"INSERT INTO zaghlol.purchase_seats ({string.Join(", ", columns)}) VALUES ({string.Join(", ", columns.Select((_, i) => $"${i + 1}"))})",
            [.. columns.Select(c => row[c])]);
        Assert.Equal(1, await insert.ExecuteNonQueryAsync());
    }

    private static Dictionary<string, object?> Set(string column, object? value) =>
        new(StringComparer.Ordinal) { [column] = value };

    private static Dictionary<string, object?> Set(params (string Column, object? Value)[] values) =>
        values.ToDictionary(v => v.Column, v => v.Value, StringComparer.Ordinal);
}
