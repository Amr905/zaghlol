using System.Data;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Seats;

namespace Zaghlol.Infrastructure.Support;

/// <summary>
/// The support write path on the Admin login (<c>ops_rw</c>, T-186). One READ COMMITTED transaction per phase; the seat tables go
/// through <see cref="NpgsqlSeatStore"/> in the same transaction so the T-184 primitive and the link, freeze and audit writes
/// commit or roll back together. Only the grants that already exist are used: <c>purchases</c> UPDATE on the support columns,
/// <c>purchase_seats</c> UPDATE on the support columns, <c>seat_claimants</c> DELETE, <c>purchase_events</c> and <c>audit_log</c> INSERT.
/// </summary>
internal sealed class SupportActionStore(IServiceProvider services, IAuditWriter audit) : ISupportActionStore
{
    public async Task<ISupportActionTransaction> BeginAsync(CancellationToken cancellationToken)
    {
        var source = services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.Admin);
        var connection = await source.OpenConnectionAsync(cancellationToken);
        try
        {
            var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
            return new Transaction(connection, transaction, audit);
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private sealed class Transaction(NpgsqlConnection connection, NpgsqlTransaction transaction, IAuditWriter audit) : ISupportActionTransaction
    {
        private const string PurchaseSql = """
            SELECT p.store, p.product_id, p.store_key, p.linked_purchase_token, p.environment, p.account_linked_by, p.dispute_frozen_until,
                   (p.install_id IS NULL OR NOT EXISTS (SELECT 1 FROM zaghlol.installs i
                                                         WHERE i.id = p.install_id AND i.deleted_at IS NULL AND i.last_seen_at > @silent_cutoff))
            FROM zaghlol.purchases p WHERE p.id = @id
            """;

        private const string AuditColumns = """
            SELECT id, operator_id, action, at, details->>'reason_code', details->>'outcome', details->>'from_install',
                   details->>'attached_account_id', details->>'corrects_audit_id'
            FROM zaghlol.audit_log
            """;

        private const string AuditByIdSql = AuditColumns + """

            WHERE id = @id AND target = @target AND action IN ('support_seat_move', 'support_detach', 'support_unfreeze')
            """;

        // The newest successful correction starts the freeze: a correcting move or a detach.
        private const string FreezeStartSql = AuditColumns + """

            WHERE target = @target
              AND ((action = 'support_seat_move' AND details->>'reason_code' = 'correction'
                    AND details->>'outcome' IN ('moved', 'moved_and_attached'))
                   OR (action = 'support_detach' AND details->>'outcome' = 'detached'))
            ORDER BY id DESC LIMIT 1
            """;

        private const string UnfreezeSql = AuditColumns + """

            WHERE target = @target AND action = 'support_unfreeze' AND details->>'outcome' = 'unfrozen'
            ORDER BY id DESC LIMIT 1
            """;

        private const string CountsSql = """
            SELECT
              (SELECT count(*) FROM zaghlol.audit_log
               WHERE target = @target AND action = 'support_seat_move' AND at > now() - interval '90 days'
                 AND details->>'outcome' IN ('moved', 'moved_and_attached')),
              (SELECT count(*) FROM zaghlol.audit_log
               WHERE operator_id = @operator AND action IN ('support_seat_move', 'support_detach', 'support_unfreeze')
                 AND at > now() - interval '1 day'),
              (SELECT count(*) FROM zaghlol.audit_log
               WHERE operator_id = @operator AND action IN ('support_seat_move', 'support_detach', 'support_unfreeze')
                 AND at > now() - interval '1 day' AND details->>'ownership_outcome' = 'fail')
            """;

        private readonly NpgsqlSeatStore seatStore = new(connection, transaction);

        public ISeatStore Seats => seatStore;

        public async Task<SupportPurchase?> LockPurchaseAsync(Guid purchaseId, DateTimeOffset now, CancellationToken cancellationToken)
        {
            // Purchase row, then seat row, both FOR UPDATE (the T-184 lock order).
            if (await seatStore.LockAsync(purchaseId, cancellationToken) is not { } seat)
            {
                return null;
            }

            await using var command = Command(PurchaseSql);
            command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
            command.Parameters.Add(new("silent_cutoff", NpgsqlDbType.TimestampTz) { Value = (now - SupportEntitlementBuilder.ThirtyDays).ToUniversalTime() });
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            return new SupportPurchase(
                seat,
                reader.GetString(0) switch
                {
                    "google_play" => SupportStore.GooglePlay,
                    "app_store" => SupportStore.AppStore,
                    _ => throw new InvalidOperationException("Unknown purchases.store value."),
                },
                reader.GetString(1),
                new Sensitive<string>(reader.GetString(2)),
                reader.IsDBNull(3) ? null : new Sensitive<string>(reader.GetString(3)),
                reader.GetString(4) == "sandbox" ? PurchaseEnvironment.Sandbox : PurchaseEnvironment.Production,
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6),
                reader.GetBoolean(7));
        }

        public Task<SupportAuditRow?> ReadAuditAsync(Guid purchaseId, long auditId, CancellationToken cancellationToken) =>
            ReadAuditRowAsync(AuditByIdSql, purchaseId, auditId, cancellationToken);

        public Task<SupportAuditRow?> NewestFreezeStartAsync(Guid purchaseId, CancellationToken cancellationToken) =>
            ReadAuditRowAsync(FreezeStartSql, purchaseId, null, cancellationToken);

        public Task<SupportAuditRow?> NewestUnfreezeAsync(Guid purchaseId, CancellationToken cancellationToken) =>
            ReadAuditRowAsync(UnfreezeSql, purchaseId, null, cancellationToken);

        public async Task<bool> InstallLiveAsync(Guid installId, CancellationToken cancellationToken)
        {
            await using var command = Command("SELECT EXISTS (SELECT 1 FROM zaghlol.installs WHERE id = @id AND deleted_at IS NULL)");
            command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
            return await command.ExecuteScalarAsync(cancellationToken) is true;
        }

        public async Task<Guid?> AccountOfInstallAsync(Guid installId, CancellationToken cancellationToken)
        {
            await using var command = Command("SELECT account_id FROM zaghlol.account_installs WHERE install_id = @id ORDER BY account_id LIMIT 1");
            command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
            return await command.ExecuteScalarAsync(cancellationToken) is Guid account ? account : null;
        }

        public Task LinkAccountBySupportAsync(Guid purchaseId, Guid accountId, CancellationToken cancellationToken) =>
            ExecuteAsync(
                """
                UPDATE zaghlol.purchases
                SET account_id = @account, account_linked_by = 'support', support_link_notice_pending = true, support_link_notice_iat = NULL
                WHERE id = @id AND account_id IS NULL
                """,
                purchaseId,
                cancellationToken,
                new NpgsqlParameter("account", NpgsqlDbType.Uuid) { Value = accountId });

        public Task UnlinkAccountAsync(Guid purchaseId, CancellationToken cancellationToken) =>
            ExecuteAsync(
                """
                UPDATE zaghlol.purchases
                SET account_id = NULL, account_linked_by = NULL, support_link_notice_pending = false, support_link_notice_iat = NULL
                WHERE id = @id
                """,
                purchaseId,
                cancellationToken);

        public Task SetDisputeFreezeAsync(Guid purchaseId, DateTimeOffset? until, CancellationToken cancellationToken) =>
            ExecuteAsync(
                "UPDATE zaghlol.purchases SET dispute_frozen_until = @until WHERE id = @id",
                purchaseId,
                cancellationToken,
                new NpgsqlParameter("until", NpgsqlDbType.TimestampTz) { Value = until is { } value ? value.ToUniversalTime() : DBNull.Value });

        public Task<long> WriteAuditAsync(Guid operatorId, AuditEntry entry, CancellationToken cancellationToken) =>
            audit.WriteAsync(connection, transaction, operatorId, entry, cancellationToken);

        public async Task<SupportAuditCounts> CountsAsync(Guid operatorId, Guid purchaseId, CancellationToken cancellationToken)
        {
            await using var command = Command(CountsSql);
            command.Parameters.Add(new("target", NpgsqlDbType.Text) { Value = purchaseId.ToString("D") });
            command.Parameters.Add(new("operator", NpgsqlDbType.Uuid) { Value = operatorId });
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            return new SupportAuditCounts(reader.GetInt64(0), reader.GetInt64(1), reader.GetInt64(2));
        }

        public Task CommitAsync(CancellationToken cancellationToken) => transaction.CommitAsync(cancellationToken);

        public async ValueTask DisposeAsync()
        {
            await transaction.DisposeAsync();
            await connection.DisposeAsync();
        }

        private async Task<SupportAuditRow?> ReadAuditRowAsync(string sql, Guid purchaseId, long? auditId, CancellationToken cancellationToken)
        {
            await using var command = Command(sql);
            command.Parameters.Add(new("target", NpgsqlDbType.Text) { Value = purchaseId.ToString("D") });
            if (auditId is { } id)
            {
                command.Parameters.Add(new("id", NpgsqlDbType.Bigint) { Value = id });
            }

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            return new SupportAuditRow(
                reader.GetInt64(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetFieldValue<DateTimeOffset>(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                ParseGuid(reader, 6),
                ParseGuid(reader, 7),
                reader.IsDBNull(8) ? null : long.Parse(reader.GetString(8), System.Globalization.CultureInfo.InvariantCulture));
        }

        private static Guid? ParseGuid(NpgsqlDataReader reader, int ordinal) =>
            reader.IsDBNull(ordinal) ? null : Guid.Parse(reader.GetString(ordinal));

        private async Task ExecuteAsync(string sql, Guid purchaseId, CancellationToken cancellationToken, params NpgsqlParameter[] extra)
        {
            await using var command = Command(sql);
            command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
            foreach (var parameter in extra)
            {
                command.Parameters.Add(parameter);
            }

            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        private NpgsqlCommand Command(string sql) => new(sql, connection, transaction);
    }
}

/// <summary>The support alerts (purchase and operator UUIDs only) through the shared alert signal.</summary>
internal sealed class SupportAlerts(IAlertSignal alerts) : ISupportAlerts
{
    public void DisputeFrozen(Guid purchaseId) => alerts.Raise(AuditAlertRule.DisputeFrozenRefusal, purchaseId);

    public void Unfreeze(Guid purchaseId) => alerts.Raise(AuditAlertRule.SupportUnfreeze, purchaseId);

    public void MovesPerPurchase(Guid purchaseId) => alerts.Raise(AuditAlertRule.SupportMovesPerPurchase90d, purchaseId);

    public void ActionsPerOperator(Guid operatorId) => alerts.Raise(AuditAlertRule.SupportActionsPerOperatorDay, operatorId: operatorId);

    public void OwnershipFailuresPerOperator(Guid operatorId) => alerts.Raise(AuditAlertRule.OwnershipFailuresPerOperatorDay, operatorId: operatorId);
}
