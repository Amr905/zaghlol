using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Zaghlol.Api.RateLimiting;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>
/// T-124 security S-1: outside Development and Testing the host refuses to start unless a trusted proxy list or the explicit
/// <c>ForwardedHeaders:NoProxy=true</c> flag is configured, so a missing setting can't silently put every client in the
/// load balancer's /24.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class ForwardedHeadersStartupCheckTests
{
    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public async Task WithoutAProxyListOrTheNoProxyFlagTheHostRefusesToStart(string environment)
    {
        await using var app = Build(environment, []);

        var error = await Assert.ThrowsAsync<ForwardedHeadersConfigurationException>(() => app.StartAsync());

        Assert.Equal(ForwardedHeadersConfigurationException.DefaultMessage, error.Message);
    }

    [Fact]
    public async Task AFalseNoProxyFlagStillRefusesToStart()
    {
        await using var app = Build("Production", [("ForwardedHeaders:NoProxy", "false")]);

        await Assert.ThrowsAsync<ForwardedHeadersConfigurationException>(() => app.StartAsync());
    }

    [Theory]
    [InlineData("ForwardedHeaders:KnownProxies:0", "10.0.0.5")]
    [InlineData("ForwardedHeaders:KnownNetworks:0", "10.0.0.0/16")]
    [InlineData("ForwardedHeaders:NoProxy", "true")]
    public async Task AProxyListOrTheExplicitNoProxyFlagLetsProductionStart(string key, string value)
    {
        await using var app = Build("Production", [(key, value)]);

        await app.StartAsync();
        await app.StopAsync();
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    public async Task DevelopmentAndTestingStartWithoutTheSetting(string environment)
    {
        await using var app = Build(environment, []);

        await app.StartAsync();
        await app.StopAsync();
    }

    private static WebApplication Build(string environment, (string Key, string Value)[] settings)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = environment });
        builder.WebHost.UseTestServer();
        builder.Configuration.AddInMemoryCollection(settings.Select(s => new KeyValuePair<string, string?>(s.Key, s.Value)));
        builder.Services.AddZaghlolRateLimits();
        return builder.Build();
    }
}
