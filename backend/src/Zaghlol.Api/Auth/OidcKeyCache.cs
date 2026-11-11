using System.Text.Json;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Zaghlol.Domain;

namespace Zaghlol.Api.Auth;

/// <summary>
/// The operator IdP's signing keys (T-136 design note §2): <see cref="OidcJwksCache"/> for <c>OperatorAuth:Issuer</c>, refreshed every
/// <c>JwksRefreshHours</c> (24 h).
/// </summary>
internal sealed class OidcKeyCache(
    IHttpClientFactory clients,
    IOptions<OperatorAuthOptions> options,
    TimeProvider clock,
    ILogger<OidcKeyCache> logger,
    IHostApplicationLifetime? lifetime = null) : OidcJwksCache(clients, HttpClientName, clock, logger, lifetime)
{
    public const string HttpClientName = "zaghlol-operator-oidc";

    protected override string Issuer => options.Value.Issuer ?? string.Empty;

    protected override Uri DiscoveryUri => options.Value.DiscoveryUri();

    protected override TimeSpan RefreshEvery => TimeSpan.FromHours(options.Value.JwksRefreshHours);

    protected override string Source => "operator";
}

/// <summary>
/// An OpenID provider's signing keys, fetched from its discovery document and <c>jwks_uri</c>, HTTPS only (T-136 design note §2;
/// generalised by issuer for the Pub/Sub push tokens of T-133). The discovered <c>issuer</c> must equal the configured one (mix-up
/// defence). Keys are refreshed every <see cref="RefreshEvery"/>; an unknown <c>kid</c> forces at most one refresh per 5 minutes, so a
/// flood of made-up key IDs can't hammer the provider; and a failed refresh keeps the last good keys for up to 7 days, then fails
/// closed. Header-supplied keys (<c>jku</c>, <c>x5u</c>, <c>jwk</c>) are never fetched or used. Written instead of
/// <c>ConfigurationManager</c> so the timing rules are exact and testable with a <see cref="TimeProvider"/>.
/// </summary>
internal abstract partial class OidcJwksCache(
    IHttpClientFactory clients,
    string clientName,
    TimeProvider clock,
    ILogger logger,
    IHostApplicationLifetime? lifetime) : IDisposable
{
    /// <summary>The longest the last good keys are used while the IdP can't be reached.</summary>
    public static readonly TimeSpan LastGoodLifetime = TimeSpan.FromDays(7);

    /// <summary>The minimum time between two completed refresh attempts (forced or after a failure).</summary>
    public static readonly TimeSpan RefreshThrottle = TimeSpan.FromMinutes(5);

    /// <summary>More keys than this in a JWKS is treated as a malformed document.</summary>
    public const int MaxKeys = 50;

    private readonly Lock sync = new();
    private readonly CancellationTokenSource disposed = new();
    private volatile KeySnapshot? current;
    private DateTimeOffset? lastAttempt;
    private Task? inflight;

    /// <summary>When the keys in use were fetched; <c>null</c> before the first success.</summary>
    public DateTimeOffset? FetchedAt => current?.FetchedAt;

    /// <summary>
    /// True while a key set no older than <see cref="LastGoodLifetime"/> is held. False before the first success and once the last good
    /// keys expired: a caller can tell "unknown kid" (a forged token) from "no keys at all" (fail closed, but retryable).
    /// </summary>
    public bool HasUsableKeys => current is { } snapshot && clock.GetUtcNow() - snapshot.FetchedAt <= LastGoodLifetime;

    /// <summary>The exact <c>issuer</c> the discovery document must announce.</summary>
    protected abstract string Issuer { get; }

    /// <summary><c>{issuer}/.well-known/openid-configuration</c>.</summary>
    protected abstract Uri DiscoveryUri { get; }

    protected abstract TimeSpan RefreshEvery { get; }

    /// <summary>A fixed word naming the provider in logs (<c>operator</c>, <c>google</c>).</summary>
    protected abstract string Source { get; }

    /// <summary>The refresh in flight, or a completed task. Callers never cancel it; tests await it.</summary>
    internal Task PendingRefresh
    {
        get
        {
            lock (sync)
            {
                return inflight ?? Task.CompletedTask;
            }
        }
    }

    /// <summary>
    /// The signing key with this <c>kid</c>, or <c>null</c>. Refreshes on schedule, and once per throttle window for an
    /// unknown <c>kid</c>; returns <c>null</c> once the last good keys are older than <see cref="LastGoodLifetime"/>.
    /// <paramref name="cancellationToken"/> only stops this caller waiting: a refresh it started runs on to completion.
    /// </summary>
    public async ValueTask<JsonWebKey?> FindAsync(string kid, CancellationToken cancellationToken)
    {
        var refreshEvery = RefreshEvery;
        var snapshot = current;
        if (snapshot is null || clock.GetUtcNow() - snapshot.FetchedAt >= refreshEvery)
        {
            await RefreshAsync(cancellationToken);
            snapshot = current;
        }

        if (snapshot is not null && clock.GetUtcNow() - snapshot.FetchedAt > LastGoodLifetime)
        {
            return null;
        }

        if (snapshot is not null && snapshot.Keys.TryGetValue(kid, out var key))
        {
            return key;
        }

        // Unknown kid: maybe the IdP rotated. One forced refresh per throttle window.
        await RefreshAsync(cancellationToken);
        snapshot = current;
        return snapshot is not null && clock.GetUtcNow() - snapshot.FetchedAt <= LastGoodLifetime
               && snapshot.Keys.TryGetValue(kid, out key)
            ? key
            : null;
    }

    /// <summary>Fetches now, regardless of the throttle (the startup check). Throws when discovery or the JWKS fails.</summary>
    public async Task LoadAsync(CancellationToken cancellationToken)
    {
        var started = clock.GetUtcNow();
        using var fetch = FetchCancellation();
        using var link = CancellationTokenSource.CreateLinkedTokenSource(fetch.Token, cancellationToken);
        try
        {
            current = await FetchAsync(link.Token);
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            MarkAttempt(started);
            throw;
        }

        MarkAttempt(started);
    }

    public void Dispose()
    {
        disposed.Cancel();
        disposed.Dispose();
    }

    /// <summary>
    /// Joins the refresh in flight, or starts one unless a completed attempt lies inside the throttle window. The fetch
    /// never runs on the caller's token (S-1): a caller that aborts only stops waiting, so it can't burn the window.
    /// </summary>
    private Task RefreshAsync(CancellationToken cancellationToken)
    {
        Task task;
        lock (sync)
        {
            if (inflight is null || inflight.IsCompleted)
            {
                var now = clock.GetUtcNow();
                if (lastAttempt is { } last && now - last < RefreshThrottle)
                {
                    return Task.CompletedTask;
                }

                inflight = Task.Run(() => RunRefreshAsync(now), CancellationToken.None);
            }

            task = inflight;
        }

        return task.WaitAsync(cancellationToken);
    }

    /// <summary>One refresh on a shutdown + 10 s token. Never throws; a failure keeps the last good keys (up to 7 days).</summary>
    private async Task RunRefreshAsync(DateTimeOffset started)
    {
        try
        {
            using var fetch = FetchCancellation();
            current = await FetchAsync(fetch.Token);
            MarkAttempt(started);
            LogRefreshed(logger, Source, current.Keys.Count);
        }
        catch (OperationCanceledException) when (IsShuttingDown())
        {
            // Shutdown is not an attempt; nothing to record.
        }
#pragma warning disable CA1031 // A failed refresh keeps the last good keys (up to 7 days); the error type is logged, never the body.
        catch (Exception ex)
#pragma warning restore CA1031
        {
            // A real fetch failure, including the 10 s IdP timeout, counts toward the throttle window.
            MarkAttempt(started);
            LogRefreshFailed(logger, Source, ex.GetType().Name);
        }
    }

    private void MarkAttempt(DateTimeOffset started)
    {
        lock (sync)
        {
            if (lastAttempt is null || started > lastAttempt)
            {
                lastAttempt = started;
            }
        }
    }

    /// <summary>Cancelled by host shutdown, disposal, or after the IdP timeout; never by an HTTP request.</summary>
    private CancellationTokenSource FetchCancellation()
    {
        var stopping = lifetime?.ApplicationStopping ?? CancellationToken.None;
        var source = CancellationTokenSource.CreateLinkedTokenSource(stopping, disposed.Token);
        source.CancelAfter(OperatorAuthServiceCollectionExtensions.IdpTimeout);
        return source;
    }

    private bool IsShuttingDown()
    {
        try
        {
            return disposed.IsCancellationRequested || lifetime?.ApplicationStopping.IsCancellationRequested == true;
        }
        catch (ObjectDisposedException)
        {
            return true;
        }
    }

    private async Task<KeySnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        var client = clients.CreateClient(clientName);

        using var discovery = JsonDocument.Parse(await GetAsync(client, DiscoveryUri, cancellationToken));
        var root = discovery.RootElement;
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("issuer", out var issuer) || issuer.ValueKind != JsonValueKind.String
            || !string.Equals(issuer.GetString(), Issuer, StringComparison.Ordinal))
        {
            throw new OidcDiscoveryException("The discovered issuer does not equal the configured issuer.");
        }

        if (!root.TryGetProperty("jwks_uri", out var jwksUri) || jwksUri.ValueKind != JsonValueKind.String
            || !Uri.TryCreate(jwksUri.GetString(), UriKind.Absolute, out var jwks) || jwks.Scheme != Uri.UriSchemeHttps)
        {
            throw new OidcDiscoveryException("The discovery document has no https jwks_uri.");
        }

        var set = new JsonWebKeySet(await GetAsync(client, jwks, cancellationToken));
        if (set.Keys.Count > MaxKeys)
        {
            throw new OidcDiscoveryException("The JWKS holds too many keys.");
        }

        var keys = new Dictionary<string, JsonWebKey>(StringComparer.Ordinal);
        foreach (var key in set.Keys)
        {
            if (Accepts(key))
            {
                keys.TryAdd(key.Kid, key);
            }
        }

        if (keys.Count == 0)
        {
            throw new OidcDiscoveryException("The JWKS holds no usable signing key.");
        }

        return new KeySnapshot(keys, clock.GetUtcNow());
    }

    /// <summary>Which keys of the JWKS are kept (default <see cref="IsUsableSigningKey"/>).</summary>
    protected virtual bool Accepts(JsonWebKey key) => IsUsableSigningKey(key);

    /// <summary>A public RSA or P-256 key with a <c>kid</c>, meant for signatures. Private keys and other kinds are skipped.</summary>
    internal static bool IsUsableSigningKey(JsonWebKey key) =>
        !string.IsNullOrEmpty(key.Kid)
        && (string.IsNullOrEmpty(key.Use) || string.Equals(key.Use, "sig", StringComparison.Ordinal))
        && string.IsNullOrEmpty(key.D)
        && ((string.Equals(key.Kty, "RSA", StringComparison.Ordinal) && !string.IsNullOrEmpty(key.N) && !string.IsNullOrEmpty(key.E))
            || (string.Equals(key.Kty, "EC", StringComparison.Ordinal) && string.Equals(key.Crv, "P-256", StringComparison.Ordinal)
                && !string.IsNullOrEmpty(key.X) && !string.IsNullOrEmpty(key.Y)));

    private static async Task<string> GetAsync(HttpClient client, Uri uri, CancellationToken cancellationToken)
    {
        if (uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new OidcDiscoveryException("OIDC documents are fetched over https only.");
        }

        using var response = await client.GetAsync(uri, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new OidcDiscoveryException("An OIDC document could not be fetched.");
        }

        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "OIDC signing keys refreshed for {KeySource} ({KeyCount} keys)")]
    private static partial void LogRefreshed(ILogger logger, string keySource, int keyCount);

    [LoggerMessage(Level = LogLevel.Warning, Message = "OIDC signing key refresh failed for {KeySource} ({ExceptionType}); keeping the last good keys")]
    private static partial void LogRefreshFailed(ILogger logger, string keySource, string exceptionType);

    private sealed record KeySnapshot(IReadOnlyDictionary<string, JsonWebKey> Keys, DateTimeOffset FetchedAt);
}

/// <summary>The operator IdP's discovery document or JWKS is unusable. The message names no value from the documents.</summary>
public sealed class OidcDiscoveryException : SafeException
{
    public OidcDiscoveryException()
    {
    }

    public OidcDiscoveryException(string message)
        : base(message)
    {
    }

    public OidcDiscoveryException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
