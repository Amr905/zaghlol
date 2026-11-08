using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>A database on a fixed host port, so the container can be stopped and started under the running API.</summary>
public sealed class ReadinessFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private WebApplicationFactory<Program>? factory;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync(hostPort: FreeTcpPort());
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", Database.Api);
            builder.UseSetting("ConnectionStrings:Admin", Database.Admin);
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(kms.Use);
        });
        Client = factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        Client?.Dispose();
        if (factory is not null)
        {
            await factory.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }

        kms.Dispose();
    }

    private static int FreeTcpPort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }
}

/// <summary>FU-003: <c>GET /v1/health</c> is a readiness probe backed by the database.</summary>
[Collection(ApiHostGroup.Name)]
public class ReadinessTests(ReadinessFixture fixture) : IClassFixture<ReadinessFixture>
{
    private static readonly Uri Health = new("/v1/health", UriKind.Relative);

    [Fact]
    public async Task HealthIs503WhileTheDatabaseIsDownAnd200WithinFiveSecondsAfterItIsBack()
    {
        using (var before = await fixture.Client.GetAsync(Health))
        {
            Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        }

        await fixture.Database.Container.StopAsync();

        // The answer is cached for 2 s, so the 503 shows up within the cache window plus one probe.
        using (var down = await PollAsync(HttpStatusCode.ServiceUnavailable, TimeSpan.FromSeconds(15)))
        {
            Assert.Equal(HttpStatusCode.ServiceUnavailable, down.StatusCode);
            Assert.Equal("application/problem+json", down.Content.Headers.ContentType?.MediaType);
            Assert.True(down.Headers.CacheControl?.NoStore);
            using var body = JsonDocument.Parse(await down.Content.ReadAsStringAsync());
            Assert.Equal("UPSTREAM_UNAVAILABLE", body.RootElement.GetProperty("code").GetString());
            Assert.Equal(503, body.RootElement.GetProperty("status").GetInt32());
        }

        await fixture.Database.Container.StartAsync();
        var sinceStart = Stopwatch.StartNew();

        using var up = await PollAsync(HttpStatusCode.OK, TimeSpan.FromSeconds(5));
        Assert.Equal(HttpStatusCode.OK, up.StatusCode);
        Assert.True(sinceStart.Elapsed <= TimeSpan.FromSeconds(5), $"recovered after {sinceStart.Elapsed}");
    }

    private async Task<HttpResponseMessage> PollAsync(HttpStatusCode expected, TimeSpan budget)
    {
        var deadline = Stopwatch.StartNew();
        while (true)
        {
            var response = await fixture.Client.GetAsync(Health);
            if (response.StatusCode == expected || deadline.Elapsed >= budget)
            {
                return response;
            }

            response.Dispose();
            await Task.Delay(TimeSpan.FromMilliseconds(200));
        }
    }
}
