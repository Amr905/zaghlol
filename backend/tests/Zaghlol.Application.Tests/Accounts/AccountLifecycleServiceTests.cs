using Zaghlol.Application.Accounts;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Tests.Entitlements;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Accounts;

/// <summary>Sign-out and delete (backend-api §4.6): the token gate, the order of revocation and deletion, and fail-closed on Apple.</summary>
public class AccountLifecycleServiceTests
{
    private static readonly Guid Account = EntitlementTestKit.Account;
    private static readonly InstallId Install = EntitlementTestKit.Caller;

    private readonly FakeAccountStore store = new();
    private readonly RecordingApple apple = new();

    private AccountLifecycleService Service(ValidatedAccountToken? token, FakeEntitlementStore? entitlements = null)
    {
        var clock = new ManualClock(EntitlementTestKit.Now);
        return new AccountLifecycleService(
            new FakeAccountValidator(token),
            store,
            apple,
            new IdentityVault(),
            new EntitlementService(entitlements ?? new FakeEntitlementStore(), new FakeEntitlementSigner(), new FakeAccountValidator(null), clock),
            clock,
            Microsoft.Extensions.Logging.Abstractions.NullLogger<AccountLifecycleService>.Instance);
    }

    private static ValidatedAccountToken Valid => new(Account, EntitlementTestKit.Now.AddDays(1));

    private static readonly Sensitive<string> Header = new("account-token");

    [Fact]
    public async Task SignOutWithoutAValidAccountTokenIsAccountTokenExpired_AndUnlinksNothing()
    {
        var result = await Service(null).SignOutAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.AccountTokenExpired, result.Kind);
        Assert.Empty(store.Unlinked);
    }

    [Fact]
    public async Task SignOutUnlinksOnlyThisInstallAndIssuesATokenWithoutThePresentedAccount()
    {
        var held = EntitlementTestKit.Held(account: Account);
        var entitlements = new FakeEntitlementStore { Facts = EntitlementTestKit.Facts(held) };

        var result = await Service(Valid, entitlements).SignOutAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.Completed, result.Kind);
        Assert.Equal([(Account, Install.Value)], store.Unlinked);
        Assert.Equal("ent.1", result.EntitlementToken.Reveal());
    }

    [Fact]
    public async Task DeleteWithoutAValidTokenTouchesNothing()
    {
        store.ForDelete = new AccountForDelete(AccountProvider.Apple, "s", [1]);

        var kind = await Service(null).DeleteAsync(Install, null, default);

        Assert.Equal(AccountLifecycleKind.AccountTokenExpired, kind);
        Assert.Empty(store.Deleted);
        Assert.Empty(apple.Revoked);
    }

    [Fact]
    public async Task DeleteRevokesTheAppleTokenThenDeletes()
    {
        store.ForDelete = new AccountForDelete(AccountProvider.Apple, "s", System.Text.Encoding.UTF8.GetBytes("services.id\nrefresh-1"));

        var kind = await Service(Valid).DeleteAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.Completed, kind);
        var revoked = Assert.Single(apple.Revoked);
        Assert.Equal("services.id", revoked.ClientId);
        Assert.Equal("refresh-1", revoked.Token.Reveal());
        Assert.Equal([Account], store.Deleted);
    }

    [Fact]
    public async Task AFailedRevocationStillDeletesTheAccount_AndQueuesOnlyTheResealedToken()
    {
        store.ForDelete = new AccountForDelete(AccountProvider.Apple, "s", System.Text.Encoding.UTF8.GetBytes("services.id\nrefresh-1"));
        apple.Outcome = AppleRevokeOutcome.Unavailable;

        var kind = await Service(Valid).DeleteAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.Completed, kind);
        Assert.Equal([Account], store.Deleted);
        var queued = Assert.Single(store.Queued);
        Assert.Equal("services.id\nrefresh-1", System.Text.Encoding.UTF8.GetString(queued!));
    }

    [Fact]
    public async Task AClientThatThrowsIsTreatedAsUnavailable_AndStillDeletes()
    {
        store.ForDelete = new AccountForDelete(AccountProvider.Apple, "s", System.Text.Encoding.UTF8.GetBytes("services.id\nrefresh-1"));
        apple.Throw = true;

        var kind = await Service(Valid).DeleteAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.Completed, kind);
        Assert.NotNull(Assert.Single(store.Queued));
    }

    [Fact]
    public async Task ARevokedOrAlreadyRevokedTokenQueuesNothing()
    {
        // invalid_grant is mapped to Revoked by the client (AppleAccountClientTests): the same outcome as a plain success here.
        store.ForDelete = new AccountForDelete(AccountProvider.Apple, "s", System.Text.Encoding.UTF8.GetBytes("services.id\nrefresh-1"));

        var kind = await Service(Valid).DeleteAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.Completed, kind);
        Assert.Null(Assert.Single(store.Queued));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task AGoogleAccountOrAnAppleAccountWithoutATokenNeedsNoRevocation(bool apple)
    {
        store.ForDelete = new AccountForDelete(apple ? AccountProvider.Apple : AccountProvider.Google, "s", null);

        var kind = await Service(Valid).DeleteAsync(Install, Header, default);

        Assert.Equal(AccountLifecycleKind.Completed, kind);
        Assert.Equal([Account], store.Deleted);
        Assert.Empty(this.apple.Revoked);
    }
}
