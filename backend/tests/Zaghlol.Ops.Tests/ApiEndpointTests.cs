using Zaghlol.Ops.Api;

namespace Zaghlol.Ops.Tests;

/// <summary>FU-264 F6: the path of <c>apiUrl</c> is kept when the CLI builds a request URL.</summary>
public class ApiEndpointTests
{
    [Theory]
    [InlineData("https://host/", "/admin/v1/flags/x", "https://host/admin/v1/flags/x")]
    [InlineData("https://host", "/admin/v1/flags/x", "https://host/admin/v1/flags/x")]
    [InlineData("https://host/api/", "/admin/v1/flags/x", "https://host/api/admin/v1/flags/x")]
    [InlineData("https://host/api", "/admin/v1/bank-requests", "https://host/api/admin/v1/bank-requests")]
    [InlineData("https://host/api/", "/admin/v1/metrics/daily-active?days=7", "https://host/api/admin/v1/metrics/daily-active?days=7")]
    public void TheBasePathIsKeptAndTheOriginNeverChanges(string baseUrl, string path, string expected)
    {
        var uri = AdminApiClient.Endpoint(new Uri(baseUrl), path);

        Assert.Equal(expected, uri.AbsoluteUri);
    }

    [Fact]
    public void APathThatLooksLikeAnotherHostStaysOnTheBase()
    {
        var uri = AdminApiClient.Endpoint(new Uri("https://host/api/"), "//evil.example/x");

        Assert.Equal("host", uri.Host);
    }
}
