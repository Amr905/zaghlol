using Zaghlol.Domain;

namespace Zaghlol.Application.Entitlements;

/// <summary>
/// Issues the signed, install-bound entitlement (T-132; backend-api §4.3, §4.4). The token's <c>sub</c> is always the calling
/// install; it covers only the seats that install holds. Never moves a seat. Signing failures propagate (no token is better
/// than an unsigned or wrong one).
/// </summary>
public sealed class EntitlementService(IEntitlementStore store, IEntitlementSigner signer, IAccountTokenValidator accounts, TimeProvider clock)
{
    /// <summary><c>GET /v1/entitlement</c>: validates the account header, issues the token and carries the support notice.</summary>
    public async Task<EntitlementIssue> GetAsync(InstallId install, Sensitive<string>? accountHeader, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var account = await accounts.ValidateAsync(accountHeader, install, now, cancellationToken).ConfigureAwait(false);
        return await IssueAsync(install, account?.AccountId, now, carryNotice: true, cancellationToken).ConfigureAwait(false);
    }

    /// <param name="carryNotice">
    /// The response may carry <c>supportNotice</c> (sync and entitlement 200s, not verify): when a purchase of the install has the
    /// flag pending, the token's <c>iat</c> is recorded for the delivery proof (R5-7) after the token was signed.
    /// </param>
    public async Task<EntitlementIssue> IssueAsync(
        InstallId install, Guid? presentedAccount, DateTimeOffset now, bool carryNotice, CancellationToken cancellationToken)
    {
        var facts = await store.ReadFactsAsync(install, now, cancellationToken).ConfigureAwait(false);
        var claims = EntitlementRules.Build(install, facts, presentedAccount, now);
        var token = await signer.SignEntitlementAsync(claims, cancellationToken).ConfigureAwait(false);

        string? notice = null;
        if (carryNotice && await store.SupportNoticePendingAsync(install, cancellationToken).ConfigureAwait(false))
        {
            await store.RecordSupportNoticeIatAsync(install, DateTimeOffset.FromUnixTimeSeconds(claims.Iat), cancellationToken).ConfigureAwait(false);
            notice = EntitlementWire.SupportNoticeLinked;
        }

        return new EntitlementIssue(token, notice, claims);
    }
}
