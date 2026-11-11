using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Seats;

/// <summary>PostgreSQL 17 with the App and Admin logins and the seat transaction factory (T-184).</summary>
public sealed class SeatServiceFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public ISeatTransactionFactory Transactions { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:App"] = Database.Api,
                ["ConnectionStrings:Admin"] = Database.Admin,
            })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin);
        services = collection.BuildServiceProvider();
        Transactions = new SeatTransactionFactory(services);
    }

    public async Task DisposeAsync()
    {
        if (services is not null)
        {
            await services.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }
}

/// <summary>A clock the test moves by hand.</summary>
public sealed class ManualTime(DateTimeOffset start) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = start;

    public override DateTimeOffset GetUtcNow() => Now;
}

/// <summary>Records seat counters and alerts.</summary>
public sealed class RecordingSeatTelemetry : ISeatTelemetry
{
    public List<(string Channel, string Kind)> Changes { get; } = [];

    public List<Guid> Alerts { get; } = [];

    public void Changed(string channel, string kind)
    {
        lock (Changes)
        {
            Changes.Add((channel, kind));
        }
    }

    public void RebindOverCap(Guid purchaseId)
    {
        lock (Alerts)
        {
            Alerts.Add(purchaseId);
        }
    }
}

/// <summary>HMAC-SHA256 with <see cref="FakeKms.FixedSeatKey"/>, standing in for the KMS.</summary>
public sealed class FixedSeatMac : ISeatKeyMac
{
    public ValueTask<byte[]> MacAsync(ReadOnlyMemory<byte> input, CancellationToken cancellationToken) =>
        ValueTask.FromResult(HMACSHA256.HashData(FakeKms.FixedSeatKey, input.Span));
}

internal sealed class NullSeatKeyMetrics : ISeatKeyMetrics
{
    public void Proof(SeatOp op, SeatKeyRejection? rejection)
    {
    }

    public void ElementZero(SeatOp op, ElementZeroStatus status)
    {
    }
}

/// <summary>The seat row as stored.</summary>
public sealed record StoredSeat(
    Guid? Holder,
    string? Proof,
    DateTimeOffset? BoundAt,
    DateTimeOffset? LastMovedAt,
    DateTimeOffset? NextMoveAt,
    byte[]? DeviceKeyHash,
    bool DeviceKeyTrusted,
    DateTimeOffset[] RecentRebinds);

/// <summary>Seeding and reading as superuser; every seat change itself goes through the service on the real logins.</summary>
public sealed class SeatDb(ZaghlolTestDatabase database)
{
    public static InstallId NewInstallId() => InstallId.FromGuid(Guid.NewGuid());

    public async Task<InstallId> InstallAsync(string platform = "ios")
    {
        var id = NewInstallId();
        await ExecAsync(
            "INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@a, @b, @c, '1.0.0')",
            id.Value,
            RandomNumberGenerator.GetBytes(32),
            platform);
        return id;
    }

    public async Task<Guid> PurchaseAsync(InstallId? buyer = null, Guid? account = null, string state = "active")
    {
        var id = Guid.CreateVersion7();
        await ExecAsync(
            """
            INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, install_id, account_id, account_linked_by, state,
                                           environment, last_verified_at)
            VALUES (@a, 'google_play', 'zaghlol_gold_monthly', 'monthly', @b, @c::uuid, @d::uuid, CASE WHEN @d::uuid IS NULL THEN NULL ELSE 'signin' END,
                    @e, 'production', now())
            """,
            id,
            Guid.NewGuid().ToString("N"),
            (object?)buyer?.Value ?? DBNull.Value,
            (object?)account ?? DBNull.Value,
            state);
        return id;
    }

    public async Task<Guid> AccountAsync(params InstallId[] linked)
    {
        var id = Guid.CreateVersion7();
        await ExecAsync("INSERT INTO zaghlol.accounts (id, provider, provider_subject) VALUES (@a, 'google', @b)", id, Guid.NewGuid().ToString("N"));
        foreach (var install in linked)
        {
            await ExecAsync("INSERT INTO zaghlol.account_installs (account_id, install_id) VALUES (@a, @b)", id, install.Value);
        }

        return id;
    }

    public Task LinkPurchaseAsync(Guid purchase, Guid? account) => ExecAsync(
        "UPDATE zaghlol.purchases SET account_id = @b::uuid, account_linked_by = CASE WHEN @b::uuid IS NULL THEN NULL ELSE 'signin' END WHERE id = @a",
        purchase,
        (object?)account ?? DBNull.Value);

    public Task SetLinkedPurchaseAsync(Guid successor, Guid predecessor) => ExecAsync(
        "UPDATE zaghlol.purchases SET linked_purchase_token = (SELECT store_key FROM zaghlol.purchases WHERE id = @b) WHERE id = @a",
        successor,
        predecessor);

