using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Zaghlol.Ops.Auth;

/// <summary>A failed sign-in. Messages carry fixed text and settings names only: no token, code or IdP text.</summary>
internal sealed class LoginException(string message) : Exception(message)
{
}

/// <summary>Opens the IdP's authorization URL for the operator (the system browser; tests act as the browser).</summary>
internal interface IBrowserLauncher
{
    /// <summary>True when the URL was handed to a browser; false means the operator has to open the printed URL.</summary>
    bool TryOpen(Uri url);
}

/// <summary>
/// Authorization code + PKCE with a loopback redirect (RFC 8252, RFC 7636; R3-9). Only the discovery document's issuer and its
/// authorization and token endpoints are read, so no device-authorization endpoint can be used, and the only grant type
/// ever sent is <c>authorization_code</c>.
/// </summary>
internal sealed class OidcLogin(OpsConfig config, HttpClient http, IBrowserLauncher browser, TimeProvider clock, TextWriter error)
{
    public const int MaxDocumentBytes = 256 * 1024;

    public static readonly TimeSpan CallbackDeadline = TimeSpan.FromMinutes(3);

    public async Task<TokenSet> LoginAsync(bool openBrowser, CancellationToken cancellationToken)
    {
        var (authorize, token) = await DiscoverAsync(cancellationToken).ConfigureAwait(false);
        var pkce = Pkce.Create();
        using var receiver = new LoopbackReceiver();
        var redirect = $"http://{config.RedirectHost}:{receiver.Port.ToString(CultureInfo.InvariantCulture)}/callback";
        var url = BuildAuthorizeUrl(authorize, redirect, pkce);

        var opened = openBrowser && browser.TryOpen(url);
        error.WriteLine(opened
            ? "Your browser should open the sign-in page. If it does not, open this URL:"
            : "Open this URL in a browser to sign in:");
        error.WriteLine(url.AbsoluteUri);

        var callback = await receiver.WaitAsync(pkce.State, CallbackDeadline, cancellationToken).ConfigureAwait(false);
        if (callback.Code is null)
        {
            throw new LoginException("The identity provider refused the sign-in (" + callback.Error + ").");
        }

        return await ExchangeAsync(token, redirect, callback.Code, pkce, cancellationToken).ConfigureAwait(false);
    }

    private static Uri BuildAuthorizeUrl(Uri authorize, string redirect, Pkce pkce, OpsConfig config) =>
        new(authorize.AbsoluteUri + (authorize.Query.Length == 0 ? "?" : "&") + Query(
            ("response_type", "code"),
            ("client_id", config.ClientId),
            ("redirect_uri", redirect),
            ("scope", config.Scopes),
            ("state", pkce.State),
            ("nonce", pkce.Nonce),
            ("code_challenge", pkce.Challenge),
            ("code_challenge_method", "S256")));

    private Uri BuildAuthorizeUrl(Uri authorize, string redirect, Pkce pkce) => BuildAuthorizeUrl(authorize, redirect, pkce, config);

    private static string Query(params (string Name, string Value)[] pairs) =>
        string.Join('&', pairs.Select(p => Uri.EscapeDataString(p.Name) + "=" + Uri.EscapeDataString(p.Value)));

    private async Task<(Uri Authorize, Uri Token)> DiscoverAsync(CancellationToken cancellationToken)
    {
        var document = new Uri(config.Issuer.AbsoluteUri.TrimEnd('/') + "/.well-known/openid-configuration");
        using var request = new HttpRequestMessage(HttpMethod.Get, document);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new LoginException("The identity provider's discovery document could not be read.");
        }

        using var json = await ReadJsonAsync(response, cancellationToken).ConfigureAwait(false);
        var root = json.RootElement;
        // Mix-up defence: the document must name the issuer it was fetched for.
        if (!root.TryGetProperty("issuer", out var issuer) || issuer.ValueKind != JsonValueKind.String
            || !string.Equals(issuer.GetString()!.TrimEnd('/'), config.Issuer.AbsoluteUri.TrimEnd('/'), StringComparison.Ordinal))
        {
            throw new LoginException("The discovery document names a different issuer than the configured one.");
        }

