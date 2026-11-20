using System.Net;
using System.Net.Sockets;
using System.Text;
using Zaghlol.Ops.Auth;
using Zaghlol.Ops.Tests.Support;
using Zaghlol.Testing;

namespace Zaghlol.Ops.Tests;

/// <summary>R3-9: authorization code + PKCE over a loopback redirect, no device-code flow, against an in-process IdP.</summary>
public class OidcLoginTests
{
    [Fact]
    public async Task LoginUsesAuthorizationCodeWithPkceAndNeverTheDeviceCodeFlow()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);

        var code = await env.RunAsync("login");

        Assert.Equal(0, code);
        Assert.Equal(1, idp.Browser.Opened);
        Assert.Equal(1, idp.TokenRequests);
        Assert.Equal(["authorization_code"], idp.GrantTypes);
        Assert.DoesNotContain(idp.Requests, r => r.Contains("devicecode", StringComparison.OrdinalIgnoreCase) || r.Contains("device", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(idp.Requests, r => r.EndsWith("/.well-known/openid-configuration", StringComparison.Ordinal));
        Assert.Contains("code_challenge_method=S256", idp.AuthorizeUrl, StringComparison.Ordinal);
        Assert.DoesNotContain("device", idp.AuthorizeUrl, StringComparison.OrdinalIgnoreCase);
        Assert.NotNull(await env.Store.ReadAsync(OpsConfigFor(env).CacheKey(), CancellationToken.None));
    }

    [Fact]
    public async Task TheTokenIsNeverPrintedAndALaterRunReusesTheStoredOne()
    {
        using var idp = new CliTestIdp("sub-reuse");
        using var env = new TestEnvironment(null, idp);
        Assert.Equal(0, await env.RunAsync("login"));
        var token = (await env.Store.ReadAsync(OpsConfigFor(env).CacheKey(), CancellationToken.None))!.Split('.', 3)[2];

        var code = await env.RunAsync("status");

        Assert.Equal(0, code);
        Assert.Equal(1, idp.TokenRequests);
        Assert.Contains("\"signedIn\": true", env.Output.ToString(), StringComparison.Ordinal);
        Assert.Contains("sub-reuse", env.Output.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(token, env.AllOutput, StringComparison.Ordinal);
        Assert.DoesNotContain(token[..40], env.AllOutput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnExpiredStoredTokenIsDroppedAndNotUsed()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);
        var key = OpsConfigFor(env).CacheKey();
        var old = idp.Issuer.Mint(new OperatorTokenSpec { Subject = "sub-old", IssuedAt = DateTimeOffset.UtcNow.AddHours(-3), LifetimeSeconds = 3600 }, DateTimeOffset.UtcNow);
        var expired = new TokenSet(old, DateTimeOffset.UtcNow.AddHours(-2), "sub-old");
        await env.Store.WriteAsync(key, expired.Serialize(), CancellationToken.None);

        var code = await env.RunAsync("status");

        Assert.Equal(0, code);
        Assert.Contains("\"signedIn\": false", env.Output.ToString(), StringComparison.Ordinal);
        Assert.Null(await env.Store.ReadAsync(key, CancellationToken.None));
        Assert.Equal(0, idp.TokenRequests);
    }

    [Fact]
    public async Task ATokenInsideTheExpiryMarginIsNotUsed()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);
        var key = OpsConfigFor(env).CacheKey();
        var nearly = idp.Issuer.Mint(new OperatorTokenSpec { Subject = "sub-near" }, DateTimeOffset.UtcNow);
        await env.Store.WriteAsync(key, new TokenSet(nearly, DateTimeOffset.UtcNow.AddSeconds(30), "sub-near").Serialize(), CancellationToken.None);

        await env.RunAsync("status");

        Assert.Contains("\"signedIn\": false", env.Output.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ALocalAttackerHittingTheCallbackWithAWrongStateIsIgnored()
    {
        using var idp = new CliTestIdp();
        idp.Browser.Mode = BrowserMode.WrongStateFirst;
        using var env = new TestEnvironment(null, idp);

        var code = await env.RunAsync("login");

        Assert.Equal(0, code);
        Assert.Equal(1, idp.TokenRequests);
    }

    [Fact]
    public async Task AnIdpErrorEndsTheLoginAndItsDescriptionIsNeverShown()
    {
        using var idp = new CliTestIdp();
        idp.Browser.Mode = BrowserMode.Denied;
        using var env = new TestEnvironment(null, idp);

        var code = await env.RunAsync("login");

        Assert.Equal(3, code);
        Assert.Contains("access_denied", env.Error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("Secret IdP text", env.AllOutput, StringComparison.Ordinal);
        Assert.Equal(0, idp.TokenRequests);
    }

    [Fact]
    public async Task ARefusedCodeIsALoginFailure()
    {
        using var idp = new CliTestIdp();
        idp.Browser.Mode = BrowserMode.UnknownCode;
        using var env = new TestEnvironment(null, idp);

        Assert.Equal(3, await env.RunAsync("login"));
        Assert.Contains("refused the code", env.Error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("not-a-known-code", env.AllOutput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AFailedPkceCheckAtTheIdpIsALoginFailure()
    {
        using var idp = new CliTestIdp { FailPkce = true };
        using var env = new TestEnvironment(null, idp);

        Assert.Equal(3, await env.RunAsync("login"));
    }

    [Fact]
    public async Task ADiscoveryDocumentForAnotherIssuerIsRefused()
    {
        using var idp = new CliTestIdp();
        idp.Issuer.AnnouncedIssuer = "https://login.evil.test/x/v2.0";
        using var env = new TestEnvironment(null, idp);

        Assert.Equal(3, await env.RunAsync("login"));
        Assert.Equal(0, idp.Browser.Opened);
        Assert.Contains("different issuer", env.Error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnIdTokenForAnotherNonceIsRefused()
    {
        using var idp = new CliTestIdp { NonceOverride = "another-request-nonce" };
        using var env = new TestEnvironment(null, idp);

        Assert.Equal(3, await env.RunAsync("login"));
        Assert.Contains("nonce", env.Error.ToString(), StringComparison.Ordinal);
        Assert.Null(await env.Store.ReadAsync(OpsConfigFor(env).CacheKey(), CancellationToken.None));
    }

    [Fact]
    public async Task AnAlreadyExpiredTokenIsRefused()
    {
        using var idp = new CliTestIdp { LifetimeSeconds = 1 };
        using var env = new TestEnvironment(null, idp);
        idp.LifetimeSeconds = -100;

        Assert.Equal(3, await env.RunAsync("login"));
        Assert.Null(await env.Store.ReadAsync(OpsConfigFor(env).CacheKey(), CancellationToken.None));
    }

    [Fact]
    public async Task TheRedirectHostCanBeTheIpLiteral()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);
        env.Variables["ZAGHLOL_OPS_REDIRECT_HOST"] = "127.0.0.1";

        Assert.Equal(0, await env.RunAsync("login"));
        Assert.Matches("redirect_uri=http%3A%2F%2F127\\.0\\.0\\.1%3A[0-9]+%2Fcallback", idp.AuthorizeUrl);
    }

    [Fact]
    public async Task AccessTokenUseWorksWhenTheIdpIssuesAJwtAccessToken()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);
        env.Variables["ZAGHLOL_OPS_TOKEN_USE"] = "access_token";

        Assert.Equal(0, await env.RunAsync("login"));
    }

    [Fact]
    public async Task NoBrowserPrintsTheUrlAndWaitsForTheOperatorToOpenIt()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);

        var run = env.RunAsync("login", "--no-browser");
        for (var i = 0; i < 200 && !env.Error.ToString().Contains("https://", StringComparison.Ordinal); i++)
        {
            await Task.Delay(25);
        }

        var url = env.Error.ToString().Split('\n').First(l => l.StartsWith("https://", StringComparison.Ordinal)).Trim();
        Assert.Equal(0, idp.Browser.Opened);
        idp.Browser.Mode = BrowserMode.Normal;
        idp.Browser.TryOpen(new Uri(url));

        Assert.Equal(0, await run);
    }

    [Fact]
    public async Task LogoutRemovesTheStoredToken()
    {
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(null, idp);
        await env.RunAsync("login");

        Assert.Equal(0, await env.RunAsync("logout"));

        Assert.Null(await env.Store.ReadAsync(OpsConfigFor(env).CacheKey(), CancellationToken.None));
    }

    [Fact]
    public void TheCallbackParserAcceptsOnlyTheExactRequestShapeAndState()
    {
        Assert.Equal("c1", LoopbackReceiver.Parse("GET /callback?code=c1&state=S HTTP/1.1\r\nHost: x\r\n\r\n", "S")!.Code);
        Assert.Equal("access_denied", LoopbackReceiver.Parse("GET /callback?error=access_denied&state=S HTTP/1.1\r\n\r\n", "S")!.Error);
        Assert.Equal("error", LoopbackReceiver.Parse("GET /callback?error=Bad%20Text&state=S HTTP/1.1\r\n\r\n", "S")!.Error);
        Assert.Null(LoopbackReceiver.Parse("GET /callback?code=c1&state=T HTTP/1.1\r\n\r\n", "S"));
        Assert.Null(LoopbackReceiver.Parse("GET /callback?code=c1 HTTP/1.1\r\n\r\n", "S"));
        Assert.Null(LoopbackReceiver.Parse("GET /other?code=c1&state=S HTTP/1.1\r\n\r\n", "S"));
        Assert.Null(LoopbackReceiver.Parse("POST /callback?code=c1&state=S HTTP/1.1\r\n\r\n", "S"));
        Assert.Null(LoopbackReceiver.Parse("GET /callback?code=&state=S HTTP/1.1\r\n\r\n", "S"));
        Assert.Null(LoopbackReceiver.Parse(null, "S"));
    }

    [Fact]
    public async Task TheReceiverSurvivesJunkConnectionsAndAnswersOnlyTheValidCallback()
    {
        using var receiver = new LoopbackReceiver();
        var wait = receiver.WaitAsync("STATE", TimeSpan.FromSeconds(20), CancellationToken.None);

        using (var junk = new TcpClient())
        {
            await junk.ConnectAsync(IPAddress.Loopback, receiver.Port);
            await junk.GetStream().WriteAsync(new byte[LoopbackReceiver.MaxHeadBytes + 100].Select(_ => (byte)'a').ToArray());
        }

        using var http = new HttpClient(new SocketsHttpHandler { UseProxy = false });
        using var favicon = await http.GetAsync(new Uri($"http://127.0.0.1:{receiver.Port}/favicon.ico"));
        using var forged = await http.GetAsync(new Uri($"http://127.0.0.1:{receiver.Port}/callback?code=evil&state=NOPE"));
        Assert.Equal(HttpStatusCode.NotFound, favicon.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, forged.StatusCode);
        Assert.False(wait.IsCompleted);

        using var good = await http.GetAsync(new Uri($"http://127.0.0.1:{receiver.Port}/callback?code=good&state=STATE"));
        var result = await wait;

        Assert.Equal(HttpStatusCode.OK, good.StatusCode);
        Assert.Equal("good", result.Code);
        Assert.Equal("no-store", good.Headers.CacheControl?.ToString());
        var page = await good.Content.ReadAsStringAsync();
        Assert.DoesNotContain("good", page, StringComparison.Ordinal);
    }

    [Fact]
    public async Task TheReceiverListensOnLoopbackOnly()
    {
        using var receiver = new LoopbackReceiver();

        var local = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces()
            .SelectMany(n => n.GetIPProperties().UnicastAddresses.Select(u => u.Address))
            .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a));
        if (local is not null)
        {
            using var client = new TcpClient();
            await Assert.ThrowsAnyAsync<SocketException>(async () => await client.ConnectAsync(local, receiver.Port).WaitAsync(TimeSpan.FromSeconds(5)));
        }

        using var loopback = new TcpClient();
        await loopback.ConnectAsync(IPAddress.Loopback, receiver.Port);
        Assert.True(loopback.Connected);
    }

    [Fact]
    public async Task TheReceiverEndsAtItsDeadline()
    {
        using var receiver = new LoopbackReceiver();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => receiver.WaitAsync("S", TimeSpan.FromMilliseconds(200), CancellationToken.None));
    }

    private static OpsConfig OpsConfigFor(TestEnvironment env) =>
        OpsConfig.Load(name => env.Variables.GetValueOrDefault(name), null, _ => null, null);
}
