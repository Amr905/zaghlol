using Npgsql;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// One negative test per CHECK (SQLSTATE 23514 and the constraint's name), written by the role that writes the table in
/// production. A guard test fails if a CHECK exists that no case here exercises.
/// </summary>
[Collection(SchemaGroup.Name)]
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

            // catalog_drafts (T-125)
            ["catalog_drafts: unknown entity"] = ("catalog_drafts", Set("entity", "places"), "ck_catalog_drafts_entity"),

            // price_quotes (T-127)
            ["price_quotes: price zero"] = ("price_quotes", Set("price", 0m), "ck_price_quotes_price_positive"),
            ["price_quotes: price negative"] = ("price_quotes", Set("price", -1m), "ck_price_quotes_price_positive"),
            ["price_quotes: feed_price zero"] = ("price_quotes", Set("feed_price", 0m), "ck_price_quotes_price_positive"),
            ["price_quotes: override without an expiry"] = ("price_quotes", Set("is_override", true), "ck_price_quotes_override_expiry"),
            ["price_quotes: expiry without an override"] = ("price_quotes", Set("override_expires_at", Rows.Now().AddHours(1)), "ck_price_quotes_override_expiry"),

            // replay_guard
            ["replay_guard: unknown kind"] = ("replay_guard", Set("kind", "signin_facebook"), "ck_replay_guard_kind"),
            ["replay_guard: key_hash not 32 bytes"] = ("replay_guard", Set("key_hash", Rows.Bytes(64)), "ck_replay_guard_key_hash_length"),

            // idempotency_records
            ["idempotency_records: registerInstall is not stored here"] = ("idempotency_records", Set("operation_id", "registerInstall"), "ck_idempotency_records_operation_id"),
            ["idempotency_records: key of 25 characters"] = ("idempotency_records", Set("idempotency_key", new string('0', 25)), "ck_idempotency_records_idempotency_key_length"),
            ["idempotency_records: key of 27 characters"] = ("idempotency_records", Set("idempotency_key", new string('0', 27)), "ck_idempotency_records_idempotency_key_length"),
            ["idempotency_records: body_sha256 not 32 bytes"] = ("idempotency_records", Set("body_sha256", Rows.Bytes(31)), "ck_idempotency_records_body_sha256_length"),
            ["idempotency_records: a 500 is never stored"] = ("idempotency_records", Set("status", 500), "ck_idempotency_records_status"),
            ["idempotency_records: a 429 is never stored"] = ("idempotency_records", Set("status", 429), "ck_idempotency_records_status"),
            ["idempotency_records: a claim without its lease"] = ("idempotency_records", Set("status", 0), "ck_idempotency_records_claim"),
            ["idempotency_records: a final row with a lease"] = ("idempotency_records", Set("claim_id", Guid.NewGuid()), "ck_idempotency_records_claim"),

            // catalog_versions
            ["catalog_versions: full_snapshot_sha256 not 32 bytes"] = ("catalog_versions", Set("full_snapshot_sha256", Rows.Bytes(31)), "ck_catalog_versions_full_snapshot_sha256_length"),

            // merchant_contributions (privacy CHECKs, SEC F2): digit runs in every script, separators, "@", slug codes
            ["merchant_contributions: merchant_norm over 64 characters"] = ("merchant_contributions", Set("merchant_norm", LongText), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: merchant_norm with a 6-digit run"] = ("merchant_contributions", Set("merchant_norm", "transfer 123456"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: merchant_norm with a phone number"] = ("merchant_contributions", Set("merchant_norm", "pay 01001234567"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: Arabic-Indic digits"] = ("merchant_contributions", Set("merchant_norm", "تحويل ٠١٠١٢٣٤٥٦٧"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: Extended Arabic-Indic digits"] = ("merchant_contributions", Set("merchant_norm", "pay ۰۱۲۳۴۵۶"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: fullwidth digits"] = ("merchant_contributions", Set("merchant_norm", "pay ０１２３４５６"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: mixed-script digits"] = ("merchant_contributions", Set("merchant_norm", "pay 01٢٣45۶"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by spaces"] = ("merchant_contributions", Set("merchant_norm", "pay 010 1234 5678"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by dashes"] = ("merchant_contributions", Set("merchant_norm", "card 41-11-11-11"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by dots"] = ("merchant_contributions", Set("merchant_norm", "acct 12.34.56"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by double spaces (FU-018)"] = ("merchant_contributions", Set("merchant_norm", "acct 12  34  56"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by slashes (FU-018)"] = ("merchant_contributions", Set("merchant_norm", "acct 12 / 34 / 56"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by underscores (FU-018)"] = ("merchant_contributions", Set("merchant_norm", "acct 12_34_56"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by Arabic commas (FU-018)"] = ("merchant_contributions", Set("merchant_norm", "acct 12،34،56"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: digits separated by commas (FU-018)"] = ("merchant_contributions", Set("merchant_norm", "acct 12, 34, 56"), "ck_merchant_contributions_merchant_norm"),
            ["bank_requests: name with slash-separated digits (FU-018)"] = ("bank_requests", Set("institution_name_norm", "bank 98 / 76 / 54"), "ck_bank_requests_institution_name_norm"),
            ["merchant_contributions: an InstaPay address"] = ("merchant_contributions", Set("merchant_norm", "ahmed@instapay"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: an e-mail"] = ("merchant_contributions", Set("merchant_norm", "someone@example.com"), "ck_merchant_contributions_merchant_norm"),
            ["merchant_contributions: institution_code over 64 characters"] = ("merchant_contributions", Set("institution_code", LongText), "ck_merchant_contributions_institution_code"),
            ["merchant_contributions: institution_code upper case"] = ("merchant_contributions", Set("institution_code", "CIB"), "ck_merchant_contributions_institution_code"),
            ["merchant_contributions: institution_code with a space"] = ("merchant_contributions", Set("institution_code", "banque misr"), "ck_merchant_contributions_institution_code"),
            ["merchant_contributions: institution_code with a dash"] = ("merchant_contributions", Set("institution_code", "vodafone-cash"), "ck_merchant_contributions_institution_code"),
            ["merchant_contributions: institution_code empty"] = ("merchant_contributions", Set("institution_code", string.Empty), "ck_merchant_contributions_institution_code"),
            ["merchant_contributions: institution_code in Arabic"] = ("merchant_contributions", Set("institution_code", "البنك"), "ck_merchant_contributions_institution_code"),
            ["merchant_contributions: category_code over 64 characters"] = ("merchant_contributions", Set("category_code", LongText), "ck_merchant_contributions_category_code"),
            ["merchant_contributions: category_code with a dot"] = ("merchant_contributions", Set("category_code", "food.groceries"), "ck_merchant_contributions_category_code"),
            ["merchant_contributions: category_code free text"] = ("merchant_contributions", Set("category_code", "My Rent"), "ck_merchant_contributions_category_code"),
            ["merchant_contributions: install_hash not 32 bytes"] = ("merchant_contributions", Set("install_hash", Rows.Bytes(16)), "ck_merchant_contributions_install_hash_length"),

            // contribution_aggregates
            ["contribution_aggregates: unknown status"] = ("contribution_aggregates", Set("status", "approved"), "ck_contribution_aggregates_status"),

            // bank_requests (privacy CHECKs, SEC F2/F8)
            ["bank_requests: name over 64 characters"] = ("bank_requests", Set("institution_name_norm", LongText), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: name with a 6-digit run"] = ("bank_requests", Set("institution_name_norm", "acct 9876543"), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: name with Arabic-Indic digits"] = ("bank_requests", Set("institution_name_norm", "بنك ٩٨٧٦٥٤"), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: name with fullwidth digits"] = ("bank_requests", Set("institution_name_norm", "bank ９８７６５４"), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: name with spaced digits"] = ("bank_requests", Set("institution_name_norm", "bank 98 76 54"), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: name with an @"] = ("bank_requests", Set("institution_name_norm", "help@bank"), "ck_bank_requests_institution_name_norm"),
            ["bank_requests: country lower case"] = ("bank_requests", Set("country", "eg"), "ck_bank_requests_country"),
            ["bank_requests: country of three letters"] = ("bank_requests", Set("country", "EGY"), "ck_bank_requests_country"),
            ["bank_requests: country free text"] = ("bank_requests", Set("country", "Egypt"), "ck_bank_requests_country"),
            ["bank_requests: unknown channel"] = ("bank_requests", Set("channel", "email"), "ck_bank_requests_channel"),
            ["bank_requests: install_hash not 32 bytes"] = ("bank_requests", Set("install_hash", Rows.Bytes(31)), "ck_bank_requests_install_hash_length"),

            // Format CHECKs (SEC F8)
            ["installs: app_version not a version"] = ("installs", Set("app_version", "latest"), "ck_installs_app_version"),
            ["installs: app_version with one part"] = ("installs", Set("app_version", "1"), "ck_installs_app_version"),
            ["installs: app_version with a v prefix"] = ("installs", Set("app_version", "v1.4.0"), "ck_installs_app_version"),
            ["installs: app_version with free text"] = ("installs", Set("app_version", "1.4.0 (Samsung SM-A515F)"), "ck_installs_app_version"),
            ["installs: app_version suffix too long"] = ("installs", Set("app_version", "1.4.0-" + new string('a', 33)), "ck_installs_app_version"),
            ["daily_active_counts: app_version not a version"] = ("daily_active_counts", Set("app_version", "abc"), "ck_daily_active_counts_app_version"),
            ["store_notifications: last_error with free text"] = ("store_notifications", Set("last_error", "Timeout talking to api.example"), "ck_store_notifications_last_error"),
            ["store_notifications: last_error lower case"] = ("store_notifications", Set("last_error", "store_unavailable"), "ck_store_notifications_last_error"),
            ["store_notifications: store_key over 512 characters"] = ("store_notifications", Set("store_key", new string('k', 513)), "ck_store_notifications_store_key_length"),
            ["purchases: store_key over 512 characters"] = ("purchases", Set("store_key", new string('k', 513)), "ck_purchases_store_key_length"),

            // audit_log (SEC F3): any depth, any letter case, values with "@", and the target
            ["audit_log: details with email"] = ("audit_log", Set("details", new Jsonb("{\"email\": \"x\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: details with order_id"] = ("audit_log", Set("details", new Jsonb("{\"order_id\": \"GPA.0000-0000-0000-00000\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: details with orderId"] = ("audit_log", Set("details", new Jsonb("{\"orderId\": \"GPA.0000-0000-0000-00000\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: nested email"] = ("audit_log", Set("details", new Jsonb("{\"x\": {\"email\": \"x\"}}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: email in an array"] = ("audit_log", Set("details", new Jsonb("{\"x\": [{\"orderId\": \"GPA.1\"}]}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: Email capitalised"] = ("audit_log", Set("details", new Jsonb("{\"Email\": \"x\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: ORDER_ID upper case"] = ("audit_log", Set("details", new Jsonb("{\"ORDER_ID\": \"GPA.1\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: e-mail spelling"] = ("audit_log", Set("details", new Jsonb("{\"e-mail\": \"x\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: an address in another value"] = ("audit_log", Set("details", new Jsonb("{\"ticket_ref\": \"someone@example.com\"}")), "ck_audit_log_details_no_identifiers"),
            ["audit_log: target is an e-mail"] = ("audit_log", Set("target", "someone@example.com"), "ck_audit_log_target_no_email"),
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

        // 23 documented + 24 hardening (octet/char lengths, cause regex, audit, codes, formats) + 1 catalog_drafts (T-125) + 2 price_quotes (T-127)
        // + 2 idempotency_records claim checks (T-130).
        Assert.Equal(52, inSchema.Count);
        Assert.Empty(inSchema.Except(tested));
        Assert.Empty(tested.Except(inSchema));
    }

    [Theory]
    [MemberData(nameof(ValidCauses))]
    public async Task EveryDocumentedCauseIsAccepted(string cause)
    {
        await Rows.InsertAsync(fixture.Database, "purchase_events", Set("cause", cause));
    }

    public static TheoryData<string, string, string> AcceptedValues => new()
    {
        { "merchant_contributions", "merchant_norm", new string('b', 64) },
        { "merchant_contributions", "merchant_norm", "branch 12345" },
        { "merchant_contributions", "merchant_norm", "فرع ١٢٣٤٥" },
        { "merchant_contributions", "merchant_norm", "كارفور المعادي" },
        { "merchant_contributions", "merchant_norm", "shop 12 34 5" },
        { "merchant_contributions", "merchant_norm", "7 eleven 2024" },
        { "merchant_contributions", "merchant_norm", "acct 12    34 56" },
        { "merchant_contributions", "merchant_norm", "12 abc 34 def 56" },
        { "merchant_contributions", "institution_code", "vodafone_cash" },
        { "merchant_contributions", "institution_code", new string('a', 64) },
        { "merchant_contributions", "category_code", "dining_out" },
        { "bank_requests", "institution_name_norm", new string('c', 64) },
        { "bank_requests", "institution_name_norm", "banque du caire" },
        { "bank_requests", "country", "AE" },
        { "installs", "app_version", "1.4.0" },
        { "installs", "app_version", "1.4.0-beta.1" },
        { "installs", "app_version", "1.4.0+42" },
        { "installs", "app_version", "10.2" },
        { "installs", "app_version", "1.2.3.4" },
        { "store_notifications", "last_error", "STORE_UNAVAILABLE" },
        { "store_notifications", "store_key", new string('k', 512) },
        { "purchases", "store_key", new string('k', 512) },
    };

    [Theory]
    [MemberData(nameof(AcceptedValues))]
    public async Task ValuesJustInsideTheLimitsAreAccepted(string table, string column, string value)
    {
        await Rows.InsertAsync(fixture.Database, table, Set(column, value));
    }

    [Fact]
    public async Task AuditDetailsWithTheDocumentedShapesAreAccepted()
    {
        // backend-schema.md section 2: support move details (no e-mail, order ID or free text) and a lookup target.
        await Rows.InsertAsync(
            fixture.Database,
            "audit_log",
            new Dictionary<string, object?>
            {
                ["action"] = "support_seat_move",
                ["target"] = Guid.CreateVersion7().ToString(),
                ["details"] = new Jsonb(
                    """
                    {"from_install": "0193a0c4-0000-7000-8000-000000000001", "to_install": "0193a0c4-0000-7000-8000-000000000002",
                     "reason_code": "correction", "ticket_ref": "ZG-1234", "ownership_check": "order_id",
                     "ownership_outcome": "pass", "outcome": "moved"}
                    """),
            });
        await Rows.InsertAsync(
            fixture.Database,
            "audit_log",
            new Dictionary<string, object?> { ["target"] = "email:" + Convert.ToHexStringLower(Rows.Bytes()) });
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
