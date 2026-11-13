using Zaghlol.Domain;

namespace Zaghlol.Application.Entitlements;

/// <summary>An account token that passed every check (<see cref="IAccountTokenValidator"/>).</summary>
public sealed record ValidatedAccountToken(Guid AccountId, DateTimeOffset ExpiresAt);

/// <summary>
/// Decides what a <c>Zaghlol-Account</c> header proves (backend-api §3): an ES256 token of the entitlement key ring, <c>iid</c> equal to
/// the calling install, not expired, and its account still existing with this install linked (R3-6). Anything else, malformed
/// or expired included, is <c>null</c>: the caller treats it as no token (account-linked Gold is then <c>paused</c>) and never
/// turns a payment into an error (BR-GOLD-06). The header is never logged.
/// </summary>
public interface IAccountTokenValidator
{
    Task<ValidatedAccountToken?> ValidateAsync(Sensitive<string>? token, InstallId caller, DateTimeOffset now, CancellationToken cancellationToken);
}

/// <summary>Signs with the entitlement key ring (T-123 <c>ISigner</c>); the keys never leave the KMS.</summary>
public interface IEntitlementSigner
{
    Task<string> SignEntitlementAsync(EntitlementClaims claims, CancellationToken cancellationToken);

    Task<string> SignAccountTokenAsync(AccountTokenClaims claims, CancellationToken cancellationToken);
}

/// <summary>The reads and the notice bookkeeping of the entitlement, on the App login.</summary>
public interface IEntitlementStore
{
    /// <summary>
    /// The purchases whose seat <paramref name="install"/> holds (any state) and the entitling purchases it bought whose seat
    /// another install holds, with who moved them (the last seat event of the purchase).
    /// </summary>
    Task<EntitlementFacts> ReadFactsAsync(InstallId install, DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>Whether a purchase bought by this install has <c>support_link_notice_pending</c> (R4-7(2)).</summary>
    Task<bool> SupportNoticePendingAsync(InstallId install, CancellationToken cancellationToken);

    /// <summary>Stores <paramref name="iat"/> as <c>support_link_notice_iat</c> of the install's pending purchases (R5-7).</summary>
    Task RecordSupportNoticeIatAsync(InstallId install, DateTimeOffset iat, CancellationToken cancellationToken);

    /// <summary>
    /// Clears <c>support_link_notice_pending</c> of the install's purchases whose recorded <c>support_link_notice_iat</c> is at or
    /// before <paramref name="issuedAt"/>: the app proved it stored a response that carried the notice (R5-7).
    /// </summary>
    Task ClearDeliveredSupportNoticeAsync(InstallId install, DateTimeOffset issuedAt, CancellationToken cancellationToken);

    /// <summary>Any purchase event on a purchase this install bought or holds after <paramref name="since"/> (a refund, a move, a bind).</summary>
    Task<bool> ChangedSinceAsync(InstallId install, DateTimeOffset since, CancellationToken cancellationToken);
}
