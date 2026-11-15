using System.Data;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Accounts;
using Zaghlol.Application.Seats;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Seats;

namespace Zaghlol.Infrastructure.Accounts;

internal static class AccountDbText
{
    public static string Provider(AccountProvider provider) => provider switch
    {
        AccountProvider.Google => "google",
        AccountProvider.Apple => "apple",
        _ => throw new ArgumentOutOfRangeException(nameof(provider)),
    };

    public static AccountProvider Provider(string text) => text switch
    {
        "google" => AccountProvider.Google,
        "apple" => AccountProvider.Apple,
        _ => throw new InvalidOperationException("Unknown accounts.provider value."),
    };
}

/// <summary>
/// The sign-in statements over the caller's open connection and transaction (T-135 design note). Everything is SQL with explicit
/// locks in the order installs, accounts, purchases (ascending ID), then the seat rows (<see cref="NpgsqlSeatStore"/>); nothing begins,
/// commits or rolls back here.
/// </summary>
internal sealed class NpgsqlAccountTxStore(NpgsqlConnection connection, NpgsqlTransaction transaction) : IAccountTxStore
{
    private const string LockInstallSql = "SELECT 1 FROM zaghlol.installs WHERE id = @id AND deleted_at IS NULL FOR UPDATE";

    private const string UpsertSql = """
        INSERT INTO zaghlol.accounts (id, provider, provider_subject, email, created_at, last_sign_in_at, apple_refresh_token_enc)
        VALUES (@id, @provider, @subject, @email, @now, @now, @enc)
        ON CONFLICT (provider, provider_subject) DO UPDATE
        SET last_sign_in_at = EXCLUDED.last_sign_in_at,
            email = COALESCE(EXCLUDED.email, zaghlol.accounts.email),
            apple_refresh_token_enc = COALESCE(EXCLUDED.apple_refresh_token_enc, zaghlol.accounts.apple_refresh_token_enc)
        RETURNING id
        """;

    private const string LinkedAccountsSql = "SELECT account_id FROM zaghlol.account_installs WHERE install_id = @install";

    private const string UnlinkInstallSql = "DELETE FROM zaghlol.account_installs WHERE install_id = @install";

    private const string LinkSql = """
        INSERT INTO zaghlol.account_installs (account_id, install_id, linked_at) VALUES (@account, @install, @now)
        ON CONFLICT (account_id, install_id) DO NOTHING
        """;

    private const string CountSql = "SELECT count(*) FROM zaghlol.account_installs WHERE account_id = @account";

    // D-54: only purchases with no account whose buying install is this one. Locked in ascending ID order first, so two requests
    // that touch the same purchases can't deadlock.
    private const string AttachSql = """
        WITH locked AS (
            SELECT id FROM zaghlol.purchases WHERE install_id = @install AND account_id IS NULL ORDER BY id FOR UPDATE)
        UPDATE zaghlol.purchases p SET account_id = @account, account_linked_by = 'signin'
        FROM locked WHERE p.id = locked.id
        RETURNING p.id
        """;

    private const string LockUnionSql = """
        SELECT id FROM zaghlol.purchases
        WHERE (install_id = @install AND account_id IS NULL) OR account_id = @account
        ORDER BY id FOR UPDATE
        """;

    private const string EntitlingSql = """
        SELECT id FROM zaghlol.purchases
        WHERE account_id = @account AND state IN ('active', 'in_grace', 'canceled_active') ORDER BY id
        """;

    public async Task<bool> LockInstallAsync(Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Command(LockInstallSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
        return await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false) is not null;
    }