    /// <summary>Writes a seat row directly (the state a test starts from).</summary>
    public Task SeatAsync(
        Guid purchase,
        InstallId? holder,
        DateTimeOffset? nextMoveAt = null,
        byte[]? deviceKeyHash = null,
        bool trusted = false,
        DateTimeOffset[]? rebinds = null) => ExecAsync(
        """
        INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at, last_moved_at, next_move_at, device_key_hash,
                                            device_key_trusted, recent_rebinds)
        VALUES (@a, @b::uuid, CASE WHEN @b::uuid IS NULL THEN NULL ELSE 'attested' END, CASE WHEN @b::uuid IS NULL THEN NULL ELSE now() END,
                @c::timestamptz - interval '30 days', @c::timestamptz, @d::bytea, @e, @f)
        ON CONFLICT (purchase_id) DO UPDATE SET install_id = EXCLUDED.install_id, proof = EXCLUDED.proof, bound_at = EXCLUDED.bound_at,
            last_moved_at = EXCLUDED.last_moved_at, next_move_at = EXCLUDED.next_move_at, device_key_hash = EXCLUDED.device_key_hash,
            device_key_trusted = EXCLUDED.device_key_trusted, recent_rebinds = EXCLUDED.recent_rebinds
        """,
        purchase,
        (object?)holder?.Value ?? DBNull.Value,
        (object?)nextMoveAt?.UtcDateTime ?? DBNull.Value,
        (object?)deviceKeyHash ?? DBNull.Value,
        trusted,
        (rebinds ?? []).Select(r => r.UtcDateTime).ToArray());

    public Task TrustInstallKeyAsync(InstallId install) =>
        ExecAsync("UPDATE zaghlol.installs SET seat_key_trusted = true WHERE id = @a AND seat_key_hash IS NOT NULL", install.Value);

    public Task DeleteInstallAsync(InstallId install) => ExecAsync("DELETE FROM zaghlol.installs WHERE id = @a", install.Value);

    public Task DeleteAccountAsync(Guid account) => ExecAsync("DELETE FROM zaghlol.accounts WHERE id = @a", account);

    public Task AgeClaimantAsync(Guid purchase, InstallId install, DateTimeOffset claimedAt) => ExecAsync(
        "UPDATE zaghlol.seat_claimants SET claimed_at = @c WHERE purchase_id = @a AND install_id = @b",
        purchase,
        install.Value,
        claimedAt.UtcDateTime);

    public async Task<StoredSeat?> ReadSeatAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            """
            SELECT install_id, proof, bound_at, last_moved_at, next_move_at, device_key_hash, device_key_trusted, recent_rebinds
            FROM zaghlol.purchase_seats WHERE purchase_id = @a
            """,
            connection);
        command.Parameters.AddWithValue("a", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            return null;
        }

        return new StoredSeat(
            reader.IsDBNull(0) ? null : reader.GetGuid(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2),
            reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4),
            reader.IsDBNull(5) ? null : reader.GetFieldValue<byte[]>(5),
            reader.GetBoolean(6),
            [.. reader.GetFieldValue<DateTime[]>(7).Select(d => new DateTimeOffset(DateTime.SpecifyKind(d, DateTimeKind.Utc)))]);
    }

    public Task<List<string>> EventsAsync(Guid purchase) =>
        ListAsync<string>("SELECT cause FROM zaghlol.purchase_events WHERE purchase_id = @a ORDER BY occurred_at, id", purchase);

    public async Task<List<(Guid Install, DateTimeOffset ClaimedAt, string Channel, byte[]? Hash)>> ClaimantsAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT install_id, claimed_at, channel, device_key_hash FROM zaghlol.seat_claimants WHERE purchase_id = @a ORDER BY claimed_at",
            connection);
        command.Parameters.AddWithValue("a", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<(Guid, DateTimeOffset, string, byte[]?)>();
        while (await reader.ReadAsync())
        {
            rows.Add((reader.GetGuid(0), reader.GetFieldValue<DateTimeOffset>(1), reader.GetString(2), reader.IsDBNull(3) ? null : reader.GetFieldValue<byte[]>(3)));
        }

        return rows;
    }

    public async Task<(byte[]? Hash, bool Trusted)> InstallKeyAsync(InstallId install)
    {
        await using var connection = new NpgsqlConnection(database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT seat_key_hash, seat_key_trusted FROM zaghlol.installs WHERE id = @a", connection);
        command.Parameters.AddWithValue("a", install.Value);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.IsDBNull(0) ? null : reader.GetFieldValue<byte[]>(0), reader.GetBoolean(1));
    }

    public async Task<(Guid? Account, DateTimeOffset? Reclaim)> PurchaseAccountAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT account_id, attach_reclaim_used_at FROM zaghlol.purchases WHERE id = @a", connection);
        command.Parameters.AddWithValue("a", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.IsDBNull(0) ? null : reader.GetGuid(0), reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1));
    }

    private async Task<List<T>> ListAsync<T>(string sql, params object[] values)
    {
        await using var connection = new NpgsqlConnection(database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        Bind(command, values);
        await using var reader = await command.ExecuteReaderAsync();
        var list = new List<T>();
        while (await reader.ReadAsync())
        {
            list.Add(reader.GetFieldValue<T>(0));
        }

        return list;
    }

    private async Task ExecAsync(string sql, params object[] values)
    {
        await using var connection = new NpgsqlConnection(database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        Bind(command, values);
        await command.ExecuteNonQueryAsync();
    }

    private static void Bind(NpgsqlCommand command, object[] values)
    {
        for (var i = 0; i < values.Length; i++)
        {
            var name = ((char)('a' + i)).ToString();
            command.Parameters.Add(values[i] is DBNull
                ? new NpgsqlParameter(name, NpgsqlTypes.NpgsqlDbType.Unknown) { Value = DBNull.Value }
                : new NpgsqlParameter(name, values[i]));
        }
    }
}
