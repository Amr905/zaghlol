using System.Buffers.Text;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Ops.Auth;
using Zaghlol.Testing;

namespace Zaghlol.Ops.Tests.Support;

/// <summary>How the scripted browser answers the authorization request.</summary>
internal enum BrowserMode
{
    /// <summary>Redirects back with a code and the right state.</summary>
    Normal,

    /// <summary>First hits the callback with a wrong state (a local attacker), then does it properly.</summary>
    WrongStateFirst,

    /// <summary>Redirects back with <c>error=access_denied</c>.</summary>
    Denied,

    /// <summary>Redirects back with a code that the token endpoint does not know.</summary>
    UnknownCode,

    /// <summary>Does nothing (the browser never returns).</summary>
    Silent,
}

/// <summary>
/// An in-process authorization server for the CLI sign-in tests, on top of <see cref="FakeOidcIssuer"/>: discovery (with a
/// device-authorization endpoint as bait), an authorization step done by <see cref="Browser"/>, and a token endpoint that checks
/// the PKCE verifier, the redirect URI and the grant type. Every request it sees is recorded.
/// </summary>
internal sealed class CliTestIdp : IDisposable
{
    public const string ClientId = FakeOidcIssuer.CliAudience;

    private readonly Dictionary<string, (string Challenge, string Nonce, string Redirect)> codes = new(StringComparer.Ordinal);
    private readonly object gate = new();

    public CliTestIdp(string? subject = null)
    {
        Subject = subject ?? "sub-" + Guid.NewGuid().ToString("N");
        Browser = new ScriptedBrowser(this);
    }

    public FakeOidcIssuer Issuer { get; } = new();

    public string Subject { get; set; }

    public IReadOnlyList<string> Roles { get; set; } = [];

    public List<string> Requests { get; } = [];

    public List<string> GrantTypes { get; } = [];

    public int TokenRequests { get; private set; }

    public bool FailPkce { get; set; }

    public string? NonceOverride { get; set; }

    public long LifetimeSeconds { get; set; } = 3600;

    public string? AuthorizeUrl { get; private set; }

    public ScriptedBrowser Browser { get; }

    public HttpMessageHandler CreateHandler() => new Handler(this);

    public void Dispose()
    {
        Issuer.Dispose();
        Browser.Dispose();
    }

    /// <summary>The authorization step: validates the request and returns the callback URL for the browser to visit.</summary>
    internal Uri Authorize(Uri url, BrowserMode mode)
    {
        var query = ParseQuery(url.Query);
        Assert.Equal("code", query["response_type"]);
        Assert.Equal(ClientId, query["client_id"]);
        Assert.Equal("S256", query["code_challenge_method"]);
        Assert.StartsWith("openid", query["scope"], StringComparison.Ordinal);
        Assert.Matches("^http://(localhost|127\\.0\\.0\\.1):[0-9]+/callback$", query["redirect_uri"]);
        Assert.True(query["state"].Length >= 16 && query["nonce"].Length >= 16 && query["code_challenge"].Length == 43);
        AuthorizeUrl = url.AbsoluteUri;
        Requests.Add("GET " + url.GetLeftPart(UriPartial.Path));

        var redirect = query["redirect_uri"];
        string result;
        switch (mode)
        {
            case BrowserMode.Denied:
                result = redirect + "?error=access_denied&error_description=" + Uri.EscapeDataString("Secret IdP text") + "&state=" + Uri.EscapeDataString(query["state"]);
                break;
            case BrowserMode.UnknownCode:
                result = redirect + "?code=not-a-known-code&state=" + Uri.EscapeDataString(query["state"]);
                break;
            default:
                var code = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(18));
                lock (gate)
                {
                    codes[code] = (query["code_challenge"], query["nonce"], redirect);
                }

                result = redirect + "?code=" + code + "&state=" + Uri.EscapeDataString(query["state"]);
                break;
        }

