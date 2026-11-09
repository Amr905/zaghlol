using System.Net;
using System.Text.Json;
using Zaghlol.Api.RateLimiting;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>
/// T-124 rate limits on <see cref="RateLimitHostFixture"/> (per network 5 an hour, registration 3 an hour). Every test uses
/// its own documentation /24, so the buckets don't leak between tests.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class RateLimitTests(RateLimitHostFixture fixture) : IClassFixture<RateLimitHostFixture>
{
    [Fact]
    public async Task TheSixthRequestFromOneNetworkIs429WithRetryAfter()
    {
        for (var i = 0; i < 5; i++)
        {
            using var allowed = await Ping("198.51.100.10");
            Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        }

        using var limited = await Ping("198.51.100.10");

        var text = await Problems.AssertAsync(limited, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        var retryAfter = limited.Headers.RetryAfter?.Delta;
        Assert.NotNull(retryAfter);
        Assert.InRange(retryAfter.Value, TimeSpan.FromSeconds(1), TimeSpan.FromHours(1));
        using var json = JsonDocument.Parse(text);
        Assert.Equal((int)retryAfter.Value.TotalSeconds, json.RootElement.GetProperty("retryAfterSeconds").GetInt32());
        Assert.DoesNotContain("198.51.100", text, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AddressesInOneSlash24ShareABucketAndOtherNetworksDoNot()
    {
        for (var i = 0; i < 5; i++)
        {
            using var allowed = await Ping(i % 2 == 0 ? "192.0.2.1" : "192.0.2.200");
            Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        }

        using var sameNetwork = await Ping("192.0.2.77");
        using var nextNetwork = await Ping("192.0.3.1");
        using var ipv6 = await Ping("2001:db8:1:200::1");

        Assert.Equal(HttpStatusCode.TooManyRequests, sameNetwork.StatusCode);
        Assert.Equal(HttpStatusCode.OK, nextNetwork.StatusCode);
        Assert.Equal(HttpStatusCode.OK, ipv6.StatusCode);
    }

    [Fact]
    public async Task AForgedForwardedForFromAnUntrustedPeerIsIgnored()
    {
        for (var i = 0; i < 5; i++)
        {
            using var allowed = await Ping("203.0.113.7", forwardedFor: $"100.64.{i}.1");
            Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        }

        using var limited = await Ping("203.0.113.7", forwardedFor: "100.64.99.1");

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
    }

    [Fact]
    public async Task TheTrustedProxysForwardedForPicksTheClientNetwork()
    {
        for (var i = 0; i < 5; i++)
        {
            using var allowed = await Ping(InstallsHostFixture.TrustedProxy, forwardedFor: "100.65.1." + (i + 1));
            Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        }

        using var limited = await Ping(InstallsHostFixture.TrustedProxy, forwardedFor: "100.65.1.50");
        using var otherClient = await Ping(InstallsHostFixture.TrustedProxy, forwardedFor: "100.65.2.1");

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(HttpStatusCode.OK, otherClient.StatusCode);
    }

    [Fact]
    public async Task RegistrationHasItsOwnSmallerBucket()
    {
        const string Peer = "198.18.7.9";
        for (var i = 0; i < 3; i++)
        {
            // Invalid bodies still draw on the bucket: the limiter runs before the handler.
            using var counted = await fixture.RegisterAsync("{}", InstallsHostFixture.NewKey(), Peer);
            Assert.Equal(HttpStatusCode.BadRequest, counted.StatusCode);
        }

        using var limited = await fixture.RegisterAsync("{}", InstallsHostFixture.NewKey(), Peer);
        using var ping = await Ping(Peer);

        await Problems.AssertAsync(limited, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        Assert.Equal(HttpStatusCode.OK, ping.StatusCode);
    }

    [Theory]
    [InlineData("198.51.100.1", "198.51.100.0/24")]
    [InlineData("198.51.100.255", "198.51.100.0/24")]
    [InlineData("::ffff:198.51.100.9", "198.51.100.0/24")]
    [InlineData("2001:db8:aa:bbcc:1:2:3:4", "2001:db8:aa:bb00::/56")]
    public void TheNetworkKeyIsTheSlash24OrSlash56(string address, string expected)
    {
        Assert.Equal(expected, ClientNetwork.Of(IPAddress.Parse(address)));
    }

    [Fact]
    public void TheDefaultsAreTheDesignNotesProposal()
    {
        var defaults = new RateLimitSettings();

        Assert.Equal((600, 600, 60), (defaults.PerNetwork.TokenLimit, defaults.PerNetwork.TokensPerPeriod, defaults.PerNetwork.PeriodSeconds));
        Assert.Equal((60, 60, 3600), (defaults.Register.TokenLimit, defaults.Register.TokensPerPeriod, defaults.Register.PeriodSeconds));
        Assert.Equal((30, 10, 60), (defaults.PerToken.TokenLimit, defaults.PerToken.TokensPerPeriod, defaults.PerToken.PeriodSeconds));
    }

    private async Task<HttpResponseMessage> Ping(string peer, string? forwardedFor = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/t/ping");
        request.Headers.Add(InstallsHostFixture.PeerHeader, peer);
        if (forwardedFor is not null)
        {
            request.Headers.Add("X-Forwarded-For", forwardedFor);
        }

        return await fixture.Client.SendAsync(request);
    }
}
