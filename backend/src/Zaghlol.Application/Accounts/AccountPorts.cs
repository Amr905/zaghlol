using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Accounts;

/// <summary>The identity providers of an account (<c>accounts.provider</c>).</summary>
public enum AccountProvider
{
    Google,
    Apple,
}

/// <summary>How an ID token verification ended.</summary>
public enum IdTokenOutcome
{
    /// <summary>Signature, <c>iss</c>, <c>aud</c> and <c>exp</c> hold.</summary>
    Verified,

    /// <summary>Anything else about the token (malformed, forged, wrong audience, expired): <c>422 ID_TOKEN_INVALID</c>.</summary>
    Invalid,

    /// <summary>The provider's signing keys can't be had right now: <c>503</c>, the app retries.</summary>
    Unavailable,
}

/// <summary>The claims of a verified ID token that sign-in needs. Never logged: <see cref="ToString"/> is <c>***</c>.</summary>
/// <param name="Subject">The provider's stable <c>sub</c>.</param>
/// <param name="Email">The <c>email</c> claim when the provider returned one (support lookup only, A-47).</param>
/// <param name="Audience">The <c>aud</c> that matched our configuration (Apple: the client ID the refresh token belongs to).</param>
/// <param name="Nonce">The <c>nonce</c> claim, or null when the token has none.</param>
/// <param name="IssuedAt">The <c>iat</c> claim, or null when the token has none.</param>
public sealed record VerifiedIdToken(string Subject, string? Email, string Audience, string? Nonce, DateTimeOffset? IssuedAt, DateTimeOffset ExpiresAt)
{
    public override string ToString() => "***";
}

public sealed record IdTokenResult(IdTokenOutcome Outcome, VerifiedIdToken? Token)
{
    public static IdTokenResult Invalid { get; } = new(IdTokenOutcome.Invalid, null);

    public static IdTokenResult Unavailable { get; } = new(IdTokenOutcome.Unavailable, null);
}

/// <summary>
/// Verifies a provider's ID token against its published keys (Google <c>aud</c> in our client IDs, Apple <c>aud</c> = Services ID or
/// bundle ID, <c>iss</c>, <c>exp</c>, RS256 only, keys from the provider's JWKS). The nonce, the age and single use are
/// <see cref="SignInService"/>'s. Tests use a fake; no test touches the network.
/// </summary>
public interface IIdTokenVerifier
{
    ValueTask<IdTokenResult> VerifyAsync(AccountProvider provider, Sensitive<string> idToken, CancellationToken cancellationToken);
}

/// <summary>Single use of an ID token's nonce (<c>replay_guard</c>); each call commits on its own (R3-5).</summary>
public interface IIdTokenReplayGuard
{
    /// <summary>Inserts the hash until <paramref name="expiresAt"/>; false when it was already there.</summary>
    Task<bool> TryUseAsync(AccountProvider provider, ReadOnlyMemory<byte> nonceClaimHash, DateTimeOffset expiresAt, CancellationToken cancellationToken);
}

/// <summary>The refresh token Apple issued for an authorization code (used only to revoke on deletion).</summary>
public sealed record AppleRefreshToken(string ClientId, Sensitive<string> Token)
{
    public override string ToString() => "***";
}

public enum AppleRevokeOutcome
{
    /// <summary>Apple revoked it, or says it no longer exists (already revoked).</summary>
    Revoked,

    /// <summary>Apple couldn't be reached or refused for a reason a retry may cure.</summary>
    Unavailable,
}

/// <summary>Sign in with Apple's token endpoint: exchange at sign-in, revoke at deletion. Fakes in tests.</summary>
public interface IAppleAccountClient
{
    /// <summary>
    /// Exchanges the authorization code for a refresh token. Null when the exchange fails or the returned identity isn't
    /// <paramref name="expectedSubject"/>: sign-in itself never fails for it (the token only enables revocation).
    /// </summary>
    Task<AppleRefreshToken?> ExchangeCodeAsync(Sensitive<string> code, string clientId, string expectedSubject, CancellationToken cancellationToken);

    Task<AppleRevokeOutcome> RevokeAsync(AppleRefreshToken token, CancellationToken cancellationToken);
}

/// <summary>Seals the Apple refresh token under a context bound to its account's provider subject (envelope encryption).</summary>
public interface IAppleTokenVault
{
    Task<byte[]> SealAsync(string subject, AppleRefreshToken token, CancellationToken cancellationToken);

    /// <summary>Null when the blob doesn't open under this subject.</summary>
    Task<AppleRefreshToken?> OpenAsync(string subject, ReadOnlyMemory<byte> sealedToken, CancellationToken cancellationToken);
}

