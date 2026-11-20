namespace Zaghlol.Ops.Auth;

/// <summary>
/// The operator's token for this run: from the credential store while it is valid, else a new sign-in. A store that fails is
/// reported once and the token then lives in memory for this process only; there is no file fallback.
/// </summary>
internal sealed class TokenProvider(OpsConfig config, ITokenStore store, ITokenStore memory, Func<bool, CancellationToken, Task<TokenSet>> login, TimeProvider clock, TextWriter error)
{
    /// <summary>A token closer to expiry than this is not used (the API allows 60 s of skew; this stays inside it).</summary>
    public static readonly TimeSpan Margin = TimeSpan.FromSeconds(60);

    private TokenSet? current;
    private bool storeFailureReported;

    public string StoreName => config.TokenCache == TokenCacheMode.Memory ? memory.Name : store.Name;

    private ITokenStore Active => config.TokenCache == TokenCacheMode.Memory ? memory : store;

    /// <summary>The cached token when it is still valid; never starts a sign-in.</summary>
    public async Task<TokenSet?> CachedAsync(CancellationToken cancellationToken)
    {
        if (current is not null && current.ExpiresAt - Margin > clock.GetUtcNow())
        {
            return current;
        }

        var stored = TokenSet.TryParse(await Active.ReadAsync(config.CacheKey(), cancellationToken).ConfigureAwait(false));
        if (stored is not null && stored.ExpiresAt - Margin > clock.GetUtcNow())
        {
            current = stored;
            return stored;
        }

        if (stored is not null)
        {
            // Expired: it is only a cache entry, and the delete is confirmed by the store.
            await Active.DeleteAsync(config.CacheKey(), cancellationToken).ConfigureAwait(false);
        }

        return null;
    }

    public async Task<TokenSet> GetAsync(bool openBrowser, CancellationToken cancellationToken) =>
        await CachedAsync(cancellationToken).ConfigureAwait(false) ?? await SignInAsync(openBrowser, cancellationToken).ConfigureAwait(false);

    public async Task<TokenSet> SignInAsync(bool openBrowser, CancellationToken cancellationToken)
    {
        var token = await login(openBrowser, cancellationToken).ConfigureAwait(false);
        current = token;
        var stored = await Active.WriteAsync(config.CacheKey(), token.Serialize(), cancellationToken).ConfigureAwait(false);
        if (!stored && config.TokenCache == TokenCacheMode.Os && !storeFailureReported)
        {
            storeFailureReported = true;
            error.WriteLine("Note: no usable OS credential store; the token is kept in memory for this run only.");
            await memory.WriteAsync(config.CacheKey(), token.Serialize(), cancellationToken).ConfigureAwait(false);
        }

        return token;
    }

    /// <summary>Forgets the token everywhere. False when the credential store could not confirm the delete.</summary>
    public async Task<bool> SignOutAsync(CancellationToken cancellationToken)
    {
        current = null;
        await memory.DeleteAsync(config.CacheKey(), cancellationToken).ConfigureAwait(false);
        return config.TokenCache == TokenCacheMode.Memory || await store.DeleteAsync(config.CacheKey(), cancellationToken).ConfigureAwait(false);
    }

    /// <summary>The token was refused by the API (401): drop it so that the next run signs in again.</summary>
    public async Task ForgetAsync(CancellationToken cancellationToken)
    {
        current = null;
        await memory.DeleteAsync(config.CacheKey(), cancellationToken).ConfigureAwait(false);
        if (config.TokenCache == TokenCacheMode.Os)
        {
            await store.DeleteAsync(config.CacheKey(), cancellationToken).ConfigureAwait(false);
        }
    }
}