        return (Endpoint(root, "authorization_endpoint"), Endpoint(root, "token_endpoint"));
    }

    private static Uri Endpoint(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String
            || !Uri.TryCreate(value.GetString(), UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(uri.UserInfo))
        {
            throw new LoginException($"The discovery document has no usable {name}.");
        }

        return uri;
    }

    private async Task<TokenSet> ExchangeAsync(Uri tokenEndpoint, string redirect, string code, Pkce pkce, CancellationToken cancellationToken)
    {
        var form = new List<KeyValuePair<string, string>>
        {
            new("grant_type", "authorization_code"),
            new("code", code),
            new("redirect_uri", redirect),
            new("client_id", config.ClientId),
            new("code_verifier", pkce.Verifier),
        };
        if (config.ClientSecret is not null)
        {
            form.Add(new("client_secret", config.ClientSecret));
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, tokenEndpoint) { Content = new FormUrlEncodedContent(form) };
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new LoginException("The identity provider's token endpoint refused the code (HTTP " + ((int)response.StatusCode).ToString(CultureInfo.InvariantCulture) + ").");
        }

        using var json = await ReadJsonAsync(response, cancellationToken).ConfigureAwait(false);
        var root = json.RootElement;
        var idToken = Text(root, "id_token");
        if (idToken is not null)
        {
            CheckIdToken(idToken, pkce.Nonce);
        }

        var chosen = config.TokenUse == TokenUse.IdToken ? idToken : Text(root, "access_token");
        if (chosen is null || !TokenSet.IsTokenShaped(chosen))
        {
            throw new LoginException(config.TokenUse == TokenUse.IdToken
                ? "The token response has no ID token (is the openid scope allowed?)."
                : "The token response has no JWT access token (use tokenUse=id_token, or configure the IdP to issue JWT access tokens).");
        }

        var exp = TokenSet.ReadClaim(chosen, "exp");
        if (!long.TryParse(exp, NumberStyles.None, CultureInfo.InvariantCulture, out var expSeconds))
        {
            throw new LoginException("The token has no expiry.");
        }

        var expiresAt = DateTimeOffset.FromUnixTimeSeconds(expSeconds);
        if (expiresAt <= clock.GetUtcNow())
        {
            throw new LoginException("The identity provider issued a token that is already expired.");
        }

        return new TokenSet(chosen, expiresAt, TokenSet.ReadClaim(chosen, "sub"));
    }

    /// <summary>
    /// The ID token came straight from the token endpoint over TLS, so its signature is the API's job; the CLI checks that it was
    /// issued for this request (nonce), this client (aud), this IdP (iss) and has not expired.
    /// </summary>
    private void CheckIdToken(string idToken, string nonce)
    {
        using var payload = TokenSet.ReadPayload(idToken) ?? throw new LoginException("The ID token is not a JWT.");
        var root = payload.RootElement;
        var issuer = root.TryGetProperty("iss", out var iss) && iss.ValueKind == JsonValueKind.String ? iss.GetString() : null;
        var issuerOk = string.Equals(issuer?.TrimEnd('/'), config.Issuer.AbsoluteUri.TrimEnd('/'), StringComparison.Ordinal)
            || (config.Issuer.Host == "accounts.google.com" && issuer == "accounts.google.com");
        var audience = root.TryGetProperty("aud", out var aud)
            && (aud.ValueKind == JsonValueKind.String
                ? aud.GetString() == config.ClientId
                : aud.ValueKind == JsonValueKind.Array && aud.EnumerateArray().Any(a => a.ValueKind == JsonValueKind.String && a.GetString() == config.ClientId));
        var nonceOk = root.TryGetProperty("nonce", out var n) && n.ValueKind == JsonValueKind.String && n.GetString() == nonce;
        if (!issuerOk || !audience || !nonceOk)
        {
            throw new LoginException("The ID token was not issued for this sign-in (issuer, audience or nonce differs).");
        }
    }

    private static string? Text(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            return await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException)
        {
            throw new LoginException("The identity provider could not be reached.");
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new LoginException("The identity provider did not answer in time.");
        }
    }

    private static async Task<JsonDocument> ReadJsonAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int read;
        while ((read = await stream.ReadAsync(chunk, cancellationToken).ConfigureAwait(false)) > 0)
        {
            buffer.Write(chunk, 0, read);
            if (buffer.Length > MaxDocumentBytes)
            {
                throw new LoginException("The identity provider's answer is too large.");
            }
        }

        try
        {
            var document = JsonDocument.Parse(buffer.ToArray());
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                return document;
            }

            document.Dispose();
        }
        catch (JsonException)
        {
            // Falls through to the error below.
        }

        throw new LoginException("The identity provider's answer is not a JSON object.");
    }
}
