using System.Data;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Infrastructure.Seats;

/// <summary>
/// <see cref="ISeatStore"/> over a caller's open connection and transaction (T-184 design note §1–§2). Every statement runs in
/// that transaction; nothing here begins, commits or rolls back. Infrastructure callers that already hold an Npgsql
/// transaction (T-132's verify writer) construct it directly; Application callers use <see cref="ISeatTransactionFactory"/>.
/// </summary>
public sealed class NpgsqlSeatStore(NpgsqlConnection connection, NpgsqlTransaction transaction) : ISeatStore
{
    private const string InstallKeySql = "SELECT seat_key_hash, seat_key_trusted FROM zaghlol.installs WHERE id = @id";

    private const string RegisterSql = """
        UPDATE zaghlol.installs SET seat_key_hash = @hash, seat_key_trusted = seat_key_trusted OR @trusted
        WHERE id = @id AND seat_key_hash IS NULL
        """;

    private const string TrustSql = """
        UPDATE zaghlol.installs SET seat_key_trusted = true WHERE id = @id AND seat_key_hash = @hash
        """;

    private const string PurchaseSql = """
        SELECT state, install_id, account_id, attach_reclaim_used_at FROM zaghlol.purchases WHERE id = @id
        """;

    private const string SeatSql = """
        SELECT install_id, proof, bound_at, last_moved_at, next_move_at, device_key_hash, device_key_trusted, recent_rebinds
        FROM zaghlol.purchase_seats WHERE purchase_id = @id
        """;

    private const string InheritSql = """
        UPDATE zaghlol.purchases s
        SET account_id = CASE WHEN s.account_id IS NULL THEN p.account_id ELSE s.account_id END,
            account_linked_by = CASE WHEN s.account_id IS NULL THEN p.account_linked_by ELSE s.account_linked_by END,
            attach_reclaim_used_at = COALESCE(s.attach_reclaim_used_at, p.attach_reclaim_used_at)
        FROM zaghlol.purchases p
        WHERE s.id = @successor AND p.id = @predecessor
        """;

    private const string InsertSeatSql = """
        INSERT INTO zaghlol.purchase_seats
            (purchase_id, install_id, proof, bound_at, last_moved_at, next_move_at, device_key_hash, device_key_trusted, recent_rebinds)
        VALUES (@id, @holder, @proof, @bound, @last, @next, @hash, @trusted, @rebinds)
        """;

    private const string UpdateSeatSql = """
        UPDATE zaghlol.purchase_seats
        SET install_id = @holder, proof = @proof, bound_at = @bound, last_moved_at = @last, next_move_at = @next,
            device_key_hash = @hash, device_key_trusted = @trusted, recent_rebinds = @rebinds
        WHERE purchase_id = @id
        """;

    // The Admin login (support move) has no grant on recent_rebinds and never writes it.
    private const string UpdateSeatKeepRebindsSql = """
        UPDATE zaghlol.purchase_seats
        SET install_id = @holder, proof = @proof, bound_at = @bound, last_moved_at = @last, next_move_at = @next,
            device_key_hash = @hash, device_key_trusted = @trusted
        WHERE purchase_id = @id
        """;

    private const string ReclaimSql = """
        UPDATE zaghlol.purchases SET attach_reclaim_used_at = @at WHERE id = @id AND attach_reclaim_used_at IS NULL
        """;

    private const string LinkedSql = """
        SELECT EXISTS (SELECT 1 FROM zaghlol.account_installs WHERE account_id = @account AND install_id = @install)
        """;

    private const string ClaimantsSql = """
        SELECT install_id, claimed_at, channel, device_key_hash FROM zaghlol.seat_claimants WHERE purchase_id = @id
        """;

    private const string UpsertClaimantSql = """
        INSERT INTO zaghlol.seat_claimants (purchase_id, install_id, claimed_at, channel, device_key_hash)
        VALUES (@id, @install, @at, @channel, @hash)
        ON CONFLICT (purchase_id, install_id) DO UPDATE
        SET claimed_at = EXCLUDED.claimed_at, channel = EXCLUDED.channel,
            device_key_hash = COALESCE(EXCLUDED.device_key_hash, seat_claimants.device_key_hash)
        """;

    private const string DeleteClaimantSql = "DELETE FROM zaghlol.seat_claimants WHERE purchase_id = @id AND install_id = @install";

