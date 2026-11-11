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
/// The idempotent <c>store_notifications</c> insert (T-134 design note §1 step 6): only the extracted columns, <c>ON CONFLICT (store,
/// external_id) DO NOTHING</c>. One instance per login: the API's on <c>app_rw</c>, the worker's (history job) on <c>worker_rw</c>.
/// </summary>
internal sealed class StoreNotificationInbox(Func<ZaghlolDbContext> contexts) : IStoreNotificationInbox
{
    private const string InsertSql = """
        INSERT INTO zaghlol.store_notifications
            (id, store, external_id, type, subtype, product_id, store_key, environment, event_time, payload_digest, attempts,
             processed_at, last_error)
        VALUES (@id, @store, @external, @type, @subtype, @product, @key, @environment, @event_time, @digest, 0,
                CASE WHEN @processed THEN now() ELSE NULL END, @error)
        ON CONFLICT (store, external_id) DO NOTHING
        """;

    public async Task<bool> TryInsertAsync(StoreNotificationRecord record, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(record);

        await using var db = contexts();
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(InsertSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("id", record.Id);
        command.Parameters.AddWithValue("store", PurchaseDbText.Store(record.Store));
        command.Parameters.AddWithValue("external", record.ExternalId);
        command.Parameters.AddWithValue("type", record.Type);
        command.Parameters.AddWithValue("subtype", (object?)record.Subtype ?? DBNull.Value);
        command.Parameters.AddWithValue("product", (object?)record.ProductId ?? DBNull.Value);
        command.Parameters.AddWithValue("key", (object?)record.StoreKey?.Reveal() ?? DBNull.Value);
        command.Parameters.AddWithValue("environment", PurchaseDbText.Environment(record.Environment));
        command.Parameters.AddWithValue("event_time", record.EventTime.ToUniversalTime());
        command.Parameters.AddWithValue("digest", record.PayloadDigest);
        command.Parameters.AddWithValue("processed", record.Processed);
        command.Parameters.AddWithValue("error", (object?)record.LastError ?? DBNull.Value);
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }
}

/// <summary>
/// The ASSN V2 worker's rows on the Worker login (T-134 design note §2, §4). No transaction is held across an Apple call: the pick
/// is a plain read and each write is one short transaction. The purchase write is the worker statement (FU-092 item 1): state,
/// expiry, product, plan and <c>last_verified_at</c> only, under the monotonic guard; <c>worker_rw</c> has no grant on anything else
/// verify writes, and none on <c>purchase_seats</c> beyond SELECT.
/// </summary>
internal sealed class AppleNotificationStore(IZaghlolDbContextFactory contexts) : IAppleNotificationStore
{
    private const string ListDueSql = """
        SELECT id, type, store_key, environment, attempts, received_at
        FROM zaghlol.store_notifications
        WHERE store = 'app_store' AND processed_at IS NULL AND (next_attempt_at IS NULL OR next_attempt_at <= @now)
        ORDER BY next_attempt_at NULLS FIRST, received_at
        LIMIT @limit
        """;

    private const string FindSql = """
        SELECT id, store_key, product_id, plan, environment, state
        FROM zaghlol.purchases WHERE store = 'app_store' AND store_key = @key
        """;

    private const string LockSql = "SELECT state, last_verified_at FROM zaghlol.purchases WHERE id = @id FOR UPDATE";

    // The worker statement (T-134 §2 step 6). Never install_id, obfuscated_install_ref, environment, acknowledged or last_payment_at.
    private const string UpdateSql = """
        UPDATE zaghlol.purchases
        SET state = @state, expires_at = CASE WHEN @keep_expires THEN expires_at ELSE @expires END,
            product_id = @product, plan = @plan, last_verified_at = @read_at
        WHERE id = @id AND last_verified_at < @read_at
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
        WHERE store = 'app_store' AND processed_at IS NULL
        """;

    private const string ExpiredSql = """
        SELECT id, store_key, product_id, plan, environment, state
        FROM zaghlol.purchases
        WHERE store = 'app_store' AND plan <> 'lifetime' AND state IN ('active', 'in_grace', 'canceled_active')
          AND expires_at BETWEEN @from AND @to AND last_verified_at < expires_at
        ORDER BY expires_at
        LIMIT @limit
        """;

    /// <summary>The advisory lock key of <paramref name="name"/>: the first 8 bytes of its SHA-256.</summary>
    public static long LockKey(string name) => BinaryPrimitives.ReadInt64BigEndian(SHA256.HashData(Encoding.ASCII.GetBytes(name)));

