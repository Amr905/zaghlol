using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Attestation;

/// <summary>
/// <see cref="IAppAttestKeyStore"/> over a caller's open connection and transaction (T-181 design note §4–§5). Nothing here
/// begins, commits or rolls back: a rollback by the caller (T-185 on <c>SEAT_KEY_MISMATCH</c>, R5-6) undoes the counter update
/// and the registration.
/// </summary>
public sealed class NpgsqlAppAttestKeyStore(NpgsqlConnection connection, NpgsqlTransaction transaction) : IAppAttestKeyStore
{
    private const string LockKeySql = """
        SELECT key_id, public_key, sign_count FROM zaghlol.app_attest_keys WHERE install_id = @install FOR UPDATE
        """;

    private const string LockInstallSql = "SELECT 1 FROM zaghlol.installs WHERE id = @install AND deleted_at IS NULL FOR UPDATE";

    private const string OwnerSql = "SELECT install_id FROM zaghlol.app_attest_keys WHERE key_id = @key";

    private const string DeleteSql = "DELETE FROM zaghlol.app_attest_keys WHERE install_id = @install";

    private const string InsertSql = """
        INSERT INTO zaghlol.app_attest_keys (key_id, install_id, public_key, sign_count, environment)
        VALUES (@key, @install, @public, 0, @environment)
        ON CONFLICT (key_id) DO NOTHING
        """;

    private const string CounterSql = """
        UPDATE zaghlol.app_attest_keys SET sign_count = @count WHERE install_id = @install AND key_id = @key
        """;

    public async Task<AppAttestKeyRow?> LockAsync(InstallId installId, CancellationToken cancellationToken)
    {
        await using var command = Command(LockKeySql);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, installId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new AppAttestKeyRow(reader.GetFieldValue<byte[]>(0), reader.GetFieldValue<byte[]>(1), reader.GetInt64(2));
    }

    public async Task<AppAttestRegistration> RegisterAsync(
        InstallId installId,
        byte[] keyId,
        byte[] publicKey,
        bool development,
        CancellationToken cancellationToken)
    {
        // The install row lock serialises registrations of one install; a vanished install registers nothing.
        await using (var lockInstall = Command(LockInstallSql))
        {
            lockInstall.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, installId.Value);
            if (await lockInstall.ExecuteScalarAsync(cancellationToken) is null)
            {
                return AppAttestRegistration.Refused;
            }
        }

        await using (var owner = Command(OwnerSql))
        {
            owner.Parameters.AddWithValue("key", NpgsqlDbType.Bytea, keyId);
            if (await owner.ExecuteScalarAsync(cancellationToken) is Guid holder)
            {
                // Same install: keep the row (never reset the counter to 0 for a replayed attestationObject).
                return holder == installId.Value ? AppAttestRegistration.AlreadyRegistered : AppAttestRegistration.Refused;
            }
        }

        await using (var delete = Command(DeleteSql))
        {
            delete.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, installId.Value);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        await using var insert = Command(InsertSql);
        insert.Parameters.AddWithValue("key", NpgsqlDbType.Bytea, keyId);
        insert.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, installId.Value);
        insert.Parameters.AddWithValue("public", NpgsqlDbType.Bytea, publicKey);
        insert.Parameters.AddWithValue("environment", NpgsqlDbType.Text, development ? "development" : "production");

        // 0 rows: another install registered the same key ID concurrently and won.
        return await insert.ExecuteNonQueryAsync(cancellationToken) == 1 ? AppAttestRegistration.Registered : AppAttestRegistration.Refused;
    }

    public async Task<bool> UpdateCounterAsync(InstallId installId, byte[] keyId, long signCount, CancellationToken cancellationToken)
    {
        await using var command = Command(CounterSql);
        command.Parameters.AddWithValue("count", NpgsqlDbType.Bigint, signCount);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, installId.Value);
        command.Parameters.AddWithValue("key", NpgsqlDbType.Bytea, keyId);
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }

    private NpgsqlCommand Command(string sql) => new(sql, connection, transaction);
}
