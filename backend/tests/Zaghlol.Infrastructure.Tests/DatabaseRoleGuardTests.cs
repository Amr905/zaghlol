using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Zaghlol.Application.Health;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>SEC F11 (login guard) and CR#1 (readiness has its own pool) against the migrated database.</summary>
[Collection(SchemaGroup.Name)]
public class DatabaseRoleGuardTests(SchemaFixture fixture)
{
    public static TheoryData<string, DatabaseRole, string?> Logins => new()
    {
        { "zaghlol_api", DatabaseRole.App, null },
        { "zaghlol_admin", DatabaseRole.Admin, null },
        { "zaghlol_worker", DatabaseRole.Worker, null },
        { "migrator", DatabaseRole.App, DatabaseRoleGuard.RejectOwner },
        { "migrator", DatabaseRole.Worker, DatabaseRoleGuard.RejectOwner },
        { "zaghlol_admin", DatabaseRole.App, DatabaseRoleGuard.RejectWrongGroups },
        { "zaghlol_api", DatabaseRole.Admin, DatabaseRoleGuard.RejectWrongGroups },
        { "zaghlol_worker", DatabaseRole.App, DatabaseRoleGuard.RejectWrongGroups },
        { "zaghlol_ops_ro", DatabaseRole.App, DatabaseRoleGuard.RejectWrongGroups },
    };

    [Theory]
    [MemberData(nameof(Logins))]
    public async Task EachLoginIsAcceptedOnlyForItsOwnRole(string login, DatabaseRole role, string? expected)
    {
        await using var connection = await Db.OpenAsync(fixture.Database.For(login));

        Assert.Equal(expected, await DatabaseRoleGuard.CheckAsync(connection, role, CancellationToken.None));
    }

    [Fact]
    public async Task ASuperuserIsRejected()
    {
        await using var connection = await Db.OpenAsync(fixture.Database.Superuser);

        Assert.Equal(DatabaseRoleGuard.RejectPrivileged, await DatabaseRoleGuard.CheckAsync(connection, DatabaseRole.App, CancellationToken.None));
    }

    [Fact]
    public async Task TheGuardStopsTheHostWithANonZeroExitCodeWhenTheAppLoginIsTheMigrator()
    {
        var lifetime = new RecordingLifetime();
        await using var provider = Services(fixture.Database.Migrator, lifetime);
        var guard = provider.GetServices<IHostedService>().Single();
        Assert.Equal(0, provider.GetRequiredService<HostExitCode>().Value);

        await guard.StartAsync(CancellationToken.None);
        var stopped = await Task.WhenAny(lifetime.Stopped, Task.Delay(TimeSpan.FromSeconds(20)));
        await guard.StopAsync(CancellationToken.None);

        Assert.Same(lifetime.Stopped, stopped);
        Assert.Equal(HostExitCode.DatabaseLoginRejected, provider.GetRequiredService<HostExitCode>().Value);
    }

    [Fact]
    public async Task ASuperuserLoginThatSwitchedToTheApiRoleIsRejected()
    {
        // FU-019: `-c role=zaghlol_api` makes current_user the API role while session_user stays the superuser.
        var switched = new NpgsqlConnectionStringBuilder(fixture.Database.Superuser) { Options = "-c role=zaghlol_api" }.ConnectionString;
        await using var connection = await Db.OpenAsync(switched);
        await using (var who = new NpgsqlCommand("SELECT current_user::text", connection))
        {
            Assert.Equal("zaghlol_api", (string?)await who.ExecuteScalarAsync());
        }

        Assert.Equal(DatabaseRoleGuard.RejectRoleSwitched, await DatabaseRoleGuard.CheckAsync(connection, DatabaseRole.App, CancellationToken.None));
    }

