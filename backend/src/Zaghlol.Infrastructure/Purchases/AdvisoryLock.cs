using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>
/// A named PostgreSQL session advisory lock on its own Worker-login connection (T-134, shared by the T-133 jobs): one holder across
/// replicas, released (and the connection returned) on dispose.
/// </summary>
internal static class AdvisoryLock
{
    /// <summary>The lock key of <paramref name="name"/>: the first 8 bytes of its SHA-256.</summary>
    public static long Key(string name) => BinaryPrimitives.ReadInt64BigEndian(SHA256.HashData(Encoding.ASCII.GetBytes(name)));

    /// <summary><c>pg_try_advisory_lock</c>; <c>null</c> when another session holds it.</summary>
    public static async Task<IAsyncDisposable?> TryTakeAsync(IZaghlolDbContextFactory contexts, string name, CancellationToken cancellationToken)
    {
        var key = Key(name);
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
