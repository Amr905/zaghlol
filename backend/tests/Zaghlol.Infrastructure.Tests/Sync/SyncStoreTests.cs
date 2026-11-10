using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Sync;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Installs;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;
using Zaghlol.Infrastructure.Sync;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Sync;

/// <summary>A migrated database of its own and the sync store on the App login, built the way the API builds it.</summary>
public sealed class SyncStoreFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IServiceProvider Services => services!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:App"] = Database.Api })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App);
        collection.AddZaghlolInstallStores();
        collection.AddSingleton<ISyncStore, SyncStore>();
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

/// <summary>
/// T-128: the claim transaction against PostgreSQL on the App login: one winner per window, intake and the daily-active count
/// commit with the claim or not at all, dedupe by unique key, and no write at all for a lost claim.
/// </summary>
public class SyncStoreTests(SyncStoreFixture fixture) : IClassFixture<SyncStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);
    private static readonly TimeSpan Window = TimeSpan.FromHours(24);

    private ISyncStore Store => fixture.Services.GetRequiredService<ISyncStore>();

    private async Task<(InstallId Id, string AppVersion)> NewInstallAsync()
    {
        var id = InstallId.Parse(Guid.NewGuid().ToString("D"));
        var appVersion = "1.0.0-t" + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(4));
        var installs = fixture.Services.GetRequiredService<IInstallStore>();
        Assert.Equal(
            RegistrationOutcome.Created,
            await installs.RegisterAsync(id, Platform.Android, appVersion, Rows.Bytes(), Rows.Bytes(), Rows.Bytes(), Now, CancellationToken.None));
        return (id, appVersion);
    }

    private static SyncClaim Claim(
        InstallId id,
        string appVersion,
        DateTimeOffset now,
        byte[]? hash = null,
        IReadOnlyList<PreparedContribution>? contributions = null,
        IReadOnlyList<PreparedBankRequest>? banks = null) =>
        new(id, now, Window, 7, "android", appVersion, hash is null ? (ReadOnlyMemory<byte>?)null : new ReadOnlyMemory<byte>(hash), contributions ?? [], banks ?? []);

    private async Task<long> DailyActiveAsync(string appVersion, DateTimeOffset day) =>
        (long?)(int?)await Db.ScalarAsync(
            fixture.Database.Superuser,
            "SELECT installs FROM zaghlol.daily_active_counts WHERE day = $1 AND platform = 'android' AND app_version = $2",
            DateOnly.FromDateTime(day.UtcDateTime),
            appVersion) ?? 0;

    private async Task<long> CountAsync(string sql, params object?[] parameters) =>
        (long)(await Db.ScalarAsync(fixture.Database.Superuser, sql, parameters))!;

    [Fact]
    public async Task TheFirstClaimWinsUpdatesTheInstallAndCountsADailyActive()
    {
        var (id, appVersion) = await NewInstallAsync();

        var result = await Store.ClaimAsync(Claim(id, appVersion, Now), CancellationToken.None);

        Assert.True(result.Claimed);
        var install = await Store.FindInstallAsync(id, CancellationToken.None);
        Assert.Equal(Now, install!.LastSyncAt);
        Assert.Equal("android", install.Platform);
        Assert.Equal(7L, await CountAsync("SELECT catalog_version::bigint FROM zaghlol.installs WHERE id = $1", id.Value));
        Assert.Equal(1L, await DailyActiveAsync(appVersion, Now));
    }

    [Fact]
    public async Task ASecondClaimInsideTheWindowWritesNothingAndOneAtTheEndWins()
    {
        var (id, appVersion) = await NewInstallAsync();
        var hash = Rows.Bytes();
        Assert.True((await Store.ClaimAsync(Claim(id, appVersion, Now), CancellationToken.None)).Claimed);

        var inside = await Store.ClaimAsync(
            Claim(id, appVersion, Now.Add(Window).AddSeconds(-1), hash, [new PreparedContribution("t128 inside", "nbe", "dining")]),
            CancellationToken.None);
        Assert.Equal(SyncClaimResult.Lost, inside);
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = 't128 inside'"));
        Assert.Equal(1L, await DailyActiveAsync(appVersion, Now));
        Assert.Equal(Now, (await Store.FindInstallAsync(id, CancellationToken.None))!.LastSyncAt);

        var atEnd = await Store.ClaimAsync(Claim(id, appVersion, Now.Add(Window)), CancellationToken.None);
        Assert.True(atEnd.Claimed);
        Assert.Equal(1L, await DailyActiveAsync(appVersion, Now.Add(Window)));
    }

    [Fact]
    public async Task ConcurrentClaimsHaveExactlyOneWinnerAndOneDailyActive()
    {
        var (id, appVersion) = await NewInstallAsync();

        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => Store.ClaimAsync(Claim(id, appVersion, Now), CancellationToken.None)));

        Assert.Single(results, r => r.Claimed);
        Assert.Equal(1L, await DailyActiveAsync(appVersion, Now));
    }

    [Fact]
    public async Task IntakeIsInsertedOnceByUniqueKeyAndCountsOnlyNewRows()
    {
        var (id, appVersion) = await NewInstallAsync();
        var hash = Rows.Bytes();
        var merchant = "sync koshary " + string.Concat(RandomNumberGenerator.GetBytes(10).Select(b => (char)('a' + (b % 26))));

        var first = await Store.ClaimAsync(
            Claim(
                id,
                appVersion,
                Now,
                hash,
                [new PreparedContribution(merchant, "nbe", "dining"), new PreparedContribution(merchant, "cib", "dining")],
                [new PreparedBankRequest(merchant, "EG", "sms")]),
            CancellationToken.None);
        var nextDay = await Store.ClaimAsync(
            Claim(id, appVersion, Now.Add(Window), hash, [new PreparedContribution(merchant, "nbe", "groceries")], [new PreparedBankRequest(merchant, "EG", "sms")]),
            CancellationToken.None);

        Assert.Equal(new SyncClaimResult(true, 2, 1), first);
        Assert.Equal(new SyncClaimResult(true, 0, 0), nextDay);
        Assert.Equal(2L, await CountAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1", merchant));
        Assert.Equal(
            "dining",
            await Db.ScalarAsync(
                fixture.Database.Superuser,
                "SELECT category_code FROM zaghlol.merchant_contributions WHERE merchant_norm = $1 AND institution_code = 'nbe'",
                merchant));
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.bank_requests WHERE institution_name_norm = $1", merchant));

        // The raw install ID is never stored with the intake; the hash is.
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE install_hash = $1", id.Value.ToByteArray()));
        Assert.Equal(2L, await CountAsync("SELECT count(*) FROM zaghlol.merchant_contributions WHERE install_hash = $1", hash));
    }

    [Fact]
    public async Task ADeletedInstallCannotClaimAndIsNotFound()
    {
        var (id, appVersion) = await NewInstallAsync();
        await fixture.Services.GetRequiredService<IInstallStore>().DeleteAsync(id, Now, CancellationToken.None);

        Assert.Null(await Store.FindInstallAsync(id, CancellationToken.None));
        Assert.Equal(SyncClaimResult.Lost, await Store.ClaimAsync(Claim(id, appVersion, Now), CancellationToken.None));
        Assert.Equal(0L, await DailyActiveAsync(appVersion, Now));
    }

    [Fact]
    public async Task TheInstallHashIsAnHmacOfTheLabelledInstallId()
    {
        using var kms = FakeKms.CreateDefault();
        await using var provider = kms.BuildServices();
        var keyed = provider.GetRequiredService<IKeyedHasher>();
        var id = InstallId.Parse("00000000-0000-4000-8000-000000000001");

        var hash = await new KeyedInstallHasher(keyed).HashAsync(id, CancellationToken.None);

        Assert.Equal("zaghlol-install-hash-v1" + "\0" + "00000000-0000-4000-8000-000000000001", Encoding.UTF8.GetString(KeyedInstallHasher.Input(id)));
        Assert.Equal(await keyed.HmacSha256Async(KeyedHashKey.InstallHashPepper, KeyedInstallHasher.Input(id), CancellationToken.None), hash);
        Assert.Equal(32, hash.Length);
    }
}
