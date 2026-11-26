using Zaghlol.Application.Config;

namespace Zaghlol.Application.Tests.Config;

/// <summary>T-334: the closed key set, its type and range checks, the effective values and the admin use cases over a fake store.</summary>
public class RemoteConfigTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 26, 12, 0, 0, TimeSpan.Zero);
    private static readonly Guid Operator = Guid.Parse("00000000-0000-4000-8000-0000000000aa");

    [Fact]
    public void TheKeySetIsClosedAndEveryDefaultIsValidForItsOwnKey()
    {
        Assert.Null(RemoteConfigKeys.Find("ask.unknown"));
        Assert.Null(RemoteConfigKeys.Find(null));
        Assert.Equal(RemoteConfigKeys.All.Count, RemoteConfigKeys.All.Select(d => d.Key).Distinct(StringComparer.Ordinal).Count());
        foreach (var definition in RemoteConfigKeys.All)
        {
            Assert.True(RemoteConfigKeys.HasValidShape(definition.Key));
            if (definition.Default.Length > 0)
            {
                Assert.True(RemoteConfigKeys.TryCanonicalize(definition, definition.Default, out var canonical), definition.Key);
                Assert.Equal(definition.Default, canonical);
            }
        }
    }

    [Theory]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "5")]
    [InlineData(RemoteConfigKeys.AskQuotaGold, "50")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "10.00")]
    [InlineData(RemoteConfigKeys.CatQuotaFree, "15")]
    [InlineData(RemoteConfigKeys.CatQuotaGold, "150")]
    [InlineData(RemoteConfigKeys.CatBatchMax, "20")]
    [InlineData(RemoteConfigKeys.CatMinConfidence, "60")]
    [InlineData(RemoteConfigKeys.CatCacheMinConfidence, "80")]
    [InlineData(RemoteConfigKeys.CatConfirmN, "3")]
    [InlineData(RemoteConfigKeys.AskInvestMinEgp, "100.00")]
    public void TheDocumentedDefaultsAreInTheCatalogue(string key, string expected) =>
        Assert.Equal(expected, RemoteConfigKeys.Find(key)!.Default);

    [Theory]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "abc")]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "1.5")]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "-1")]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "100001")]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "")]
    [InlineData(RemoteConfigKeys.AskQuotaFree, " 5")]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "٥")]
    [InlineData(RemoteConfigKeys.CatBatchMax, "21")]
    [InlineData(RemoteConfigKeys.CatMinConfidence, "101")]
    [InlineData(RemoteConfigKeys.AskInvestGoldKarat, "20")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "10.005")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "-1.00")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "1e3")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "100000.01")]
    [InlineData(RemoteConfigKeys.LlmProvider, "Has Space")]
    [InlineData(RemoteConfigKeys.LlmProvider, "x@y")]
    [InlineData(RemoteConfigKeys.LlmProvider, "ok\n")]
    [InlineData(RemoteConfigKeys.LlmProviderNameEn, "a@b")]
    public void AWrongTypeOrOutOfRangeValueIsRejected(string key, string raw) =>
        Assert.False(RemoteConfigKeys.TryCanonicalize(RemoteConfigKeys.Find(key)!, raw, out _));

    [Theory]
    [InlineData(RemoteConfigKeys.AskQuotaFree, "007", "7")]
    [InlineData(RemoteConfigKeys.CatQuotaGold, "0", "0")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "25", "25.00")]
    [InlineData(RemoteConfigKeys.LlmSpendCapUsd, "7.5", "7.50")]
    [InlineData(RemoteConfigKeys.AskInvestGoldKarat, "24", "24")]
    [InlineData(RemoteConfigKeys.LlmProvider, "openai-luna", "openai-luna")]
    [InlineData(RemoteConfigKeys.LlmProviderNameAr, "المساعد الأونلاين", "المساعد الأونلاين")]
    public void ValuesAreStoredInTheirCanonicalForm(string key, string raw, string expected)
    {
        Assert.True(RemoteConfigKeys.TryCanonicalize(RemoteConfigKeys.Find(key)!, raw, out var canonical));
        Assert.Equal(expected, canonical);
    }

    [Fact]
    public async Task AnUnknownKeyIs404AndABadValueNeverReachesTheStore()
    {
        var store = new FakeStore();
        var service = new RemoteConfigAdminService(store, new FixedClock());

        Assert.Equal(ConfigSetStatus.UnknownKey, (await service.SetAsync("nope.key", "1", Operator, default)).Status);
        Assert.Equal(ConfigSetStatus.InvalidValue, (await service.SetAsync(RemoteConfigKeys.AskQuotaFree, "many", Operator, default)).Status);
        Assert.Equal(ConfigSetStatus.InvalidValue, (await service.SetAsync(RemoteConfigKeys.AskQuotaFree, null, Operator, default)).Status);
        Assert.Equal(0, store.Writes);
        Assert.Null(await service.GetAsync("nope.key", default));
    }

    [Fact]
    public async Task EverySuccessfulSetWritesOnceAndBumpsTheVersionByOne()
    {
        var store = new FakeStore();
        var service = new RemoteConfigAdminService(store, new FixedClock());

        var before = await service.GetAsync(RemoteConfigKeys.LlmSpendCapUsd, default);
        Assert.True(before!.IsDefault);
        Assert.Equal(0, before.Version);
        Assert.Equal("10.00", before.Value);

        var first = await service.SetAsync(RemoteConfigKeys.LlmSpendCapUsd, "12", Operator, default);
        var second = await service.SetAsync(RemoteConfigKeys.LlmSpendCapUsd, "15.50", Operator, default);

        Assert.Equal(1, first.State!.Version);
        Assert.Equal(2, second.State!.Version);
        Assert.Equal("15.50", second.State.Value);
        Assert.False(second.State.IsDefault);
        Assert.Equal(2, store.Writes);
        Assert.Equal(RemoteConfigKeys.All.Count, (await service.ListAsync(default)).Count);
    }

    [Fact]
    public void AStoredValueThatNoLongerValidatesFallsBackToTheDefault()
    {
        var snapshot = RemoteConfigService.Build([new RemoteConfigRow(RemoteConfigKeys.CatBatchMax, "9999", 3, Now), new RemoteConfigRow("gone.key", "1", 1, Now)]);

        Assert.Equal(20, snapshot.GetInt(RemoteConfigKeys.CatBatchMax));
        Assert.Equal(10.00m, snapshot.GetDecimal(RemoteConfigKeys.LlmSpendCapUsd));
    }

    [Fact]
    public void TheAppVersionIsTheSumOfTheAppVisibleKeyVersionsAndIgnoresServerOnlyKeys()
    {
        var snapshot = RemoteConfigService.Build(
        [
            new RemoteConfigRow(RemoteConfigKeys.AskQuotaFree, "6", 3, Now),
            new RemoteConfigRow(RemoteConfigKeys.CatQuotaFree, "20", 2, Now),
            new RemoteConfigRow(RemoteConfigKeys.LlmProvider, "p", 9, Now),
        ]);

        Assert.Equal(5, snapshot.AppVersion);
        Assert.Equal(0, RemoteConfigService.Build([]).AppVersion);
        Assert.Null(snapshot.ToAppBlock().ProviderName);
    }

    private sealed class FixedClock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class FakeStore : IRemoteConfigAdminStore
    {
        private readonly Dictionary<string, RemoteConfigRow> rows = [];

        public int Writes { get; private set; }

        public Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<RemoteConfigRow>>(rows.Values.ToList());

        public Task<RemoteConfigRow> UpsertAsync(string key, string value, Guid operatorId, DateTimeOffset now, CancellationToken cancellationToken)
        {
            Writes++;
            var row = new RemoteConfigRow(key, value, rows.TryGetValue(key, out var old) ? old.Version + 1 : 1, now);
            rows[key] = row;
            return Task.FromResult(row);
        }
    }
}
