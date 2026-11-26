using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Llm.Categorise.Feedback;
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

    // B97-M1: feedback counts only from an install with an attested categorise call (a counter row for this or the previous Cairo month).
    private Task AttestAsync(InstallId id, int monthKey = 202611, int used = 1) => Db.InsertAsync(
        fixture.Database.Migrator,
        "llm_quota_counters",
        new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["feature"] = "cat",
            ["subject_kind"] = "install",
            ["subject_id"] = id.Value,
            ["month_key"] = monthKey,
            ["used"] = used,
            ["updated_at"] = Now,
        });

    private async Task<(InstallId Id, string AppVersion)> NewInstallAsync(bool attested = true)
    {
        var id = InstallId.Parse(Guid.NewGuid().ToString("D"));
        var appVersion = "1.0.0-t" + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(4));
        var installs = fixture.Services.GetRequiredService<IInstallStore>();
        Assert.Equal(
            RegistrationOutcome.Created,
            await installs.RegisterAsync(id, Platform.Android, appVersion, Rows.Bytes(), Rows.Bytes(), Rows.Bytes(), Now, CancellationToken.None));
        if (attested)
        {
            await AttestAsync(id);
        }

        return (id, appVersion);
    }

    private static SyncClaim Claim(
        InstallId id,
        string appVersion,
        DateTimeOffset now,
        byte[]? hash = null,
        IReadOnlyList<PreparedContribution>? contributions = null,
        IReadOnlyList<PreparedBankRequest>? banks = null,
        PreparedFeedback? feedback = null) =>
        new(id, now, Window, 7, "android", appVersion, hash is null ? (ReadOnlyMemory<byte>?)null : new ReadOnlyMemory<byte>(hash), contributions ?? [], banks ?? [], feedback);

    // The day is the database's own UTC date (T-128 SEC S3), not the test clock's; every install has its own app version.
    private async Task<long> DailyActiveAsync(string appVersion) =>
        (long?)await Db.ScalarAsync(
            fixture.Database.Superuser,
            "SELECT sum(installs)::bigint FROM zaghlol.daily_active_counts WHERE platform = 'android' AND app_version = $1",
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
        Assert.Equal(1L, await DailyActiveAsync(appVersion));
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
        Assert.Equal(1L, await DailyActiveAsync(appVersion));
        Assert.Equal(Now, (await Store.FindInstallAsync(id, CancellationToken.None))!.LastSyncAt);

        var atEnd = await Store.ClaimAsync(Claim(id, appVersion, Now.Add(Window)), CancellationToken.None);
        Assert.True(atEnd.Claimed);
        Assert.Equal(2L, await DailyActiveAsync(appVersion));
    }

    [Fact]
    public async Task ConcurrentClaimsHaveExactlyOneWinnerAndOneDailyActive()
    {
        var (id, appVersion) = await NewInstallAsync();

        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => Store.ClaimAsync(Claim(id, appVersion, Now), CancellationToken.None)));

        Assert.Single(results, r => r.Claimed);
        Assert.Equal(1L, await DailyActiveAsync(appVersion));
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

    // ---- T-353 ----

    private static readonly string[] ForbiddenColumnWords = ["install", "account", "ip", "version", "token"];

    private static string Marker() => "fb" + string.Concat(RandomNumberGenerator.GetBytes(10).Select(b => (char)('a' + (b % 26))));

    private static PreparedFeedback Feedback(IEnumerable<PreparedConfirmation>? right = null, IEnumerable<PreparedCorrection>? wrong = null) =>
        new([.. right ?? []], new IntakeCounts(0, 0, 0), [.. wrong ?? []], new IntakeCounts(0, 0, 0));

    private async Task<SyncClaimResult> CorrectAsync(string merchant, string aiCategory = "dining", string userCategory = "groceries", bool attested = true, DateTimeOffset? at = null)
    {
        var (id, appVersion) = await NewInstallAsync(attested);
        return await Store.ClaimAsync(Claim(id, appVersion, at ?? Now, Rows.Bytes(), feedback: Feedback(wrong: [new PreparedCorrection(merchant, aiCategory, userCategory, "llm")])), CancellationToken.None);
    }

    private Task SeedCacheAsync(string merchant, string category) => Db.InsertAsync(
        fixture.Database.Migrator,
        "llm_cat_answer_cache",
        new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["merchant_norm"] = merchant,
            ["category_code"] = category,
            ["confidence"] = (short)90,
            ["provider_id"] = "fake",
            ["prompt_version"] = "v1",
            ["created_at"] = Now.AddDays(-3),
            ["expires_at"] = Now.AddDays(90),
        });

    // AC 1: one row per verdict with the keyed hash and the day-cut time; a retry and a second install's same verdict behave per the unique key.
    [Fact]
    public async Task RightAndWrongAreStoredOnceWithTheInstallHashAndARetryAddsNothing()
    {
        var (id, appVersion) = await NewInstallAsync();
        var hash = Rows.Bytes();
        var merchant = Marker();
        var feedback = Feedback([new PreparedConfirmation(merchant, "dining", "llm")], [new PreparedCorrection(merchant, "dining", "custom", "cache")]);

        var first = await Store.ClaimAsync(Claim(id, appVersion, Now.AddHours(5), hash, feedback: feedback), CancellationToken.None);
        var retry = await Store.ClaimAsync(Claim(id, appVersion, Now.Add(Window).AddHours(5), hash, feedback: feedback), CancellationToken.None);

        Assert.Equal(new SyncClaimResult(true, 0, 0, 1, 1), first);
        Assert.Equal(new SyncClaimResult(true, 0, 0, 0, 0), retry);
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = $1 AND install_hash = $2 AND status = 'collecting'", merchant, hash));
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = $1 AND install_hash = $2 AND user_category = 'custom' AND status = 'open' AND created_at = $3", merchant, hash, new DateTimeOffset(Now.UtcDateTime.Date, TimeSpan.Zero)));
    }

    // AC 3, abuse: one install, however often it resends, never reaches three.
    [Fact]
    public async Task OneInstallCorrectingRepeatedlyNeverDeletesTheCachedAnswer()
    {
        var merchant = Marker();
        await SeedCacheAsync(merchant, "dining");
        var (id, appVersion) = await NewInstallAsync();
        var hash = Rows.Bytes();
        var feedback = Feedback(wrong: [new PreparedCorrection(merchant, "dining", "groceries", "llm")]);

        for (var day = 0; day < 5; day++)
        {
            await Store.ClaimAsync(Claim(id, appVersion, Now.Add(Window * day), hash, feedback: feedback), CancellationToken.None);
        }

        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = $1", merchant));
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));
    }

    // AC 3 / negative proof 3: two installs leave the cache row, the third deletes it.
    [Fact]
    public async Task ThreeCorrectionsFromThreeInstallsDeleteTheMatchingCacheRowAndTwoDoNot()
    {
        var merchant = Marker();
        await SeedCacheAsync(merchant, "dining");

        await CorrectAsync(merchant);
        await CorrectAsync(merchant);
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));

        await CorrectAsync(merchant);
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));
        Assert.Equal(3L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = $1", merchant));
    }

    // B97-M1: scripted installs (register + sync, no attestation) cannot delete a shared cache row, however many there are.
    [Fact]
    public async Task UnattestedInstallsCannotDeleteACacheRow()
    {
        var merchant = Marker();
        await SeedCacheAsync(merchant, "dining");

        for (var i = 0; i < 5; i++)
        {
            Assert.Equal(new SyncClaimResult(true, 0, 0, 0, 0), await CorrectAsync(merchant, attested: false));
        }

        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_corrections WHERE merchant_norm = $1", merchant));
    }

    [Fact]
    public async Task ThreeFakeConfirmationsFromUnattestedInstallsDoNotCount()
    {
        var merchant = Marker();
        for (var i = 0; i < 3; i++)
        {
            var (id, appVersion) = await NewInstallAsync(attested: false);
            await Store.ClaimAsync(Claim(id, appVersion, Now, Rows.Bytes(), feedback: Feedback([new PreparedConfirmation(merchant, "dining", "llm")])), CancellationToken.None);
        }

        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = $1", merchant));

        var (real, version) = await NewInstallAsync();
        var counted = await Store.ClaimAsync(Claim(real, version, Now, Rows.Bytes(), feedback: Feedback([new PreparedConfirmation(merchant, "dining", "llm")])), CancellationToken.None);
        Assert.Equal(1, counted.ConfirmationsInserted);
    }

    [Fact]
    public async Task OnlyAnAttestedCallInTheCurrentOrPreviousMonthWithUsedAboveZeroCounts()
    {
        var merchant = Marker();
        var (old, oldVersion) = await NewInstallAsync(attested: false);
        await AttestAsync(old, 202609);
        var (zero, zeroVersion) = await NewInstallAsync(attested: false);
        await AttestAsync(zero, 202611, 0);
        var (previous, previousVersion) = await NewInstallAsync(attested: false);
        await AttestAsync(previous, 202610);
        var feedback = Feedback([new PreparedConfirmation(merchant, "dining", "llm")]);

        Assert.Equal(0, (await Store.ClaimAsync(Claim(old, oldVersion, Now, Rows.Bytes(), feedback: feedback), CancellationToken.None)).ConfirmationsInserted);
        Assert.Equal(0, (await Store.ClaimAsync(Claim(zero, zeroVersion, Now, Rows.Bytes(), feedback: feedback), CancellationToken.None)).ConfirmationsInserted);
        Assert.Equal(1, (await Store.ClaimAsync(Claim(previous, previousVersion, Now, Rows.Bytes(), feedback: feedback), CancellationToken.None)).ConfirmationsInserted);
    }

    // B97-M1: after three corrections delete a row and the name is learned again, the same three corrections must not delete it a second time.
    [Fact]
    public async Task ARelearnedCacheRowIsNotDeletedAgainByTheCorrectionsThatDeletedItsPredecessor()
    {
        var merchant = Marker();
        await SeedCacheAsync(merchant, "dining");
        await CorrectAsync(merchant);
        await CorrectAsync(merchant);
        await CorrectAsync(merchant);
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));

        await Db.ExecuteAsync(fixture.Database.Superuser, "INSERT INTO zaghlol.llm_cat_answer_cache (merchant_norm, category_code, confidence, provider_id, prompt_version, created_at, expires_at, hits) VALUES ($1, 'dining', 90, 'fake', 'v1', $2, $3, 0)", merchant, Now.AddDays(2), Now.AddDays(92));

        // A fourth, new install's correction on a later day: 1 new correction, not 3.
        await CorrectAsync(merchant, at: Now.AddDays(3));
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));

        // Two more new ones make three since the row was re-created: it goes again.
        await CorrectAsync(merchant, at: Now.AddDays(4));
        await CorrectAsync(merchant, at: Now.AddDays(5));
        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));
    }

    [Fact]
    public async Task CorrectionsOfADifferentCategoryOrARejectedReviewDoNotCountAgainstTheCache()
    {
        var other = Marker();
        await SeedCacheAsync(other, "dining");
        await CorrectAsync(other, "groceries", "education");
        await CorrectAsync(other, "groceries", "education");
        await CorrectAsync(other, "groceries", "education");
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", other));

        var rejected = Marker();
        await SeedCacheAsync(rejected, "dining");
        await CorrectAsync(rejected);
        await CorrectAsync(rejected);
        await Db.ExecuteAsync(fixture.Database.Superuser, "UPDATE zaghlol.llm_cat_corrections SET status = 'rejected' WHERE merchant_norm = $1", rejected);
        await CorrectAsync(rejected);
        Assert.Equal(1L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", rejected));
    }

    [Fact]
    public async Task ConcurrentThirdCorrectionsStillDeleteTheCacheRow()
    {
        var merchant = Marker();
        await SeedCacheAsync(merchant, "dining");
        await CorrectAsync(merchant);

        await Task.WhenAll(CorrectAsync(merchant), CorrectAsync(merchant));

        Assert.Equal(0L, await CountAsync("SELECT count(*) FROM zaghlol.llm_cat_answer_cache WHERE merchant_norm = $1", merchant));
    }

    // AC 4 / negative proof 1 (data check): marker ids never reach the two tables; a lost claim writes no feedback.
    [Fact]
    public async Task ADumpOfBothTablesHoldsNoInstallIdAppVersionOrAccountMarker()
    {
        var (id, appVersion) = await NewInstallAsync();
        var merchant = Marker();
        var hash = Rows.Bytes();
        var feedback = Feedback([new PreparedConfirmation(merchant, "dining", "llm")], [new PreparedCorrection(merchant, "dining", "groceries", "llm")]);
        await Store.ClaimAsync(Claim(id, appVersion, Now, hash, feedback: feedback), CancellationToken.None);
        var lost = await Store.ClaimAsync(Claim(id, appVersion, Now.AddMinutes(1), hash, feedback: Feedback([new PreparedConfirmation(merchant + "lost", "dining", "llm")])), CancellationToken.None);
        Assert.Equal(SyncClaimResult.Lost, lost);

        var dump = (string)(await Db.ScalarAsync(
            fixture.Database.Superuser,
            "SELECT coalesce((SELECT string_agg(row_to_json(t)::text, E'\\n') FROM zaghlol.llm_cat_confirmations t WHERE merchant_norm LIKE $1), '') || coalesce((SELECT string_agg(row_to_json(t)::text, E'\\n') FROM zaghlol.llm_cat_corrections t WHERE merchant_norm LIKE $1), '')",
            merchant + "%"))!;

        Assert.Contains(merchant, dump, StringComparison.Ordinal);
        Assert.DoesNotContain(merchant + "lost", dump, StringComparison.Ordinal);
        Assert.DoesNotContain(id.Value.ToString("D"), dump, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(appVersion, dump, StringComparison.Ordinal);
        Assert.DoesNotContain("127.0.0.1", dump, StringComparison.Ordinal);

        var columns = await Db.QueryAsync(
            fixture.Database.Superuser,
            "SELECT column_name FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name IN ('llm_cat_confirmations', 'llm_cat_corrections')");
        Assert.DoesNotContain(columns, c => ForbiddenColumnWords.Any(word => ((string)c[0]!).Contains(word, StringComparison.Ordinal) && (string)c[0]! != "install_hash"));
    }

    [Fact]
    public async Task ADeletedInstallCannotClaimAndIsNotFound()
    {
        var (id, appVersion) = await NewInstallAsync();
        await fixture.Services.GetRequiredService<IInstallStore>().DeleteAsync(id, Now, CancellationToken.None);

        Assert.Null(await Store.FindInstallAsync(id, CancellationToken.None));
        Assert.Equal(SyncClaimResult.Lost, await Store.ClaimAsync(Claim(id, appVersion, Now), CancellationToken.None));
        Assert.Equal(0L, await DailyActiveAsync(appVersion));
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
