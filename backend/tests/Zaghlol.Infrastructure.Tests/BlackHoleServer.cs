using System.Net;
using System.Net.Sockets;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>A TCP server on loopback that accepts connections and never answers; counts accepted connections.</summary>
public sealed class BlackHoleServer : IDisposable
{
    private readonly TcpListener listener = new(IPAddress.Loopback, 0);
    private readonly List<TcpClient> accepted = [];
    private readonly CancellationTokenSource stop = new();
    private readonly Task acceptLoop;
    private int connections;

    public BlackHoleServer()
    {
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        acceptLoop = Task.Run(AcceptAsync);
    }

    public int Port { get; }

    public int Connections => Volatile.Read(ref connections);

    public void Dispose()
    {
        stop.Cancel();
        listener.Stop();
        try
        {
            acceptLoop.Wait(TimeSpan.FromSeconds(5));
        }
        catch (AggregateException)
        {
            // the loop ends with the listener
        }

        lock (accepted)
        {
            accepted.ForEach(c => c.Dispose());
        }

        listener.Dispose();
        stop.Dispose();
    }

    private async Task AcceptAsync()
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                var client = await listener.AcceptTcpClientAsync(stop.Token);
                lock (accepted)
                {
                    accepted.Add(client);
                }

                Interlocked.Increment(ref connections);
            }
            catch (Exception ex) when (ex is OperationCanceledException or SocketException or ObjectDisposedException)
            {
                break;
            }
        }
    }
}
