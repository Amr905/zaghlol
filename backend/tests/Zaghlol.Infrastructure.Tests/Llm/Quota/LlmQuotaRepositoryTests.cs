using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Application.Retention;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Infrastructure.Installs;
using Zaghlol.Infrastructure.Llm.Quota;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Retention;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm.Quota;

/// <summary>T-335 against PostgreSQL: the commit statement, the limits, the purge rule and the delete flows.</summary>
public sealed class LlmQuotaFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IServiceProvider Services => services!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:App"] = Database.Api, ["ConnectionStrings:Worker"] = Database.Worker })
            .Build();
        var collection = new ServiceCollection();
        collection.AddLogging();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Worker);
        collection.AddZaghlolInstallStores();
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
}

public class LlmQuotaRepositoryTests(LlmQuotaFixture fixture) : IClassFixture<LlmQuotaFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 20, 10, 0, 0, TimeSpan.Zero);

    private LlmQuotaRepository Repository => new(fixture.Services.GetRequiredKeyedService<Npgsql.NpgsqlDataSource>(DatabaseRole.App));

    private static byte[] Hash(string id) => System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(id));

    private async Task<long> RowsAsync(string kind, Guid subject) =>
        (long)(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.llm_quota_counters WHERE subject_kind = $1 AND subject_id = $2", kind, subject))!;

    private async Task<int> UsedAsync(string feature, Guid subject) =>
        (int)(await Db.ScalarAsync(fixture.Database.Superuser, "SELECT used FROM zaghlol.llm_quota_counters WHERE feature = $1 AND subject_id = $2", feature, subject))!;

    /// <summary>Negative proof 1 (AC 4): parallel commits of one request id count exactly once, for a new row and for an existing one.</summary>
    [Fact]
    public async Task ParallelCommitsWithTheSameRequestIdCountOnce()
    {
        var repository = Repository;
        for (var round = 0; round < 10; round++)
        {
            var subject = Guid.NewGuid();
            var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ =>
                repository.CommitAsync(LlmFeature.Categorise, LlmQuotaSubjectKind.Install, subject, 202611, 4, 15, Hash("batch-" + round), Now, Now.AddMinutes(-2), CancellationToken.None)));
            Assert.Equal(1, results.Count(r => r));
            Assert.Equal(4, await UsedAsync("cat", subject));

            // An existing row (a previous request counted) behaves the same.
            var second = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ =>
                repository.CommitAsync(LlmFeature.Categorise, LlmQuotaSubjectKind.Install, subject, 202611, 4, 15, Hash("next-" + round), Now, Now.AddMinutes(-2), CancellationToken.None)));
            Assert.Equal(1, second.Count(r => r));
            Assert.Equal(8, await UsedAsync("cat", subject));
        }
    }

    [Fact]
    public async Task TheStatementNeverTakesARowPastItsLimit()
    {
        var subject = Guid.NewGuid();
        var repository = Repository;
        Assert.True(await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, 4, 5, Hash("a"), Now, Now.AddMinutes(-2), CancellationToken.None));
        Assert.True(await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, 4, 5, Hash("b"), Now, Now.AddMinutes(-2), CancellationToken.None));
        Assert.False(await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, 1, 5, Hash("c"), Now, Now.AddMinutes(-2), CancellationToken.None));
        Assert.Equal(5, await UsedAsync("ask", subject));
        var row = await ReadBack(subject);
        Assert.Equal(5, row?.Used);
        Assert.Equal(Hash("b"), row?.LastRequestHash);
    }

    /// <summary>B92-M1: the same hash counts again once it is older than the cutoff, and not inside it.</summary>
    [Fact]
    public async Task AReplayedRequestIdCountsAgainAfterTheRetryWindowButNotInsideIt()
    {
        var subject = Guid.NewGuid();
        var repository = Repository;
        var window = LlmQuotaStore.RetryWindow;
        Assert.True(await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, 1, 5, Hash("a"), Now, Now - window, CancellationToken.None));
        var later = Now + window - TimeSpan.FromSeconds(1);
        Assert.False(await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, 1, 5, Hash("a"), later, later - window, CancellationToken.None));
        Assert.Equal(1, await UsedAsync("ask", subject));
        later = Now + window + TimeSpan.FromSeconds(1);
        Assert.True(await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, 1, 5, Hash("a"), later, later - window, CancellationToken.None));
        Assert.Equal(2, await UsedAsync("ask", subject));
        Assert.Equal(later, (await ReadBack(subject))?.UpdatedAt);
    }

    private async Task<LlmQuotaRow?> ReadBack(Guid subject)
    {
        var row = await Repository.ReadAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, subject, 202611, CancellationToken.None);
        return row is null ? null : new LlmQuotaRow(row.Used, row.LastRequestHash, row.UpdatedAt);
    }

    [Fact]
    public async Task LimitsComeFromRemoteConfigWithTheDefaultsAsFallback()
    {
        var limits = new RemoteConfigQuotaLimits(fixture.Services.GetRequiredKeyedService<Npgsql.NpgsqlDataSource>(DatabaseRole.App));
        Assert.Equal(5, await limits.LimitAsync(LlmFeature.Ask, false, CancellationToken.None));
        Assert.Equal(150, await limits.LimitAsync(LlmFeature.Categorise, true, CancellationToken.None));

        await Db.ExecuteAsync(fixture.Database.Superuser, "INSERT INTO zaghlol.remote_config (key, value, version, updated_at) VALUES ('ask.quota_free', '7', 1, now()), ('cat.quota_free', 'many', 1, now())");
        Assert.Equal(7, await limits.LimitAsync(LlmFeature.Ask, false, CancellationToken.None));
        Assert.Equal(15, await limits.LimitAsync(LlmFeature.Categorise, false, CancellationToken.None));
    }

    /// <summary>Negative proof 2 (AC 5): the delete flows leave no row of the subject; the purge keeps only the current and previous month.</summary>
    [Fact]
    public async Task DeleteFlowsAndThePurgeLeaveNoStaleCounterRows()
    {
        var repository = Repository;
        var install = Guid.NewGuid();
        await Rows.InsertAsync(fixture.Database, "installs", new Dictionary<string, object?> { ["id"] = install });
        var accountRow = await Rows.InsertAsync(fixture.Database, "accounts");
        var account = (Guid)accountRow["id"]!;
        var bystander = Guid.NewGuid();
        foreach (var feature in new[] { LlmFeature.Ask, LlmFeature.Categorise })
        {
            await repository.CommitAsync(feature, LlmQuotaSubjectKind.Install, install, 202611, 1, 50, Hash("x"), Now, Now.AddMinutes(-2), CancellationToken.None);
            await repository.CommitAsync(feature, LlmQuotaSubjectKind.Account, account, 202611, 1, 50, Hash("x"), Now, Now.AddMinutes(-2), CancellationToken.None);
            await repository.CommitAsync(feature, LlmQuotaSubjectKind.Install, bystander, 202611, 1, 50, Hash("x"), Now, Now.AddMinutes(-2), CancellationToken.None);
        }

        await new NpgsqlAccountStore(fixture.Services).DeleteAccountAsync(account, null, Now, CancellationToken.None);
        Assert.Equal(0, await RowsAsync("account", account));
        Assert.Equal(2, await RowsAsync("install", install));

        await fixture.Services.GetRequiredService<IInstallStore>().DeleteAsync(InstallId.TryParse(install.ToString("D"), out var installId) ? installId : throw new InvalidOperationException(), Now, CancellationToken.None);
        Assert.Equal(0, await RowsAsync("install", install));
        Assert.Equal(2, await RowsAsync("install", bystander));

        // Purge: now is 20 Nov 2026 -> keep 202611 and 202610, delete 202609 and older.
        var old = Guid.NewGuid();
        foreach (var month in new[] { 202609, 202610, 202611 })
        {
            await repository.CommitAsync(LlmFeature.Ask, LlmQuotaSubjectKind.Install, old, month, 1, 5, Hash("m"), Now, Now.AddMinutes(-2), CancellationToken.None);
        }

        var store = new RetentionStore(fixture.Services.GetRequiredService<IZaghlolDbContextFactory>());
        Assert.Equal(1, await store.PurgeBatchAsync(RetentionRules.LlmQuotaMonths, Now, 100, CancellationToken.None));
        var months = await Db.QueryAsync(fixture.Database.Superuser, "SELECT month_key FROM zaghlol.llm_quota_counters WHERE subject_id = $1 ORDER BY 1", old);
        Assert.Equal([202610, 202611], months.Select(r => (int)r[0]!));
    }
}
