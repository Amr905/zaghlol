using System.Buffers;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// A transient OpenBao failure inside the adapter (transport, TLS, timeout, sealed, refused, malformed answer). It never
/// leaves the adapter's callers: <see cref="KmsCall"/> retries it once and then throws <see cref="KmsUnavailableException"/>.
/// The message is constant; no URL, key name, token or server text.
/// </summary>
internal sealed class OpenBaoUnavailableException : Exception
{
    public const string DefaultMessage = "OpenBao did not answer usefully.";

    public OpenBaoUnavailableException()
        : base(DefaultMessage)
    {
    }

    public OpenBaoUnavailableException(string message)
        : base(message)
    {
    }

    public OpenBaoUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>One OpenBao answer: the status and the parsed JSON. Dispose zeroes the bytes it was read from.</summary>
internal sealed class OpenBaoAnswer : IDisposable
{
    private readonly byte[] buffer;
    private readonly JsonDocument? json;

    public OpenBaoAnswer(HttpStatusCode status, byte[] buffer, int length)
    {
        Status = status;
        this.buffer = buffer;
        if (length > 0)
        {
            try
            {
                // The document reads the buffer in place (no copy), so zeroing the buffer on dispose clears the key bytes.
                json = JsonDocument.Parse(buffer.AsMemory(0, length), new JsonDocumentOptions { MaxDepth = 16 });
            }
            catch (JsonException)
            {
                json = null;
            }
        }
    }

    public HttpStatusCode Status { get; }

    public bool IsSuccess => (int)Status is >= 200 and < 300;

    /// <summary>The <c>data</c> object of a successful answer, or <c>null</c>.</summary>
    public JsonElement? Data => Object("data");

    /// <summary>The <c>auth</c> object of a login answer, or <c>null</c>.</summary>
    public JsonElement? Auth => Object("auth");

    /// <summary>True when the answer's <c>errors</c> array holds exactly <paramref name="error"/> and nothing else.</summary>
    public bool HasOnlyError(string error)
    {
        if (json is null
            || json.RootElement.ValueKind != JsonValueKind.Object
            || !json.RootElement.TryGetProperty("errors", out var errors)
            || errors.ValueKind != JsonValueKind.Array
            || errors.GetArrayLength() != 1)
        {
            return false;
        }

        var only = errors[0];
        return only.ValueKind == JsonValueKind.String && only.ValueEquals(error);
    }

    public void Dispose()
    {
        json?.Dispose();
        CryptographicOperations.ZeroMemory(buffer);
    }

    private JsonElement? Object(string name) =>
        json is { RootElement.ValueKind: JsonValueKind.Object } doc
        && doc.RootElement.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.Object
            ? value
            : null;
}

/// <summary>
/// The HTTP side of the OpenBao adapter (T-201 design note §3–§4): one pinned-CA TLS client with no proxy, an AppRole
/// session that logs in again after two thirds of the token lifetime or after a <c>403</c>, and answers read to at most
/// <see cref="MaxResponseBytes"/>. Request bodies are written into buffers that are zeroed after the call.
/// </summary>
internal sealed class OpenBaoClient : IDisposable
{
    public const int MaxResponseBytes = 64 * 1024;

    private const string TokenHeader = "X-Vault-Token";

    private readonly HttpClient http;
    private readonly Uri apiBase;
    private readonly Func<OpenBaoCredentials> credentials;
    private readonly TimeProvider clock;
    private readonly SemaphoreSlim loginGate = new(1, 1);
    private readonly bool fixedToken;
    private Session? session;
    private int logins;

    /// <param name="address">The server address (validated by the caller); requests go to <c>&lt;address&gt;/v1/…</c>.</param>
    /// <param name="handler">The transport; <see cref="CreateHandler"/> in production, owned and disposed by this client.</param>
    /// <param name="credentials">Reads <c>role-id</c> and <c>secret-id</c> again for every login.</param>
    public OpenBaoClient(Uri address, HttpMessageHandler handler, Func<OpenBaoCredentials> credentials, TimeProvider clock)
    {
        ArgumentNullException.ThrowIfNull(address);
        ArgumentNullException.ThrowIfNull(handler);
        apiBase = new Uri(address.GetLeftPart(UriPartial.Authority) + "/v1/");
        this.credentials = credentials;
        this.clock = clock;
        http = new HttpClient(handler, disposeHandler: true)
        {
            // KmsCall bounds every attempt; this is only a backstop.
            Timeout = TimeSpan.FromSeconds(30),
            MaxResponseContentBufferSize = MaxResponseBytes,
        };
    }

