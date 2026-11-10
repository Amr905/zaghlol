using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Auth;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>
/// T-136 design note §4: outside Development and Testing every incomplete operator-auth configuration stops the host (never a
/// silent reject-all); Development and Testing start and fall back to reject-all.
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class OperatorAuthStartupCheckTests : IDisposable
{
    private readonly FakeOidcIssuer issuer = new();

    public void Dispose() => issuer.Dispose();

    public static TheoryData<string> BadConfigurations => new()
    {
        "disabled", "http_issuer", "issuer_with_query", "no_audience", "hs256_algorithm", "enforced_without_acrs",
        "enforced_on_google", "lifetime_over_an_hour", "idp_unreachable", "idp_issuer_mismatch", "test_issuer",
    };

    [Theory]
    [MemberData(nameof(BadConfigurations))]
    public async Task ProductionRefusesToStart(string configuration)
    {
        var settings = Valid();
        switch (configuration)
        {
            case "disabled":
                settings["OperatorAuth:Enabled"] = "false";
                break;
            case "http_issuer":
                settings["OperatorAuth:Issuer"] = "http://login.zaghlol.test/tenant-1/v2.0";
                break;
            case "issuer_with_query":
                settings["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer + "?x=1";
                break;
            case "no_audience":
                settings.Remove("OperatorAuth:Audiences:0");
                break;
            case "hs256_algorithm":
                settings["OperatorAuth:Algorithms:0"] = "HS256";
                break;
            case "enforced_without_acrs":
                settings["OperatorAuth:PhishingResistantMode"] = "Enforced";
                break;
            case "enforced_on_google":
                settings["OperatorAuth:PhishingResistantMode"] = "Enforced";
                settings["OperatorAuth:Profile"] = "Google";
                settings["OperatorAuth:RequiredAcrs"] = "c1";
                break;
            case "lifetime_over_an_hour":
                settings["OperatorAuth:MaxLifetimeSeconds"] = "7200";
                break;
            case "idp_unreachable":
                issuer.Failing = true;
                break;
            case "idp_issuer_mismatch":
                issuer.AnnouncedIssuer = "https://login.zaghlol.test/other/v2.0";
                break;
            default:
                settings["OperatorAuth:TestIssuer:Enabled"] = "true";
                break;
        }

        await using var app = Build("Production", settings);

        await Assert.ThrowsAsync<OperatorAuthConfigurationException>(() => app.StartAsync());
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public async Task ACompleteConfigurationStartsAndLoadsTheKeysAtBoot(string environment)
    {
        await using var app = Build(environment, Valid());

        await app.StartAsync();
        await app.StopAsync();

        Assert.Equal(1, issuer.JwksRequests);
        Assert.IsType<OidcOperatorTokenValidator>(app.Services.GetRequiredService<IOperatorTokenValidator>());
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    public async Task DevelopmentAndTestingStartWithoutOperatorAuthAndRejectEveryone(string environment)
    {
        await using var app = Build(environment, new Dictionary<string, string?> { ["OperatorAuth:TestIssuer:Enabled"] = "true" });

        await app.StartAsync();
        await app.StopAsync();

        Assert.IsType<RejectAllOperatorTokenValidator>(app.Services.GetRequiredService<IOperatorTokenValidator>());
    }

    [Fact]
    public async Task AnEnabledButInvalidConfigurationInDevelopmentStaysRejectAll()
    {
        var settings = Valid();
        settings["OperatorAuth:Issuer"] = "http://insecure.example";
        await using var app = Build("Development", settings);

        await app.StartAsync();
        await app.StopAsync();

        Assert.IsType<RejectAllOperatorTokenValidator>(app.Services.GetRequiredService<IOperatorTokenValidator>());
    }

    private static Dictionary<string, string?> Valid() => new(StringComparer.Ordinal)
    {
        ["OperatorAuth:Enabled"] = "true",
        ["OperatorAuth:Profile"] = "Entra",
        ["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer,
        ["OperatorAuth:Audiences:0"] = FakeOidcIssuer.CliAudience,
    };

    private WebApplication Build(string environment, Dictionary<string, string?> settings)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = environment });
        builder.WebHost.UseTestServer();
        builder.Configuration.AddInMemoryCollection(settings);
        builder.Services.AddSingleton(new Infrastructure.Observability.ZaghlolMetrics());
        builder.Services.AddOperatorAuthentication();
        builder.Services.AddZaghlolOperatorAuth();
        builder.Services.AddSingleton<Application.Operators.IOperatorDirectory>(new FakeOperatorDirectory());
        builder.Services.AddHttpClient(OidcKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => issuer.CreateHandler());
        return builder.Build();
    }
}
