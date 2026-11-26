using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Config;
using Zaghlol.Infrastructure.Config;
using Zaghlol.Infrastructure.Flags;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Config;

/// <summary>A migrated database of its own and the remote config stores on the Admin and App logins, built the way the API builds them.</summary>
public sealed class RemoteConfigFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IServiceProvider Services => services!;

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
        collection.AddLogging();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin);
        collection.AddZaghlolFlagReader();
        collection.AddZaghlolRemoteConfig();
        services = collection.BuildServiceProvider();
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

    public async Task<Guid> NewOperatorAsync()
    {
        var id = Guid.NewGuid();
        await Db.ExecuteAsync(
            Database.Migrator,
            "INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ($1, $2, $3, ARRAY['flags_admin'])",
            id,
            "sub-" + id,
            "Test operator");
        return id;
    }
}

/// <summary>T-334: the config stores against PostgreSQL (versioning, audit, rollback, grants, the app login reading what the admin login wrote).</summary>
public class RemoteConfigStoreTests(RemoteConfigFixture fixture) : IClassFixture<RemoteConfigFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 26, 12, 0, 0, TimeSpan.Zero);

    private IRemoteConfigAdminStore Admin => fixture.Services.GetRequiredService<IRemoteConfigAdminStore>();

    private IRemoteConfigService Service => fixture.Services.GetRequiredService<IRemoteConfigService>();

    [Fact]
    public async Task EachChangeBumpsTheVersionWritesOneAuditRowAndTheAppLoginSeesItOnTheNextRead()
    {
        var op = await fixture.NewOperatorAsync();
        Assert.Equal(5, (await Service.GetAsync(CancellationToken.None)).GetInt(RemoteConfigKeys.AskQuotaFree));

        var first = await Admin.UpsertAsync(RemoteConfigKeys.AskQuotaFree, "8", op, Now, CancellationToken.None);
        var second = await Admin.UpsertAsync(RemoteConfigKeys.AskQuotaFree, "9", op, Now.AddMinutes(1), CancellationToken.None);

        Assert.Equal(1, first.Version);
        Assert.Equal(2, second.Version);
        var snapshot = await Service.GetAsync(CancellationToken.None);
        Assert.Equal(9, snapshot.GetInt(RemoteConfigKeys.AskQuotaFree));
        Assert.True(snapshot.AppVersion >= 2);

        var rows = await Db.QueryAsync(
            fixture.Database.Superuser,
            "SELECT action, target, details::text FROM zaghlol.audit_log WHERE operator_id = $1 ORDER BY id",
            op);
        Assert.Equal(2, rows.Count);
        Assert.All(rows, r =>
        {
            Assert.Equal("config_update", (string)r[0]!);
            Assert.Equal("config:ask.quota_free", (string)r[1]!);
        });
    }

    [Fact]
    public async Task AFailedAuditInsertRollsTheConfigChangeBack()
    {
        var unknownOperator = Guid.NewGuid();

        await Assert.ThrowsAsync<PostgresException>(() =>
            Admin.UpsertAsync(RemoteConfigKeys.CatBatchMax, "10", unknownOperator, Now, CancellationToken.None));

        Assert.DoesNotContain(await Admin.ListAsync(CancellationToken.None), r => r.Key == RemoteConfigKeys.CatBatchMax);
    }

    [Fact]
    public async Task ThePublicApiLoginCanReadButNeverWriteRemoteConfig()
    {
        var write = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(
                fixture.Database.Api,
                "INSERT INTO zaghlol.remote_config (key, value, version, updated_at) VALUES ('ask.quota_free', '999', 1, now())"));

        Assert.Equal("42501", write.SqlState);
        await Db.ScalarAsync(fixture.Database.Api, "SELECT count(*) FROM zaghlol.remote_config");
    }
}
