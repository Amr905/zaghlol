using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>The database text of the Application purchase enums (backend-schema §2 CHECK values).</summary>
internal static class PurchaseDbText
{
    public static string Store(PurchaseStore store) => store == PurchaseStore.GooglePlay ? "google_play" : "app_store";

    public static string Plan(GoldPlan plan) => plan switch
    {
        GoldPlan.Monthly => "monthly",
        GoldPlan.Yearly => "yearly",
        _ => "lifetime",
    };

    public static string Environment(PurchaseEnvironment environment) =>
        environment == PurchaseEnvironment.Sandbox ? "sandbox" : "production";

    public static string State(StoredPurchaseState state) => state switch
    {
        StoredPurchaseState.Pending => "pending",
        StoredPurchaseState.Active => "active",
        StoredPurchaseState.InGrace => "in_grace",
        StoredPurchaseState.OnHold => "on_hold",
        StoredPurchaseState.Paused => "paused",
        StoredPurchaseState.CanceledActive => "canceled_active",
        StoredPurchaseState.Expired => "expired",
        StoredPurchaseState.Refunded => "refunded",
        StoredPurchaseState.Revoked => "revoked",
        _ => throw new ArgumentOutOfRangeException(nameof(state)),
    };

    public static StoredPurchaseState ParseState(string text) => text switch
    {
        "pending" => StoredPurchaseState.Pending,
        "active" => StoredPurchaseState.Active,
        "in_grace" => StoredPurchaseState.InGrace,
        "on_hold" => StoredPurchaseState.OnHold,
        "paused" => StoredPurchaseState.Paused,
        "canceled_active" => StoredPurchaseState.CanceledActive,
        "expired" => StoredPurchaseState.Expired,
        "refunded" => StoredPurchaseState.Refunded,
        "revoked" => StoredPurchaseState.Revoked,
        _ => throw new InvalidOperationException("Unknown purchases.state value."),
    };
}

/// <summary>
/// <c>purchases</c> upserts of verify on the App login (T-130 design note §1 step 5). One short READ COMMITTED transaction:
/// the row is locked (<c>FOR UPDATE</c>), inserted or updated only when <c>last_verified_at &lt; readAt</c> (the monotonic
/// guard: a slower read never overwrites a newer RTDN or sweeper read), and a <c>purchase_events</c> row is added when the
/// state changes. <c>install_id</c> and <c>product_id</c> are written on insert only; <c>acknowledged</c> never goes back to
/// false. The predecessor named by <c>linked_purchase_token</c> is looked up, never edited.
/// </summary>
internal sealed class PurchaseWriter(IAppDbContextFactory contexts) : IPurchaseWriter
{
    private const string LockSql = """
        SELECT id, state, expires_at, acknowledged, last_verified_at
        FROM zaghlol.purchases WHERE store = @store AND store_key = @key
        FOR UPDATE
        """;

    private const string InsertSql = """
        INSERT INTO zaghlol.purchases
            (id, store, product_id, plan, store_key, linked_purchase_token, install_id, state, expires_at, acknowledged,
             environment, obfuscated_install_ref, last_verified_at)
        VALUES (@id, @store, @product, @plan, @key, @linked, @install, @state, @expires, @ack, @environment, @ref, @read_at)
        ON CONFLICT (store, store_key) DO NOTHING
        """;

    private const string UpdateSql = """
        UPDATE zaghlol.purchases
        SET linked_purchase_token = COALESCE(@linked, linked_purchase_token),
            obfuscated_install_ref = COALESCE(@ref, obfuscated_install_ref),
            state = @state, expires_at = @expires, environment = @environment,
            acknowledged = acknowledged OR @ack, last_verified_at = @read_at
        WHERE id = @id AND last_verified_at < @read_at
        RETURNING acknowledged
        """;

    private const string EventSql = """
        INSERT INTO zaghlol.purchase_events (id, purchase_id, from_state, to_state, cause, occurred_at)
        VALUES (@id, @purchase, @from, @to, @cause, @at)
        """;

    private const string PredecessorSql = "SELECT id FROM zaghlol.purchases WHERE store = @store AND store_key = @linked AND id <> @id";

