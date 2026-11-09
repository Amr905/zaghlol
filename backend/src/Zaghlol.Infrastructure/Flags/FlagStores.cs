using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Flags;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Flags;

/// <summary><c>feature_flags</c> on the Admin login (<c>ops_rw</c>): the only writer of flags, and of their audit rows.</summary>
internal sealed class FlagAdminStore(IZaghlolDbContextFactory contexts) : IFlagAdminStore
{
    /// <summary>The audit action for a flag change (<c>audit_log.action</c>).</summary>
    public const string AuditAction = "flag_update";

    // One statement: the version increments atomically, so two concurrent changes never share a version.
    private const string UpsertSql = """
        INSERT INTO zaghlol.feature_flags AS f (key, enabled, rules, version, updated_at, updated_by)
        VALUES (@key, @value, COALESCE(@rules, '{}'::jsonb), 1, @now, @operator)
        ON CONFLICT (key) DO UPDATE SET
          enabled = EXCLUDED.enabled,
          rules = COALESCE(@rules, f.rules),
          version = f.version + 1,
          updated_at = EXCLUDED.updated_at,
          updated_by = EXCLUDED.updated_by
        RETURNING f.enabled, f.rules::text, f.version, f.updated_at
        """;

    // `at` is left to the database clock: the audit_log RLS policy only accepts rows stamped now.
    private const string AuditSql = """
        INSERT INTO zaghlol.audit_log (operator_id, action, target, details)
        VALUES (@operator, @action, @target, @details)
        """;

    public async Task<FlagState?> GetAsync(string key, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        var row = await db.FeatureFlags.AsNoTracking().SingleOrDefaultAsync(f => f.Key == key, cancellationToken);
        return row is null ? null : FlagRows.ToState(row);
    }

    public async Task<FlagState> UpsertAsync(
        string key,
        bool value,
        FlagRules? rules,
        Guid operatorId,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        FlagState state;
        await using (var upsert = new NpgsqlCommand(UpsertSql, connection, transaction))
        {
            upsert.Parameters.AddWithValue("key", key);
            upsert.Parameters.AddWithValue("value", value);
            upsert.Parameters.Add(new NpgsqlParameter("rules", NpgsqlDbType.Jsonb)
            {
                Value = rules is null ? DBNull.Value : (object)FlagRulesJson.Serialize(rules),
            });
            upsert.Parameters.AddWithValue("now", now.ToUniversalTime());
            upsert.Parameters.AddWithValue("operator", operatorId);

            await using var reader = await upsert.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                throw new InvalidOperationException("The flag upsert returned no row.");
            }

            state = new FlagState(
                key,
                reader.GetBoolean(0),
                FlagRulesJson.Parse(reader.GetString(1)),
                reader.GetInt32(2),
                reader.GetFieldValue<DateTimeOffset>(3));
        }

        await using (var audit = new NpgsqlCommand(AuditSql, connection, transaction))
        {
            audit.Parameters.AddWithValue("operator", operatorId);
            audit.Parameters.AddWithValue("action", AuditAction);
            audit.Parameters.AddWithValue("target", "flag:" + key);
            audit.Parameters.Add(new NpgsqlParameter("details", NpgsqlDbType.Jsonb) { Value = AuditDetails(state) });
            await audit.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return state;
    }

    /// <summary>The audit payload: the flag's new value, version and rules. Never an e-mail, an order ID or free text.</summary>
    internal static string AuditDetails(FlagState state)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteBoolean("value", state.Value);
            writer.WriteNumber("version", state.Version);
            writer.WritePropertyName("rules");
            writer.WriteRawValue(FlagRulesJson.Serialize(state.Rules));
            writer.WriteEndObject();
        }

        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }
}

/// <summary><c>feature_flags</c> on the App login (<c>app_rw</c>, SELECT only): what the sync response is built from.</summary>
internal sealed class FlagReader(IAppDbContextFactory contexts) : IFlagReader
{
    public async Task<IReadOnlyList<FlagState>> ListAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        var rows = await db.FeatureFlags.AsNoTracking().ToListAsync(cancellationToken);
        return rows.Select(FlagRows.ToState).ToList();
    }
}

internal static class FlagRows
{
    public static FlagState ToState(FeatureFlag row) =>
        new(row.Key, row.Enabled, FlagRulesJson.Parse(row.Rules), row.Version, row.UpdatedAt);
}
