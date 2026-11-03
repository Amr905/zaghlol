namespace Zaghlol.Api;

internal static class HealthProbe
{
    private const string DefaultUrl = "http://127.0.0.1:8080/v1/health";

    public static async Task<int> RunAsync()
    {
        var url = Environment.GetEnvironmentVariable("ZAGHLOL_HEALTHCHECK_URL");
        if (string.IsNullOrWhiteSpace(url))
        {
            url = DefaultUrl;
        }

        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        try
        {
            using var response = await client.GetAsync(new Uri(url));
            return response.IsSuccessStatusCode ? 0 : 1;
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
