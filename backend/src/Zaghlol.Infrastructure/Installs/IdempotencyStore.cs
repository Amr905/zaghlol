using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Installs;

/// <summary>A stored final result (R2-8): the request body hash, the status and the envelope-encrypted unsigned body.</summary>
public sealed record StoredIdempotentResult(ReadOnlyMemory<byte> BodySha256, int Status, ReadOnlyMemory<byte> ResponseBodyEnc);

/// <summary>What <see cref="IIdempotencyStore.TryClaimAsync"/> found.</summary>
public enum IdempotencyClaimKind
{
    /// <summary>This request holds the key now (<see cref="IdempotencyClaim.ClaimId"/>); run the handler.</summary>
    Claimed,

    /// <summary>A live final result exists (<see cref="IdempotencyClaim.Stored"/>): replay it or answer 409.</summary>
    Stored,

    /// <summary>Another request holds the key: <c>429</c> with <c>Retry-After: 1</c>.</summary>
    InProgress,

    /// <summary>The install is gone (deleted after authentication): <c>401</c>.</summary>
    NoInstall,
}

public sealed record IdempotencyClaim(IdempotencyClaimKind Kind, Guid ClaimId, bool TakenOver, StoredIdempotentResult? Stored);

/// <summary>
/// <c>idempotency_records</c> for <c>verifyPurchase</c> and <c>signIn</c> (backend-api §1, R2-8, R3-6), keyed by (install from the
/// token, operation, Idempotency-Key). T-130 (FU-052 S-2): a key is claimed by a row with <c>status = 0</c> and a 60 s lease in
/// one short transaction, and completed or released in another; no connection, transaction or lock is held while the handler
/// runs (it may wait seconds on a store), so a full pool can't deadlock.
/// </summary>
public interface IIdempotencyStore
{
    /// <summary>
    /// Transaction 1 (milliseconds): deletes an expired row of the key (an expired claim from a crashed request is taken over),
    /// inserts a claim only while the install exists and isn't deleted (S-4), otherwise reports the live row.
    /// </summary>
    Task<IdempotencyClaim> TryClaimAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        ReadOnlyMemory<byte> bodySha256,
        DateTimeOffset now,
        CancellationToken cancellationToken);

    /// <summary>
    /// Transaction 2: replaces this request's claim with the final row (the same install guard). False when the lease was lost
    /// (taken over after expiry, or the install was deleted): nothing is stored.
    /// </summary>
    Task<bool> CompleteAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        Guid claimId,
        ReadOnlyMemory<byte> bodySha256,
        int status,
        ReadOnlyMemory<byte> responseBodyEnc,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken);

    /// <summary>Deletes this request's claim (429, 5xx, an exception), so a retry runs at once. Best effort: the lease backs it up.</summary>
    Task ReleaseAsync(InstallId installId, IdempotentOperation operation, string idempotencyKey, Guid claimId, CancellationToken cancellationToken);
}

/// <summary>The idempotency claim lease (T-130, FU-052 S-2).</summary>
public static class IdempotencyLease
{
    /// <summary>How long a claim lasts without being completed. Longer than the handler timeout, so a live handler keeps it.</summary>
    public static readonly TimeSpan Duration = TimeSpan.FromSeconds(60);
}

internal sealed class IdempotencyStore(IAppDbContextFactory contexts) : IIdempotencyStore
{
    public static readonly TimeSpan Lease = IdempotencyLease.Duration;

    private const string DeleteExpiredSql = """
        DELETE FROM zaghlol.idempotency_records
        WHERE install_id = @install AND operation_id = @operation AND idempotency_key = @key AND expires_at <= @now
        RETURNING status
        """;

    // FOR SHARE on the install row: DELETE /v1/installs/me updates that row before deleting the records, so either the delete
    // waits for this insert and then removes it, or this insert waits for the delete and then sees deleted_at set (S-4).
    private const string InsertSql = """
        INSERT INTO zaghlol.idempotency_records
            (install_id, operation_id, idempotency_key, body_sha256, status, response_body_enc, claim_id, expires_at)
        SELECT @install, @operation, @key, @hash, @status, @body, @claim, @expires
        ON CONFLICT DO NOTHING
        """;

    private const string LiveSql = """
        SELECT body_sha256, status, response_body_enc FROM zaghlol.idempotency_records
        WHERE install_id = @install AND operation_id = @operation AND idempotency_key = @key AND expires_at > @now
        """;

    private const string InstallLiveSql = "SELECT EXISTS (SELECT 1 FROM zaghlol.installs WHERE id = @install AND deleted_at IS NULL)";

    private const string DeleteClaimSql = """
        DELETE FROM zaghlol.idempotency_records
        WHERE install_id = @install AND operation_id = @operation AND idempotency_key = @key AND claim_id = @claim AND status = 0
        """;

