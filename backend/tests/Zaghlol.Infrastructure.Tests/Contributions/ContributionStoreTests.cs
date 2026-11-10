using System.Globalization;
using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Contributions;
using Zaghlol.Infrastructure.Catalog;
using Zaghlol.Infrastructure.Contributions;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Contributions;

/// <summary>A signer that is never asked to sign: nothing in these tests publishes (that is the point of one of them).</summary>
internal sealed class UnusedSigner : ISigner
{
    public ValueTask<ResponseSignature> SignAsync(SigningPurpose purpose, ReadOnlyMemory<byte> data, CancellationToken cancellationToken) =>
        throw new InvalidOperationException("Nothing here publishes.");

    public ValueTask<string> CreateJwsAsync<T>(SigningPurpose purpose, T payload, CancellationToken cancellationToken) =>
        throw new InvalidOperationException("Nothing here signs.");

    public IReadOnlyList<SigningKey> PublishedKeys(SigningPurpose purpose) => [];
}

internal sealed class UnusedSnapshotStore : ICatalogSnapshotStore
{
    public Task<Uri> PutAsync(int version, ReadOnlyMemory<byte> gzipJson, string signature, CancellationToken cancellationToken) =>
        throw new InvalidOperationException("Nothing here publishes.");

    public Task<byte[]?> GetAsync(int version, CancellationToken cancellationToken) => Task.FromResult<byte[]?>(null);
}

/// <summary>A migrated database with the contribution stores on the Worker and Admin logins, built the way the hosts build them.</summary>
public sealed class ContributionStoreFixture : IAsyncLifetime
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
                ["ConnectionStrings:Worker"] = Database.Worker,
            })
            .Build();
        var collection = new ServiceCollection();
        collection.AddLogging();
        collection.AddSingleton(TimeProvider.System);
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddSingleton<ISigner, UnusedSigner>();
        collection.AddSingleton<ICatalogSnapshotStore, UnusedSnapshotStore>();
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin, DatabaseRole.Worker);
        collection.AddZaghlolCatalog();
        collection.AddZaghlolContributionAdmin();
        collection.AddZaghlolContributionWorker();
        services = collection.BuildServiceProvider();

        // One live draft category, so merchants can be created.
        var editor = await NewOperatorAsync();
        await Catalog.PutAsync(
            editor,
            Key(CatalogEntity.Categories, "dining"),
            new CatalogFields { NameAr = "x", NameEn = "Dining", Icon = "fork", Color = "#112233", Bucket = "wants", Sort = 1 },
            CancellationToken.None);
        await Catalog.PutAsync(
            editor,
            Key(CatalogEntity.Categories, "groceries"),
            new CatalogFields { NameAr = "y", NameEn = "Groceries", Icon = "cart", Color = "#223344", Bucket = "needs", Sort = 2 },
            CancellationToken.None);
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

    public ICatalogAdminStore Catalog => Services.GetRequiredService<ICatalogAdminStore>();

    public static CatalogEntryKey Key(CatalogEntity entity, string id) =>
        CatalogKeys.TryParse(entity, id, out var key) ? key : throw new InvalidOperationException("bad key");

    public async Task<Guid> NewOperatorAsync()
    {
        var id = Guid.NewGuid();
        await Db.ExecuteAsync(
            Database.Migrator,
            "INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ($1, $2, $3, ARRAY['catalog_editor'])",
            id,
            "sub-" + id,
            "Test operator");
        return id;
    }
}

/// <summary>T-129: aggregation, review queue, promote and reject against PostgreSQL.</summary>
public class ContributionStoreTests(ContributionStoreFixture fixture) : IClassFixture<ContributionStoreFixture>
{
    private IContributionAdminStore Admin => fixture.Services.GetRequiredService<IContributionAdminStore>();

    private IContributionAggregationStore Aggregation => fixture.Services.GetRequiredService<IContributionAggregationStore>();

    // Letters only: a random hex suffix could contain a run of 6 digits, which the privacy CHECK refuses.
    private static string Unique(string prefix) =>
        prefix + " " + string.Concat(Guid.NewGuid().ToByteArray().Take(8).Select(b => (char)('a' + (b % 26))));

