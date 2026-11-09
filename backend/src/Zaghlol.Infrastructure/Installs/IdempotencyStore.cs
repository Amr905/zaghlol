using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Installs;

/// <summary>A stored final result (R2-8): the request body hash, the status and the envelope-encrypted unsigned body.</summary>
public sealed record StoredIdempotentResult(ReadOnlyMemory<byte> BodySha256, int Status, ReadOnlyMemory<byte> ResponseBodyEnc);

/// <summary>
/// <c>idempotency_records</c> for <c>verifyPurchase</c> and <c>signIn</c> (backend-api §1, R2-8, R3-6). A record is keyed by
/// (install from the token, operation, Idempotency-Key); a different install's same key is a different record.
/// </summary>
public interface IIdempotencyStore
{
    /// <summary>
    /// Opens a transaction holding <c>pg_try_advisory_xact_lock</c> on (install, operation, key). <c>null</c> when another
    /// request holds that key right now (the caller answers <c>429</c> with <c>Retry-After: 1</c> and stores nothing).
    /// </summary>
    Task<IIdempotencySession?> TryBeginAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        CancellationToken cancellationToken);
}

/// <summary>One locked key. Disposing without <see cref="SaveAsync"/> rolls back and releases the lock.</summary>
public interface IIdempotencySession : IAsyncDisposable
{
    /// <summary>The record, only when <c>expires_at &gt; now</c>: a row the purger has not reached yet is never served.</summary>
    Task<StoredIdempotentResult?> FindLiveAsync(DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>Stores a final result (replacing an expired, unpurged row of the same key) and commits.</summary>
    Task SaveAsync(
        ReadOnlyMemory<byte> bodySha256,
        int status,
        ReadOnlyMemory<byte> responseBodyEnc,
        DateTimeOffset now,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken);
}

internal sealed class IdempotencyStore(IAppDbContextFactory contexts) : IIdempotencyStore
{
    public async Task<IIdempotencySession?> TryBeginAsync(
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(idempotencyKey);

        var lockKey = LockKey(installId, operation, idempotencyKey);
        var db = contexts.CreateDbContext();
        IDbContextTransaction? transaction = null;
        try
        {
            transaction = await db.Database.BeginTransactionAsync(cancellationToken);
            var acquired = await db.Database
                .SqlQuery<bool>($"SELECT pg_try_advisory_xact_lock({lockKey}) AS \"Value\"")
                .ToListAsync(cancellationToken);
            if (acquired is [true])
            {
                return new Session(db, transaction, installId, operation, idempotencyKey);
            }

            await transaction.DisposeAsync();
            await db.DisposeAsync();
            return null;
        }
        catch
        {
            if (transaction is not null)
            {
                await transaction.DisposeAsync();
            }

            await db.DisposeAsync();
            throw;
        }
    }

    /// <summary>A 64-bit advisory lock key: the first 8 bytes of SHA-256 over the three key parts.</summary>
    internal static long LockKey(InstallId installId, IdempotentOperation operation, string idempotencyKey)
    {
        var material = Encoding.UTF8.GetBytes(
            "zaghlol-idem-lock-v1\0" + installId + "\0" + DbEnumMaps.IdempotentOperations.ToDb(operation) + "\0" + idempotencyKey);
        return BinaryPrimitives.ReadInt64BigEndian(SHA256.HashData(material));
    }

    private sealed class Session(
        ZaghlolDbContext db,
        IDbContextTransaction transaction,
        InstallId installId,
        IdempotentOperation operation,
        string idempotencyKey) : IIdempotencySession
    {
        public async Task<StoredIdempotentResult?> FindLiveAsync(DateTimeOffset now, CancellationToken cancellationToken)
        {
            var id = installId.Value;
            var op = operation;
            var key = idempotencyKey;
            var row = await db.IdempotencyRecords
                .AsNoTracking()
                .Where(r => r.InstallId == id && r.OperationId == op && r.IdempotencyKey == key && r.ExpiresAt > now)
                .Select(r => new { r.BodySha256, r.Status, r.ResponseBodyEnc })
                .SingleOrDefaultAsync(cancellationToken);
            return row is null ? null : new StoredIdempotentResult(row.BodySha256, row.Status, row.ResponseBodyEnc);
        }

        public async Task SaveAsync(
            ReadOnlyMemory<byte> bodySha256,
            int status,
            ReadOnlyMemory<byte> responseBodyEnc,
            DateTimeOffset now,
            DateTimeOffset expiresAt,
            CancellationToken cancellationToken)
        {
            var id = installId.Value;
            var op = operation;
            var key = idempotencyKey;
            var opText = DbEnumMaps.IdempotentOperations.ToDb(operation);
            var hash = bodySha256.ToArray();
            var body = responseBodyEnc.ToArray();

            // An expired row the purger hasn't removed yet would block the insert (app_rw has no UPDATE here).
            await db.IdempotencyRecords
                .Where(r => r.InstallId == id && r.OperationId == op && r.IdempotencyKey == key && r.ExpiresAt <= now)
                .ExecuteDeleteAsync(cancellationToken);
            await db.Database.ExecuteSqlAsync(
                $"""
                INSERT INTO zaghlol.idempotency_records
                    (install_id, operation_id, idempotency_key, body_sha256, status, response_body_enc, expires_at)
                VALUES ({id}, {opText}, {key}, {hash}, {status}, {body}, {expiresAt})
                ON CONFLICT DO NOTHING
                """,
                cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }

        public async ValueTask DisposeAsync()
        {
            await transaction.DisposeAsync();
            await db.DisposeAsync();
        }
    }
}
