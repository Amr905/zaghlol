using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Llm.Quota;

/// <summary>T-335 AC 2, 3 and 6 against an in-memory repository that mimics the commit statement.</summary>
public class LlmQuotaStoreTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 20, 10, 0, 0, TimeSpan.Zero);

    private static readonly InstallId Install = InstallId.TryParse("3f2504e0-4f89-41d3-9a0c-0305e82c3301", out var id) ? id : throw new InvalidOperationException();

    private static readonly Guid Account = Guid.Parse("11111111-2222-4333-8444-555555555555");

    private sealed class MemoryRepository : ILlmQuotaRepository
    {
        public Dictionary<(LlmFeature, LlmQuotaSubjectKind, Guid, int), (int Used, byte[]? Hash)> Rows { get; } = [];

        public Dictionary<(LlmFeature, LlmQuotaSubjectKind, Guid, int), DateTimeOffset> Stamps { get; } = [];

        public Task<LlmQuotaRow?> ReadAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, CancellationToken cancellationToken) =>
            Task.FromResult(Rows.TryGetValue((feature, kind, subject, monthKey), out var row) ? new LlmQuotaRow(row.Used, row.Hash, Stamps.GetValueOrDefault((feature, kind, subject, monthKey), Now)) : null);

        public Task<bool> CommitAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, int n, int limit, byte[] requestHash, DateTimeOffset now, DateTimeOffset retryCutoff, CancellationToken cancellationToken)
        {
            var key = (feature, kind, subject, monthKey);
            if (!Rows.TryGetValue(key, out var row))
            {
                Rows[key] = (Math.Min(n, limit), requestHash);
                Stamps[key] = now;
                return Task.FromResult(true);
            }

            var twin = row.Hash is { } h && h.AsSpan().SequenceEqual(requestHash) && Stamps.GetValueOrDefault(key, Now) > retryCutoff;
            if (row.Used >= limit || twin)
            {
                return Task.FromResult(false);
            }

            Rows[key] = (row.Used + Math.Min(n, limit - row.Used), requestHash);
            Stamps[key] = now;
            return Task.FromResult(true);
        }
    }

    private sealed class Limits : ILlmQuotaLimits
    {
        public Task<int> LimitAsync(LlmFeature feature, bool gold, CancellationToken cancellationToken) => Task.FromResult(LlmQuotaDefaults.Default(feature, gold));
    }

    private sealed class Tier(bool gold) : ILlmQuotaTier
    {
        public Task<bool> IsGoldAsync(InstallId install, Guid? account, DateTimeOffset now, CancellationToken cancellationToken) => Task.FromResult(gold);
    }

    private sealed class Clock(DateTimeOffset at) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => at;
    }

    private static LlmQuotaStore Store(MemoryRepository repository, bool gold = false, DateTimeOffset? at = null) =>
        new(repository, new Limits(), new Tier(gold), new Clock(at ?? Now), NullLogger<LlmQuotaStore>.Instance);

    [Theory]
    [InlineData(false, LlmFeature.Ask, 5)]
    [InlineData(true, LlmFeature.Ask, 50)]
    [InlineData(false, LlmFeature.Categorise, 15)]
    [InlineData(true, LlmFeature.Categorise, 150)]
    public async Task LimitsFollowTheTierAndTheFeature(bool gold, LlmFeature feature, int expected)
    {
        var check = await Store(new MemoryRepository(), gold).PreCheckAsync(feature, Install, null, "req-1", CancellationToken.None);

        Assert.Equal(LlmQuotaCheckKind.Allowed, check.Kind);
        Assert.Equal(expected, check.Limit);
        Assert.Equal(expected, check.Remaining);
        Assert.Equal(new DateTimeOffset(2026, 11, 30, 22, 0, 0, TimeSpan.Zero), check.ResetsAt);
    }

    [Fact]
    public async Task AtTheLimitExhaustedButARetryOfTheCountedRequestStillPasses()
    {
        var store = Store(new MemoryRepository());
        for (var i = 0; i < 5; i++)
        {
            await store.CommitAsync(LlmFeature.Ask, Install, null, "req-" + i, 1, CancellationToken.None);
        }

        Assert.Equal(LlmQuotaCheckKind.Exhausted, (await store.PreCheckAsync(LlmFeature.Ask, Install, null, "req-new", CancellationToken.None)).Kind);
        var retry = await store.PreCheckAsync(LlmFeature.Ask, Install, null, "req-4", CancellationToken.None);
        Assert.Equal(LlmQuotaCheckKind.Allowed, retry.Kind);
        Assert.True(retry.IsRetry);
        var again = await store.CommitAsync(LlmFeature.Ask, Install, null, "req-4", 1, CancellationToken.None);
        Assert.Equal(0, again.Applied);
    }

    private static async Task<MemoryRepository> AtTheLimitAsync(Guid? account = null)
    {
        var repository = new MemoryRepository();
        for (var i = 0; i < 5; i++)
        {
            await Store(repository).CommitAsync(LlmFeature.Ask, Install, account, "req-" + i, 1, CancellationToken.None);
        }

        return repository;
    }

    /// <summary>B92-M1: the limit-hitting requestId is a retry only inside the window; after it, a new question under that id is refused.</summary>
    [Fact]
    public async Task ReusingTheLimitHittingRequestIdAfterTheWindowIsRefused()
    {
        var repository = await AtTheLimitAsync();

        var inside = await Store(repository, at: Now + LlmQuotaStore.RetryWindow).PreCheckAsync(LlmFeature.Ask, Install, null, "req-4", CancellationToken.None);
        Assert.Equal(LlmQuotaCheckKind.Allowed, inside.Kind);
        Assert.True(inside.IsRetry);
        var late = Store(repository, at: Now + LlmQuotaStore.RetryWindow + TimeSpan.FromSeconds(1));
        Assert.Equal(LlmQuotaCheckKind.Exhausted, (await late.PreCheckAsync(LlmFeature.Ask, Install, null, "req-4", CancellationToken.None)).Kind);
        Assert.Equal(LlmQuotaCheckKind.Exhausted, (await late.CommitAsync(LlmFeature.Ask, Install, null, "req-4", 1, CancellationToken.None)).Kind);
    }

    /// <summary>B92-M1: a matching hash on the account row never lets another install of the account through.</summary>
    [Fact]
    public async Task ReusingTheRequestIdFromAnotherInstallOfTheSameAccountIsRefused()
    {
        var repository = await AtTheLimitAsync(Account);
        var other = InstallId.TryParse("7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", out var id) ? id : throw new InvalidOperationException();

        var check = await Store(repository).PreCheckAsync(LlmFeature.Ask, other, Account, "req-4", CancellationToken.None);

        Assert.Equal(LlmQuotaCheckKind.Exhausted, check.Kind);
        Assert.False(check.IsRetry);
    }

    /// <summary>B92-M1: a genuine retry inside the window passes once and is not counted a second time.</summary>
    [Fact]
    public async Task AGenuineRetryInsideTheWindowIsAllowedWithoutASecondCount()
    {
        var repository = new MemoryRepository();
        var month = CairoMonth.MonthKey(Now);
        await Store(repository).CommitAsync(LlmFeature.Ask, Install, Account, "req-1", 1, CancellationToken.None);
        var soon = Store(repository, at: Now.AddSeconds(30));

        Assert.True((await soon.PreCheckAsync(LlmFeature.Ask, Install, Account, "req-1", CancellationToken.None)).IsRetry);
        Assert.Equal(0, (await soon.CommitAsync(LlmFeature.Ask, Install, Account, "req-1", 1, CancellationToken.None)).Applied);
        Assert.Equal(1, repository.Rows[(LlmFeature.Ask, LlmQuotaSubjectKind.Install, Install.Value, month)].Used);
        Assert.Equal(1, repository.Rows[(LlmFeature.Ask, LlmQuotaSubjectKind.Account, Account, month)].Used);
    }

    /// <summary>B92-M1: below the limit an old requestId counts again instead of passing free forever.</summary>
    [Fact]
    public async Task AnOldRequestIdBelowTheLimitCountsAgain()
    {
        var repository = new MemoryRepository();
        await Store(repository).CommitAsync(LlmFeature.Ask, Install, null, "req-1", 1, CancellationToken.None);
        var late = Store(repository, at: Now.AddMinutes(10));

        Assert.False((await late.PreCheckAsync(LlmFeature.Ask, Install, null, "req-1", CancellationToken.None)).IsRetry);
        Assert.Equal(1, (await late.CommitAsync(LlmFeature.Ask, Install, null, "req-1", 1, CancellationToken.None)).Applied);
    }

    [Fact]
    public async Task EitherCounterAtTheLimitExhaustsAndTheAccountUsesTheInstallsLimit()
    {
        var repository = new MemoryRepository();
        var month = CairoMonth.MonthKey(Now);
        repository.Rows[(LlmFeature.Ask, LlmQuotaSubjectKind.Account, Account, month)] = (5, null);
        var free = Store(repository);

        var check = await free.PreCheckAsync(LlmFeature.Ask, Install, Account, "r", CancellationToken.None);
        Assert.Equal(LlmQuotaCheckKind.Exhausted, check.Kind);

        // The same account counter (5 used) is fine for a Gold install (limit 50), and not used at all without the account.
        Assert.Equal(LlmQuotaCheckKind.Allowed, (await Store(repository, gold: true).PreCheckAsync(LlmFeature.Ask, Install, Account, "r", CancellationToken.None)).Kind);
        Assert.Equal(LlmQuotaCheckKind.Allowed, (await free.PreCheckAsync(LlmFeature.Ask, Install, null, "r", CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task CategoriseCommitAddsNAndTrimsToTheLowerRemainingOfInstallAndAccount()
    {
        var repository = new MemoryRepository();
        var month = CairoMonth.MonthKey(Now);
        repository.Rows[(LlmFeature.Categorise, LlmQuotaSubjectKind.Install, Install.Value, month)] = (4, null);
        repository.Rows[(LlmFeature.Categorise, LlmQuotaSubjectKind.Account, Account, month)] = (10, null);

        var commit = await Store(repository).CommitAsync(LlmFeature.Categorise, Install, Account, "batch-1", 9, CancellationToken.None);

        // Remaining: install 11, account 5 -> 5 are counted on both rows.
        Assert.Equal(5, commit.Applied);
        Assert.Equal(9, repository.Rows[(LlmFeature.Categorise, LlmQuotaSubjectKind.Install, Install.Value, month)].Used);
        Assert.Equal(15, repository.Rows[(LlmFeature.Categorise, LlmQuotaSubjectKind.Account, Account, month)].Used);
        Assert.Equal(0, (await Store(repository).CommitAsync(LlmFeature.Categorise, Install, Account, "batch-2", 3, CancellationToken.None)).Applied);
    }

    [Fact]
    public async Task AskAndCategoriseCountersAreIndependent()
    {
        var repository = new MemoryRepository();
        var store = Store(repository);
        await store.CommitAsync(LlmFeature.Categorise, Install, Account, "c1", 3, CancellationToken.None);
        var month = CairoMonth.MonthKey(Now);

        Assert.False(repository.Rows.ContainsKey((LlmFeature.Ask, LlmQuotaSubjectKind.Install, Install.Value, month)));
        Assert.Equal(5, (await store.PreCheckAsync(LlmFeature.Ask, Install, Account, "a1", CancellationToken.None)).Remaining);

        await store.CommitAsync(LlmFeature.Ask, Install, Account, "a1", 1, CancellationToken.None);
        Assert.Equal(3, repository.Rows[(LlmFeature.Categorise, LlmQuotaSubjectKind.Install, Install.Value, month)].Used);
    }
}