    [Fact]
    public async Task AnyExtraTransitiveMembershipIsRejected()
    {
        // FU-023: a predefined role granted directly, and another group reached through an intermediate role.
        var suffix = Guid.NewGuid().ToString("N")[..8];
        string direct = "t123_direct_" + suffix, viaMid = "t123_via_" + suffix, mid = "t123_mid_" + suffix, clean = "t123_clean_" + suffix;
        var password = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        await Db.ExecuteAsync(fixture.Database.Superuser, $"""
            CREATE ROLE {direct} LOGIN PASSWORD '{password}' IN ROLE app_rw, pg_write_all_data;
            CREATE ROLE {mid} NOLOGIN IN ROLE ops_rw;
            CREATE ROLE {viaMid} LOGIN PASSWORD '{password}' IN ROLE app_rw, {mid};
            CREATE ROLE {clean} LOGIN PASSWORD '{password}' IN ROLE app_rw;
            GRANT CONNECT ON DATABASE {ZaghlolTestDatabase.DatabaseName} TO {direct}, {viaMid}, {clean};
            """);
        try
        {
            foreach (var (login, expected) in new[] { (direct, DatabaseRoleGuard.RejectWrongGroups), (viaMid, DatabaseRoleGuard.RejectWrongGroups), (clean, (string?)null) })
            {
                var connectionString = new NpgsqlConnectionStringBuilder(fixture.Database.Superuser) { Username = login, Password = password }.ConnectionString;
                await using var connection = await Db.OpenAsync(connectionString);
                Assert.Equal(expected, await DatabaseRoleGuard.CheckAsync(connection, DatabaseRole.App, CancellationToken.None));
            }
        }
        finally
        {
            NpgsqlConnection.ClearAllPools();
            await Db.ExecuteAsync(fixture.Database.Superuser, $"""
                REVOKE CONNECT ON DATABASE {ZaghlolTestDatabase.DatabaseName} FROM {direct}, {viaMid}, {clean};
                DROP ROLE {direct}; DROP ROLE {viaMid}; DROP ROLE {mid}; DROP ROLE {clean};
                """);
        }
    }

    [Theory]
    [InlineData("Host=db.invalid;Database=zaghlol;Username=zaghlol_api;Include Error Detail=true")]
    [InlineData("Host=db.invalid;Database=zaghlol;Username=zaghlol_api;IncludeErrorDetail=True")]
    public void IncludeErrorDetailIsRefusedAtStartup(string connectionString)
    {
        // FU-025: the server's DETAIL for a CHECK failure carries row values; it must never reach exception messages.
        Assert.True(ZaghlolDbContextOptions.IncludesErrorDetail(connectionString));
        Assert.Throws<ArgumentException>(() => ZaghlolDbContextOptions.CreateDataSource(connectionString, DatabaseRole.App));
        using var provider = Services(connectionString, new RecordingLifetime());
        var error = Assert.Throws<OptionsValidationException>(() => provider.GetRequiredService<IOptions<DatabaseConnectionOptions>>().Value);
        Assert.Contains("Include Error Detail", error.Message, StringComparison.Ordinal);
        Assert.False(new NpgsqlConnectionStringBuilder(PostgresDatabaseReadiness.ProbeConnectionString(connectionString)).IncludeErrorDetail);
    }

    [Fact]
    public async Task TheGuardLetsTheRightLoginRun()
    {
        var lifetime = new RecordingLifetime();
        await using var provider = Services(fixture.Database.Api, lifetime);
        var guard = (BackgroundService)provider.GetServices<IHostedService>().Single();

        await guard.StartAsync(CancellationToken.None);
        await guard.ExecuteTask!.WaitAsync(TimeSpan.FromSeconds(20));

        Assert.False(lifetime.Stopped.IsCompleted);
    }

    [Fact]
    public async Task ReadinessUsesItsOwnOneConnectionPoolAndRejectsTheWrongLogin()
    {
        await using (var provider = Services(fixture.Database.Api, new RecordingLifetime()))
        {
            var app = provider.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);
            var probe = provider.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRoles.ReadinessDataSourceKey);