/// <summary>The sign-in statements inside the caller's open transaction (same connection as <see cref="ISeatStore"/>).</summary>
public interface IAccountTxStore
{
    /// <summary><c>installs</c> row <c>FOR UPDATE</c> (the first lock of the order installs, purchases, seats); false when it doesn't exist or is deleted.</summary>
    Task<bool> LockInstallAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>Inserts the account, or refreshes <c>last_sign_in_at</c> (and the e-mail and refresh token when new ones came); returns its ID.</summary>
    Task<Guid> UpsertAccountAsync(
        AccountProvider provider, string subject, string? email, byte[]? appleRefreshTokenSealed, DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>The accounts this install is linked to.</summary>
    Task<IReadOnlyList<Guid>> LinkedAccountsOfInstallAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>Removes every link of the install (<c>replaceLink</c>, EC-46).</summary>
    Task UnlinkInstallAsync(Guid installId, CancellationToken cancellationToken);

    Task LinkAsync(Guid accountId, Guid installId, DateTimeOffset now, CancellationToken cancellationToken);

    Task<int> CountLinkedInstallsAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>
    /// Locks, in ascending ID order and in one statement, every purchase sign-in is about to touch: the unlinked purchases bought by
    /// <paramref name="installId"/> and every purchase already linked to <paramref name="accountId"/>. Called before the attach, so
    /// sign-in, delete and restore all lock purchases in the one global (uuid) order and can't deadlock.
    /// </summary>
    Task LockPurchasesAsync(Guid installId, Guid accountId, CancellationToken cancellationToken);

    /// <summary>
    /// D-54 attach: sets <c>account_id</c> and <c>account_linked_by = 'signin'</c> on the purchases with no account whose buying
    /// install (<c>purchases.install_id</c>) is <paramref name="installId"/>, locked in ascending ID order. Returns their IDs.
    /// </summary>
    Task<IReadOnlyList<Guid>> AttachBuyingPurchasesAsync(Guid installId, Guid accountId, CancellationToken cancellationToken);

    /// <summary>The entitling purchases (<c>active</c>, <c>in_grace</c>, <c>canceled_active</c>) linked to the account, ascending ID.</summary>
    Task<IReadOnlyList<Guid>> ListEntitlingPurchasesAsync(Guid accountId, CancellationToken cancellationToken);
}

/// <summary>A READ COMMITTED transaction on the App login with the seat and account statements; rolled back on dispose unless committed.</summary>
public interface IAccountTransaction : IAsyncDisposable
{
    ISeatStore Seats { get; }

    IAccountTxStore Accounts { get; }

    Task CommitAsync(CancellationToken cancellationToken);
}

public interface IAccountTransactionFactory
{
    Task<IAccountTransaction> BeginAsync(CancellationToken cancellationToken);
}

/// <summary>What delete needs of an account: who it is and its sealed Apple refresh token.</summary>
public sealed record AccountForDelete(AccountProvider Provider, string Subject, byte[]? AppleRefreshTokenSealed)
{
    public override string ToString() => "***";
}

/// <summary>Single statements outside a sign-in transaction. Deletes are SQL, never tracked graphs (FU-015).</summary>
public interface IAccountStore
{
    /// <summary><c>ios</c> or <c>android</c> from <c>installs.platform</c>; null when the install doesn't exist or is deleted.</summary>
    Task<string?> ReadInstallPlatformAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>Removes the (account, install) link; seats are not touched (D-61(c)).</summary>
    Task UnlinkInstallAsync(Guid accountId, Guid installId, CancellationToken cancellationToken);

    Task<AccountForDelete?> ReadForDeleteAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>
    /// One transaction: clears <c>account_id</c> and <c>account_linked_by</c> of the account's purchases (<c>attach_reclaim_used_at</c>
    /// stays, D-58), deletes the <c>idempotency_records</c> rows of the account (R3-6), then the account (links cascade). When
    /// <paramref name="pendingRevocationSealed"/> is set, the same transaction inserts one <c>pending_apple_revocations</c> row for it
    /// (sealed blob and times only, no account reference; kept <see cref="PendingAppleRevocationPolicy.Window"/>).
    /// </summary>
    Task DeleteAccountAsync(Guid accountId, byte[]? pendingRevocationSealed, DateTimeOffset now, CancellationToken cancellationToken);
}

/// <summary>A sealed Apple refresh token waiting for a successful revocation. Never logged.</summary>
public sealed record PendingAppleRevocation(Guid Id, byte[] SealedToken, int Attempts)
{
    public override string ToString() => "***";
}

/// <summary>The retry rules of <c>pending_apple_revocations</c> (Lead decision: deletion is never blocked by Apple).</summary>
public static class PendingAppleRevocationPolicy
{
    /// <summary>How long a failed revocation is retried before the sealed token is dropped.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromDays(30);

    /// <summary>
    /// The vault context of a pending blob. The account (and its provider subject) is gone, so the token is re-sealed under this
    /// constant instead of the subject.
    /// </summary>
    public const string VaultSubject = "pending-apple-revocation";

    public static readonly TimeSpan FirstDelay = TimeSpan.FromMinutes(15);

    public static readonly TimeSpan MaxDelay = TimeSpan.FromHours(24);

    /// <summary>Exponential back-off from <see cref="FirstDelay"/> (15 min, 30 min, 1 h, ...) capped at <see cref="MaxDelay"/>.</summary>
    public static TimeSpan DelayAfter(int attempts)
    {
        var doublings = Math.Clamp(attempts, 0, 12);
        var delay = TimeSpan.FromTicks(FirstDelay.Ticks << doublings);
        return delay > MaxDelay ? MaxDelay : delay;
    }
}

/// <summary>The Worker login's access to <c>pending_apple_revocations</c>.</summary>
public interface IPendingAppleRevocationStore
{
    /// <summary>Deletes rows past their window (the retry gave up); returns how many.</summary>
    Task<int> DeleteExpiredAsync(DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>Rows whose next attempt is due, oldest first.</summary>
    Task<IReadOnlyList<PendingAppleRevocation>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken);

    Task DeleteAsync(Guid id, CancellationToken cancellationToken);

    Task DeferAsync(Guid id, int attempts, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken);
}
