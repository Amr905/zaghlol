using Zaghlol.Application.Sync;

namespace Zaghlol.Application.Entitlements;

/// <summary>
/// The sync's entitlement, account-token and support-notice blocks (T-132 fills T-128's extension point; backend-api §4.2).
/// A fresh token goes out when the cached one (<c>entitlementIssuedAt</c>) is missing, in the future, more than 12 h old or
/// anything changed since, and always together with the support notice. The delivery proof (R5-7) is applied first, so the sync
/// that proves it doesn't repeat the notice. Every side effect is idempotent (the call may become a throttle answer).
/// </summary>
public sealed class SyncEntitlementBlock(EntitlementService entitlement, IEntitlementStore store, IEntitlementSigner signer, IAccountTokenValidator accounts)
    : ISyncEntitlementBlock
{
    public async Task<SyncEntitlementResult> ComposeAsync(SyncEntitlementContext context, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(context);

        var install = context.InstallId;
        var now = context.Now;
        var issuedAt = context.EntitlementIssuedAt;
        if (issuedAt is { } proved)
        {
            await store.ClearDeliveredSupportNoticeAsync(install, proved, cancellationToken).ConfigureAwait(false);
        }

        var account = await accounts.ValidateAsync(context.AccountToken, install, now, cancellationToken).ConfigureAwait(false);
        var notice = await store.SupportNoticePendingAsync(install, cancellationToken).ConfigureAwait(false);
        var stale = issuedAt is not { } at
            || at > now
            || now - at > EntitlementLifetimes.RefreshAfter
            || await store.ChangedSinceAsync(install, at, cancellationToken).ConfigureAwait(false);

        EntitlementIssue? issue = null;
        if (notice || stale)
        {
            issue = await entitlement.IssueAsync(install, account?.AccountId, now, carryNotice: true, cancellationToken).ConfigureAwait(false);
        }

        string? accountToken = null;
        if (account is { } valid && valid.ExpiresAt - now < EntitlementLifetimes.AccountTokenRefreshWindow)
        {
            var iat = EntitlementRules.Whole(now);
            accountToken = await signer.SignAccountTokenAsync(
                new AccountTokenClaims(
                    valid.AccountId.ToString("D", System.Globalization.CultureInfo.InvariantCulture),
                    install.ToString(),
                    iat.ToUnixTimeSeconds(),
                    (iat + EntitlementLifetimes.AccountTokenLife).ToUnixTimeSeconds()),
                cancellationToken).ConfigureAwait(false);
        }

        return issue is null && accountToken is null
            ? SyncEntitlementResult.None
            : new SyncEntitlementResult(issue?.Token, accountToken, issue?.SupportNotice);
    }
}
