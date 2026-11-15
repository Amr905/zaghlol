using Zaghlol.Application.Entitlements;
using Zaghlol.Domain;

namespace Zaghlol.Application.Accounts;

public enum AccountLifecycleKind
{
    Completed,

    /// <summary>The account token is missing, malformed, expired, or its account or install link is gone: <c>401 ACCOUNT_TOKEN_EXPIRED</c> (R3-6).</summary>
    AccountTokenExpired,

    /// <summary>Apple couldn't revoke the refresh token now; the account was not deleted: <c>503</c>, the app retries.</summary>
    Unavailable,
}

/// <summary>Sign-out's 200: the fresh entitlement without the account-linked purchases (now <c>paused</c> here).</summary>
public sealed record SignOutResult(AccountLifecycleKind Kind, Sensitive<string> EntitlementToken = default)
{
    public override string ToString() => Kind.ToString();
}

/// <summary>
/// <c>POST /v1/accounts/signout</c> (D-61(c)) and <c>DELETE /v1/accounts/me</c> (T-135 design note; backend-api §4.6). Both need a
/// valid <c>Zaghlol-Account</c> token (the shared validator of §3): anything else is <c>401 ACCOUNT_TOKEN_EXPIRED</c>, so the app clears its token.
/// </summary>
public sealed class AccountLifecycleService(
    IAccountTokenValidator tokens,
    IAccountStore store,
    IAppleAccountClient apple,
    IAppleTokenVault vault,
    EntitlementService entitlement,
    TimeProvider clock)
{
    /// <summary>Unlinks this install only. No seat is released or moved; the new token omits account-linked purchases.</summary>
    public async Task<SignOutResult> SignOutAsync(InstallId install, Sensitive<string>? accountToken, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var account = await tokens.ValidateAsync(accountToken, install, now, cancellationToken).ConfigureAwait(false);
        if (account is null)
        {
            return new SignOutResult(AccountLifecycleKind.AccountTokenExpired);
        }

        await store.UnlinkInstallAsync(account.AccountId, install.Value, cancellationToken).ConfigureAwait(false);
        var issue = await entitlement.IssueAsync(install, presentedAccount: null, clock.GetUtcNow(), carryNotice: false, cancellationToken).ConfigureAwait(false);
        return new SignOutResult(AccountLifecycleKind.Completed, new Sensitive<string>(issue.Token));
    }

    /// <summary>
    /// Revokes the Apple token first (a failed revocation keeps the account so the app retries; "already revoked" counts as done),
    /// then deletes the account, its links and its sign-in idempotency rows in one transaction. Purchases keep seats and
    /// <c>attach_reclaim_used_at</c>; their account link is cleared.
    /// </summary>
    public async Task<AccountLifecycleKind> DeleteAsync(InstallId install, Sensitive<string>? accountToken, CancellationToken cancellationToken)
    {
        var account = await tokens.ValidateAsync(accountToken, install, clock.GetUtcNow(), cancellationToken).ConfigureAwait(false);
        if (account is null)
        {
            return AccountLifecycleKind.AccountTokenExpired;
        }

        var row = await store.ReadForDeleteAsync(account.AccountId, cancellationToken).ConfigureAwait(false);
        if (row is { Provider: AccountProvider.Apple, AppleRefreshTokenSealed: { } sealedToken })
        {
            var refresh = await vault.OpenAsync(row.Subject, sealedToken, cancellationToken).ConfigureAwait(false);
            if (refresh is not null && await apple.RevokeAsync(refresh, cancellationToken).ConfigureAwait(false) != AppleRevokeOutcome.Revoked)
            {
                return AccountLifecycleKind.Unavailable;
            }
        }

        await store.DeleteAccountAsync(account.AccountId, cancellationToken).ConfigureAwait(false);
        return AccountLifecycleKind.Completed;
    }
}