        return new Uri(result);
    }

    internal static Dictionary<string, string> ParseQuery(string query) =>
        query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(pair => pair.Split('=', 2))
            .ToDictionary(p => Uri.UnescapeDataString(p[0]), p => Uri.UnescapeDataString(p.Length > 1 ? p[1] : string.Empty), StringComparer.Ordinal);

    private HttpResponseMessage Token(string body)
    {
        var form = ParseQuery(body.Replace('+', ' '));
        TokenRequests++;
        GrantTypes.Add(form.GetValueOrDefault("grant_type", string.Empty));
        if (form.GetValueOrDefault("grant_type") != "authorization_code" || !form.TryGetValue("code", out var code))
        {
            return Json(HttpStatusCode.BadRequest, "{\"error\":\"unsupported_grant_type\"}");
        }

        (string Challenge, string Nonce, string Redirect) entry;
        lock (gate)
        {
            if (!codes.Remove(code, out entry))
            {
                return Json(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
            }
        }

        var verifier = form.GetValueOrDefault("code_verifier", string.Empty);
        if (FailPkce || Pkce.ChallengeFor(verifier) != entry.Challenge || form.GetValueOrDefault("redirect_uri") != entry.Redirect || form.GetValueOrDefault("client_id") != ClientId)
        {
            return Json(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
        }

        var token = Issuer.Mint(
            new OperatorTokenSpec
            {
                Subject = Subject,
                Roles = Roles.Count == 0 ? null : Roles,
                LifetimeSeconds = LifetimeSeconds,
                Extra = new Dictionary<string, JsonNode?> { ["nonce"] = NonceOverride ?? entry.Nonce },
            },
            DateTimeOffset.UtcNow);
        var answer = new JsonObject { ["token_type"] = "Bearer", ["id_token"] = token, ["access_token"] = token, ["expires_in"] = LifetimeSeconds };
        return Json(HttpStatusCode.OK, answer.ToJsonString());
    }

    private static HttpResponseMessage Json(HttpStatusCode status, string body) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    private sealed class Handler(CliTestIdp idp) : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var url = request.RequestUri!.AbsoluteUri;
            idp.Requests.Add(request.Method + " " + request.RequestUri.GetLeftPart(UriPartial.Path));
            if (url == idp.Issuer.Issuer + "/token" && request.Method == HttpMethod.Post)
            {
                return idp.Token(await request.Content!.ReadAsStringAsync(cancellationToken));
            }

            using var inner = idp.Issuer.CreateHandler();
            using var invoker = new HttpMessageInvoker(inner);
            var response = await invoker.SendAsync(request, cancellationToken);
            if (url.EndsWith("/.well-known/openid-configuration", StringComparison.Ordinal))
            {
                var document = JsonNode.Parse(await response.Content.ReadAsStringAsync(cancellationToken))!.AsObject();
                // Bait: a client that used the device-code flow would find this endpoint.
                document["device_authorization_endpoint"] = idp.Issuer.Issuer + "/devicecode";
                document["grant_types_supported"] = new JsonArray("authorization_code", "urn:ietf:params:oauth:grant-type:device_code");
                return Json(HttpStatusCode.OK, document.ToJsonString());
            }

            return response;
        }
    }
}

/// <summary>Acts as the operator's browser: visits the loopback callback on a real socket (no proxy).</summary>
internal sealed class ScriptedBrowser(CliTestIdp idp) : IBrowserLauncher, IDisposable
{
    private readonly HttpClient client = new(new SocketsHttpHandler { UseProxy = false, AllowAutoRedirect = false });

    public BrowserMode Mode { get; set; } = BrowserMode.Normal;

    public int Opened { get; private set; }

    public Uri? LastCallbackStatusUrl { get; private set; }

    public bool TryOpen(Uri url)
    {
        Opened++;
        if (Mode == BrowserMode.Silent)
        {
            return true;
        }

        var callback = idp.Authorize(url, Mode);
        _ = Task.Run(async () =>
        {
            if (Mode == BrowserMode.WrongStateFirst)
            {
                var forged = callback.AbsoluteUri.Replace("state=", "state=x", StringComparison.Ordinal);
                using var _ = await client.GetAsync(forged);
            }

            LastCallbackStatusUrl = callback;
            using var response = await client.GetAsync(callback);
        });
        return true;
    }

    public void Dispose() => client.Dispose();
}
