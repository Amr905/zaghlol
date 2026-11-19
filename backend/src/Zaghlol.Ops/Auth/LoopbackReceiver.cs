using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace Zaghlol.Ops.Auth;

/// <summary>What the IdP sent to the loopback redirect.</summary>
internal sealed record CallbackResult(string? Code, string? Error);

/// <summary>
/// The loopback redirect receiver (RFC 8252 section 7.3): a raw TCP listener on the loopback addresses only, with an OS-chosen
/// port, that answers <c>GET /callback</c> once with the right <c>state</c>. It reads at most <see cref="MaxHeadBytes"/> of a
/// request, gives each connection <see cref="ReadTimeout"/>, ignores anything else, and has an overall deadline.
/// </summary>
internal sealed partial class LoopbackReceiver : IDisposable
{
    public const int MaxHeadBytes = 8 * 1024;

    public static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(5);

    private readonly List<TcpListener> listeners = [];

    public LoopbackReceiver()
    {
        var v4 = new TcpListener(IPAddress.Loopback, 0);
        v4.Start();
        listeners.Add(v4);
        Port = ((IPEndPoint)v4.LocalEndpoint).Port;
        try
        {
            // `localhost` can resolve to ::1 first; the same port on IPv6 is best effort.
            var v6 = new TcpListener(IPAddress.IPv6Loopback, Port);
            v6.Start();
            listeners.Add(v6);
        }
        catch (SocketException)
        {
            // No IPv6 loopback or the port is taken there: IPv4 alone is enough for 127.0.0.1 and for browsers that fall back.
        }
    }

    public int Port { get; }

    public async Task<CallbackResult> WaitAsync(string expectedState, TimeSpan deadline, CancellationToken cancellationToken)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(deadline);
        var loops = listeners.Select(l => AcceptLoopAsync(l, expectedState, cts.Token)).ToList();
        try
        {
            var first = await Task.WhenAny(loops).ConfigureAwait(false);
            return await first.ConfigureAwait(false);
        }
        finally
        {
            await cts.CancelAsync().ConfigureAwait(false);
            foreach (var loop in loops)
            {
                try
                {
                    await loop.ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    // The loser of the race ends by cancellation.
                }
            }
        }
    }

    public void Dispose()
    {
        foreach (var listener in listeners)
        {
            listener.Stop();
        }
    }

    private static async Task<CallbackResult> AcceptLoopAsync(TcpListener listener, string expectedState, CancellationToken cancellationToken)
    {
        while (true)
        {
            using var client = await listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
            var stream = client.GetStream();
            string? head;
            using (var read = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
            {
                read.CancelAfter(ReadTimeout);
                try
                {
                    head = await ReadHeadAsync(stream, read.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    continue;
                }
                catch (IOException)
                {
                    continue;
                }
            }

            var result = Parse(head, expectedState);
            await RespondAsync(stream, result is not null, cancellationToken).ConfigureAwait(false);
            if (result is not null)
            {
                return result;
            }
        }
    }

    private static async Task<string?> ReadHeadAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var buffer = new byte[MaxHeadBytes];
        var length = 0;
        while (length < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(length), cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            length += read;
            if (Encoding.ASCII.GetString(buffer, 0, length).Contains("\r\n\r\n", StringComparison.Ordinal))
            {
                return Encoding.ASCII.GetString(buffer, 0, length);
            }
        }

        return null;
    }

    /// <summary>The callback's <c>code</c> or <c>error</c> when it is <c>GET /callback</c> with exactly the expected state; else null.</summary>
    internal static CallbackResult? Parse(string? head, string expectedState)
    {
        var line = head?.Split("\r\n", 2)[0];
        var match = line is null ? null : RequestLine().Match(line);
        if (match is not { Success: true })
        {
            return null;
        }

        string? code = null;
        string? error = null;
        string? state = null;
        foreach (var pair in match.Groups["query"].Value.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = pair.IndexOf('=', StringComparison.Ordinal);
            if (eq <= 0)
            {
                continue;
            }

            var name = pair[..eq];
            var value = Uri.UnescapeDataString(pair[(eq + 1)..].Replace('+', ' '));
            switch (name)
            {
                case "code":
                    code = value;
                    break;
                case "error":
                    error = value;
                    break;
                case "state":
                    state = value;
                    break;
            }
        }

        if (!string.Equals(state, expectedState, StringComparison.Ordinal))
        {
            return null;
        }

        // The IdP's error description is never read; the code is reduced to a fixed character set.
        if (error is not null)
        {
            return new CallbackResult(null, ErrorCode().IsMatch(error) ? error : "error");
        }

        return code is { Length: > 0 and <= 2048 } ? new CallbackResult(code, null) : null;
    }

    private static async Task RespondAsync(NetworkStream stream, bool ok, CancellationToken cancellationToken)
    {
        var body = ok
            ? "<!doctype html><meta charset=utf-8><title>zaghlol-ops</title><p>Signed in. You can close this tab and return to the terminal."
            : string.Empty;
        var head = ok ? "HTTP/1.1 200 OK" : "HTTP/1.1 404 Not Found";
        var text = head + "\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: "
            + Encoding.UTF8.GetByteCount(body).ToString(System.Globalization.CultureInfo.InvariantCulture) + "\r\n\r\n" + body;
        try
        {
            await stream.WriteAsync(Encoding.UTF8.GetBytes(text), cancellationToken).ConfigureAwait(false);
        }
        catch (IOException)
        {
            // The browser went away; the result stands.
        }
    }

    [GeneratedRegex(@"^GET /callback\?(?<query>[^ ]{0,4096}) HTTP/1\.[01]$", RegexOptions.CultureInvariant, 1000)]
    private static partial Regex RequestLine();

    [GeneratedRegex("^[a-z_]{1,40}$", RegexOptions.CultureInvariant, 1000)]
    private static partial Regex ErrorCode();
}
