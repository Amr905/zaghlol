using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Sync;
using Zaghlol.Domain;
using static Zaghlol.Application.Tests.Entitlements.EntitlementTestKit;

namespace Zaghlol.Application.Tests.Entitlements;

/// <summary>T-132: the sync's entitlement, accountToken and supportNotice blocks (backend-api §4.2, R5-7).</summary>
public sealed class SyncEntitlementBlockTests
{
    private readonly FakeEntitlementStore store = new();
    private readonly FakeEntitlementSigner signer = new();

    private SyncEntitlementBlock Block(ValidatedAccountToken? account = null)
    {
        var validator = new FakeAccountValidator(account);
        return new SyncEntitlementBlock(new EntitlementService(store, signer, validator, new ManualClock(Now)), store, signer, validator);
    }

    private Task<SyncEntitlementResult> Sync(DateTimeOffset? issuedAt, Sensitive<string>? account = null, ValidatedAccountToken? valid = null) =>
        Block(valid).ComposeAsync(new SyncEntitlementContext(Caller, issuedAt, Now, account), CancellationToken.None);

    [Fact]
    public async Task NoCachedTokenGetsAFreshOne() => Assert.Equal("ent.1", (await Sync(null)).Entitlement);

    [Fact]
    public async Task ACachedTokenOlderThanTwelveHoursGetsAFreshOne() =>
        Assert.NotNull((await Sync(Now.AddHours(-12).AddSeconds(-1))).Entitlement);

    [Fact]
    public async Task AYoungUnchangedTokenIsLeftAlone()
    {
        var result = await Sync(Now.AddHours(-11));

        Assert.Null(result.Entitlement);
        Assert.Null(result.SupportNotice);
        Assert.Empty(signer.Entitlements);
    }

    [Fact]
    public async Task AChangeSinceTheCachedTokenGetsAFreshOneEvenWhenYoung()
    {
        store.Changed = true;

        Assert.NotNull((await Sync(Now.AddHours(-1))).Entitlement);
    }

    [Fact]
    public async Task ACachedTokenFromTheFutureIsNotTrusted() => Assert.NotNull((await Sync(Now.AddMinutes(1))).Entitlement);

    [Fact]
    public async Task R57TheNoticeKeepsComingUntilASyncProvesDelivery()
    {
        store.Pending = true;

        var first = await Sync(null);
        var iat = store.NoticeIat!.Value;
        var olderThanTheNoticeToken = await Sync(iat.AddSeconds(-1));
        var delivered = await Sync(iat);

        Assert.Equal("gold_linked_by_support", first.SupportNotice);
        Assert.NotNull(first.Entitlement);
        Assert.Equal("gold_linked_by_support", olderThanTheNoticeToken.SupportNotice);
        Assert.NotNull(olderThanTheNoticeToken.Entitlement);
        Assert.Null(delivered.SupportNotice);
        Assert.False(store.Pending);
    }

    [Fact]
    public async Task AnAccountTokenWithMoreThanSevenDaysLeftIsNotRefreshed() =>
        Assert.Null((await Sync(Now, new Sensitive<string>("t"), new ValidatedAccountToken(Account, Now.AddDays(8)))).AccountToken);

    [Fact]
    public async Task AnAccountTokenWithLessThanSevenDaysLeftIsRefreshedForThirtyDays()
    {
        var result = await Sync(Now, new Sensitive<string>("t"), new ValidatedAccountToken(Account, Now.AddDays(6)));

        Assert.Equal("acct.1", result.AccountToken);
        var claims = Assert.Single(signer.AccountTokens);
        Assert.Equal(Account.ToString("D"), claims.Sub);
        Assert.Equal(Caller.ToString(), claims.Iid);
        Assert.Equal(TimeSpan.FromDays(30).TotalSeconds, claims.Exp - claims.Iat);
    }

    [Fact]
    public async Task AnInvalidAccountTokenIsNeverRefreshed() =>
        Assert.Null((await Sync(null, new Sensitive<string>("bad"), valid: null)).AccountToken);
}
