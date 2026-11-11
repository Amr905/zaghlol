using System.Buffers.Binary;
using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>
/// The acknowledge sweeper's rows on the Worker login (<c>worker_rw</c>: UPDATE on state, expires_at, acknowledged,
/// last_verified_at, linked_purchase_token and ack_next_attempt_at only; INSERT on purchase_events). No transaction is held across a Play call: the
/// list is a plain read and each update is its own short transaction with the monotonic guard.
/// </summary>
internal sealed class PlayAckSweepStore(IZaghlolDbContextFactory contexts) : IPlayAckSweepStore
{
    /// <summary>The advisory lock key: the first 8 bytes of SHA-256("play-ack-sweeper").</summary>
    public static readonly long LockKey = BinaryPrimitives.ReadInt64BigEndian(SHA256.HashData(Encoding.ASCII.GetBytes("play-ack-sweeper")));

    // Pending rows are read too (they may have become purchased); expired, refunded, on-hold and paused ones are never acked.
    // Only due rows, in PlayAckSweepSchedule.SortKey order: ackable before pending, never deferred first, earliest due, oldest.
    private const string ListSql = """
        SELECT id, product_id, store_key, state, created_at
        FROM zaghlol.purchases
        WHERE store = 'google_play' AND acknowledged = false AND state IN ('pending', 'active', 'in_grace', 'canceled_active')
          AND (ack_next_attempt_at IS NULL OR ack_next_attempt_at <= @now)
        ORDER BY (state = 'pending'), ack_next_attempt_at NULLS FIRST, created_at
        LIMIT @limit
        """;

    private const string DeferSql = "UPDATE zaghlol.purchases SET ack_next_attempt_at = @next WHERE id = @id";

    private const string LockRowSql = "SELECT state, last_verified_at FROM zaghlol.purchases WHERE id = @id FOR UPDATE";

    private const string UpdateSql = """
        UPDATE zaghlol.purchases
        SET state = @state, expires_at = @expires, acknowledged = acknowledged OR @ack,
            linked_purchase_token = COALESCE(@linked, linked_purchase_token), last_verified_at = @read_at
        WHERE id = @id
        """;

    // Rows past the refund age are out of the alert: Play has already refunded them, nothing is left to save.
    private const string SummarySql = """
        SELECT count(*) FILTER (WHERE created_at > @cutoff), count(*) FILTER (WHERE created_at <= @cutoff), min(created_at)
        FROM zaghlol.purchases
        WHERE store = 'google_play' AND acknowledged = false AND state IN ('active', 'in_grace', 'canceled_active')
          AND created_at > @refunded
        """;

    private const string OverdueSql = """
        SELECT id FROM zaghlol.purchases
        WHERE store = 'google_play' AND acknowledged = false AND state IN ('active', 'in_grace', 'canceled_active')
          AND created_at <= @cutoff AND created_at > @refunded
        ORDER BY created_at
        LIMIT @limit
        """;

    public async Task<IAsyncDisposable?> TryLockAsync(CancellationToken cancellationToken)
    {
        var db = contexts.CreateDbContext(DatabaseRole.Worker);
        try
        {
            await db.Database.OpenConnectionAsync(cancellationToken);
            var connection = (NpgsqlConnection)db.Database.GetDbConnection();
            await using var command = new NpgsqlCommand("SELECT pg_try_advisory_lock(@key)", connection);
            command.Parameters.AddWithValue("key", LockKey);
            if (await command.ExecuteScalarAsync(cancellationToken) is true)
            {
                return new SessionLock(db, connection);
            }

            await db.DisposeAsync();
            return null;
        }
        catch
        {
            await db.DisposeAsync();
            throw;
        }
    }

    public async Task<IReadOnlyList<UnackedPurchase>> ListAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(ListSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("now", now.ToUniversalTime());
        command.Parameters.AddWithValue("limit", limit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<UnackedPurchase>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new UnackedPurchase(
                reader.GetGuid(0),
                reader.GetString(1),
                new Sensitive<string>(reader.GetString(2)),
                PurchaseDbText.ParseState(reader.GetString(3)),
                reader.GetFieldValue<DateTimeOffset>(4)));
        }