    public async Task<Guid> UpsertAccountAsync(
        AccountProvider provider, string subject, string? email, byte[]? appleRefreshTokenSealed, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var command = Command(UpsertSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = Guid.NewGuid() });
        command.Parameters.Add(new("provider", NpgsqlDbType.Text) { Value = AccountDbText.Provider(provider) });
        command.Parameters.Add(new("subject", NpgsqlDbType.Text) { Value = subject });
        command.Parameters.Add(new("email", NpgsqlDbType.Text) { Value = (object?)email ?? DBNull.Value });
        command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        command.Parameters.Add(new("enc", NpgsqlDbType.Bytea) { Value = (object?)appleRefreshTokenSealed ?? DBNull.Value });
        return (Guid)(await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false))!;
    }

    public async Task<IReadOnlyList<Guid>> LinkedAccountsOfInstallAsync(Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Command(LinkedAccountsSql);
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        return await ReadIdsAsync(command, cancellationToken).ConfigureAwait(false);
    }

    public async Task UnlinkInstallAsync(Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Command(UnlinkInstallSql);
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task LinkAsync(Guid accountId, Guid installId, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var command = Command(LinkSql);
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<int> CountLinkedInstallsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = Command(CountSql);
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        return (int)(long)(await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false))!;
    }

    public async Task LockPurchasesAsync(Guid installId, Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = Command(LockUnionSql);
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        await ReadIdsAsync(command, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<Guid>> AttachBuyingPurchasesAsync(Guid installId, Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = Command(AttachSql);
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        return await ReadIdsAsync(command, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<Guid>> ListEntitlingPurchasesAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = Command(EntitlingSql);
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        return await ReadIdsAsync(command, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<IReadOnlyList<Guid>> ReadIdsAsync(NpgsqlCommand command, CancellationToken cancellationToken)
    {
        var ids = new List<Guid>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            ids.Add(reader.GetGuid(0));
        }

        ids.Sort();
        return ids;
    }

    private NpgsqlCommand Command(string sql) => new(sql, connection, transaction);
}

/// <summary>Single statements on the App login, outside a sign-in transaction (T-135 design note).</summary>
internal sealed class NpgsqlAccountStore(IServiceProvider services) : IAccountStore
{
    private const string PlatformSql = "SELECT platform FROM zaghlol.installs WHERE id = @id AND deleted_at IS NULL";

    private const string UnlinkSql = "DELETE FROM zaghlol.account_installs WHERE account_id = @account AND install_id = @install";

    private const string ReadSql = "SELECT provider, provider_subject, apple_refresh_token_enc FROM zaghlol.accounts WHERE id = @id";

    // The account row is locked first (the sign-in order: accounts before purchases), so a concurrent sign-in can't deadlock with this.
    private const string LockSql = "SELECT 1 FROM zaghlol.accounts WHERE id = @id FOR UPDATE";

    // FU-015: explicit statements, never a tracked graph (EF's client-side SetNull would null account_id without account_linked_by and
    // violate the CHECK). attach_reclaim_used_at is untouched: it is never cleared (D-58).
    private const string ClearPurchasesSql = """
        UPDATE zaghlol.purchases SET account_id = NULL, account_linked_by = NULL WHERE account_id = @id
        """;

    private const string LockPurchasesSql = "SELECT id FROM zaghlol.purchases WHERE account_id = @id ORDER BY id FOR UPDATE";

    private const string DeleteIdempotencySql = "DELETE FROM zaghlol.idempotency_records WHERE account_id = @id";

    private const string DeleteAccountSql = "DELETE FROM zaghlol.accounts WHERE id = @id";

    // Only the sealed blob and the times: no account, install or subject reference (Lead decision, T-135).
    private const string QueueRevocationSql = """
        INSERT INTO zaghlol.pending_apple_revocations (id, sealed_blob, created_at, next_attempt_at, expires_at)
        VALUES (@pid, @blob, @now, @next, @expires)
        """;

    private NpgsqlDataSource Source => services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);

    public async Task<string?> ReadInstallPlatformAsync(Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(PlatformSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
        return await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false) as string;
    }

    public async Task UnlinkInstallAsync(Guid accountId, Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(UnlinkSql);
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<AccountForDelete?> ReadForDeleteAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(ReadSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = accountId });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        if (!await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            return null;
        }

        return new AccountForDelete(
            AccountDbText.Provider(reader.GetString(0)),
            reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetFieldValue<byte[]>(2));
    }

    public async Task DeleteAccountAsync(Guid accountId, byte[]? pendingRevocationSealed, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var connection = await Source.OpenConnectionAsync(cancellationToken).ConfigureAwait(false);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken).ConfigureAwait(false);
        await using (var lockCommand = new NpgsqlCommand(LockSql, connection, transaction))
        {
            lockCommand.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = accountId });
            await lockCommand.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        }

        // Same global order as sign-in and restore: every purchase of the account locked in ascending ID before the UPDATE.
        await using (var orderCommand = new NpgsqlCommand(LockPurchasesSql, connection, transaction))
        {
            orderCommand.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = accountId });
            await orderCommand.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        }

        foreach (var sql in new[] { ClearPurchasesSql, DeleteIdempotencySql, DeleteAccountSql })
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = accountId });
            await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        }

        if (pendingRevocationSealed is not null)
        {
            await using var queue = new NpgsqlCommand(QueueRevocationSql, connection, transaction);
            queue.Parameters.Add(new("pid", NpgsqlDbType.Uuid) { Value = Guid.NewGuid() });
            queue.Parameters.Add(new("blob", NpgsqlDbType.Bytea) { Value = pendingRevocationSealed });
            queue.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
            queue.Parameters.Add(new("next", NpgsqlDbType.TimestampTz) { Value = (now + PendingAppleRevocationPolicy.FirstDelay).ToUniversalTime() });
            queue.Parameters.Add(new("expires", NpgsqlDbType.TimestampTz) { Value = (now + PendingAppleRevocationPolicy.Window).ToUniversalTime() });
            await queue.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        }

        await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
    }
}

