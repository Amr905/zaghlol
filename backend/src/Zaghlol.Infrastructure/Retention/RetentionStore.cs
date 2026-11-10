using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Retention;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Retention;

/// <summary>
/// The RetentionPurger's SQL on the Worker login (backend-schema.md section 4). Raw SQL only: deleting through EF's tracked graph
/// would client-side SetNull the purchase links without their paired column (FU-015). Every statement is bounded by a batch size
/// (<c>ctid</c> subselect) so a large backlog never holds a long lock. Ages are computed in SQL from <c>@now</c> with calendar
/// intervals, the same arithmetic as the <c>audit_log</c> row-level-security policy, which still applies on top (a bug here can't
/// erase an audit row before its age).
/// </summary>
internal sealed class RetentionStore(IZaghlolDbContextFactory contexts) : IRetentionStore
{
    private static readonly string SupportActions = string.Join(",", RetentionAuditActions.OneYear.Select(a => $"'{a}'"));

    private static readonly Dictionary<string, string> Statements = new(StringComparer.Ordinal)
    {
        // Installs first-seen > 24 h ago whose registration retry columns were never cleared by an authenticated call.
        [RetentionRules.RegistrationColumns] = """
            UPDATE zaghlol.installs SET registration_key_hash = NULL, registration_body_sha256 = NULL
            WHERE ctid IN (SELECT ctid FROM zaghlol.installs
                           WHERE registration_key_hash IS NOT NULL AND first_seen_at < @now - interval '24 hours'
                           LIMIT @batch)
            """,

        // A delete vacates the install's seats (trigger, keeps device_key_hash) and nulls purchases.install_id (FK); the
        // idempotency rows have no FK, so they go in the same statement.
        [RetentionRules.TombstonedInstalls] = InstallDelete("deleted_at IS NOT NULL AND deleted_at < @now - interval '30 days'"),
        [RetentionRules.InactiveInstalls] = InstallDelete("last_seen_at < @now - interval '12 months'"),

        [RetentionRules.StoreNotifications] = Delete("store_notifications", "received_at < @now - interval '90 days'"),

        // Raw rows go when their aggregate is promoted or rejected, or after 180 days.
        [RetentionRules.Contributions] = Delete(
            "merchant_contributions",
            """
            received_at < @now - interval '180 days'
            OR EXISTS (SELECT 1 FROM zaghlol.contribution_aggregates a
                       WHERE a.merchant_norm = merchant_contributions.merchant_norm
                         AND a.institution_code = merchant_contributions.institution_code
                         AND a.status IN ('promoted', 'rejected'))
            """),
        [RetentionRules.BankRequests] = Delete("bank_requests", "received_at < @now - interval '24 months'"),

        // D-47: support rows exactly 1 year after creation; all other operator actions 3 years.
        [RetentionRules.AuditSupport] = Delete("audit_log", $"action IN ({SupportActions}) AND at < @now - interval '1 year'"),
        [RetentionRules.AuditOther] = Delete("audit_log", $"action NOT IN ({SupportActions}) AND at < @now - interval '3 years'"),

        [RetentionRules.ReplayGuard] = Delete("replay_guard", "expires_at < @now"),
        [RetentionRules.SeatClaimants] = Delete("seat_claimants", "claimed_at < @now - interval '7 days'"),
        [RetentionRules.IdempotencyRecords] = Delete("idempotency_records", "expires_at < @now"),
    };

    public async Task<int> PurgeBatchAsync(string rule, DateTimeOffset now, int batchSize, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(rule);
        ArgumentOutOfRangeException.ThrowIfLessThan(batchSize, 1);
        if (!Statements.TryGetValue(rule, out var sql))
        {
            throw new ArgumentOutOfRangeException(nameof(rule), "Unknown retention rule.");
        }

        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
#pragma warning disable CA2100 // The text comes from the fixed Statements table above, never from input; only @now and @batch vary.
        await using var command = new NpgsqlCommand(sql, connection);
#pragma warning restore CA2100
        command.Parameters.Add(new NpgsqlParameter("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        command.Parameters.Add(new NpgsqlParameter("batch", NpgsqlDbType.Integer) { Value = batchSize });

        // The install rules select the number of installs removed (their statement also deletes idempotency rows).
        return rule is RetentionRules.TombstonedInstalls or RetentionRules.InactiveInstalls
            ? Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken), System.Globalization.CultureInfo.InvariantCulture)
            : await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string Delete(string table, string condition) => $"""
        DELETE FROM zaghlol.{table}
        WHERE ctid IN (SELECT ctid FROM zaghlol.{table} WHERE ({condition}) LIMIT @batch)
        """;

    private static string InstallDelete(string condition) => $"""
        WITH gone AS (
          DELETE FROM zaghlol.installs
          WHERE ctid IN (SELECT ctid FROM zaghlol.installs WHERE ({condition}) LIMIT @batch)
          RETURNING id),
        idem AS (
          DELETE FROM zaghlol.idempotency_records WHERE install_id IN (SELECT id FROM gone) RETURNING 1)
        SELECT count(*)::int FROM gone
        """;
}
