using Zaghlol.Application.Entitlements;
using Zaghlol.Domain;
using static Zaghlol.Application.Tests.Entitlements.EntitlementTestKit;

namespace Zaghlol.Application.Tests.Entitlements;

public sealed class EntitlementServiceTests
{
    private readonly FakeEntitlementStore store = new();
    private readonly FakeEntitlementSigner signer = new();
    private readonly ManualClock clock = new(Now);

    private EntitlementService Service(ValidatedAccountToken? account = null) => new(store, signer, new FakeAccountValidator(account), clock);

    [Fact]
    public async Task TheTokenIsSignedForTheCallingInstallFromItsOwnFacts()
    {
        store.Facts = Facts(Held());

        var issue = await Service().GetAsync(Caller, null, CancellationToken.None);

        Assert.Equal("ent.1", issue.Token);
        Assert.Equal(Caller.ToString(), Assert.Single(signer.Entitlements).Sub);
        Assert.Null(issue.SupportNotice);
    }

    [Fact]
    public async Task AValidAccountTokenLetsAnAccountLinkedPurchaseThrough()
    {
        store.Facts = Facts(Held(account: Account));

        var withToken = await Service(new ValidatedAccountToken(Account, Now.AddDays(20))).GetAsync(Caller, new Sensitive<string>("t"), CancellationToken.None);
        var without = await Service(new ValidatedAccountToken(Account, Now.AddDays(20))).GetAsync(Caller, null, CancellationToken.None);

        Assert.Equal("active", withToken.Claims.Status);
        Assert.Equal(Account.ToString("D"), withToken.Claims.Acct);
        Assert.Equal("paused", without.Claims.Status);
    }

    [Fact]
    public async Task APendingSupportNoticeRidesWithAFreshTokenAndItsIatIsRecorded()
    {
        store.Pending = true;

        var issue = await Service().GetAsync(Caller, null, CancellationToken.None);

        Assert.Equal("gold_linked_by_support", issue.SupportNotice);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(issue.Claims.Iat), store.NoticeIat);
        Assert.True(store.Pending, "sending is not delivery");
    }

    [Fact]
    public async Task VerifyIssuesWithoutTheNoticeAndWithoutRecordingAnIat()
    {
        store.Pending = true;

        var issue = await Service().IssueAsync(Caller, null, Now, carryNotice: false, CancellationToken.None);

        Assert.Null(issue.SupportNotice);
        Assert.Null(store.NoticeIat);
    }

    [Fact]
    public async Task ASigningFailureRecordsNoNoticeIat()
    {
        store.Pending = true;
        var failing = new EntitlementService(store, new ThrowingSigner(), new FakeAccountValidator(null), clock);

        await Assert.ThrowsAsync<InvalidOperationException>(() => failing.GetAsync(Caller, null, CancellationToken.None));

        Assert.Null(store.NoticeIat);
    }

    private sealed class ThrowingSigner : IEntitlementSigner
    {
        public Task<string> SignEntitlementAsync(EntitlementClaims claims, CancellationToken cancellationToken) => throw new InvalidOperationException();

        public Task<string> SignAccountTokenAsync(AccountTokenClaims claims, CancellationToken cancellationToken) => throw new InvalidOperationException();
    }
}
