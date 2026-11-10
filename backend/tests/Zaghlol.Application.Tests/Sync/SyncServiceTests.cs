using Zaghlol.Application.Catalog;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Prices;
using Zaghlol.Application.Sync;
using Zaghlol.Application.Tests.Prices;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Sync;

/// <summary>The sync pipeline over fakes: throttle, composition order, failure modes and the extension point.</summary>
public class SyncServiceTests
{
    private static readonly InstallId Id = InstallId.Parse("00000000-0000-4000-8000-000000000001");
    private static readonly DateTimeOffset T0 = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);

    private readonly TestClock clock = new(T0.AddTicks(4321));
    private readonly FakeSyncStore store = new();
    private readonly FakeCatalog catalog = new();
    private readonly FakeFlags flags = new();
    private readonly MemoryPriceStore prices = new();
    private readonly FakeEntitlement entitlement = new();
    private readonly FakeHasher hasher = new();
    private readonly RecordingTelemetry telemetry = new();

    private SyncService Service => new(
        store, catalog, flags, new PriceReadService(prices, clock), entitlement, hasher, telemetry, SyncOptions.Default, clock);

    private static SyncRequestData Request(
        int catalogVersion = 0,
        int flagsVersion = 0,
        DateTimeOffset? pricesAsOf = null,
        DateTimeOffset? entitlementIssuedAt = null,
        IReadOnlyList<SyncContribution>? contributions = null,
        IReadOnlyList<SyncBankRequest>? bankRequests = null) =>
        new(catalogVersion, flagsVersion, pricesAsOf, entitlementIssuedAt, contributions ?? [], bankRequests ?? []);

    private Task<SyncResult> SyncAsync(SyncRequestData request, string appVersion = "1.0.0") =>
        Service.SyncAsync(Id, appVersion, request, CancellationToken.None);

    [Fact]
    public async Task AFirstSyncIsFullAtWholeSecondsAndClaimsTheWindow()
    {
        catalog.Latest = 3;

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request()));

        Assert.Equal(T0, result.ServerTime);
        Assert.Equal(T0.AddHours(24), result.NextSyncNotBefore);
        Assert.Equal(CatalogModes.Full, result.Catalog!.Mode);
        Assert.Equal(new Uri("https://cdn.test/v1/catalog/3/full"), result.Catalog.FullUrl);
        Assert.Empty(result.Catalog.Ops);
        Assert.Equal(0, result.Catalog.FromVersion);
        var claim = Assert.Single(store.Claims);
        Assert.Equal(T0, claim.Now);
        Assert.Equal("android", claim.Platform);
        Assert.Null(claim.InstallHash);
        Assert.Contains((SyncTags.Ok, 1), telemetry.Requests);
    }

    [Fact]
    public async Task InsideTheWindowTheAnswerIsTheThrottleAndNothingIsReadOrWritten()
    {
        store.Install = store.Install! with { LastSyncAt = T0.AddHours(-23).AddMinutes(-59) };
        catalog.Throws = true; // proves no source is read

        var result = Assert.IsType<SyncThrottled>(await SyncAsync(Request(contributions: [new SyncContribution("koshary", "nbe", "dining")])));

        Assert.Equal(T0, result.ServerTime);
        Assert.Equal(T0.AddMinutes(1), result.NextSyncNotBefore);
        Assert.Empty(store.Claims);
        Assert.Equal(0, hasher.Calls);
        Assert.Equal(0, entitlement.Calls);
        Assert.Contains((SyncTags.Throttled, 1), telemetry.Requests);
    }

    [Fact]
    public async Task AtTheEndOfTheWindowTheSyncIsFullAgain()
    {
        store.Install = store.Install! with { LastSyncAt = T0.AddHours(-24) };

        Assert.IsType<SyncCompleted>(await SyncAsync(Request()));
    }

    [Fact]
    public async Task ALostClaimRaceIsTheThrottleAnswerOfTheWinner()
    {
        store.LoseClaim = T0.AddSeconds(-2);

        var result = Assert.IsType<SyncThrottled>(await SyncAsync(Request()));

        Assert.Equal(T0.AddSeconds(-2).AddHours(24), result.NextSyncNotBefore);
    }

    [Fact]
    public async Task AMissingOrDeletedInstallIsGone()
    {
        store.Install = null;

        Assert.IsType<SyncInstallGone>(await SyncAsync(Request()));
        Assert.Empty(store.Claims);
    }

    [Fact]
    public async Task AnUpToDateClientGetsNullBlocks()
    {
        catalog.Latest = 3;
        flags.Stored = [new FlagState("zakah", false, FlagRules.None, 2, T0)];
        await prices.ApplyFeedAsync(new NormalizedPrices([new StoredGold("XAU24_G", "EGP", 4800m, "fake")], []), T0.AddMinutes(-5), CancellationToken.None);

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request(3, 2, T0.AddMinutes(-5))));

        Assert.True(result.UpToDate);
        Assert.Null(result.Catalog);
        Assert.Null(result.Flags);
        Assert.Null(result.Prices);
        Assert.Equal(new SyncAcceptedCounts(0, 0), result.Accepted);
        Assert.Contains((CatalogModes.None, 1), telemetry.Modes);
    }

    [Fact]
    public async Task ADeltaCarriesTheOpsAndEchoesFromVersion()
    {
        catalog.Latest = 5;
        catalog.Ops = [Op("dining")];

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request(catalogVersion: 4)));

        Assert.Equal(CatalogModes.Delta, result.Catalog!.Mode);
        Assert.Equal(4, result.Catalog.FromVersion);
        Assert.Equal(5, result.Catalog.ToVersion);
        Assert.Null(result.Catalog.FullUrl);
        Assert.Single(result.Catalog.Ops);
    }

    [Fact]
    public async Task ADeltaOverTheOpCapIsSentAsFull()
    {
        catalog.Latest = 5;
        catalog.Ops = Enumerable.Range(0, SyncOptions.Default.MaxDeltaOps + 1).Select(i => Op("c" + i)).ToList();

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request(catalogVersion: 4)));

        Assert.Equal(CatalogModes.Full, result.Catalog!.Mode);
        Assert.Empty(result.Catalog.Ops);
    }

    [Fact]
    public async Task FlagsAreSentWhenTheAppVersionChangedEvenIfTheirVersionDidNot()
    {
        flags.Stored = [new FlagState("zakah", true, new FlagRules(null, "1.1.0", null), 1, T0)];

        var same = Assert.IsType<SyncCompleted>(await SyncAsync(Request(flagsVersion: 1)));
        store.Reset();
        var updated = Assert.IsType<SyncCompleted>(await SyncAsync(Request(flagsVersion: 1), appVersion: "1.1.0"));

        Assert.Null(same.Flags);
        Assert.True(updated.Flags!.Values["zakah"]);
    }

    [Fact]
    public async Task CorruptFlagRulesAreOffAndCountedNotAFailure()
    {
        flags.Stored = [new FlagState("smart_roi", true, FlagRules.None, 3, T0, RulesInvalid: true)];

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request()));

        Assert.False(result.Flags!.Values["smart_roi"]);
        Assert.Equal("smart_roi", Assert.Single(telemetry.InvalidFlags));
    }

    [Fact]
    public async Task ACatalogFailureIs503WithNothingWrittenAndTheRetrySucceeds()
    {
        catalog.Throws = true;

        await Assert.ThrowsAsync<SyncSourceUnavailableException>(() => SyncAsync(Request()));
        Assert.Empty(store.Claims);
        Assert.Equal(SyncTags.CatalogBlock, Assert.Single(telemetry.Failures));

        catalog.Throws = false;
        Assert.IsType<SyncCompleted>(await SyncAsync(Request()));
    }

    [Fact]
    public async Task AMissingVersionRowForAFullAnswerIs503()
    {
        catalog.Latest = 3;
        catalog.VersionRowMissing = true;

        await Assert.ThrowsAsync<SyncSourceUnavailableException>(() => SyncAsync(Request()));
        Assert.Empty(store.Claims);
    }

    [Fact]
    public async Task AFlagReadFailureIs503()
    {
        flags.Throws = true;

        await Assert.ThrowsAsync<SyncSourceUnavailableException>(() => SyncAsync(Request()));
        Assert.Empty(store.Claims);
        Assert.Equal(SyncTags.FlagsBlock, Assert.Single(telemetry.Failures));
    }

    [Fact]
    public async Task APriceFailureDegradesToNullPrices()
    {
        var result = Assert.IsType<SyncCompleted>(await new SyncService(
                store, catalog, flags, new PriceReadService(new ThrowingPriceReader(), clock), entitlement, hasher, telemetry, SyncOptions.Default, clock)
            .SyncAsync(Id, "1.0.0", Request(), CancellationToken.None));

        Assert.Null(result.Prices);
        Assert.Single(store.Claims);
        Assert.Equal(SyncTags.PricesBlock, Assert.Single(telemetry.Failures));
    }

    [Fact]
    public async Task AnEntitlementBlockFailureIs503BeforeAnyWrite()
    {
        entitlement.Throws = true;

        await Assert.ThrowsAsync<SyncSourceUnavailableException>(() => SyncAsync(Request()));
        Assert.Empty(store.Claims);
        Assert.Equal(SyncTags.EntitlementBlock, Assert.Single(telemetry.Failures));
    }

    [Fact]
    public async Task TheEntitlementBlockGetsEntitlementIssuedAtUnchangedAndItsResultIsReturned()
    {
        var issuedAt = new DateTimeOffset(2026, 10, 30, 10, 0, 0, 123, TimeSpan.Zero);
        entitlement.Result = new SyncEntitlementResult("e.y.z", "a.b.c", "gold_linked_by_support");

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request(entitlementIssuedAt: issuedAt)));

        Assert.Equal(new SyncEntitlementContext(Id, issuedAt, T0), entitlement.Seen);
        Assert.Equal(entitlement.Result, result.Entitlement);
        Assert.False(result.UpToDate);
    }

    [Fact]
    public async Task TheDefaultEntitlementBlockReturnsNulls()
    {
        Assert.Equal(
            SyncEntitlementResult.None,
            await new NullSyncEntitlementBlock().ComposeAsync(new SyncEntitlementContext(Id, null, T0), CancellationToken.None));
        Assert.Equal(new SyncEntitlementResult(null, null, null), SyncEntitlementResult.None);
    }

    [Fact]
    public async Task IntakeIsFilteredHashedOnceAndCountedFromInsertedRows()
    {
        catalog.Categories = new HashSet<string>(["dining"], StringComparer.Ordinal);
        store.InsertedContributions = 1;

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request(
            contributions:
            [
                new SyncContribution("Koshary El Tahrir", "nbe", "dining"),
                new SyncContribution("Abu Tarek", "nbe", "dining"),
                new SyncContribution("010 1234 5678", "nbe", "dining"),
                new SyncContribution("mine", "nbe", "my_category"),
            ],
            bankRequests: [new SyncBankRequest("Banque du Caire", "EG", "sms")])));

        var claim = Assert.Single(store.Claims);
        Assert.Equal(1, hasher.Calls);
        Assert.Equal(FakeHasher.Hash, claim.InstallHash!.Value.ToArray());
        Assert.Equal(2, claim.Contributions.Count);
        Assert.Single(claim.BankRequests);
        Assert.Equal(new SyncAcceptedCounts(1, 1), result.Accepted);
        Assert.Contains((SyncTags.Contribution, SyncTags.Filtered, 1), telemetry.Intakes);
        Assert.Contains((SyncTags.Contribution, SyncTags.InvalidCode, 1), telemetry.Intakes);
        Assert.Contains((SyncTags.Contribution, SyncTags.Duplicate, 1), telemetry.Intakes); // one already stored
        Assert.Contains((SyncTags.Contribution, SyncTags.Accepted, 1), telemetry.Intakes);
    }

    [Fact]
    public async Task AHasherOutageDropsTheIntakeButTheSyncSucceeds()
    {
        catalog.Categories = new HashSet<string>(["dining"], StringComparer.Ordinal);
        hasher.Throws = true;

        var result = Assert.IsType<SyncCompleted>(await SyncAsync(Request(contributions: [new SyncContribution("koshary", "nbe", "dining")])));

        var claim = Assert.Single(store.Claims);
        Assert.Null(claim.InstallHash);
        Assert.Empty(claim.Contributions);
        Assert.Equal(new SyncAcceptedCounts(0, 0), result.Accepted);
        Assert.Equal(1, telemetry.HashUnavailable);
        Assert.Contains((SyncTags.Contribution, SyncTags.DroppedHasher, 1), telemetry.Intakes);
    }

    [Fact]
    public async Task NoIntakeMeansNoHashAndNoCategoryRead()
    {
        catalog.CategoriesThrow = true;

        Assert.IsType<SyncCompleted>(await SyncAsync(Request()));
        Assert.Equal(0, hasher.Calls);
    }

    private static CatalogOp Op(string code) =>
        new(new CatalogEntryKey { Entity = CatalogEntity.Categories, PathId = code, StorageKey = code, Code = code }, false, new CatalogFields { NameAr = "x", NameEn = "x" });

    private sealed class FakeSyncStore : ISyncStore
    {
        public SyncInstall? Install { get; set; } = new("android", "1.0.0", null);

        public DateTimeOffset? LoseClaim { get; set; }

        public int InsertedContributions { get; set; } = -1;

        public List<SyncClaim> Claims { get; } = [];

        public void Reset()
        {
            Claims.Clear();
            Install = Install! with { LastSyncAt = null };
        }

        public Task<SyncInstall?> FindInstallAsync(InstallId installId, CancellationToken cancellationToken) => Task.FromResult(Install);

        public Task<SyncClaimResult> ClaimAsync(SyncClaim claim, CancellationToken cancellationToken)
        {
            if (LoseClaim is { } winner)
            {
                Install = Install! with { LastSyncAt = winner };
                return Task.FromResult(SyncClaimResult.Lost);
            }

            Claims.Add(claim);
            var contributions = InsertedContributions >= 0 ? InsertedContributions : claim.Contributions.Count;
            return Task.FromResult(new SyncClaimResult(true, contributions, claim.BankRequests.Count));
        }
    }

    private sealed class FakeCatalog : ICatalogReader
    {
        public int Latest { get; set; }

        public bool Throws { get; set; }

        public bool VersionRowMissing { get; set; }

        public bool CategoriesThrow { get; set; }

        public IReadOnlyList<CatalogOp> Ops { get; set; } = [];

        public IReadOnlySet<string> Categories { get; set; } = new HashSet<string>(StringComparer.Ordinal);

        public Task<CatalogVersionInfo?> FindVersionAsync(int version, CancellationToken cancellationToken) =>
            Task.FromResult<CatalogVersionInfo?>(VersionRowMissing
                ? null
                : new CatalogVersionInfo(version, T0, new byte[32], new Uri($"https://cdn.test/v1/catalog/{version}/full")));

        public Task<int> LatestVersionAsync(CancellationToken cancellationToken) =>
            Throws ? throw new InvalidOperationException("catalog down") : Task.FromResult(Latest);

        public Task<IReadOnlyList<CatalogOp>> DeltaAsync(int fromVersion, int toVersion, CancellationToken cancellationToken) => Task.FromResult(Ops);

        public Task<IReadOnlySet<string>> CategoryCodesAsync(CancellationToken cancellationToken) =>
            CategoriesThrow ? throw new InvalidOperationException("categories down") : Task.FromResult(Categories);
    }

    private sealed class FakeFlags : IFlagReader
    {
        public bool Throws { get; set; }

        public IReadOnlyList<FlagState> Stored { get; set; } = [];

        public Task<IReadOnlyList<FlagState>> ListAsync(CancellationToken cancellationToken) =>
            Throws ? throw new InvalidOperationException("flags down") : Task.FromResult(Stored);
    }

    private sealed class ThrowingPriceReader : IPriceReader
    {
        public Task<IReadOnlyList<PriceRow>> ListGoldAsync(CancellationToken cancellationToken) => throw new InvalidOperationException("prices down");

        public Task<IReadOnlyList<FxRow>> ListFxAsync(CancellationToken cancellationToken) => throw new InvalidOperationException("prices down");
    }

    private sealed class FakeEntitlement : ISyncEntitlementBlock
    {
        public bool Throws { get; set; }

        public int Calls { get; private set; }

        public SyncEntitlementContext? Seen { get; private set; }

        public SyncEntitlementResult Result { get; set; } = SyncEntitlementResult.None;

        public Task<SyncEntitlementResult> ComposeAsync(SyncEntitlementContext context, CancellationToken cancellationToken)
        {
            Calls++;
            Seen = context;
            return Throws ? throw new InvalidOperationException("entitlement down") : Task.FromResult(Result);
        }
    }

    private sealed class FakeHasher : IInstallHasher
    {
        public static readonly byte[] Hash = Enumerable.Repeat((byte)7, 32).ToArray();

        public bool Throws { get; set; }

        public int Calls { get; private set; }

        public ValueTask<byte[]> HashAsync(InstallId installId, CancellationToken cancellationToken)
        {
            Calls++;
            return Throws ? throw new InvalidOperationException("kms down") : ValueTask.FromResult(Hash);
        }
    }

    private sealed class RecordingTelemetry : ISyncTelemetry
    {
        public List<(string, int)> Requests { get; } = [];

        public List<(string, int)> Modes { get; } = [];

        public List<(string, string, int)> Intakes { get; } = [];

        public List<string> Failures { get; } = [];

        public List<string> InvalidFlags { get; } = [];

        public int HashUnavailable { get; private set; }

        public void Request(string outcome) => Requests.Add((outcome, 1));

        public void Catalog(string mode) => Modes.Add((mode, 1));

        public void Intake(string kind, string result, int count)
        {
            if (count > 0)
            {
                Intakes.Add((kind, result, count));
            }
        }

        public void BlockFailed(string block) => Failures.Add(block);

        public void FlagRulesInvalid(string flag) => InvalidFlags.Add(flag);

        public void InstallHashUnavailable() => HashUnavailable++;
    }
}
