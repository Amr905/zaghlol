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
    /// stays, D-58), deletes the <c>idempotency_records</c> rows of the account (R3-6), then the account (links cascade).
    /// </summary>
    Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken);
}
