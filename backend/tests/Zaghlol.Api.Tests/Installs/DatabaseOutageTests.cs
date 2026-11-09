using System.Net;
using Zaghlol.Api.Auth;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>
/// T-124 deviation D3 (code review minor 3): with the database unreachable (connection refused, a transient
/// <c>DbException</c>), registration and an authenticated call answer <c>503 UPSTREAM_UNAVAILABLE</c>, never 500, and the body
/// carries no driver text.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class DatabaseOutageTests(RateLimitHostFixture fixture) : IClassFixture<RateLimitHostFixture>
{
    [Fact]
    public async Task RegistrationAnswers503UpstreamUnavailableWithoutDriverText()
    {
        using var response = await fixture.RegisterAsync(
            InstallsHostFixture.InstallBody(InstallsHostFixture.NewInstallId()), InstallsHostFixture.NewKey(), "198.18.40.1");

        var text = await Problems.AssertAsync(response, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE");
        AssertNoDriverText(text);
    }

    [Fact]
    public async Task AnAuthenticatedCallAnswers503UpstreamUnavailableWithoutDriverText()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/t/whoami");
        request.Headers.Add(InstallsHostFixture.PeerHeader, "198.18.41.1");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + InstallTokens.Generate());

        using var response = await fixture.Client.SendAsync(request);

        var text = await Problems.AssertAsync(response, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE");
        AssertNoDriverText(text);
    }

    private static void AssertNoDriverText(string body)
    {
        foreach (var fragment in new[] { "Npgsql", "127.0.0.1", "Failed to connect", "refused", "Exception", "   at " })
        {
            Assert.DoesNotContain(fragment, body, StringComparison.OrdinalIgnoreCase);
        }
    }
}