    /// <summary>A client that always uses <paramref name="token"/> (the operator key tool); it never logs in.</summary>
    public static OpenBaoClient WithToken(Uri address, HttpMessageHandler handler, string token, TimeProvider clock)
    {
        var client = new OpenBaoClient(address, handler, static () => throw new OpenBaoUnavailableException(), clock, fixedToken: true);
        client.session = new Session(token, RefreshAt: null);
        return client;
    }

    private OpenBaoClient(Uri address, HttpMessageHandler handler, Func<OpenBaoCredentials> credentials, TimeProvider clock, bool fixedToken)
        : this(address, handler, credentials, clock)
    {
        this.fixedToken = fixedToken;
    }

    /// <summary>How many logins this client made (tests: one login for many concurrent callers).</summary>
    public int Logins => Volatile.Read(ref logins);

    /// <summary>
    /// A <see cref="SocketsHttpHandler"/> that never uses a proxy or follows a redirect and, for <c>https</c>, trusts only
    /// <paramref name="trustedRoots"/> (system roots ignored; host name checked; TLS 1.2/1.3).
    /// </summary>
    public static SocketsHttpHandler CreateHandler(X509Certificate2Collection? trustedRoots, TimeSpan connectTimeout)
    {
        var handler = new SocketsHttpHandler
        {
            UseProxy = false,
            AllowAutoRedirect = false,
            UseCookies = false,
            AutomaticDecompression = DecompressionMethods.None,
            ConnectTimeout = connectTimeout,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            MaxResponseHeadersLength = 64,
        };

        if (trustedRoots is not null)
        {
            var policy = new X509ChainPolicy
            {
                TrustMode = X509ChainTrustMode.CustomRootTrust,
                RevocationMode = X509RevocationMode.NoCheck,
                VerificationFlags = X509VerificationFlags.NoFlag,
            };
            policy.CustomTrustStore.AddRange(trustedRoots);

            handler.SslOptions = new SslClientAuthenticationOptions
            {
#pragma warning disable CA5398 // Pinned on purpose: OpenBao's listener is configured for TLS 1.2+ and nothing older is acceptable.
                EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
#pragma warning restore CA5398
                CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
                CertificateChainPolicy = policy,

                // The chain policy above already decided; any error (another CA, name mismatch, no certificate) refuses.
                RemoteCertificateValidationCallback = static (_, _, _, errors) => errors == SslPolicyErrors.None,
            };
        }

        return handler;
    }

    /// <summary>
    /// Sends one request with the session token. On <c>403</c> it logs in again once (only if the token it used is still the
    /// session's) and repeats the request once. Transport failures throw <see cref="OpenBaoUnavailableException"/>; caller
    /// cancellation propagates. The caller disposes the answer.
    /// </summary>
    public async Task<OpenBaoAnswer> SendAsync(HttpMethod method, string path, Action<Utf8JsonWriter>? body, CancellationToken cancellationToken)
    {
        var token = await TokenAsync(cancellationToken).ConfigureAwait(false);
        var answer = await SendRawAsync(method, path, body, token, cancellationToken).ConfigureAwait(false);
        if (answer.Status != HttpStatusCode.Forbidden)
        {
            return answer;
        }

        answer.Dispose();
        Invalidate(token);
        token = await TokenAsync(cancellationToken).ConfigureAwait(false);
        answer = await SendRawAsync(method, path, body, token, cancellationToken).ConfigureAwait(false);
        if (answer.Status == HttpStatusCode.Forbidden)
        {
            answer.Dispose();
            throw new OpenBaoUnavailableException();
        }

        return answer;
    }

