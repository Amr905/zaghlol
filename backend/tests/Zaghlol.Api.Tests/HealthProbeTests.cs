using System.Net;
using System.Net.Sockets;

namespace Zaghlol.Api.Tests;

/// <summary>FU-017: the container healthcheck is liveness only; a database outage (503) must not make it fail.</summary>
public class HealthProbeTests
{
    [Theory]
    [InlineData(200, 0)]
    [InlineData(503, 0)]
    [InlineData(500, 1)]
    [InlineData(404, 1)]
    public async Task OnlyAnAnsweringProcessIsAlive(int status, int expectedExit)
    {
        var port = FreePort();
        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        var serve = Task.Run(async () =>
        {
            var context = await listener.GetContextAsync();
            context.Response.StatusCode = status;
            context.Response.Close();
        });

        Assert.Equal(expectedExit, await HealthProbe.RunAsync($"http://127.0.0.1:{port}/v1/health"));
        await serve;
    }

    [Fact]
    public async Task NothingListeningFailsTheProbe()
    {
        Assert.Equal(1, await HealthProbe.RunAsync($"http://127.0.0.1:{FreePort()}/v1/health"));
    }

    private static int FreePort()
    {
        using var socket = new TcpListener(IPAddress.Loopback, 0);
        socket.Start();
        return ((IPEndPoint)socket.LocalEndpoint).Port;
    }
}