    public async Task<IAsyncDisposable?> TryLockAsync(string name, CancellationToken cancellationToken)
    {
        var key = LockKey(name);
        var db = contexts.CreateDbContext(DatabaseRole.Worker);
        try
        {
            await db.Database.OpenConnectionAsync(cancellationToken);
            var connection = (NpgsqlConnection)db.Database.GetDbConnection();
            await using var command = new NpgsqlCommand("SELECT pg_try_advisory_lock(@key)", connection);
            command.Parameters.AddWithValue("key", key);
            if (await command.ExecuteScalarAsync(cancellationToken) is true)
            {
                return new SessionLock(db, connection, key);
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

    public async Task<IReadOnlyList<DueAppleNotification>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(ListDueSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("now", now.ToUniversalTime());
        command.Parameters.AddWithValue("limit", limit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<DueAppleNotification>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new DueAppleNotification(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? null : new Sensitive<string>(reader.GetString(2)),
                reader.IsDBNull(3) ? null : ParseEnvironment(reader.GetString(3)),
                reader.GetInt32(4),
                reader.GetFieldValue<DateTimeOffset>(5)));
        }

        return rows;
    }

    public async Task<ApplePurchaseRow?> FindPurchaseAsync(Sensitive<string> storeKey, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(FindSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("key", storeKey.Reveal());
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadPurchase(reader) : null;
    }

    public async Task<AppleWriteResult> ApplyAsync(AppleStateWrite write, Guid? notificationId, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(write);

        var readAt = write.ReadAt.ToUniversalTime();
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        string? current = null;
        DateTimeOffset lastVerifiedAt = default;
        await using (var lockRow = new NpgsqlCommand(LockSql, connection, transaction))
        {
            lockRow.Parameters.AddWithValue("id", write.PurchaseId);
            await using var reader = await lockRow.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                current = reader.GetString(0);
                lastVerifiedAt = reader.GetFieldValue<DateTimeOffset>(1);
            }
        }

        AppleWriteResult result;
        if (current is null)
        {
            result = AppleWriteResult.Gone;
        }
        else if (lastVerifiedAt >= readAt)
        {
            // A newer read (verify, the sweep, another notification) is stored: keep it.
            result = AppleWriteResult.Superseded;
        }
        else
        {
            var state = PurchaseDbText.State(write.State);
            await using (var update = new NpgsqlCommand(UpdateSql, connection, transaction))
            {
                update.Parameters.AddWithValue("id", write.PurchaseId);
                update.Parameters.AddWithValue("state", state);
                update.Parameters.AddWithValue("keep_expires", write.KeepStoredExpiry);
                update.Parameters.AddWithValue("expires", (object?)write.ExpiresAt?.ToUniversalTime() ?? DBNull.Value);
                update.Parameters.AddWithValue("product", write.ProductId);
                update.Parameters.AddWithValue("plan", PurchaseDbText.Plan(write.Plan));
                update.Parameters.AddWithValue("read_at", readAt);
                if (await update.ExecuteNonQueryAsync(cancellationToken) != 1)
                {
                    throw new InvalidOperationException("The locked purchase row was not updated.");
                }
            }

            if (string.Equals(current, state, StringComparison.Ordinal))
            {
                result = AppleWriteResult.Unchanged;
            }
            else
            {
                await PurchaseWriter.EventAsync(connection, transaction, write.PurchaseId, current, state, write.Cause, readAt, cancellationToken);
                result = AppleWriteResult.Applied;
            }
        }

        if (notificationId is { } id)
        {
            await using var complete = new NpgsqlCommand(CompleteSql, connection, transaction);
            complete.Parameters.AddWithValue("id", id);
            complete.Parameters.AddWithValue("error", result == AppleWriteResult.Gone ? AppleNotificationSchedule.NoPurchase : (object)DBNull.Value);
            await complete.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    public async Task CompleteAsync(Guid notificationId, string? code, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(CompleteSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("id", notificationId);
        command.Parameters.AddWithValue("error", (object?)code ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task FailAsync(Guid notificationId, int attempts, DateTimeOffset? nextAttemptAt, string code, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(FailSql, (NpgsqlConnection)db.Database.GetDbConnection());
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
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(DeferSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("id", notificationId);
        command.Parameters.AddWithValue("next", nextAttemptAt.ToUniversalTime());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<(long LessThan1h, long AtLeast1h)> BacklogAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(BacklogSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("cutoff", now.ToUniversalTime() - TimeSpan.FromHours(1));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return (reader.GetInt64(0), reader.GetInt64(1));
    }

    public async Task<IReadOnlyList<ApplePurchaseRow>> ListExpiredSubscriptionsAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(ExpiredSql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("from", now.ToUniversalTime() - TimeSpan.FromDays(7));
        command.Parameters.AddWithValue("to", now.ToUniversalTime() - TimeSpan.FromMinutes(10));
        command.Parameters.AddWithValue("limit", limit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<ApplePurchaseRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(ReadPurchase(reader));
        }

        return rows;
    }

    private static ApplePurchaseRow ReadPurchase(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        new Sensitive<string>(reader.GetString(1)),
        reader.GetString(2),
        reader.GetString(3) switch
        {
            "monthly" => GoldPlan.Monthly,
            "yearly" => GoldPlan.Yearly,
            _ => GoldPlan.Lifetime,
        },
        ParseEnvironment(reader.GetString(4)),
        PurchaseDbText.ParseState(reader.GetString(5)));

    private static PurchaseEnvironment ParseEnvironment(string text) => text switch
    {
        "production" => PurchaseEnvironment.Production,
        "sandbox" => PurchaseEnvironment.Sandbox,
        _ => throw new InvalidOperationException("Unknown environment value."),
    };

    /// <summary>The session advisory lock on its own connection; released (and the connection returned) on dispose.</summary>
    private sealed class SessionLock(ZaghlolDbContext db, NpgsqlConnection connection, long key) : IAsyncDisposable
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
                unlock.Parameters.AddWithValue("key", key);
                await unlock.ExecuteScalarAsync();
            }
            finally
            {
                await db.DisposeAsync();
            }
        }
    }
}