    public async Task<IdempotencyClaim> TryClaimAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        ReadOnlyMemory<byte> bodySha256,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(idempotencyKey);

        var at = now.ToUniversalTime();
        await using var db = contexts.CreateDbContext();
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        var takenOver = false;
        await using (var expired = Command(connection, transaction, DeleteExpiredSql, installId, operation, idempotencyKey))
        {
            expired.Parameters.AddWithValue("now", at);
            await using var reader = await expired.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                takenOver |= reader.GetInt32(0) == 0;
            }
        }

        var claimId = Guid.NewGuid();
        await using (var insert = Command(connection, transaction, InsertSql, installId, operation, idempotencyKey))
        {
            insert.Parameters.AddWithValue("hash", bodySha256.ToArray());
            insert.Parameters.AddWithValue("status", 0);
            insert.Parameters.AddWithValue("body", Array.Empty<byte>());
            insert.Parameters.AddWithValue("claim", NpgsqlDbType.Uuid, claimId);
            insert.Parameters.AddWithValue("expires", at + Lease);
            if (await insert.ExecuteNonQueryAsync(cancellationToken) == 1)
            {
                await transaction.CommitAsync(cancellationToken);
                return new IdempotencyClaim(IdempotencyClaimKind.Claimed, claimId, takenOver, null);
            }
        }

        IdempotencyClaim result;
        await using (var live = Command(connection, transaction, LiveSql, installId, operation, idempotencyKey))
        {
            live.Parameters.AddWithValue("now", at);
            await using var reader = await live.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                var status = reader.GetInt32(1);
                result = status == 0
                    ? new IdempotencyClaim(IdempotencyClaimKind.InProgress, Guid.Empty, false, null)
                    : new IdempotencyClaim(
                        IdempotencyClaimKind.Stored,
                        Guid.Empty,
                        false,
                        new StoredIdempotentResult(reader.GetFieldValue<byte[]>(0), status, reader.GetFieldValue<byte[]>(2)));
            }
            else
            {
                result = new IdempotencyClaim(IdempotencyClaimKind.InProgress, Guid.Empty, false, null);
            }
        }

        if (result.Kind == IdempotencyClaimKind.InProgress)
        {
            // No row was inserted and none is live: the install is gone, or another claim just went away (retry).
            await using var exists = new NpgsqlCommand(InstallLiveSql, connection, transaction);
            exists.Parameters.AddWithValue("install", installId.Value);
            if (await exists.ExecuteScalarAsync(cancellationToken) is not true)
            {
                result = new IdempotencyClaim(IdempotencyClaimKind.NoInstall, Guid.Empty, false, null);
            }
        }

        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    public async Task<bool> CompleteAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        Guid claimId,
        ReadOnlyMemory<byte> bodySha256,
        int status,
        ReadOnlyMemory<byte> responseBodyEnc,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(idempotencyKey);
        ArgumentOutOfRangeException.ThrowIfZero(status);

        await using var db = contexts.CreateDbContext();
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        await using (var delete = Command(connection, transaction, DeleteClaimSql, installId, operation, idempotencyKey))
        {
            delete.Parameters.AddWithValue("claim", claimId);
            if (await delete.ExecuteNonQueryAsync(cancellationToken) != 1)
            {
                await transaction.RollbackAsync(cancellationToken);
                return false;
            }
        }

        await using (var insert = Command(connection, transaction, InsertSql, installId, operation, idempotencyKey))
        {
            insert.Parameters.AddWithValue("hash", bodySha256.ToArray());
            insert.Parameters.AddWithValue("status", status);
            insert.Parameters.AddWithValue("body", responseBodyEnc.ToArray());
            insert.Parameters.AddWithValue("claim", NpgsqlDbType.Uuid, DBNull.Value);
            insert.Parameters.AddWithValue("expires", expiresAt.ToUniversalTime());
            if (await insert.ExecuteNonQueryAsync(cancellationToken) != 1)
            {
                await transaction.RollbackAsync(cancellationToken);
                return false;
            }
        }

        await transaction.CommitAsync(cancellationToken);
        return true;
    }

    public async Task ReleaseAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        Guid claimId,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(idempotencyKey);

        await using var db = contexts.CreateDbContext();
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var delete = Command((NpgsqlConnection)db.Database.GetDbConnection(), null, DeleteClaimSql, installId, operation, idempotencyKey);
        delete.Parameters.AddWithValue("claim", claimId);
        await delete.ExecuteNonQueryAsync(cancellationToken);
    }

    private static NpgsqlCommand Command(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        string sql,
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey)
    {
        var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("install", installId.Value);
        command.Parameters.AddWithValue("operation", DbEnumMaps.IdempotentOperations.ToDb(operation));
        command.Parameters.AddWithValue("key", idempotencyKey);
        return command;
    }
}
