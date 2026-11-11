using System.Text;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>Table privileges a group role may hold. DDL, TRUNCATE, REFERENCES and TRIGGER are never granted.</summary>
[Flags]
public enum TablePrivileges
{
    None = 0,
    Select = 1,
    Insert = 2,
    Update = 4,
    Delete = 8,
}

/// <summary>
/// One row of the grant matrix: table-level privileges, plus optional column-level SELECT or UPDATE lists for a role that
/// may read or write only some columns.
/// </summary>
public sealed record TableGrant(
    string Role,
    string Table,
    TablePrivileges Privileges,
    IReadOnlyList<string>? SelectColumns = null,
    IReadOnlyList<string>? UpdateColumns = null);

/// <summary>
/// Least-privilege grants of the four group roles (T-122 design note). The schema's privileges must equal
/// <see cref="Current"/> exactly; a Testcontainers test compares it with <c>pg_class.relacl</c> / <c>pg_attribute.attacl</c>.
/// </summary>
/// <remarks>
/// <list type="bullet">
/// <item>Only <c>migrator</c> (the owner) has DDL, TRUNCATE, REFERENCES or TRIGGER.</item>
/// <item><c>audit_log</c>: INSERT for <c>ops_rw</c> only, DELETE for <c>worker_rw</c> only and, through row-level
/// security, only for rows past their retention age; UPDATE for nobody.</item>
/// <item><c>app_rw</c> (<c>/v1/*</c>): install, purchase, sync, account and notification-ingest writes only; no catalog,
/// flag, price, operator, counter or audit writes, no dispute-freeze writes, and no reading of other installs'
/// contributions.</item>
/// <item><c>ops_rw</c> (<c>/admin/v1/*</c>): catalog, flags, price overrides, contribution review, the support-correction
/// columns of purchases and seats, claimant removal, purchase_events and audit_log inserts.</item>
/// <item><c>worker_rw</c>: notification processing, sweeps, aggregation, price fetching, daily counters and retention
/// deletes; UPDATE on <c>installs</c> and <c>purchases</c> is column-level.</item>
/// <item><c>ops_ro</c>: SELECT, except <c>installs.token_hash</c>, <c>accounts.email</c>, <c>accounts.provider_subject</c>,
/// <c>accounts.apple_refresh_token_enc</c>, <c>purchases.store_key</c>, <c>purchases.linked_purchase_token</c>,
/// <c>store_notifications.store_key</c> and <c>idempotency_records.response_body_enc</c>. The T-130 column
/// <c>idempotency_records.claim_id</c> (a 60 s request lease) and <c>purchases.ack_next_attempt_at</c> (the sweeper's deferral
/// stamp), the T-131 column <c>purchases.last_payment_at</c> (verify's new-payment marker, <c>app_rw</c> UPDATE only) and the T-134
/// column <c>store_notifications.next_attempt_at</c> (the processor's back-off) were added without an <c>ops_ro</c> grant.</item>
/// </list>
/// A later migration that adds a table or a grant adds a frozen list here (like <see cref="InitialCreate"/>), renders it
/// with <see cref="ToSql"/> in that migration, and appends it to <see cref="Current"/> (merged per role and table). A migration never renders
/// <see cref="Current"/>, so old migrations don't change.
/// </remarks>
public static class GrantMatrix
{
    public const string AppRw = "app_rw";
    public const string WorkerRw = "worker_rw";
    public const string OpsRo = "ops_ro";
    public const string OpsRw = "ops_rw";

    public static IReadOnlyList<string> GroupRoles { get; } = [AppRw, WorkerRw, OpsRo, OpsRw];

    private const TablePrivileges S = TablePrivileges.Select;
    private const TablePrivileges SI = TablePrivileges.Select | TablePrivileges.Insert;
    private const TablePrivileges SU = TablePrivileges.Select | TablePrivileges.Update;
    private const TablePrivileges SD = TablePrivileges.Select | TablePrivileges.Delete;
    private const TablePrivileges SIU = SI | TablePrivileges.Update;
    private const TablePrivileges SID = SI | TablePrivileges.Delete;
    private const TablePrivileges SUD = SU | TablePrivileges.Delete;
    private const TablePrivileges SIUD = SIU | TablePrivileges.Delete;