    private const string EventSql = """
        INSERT INTO zaghlol.purchase_events (id, purchase_id, from_state, to_state, cause, occurred_at)
        VALUES (@id, @purchase, @state, @state, @cause, @at)
        """;

    public Task<InstallSeatKey?> ReadInstallSeatKeyAsync(Guid installId, CancellationToken cancellationToken) =>
        InstallKeyAsync(InstallKeySql, installId, cancellationToken);

    public Task<InstallSeatKey?> LockInstallSeatKeyAsync(Guid installId, CancellationToken cancellationToken) =>
        InstallKeyAsync(InstallKeySql + " FOR UPDATE", installId, cancellationToken);

    public async Task<bool> RegisterInstallSeatKeyAsync(Guid installId, InstallKeyHash hash, bool trusted, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(hash);
        await using var command = Command(RegisterSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
        command.Parameters.Add(new("hash", NpgsqlDbType.Bytea) { Value = hash.ToStorage() });
        command.Parameters.Add(new("trusted", NpgsqlDbType.Boolean) { Value = trusted });
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }

    public async Task<bool> TrustInstallSeatKeyAsync(Guid installId, InstallKeyHash hash, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(hash);
        await using var command = Command(TrustSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
        command.Parameters.Add(new("hash", NpgsqlDbType.Bytea) { Value = hash.ToStorage() });
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }

    public Task<SeatSnapshot?> LockAsync(Guid purchaseId, CancellationToken cancellationToken) =>
        SnapshotAsync(purchaseId, " FOR UPDATE", cancellationToken);

    public Task<SeatSnapshot?> ReadPredecessorAsync(Guid purchaseId, CancellationToken cancellationToken) =>
        SnapshotAsync(purchaseId, " FOR SHARE", cancellationToken);

    public async Task InheritAccountAsync(Guid successorId, Guid predecessorId, CancellationToken cancellationToken)
    {
        await using var command = Command(InheritSql);
        command.Parameters.Add(new("successor", NpgsqlDbType.Uuid) { Value = successorId });
        command.Parameters.Add(new("predecessor", NpgsqlDbType.Uuid) { Value = predecessorId });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task SaveSeatAsync(SeatRow row, bool insert, bool writeRebinds, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(row);
        if (insert && !writeRebinds)
        {
            throw new ArgumentException("An inserted seat row always carries recent_rebinds.", nameof(writeRebinds));
        }

        await using var command = Command(insert ? InsertSeatSql : writeRebinds ? UpdateSeatSql : UpdateSeatKeepRebindsSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = row.PurchaseId });
        command.Parameters.Add(new("holder", NpgsqlDbType.Uuid) { Value = (object?)row.Holder ?? DBNull.Value });
        command.Parameters.Add(new("proof", NpgsqlDbType.Text) { Value = row.Proof is { } proof ? SeatDbText.Proof(proof) : DBNull.Value });
        command.Parameters.Add(new("bound", NpgsqlDbType.TimestampTz) { Value = Utc(row.BoundAt) });
        command.Parameters.Add(new("last", NpgsqlDbType.TimestampTz) { Value = Utc(row.LastMovedAt) });
        command.Parameters.Add(new("next", NpgsqlDbType.TimestampTz) { Value = Utc(row.NextMoveAt) });
        command.Parameters.Add(new("hash", NpgsqlDbType.Bytea) { Value = (object?)row.DeviceKeyHash?.ToStorage() ?? DBNull.Value });
        command.Parameters.Add(new("trusted", NpgsqlDbType.Boolean) { Value = row.DeviceKeyTrusted });
        if (writeRebinds)
        {
            command.Parameters.Add(new("rebinds", NpgsqlDbType.Array | NpgsqlDbType.TimestampTz)
            {
                Value = row.RecentRebinds.Select(r => r.UtcDateTime).ToArray(),
            });
        }

        if (await command.ExecuteNonQueryAsync(cancellationToken) != 1)
        {
            throw new InvalidOperationException("The seat row was not written.");
        }
    }

    public async Task<bool> MarkAttachReclaimUsedAsync(Guid purchaseId, DateTimeOffset at, CancellationToken cancellationToken)
    {
        await using var command = Command(ReclaimSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
        command.Parameters.Add(new("at", NpgsqlDbType.TimestampTz) { Value = at.ToUniversalTime() });
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }

    public async Task<bool> IsLinkedToAccountAsync(Guid installId, Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = Command(LinkedSql);
        command.Parameters.Add(new("account", NpgsqlDbType.Uuid) { Value = accountId });
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    public async Task<IReadOnlyList<SeatClaimantRow>> ReadClaimantsAsync(Guid purchaseId, CancellationToken cancellationToken)
    {
        await using var command = Command(ClaimantsSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<SeatClaimantRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new SeatClaimantRow(
                reader.GetGuid(0),
                reader.GetFieldValue<DateTimeOffset>(1),
                SeatDbText.ParseChannel(reader.GetString(2)),
                reader.IsDBNull(3) ? null : SeatKeyHash.FromStored(reader.GetFieldValue<byte[]>(3))));
        }

        return rows;
    }

    public async Task UpsertClaimantAsync(Guid purchaseId, SeatClaimantRow row, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(row);
        await using var command = Command(UpsertClaimantSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = row.InstallId });
        command.Parameters.Add(new("at", NpgsqlDbType.TimestampTz) { Value = row.ClaimedAt.ToUniversalTime() });
        command.Parameters.Add(new("channel", NpgsqlDbType.Text) { Value = SeatDbText.Channel(row.Channel) });
        command.Parameters.Add(new("hash", NpgsqlDbType.Bytea) { Value = (object?)row.DeviceKeyHash?.ToStorage() ?? DBNull.Value });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeleteClaimantAsync(Guid purchaseId, Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Command(DeleteClaimantSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
        command.Parameters.Add(new("install", NpgsqlDbType.Uuid) { Value = installId });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task WriteEventAsync(Guid purchaseId, StoredPurchaseState state, string cause, DateTimeOffset at, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrEmpty(cause);
        await using var command = Command(EventSql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = Guid.CreateVersion7() });
        command.Parameters.Add(new("purchase", NpgsqlDbType.Uuid) { Value = purchaseId });
        command.Parameters.Add(new("state", NpgsqlDbType.Text) { Value = PurchaseDbText.State(state) });
        command.Parameters.Add(new("cause", NpgsqlDbType.Text) { Value = cause });
        command.Parameters.Add(new("at", NpgsqlDbType.TimestampTz) { Value = at.ToUniversalTime() });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static object Utc(DateTimeOffset? value) => value is { } v ? v.ToUniversalTime() : DBNull.Value;

    private async Task<InstallSeatKey?> InstallKeyAsync(string sql, Guid installId, CancellationToken cancellationToken)
    {
        await using var command = Command(sql);
        command.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = installId });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new InstallSeatKey(
            reader.IsDBNull(0) ? null : InstallKeyHash.FromStored(reader.GetFieldValue<byte[]>(0)),
            reader.GetBoolean(1));
    }

    private async Task<SeatSnapshot?> SnapshotAsync(Guid purchaseId, string lockClause, CancellationToken cancellationToken)
    {
        StoredPurchaseState state;
        Guid? buyer;
        Guid? account;
        DateTimeOffset? reclaim;
        await using (var purchase = Command(PurchaseSql + lockClause))
        {
            purchase.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
            await using var reader = await purchase.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            state = PurchaseDbText.ParseState(reader.GetString(0));
            buyer = reader.IsDBNull(1) ? null : reader.GetGuid(1);
            account = reader.IsDBNull(2) ? null : reader.GetGuid(2);
            reclaim = reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3);
        }

        await using var seat = Command(SeatSql + lockClause);
        seat.Parameters.Add(new("id", NpgsqlDbType.Uuid) { Value = purchaseId });
        await using var row = await seat.ExecuteReaderAsync(cancellationToken);
        if (!await row.ReadAsync(cancellationToken))
        {
            return new SeatSnapshot(purchaseId, state, buyer, account, reclaim, false, null, null, null, null, null, null, false, []);
        }

        return new SeatSnapshot(
            purchaseId,
            state,
            buyer,
            account,
            reclaim,
            SeatExists: true,
            Holder: row.IsDBNull(0) ? null : row.GetGuid(0),
            Proof: row.IsDBNull(1) ? null : SeatDbText.ParseProof(row.GetString(1)),
            BoundAt: Time(row, 2),
            LastMovedAt: Time(row, 3),
            NextMoveAt: Time(row, 4),
            DeviceKeyHash: row.IsDBNull(5) ? null : SeatKeyHash.FromStored(row.GetFieldValue<byte[]>(5)),
            DeviceKeyTrusted: row.GetBoolean(6),
            RecentRebinds: [.. row.GetFieldValue<DateTime[]>(7).Select(d => new DateTimeOffset(DateTime.SpecifyKind(d, DateTimeKind.Utc)))]);
    }

    private static DateTimeOffset? Time(NpgsqlDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetFieldValue<DateTimeOffset>(ordinal);

    private NpgsqlCommand Command(string sql) => new(sql, connection, transaction);
}

/// <summary>The database text of the seat enums (backend-schema CHECK values).</summary>
internal static class SeatDbText
{
    public static string Proof(SeatProofKind proof) => proof switch
    {
        SeatProofKind.Binding => "binding",
        SeatProofKind.Attested => "attested",
        SeatProofKind.Basic => "basic",
        SeatProofKind.Account => "account",
        SeatProofKind.Support => "support",
        SeatProofKind.Device => "device",
        _ => throw new ArgumentOutOfRangeException(nameof(proof)),
    };

    public static SeatProofKind ParseProof(string text) => text switch
    {
        "binding" => SeatProofKind.Binding,
        "attested" => SeatProofKind.Attested,
        "basic" => SeatProofKind.Basic,
        "account" => SeatProofKind.Account,
        "support" => SeatProofKind.Support,
        "device" => SeatProofKind.Device,
        _ => throw new InvalidOperationException("Unknown purchase_seats.proof value."),
    };

    public static string Channel(SeatClaimantChannel channel) => channel switch
    {
        SeatClaimantChannel.Restore => "restore",
        SeatClaimantChannel.SignIn => "signin",
        SeatClaimantChannel.Verify => "verify",
        _ => throw new ArgumentOutOfRangeException(nameof(channel)),
    };

    public static SeatClaimantChannel ParseChannel(string text) => text switch
    {
        "restore" => SeatClaimantChannel.Restore,
        "signin" => SeatClaimantChannel.SignIn,
        "verify" => SeatClaimantChannel.Verify,
        _ => throw new InvalidOperationException("Unknown seat_claimants.channel value."),
    };
}

/// <summary>One READ COMMITTED transaction on the App or Admin login; rolled back on dispose unless committed.</summary>
internal sealed class SeatTransactionFactory(IServiceProvider services) : ISeatTransactionFactory
{
    public async Task<ISeatTransaction> BeginAsync(SeatLogin login, CancellationToken cancellationToken)
    {
        var role = login switch
        {
            SeatLogin.App => DatabaseRole.App,
            SeatLogin.Support => DatabaseRole.Admin,
            _ => throw new ArgumentOutOfRangeException(nameof(login)),
        };
        var source = services.GetRequiredKeyedService<NpgsqlDataSource>(role);
        var connection = await source.OpenConnectionAsync(cancellationToken);
        try
        {
            var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
            return new SeatTransaction(connection, transaction);
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private sealed class SeatTransaction(NpgsqlConnection connection, NpgsqlTransaction transaction) : ISeatTransaction
    {
        public ISeatStore Seats { get; } = new NpgsqlSeatStore(connection, transaction);

        public Task CommitAsync(CancellationToken cancellationToken) => transaction.CommitAsync(cancellationToken);

        public async ValueTask DisposeAsync()
        {
            await transaction.DisposeAsync();
            await connection.DisposeAsync();
        }
    }
}

/// <summary><c>zaghlol.seat.change{channel, kind}</c> and the <c>seat_rebind</c> alert (purchase UUID only).</summary>
internal sealed class SeatTelemetry(ZaghlolMetrics metrics, IAlertSignal alerts) : ISeatTelemetry
{
    public void Changed(string channel, string kind) => metrics.SeatChanged(channel, kind);

    public void RebindOverCap(Guid purchaseId) => alerts.Raise(AuditAlertRule.SeatRebindOverCap, purchaseId);
}

public static class SeatsServiceCollectionExtensions
{
    /// <summary>
    /// The seat service (T-184): <see cref="SeatService"/>, its telemetry and <see cref="ISeatTransactionFactory"/>. Call after
    /// <c>AddZaghlolSeatKeys</c> and <c>AddZaghlolDatabase</c> (App and/or Admin).
    /// </summary>
    public static IServiceCollection AddZaghlolSeats(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<IAlertSignal, AlertSignal>();
        services.TryAddSingleton<ISeatTelemetry, SeatTelemetry>();
        services.TryAddSingleton<ISeatTransactionFactory, SeatTransactionFactory>();
        services.TryAddSingleton<SeatService>();
        return services;
    }
}