            Assert.NotSame(app, probe);
            Assert.Equal(1, new NpgsqlConnectionStringBuilder(probe.ConnectionString).MaxPoolSize);
            Assert.True(await provider.GetRequiredService<IDatabaseReadiness>().IsReadyAsync(CancellationToken.None));
        }

        // The schema owner's credentials in ConnectionStrings:App never make the API "ready".
        await using (var provider = Services(fixture.Database.Migrator, new RecordingLifetime()))
        {
            Assert.False(await provider.GetRequiredService<IDatabaseReadiness>().IsReadyAsync(CancellationToken.None));
        }
    }

    [Fact]
    public async Task AProbeTimeoutLeavesTheAppPoolAlone()
    {
        // CR#1: an App connection sits idle in its pool; a readiness probe then times out against a server that never
        // answers. The idle App connection must survive (the old code cleared the shared pool on every failure).
        using var blackHole = new BlackHoleServer();
        await using var app = ZaghlolDbContextOptions.CreateDataSource(fixture.Database.Api, DatabaseRole.App);
        var marker = "t122-pool-" + Guid.NewGuid().ToString("N")[..8];
        await using (var connection = await app.OpenConnectionAsync())
        await using (var tag = new NpgsqlCommand($"SET application_name = '{marker}'", connection))
        {
            await tag.ExecuteNonQueryAsync();
        }

        await using var probeSource = PostgresDatabaseReadiness.CreateProbeSource(
            $"Host=127.0.0.1;Port={blackHole.Port};Database=none;Username=none;Password=none;Timeout=30");
        using var readiness = new PostgresDatabaseReadiness(probeSource, TimeProvider.System, NullLogger<PostgresDatabaseReadiness>.Instance);

        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));

        // Npgsql resets application_name only when the connection is reopened, so the backend keeps the marker
        // for as long as the pooled connection lives.
        Assert.Equal(1L, await Db.ScalarAsync(
            fixture.Database.Superuser, "SELECT count(*) FROM pg_stat_activity WHERE application_name = $1", marker));
    }

    [Fact]
    public async Task AReadyAnswerIsCachedForTwoSeconds()
    {
        // FU-026: "ready" is cached like "not ready". The data source is disposed after the first probe, so any later
        // probe fails: within the window the cached true is served; after it, the failed probe is reported.
        var clock = new SteppingClock(DateTimeOffset.UtcNow);
        var probeSource = PostgresDatabaseReadiness.CreateProbeSource(fixture.Database.Api);
        using var readiness = new PostgresDatabaseReadiness(probeSource, clock, NullLogger<PostgresDatabaseReadiness>.Instance);

        Assert.True(await readiness.IsReadyAsync(CancellationToken.None));
        await probeSource.DisposeAsync();

        clock.Advance(TimeSpan.FromSeconds(1.9));
        Assert.True(await readiness.IsReadyAsync(CancellationToken.None));
        clock.Advance(TimeSpan.FromSeconds(0.2));
        Assert.False(await readiness.IsReadyAsync(CancellationToken.None));
    }

    private static ServiceProvider Services(string appConnectionString, IHostApplicationLifetime lifetime)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:App"] = appConnectionString })
            .Build();
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton(lifetime);
        services.AddLogging();
        services.AddZaghlolDatabase(DatabaseRole.App);
        services.AddDatabaseReadiness();
        return services.BuildServiceProvider();
    }

    private sealed class SteppingClock(DateTimeOffset start) : TimeProvider
    {
        private long ticks = start.UtcTicks;

        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref ticks), TimeSpan.Zero);

        public void Advance(TimeSpan by) => Interlocked.Add(ref ticks, by.Ticks);
    }

    private sealed class RecordingLifetime : IHostApplicationLifetime
    {
        private readonly TaskCompletionSource stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task Stopped => stopped.Task;

        public CancellationToken ApplicationStarted => CancellationToken.None;

        public CancellationToken ApplicationStopping => CancellationToken.None;

        public CancellationToken ApplicationStopped => CancellationToken.None;

        public void StopApplication() => stopped.TrySetResult();
    }
}
