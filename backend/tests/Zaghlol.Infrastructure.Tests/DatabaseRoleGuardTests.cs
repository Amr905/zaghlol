using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Zaghlol.Application.Health;
using Zaghlol.Infrastructure.Persistence;

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
    public async Task TheGuardStopsTheHostWhenTheAppLoginIsTheMigrator()
    {
        var lifetime = new RecordingLifetime();
        await using var provider = Services(fixture.Database.Migrator, lifetime);
        var guard = provider.GetServices<IHostedService>().Single();

        await guard.StartAsync(CancellationToken.None);
        var stopped = await Task.WhenAny(lifetime.Stopped, Task.Delay(TimeSpan.FromSeconds(20)));
        await guard.StopAsync(CancellationToken.None);

        Assert.Same(lifetime.Stopped, stopped);
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