    private const TablePrivileges I = TablePrivileges.Insert;

    // Column lists used by the InitialCreate grants. Frozen with that migration (a golden test pins the rendered SQL):
    // a later migration declares its own lists instead of editing these.
    private static readonly string[] InstallsReadable =
    [
        "id", "platform", "app_version", "catalog_version", "first_seen_at", "last_seen_at", "deleted_at",
        "registration_key_hash", "registration_body_sha256", "seat_key_hash", "seat_key_trusted",
    ];

    // ops_rw needs the e-mail and subject for the audited support lookup (backend-api section 5.2).
    private static readonly string[] AccountsAdminReadable =
        ["id", "provider", "provider_subject", "email", "created_at", "last_sign_in_at"];

    // ops_ro (a direct DB login) never sees personal identifiers or bearer-like store tokens (SEC F1).
    private static readonly string[] AccountsReadOnly = ["id", "provider", "created_at", "last_sign_in_at"];

    private static readonly string[] PurchasesReadOnly =
    [
        "id", "store", "product_id", "plan", "install_id", "account_id", "account_linked_by", "attach_reclaim_used_at",
        "dispute_frozen_until", "support_link_notice_pending", "support_link_notice_iat", "state", "expires_at",
        "acknowledged", "environment", "obfuscated_install_ref", "last_verified_at", "created_at",
    ];

    private static readonly string[] StoreNotificationsReadOnly =
    [
        "id", "store", "external_id", "type", "subtype", "product_id", "environment", "event_time", "received_at",
        "processed_at", "attempts", "last_error", "payload_digest",
    ];

    private static readonly string[] IdempotencyReadable =
        ["install_id", "operation_id", "idempotency_key", "body_sha256", "status", "account_id", "expires_at"];

    // /v1 writes every purchase column except the key, the creation time and the support-only dispute freeze (D-64).
    private static readonly string[] PurchasesAppUpdatable =
    [
        "store", "product_id", "plan", "store_key", "linked_purchase_token", "install_id", "account_id", "account_linked_by",
        "attach_reclaim_used_at", "support_link_notice_pending", "support_link_notice_iat", "state", "expires_at",
        "acknowledged", "environment", "obfuscated_install_ref", "last_verified_at",
    ];

    // Support corrections (backend-api section 5.3): link/detach, the free reclaim marker, the dispute freeze and the notice.
    private static readonly string[] PurchasesSupportColumns =
    [
        "account_id", "account_linked_by", "attach_reclaim_used_at", "dispute_frozen_until", "support_link_notice_pending",
        "support_link_notice_iat",
    ];

    // Support seat moves: the holder and its proof, the move times and the target's device key (never recent_rebinds).
    private static readonly string[] SeatsSupportColumns =
        ["install_id", "proof", "bound_at", "last_moved_at", "next_move_at", "device_key_hash", "device_key_trusted"];

    // Worker: the 24 h registration purge and the tombstone (clears seat_key_hash); never token_hash or seat_key_trusted.
    private static readonly string[] InstallsWorkerUpdatable =
        ["registration_key_hash", "registration_body_sha256", "seat_key_hash", "deleted_at"];

    // Worker: notification processing and the acknowledgement sweep; never the account link.
    private static readonly string[] PurchasesWorkerUpdatable =
        ["state", "expires_at", "acknowledged", "last_verified_at", "linked_purchase_token"];

    // EF reads back the now() default with RETURNING; nothing else of other installs' rows is readable.
    private static readonly string[] ReceivedAtOnly = ["received_at"];