/// <summary>One transaction with the seat and account statements on the App login.</summary>
internal sealed class AccountTransactionFactory(IServiceProvider services) : IAccountTransactionFactory
{
    public async Task<IAccountTransaction> BeginAsync(CancellationToken cancellationToken)
    {
        var source = services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);
        var connection = await source.OpenConnectionAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken).ConfigureAwait(false);
            return new AccountTransaction(connection, transaction);
        }
        catch
        {
            await connection.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }

    private sealed class AccountTransaction(NpgsqlConnection connection, NpgsqlTransaction transaction) : IAccountTransaction
    {
        public ISeatStore Seats { get; } = new NpgsqlSeatStore(connection, transaction);

        public IAccountTxStore Accounts { get; } = new NpgsqlAccountTxStore(connection, transaction);

        public Task CommitAsync(CancellationToken cancellationToken) => transaction.CommitAsync(cancellationToken);

        public async ValueTask DisposeAsync()
        {
            await transaction.DisposeAsync().ConfigureAwait(false);
            await connection.DisposeAsync().ConfigureAwait(false);
        }
    }
}

/// <summary>Single use of a sign-in nonce: a <c>replay_guard</c> row (hash only), committed on its own (R3-5).</summary>
internal sealed class NpgsqlIdTokenReplayGuard(IServiceProvider services) : IIdTokenReplayGuard
{
    private const string Sql = """
        INSERT INTO zaghlol.replay_guard (key_hash, kind, expires_at) VALUES (@hash, @kind, @expires)
        ON CONFLICT (key_hash) DO NOTHING
        """;

    public async Task<bool> TryUseAsync(AccountProvider provider, ReadOnlyMemory<byte> nonceClaimHash, DateTimeOffset expiresAt, CancellationToken cancellationToken)
    {
        var source = services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);
        await using var command = source.CreateCommand(Sql);
        command.Parameters.Add(new("hash", NpgsqlDbType.Bytea) { Value = nonceClaimHash.ToArray() });
        command.Parameters.Add(new("kind", NpgsqlDbType.Text) { Value = provider == AccountProvider.Google ? "signin_google" : "signin_apple" });
        command.Parameters.Add(new("expires", NpgsqlDbType.TimestampTz) { Value = expiresAt.ToUniversalTime() });
        return await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false) == 1;
    }
}