        return rows;
    }

    public async Task DeferAsync(Guid id, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(DeferSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("next", nextAttemptAt.ToUniversalTime());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<bool> ApplyAsync(SweepUpdate update, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(update);

        var readAt = update.ReadAt.ToUniversalTime();
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        string current;
        await using (var lockRow = new NpgsqlCommand(LockRowSql, connection, transaction))
        {
            lockRow.Parameters.AddWithValue("id", update.Id);
            await using var reader = await lockRow.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken) || reader.GetFieldValue<DateTimeOffset>(1) >= readAt)
            {
                // Gone, or a newer read (verify, RTDN) already stored: keep it.
                return false;
            }

            current = reader.GetString(0);
        }

        // T-133 label rule under the row lock: an 'expired' read keeps a stored 'refunded'/'revoked'.
        var state = PurchaseDbText.State(PlayStateMapping.Settle(PurchaseDbText.ParseState(current), update.State, null));
        await using (var command = new NpgsqlCommand(UpdateSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", update.Id);
            command.Parameters.AddWithValue("state", state);
            command.Parameters.AddWithValue("expires", (object?)update.ExpiresAt?.ToUniversalTime() ?? DBNull.Value);
            command.Parameters.AddWithValue("ack", update.Acknowledged);
            command.Parameters.AddWithValue("linked", (object?)update.LinkedPurchaseToken?.Reveal() ?? DBNull.Value);
            command.Parameters.AddWithValue("read_at", readAt);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        if (!string.Equals(current, state, StringComparison.Ordinal))
        {
            await PurchaseWriter.EventAsync(connection, transaction, update.Id, current, state, "sweep", readAt, cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return true;
    }

    public async Task<UnackedSummary> SummarizeAsync(DateTimeOffset now, int maxOverdue, CancellationToken cancellationToken)
    {
        var cutoff = now.ToUniversalTime() - PlayAckSweepJob.AlertAge;
        var refunded = now.ToUniversalTime() - PlayAckSweepSchedule.RefundAge;
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();

        long fresh, overdue;
        DateTimeOffset? oldest;
        await using (var summary = new NpgsqlCommand(SummarySql, connection))
        {
            summary.Parameters.AddWithValue("cutoff", cutoff);
            summary.Parameters.AddWithValue("refunded", refunded);
            await using var reader = await summary.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            fresh = reader.GetInt64(0);
            overdue = reader.GetInt64(1);
            oldest = reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2);
        }

        var ids = new List<Guid>();
        if (overdue > 0)
        {
            await using var list = new NpgsqlCommand(OverdueSql, connection);
            list.Parameters.AddWithValue("cutoff", cutoff);
            list.Parameters.AddWithValue("refunded", refunded);
            list.Parameters.AddWithValue("limit", maxOverdue);
            await using var reader = await list.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                ids.Add(reader.GetGuid(0));
            }
        }

        var age = oldest is { } first ? now - first : TimeSpan.Zero;
        return new UnackedSummary(fresh, overdue, age < TimeSpan.Zero ? TimeSpan.Zero : age, ids);
    }

    /// <summary>The session advisory lock on its own connection; released (and the connection returned) on dispose.</summary>
    private sealed class SessionLock(ZaghlolDbContext db, NpgsqlConnection connection) : IAsyncDisposable
    {
        private int disposed;

        public async ValueTask DisposeAsync()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 1)
            {
                return;
            }

            try
            {
                await using var unlock = new NpgsqlCommand("SELECT pg_advisory_unlock(@key)", connection);
                unlock.Parameters.AddWithValue("key", LockKey);
                await unlock.ExecuteScalarAsync();
            }
            finally
            {
                await db.DisposeAsync();
            }
        }
    }
}