    /// <summary>The grants of the InitialCreate migration. Frozen: never edit after it ships.</summary>
    public static IReadOnlyList<TableGrant> InitialCreate { get; } =
    [
        // app_rw: /v1/* (install, purchase, sync, account, notification ingest).
        new(AppRw, "installs", SIU),
        new(AppRw, "accounts", SIUD),
        new(AppRw, "account_installs", SIUD),
        new(AppRw, "purchases", SI, UpdateColumns: PurchasesAppUpdatable),
        new(AppRw, "purchase_events", SI),
        new(AppRw, "purchase_seats", SIU),
        new(AppRw, "seat_claimants", SIUD),
        new(AppRw, "app_attest_keys", SIUD),
        new(AppRw, "v_entitlements", S),
        new(AppRw, "replay_guard", SI),
        new(AppRw, "idempotency_records", SID),
        new(AppRw, "store_notifications", SI),
        new(AppRw, "catalog_versions", S),
        new(AppRw, "catalog_categories", S),
        new(AppRw, "catalog_merchants", S),
        new(AppRw, "catalog_aliases", S),
        new(AppRw, "catalog_keywords", S),
        new(AppRw, "feature_flags", S),
        new(AppRw, "price_quotes", S),
        new(AppRw, "fx_rates", S),
        new(AppRw, "merchant_contributions", I, SelectColumns: ReceivedAtOnly),
        new(AppRw, "bank_requests", I, SelectColumns: ReceivedAtOnly),

        // worker_rw: notification processor, sweeper, aggregator, price fetcher, RetentionPurger, daily counters.
        new(WorkerRw, "installs", SD, UpdateColumns: InstallsWorkerUpdatable),
        new(WorkerRw, "purchases", S, UpdateColumns: PurchasesWorkerUpdatable),
        new(WorkerRw, "purchase_events", SI),
        new(WorkerRw, "purchase_seats", S),
        new(WorkerRw, "seat_claimants", SD),
        new(WorkerRw, "replay_guard", SD),
        new(WorkerRw, "idempotency_records", SD),
        new(WorkerRw, "store_notifications", SUD),
        new(WorkerRw, "price_quotes", SIU),
        new(WorkerRw, "fx_rates", SIU),
        new(WorkerRw, "merchant_contributions", SD),
        new(WorkerRw, "contribution_aggregates", SIU),
        new(WorkerRw, "bank_requests", SD),
        new(WorkerRw, "daily_active_counts", SIUD),
        new(WorkerRw, "audit_log", SD), // DELETE is further limited to rows past retention by RLS

        // ops_ro: read-only operators. No e-mail, provider subject, store keys, tokens or stored responses.
        new(OpsRo, "installs", TablePrivileges.None, SelectColumns: InstallsReadable),
        new(OpsRo, "accounts", TablePrivileges.None, SelectColumns: AccountsReadOnly),
        new(OpsRo, "account_installs", S),
        new(OpsRo, "purchases", TablePrivileges.None, SelectColumns: PurchasesReadOnly),
        new(OpsRo, "purchase_events", S),
        new(OpsRo, "purchase_seats", S),
        new(OpsRo, "seat_claimants", S),
        new(OpsRo, "app_attest_keys", S),
        new(OpsRo, "v_entitlements", S),
        new(OpsRo, "replay_guard", S),
        new(OpsRo, "idempotency_records", TablePrivileges.None, SelectColumns: IdempotencyReadable),
        new(OpsRo, "store_notifications", TablePrivileges.None, SelectColumns: StoreNotificationsReadOnly),
        new(OpsRo, "catalog_versions", S),
        new(OpsRo, "catalog_categories", S),
        new(OpsRo, "catalog_merchants", S),
        new(OpsRo, "catalog_aliases", S),
        new(OpsRo, "catalog_keywords", S),
        new(OpsRo, "feature_flags", S),
        new(OpsRo, "price_quotes", S),
        new(OpsRo, "fx_rates", S),
        new(OpsRo, "merchant_contributions", S),
        new(OpsRo, "contribution_aggregates", S),
        new(OpsRo, "bank_requests", S),
        new(OpsRo, "daily_active_counts", S),
        new(OpsRo, "operators", S),
        new(OpsRo, "audit_log", S),

        // ops_rw: /admin/v1/* (every call audited). Reads what support needs, plus the writes below.
        new(OpsRw, "installs", TablePrivileges.None, SelectColumns: InstallsReadable),
        new(OpsRw, "accounts", TablePrivileges.None, SelectColumns: AccountsAdminReadable),
        new(OpsRw, "account_installs", S),
        new(OpsRw, "purchases", S, UpdateColumns: PurchasesSupportColumns),
        new(OpsRw, "purchase_events", SI),
        new(OpsRw, "purchase_seats", S, UpdateColumns: SeatsSupportColumns),
        new(OpsRw, "seat_claimants", SD),
        new(OpsRw, "app_attest_keys", S),
        new(OpsRw, "v_entitlements", S),
        new(OpsRw, "store_notifications", S),
        new(OpsRw, "catalog_versions", SIU),
        new(OpsRw, "catalog_categories", SIU),
        new(OpsRw, "catalog_merchants", SIU),
        new(OpsRw, "catalog_aliases", SIU),
        new(OpsRw, "catalog_keywords", SIU),
        new(OpsRw, "feature_flags", SIU),
        new(OpsRw, "price_quotes", SIU),
        new(OpsRw, "fx_rates", S),
        new(OpsRw, "merchant_contributions", S),
        new(OpsRw, "contribution_aggregates", SU),
        new(OpsRw, "bank_requests", S),
        new(OpsRw, "daily_active_counts", S),
        new(OpsRw, "operators", S),
        new(OpsRw, "audit_log", SI), // INSERT only; RLS has no UPDATE or DELETE policy for ops_rw
    ];