    public async Task<PurchaseUpsertResult> UpsertAsync(PurchaseUpsert upsert, string cause, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(upsert);
        ArgumentException.ThrowIfNullOrEmpty(cause);

        var store = PurchaseDbText.Store(upsert.Store);
        var key = upsert.StoreKey.Reveal();
        var state = PurchaseDbText.State(upsert.State);
        var readAt = upsert.ReadAt.ToUniversalTime();

        await using var db = contexts.CreateDbContext();
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        var existing = await LockAsync(connection, transaction, store, key, cancellationToken);
        Guid id;
        bool applied;
        string storedState;
        DateTimeOffset? storedExpires;
        bool storedAck;
        if (existing is null)
        {
            id = Guid.CreateVersion7();
            await using var insert = new NpgsqlCommand(InsertSql, connection, transaction);
            insert.Parameters.AddWithValue("id", id);
            insert.Parameters.AddWithValue("store", store);
            insert.Parameters.AddWithValue("product", upsert.ProductId);
            insert.Parameters.AddWithValue("plan", PurchaseDbText.Plan(upsert.Plan));
            insert.Parameters.AddWithValue("key", key);
            insert.Parameters.AddWithValue("linked", (object?)upsert.LinkedPurchaseToken?.Reveal() ?? DBNull.Value);
            insert.Parameters.AddWithValue("install", (object?)upsert.InstallId?.Value ?? DBNull.Value);
            insert.Parameters.AddWithValue("state", state);
            insert.Parameters.AddWithValue("expires", (object?)upsert.ExpiresAt?.ToUniversalTime() ?? DBNull.Value);
            insert.Parameters.AddWithValue("ack", upsert.Acknowledged);
            insert.Parameters.AddWithValue("environment", PurchaseDbText.Environment(upsert.Environment));
            insert.Parameters.AddWithValue("ref", (object?)upsert.ObfuscatedInstallRef ?? DBNull.Value);
            insert.Parameters.AddWithValue("read_at", readAt);
            if (await insert.ExecuteNonQueryAsync(cancellationToken) == 1)
            {
                await EventAsync(connection, transaction, id, null, state, cause, readAt, cancellationToken);
                applied = true;
                (storedState, storedExpires, storedAck) = (state, upsert.ExpiresAt, upsert.Acknowledged);
            }
            else
            {
                // A concurrent insert won; lock its row and fall through to the update rules.
                existing = await LockAsync(connection, transaction, store, key, cancellationToken)
                    ?? throw new InvalidOperationException("The purchase row vanished during the upsert.");
                (id, applied, storedState, storedExpires, storedAck) = await UpdateAsync(connection, transaction, existing, upsert, state, cause, readAt, cancellationToken);
            }
        }
        else
        {
            (id, applied, storedState, storedExpires, storedAck) = await UpdateAsync(connection, transaction, existing, upsert, state, cause, readAt, cancellationToken);
        }

        Guid? predecessor = null;
        if (upsert.LinkedPurchaseToken?.Reveal() is { } linked)
        {
            await using var find = new NpgsqlCommand(PredecessorSql, connection, transaction);
            find.Parameters.AddWithValue("store", store);
            find.Parameters.AddWithValue("linked", linked);
            find.Parameters.AddWithValue("id", id);
            predecessor = await find.ExecuteScalarAsync(cancellationToken) as Guid?;
        }

        await transaction.CommitAsync(cancellationToken);
        return new PurchaseUpsertResult(id, applied, PurchaseDbText.ParseState(storedState), storedExpires, storedAck, predecessor);
    }

    public async Task<bool> MarkAcknowledgedAsync(Guid purchaseId, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        var updated = await db.Database.ExecuteSqlAsync(
            $"UPDATE zaghlol.purchases SET acknowledged = true WHERE id = {purchaseId} AND acknowledged = false",
            cancellationToken);
        return updated == 1;
    }

    private static async Task<LockedRow?> LockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string store,
        string key,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(LockSql, connection, transaction);
        command.Parameters.AddWithValue("store", store);
        command.Parameters.AddWithValue("key", key);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new LockedRow(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2),
            reader.GetBoolean(3),
            reader.GetFieldValue<DateTimeOffset>(4));
    }

    private static async Task<(Guid, bool, string, DateTimeOffset?, bool)> UpdateAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        LockedRow existing,
        PurchaseUpsert upsert,
        string state,
        string cause,
        DateTimeOffset readAt,
        CancellationToken cancellationToken)
    {
        if (existing.LastVerifiedAt >= readAt)
        {
            // A newer read is already stored: keep it and report it as stored.
            return (existing.Id, false, existing.State, existing.ExpiresAt, existing.Acknowledged);
        }

        await using var update = new NpgsqlCommand(UpdateSql, connection, transaction);
        update.Parameters.AddWithValue("id", existing.Id);
        update.Parameters.AddWithValue("linked", (object?)upsert.LinkedPurchaseToken?.Reveal() ?? DBNull.Value);
        update.Parameters.AddWithValue("ref", (object?)upsert.ObfuscatedInstallRef ?? DBNull.Value);
        update.Parameters.AddWithValue("state", state);
        update.Parameters.AddWithValue("expires", (object?)upsert.ExpiresAt?.ToUniversalTime() ?? DBNull.Value);
        update.Parameters.AddWithValue("environment", PurchaseDbText.Environment(upsert.Environment));
        update.Parameters.AddWithValue("ack", upsert.Acknowledged);
        update.Parameters.AddWithValue("read_at", readAt);
        var acknowledged = await update.ExecuteScalarAsync(cancellationToken) is true;
        if (!string.Equals(existing.State, state, StringComparison.Ordinal))
        {
            await EventAsync(connection, transaction, existing.Id, existing.State, state, cause, readAt, cancellationToken);
        }

        return (existing.Id, true, state, upsert.ExpiresAt, acknowledged);
    }

    internal static async Task EventAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid purchaseId,
        string? from,
        string to,
        string cause,
        DateTimeOffset at,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(EventSql, connection, transaction);
        command.Parameters.AddWithValue("id", Guid.CreateVersion7());
        command.Parameters.AddWithValue("purchase", purchaseId);
        command.Parameters.AddWithValue("from", (object?)from ?? DBNull.Value);
        command.Parameters.AddWithValue("to", to);
        command.Parameters.AddWithValue("cause", cause);
        command.Parameters.AddWithValue("at", at);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private sealed record LockedRow(Guid Id, string State, DateTimeOffset? ExpiresAt, bool Acknowledged, DateTimeOffset LastVerifiedAt);
}