    private static Task<AggregationRun> RunAsync(ContributionStoreFixture f, DateTimeOffset? cutoff = null) =>
        f.Services.GetRequiredService<IContributionAggregationStore>()
            .RunAsync(ContributionRules.MinDistinctInstalls, cutoff ?? DateTimeOffset.UtcNow.AddDays(-ContributionRules.RawRetentionDays), CancellationToken.None);

    private async Task SeedRawAsync(string norm, string institution, string category, int installs, DateTimeOffset? receivedAt = null)
    {
        for (var i = 0; i < installs; i++)
        {
            await Db.ExecuteAsync(
                fixture.Database.Migrator,
                "INSERT INTO zaghlol.merchant_contributions (id, merchant_norm, institution_code, category_code, install_hash, received_at) VALUES ($1, $2, $3, $4, $5, $6)",
                Guid.NewGuid(),
                norm,
                institution,
                category,
                RandomNumberGenerator.GetBytes(32),
                receivedAt ?? DateTimeOffset.UtcNow);
        }
    }

    private async Task<(string Status, int Installs, string Top)> AggregateAsync(string norm, string institution)
    {
        var rows = await Db.QueryAsync(
            fixture.Database.Migrator,
            "SELECT status, distinct_installs, top_category_code FROM zaghlol.contribution_aggregates WHERE merchant_norm = $1 AND institution_code = $2",
            norm,
            institution);
        var row = Assert.Single(rows);
        return ((string)row[0]!, (int)row[1]!, (string)row[2]!);
    }

    private async Task<long> RawCountAsync(string norm, string institution) =>
        (long)(await Db.ScalarAsync(
            fixture.Database.Migrator,
            "SELECT count(*) FROM zaghlol.merchant_contributions WHERE merchant_norm = $1 AND institution_code = $2",
            norm,
            institution))!;

    private async Task<long> AuditCountAsync(Guid operatorId, string action) =>
        (long)(await Db.ScalarAsync(
            fixture.Database.Migrator,
            "SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = $1 AND action = $2",
            operatorId,
            action))!;

    private async Task<ContributionKey> ReadyAsync(string prefix, string category = "dining", int installs = 5)
    {
        var norm = Unique(prefix);
        await SeedRawAsync(norm, "nbe", category, installs);
        await RunAsync(fixture);
        return new ContributionKey(norm, "nbe");
    }

    // ---- Aggregation ---------------------------------------------------------------------------------------------------

    [Fact]
    public async Task FourInstallsCollectAndAFifthMakesTheAggregateReadyForReview()
    {
        var norm = Unique("koshary");
        await SeedRawAsync(norm, "nbe", "dining", 4);

        await RunAsync(fixture);
        Assert.Equal(("collecting", 4, "dining"), await AggregateAsync(norm, "nbe"));
        Assert.DoesNotContain(await Admin.ListAsync(ContributionReviewStatus.ReadyForReview, CancellationToken.None), a => a.MerchantNorm == norm);

        await SeedRawAsync(norm, "nbe", "dining", 1);
        var run = await RunAsync(fixture);

        Assert.True(run.BecameReady >= 1);
        Assert.Equal(("ready_for_review", 5, "dining"), await AggregateAsync(norm, "nbe"));
        var listed = Assert.Single(await Admin.ListAsync(ContributionReviewStatus.ReadyForReview, CancellationToken.None), a => a.MerchantNorm == norm);
        Assert.Equal(new ContributionAggregateView(norm, "nbe", "dining", 5, ContributionReviewStatus.ReadyForReview), listed);
    }

    [Fact]
    public async Task TheSameMerchantAtTwoInstitutionsIsTwoAggregates()
    {
        var norm = Unique("pharmacy");
        await SeedRawAsync(norm, "nbe", "dining", 5);
        await SeedRawAsync(norm, "cib", "dining", 2);

        await RunAsync(fixture);

        Assert.Equal("ready_for_review", (await AggregateAsync(norm, "nbe")).Status);
        Assert.Equal("collecting", (await AggregateAsync(norm, "cib")).Status);
    }

