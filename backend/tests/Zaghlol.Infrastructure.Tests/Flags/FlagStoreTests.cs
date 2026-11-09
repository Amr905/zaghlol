using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Flags;
using Zaghlol.Infrastructure.Flags;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Flags;

/// <summary>A migrated database of its own and the flag stores on the Admin and App logins, built the way the API builds them.</summary>
public sealed class FlagStoreFixture : IAsyncLifetime
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
        collection.AddZaghlolFlagAdmin();
        collection.AddZaghlolFlagReader();
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

    /// <summary>An operator row (the audit log references it), as the operator-auth task will create them.</summary>
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

/// <summary>T-126: the flag stores against PostgreSQL (versioning, rules replace/keep, audit, grants).</summary>
public class FlagStoreTests(FlagStoreFixture fixture) : IClassFixture<FlagStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);

    private IFlagAdminStore Admin => fixture.Services.GetRequiredService<IFlagAdminStore>();

    private IFlagReader Reader => fixture.Services.GetRequiredService<IFlagReader>();

    [Fact]
    public async Task ANeverSetFlagHasNoRow()
    {
        Assert.Null(await Admin.GetAsync("never_set", CancellationToken.None));
        Assert.Empty((await Reader.ListAsync(CancellationToken.None)).Where(f => f.Key == "never_set"));
    }

    [Fact]
    public async Task EachChangeIncrementsTheVersionAndTheAppLoginReadsIt()
    {
        var op = await fixture.NewOperatorAsync();

        var first = await Admin.UpsertAsync("version_probe", true, null, op, Now, CancellationToken.None);
        var second = await Admin.UpsertAsync("version_probe", false, null, op, Now.AddMinutes(1), CancellationToken.None);

        Assert.Equal(1, first.Version);
        Assert.True(first.Value);
        Assert.True(first.Rules.IsEmpty);
        Assert.Equal(2, second.Version);
        Assert.False(second.Value);
        Assert.Equal(Now.AddMinutes(1), second.UpdatedAt);

        var read = Assert.Single((await Reader.ListAsync(CancellationToken.None)).Where(f => f.Key == "version_probe"));
        Assert.Equal(2, read.Version);
        Assert.False(read.Value);
        var viaAdmin = await Admin.GetAsync("version_probe", CancellationToken.None);
        Assert.Equal(2, viaAdmin!.Version);
    }

    [Fact]
    public async Task RulesAreReplacedAsAWholeWhenPresentAndKeptWhenAbsent()
    {
        var op = await fixture.NewOperatorAsync();
        var rules = new FlagRules(["android"], "1.4.0", 10);

        var set = await Admin.UpsertAsync("rules_probe", true, rules, op, Now, CancellationToken.None);
        var kept = await Admin.UpsertAsync("rules_probe", true, null, op, Now, CancellationToken.None);
        var replaced = await Admin.UpsertAsync("rules_probe", true, new FlagRules(null, null, 50), op, Now, CancellationToken.None);
        var cleared = await Admin.UpsertAsync("rules_probe", true, FlagRules.None, op, Now, CancellationToken.None);

        Assert.Equal(new[] { "android" }, set.Rules.Platforms!.ToArray());
        Assert.Equal("1.4.0", set.Rules.MinAppVersion);
        Assert.Equal(10, set.Rules.RolloutPercent);
        Assert.Equal("1.4.0", kept.Rules.MinAppVersion);
        Assert.Null(replaced.Rules.Platforms);
        Assert.Null(replaced.Rules.MinAppVersion);
        Assert.Equal(50, replaced.Rules.RolloutPercent);
        Assert.True(cleared.Rules.IsEmpty);
        Assert.Equal(new[] { 1, 2, 3, 4 }, new[] { set.Version, kept.Version, replaced.Version, cleared.Version });
    }

    [Fact]
    public async Task EachChangeWritesExactlyOneAuditRowNamingTheOperator()
    {
        var op = await fixture.NewOperatorAsync();
        var before = (long)(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = $1", op))!;
        Assert.Equal(0, before);

        await Admin.UpsertAsync("audit_probe", true, new FlagRules(["ios"], null, 25), op, Now, CancellationToken.None);
        await Admin.UpsertAsync("audit_probe", false, null, op, Now, CancellationToken.None);

        var rows = await Db.QueryAsync(
            fixture.Database.Superuser,
            "SELECT action, target, details::text FROM zaghlol.audit_log WHERE operator_id = $1 ORDER BY id",
            op);
        Assert.Equal(2, rows.Count);
        Assert.All(rows, r =>
        {
            Assert.Equal("flag_update", (string)r[0]!);
            Assert.Equal("flag:audit_probe", (string)r[1]!);
        });
        Assert.Contains("\"value\": true", (string)rows[0][2]!, StringComparison.Ordinal);
        Assert.Contains("\"platforms\": [\"ios\"]", (string)rows[0][2]!, StringComparison.Ordinal);
        Assert.Contains("\"version\": 2", (string)rows[1][2]!, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnUnknownOperatorRollsTheWholeChangeBack()
    {
        var unknownOperator = Guid.NewGuid();

        await Assert.ThrowsAsync<PostgresException>(() =>
            Admin.UpsertAsync("rollback_probe", true, null, unknownOperator, Now, CancellationToken.None));

        // The audit insert failed its foreign key, so the flag write in the same transaction is gone too.
        Assert.Null(await Admin.GetAsync("rollback_probe", CancellationToken.None));
        var auditRows = (long)(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = $1", unknownOperator))!;
        Assert.Equal(0, auditRows);
    }

    [Fact]
    public async Task ConcurrentChangesNeverShareAVersion()
    {
        var op = await fixture.NewOperatorAsync();

        var results = await Task.WhenAll(Enumerable.Range(0, 12).Select(i =>
            Admin.UpsertAsync("race_probe", i % 2 == 0, null, op, Now, CancellationToken.None)));

        var versions = results.Select(r => r.Version).OrderBy(v => v).ToArray();
        Assert.Equal(versions.Distinct().Count(), versions.Length);
        Assert.Equal(versions[0] + 11, versions[^1]);
    }

    [Fact]
    public async Task TheAppLoginCannotWriteFlagsOrAudit()
    {
        var op = await fixture.NewOperatorAsync();
        var write = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(fixture.Database.Api, "UPDATE zaghlol.feature_flags SET enabled = true"));
        Assert.Equal("42501", write.SqlState);
        var audit = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(
                fixture.Database.Api,
                "INSERT INTO zaghlol.audit_log (operator_id, action, target, details) VALUES ($1, 'flag_update', 'flag:zakah', '{}')",
                op));
        Assert.Equal("42501", audit.SqlState);
    }
}
