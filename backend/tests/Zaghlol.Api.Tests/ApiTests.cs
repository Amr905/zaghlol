using System.Net;
using System.Text;
using System.Text.Json;
using Npgsql;

namespace Zaghlol.Api.Tests;

[Collection(ApiHostGroup.Name)]
public class ApiTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    private static readonly string[] StackTraceMarkers = ["   at ", "StackTrace", "InvalidOperationException"];

    [Fact]
    public async Task PostgresContainerIsVersion17()
    {
        await using var connection = new NpgsqlConnection(fixture.PostgresConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SHOW server_version", connection);

        var version = (string?)await command.ExecuteScalarAsync();

        Assert.NotNull(version);
        Assert.StartsWith("17", version, StringComparison.Ordinal);
    }

    [Fact]
    public async Task HealthReturns200WithStatusOkAndServerTime()
    {
        var before = DateTimeOffset.UtcNow.AddMinutes(-5);

        using var response = await fixture.Client.GetAsync(new Uri("/v1/health", UriKind.Relative));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("ok", json.RootElement.GetProperty("status").GetString());
        var serverTime = json.RootElement.GetProperty("serverTime").GetDateTimeOffset();
        Assert.InRange(serverTime, before, DateTimeOffset.UtcNow.AddMinutes(5));
        Assert.Equal(TimeSpan.Zero, serverTime.Offset);
        Assert.EndsWith("Z", json.RootElement.GetProperty("serverTime").GetString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task UnknownRouteReturnsProblemDetailsWithStableCode()
    {
        using var response = await fixture.Client.GetAsync(new Uri("/v1/does-not-exist", UriKind.Relative));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(404, json.RootElement.GetProperty("status").GetInt32());
        Assert.Equal("NOT_FOUND", json.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task UnhandledExceptionReturns500InternalWithoutLeakingDetails()
    {
        using var response = await fixture.Client.GetAsync(new Uri("/test/boom", UriKind.Relative));

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        Assert.Equal("INTERNAL", json.RootElement.GetProperty("code").GetString());
        Assert.True(json.RootElement.TryGetProperty("correlationId", out _));
        Assert.DoesNotContain(FaultInjectionStartupFilter.Secret, body, StringComparison.Ordinal);
        foreach (var marker in StackTraceMarkers)
        {
            Assert.DoesNotContain(marker, body, StringComparison.Ordinal);
        }
    }

    [Fact]
    public async Task BadHttpRequestMapsTo400ValidationFailedWithoutEchoingMessage()
    {
        using var response = await fixture.Client.GetAsync(new Uri("/test/bad-request", UriKind.Relative));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        Assert.Equal("VALIDATION_FAILED", json.RootElement.GetProperty("code").GetString());
        Assert.DoesNotContain(FaultInjectionStartupFilter.Secret, body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RequestBodiesAreNeverLogged()
    {
        const string secretBody = "{\"purchaseToken\":\"super-secret-body-value\"}";
        using var content = new StringContent(secretBody, Encoding.UTF8, "application/json");

        using var response = await fixture.Client.PostAsync(new Uri("/v1/health", UriKind.Relative), content);

        Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);

        // The request-completion event is written after the response is sent: wait for this request's own entry.
        static bool ThisRequest(string e) =>
            e.Contains("RequestMethod=\"POST\"", StringComparison.Ordinal)
            && e.Contains("RequestPath=\"/v1/health\"", StringComparison.Ordinal);
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (!fixture.LogSink.Entries.Any(ThisRequest) && DateTime.UtcNow < deadline)
        {
            await Task.Delay(50);
        }

        Assert.Contains(fixture.LogSink.Entries, ThisRequest);
        Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains("super-secret-body-value", StringComparison.Ordinal));
    }
}