    /// <summary>The grants of the AddCatalogDrafts migration (T-125). Frozen: never edit after it ships.</summary>
    public static IReadOnlyList<TableGrant> CatalogDrafts { get; } =
    [
        new(OpsRw, "catalog_drafts", SIUD), // the operator draft workspace (backend-api section 5.2)
        new(OpsRo, "catalog_drafts", S),
    ];

    /// <summary>
    /// The grants of the PurchaseAckNextAttempt migration (T-130 security M-1). Frozen: never edit after it ships. Only the sweeper
    /// writes the deferral stamp (like <c>idempotency_records.claim_id</c>, the new column has no <c>ops_ro</c> grant).
    /// </summary>
    public static IReadOnlyList<TableGrant> PurchaseAckNextAttempt { get; } =
    [
        new(WorkerRw, "purchases", TablePrivileges.None, UpdateColumns: ["ack_next_attempt_at"]),
    ];

    /// <summary>
    /// The grants of the PurchaseLastPaymentAt migration (T-131 design note §4). Frozen: never edit after it ships. Only verify (the
    /// App login) advances the new-payment marker; the worker gets nothing, so a store notification can never swallow a new
    /// payment, and like the other T-130/T-131 columns it has no <c>ops_ro</c> grant.
    /// </summary>
    public static IReadOnlyList<TableGrant> PurchaseLastPaymentAt { get; } =
    [
        new(AppRw, "purchases", TablePrivileges.None, UpdateColumns: ["last_payment_at"]),
    ];

    /// <summary>
    /// The grants of the AppleNotifications migration (T-134 design note §5, FU-092 item 1). Frozen: never edit after it ships. The
    /// worker may re-plan an App Store row (an upgrade notification changes the product, as verify does) and insert notifications
    /// (the <c>Get Notification History</c> job). It still never updates <c>environment</c>, <c>obfuscated_install_ref</c>,
    /// <c>install_id</c> or <c>last_payment_at</c>, and keeps only SELECT on <c>purchase_seats</c>, so a notification can't move a
    /// seat. The new <c>store_notifications.next_attempt_at</c> has no <c>ops_ro</c> grant (like <c>purchases.ack_next_attempt_at</c>).
    /// </summary>
    public static IReadOnlyList<TableGrant> AppleNotifications { get; } =
    [
        new(WorkerRw, "purchases", TablePrivileges.None, UpdateColumns: ["product_id", "plan"]),
        new(WorkerRw, "store_notifications", I),
    ];

