using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "zaghlol");

            migrationBuilder.CreateTable(
                name: "accounts",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    provider = table.Column<string>(type: "text", nullable: false),
                    provider_subject = table.Column<string>(type: "text", nullable: false),
                    email = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    last_sign_in_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    apple_refresh_token_enc = table.Column<byte[]>(type: "bytea", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_accounts", x => x.id);
                    table.CheckConstraint("ck_accounts_provider", "provider IN ('google','apple')");
                });

            migrationBuilder.CreateTable(
                name: "audit_log",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    operator_id = table.Column<Guid>(type: "uuid", nullable: false),
                    action = table.Column<string>(type: "text", nullable: false),
                    target = table.Column<string>(type: "text", nullable: false),
                    details = table.Column<string>(type: "jsonb", nullable: false),
                    at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_audit_log", x => x.id);
                    table.CheckConstraint("ck_audit_log_details_no_identifiers", "NOT (details ?| array['email','order_id','orderId'])");
                });

            migrationBuilder.CreateTable(
                name: "bank_requests",
                schema: "zaghlol",
                columns: table => new
                {
                    institution_name_norm = table.Column<string>(type: "text", nullable: false),
                    country = table.Column<string>(type: "text", nullable: false),
                    channel = table.Column<string>(type: "text", nullable: false),
                    install_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    received_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_bank_requests", x => new { x.institution_name_norm, x.country, x.channel, x.install_hash });
                    table.CheckConstraint("ck_bank_requests_channel", "channel IN ('sms','notification')");
                    table.CheckConstraint("ck_bank_requests_install_hash_length", "octet_length(install_hash) = 32");
                    table.CheckConstraint("ck_bank_requests_institution_name_norm", "char_length(institution_name_norm) <= 64 AND institution_name_norm !~ '[0-9]{6,}'");
                });

            migrationBuilder.CreateTable(
                name: "catalog_categories",
                schema: "zaghlol",
                columns: table => new
                {
                    code = table.Column<string>(type: "text", nullable: false),
                    parent_code = table.Column<string>(type: "text", nullable: true),
                    name_ar = table.Column<string>(type: "text", nullable: false),
                    name_en = table.Column<string>(type: "text", nullable: false),
                    icon = table.Column<string>(type: "text", nullable: false),
                    color = table.Column<string>(type: "text", nullable: false),
                    bucket = table.Column<string>(type: "text", nullable: false),
                    sort = table.Column<int>(type: "integer", nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_categories", x => x.code);
                    table.ForeignKey(
                        name: "fk_catalog_categories_catalog_categories_parent_code",
                        column: x => x.parent_code,
                        principalSchema: "zaghlol",
                        principalTable: "catalog_categories",
                        principalColumn: "code");
                });

            migrationBuilder.CreateTable(
                name: "catalog_keywords",
                schema: "zaghlol",
                columns: table => new
                {
                    keyword_norm = table.Column<string>(type: "text", nullable: false),
                    lang = table.Column<string>(type: "text", nullable: false),
                    category_code = table.Column<string>(type: "text", nullable: false),
                    weight = table.Column<int>(type: "integer", nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_keywords", x => new { x.keyword_norm, x.lang });
                });

            migrationBuilder.CreateTable(
                name: "catalog_versions",
                schema: "zaghlol",
                columns: table => new
                {
                    version = table.Column<int>(type: "integer", nullable: false),
                    published_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    published_by = table.Column<Guid>(type: "uuid", nullable: false),
                    notes = table.Column<string>(type: "text", nullable: true),
                    full_snapshot_url = table.Column<string>(type: "text", nullable: false),
                    full_snapshot_sha256 = table.Column<byte[]>(type: "bytea", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_versions", x => x.version);
                    table.CheckConstraint("ck_catalog_versions_full_snapshot_sha256_length", "octet_length(full_snapshot_sha256) = 32");
                });

            migrationBuilder.CreateTable(
                name: "contribution_aggregates",
                schema: "zaghlol",
                columns: table => new
                {
                    merchant_norm = table.Column<string>(type: "text", nullable: false),
                    institution_code = table.Column<string>(type: "text", nullable: false),
                    distinct_installs = table.Column<int>(type: "integer", nullable: false),
                    top_category_code = table.Column<string>(type: "text", nullable: false),
                    category_votes = table.Column<string>(type: "jsonb", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    reviewed_by = table.Column<Guid>(type: "uuid", nullable: true),
                    reviewed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_contribution_aggregates", x => new { x.merchant_norm, x.institution_code });
                    table.CheckConstraint("ck_contribution_aggregates_status", "status IN ('collecting','ready_for_review','promoted','rejected')");
                });

            migrationBuilder.CreateTable(
                name: "daily_active_counts",
                schema: "zaghlol",
                columns: table => new
                {
                    day = table.Column<DateOnly>(type: "date", nullable: false),
                    platform = table.Column<string>(type: "text", nullable: false),
                    app_version = table.Column<string>(type: "text", nullable: false),
                    installs = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_daily_active_counts", x => new { x.day, x.platform, x.app_version });
                });

            migrationBuilder.CreateTable(
                name: "feature_flags",
                schema: "zaghlol",
                columns: table => new
                {
                    key = table.Column<string>(type: "text", nullable: false),
                    enabled = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    rules = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'"),
                    version = table.Column<int>(type: "integer", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_feature_flags", x => x.key);
                });

            migrationBuilder.CreateTable(
                name: "fx_rates",
                schema: "zaghlol",
                columns: table => new
                {
                    @base = table.Column<string>(name: "base", type: "text", nullable: false),
                    quote = table.Column<string>(type: "text", nullable: false),
                    rate = table.Column<decimal>(type: "numeric(24,12)", precision: 24, scale: 12, nullable: false),
                    as_of = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    source = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fx_rates", x => new { x.@base, x.quote });
                });

            migrationBuilder.CreateTable(
                name: "idempotency_records",
                schema: "zaghlol",
                columns: table => new
                {
                    install_id = table.Column<Guid>(type: "uuid", nullable: false),
                    operation_id = table.Column<string>(type: "text", nullable: false),
                    idempotency_key = table.Column<string>(type: "text", nullable: false),
                    body_sha256 = table.Column<byte[]>(type: "bytea", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    response_body_enc = table.Column<byte[]>(type: "bytea", nullable: false),
                    account_id = table.Column<Guid>(type: "uuid", nullable: true),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_idempotency_records", x => new { x.install_id, x.operation_id, x.idempotency_key });
                    table.CheckConstraint("ck_idempotency_records_body_sha256_length", "octet_length(body_sha256) = 32");
                    table.CheckConstraint("ck_idempotency_records_idempotency_key_length", "char_length(idempotency_key) = 26");
                    table.CheckConstraint("ck_idempotency_records_operation_id", "operation_id IN ('verifyPurchase','signIn')");
                });

            migrationBuilder.CreateTable(
                name: "installs",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    platform = table.Column<string>(type: "text", nullable: false),
                    app_version = table.Column<string>(type: "text", nullable: false),
                    catalog_version = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    first_seen_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    last_seen_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    registration_key_hash = table.Column<byte[]>(type: "bytea", nullable: true),
                    registration_body_sha256 = table.Column<byte[]>(type: "bytea", nullable: true),
                    seat_key_hash = table.Column<byte[]>(type: "bytea", nullable: true),
                    seat_key_trusted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false, comment: "set ONLY by an App Attest-covered request (R5-2): a restore whose assertion covered this key as element 0. iOS sign-in has no App Attest (D-66), so it never sets it. Verify and sign-in register the key UNTRUSTED. Only false -> true. Gates the over-cap sign-in rebind (D-65(a), backend-api §4.3)")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_installs", x => x.id);
                    table.CheckConstraint("ck_installs_platform", "platform IN ('android','ios')");
                    table.CheckConstraint("ck_installs_registration_body_sha256_length", "octet_length(registration_body_sha256) = 32");
                    table.CheckConstraint("ck_installs_registration_key_hash_length", "octet_length(registration_key_hash) = 32");
                    table.CheckConstraint("ck_installs_seat_key_hash_length", "octet_length(seat_key_hash) = 32");
                    table.CheckConstraint("ck_installs_token_hash_length", "octet_length(token_hash) = 32");
                });

            migrationBuilder.CreateTable(
                name: "merchant_contributions",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    merchant_norm = table.Column<string>(type: "text", nullable: false),
                    institution_code = table.Column<string>(type: "text", nullable: false),
                    category_code = table.Column<string>(type: "text", nullable: false),
                    install_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    received_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_merchant_contributions", x => x.id);
                    table.CheckConstraint("ck_merchant_contributions_code_lengths", "char_length(institution_code) <= 64 AND char_length(category_code) <= 64");
                    table.CheckConstraint("ck_merchant_contributions_install_hash_length", "octet_length(install_hash) = 32");
                    table.CheckConstraint("ck_merchant_contributions_merchant_norm", "char_length(merchant_norm) <= 64 AND merchant_norm !~ '[0-9]{6,}'");
                });

            migrationBuilder.CreateTable(
                name: "operators",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    oidc_subject = table.Column<string>(type: "text", nullable: false),
                    display_name = table.Column<string>(type: "text", nullable: false),
                    roles = table.Column<string[]>(type: "text[]", nullable: false),
                    disabled_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_operators", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "price_quotes",
                schema: "zaghlol",
                columns: table => new
                {
                    symbol = table.Column<string>(type: "text", nullable: false),
                    currency = table.Column<string>(type: "text", nullable: false),
                    price = table.Column<decimal>(type: "numeric(20,6)", precision: 20, scale: 6, nullable: false),
                    per_unit = table.Column<string>(type: "text", nullable: false),
                    as_of = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    source = table.Column<string>(type: "text", nullable: false),
                    is_override = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    override_expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_price_quotes", x => new { x.symbol, x.currency });
                });

            migrationBuilder.CreateTable(
                name: "replay_guard",
                schema: "zaghlol",
                columns: table => new
                {
                    key_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    kind = table.Column<string>(type: "text", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_replay_guard", x => x.key_hash);
                    table.CheckConstraint("ck_replay_guard_key_hash_length", "octet_length(key_hash) = 32");
                    table.CheckConstraint("ck_replay_guard_kind", "kind IN ('signin_google','signin_apple','play_integrity')");
                });

            migrationBuilder.CreateTable(
                name: "store_notifications",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    store = table.Column<string>(type: "text", nullable: false),
                    external_id = table.Column<string>(type: "text", nullable: false),
                    type = table.Column<string>(type: "text", nullable: false),
                    subtype = table.Column<string>(type: "text", nullable: true),
                    product_id = table.Column<string>(type: "text", nullable: true),
                    store_key = table.Column<string>(type: "text", nullable: true),
                    environment = table.Column<string>(type: "text", nullable: true),
                    event_time = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    received_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    processed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    attempts = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    last_error = table.Column<string>(type: "text", nullable: true),
                    payload_digest = table.Column<byte[]>(type: "bytea", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_store_notifications", x => x.id);
                    table.CheckConstraint("ck_store_notifications_environment", "environment IN ('production','sandbox')");
                    table.CheckConstraint("ck_store_notifications_payload_digest_length", "octet_length(payload_digest) = 32");
                });

            migrationBuilder.CreateTable(
                name: "catalog_merchants",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    canonical = table.Column<string>(type: "text", nullable: false),
                    name_ar = table.Column<string>(type: "text", nullable: true),
                    name_en = table.Column<string>(type: "text", nullable: true),
                    category_code = table.Column<string>(type: "text", nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_merchants", x => x.id);
                    table.ForeignKey(
                        name: "fk_catalog_merchants_catalog_categories_category_code",
                        column: x => x.category_code,
                        principalSchema: "zaghlol",
                        principalTable: "catalog_categories",
                        principalColumn: "code");
                });

            migrationBuilder.CreateTable(
                name: "account_installs",
                schema: "zaghlol",
                columns: table => new
                {
                    account_id = table.Column<Guid>(type: "uuid", nullable: false),
                    install_id = table.Column<Guid>(type: "uuid", nullable: false),
                    linked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_account_installs", x => new { x.account_id, x.install_id });
                    table.ForeignKey(
                        name: "fk_account_installs_accounts_account_id",
                        column: x => x.account_id,
                        principalSchema: "zaghlol",
                        principalTable: "accounts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_account_installs_installs_install_id",
                        column: x => x.install_id,
                        principalSchema: "zaghlol",
                        principalTable: "installs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "app_attest_keys",
                schema: "zaghlol",
                columns: table => new
                {
                    key_id = table.Column<byte[]>(type: "bytea", nullable: false),
                    install_id = table.Column<Guid>(type: "uuid", nullable: false),
                    public_key = table.Column<byte[]>(type: "bytea", nullable: false),
                    sign_count = table.Column<long>(type: "bigint", nullable: false),
                    environment = table.Column<string>(type: "text", nullable: false),
                    attested_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_app_attest_keys", x => x.key_id);
                    table.CheckConstraint("ck_app_attest_keys_environment", "environment IN ('production','development')");
                    table.CheckConstraint("ck_app_attest_keys_key_id_length", "octet_length(key_id) = 32");
                    table.ForeignKey(
                        name: "fk_app_attest_keys_installs_install_id",
                        column: x => x.install_id,
                        principalSchema: "zaghlol",
                        principalTable: "installs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "purchases",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    store = table.Column<string>(type: "text", nullable: false),
                    product_id = table.Column<string>(type: "text", nullable: false),
                    plan = table.Column<string>(type: "text", nullable: false),
                    store_key = table.Column<string>(type: "text", nullable: false),
                    linked_purchase_token = table.Column<string>(type: "text", nullable: true),
                    install_id = table.Column<Guid>(type: "uuid", nullable: true),
                    account_id = table.Column<Guid>(type: "uuid", nullable: true),
                    account_linked_by = table.Column<string>(type: "text", nullable: true),
                    attach_reclaim_used_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    dispute_frozen_until = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    support_link_notice_pending = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    support_link_notice_iat = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    state = table.Column<string>(type: "text", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    acknowledged = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    environment = table.Column<string>(type: "text", nullable: false),
                    obfuscated_install_ref = table.Column<string>(type: "text", nullable: true),
                    last_verified_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchases", x => x.id);
                    table.CheckConstraint("ck_purchases_account_link_pair", "(account_id IS NULL) = (account_linked_by IS NULL)");
                    table.CheckConstraint("ck_purchases_account_linked_by", "account_linked_by IN ('signin','support')");
                    table.CheckConstraint("ck_purchases_environment", "environment IN ('production','sandbox')");
                    table.CheckConstraint("ck_purchases_plan", "plan IN ('monthly','yearly','lifetime')");
                    table.CheckConstraint("ck_purchases_state", "state IN ('pending','active','in_grace','on_hold','paused','canceled_active','expired','refunded','revoked')");
                    table.CheckConstraint("ck_purchases_store", "store IN ('google_play','app_store')");
                    table.ForeignKey(
                        name: "fk_purchases_accounts_account_id",
                        column: x => x.account_id,
                        principalSchema: "zaghlol",
                        principalTable: "accounts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_purchases_installs_install_id",
                        column: x => x.install_id,
                        principalSchema: "zaghlol",
                        principalTable: "installs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "catalog_aliases",
                schema: "zaghlol",
                columns: table => new
                {
                    merchant_id = table.Column<int>(type: "integer", nullable: false),
                    alias_norm = table.Column<string>(type: "text", nullable: false),
                    match = table.Column<string>(type: "text", nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_aliases", x => new { x.alias_norm, x.merchant_id });
                    table.ForeignKey(
                        name: "fk_catalog_aliases_catalog_merchants_merchant_id",
                        column: x => x.merchant_id,
                        principalSchema: "zaghlol",
                        principalTable: "catalog_merchants",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "purchase_events",
                schema: "zaghlol",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    purchase_id = table.Column<Guid>(type: "uuid", nullable: false),
                    from_state = table.Column<string>(type: "text", nullable: true),
                    to_state = table.Column<string>(type: "text", nullable: false),
                    cause = table.Column<string>(type: "text", nullable: false),
                    occurred_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchase_events", x => x.id);
                    table.CheckConstraint("ck_purchase_events_cause", "cause ~ '^(verify|restore|seat_bind|sweep|seat_move:(restore|signin|support|account_attach|verify)|seat_rebind:(restore|signin)|seat_rebind_over_cap:(restore|signin)|(rtdn|assn):[A-Za-z0-9_]{1,64})$'");
                    table.ForeignKey(
                        name: "fk_purchase_events_purchases_purchase_id",
                        column: x => x.purchase_id,
                        principalSchema: "zaghlol",
                        principalTable: "purchases",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "purchase_seats",
                schema: "zaghlol",
                columns: table => new
                {
                    purchase_id = table.Column<Guid>(type: "uuid", nullable: false),
                    install_id = table.Column<Guid>(type: "uuid", nullable: true),
                    proof = table.Column<string>(type: "text", nullable: true),
                    bound_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    last_moved_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    next_move_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    device_key_hash = table.Column<byte[]>(type: "bytea", nullable: true),
                    device_key_trusted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    recent_rebinds = table.Column<DateTimeOffset[]>(type: "timestamp with time zone[]", nullable: false, defaultValueSql: "'{}'")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchase_seats", x => x.purchase_id);
                    table.CheckConstraint("ck_purchase_seats_device_key_hash_length", "octet_length(device_key_hash) = 32");
                    table.CheckConstraint("ck_purchase_seats_holder_proof", "(install_id IS NULL) = (proof IS NULL)");
                    table.CheckConstraint("ck_purchase_seats_move_pair", "(last_moved_at IS NULL) = (next_move_at IS NULL)");
                    table.CheckConstraint("ck_purchase_seats_next_move_whole_hour", "next_move_at IS NULL OR date_trunc('hour', next_move_at, 'UTC') = next_move_at");
                    table.CheckConstraint("ck_purchase_seats_proof", "proof IN ('binding','attested','basic','account','support','device')");
                    table.CheckConstraint("ck_purchase_seats_recent_rebinds_cap", "cardinality(recent_rebinds) <= 2");
                    table.ForeignKey(
                        name: "fk_purchase_seats_installs_install_id",
                        column: x => x.install_id,
                        principalSchema: "zaghlol",
                        principalTable: "installs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_purchase_seats_purchases_purchase_id",
                        column: x => x.purchase_id,
                        principalSchema: "zaghlol",
                        principalTable: "purchases",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "seat_claimants",
                schema: "zaghlol",
                columns: table => new
                {
                    purchase_id = table.Column<Guid>(type: "uuid", nullable: false),
                    install_id = table.Column<Guid>(type: "uuid", nullable: false),
                    claimed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    channel = table.Column<string>(type: "text", nullable: false),
                    device_key_hash = table.Column<byte[]>(type: "bytea", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_seat_claimants", x => new { x.purchase_id, x.install_id });
                    table.CheckConstraint("ck_seat_claimants_channel", "channel IN ('restore','signin','verify')");
                    table.CheckConstraint("ck_seat_claimants_device_key_hash_length", "octet_length(device_key_hash) = 32");
                    table.ForeignKey(
                        name: "fk_seat_claimants_installs_install_id",
                        column: x => x.install_id,
                        principalSchema: "zaghlol",
                        principalTable: "installs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_seat_claimants_purchases_purchase_id",
                        column: x => x.purchase_id,
                        principalSchema: "zaghlol",
                        principalTable: "purchases",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_account_installs_install_id",
                schema: "zaghlol",
                table: "account_installs",
                column: "install_id");

            migrationBuilder.CreateIndex(
                name: "ux_accounts_provider_provider_subject",
                schema: "zaghlol",
                table: "accounts",
                columns: new[] { "provider", "provider_subject" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ux_app_attest_keys_install_id",
                schema: "zaghlol",
                table: "app_attest_keys",
                column: "install_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_audit_log_at",
                schema: "zaghlol",
                table: "audit_log",
                column: "at");

            migrationBuilder.CreateIndex(
                name: "ix_audit_log_support_at",
                schema: "zaghlol",
                table: "audit_log",
                column: "at",
                filter: "action IN ('support_lookup','support_seat_move','support_detach','support_unfreeze')");

            migrationBuilder.CreateIndex(
                name: "ix_bank_requests_received_at",
                schema: "zaghlol",
                table: "bank_requests",
                column: "received_at");

            migrationBuilder.CreateIndex(
                name: "ix_catalog_aliases_merchant_id",
                schema: "zaghlol",
                table: "catalog_aliases",
                column: "merchant_id");

            migrationBuilder.CreateIndex(
                name: "ix_catalog_categories_parent_code",
                schema: "zaghlol",
                table: "catalog_categories",
                column: "parent_code");

            migrationBuilder.CreateIndex(
                name: "ix_catalog_merchants_category_code",
                schema: "zaghlol",
                table: "catalog_merchants",
                column: "category_code");

            migrationBuilder.CreateIndex(
                name: "ux_catalog_merchants_canonical",
                schema: "zaghlol",
                table: "catalog_merchants",
                column: "canonical",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_idempotency_account",
                schema: "zaghlol",
                table: "idempotency_records",
                column: "account_id",
                filter: "account_id IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_idempotency_records_expires_at",
                schema: "zaghlol",
                table: "idempotency_records",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ix_installs_deleted_at",
                schema: "zaghlol",
                table: "installs",
                column: "deleted_at",
                filter: "deleted_at IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_installs_last_seen",
                schema: "zaghlol",
                table: "installs",
                column: "last_seen_at");

            migrationBuilder.CreateIndex(
                name: "ix_installs_registration_pending",
                schema: "zaghlol",
                table: "installs",
                column: "first_seen_at",
                filter: "registration_key_hash IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_merchant_contributions_received_at",
                schema: "zaghlol",
                table: "merchant_contributions",
                column: "received_at");

            migrationBuilder.CreateIndex(
                name: "ux_merchant_contributions_merchant_norm_institution_code_install_hash",
                schema: "zaghlol",
                table: "merchant_contributions",
                columns: new[] { "merchant_norm", "institution_code", "install_hash" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ux_operators_oidc_subject",
                schema: "zaghlol",
                table: "operators",
                column: "oidc_subject",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_purchase_events_purchase_id",
                schema: "zaghlol",
                table: "purchase_events",
                column: "purchase_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_seats_install",
                schema: "zaghlol",
                table: "purchase_seats",
                column: "install_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchases_account",
                schema: "zaghlol",
                table: "purchases",
                column: "account_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchases_install",
                schema: "zaghlol",
                table: "purchases",
                column: "install_id");

            migrationBuilder.CreateIndex(
                name: "ix_purchases_unacked",
                schema: "zaghlol",
                table: "purchases",
                column: "created_at",
                filter: "store = 'google_play' AND acknowledged = false");

            migrationBuilder.CreateIndex(
                name: "ux_purchases_store_store_key",
                schema: "zaghlol",
                table: "purchases",
                columns: new[] { "store", "store_key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_replay_guard_expires_at",
                schema: "zaghlol",
                table: "replay_guard",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ix_seat_claimants_claimed_at",
                schema: "zaghlol",
                table: "seat_claimants",
                column: "claimed_at");

            migrationBuilder.CreateIndex(
                name: "ix_seat_claimants_install_id",
                schema: "zaghlol",
                table: "seat_claimants",
                column: "install_id");

            migrationBuilder.CreateIndex(
                name: "ix_store_notifications_received_at",
                schema: "zaghlol",
                table: "store_notifications",
                column: "received_at");

            migrationBuilder.CreateIndex(
                name: "ux_store_notifications_store_external_id",
                schema: "zaghlol",
                table: "store_notifications",
                columns: new[] { "store", "external_id" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "account_installs",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "app_attest_keys",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "audit_log",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "bank_requests",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "catalog_aliases",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "catalog_keywords",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "catalog_versions",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "contribution_aggregates",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "daily_active_counts",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "feature_flags",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "fx_rates",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "idempotency_records",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "merchant_contributions",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "operators",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "price_quotes",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "purchase_events",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "purchase_seats",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "replay_guard",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "seat_claimants",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "store_notifications",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "catalog_merchants",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "purchases",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "catalog_categories",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "accounts",
                schema: "zaghlol");

            migrationBuilder.DropTable(
                name: "installs",
                schema: "zaghlol");
        }
    }
}
