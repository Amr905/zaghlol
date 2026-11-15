using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Accounts;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Accounts;

/// <summary><c>pending_apple_revocations</c> on the Worker login (<c>worker_rw</c>: SELECT, DELETE and UPDATE of the two retry columns).</summary>
internal sealed class PendingAppleRevocationStore(IServiceProvider services) : IPendingAppleRevocationStore
{
    private const string DeleteExpiredSql = "DELETE FROM zaghlol.pending_apple_revocations WHERE expires_at <= @now";

    private const string ListSql = """
        SELECT id, sealed_blob, attempts FROM zaghlol.pending_apple_revocations
        WHERE next_attempt_at <= @now AND expires_at > @now
        ORDER BY next_attempt_at LIMIT @limit
        """;

    private const string DeleteSql = "DELETE FROM zaghlol.pending_apple_revocations WHERE id = @id";

    private const string DeferSql = "UPDATE zaghlol.pending_apple_revocations SET attempts = @attempts, next_attempt_at = @next WHERE id = @id";

    private NpgsqlDataSource Source => services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.Worker);

    public async Task<int> DeleteExpiredAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(DeleteExpiredSql);
        command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        return await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<PendingAppleRevocation>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(ListSql);
        command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        command.Parameters.Add(new("limit", NpgsqlDbType.Integer) { Value = limit });
        var rows = new List<PendingAppleRevocation>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            rows.Add(new PendingAppleRevocation(reader.GetGuid(0), reader.GetFieldValue<byte[]>(1), reader.GetInt32(2)));
        }

        return rows;
    }

    public async Task DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(DeleteSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = id });
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task DeferAsync(Guid id, int attempts, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(DeferSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = id });
        command.Parameters.Add(new("attempts", NpgsqlDbType.Integer) { Value = attempts });
        command.Parameters.Add(new("next", NpgsqlDbType.TimestampTz) { Value = nextAttemptAt.ToUniversalTime() });
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }
}
