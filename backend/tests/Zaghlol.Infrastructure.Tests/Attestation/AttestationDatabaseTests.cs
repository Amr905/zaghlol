using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Attestation;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Attestation;

/// <summary>PostgreSQL 17 with the App login, the seat transaction factory and the Play Integrity replay guard (T-181).</summary>
public sealed class AttestationDatabaseFixture : IAsyncLifetime
{
    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public ServiceProvider Services { get; private set; } = null!;

    public ISeatTransactionFactory Transactions { get; private set; } = null!;

    public SeatDb Db => new(Database);

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:App"] = Database.Api })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App);
        Services = collection.BuildServiceProvider();
        Transactions = new SeatTransactionFactory(Services);
    }

    public async Task DisposeAsync()
    {
        if (Services is not null)
        {
            await Services.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }
}

/// <summary>
/// <c>app_attest_keys</c> and <c>replay_guard</c> on the real App login: registration rules, the counter update inside the
/// caller's transaction (R5-6) and single use of a Play Integrity token.
/// </summary>
public sealed class AttestationDatabaseTests(AttestationDatabaseFixture fixture) : IClassFixture<AttestationDatabaseFixture>, IDisposable
{
    private static readonly byte[] ClientDataHash = SHA256.HashData("client data"u8);
    private readonly AppAttestTestSigner signer = new();

    public void Dispose() => signer.Dispose();

    [Fact]
    public async Task AValidAttestationRegistersTheKeyToTheCallingInstallAndAnotherInstallIsRefused()
    {
        var install = await fixture.Db.InstallAsync();
        var other = await fixture.Db.InstallAsync();
        using var key = AppAttestTestSigner.NewKey();

        Assert.True((await RegisterAsync(install, key)).IsVerified);
        var refused = await RegisterAsync(other, key);

        Assert.Equal(AttestationFailure.KeyUnknown, refused.Failure);
        Assert.Equal((install.Value, 0L, "production"), (await ReadKeyAsync(key.KeyId))!.Value);
        Assert.Null(await ReadInstallKeyAsync(other));
    }

    [Fact]
    public async Task ReAttestReplacesTheInstallsKeyAndADeletedInstallRegistersNothing()
    {
        var install = await fixture.Db.InstallAsync();
        using var first = AppAttestTestSigner.NewKey();
        using var second = AppAttestTestSigner.NewKey();
        await RegisterAsync(install, first);
        await RegisterAsync(install, second);
        Assert.Equal(second.KeyId, await ReadInstallKeyAsync(install));
        Assert.Null(await ReadKeyAsync(first.KeyId));

        var tombstoned = await fixture.Db.InstallAsync();
        await ExecAsync("UPDATE zaghlol.installs SET deleted_at = now() WHERE id = @a", tombstoned.Value);
        using var third = AppAttestTestSigner.NewKey();
        Assert.Equal(AttestationFailure.KeyUnknown, (await RegisterAsync(tombstoned, third)).Failure);
    }

    /// <summary>Core safety property (negative proof 3): the counter update rolls back with the caller's transaction.</summary>
    [Fact]
    public async Task TheCounterUpdateRollsBackWithTheCallersTransaction()
    {
        var install = await fixture.Db.InstallAsync();
        using var key = AppAttestTestSigner.NewKey();
        await RegisterAsync(install, key);

        await using (var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, default))
        {
            var verified = await Verifier().VerifyAssertionAsync(tx.AppAttestKeys, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 7), ClientDataHash, default);
            Assert.True(verified.IsVerified);

            // T-185 hits SEAT_KEY_MISMATCH here and disposes without committing.
        }

        Assert.Equal(0L, (await ReadKeyAsync(key.KeyId))!.Value.SignCount);

        await using (var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, default))
        {
            Assert.True((await Verifier().VerifyAssertionAsync(tx.AppAttestKeys, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 7), ClientDataHash, default)).IsVerified);
            await tx.CommitAsync(default);
        }

        Assert.Equal(7L, (await ReadKeyAsync(key.KeyId))!.Value.SignCount);
    }

    [Fact]
    public async Task APlayIntegrityTokenHashIsUsableOnceAndCommittedOnItsOwn()
    {
        var guard = new NpgsqlPlayIntegrityReplayGuard(fixture.Services);
        var hash = RandomNumberGenerator.GetBytes(32);
        var expires = DateTimeOffset.UtcNow.AddMinutes(15);

        // A surrounding transaction that rolls back does not undo the insert.
        await using (var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, default))
        {
            Assert.True(await guard.TryUseAsync(hash, expires, default));
        }

        Assert.False(await guard.TryUseAsync(hash, expires, default));
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT kind FROM zaghlol.replay_guard WHERE key_hash = @h", connection);
        command.Parameters.AddWithValue("h", hash);
        Assert.Equal("play_integrity", await command.ExecuteScalarAsync());
    }

    private AppAttestVerifier Verifier() =>
        new(new AppAttestOptions { AppId = AppAttestTestSigner.AppId, TestRoot = signer.RootDer }, TimeProvider.System, NullLogger<AppAttestVerifier>.Instance);

    private async Task<AttestationResult> RegisterAsync(InstallId install, AppAttestTestKey key)
    {
        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, default);
        var result = await Verifier().RegisterAttestationAsync(tx.AppAttestKeys, install, key.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default);
        await tx.CommitAsync(default);
        return result;
    }

    private async Task<(Guid Install, long SignCount, string Environment)?> ReadKeyAsync(byte[] keyId)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT install_id, sign_count, environment FROM zaghlol.app_attest_keys WHERE key_id = @k", connection);
        command.Parameters.AddWithValue("k", keyId);
        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? (reader.GetGuid(0), reader.GetInt64(1), reader.GetString(2)) : null;
    }

    private async Task<byte[]?> ReadInstallKeyAsync(InstallId install)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT key_id FROM zaghlol.app_attest_keys WHERE install_id = @i", connection);
        command.Parameters.AddWithValue("i", install.Value);
        return await command.ExecuteScalarAsync() as byte[];
    }

    private async Task ExecAsync(string sql, Guid id)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("a", id);
        await command.ExecuteNonQueryAsync();
    }
}
