using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>
/// The RTDN worker's rows on the Worker login (T-133 design note §2-§4). No transaction is held across a Play call: the pick is a plain
/// read and each write is one short transaction. The purchase write is the Google worker statement: <c>state</c>, <c>expires_at</c>
/// and <c>last_verified_at</c> only, with <c>store = 'google_play'</c> in its <c>WHERE</c> and under the monotonic guard, after the
/// label rule (<see cref="PlayStateMapping.Settle"/>) under the row lock. <c>worker_rw</c> has no grant on anything verify-only, none on
/// <c>purchase_seats</c> beyond SELECT, and can't insert purchases.
/// </summary>
internal sealed class PlayNotificationStore(IZaghlolDbContextFactory contexts) : IPlayNotificationStore
{
    private const string ListDueSql = """
        SELECT id, external_id, type, subtype, store_key, environment, attempts, received_at
        FROM zaghlol.store_notifications
        WHERE store = 'google_play' AND processed_at IS NULL AND (next_attempt_at IS NULL OR next_attempt_at <= @now)
        ORDER BY next_attempt_at NULLS FIRST, received_at
        LIMIT @limit
        """;

    private const string FindSql = """
        SELECT id, store_key, product_id, environment, state
        FROM zaghlol.purchases WHERE store = 'google_play' AND store_key = @key
        """;

    private const string LockSql = "SELECT state, last_verified_at FROM zaghlol.purchases WHERE id = @id AND store = 'google_play' FOR UPDATE";

    // The Google worker statement (T-133 §2): never product_id, plan, install_id, obfuscated_install_ref, environment,
    // acknowledged or last_payment_at.
    private const string UpdateSql = """
        UPDATE zaghlol.purchases
        SET state = @state, expires_at = CASE WHEN @keep_expires THEN expires_at ELSE @expires END, last_verified_at = @read_at
        WHERE id = @id AND store = 'google_play' AND last_verified_at < @read_at
        """;

    private const string CompleteSql = """
        UPDATE zaghlol.store_notifications SET processed_at = now(), last_error = @error
        WHERE id = @id AND processed_at IS NULL
        """;

    private const string FailSql = """
        UPDATE zaghlol.store_notifications
        SET attempts = @attempts, last_error = @error, next_attempt_at = @next,
            processed_at = CASE WHEN @dead THEN now() ELSE NULL END
        WHERE id = @id AND processed_at IS NULL
        """;

    private const string DeferSql = "UPDATE zaghlol.store_notifications SET next_attempt_at = @next WHERE id = @id AND processed_at IS NULL";

    private const string BacklogSql = """
        SELECT count(*) FILTER (WHERE received_at > @cutoff), count(*) FILTER (WHERE received_at <= @cutoff)
        FROM zaghlol.store_notifications
        WHERE store = 'google_play' AND processed_at IS NULL
        """;

    // FU-098 code 3: a purchase whose sweep row for this expiry already exists (pending, done or dead-lettered) is skipped, so a stuck
    // row never blocks the rest; a renewal (new expires_at) gets a new key.
    private const string ExpiredSql = """
        SELECT p.id, p.store_key, p.expires_at
        FROM zaghlol.purchases p
        WHERE p.store = 'google_play' AND p.plan <> 'lifetime' AND p.state IN ('active', 'in_grace', 'canceled_active')
          AND p.expires_at BETWEEN @from AND @to AND p.last_verified_at < p.expires_at
          AND NOT EXISTS (
              SELECT 1 FROM zaghlol.store_notifications n
              WHERE n.store = 'google_play'
                AND n.external_id = 'sweep:' || p.id::text || ':' || floor(extract(epoch FROM p.expires_at))::bigint::text)
        ORDER BY p.expires_at
        LIMIT @limit
        """;

    private const string RtdnVoidedSql = """
        SELECT EXISTS (
            SELECT 1 FROM zaghlol.store_notifications
            WHERE store = 'google_play' AND type = 'VOIDED_PURCHASE' AND store_key = @key AND external_id NOT LIKE 'voided:%')
        """;

    public Task<IAsyncDisposable?> TryLockAsync(string name, CancellationToken cancellationToken) =>
        AdvisoryLock.TryTakeAsync(contexts, name, cancellationToken);

