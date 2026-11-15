namespace Zaghlol.Api;

/// <summary>
/// The container <c>--healthcheck</c> (FU-017). It is a liveness check: exit 0 whenever the process answers HTTP, even with
/// 503 (database not ready), so an orchestrator doesn't restart a healthy API during a database outage. Readiness is
/// <c>GET /v1/health</c> itself, which load balancers use.
/// </summary>
internal static class HealthProbe
{
    private const string DefaultUrl = "http://127.0.0.1:8080/v1/health";

    public static async Task<int> RunAsync()
    {
        return await RunAsync(Environment.GetEnvironmentVariable("ZAGHLOL_HEALTHCHECK_URL"));
    }

    public static async Task<int> RunAsync(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            url = DefaultUrl;
        }

        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        try
        {
            using var response = await client.GetAsync(new Uri(url), HttpCompletionOption.ResponseHeadersRead);
            // Any HTTP answer means the process is alive; only 5xx other than the 503 "not ready" is a failure.
            return response.IsSuccessStatusCode || response.StatusCode == System.Net.HttpStatusCode.ServiceUnavailable ? 0 : 1;
        }
        catch (HttpRequestException)
        {
            return 1;
        }
        catch (OperationCanceledException)
        {
            return 1;
        }
    }
}
