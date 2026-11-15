using Microsoft.Extensions.Logging;
using Zaghlol.Application.Entitlements;
using Zaghlol.Domain;

namespace Zaghlol.Application.Accounts;

public enum AccountLifecycleKind
{
    Completed,

    /// <summary>The account token is missing, malformed, expired, or its account or install link is gone: <c>401 ACCOUNT_TOKEN_EXPIRED</c> (R3-6).</summary>
    AccountTokenExpired,

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
public sealed partial class AccountLifecycleService(
    IAccountTokenValidator tokens,
    IAccountStore store,
    IAppleAccountClient apple,
    IAppleTokenVault vault,
    EntitlementService entitlement,
    TimeProvider clock,
    ILogger<AccountLifecycleService> logger)
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
    /// Always deletes the account, its links and its sign-in idempotency rows in one transaction; Apple can never block it. The Apple
    /// token is revoked first; when that fails for any reason, only the re-sealed refresh token goes into a
    /// <c>pending_apple_revocations</c> row in the same transaction, and the worker retries it for 30 days. "Already revoked"
    /// (<c>invalid_grant</c>) is done and queues nothing. Purchases keep seats and <c>attach_reclaim_used_at</c>; their account link is cleared.
    /// </summary>
    public async Task<AccountLifecycleKind> DeleteAsync(InstallId install, Sensitive<string>? accountToken, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var account = await tokens.ValidateAsync(accountToken, install, now, cancellationToken).ConfigureAwait(false);
        if (account is null)
        {
            return AccountLifecycleKind.AccountTokenExpired;
        }

        byte[]? pending = null;
        var row = await store.ReadForDeleteAsync(account.AccountId, cancellationToken).ConfigureAwait(false);
        if (row is { Provider: AccountProvider.Apple, AppleRefreshTokenSealed: { } sealedToken })
        {
            var refresh = await vault.OpenAsync(row.Subject, sealedToken, cancellationToken).ConfigureAwait(false);
            if (refresh is null)
            {
                LogTokenUnreadable(logger);
            }
            else
            {
                pending = await RevokeOrSealAsync(refresh, cancellationToken).ConfigureAwait(false);
            }
        }

        await store.DeleteAccountAsync(account.AccountId, pending, now, cancellationToken).ConfigureAwait(false);
        return AccountLifecycleKind.Completed;
    }

    /// <summary>Null when Apple revoked it; otherwise the token re-sealed for the retry queue (null too if sealing itself fails).</summary>
    private async Task<byte[]?> RevokeOrSealAsync(AppleRefreshToken refresh, CancellationToken cancellationToken)
    {
        AppleRevokeOutcome outcome;
        try
        {
            outcome = await apple.RevokeAsync(refresh, cancellationToken).ConfigureAwait(false);
        }
#pragma warning disable CA1031 // Whatever Apple or our client does, the deletion goes on.
        catch (Exception exception) when (exception is not OperationCanceledException)
#pragma warning restore CA1031
        {
            LogRevokeThrew(logger, exception.GetType().Name);
            outcome = AppleRevokeOutcome.Unavailable;
        }

        if (outcome == AppleRevokeOutcome.Revoked)
        {
            return null;
        }

        try
        {
            return await vault.SealAsync(PendingAppleRevocationPolicy.VaultSubject, refresh, cancellationToken).ConfigureAwait(false);
        }
#pragma warning disable CA1031 // A sealing failure must not block the deletion either.
        catch (Exception exception) when (exception is not OperationCanceledException)
#pragma warning restore CA1031
        {
            LogSealFailed(logger, exception.GetType().Name);
            return null;
        }
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Warning, Message = "An Apple refresh token could not be opened at account deletion; it was not revoked.")]
    private static partial void LogTokenUnreadable(ILogger logger);

    [LoggerMessage(EventId = 2, Level = LogLevel.Warning, Message = "Apple revocation threw {ExceptionType} at account deletion; the token is queued for retry.")]
    private static partial void LogRevokeThrew(ILogger logger, string exceptionType);

    [LoggerMessage(EventId = 3, Level = LogLevel.Warning, Message = "The Apple refresh token could not be sealed for retry ({ExceptionType}); the account is deleted without a revocation.")]
    private static partial void LogSealFailed(ILogger logger, string exceptionType);
}
