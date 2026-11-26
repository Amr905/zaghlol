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

        public Task<LlmQuotaRow?> ReadAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, CancellationToken cancellationToken) =>
            Task.FromResult(Rows.TryGetValue((feature, kind, subject, monthKey), out var row) ? new LlmQuotaRow(row.Used, row.Hash) : null);

        public Task<bool> CommitAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, int n, int limit, byte[] requestHash, DateTimeOffset now, CancellationToken cancellationToken)
        {
            var key = (feature, kind, subject, monthKey);
            if (!Rows.TryGetValue(key, out var row))
            {
                Rows[key] = (Math.Min(n, limit), requestHash);
                return Task.FromResult(true);
            }

            if (row.Used >= limit || row.Hash is { } h && h.AsSpan().SequenceEqual(requestHash))
            {
                return Task.FromResult(false);
            }

            Rows[key] = (row.Used + Math.Min(n, limit - row.Used), requestHash);
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

    private sealed class Clock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private static LlmQuotaStore Store(MemoryRepository repository, bool gold = false) =>
        new(repository, new Limits(), new Tier(gold), new Clock(), NullLogger<LlmQuotaStore>.Instance);

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