    /// <summary>What the database must hold after all migrations: one merged row per role and table.</summary>
    public static IReadOnlyList<TableGrant> Current { get; } =
        Merge([.. InitialCreate, .. CatalogDrafts, .. PurchaseAckNextAttempt, .. PurchaseLastPaymentAt, .. AppleNotifications]);

    /// <summary>
    /// Folds the grants of several migrations into one row per role and table (privileges and column lists united, in order),
    /// so a later migration may add a column grant to a table an earlier one already granted.
    /// </summary>
    public static IReadOnlyList<TableGrant> Merge(IEnumerable<TableGrant> grants)
    {
        ArgumentNullException.ThrowIfNull(grants);

        var merged = new List<TableGrant>();
        foreach (var grant in grants)
        {
            var at = merged.FindIndex(g => g.Role == grant.Role && g.Table == grant.Table);
            if (at < 0)
            {
                merged.Add(grant);
                continue;
            }

            var existing = merged[at];
            merged[at] = existing with
            {
                Privileges = existing.Privileges | grant.Privileges,
                SelectColumns = Union(existing.SelectColumns, grant.SelectColumns),
                UpdateColumns = Union(existing.UpdateColumns, grant.UpdateColumns),
            };
        }

        return merged;
    }

    /// <summary>Renders grants as SQL statements (schema-qualified, deterministic order).</summary>
    public static string ToSql(IEnumerable<TableGrant> grants)
    {
        ArgumentNullException.ThrowIfNull(grants);

        var sql = new StringBuilder();
        foreach (var grant in grants)
        {
            var target = $"{ZaghlolDbContext.Schema}.{grant.Table}";
            var privileges = PrivilegeNames(grant.Privileges);
            if (privileges.Count > 0)
            {
                sql.Append("GRANT ").Append(string.Join(", ", privileges)).Append(" ON ").Append(target)
                    .Append(" TO ").Append(grant.Role).Append(";\n");
            }

            if (grant.SelectColumns is { Count: > 0 } selectColumns)
            {
                sql.Append("GRANT SELECT (").Append(string.Join(", ", selectColumns)).Append(") ON ").Append(target)
                    .Append(" TO ").Append(grant.Role).Append(";\n");
            }

            if (grant.UpdateColumns is { Count: > 0 } updateColumns)
            {
                sql.Append("GRANT UPDATE (").Append(string.Join(", ", updateColumns)).Append(") ON ").Append(target)
                    .Append(" TO ").Append(grant.Role).Append(";\n");
            }
        }

        return sql.ToString();
    }

    /// <summary>Flattens grants to <c>role|table|PRIVILEGE</c> (table level) and <c>role|table.column|PRIVILEGE</c>.</summary>
    public static ISet<string> Flatten(IEnumerable<TableGrant> grants)
    {
        ArgumentNullException.ThrowIfNull(grants);

        var result = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var grant in grants)
        {
            foreach (var privilege in PrivilegeNames(grant.Privileges))
            {
                result.Add($"{grant.Role}|{grant.Table}|{privilege}");
            }

            foreach (var column in grant.SelectColumns ?? [])
            {
                result.Add($"{grant.Role}|{grant.Table}.{column}|SELECT");
            }

            foreach (var column in grant.UpdateColumns ?? [])
            {
                result.Add($"{grant.Role}|{grant.Table}.{column}|UPDATE");
            }
        }

        return result;
    }


    private static IReadOnlyList<string>? Union(IReadOnlyList<string>? first, IReadOnlyList<string>? second) =>
        first is null ? second : second is null ? first : [.. first.Concat(second).Distinct(StringComparer.Ordinal)];

    private static List<string> PrivilegeNames(TablePrivileges privileges)
    {
        var names = new List<string>(4);
        if (privileges.HasFlag(TablePrivileges.Select))
        {
            names.Add("SELECT");
        }

        if (privileges.HasFlag(TablePrivileges.Insert))
        {
            names.Add("INSERT");
        }

        if (privileges.HasFlag(TablePrivileges.Update))
        {
            names.Add("UPDATE");
        }

        if (privileges.HasFlag(TablePrivileges.Delete))
        {
            names.Add("DELETE");
        }

        return names;
    }
}