    public async Task<IReadOnlyList<DuePlayNotification>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, ListDueSql, cancellationToken);
        command.Parameters.AddWithValue("now", now.ToUniversalTime());
        command.Parameters.AddWithValue("limit", limit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<DuePlayNotification>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new DuePlayNotification(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.IsDBNull(4) ? null : new Sensitive<string>(reader.GetString(4)),
                reader.IsDBNull(5) ? null : ParseEnvironment(reader.GetString(5)),
                reader.GetInt32(6),
                reader.GetFieldValue<DateTimeOffset>(7)));
        }

        return rows;
    }

    public async Task<PlayPurchaseRow?> FindPurchaseAsync(Sensitive<string> storeKey, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, FindSql, cancellationToken);
        command.Parameters.AddWithValue("key", storeKey.Reveal() ?? string.Empty);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new PlayPurchaseRow(
            reader.GetGuid(0),
            new Sensitive<string>(reader.GetString(1)),
            reader.GetString(2),
            ParseEnvironment(reader.GetString(3)),
            PurchaseDbText.ParseState(reader.GetString(4)));
    }

    public async Task<PlayWriteResult> ApplyAsync(PlayStateWrite write, Guid notificationId, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(write);

        var readAt = write.ReadAt.ToUniversalTime();
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        StoredPurchaseState? current = null;
        DateTimeOffset lastVerifiedAt = default;
        await using (var lockRow = new NpgsqlCommand(LockSql, connection, transaction))
        {
            lockRow.Parameters.AddWithValue("id", write.PurchaseId);
            await using var reader = await lockRow.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                current = PurchaseDbText.ParseState(reader.GetString(0));
                lastVerifiedAt = reader.GetFieldValue<DateTimeOffset>(1);
            }
        }

        PlayWriteResult result;
        if (current is not { } stored)
        {
            result = PlayWriteResult.Gone;
        }
        else if (lastVerifiedAt >= readAt)
        {
            // A newer read (verify, the sweeper, another notification) is stored: keep it.
            result = PlayWriteResult.Superseded;
        }
        else if (write.OnlyFromPending && stored != StoredPurchaseState.Pending)
        {
            // SUBSCRIPTION_PENDING_PURCHASE_CANCELED for a row that is no longer pending: nothing to write.
            result = PlayWriteResult.Unchanged;
        }
        else
        {
            var state = PlayStateMapping.Settle(stored, write.Read, write.SettleType);
            var text = PurchaseDbText.State(state);
            await using (var update = new NpgsqlCommand(UpdateSql, connection, transaction))
            {
                update.Parameters.AddWithValue("id", write.PurchaseId);
                update.Parameters.AddWithValue("state", text);
                update.Parameters.AddWithValue("keep_expires", write.KeepStoredExpiry);
                update.Parameters.AddWithValue("expires", (object?)write.ExpiresAt?.ToUniversalTime() ?? DBNull.Value);
                update.Parameters.AddWithValue("read_at", readAt);
                if (await update.ExecuteNonQueryAsync(cancellationToken) != 1)
                {
                    throw new InvalidOperationException("The locked purchase row was not updated.");
                }
            }

            if (state == stored)
            {
                result = PlayWriteResult.Unchanged;
            }
            else
            {
                await PurchaseWriter.EventAsync(connection, transaction, write.PurchaseId, PurchaseDbText.State(stored), text, write.Cause, readAt, cancellationToken);
                result = PlayWriteResult.Applied;
            }
        }

        await using (var complete = new NpgsqlCommand(CompleteSql, connection, transaction))
        {
            complete.Parameters.AddWithValue("id", notificationId);
            complete.Parameters.AddWithValue("error", result == PlayWriteResult.Gone ? PlayNotificationSchedule.NoPurchase : (object)DBNull.Value);
            await complete.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    public async Task CompleteAsync(Guid notificationId, string? code, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, CompleteSql, cancellationToken);
        command.Parameters.AddWithValue("id", notificationId);
        command.Parameters.AddWithValue("error", (object?)code ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task FailAsync(Guid notificationId, int attempts, DateTimeOffset? nextAttemptAt, string code, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, FailSql, cancellationToken);
        command.Parameters.AddWithValue("id", notificationId);
        command.Parameters.AddWithValue("attempts", attempts);
        command.Parameters.AddWithValue("error", code);
        command.Parameters.AddWithValue("next", (object?)nextAttemptAt?.ToUniversalTime() ?? DBNull.Value);
        command.Parameters.AddWithValue("dead", nextAttemptAt is null);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeferAsync(Guid notificationId, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, DeferSql, cancellationToken);
        command.Parameters.AddWithValue("id", notificationId);
        command.Parameters.AddWithValue("next", nextAttemptAt.ToUniversalTime());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<(long LessThan1h, long AtLeast1h)> BacklogAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, BacklogSql, cancellationToken);
        command.Parameters.AddWithValue("cutoff", now.ToUniversalTime() - TimeSpan.FromHours(1));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return (reader.GetInt64(0), reader.GetInt64(1));
    }

    public async Task<IReadOnlyList<PlayExpiredSubscription>> ListExpiredSubscriptionsAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, ExpiredSql, cancellationToken);
        command.Parameters.AddWithValue("from", now.ToUniversalTime() - TimeSpan.FromDays(7));
        command.Parameters.AddWithValue("to", now.ToUniversalTime() - TimeSpan.FromMinutes(10));
        command.Parameters.AddWithValue("limit", limit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<PlayExpiredSubscription>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new PlayExpiredSubscription(reader.GetGuid(0), new Sensitive<string>(reader.GetString(1)), reader.GetFieldValue<DateTimeOffset>(2)));
        }

        return rows;
    }

    public async Task<bool> HasRtdnVoidedAsync(Sensitive<string> storeKey, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await using var command = await CommandAsync(db, RtdnVoidedSql, cancellationToken);
        command.Parameters.AddWithValue("key", storeKey.Reveal() ?? string.Empty);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    private static async Task<NpgsqlCommand> CommandAsync(ZaghlolDbContext db, string sql, CancellationToken cancellationToken)
    {
        await db.Database.OpenConnectionAsync(cancellationToken);
        return new NpgsqlCommand(sql, (NpgsqlConnection)db.Database.GetDbConnection());
    }

    private static PurchaseEnvironment ParseEnvironment(string text) => text switch
    {
        "production" => PurchaseEnvironment.Production,
        "sandbox" => PurchaseEnvironment.Sandbox,
        _ => throw new InvalidOperationException("Unknown environment value."),
    };
}
