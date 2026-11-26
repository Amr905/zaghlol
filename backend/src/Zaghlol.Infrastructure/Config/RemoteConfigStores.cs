using Microsoft.EntityFrameworkCore;
using Npgsql;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Config;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Config;

/// <summary>
/// <c>remote_config</c> on the Admin login (<c>ops_rw</c>: SELECT, INSERT, UPDATE): the only writer of config, and of its audit
/// rows. The table has no EF entity (T-323 created it by raw SQL), so the statements are written out.
/// </summary>
internal sealed class RemoteConfigAdminStore(IZaghlolDbContextFactory contexts, IAuditWriter audit) : IRemoteConfigAdminStore
{
    // One statement: the version increments atomically, so two concurrent changes never share a version.
    private const string UpsertSql = """
        INSERT INTO zaghlol.remote_config AS c (key, value, version, updated_by, updated_at)
        VALUES (@key, @value, 1, @operator, @now)
        ON CONFLICT (key) DO UPDATE SET
          value = EXCLUDED.value,
          version = c.version + 1,
          updated_by = EXCLUDED.updated_by,
          updated_at = EXCLUDED.updated_at
        RETURNING c.value, c.version, c.updated_at
        """;

    public async Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        return await RemoteConfigSql.ReadAllAsync(db, cancellationToken);
    }

    public async Task<RemoteConfigRow> UpsertAsync(string key, string value, Guid operatorId, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        RemoteConfigRow row;
        await using (var upsert = new NpgsqlCommand(UpsertSql, connection, transaction))
        {
            upsert.Parameters.AddWithValue("key", key);
            upsert.Parameters.AddWithValue("value", value);
            upsert.Parameters.AddWithValue("operator", operatorId);
            upsert.Parameters.AddWithValue("now", now.ToUniversalTime());

            await using var reader = await upsert.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                throw new InvalidOperationException("The config upsert returned no row.");
            }

            row = new RemoteConfigRow(key, reader.GetString(0), reader.GetInt64(1), reader.GetFieldValue<DateTimeOffset>(2));
        }

        // Same transaction: exactly one audit row per change, and a failed insert rolls the change back.
        await audit.WriteAsync(connection, transaction, operatorId, new ConfigUpdateAudit(row.Key, row.Value, row.Version), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return row;
    }
}

/// <summary><c>remote_config</c> on the App login (<c>app_rw</c>, SELECT only).</summary>
internal sealed class RemoteConfigReader(IAppDbContextFactory contexts) : IRemoteConfigReader
{
    public async Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        return await RemoteConfigSql.ReadAllAsync(db, cancellationToken);
    }
}

internal static class RemoteConfigSql
{
    private const string SelectSql = "SELECT key, value, version, updated_at FROM zaghlol.remote_config";

    public static async Task<IReadOnlyList<RemoteConfigRow>> ReadAllAsync(ZaghlolDbContext db, CancellationToken cancellationToken)
    {
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var command = new NpgsqlCommand(SelectSql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<RemoteConfigRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new RemoteConfigRow(reader.GetString(0), reader.GetString(1), reader.GetInt64(2), reader.GetFieldValue<DateTimeOffset>(3)));
        }

        return rows;
    }
}