    [Fact]
    public async Task TheTopCategoryIsTheMostVotedWithTiesBrokenByCode()
    {
        var voted = Unique("voted");
        await SeedRawAsync(voted, "nbe", "dining", 2);
        await SeedRawAsync(voted, "nbe", "groceries", 3);
        var tied = Unique("tied");
        await SeedRawAsync(tied, "nbe", "groceries", 3);
        await SeedRawAsync(tied, "nbe", "dining", 3);

        await RunAsync(fixture);

        Assert.Equal("groceries", (await AggregateAsync(voted, "nbe")).Top);
        Assert.Equal("dining", (await AggregateAsync(tied, "nbe")).Top);
        var votes = (string)(await Db.ScalarAsync(
            fixture.Database.Migrator,
            "SELECT category_votes::text FROM zaghlol.contribution_aggregates WHERE merchant_norm = $1",
            voted))!;
        Assert.Contains("\"groceries\": 3", votes, StringComparison.Ordinal);
        Assert.Contains("\"dining\": 2", votes, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AReadyAggregateNeverShrinksOrFallsBackWhenOldRawRowsGo()
    {
        var key = await ReadyAsync("sticky", installs: 6);
        await Db.ExecuteAsync(
            fixture.Database.Migrator,
            "DELETE FROM zaghlol.merchant_contributions WHERE id IN (SELECT id FROM zaghlol.merchant_contributions WHERE merchant_norm = $1 LIMIT 3)",
            key.MerchantNorm);

        await RunAsync(fixture);

        Assert.Equal(("ready_for_review", 6, "dining"), await AggregateAsync(key.MerchantNorm, "nbe"));
    }

    [Fact]
    public async Task RawRowsOfPromotedAndRejectedAggregatesArePurgedAndTheAggregatesAreLeftAlone()
    {
        var promoted = await ReadyAsync("to promote");
        var rejected = await ReadyAsync("to reject");
        var op = await fixture.NewOperatorAsync();
        Assert.Equal(ContributionOutcome.Ok, (await Admin.PromoteAsync(op, promoted, null, null, CancellationToken.None)).Outcome);
        Assert.Equal(ContributionOutcome.Ok, (await Admin.RejectAsync(op, rejected, CancellationToken.None)).Outcome);
        Assert.Equal(5, await RawCountAsync(promoted.MerchantNorm, "nbe"));

        // New contributions arrive for a decided key: they are purged too and never reopen it.
        await SeedRawAsync(promoted.MerchantNorm, "nbe", "groceries", 3);
        var run = await RunAsync(fixture);

        Assert.True(run.PurgedDecided >= 13);
        Assert.Equal(0, await RawCountAsync(promoted.MerchantNorm, "nbe"));
        Assert.Equal(0, await RawCountAsync(rejected.MerchantNorm, "nbe"));
        Assert.Equal(("promoted", 5, "dining"), await AggregateAsync(promoted.MerchantNorm, "nbe"));
        Assert.Equal(("rejected", 5, "dining"), await AggregateAsync(rejected.MerchantNorm, "nbe"));
    }

    [Fact]
    public async Task RawRowsOlderThanTheRetentionAreDeletedAndAnEmptyCollectingAggregateIsReset()
    {
        var norm = Unique("old");
        await SeedRawAsync(norm, "nbe", "dining", 3, DateTimeOffset.UtcNow.AddDays(-200));
        await SeedRawAsync(norm, "cib", "dining", 2);
        await RunAsync(fixture, DateTimeOffset.UtcNow.AddDays(-400)); // before they expire: both counted
        Assert.Equal(3, (await AggregateAsync(norm, "nbe")).Installs);

        var run = await RunAsync(fixture);

        Assert.True(run.PurgedExpired >= 3);
        Assert.Equal(0, await RawCountAsync(norm, "nbe"));
        Assert.Equal(2, await RawCountAsync(norm, "cib"));
        Assert.Equal(("collecting", 0, "dining"), await AggregateAsync(norm, "nbe"));
        Assert.Equal(2, (await AggregateAsync(norm, "cib")).Installs);
    }

    [Fact]
    public async Task AggregatesHoldCountsAndCodesNeverInstallHashes()
    {
        var key = await ReadyAsync("columns");
        var columns = await Db.QueryAsync(
            fixture.Database.Migrator,
            "SELECT column_name FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name = 'contribution_aggregates' ORDER BY ordinal_position");
        Assert.DoesNotContain(columns, c => ((string)c[0]!).Contains("hash", StringComparison.Ordinal));
        Assert.Equal("ready_for_review", (await AggregateAsync(key.MerchantNorm, "nbe")).Status);
    }

    // ---- Review queue and decisions -----------------------------------------------------------------------------------

    [Fact]
    public async Task ListingFiltersByStatusAndNeverShowsCollecting()
    {
        var ready = await ReadyAsync("list ready");
        var collecting = Unique("list collecting");
        await SeedRawAsync(collecting, "nbe", "dining", 4);
        await RunAsync(fixture);
        var op = await fixture.NewOperatorAsync();
        var rejected = await ReadyAsync("list rejected");
        await Admin.RejectAsync(op, rejected, CancellationToken.None);

        var queue = await Admin.ListAsync(ContributionReviewStatus.ReadyForReview, CancellationToken.None);
        var done = await Admin.ListAsync(ContributionReviewStatus.Rejected, CancellationToken.None);

        Assert.Contains(queue, a => a.MerchantNorm == ready.MerchantNorm);
        Assert.DoesNotContain(queue, a => a.MerchantNorm == collecting || a.MerchantNorm == rejected.MerchantNorm);
        Assert.Contains(done, a => a.MerchantNorm == rejected.MerchantNorm);
        foreach (var status in Enum.GetValues<ContributionReviewStatus>())
        {
            Assert.DoesNotContain(await Admin.ListAsync(status, CancellationToken.None), a => a.MerchantNorm == collecting);
        }
    }

    [Fact]
    public async Task PromotingWithoutAMerchantCreatesADraftMerchantWithAnExactAliasAndPublishesNothing()
    {
        var key = await ReadyAsync("new merchant", "groceries");
        var op = await fixture.NewOperatorAsync();
        var versionsBefore = (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_versions"))!;

        var decision = await Admin.PromoteAsync(op, key, null, null, CancellationToken.None);

        Assert.Equal(ContributionOutcome.Ok, decision.Outcome);
        Assert.Equal(ContributionReviewStatus.Promoted, decision.Status);
        var merchantId = decision.MerchantId!.Value;
        var merchant = Assert.Single(await Db.QueryAsync(
            fixture.Database.Migrator,
            "SELECT body ->> 'canonical', body ->> 'category', changed, published, deleted FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND entry_key = $1",
            merchantId.ToString(CultureInfo.InvariantCulture)));
        Assert.Equal(key.MerchantNorm, merchant[0]);
        Assert.Equal("groceries", merchant[1]); // the top vote
        Assert.True((bool)merchant[2]!);
        Assert.False((bool)merchant[3]!);
        var alias = Assert.Single(await Db.QueryAsync(
            fixture.Database.Migrator,
            "SELECT body ->> 'match' FROM zaghlol.catalog_drafts WHERE entity = 'aliases' AND entry_key = $1",
            merchantId.ToString(CultureInfo.InvariantCulture) + ":" + key.MerchantNorm));
        Assert.Equal("exact", alias[0]);

        // Nothing goes live without a publish.
        Assert.Equal(versionsBefore, (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_versions"))!);
        Assert.Equal(0L, await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_merchants WHERE canonical = $1", key.MerchantNorm));
        Assert.Equal("promoted", (await AggregateAsync(key.MerchantNorm, "nbe")).Status);
        var reviewer = Assert.Single(await Db.QueryAsync(
            fixture.Database.Migrator,
            "SELECT reviewed_by, reviewed_at IS NOT NULL FROM zaghlol.contribution_aggregates WHERE merchant_norm = $1",
            key.MerchantNorm));
        Assert.Equal(op, reviewer[0]);
        Assert.True((bool)reviewer[1]!);
        Assert.Equal(1, await AuditCountAsync(op, "contribution_promote"));
    }

    [Fact]
    public async Task PromotingWithACategoryCodeUsesIt()
    {
        var key = await ReadyAsync("category override", "groceries");
        var op = await fixture.NewOperatorAsync();

        var decision = await Admin.PromoteAsync(op, key, null, "dining", CancellationToken.None);

        Assert.Equal(ContributionOutcome.Ok, decision.Outcome);
        Assert.Equal(
            "dining",
            await Db.ScalarAsync(
                fixture.Database.Migrator,
                "SELECT body ->> 'category' FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND entry_key = $1",
                decision.MerchantId!.Value.ToString(CultureInfo.InvariantCulture)));
    }

    [Fact]
    public async Task PromotingWithAMerchantIdAttachesAnExactAliasToThatMerchantOnly()
    {
        var key = await ReadyAsync("alias target");
        var op = await fixture.NewOperatorAsync();
        var created = await fixture.Catalog.CreateMerchantAsync(
            op,
            new CatalogFields { Canonical = Unique("canonical"), NameAr = "m", Category = "groceries" },
            CancellationToken.None);
        var merchantId = created.Op!.Key.MerchantId;
        var merchantsBefore = (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!;

        var decision = await Admin.PromoteAsync(op, key, merchantId, "dining", CancellationToken.None);

        Assert.Equal(ContributionOutcome.Ok, decision.Outcome);
        Assert.Equal(merchantId, decision.MerchantId);
        Assert.Equal(merchantsBefore, (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!);
        Assert.Equal(
            1L,
            await Db.ScalarAsync(
                fixture.Database.Migrator,
                "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'aliases' AND entry_key = $1 AND NOT deleted",
                merchantId.ToString(CultureInfo.InvariantCulture) + ":" + key.MerchantNorm));
    }

    [Fact]
    public async Task PromotingAnAlreadyDecidedAggregateIsAConflictAndChangesNothing()
    {
        var promoted = await ReadyAsync("twice");
        var rejected = await ReadyAsync("reject then promote");
        var op = await fixture.NewOperatorAsync();
        Assert.Equal(ContributionOutcome.Ok, (await Admin.PromoteAsync(op, promoted, null, null, CancellationToken.None)).Outcome);
        Assert.Equal(ContributionOutcome.Ok, (await Admin.RejectAsync(op, rejected, CancellationToken.None)).Outcome);
        var merchants = (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!;

        Assert.Equal(ContributionOutcome.Conflict, (await Admin.PromoteAsync(op, promoted, null, null, CancellationToken.None)).Outcome);
        Assert.Equal(ContributionOutcome.Conflict, (await Admin.RejectAsync(op, promoted, CancellationToken.None)).Outcome);
        Assert.Equal(ContributionOutcome.Conflict, (await Admin.PromoteAsync(op, rejected, null, null, CancellationToken.None)).Outcome);
        Assert.Equal(ContributionOutcome.Conflict, (await Admin.RejectAsync(op, rejected, CancellationToken.None)).Outcome);

        Assert.Equal(merchants, (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!);
        Assert.Equal(1, await AuditCountAsync(op, "contribution_promote"));
        Assert.Equal(1, await AuditCountAsync(op, "contribution_reject"));
    }

    [Fact]
    public async Task ACollectingKeyAndAnAbsentKeyAreTheSameNotFoundAndWriteNothing()
    {
        var collecting = Unique("collecting");
        await SeedRawAsync(collecting, "nbe", "dining", 4);
        await RunAsync(fixture);
        var op = await fixture.NewOperatorAsync();
        var absent = new ContributionKey(Unique("absent"), "nbe");
        var present = new ContributionKey(collecting, "nbe");
        var draftsBefore = (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts"))!;

        foreach (var key in new[] { absent, present })
        {
            Assert.Equal(new ContributionDecision(ContributionOutcome.NotFound), await Admin.PromoteAsync(op, key, null, null, CancellationToken.None));
            Assert.Equal(new ContributionDecision(ContributionOutcome.NotFound), await Admin.PromoteAsync(op, key, 1, "dining", CancellationToken.None));
            Assert.Equal(new ContributionDecision(ContributionOutcome.NotFound), await Admin.RejectAsync(op, key, CancellationToken.None));
        }

        Assert.Equal(draftsBefore, (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts"))!);
        Assert.Equal("collecting", (await AggregateAsync(collecting, "nbe")).Status);
        Assert.Equal(0, await AuditCountAsync(op, "contribution_promote"));
        Assert.Equal(0, await AuditCountAsync(op, "contribution_reject"));
    }

    [Fact]
    public async Task ADraftConflictRollsEverythingBackAndLeavesTheAggregateReady()
    {
        var key = await ReadyAsync("conflicts");
        var op = await fixture.NewOperatorAsync();
        var merchants = (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!;

        // A category that is not live in the draft, a merchant that does not exist, and a merchant that already has this canonical name.
        Assert.Equal(ContributionOutcome.Conflict, (await Admin.PromoteAsync(op, key, null, "no_such_category", CancellationToken.None)).Outcome);
        Assert.Equal(ContributionOutcome.Conflict, (await Admin.PromoteAsync(op, key, 2_000_000_000, null, CancellationToken.None)).Outcome);
        var clash = await fixture.Catalog.CreateMerchantAsync(
            op,
            new CatalogFields { Canonical = key.MerchantNorm, NameAr = "m", Category = "dining" },
            CancellationToken.None);
        Assert.Equal(DraftStatus.Ok, clash.Status);
        Assert.Equal(ContributionOutcome.Conflict, (await Admin.PromoteAsync(op, key, null, null, CancellationToken.None)).Outcome);

        Assert.Equal(merchants + 1, (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!);
        Assert.Equal("ready_for_review", (await AggregateAsync(key.MerchantNorm, "nbe")).Status);
        Assert.Equal(0, await AuditCountAsync(op, "contribution_promote"));
    }

    [Fact]
    public async Task APromoteWhoseAliasIsNotAValidCatalogAliasRollsTheMerchantBack()
    {
        var norm = "كشري " + Unique("x"); // an alias is a Latin string
        await SeedRawAsync(norm, "nbe", "dining", 5);
        await RunAsync(fixture);
        var op = await fixture.NewOperatorAsync();
        var merchants = (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!;

        var decision = await Admin.PromoteAsync(op, new ContributionKey(norm, "nbe"), null, null, CancellationToken.None);

        Assert.Equal(ContributionOutcome.Conflict, decision.Outcome);
        Assert.Equal(merchants, (long)(await Db.ScalarAsync(fixture.Database.Migrator, "SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants'"))!);
        Assert.Equal("ready_for_review", (await AggregateAsync(norm, "nbe")).Status);
        Assert.Equal(ContributionOutcome.Ok, (await Admin.RejectAsync(op, new ContributionKey(norm, "nbe"), CancellationToken.None)).Outcome);
    }

    [Fact]
    public async Task TwoOperatorsDecidingAtOnceGiveOneWinner()
    {
        var key = await ReadyAsync("race");
        var op1 = await fixture.NewOperatorAsync();
        var op2 = await fixture.NewOperatorAsync();

        var results = await Task.WhenAll(
            Admin.PromoteAsync(op1, key, null, null, CancellationToken.None),
            Admin.RejectAsync(op2, key, CancellationToken.None),
            Admin.PromoteAsync(op2, key, null, null, CancellationToken.None));

        Assert.Equal(1, results.Count(r => r.Outcome == ContributionOutcome.Ok));
        Assert.Equal(2, results.Count(r => r.Outcome == ContributionOutcome.Conflict));
        var status = (await AggregateAsync(key.MerchantNorm, "nbe")).Status;
        Assert.Contains(status, new[] { "promoted", "rejected" });
    }

    [Fact]
    public async Task TheAuditRowsKeepTheMerchantTextOnlyEncoded()
    {
        var key = await ReadyAsync("audit");
        var op = await fixture.NewOperatorAsync();
        await Admin.PromoteAsync(op, key, null, null, CancellationToken.None);

        var row = Assert.Single(await Db.QueryAsync(
            fixture.Database.Migrator,
            "SELECT target, details::text FROM zaghlol.audit_log WHERE operator_id = $1 AND action = 'contribution_promote'",
            op));

        Assert.Equal("contribution/nbe:" + CatalogKeys.EncodeText(key.MerchantNorm), row[0]);
        Assert.DoesNotContain(key.MerchantNorm, (string)row[1]!, StringComparison.Ordinal);
    }
}
