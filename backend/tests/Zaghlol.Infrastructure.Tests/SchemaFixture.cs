using Npgsql;
using NpgsqlTypes;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>One migrated PostgreSQL 17 shared by the schema test classes (they run one after another).</summary>
public sealed class SchemaFixture : IAsyncLifetime
{
    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public async Task InitializeAsync() => Database = await ZaghlolTestDatabase.StartAsync();

    public async Task DisposeAsync()
    {
        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }
}

[CollectionDefinition(Name)]
public sealed class SchemaCollection : ICollectionFixture<SchemaFixture>
{
    public const string Name = "schema";
}

/// <summary>A <c>jsonb</c> parameter value.</summary>
public sealed record Jsonb(string Json);

/// <summary>Small helpers for raw SQL against the test database.</summary>
public static class Db
{
    public static async Task<NpgsqlConnection> OpenAsync(string connectionString)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        return connection;
    }

    public static async Task<List<object?[]>> QueryAsync(string connectionString, string sql, params object?[] parameters)
    {
        await using var connection = await OpenAsync(connectionString);
        await using var command = Command(connection, sql, parameters);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<object?[]>();
        while (await reader.ReadAsync())
        {
            var row = new object?[reader.FieldCount];
            for (var i = 0; i < row.Length; i++)
            {
                row[i] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }

            rows.Add(row);
        }

        return rows;
    }

    public static async Task<object?> ScalarAsync(string connectionString, string sql, params object?[] parameters)
    {
        await using var connection = await OpenAsync(connectionString);
        await using var command = Command(connection, sql, parameters);
        var value = await command.ExecuteScalarAsync();
        return value is DBNull ? null : value;
    }

    public static async Task<int> ExecuteAsync(string connectionString, string sql, params object?[] parameters)
    {
        await using var connection = await OpenAsync(connectionString);
        await using var command = Command(connection, sql, parameters);
        return await command.ExecuteNonQueryAsync();
    }

    /// <summary>Inserts one row into <c>zaghlol.&lt;table&gt;</c> with positional parameters.</summary>
    public static async Task InsertAsync(string connectionString, string table, IReadOnlyDictionary<string, object?> values)
    {
        var columns = values.Keys.ToList();
        var placeholders = columns.Select((_, i) => $"${i + 1}");
        var sql = $"INSERT INTO zaghlol.{table} ({string.Join(", ", columns)}) VALUES ({string.Join(", ", placeholders)})";
        await ExecuteAsync(connectionString, sql, [.. columns.Select(c => values[c])]);
    }

    public static NpgsqlCommand Command(NpgsqlConnection connection, string sql, params object?[] parameters)
    {
        var command = new NpgsqlCommand(sql, connection);
        foreach (var value in parameters)
        {
            command.Parameters.Add(value switch
            {
                null => new NpgsqlParameter { Value = DBNull.Value },
                Jsonb json => new NpgsqlParameter { Value = json.Json, NpgsqlDbType = NpgsqlDbType.Jsonb },
                _ => new NpgsqlParameter { Value = value },
            });
        }

        return command;
    }
}