    /// <summary>Sends without a session (the key tool's operator token, or none for login).</summary>
    public async Task<OpenBaoAnswer> SendRawAsync(HttpMethod method, string path, Action<Utf8JsonWriter>? body, string? token, CancellationToken cancellationToken)
    {
        byte[]? content = null;
        var contentLength = 0;
        try
        {
            using var request = new HttpRequestMessage(method, new Uri(apiBase, path));
            if (token is not null)
            {
                request.Headers.TryAddWithoutValidation(TokenHeader, token);
            }

            if (body is not null)
            {
                (content, contentLength) = Serialize(body);
                var payload = new ByteArrayContent(content, 0, contentLength);
                payload.Headers.ContentType = new MediaTypeHeaderValue("application/json");
                request.Content = payload;
            }

            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
            if (response.Content.Headers.ContentLength is > MaxResponseBytes)
            {
                throw new OpenBaoUnavailableException();
            }

            // Owned (not pooled) buffers: an answer may hold a data key, and a pooled array could be handed to someone else
            // while a cancelled read is still unwinding. Grown by doubling up to the cap; each outgrown buffer is zeroed.
            var buffer = new byte[4096];
            var length = 0;
            try
            {
                await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
                while (true)
                {
                    if (length == buffer.Length)
                    {
                        if (buffer.Length > MaxResponseBytes)
                        {
                            throw new OpenBaoUnavailableException();
                        }

                        var larger = new byte[Math.Min(buffer.Length * 2, MaxResponseBytes + 1)];
                        buffer.AsSpan(0, length).CopyTo(larger);
                        CryptographicOperations.ZeroMemory(buffer);
                        buffer = larger;
                    }

                    var read = await stream.ReadAsync(buffer.AsMemory(length), cancellationToken).ConfigureAwait(false);
                    if (read == 0)
                    {
                        break;
                    }

                    length += read;
                }

                if (length > MaxResponseBytes)
                {
                    throw new OpenBaoUnavailableException();
                }
            }
            catch
            {
                CryptographicOperations.ZeroMemory(buffer);
                throw;
            }

            return new OpenBaoAnswer(response.StatusCode, buffer, length);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OpenBaoUnavailableException)
        {
            throw;
        }
#pragma warning disable CA1031 // Any transport failure (TLS, socket, timeout, bad header) is one constant transient error: its text can carry the URL.
        catch (Exception ex) when (ex is not (OutOfMemoryException or StackOverflowException))
#pragma warning restore CA1031
        {
            throw new OpenBaoUnavailableException();
        }
        finally
        {
            if (content is not null)
            {
                CryptographicOperations.ZeroMemory(content.AsSpan(0, contentLength));
            }
        }
    }

    public void Dispose()
    {
        http.Dispose();
        loginGate.Dispose();
    }

    private static (byte[] Buffer, int Length) Serialize(Action<Utf8JsonWriter> body)
    {
        // 4 KiB holds every request this adapter sends (the largest, a key import, is about 1 KiB), so the writer never grows
        // and leaves no unzeroed copy behind.
        var output = new ArrayBufferWriter<byte>(4096);
        using (var writer = new Utf8JsonWriter(output))
        {
            writer.WriteStartObject();
            body(writer);
            writer.WriteEndObject();
        }

        var length = output.WrittenCount;
        var buffer = output.WrittenSpan.ToArray();

        // ArrayBufferWriter.Clear zeroes the written bytes.
        output.Clear();
        return (buffer, length);
    }

    private async Task<string> TokenAsync(CancellationToken cancellationToken)
    {
        if (Valid(Volatile.Read(ref session)) is { } current)
        {
            return current;
        }

        await loginGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (Valid(Volatile.Read(ref session)) is { } refreshed)
            {
                return refreshed;
            }

            var fresh = await LoginAsync(cancellationToken).ConfigureAwait(false);
            Volatile.Write(ref session, fresh);
            return fresh.Token;
        }
        finally
        {
            loginGate.Release();
        }
    }

    private string? Valid(Session? candidate) =>
        candidate is not null && (candidate.RefreshAt is null || clock.GetUtcNow() < candidate.RefreshAt) ? candidate.Token : null;

    /// <summary>Drops the session only if it still holds the token that was refused (another caller may have renewed it).</summary>
    private void Invalidate(string refusedToken)
    {
        if (fixedToken)
        {
            throw new OpenBaoUnavailableException();
        }

        var current = Volatile.Read(ref session);
        if (current is not null && string.Equals(current.Token, refusedToken, StringComparison.Ordinal))
        {
            Interlocked.CompareExchange(ref session, null, current);
        }
    }

    private async Task<Session> LoginAsync(CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref logins);
        var login = credentials();
        using var answer = await SendRawAsync(
            HttpMethod.Post,
            "auth/approle/login",
            writer =>
            {
                writer.WriteString("role_id", login.RoleId);
                writer.WriteString("secret_id", login.SecretId);
            },
            token: null,
            cancellationToken).ConfigureAwait(false);

        if (!answer.IsSuccess
            || answer.Auth is not { } auth
            || !auth.TryGetProperty("client_token", out var tokenElement)
            || tokenElement.ValueKind != JsonValueKind.String
            || tokenElement.GetString() is not { Length: > 0 and <= 1024 } token
            || !token.All(c => c is > ' ' and <= '~'))
        {
            throw new OpenBaoUnavailableException();
        }

        DateTimeOffset? refreshAt = null;
        if (auth.TryGetProperty("lease_duration", out var lease) && lease.TryGetInt64(out var seconds) && seconds > 0)
        {
            refreshAt = clock.GetUtcNow() + TimeSpan.FromSeconds(seconds * 2 / 3.0);
        }

        return new Session(token, refreshAt);
    }

    private sealed record Session(string Token, DateTimeOffset? RefreshAt);
}

/// <summary>The AppRole login pair, read from the credential directory for one login.</summary>
internal sealed record OpenBaoCredentials(string RoleId, string SecretId);
