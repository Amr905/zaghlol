using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Accounts;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Accounts;

/// <summary>
/// Sign in with Apple's token endpoint (T-135 design note). The client secret is an ES256 JWT signed with the Sign in with Apple
/// key from the secrets manager (<c>Accounts:Apple:*</c>), minted per call, valid five minutes. The refresh token is kept only to
/// revoke it on account deletion. Codes, tokens and Apple's bodies are never logged: only fixed words and status codes.
/// </summary>
internal sealed partial class AppleAccountClient(
    IHttpClientFactory clients, AccountsOptions options, TimeProvider clock, ILogger<AppleAccountClient> logger) : IAppleAccountClient, IDisposable
{
    public const string HttpClientName = "zaghlol-apple-account";

    private const string Audience = "https://appleid.apple.com";
    private const int MaxResponseBytes = 16 * 1024;

    private readonly Lazy<ECDsa?> key = new(() => options.ApplePrivateKey is { } pem ? AppStoreApiTokenProvider.LoadKey(pem.Reveal()) : null);

    public async Task<AppleRefreshToken?> ExchangeCodeAsync(
        Sensitive<string> code, string clientId, string expectedSubject, CancellationToken cancellationToken)
    {
        if (!options.HasAppleKey)
        {
            LogNotConfigured(logger);
            return null;
        }

        try
        {
            using var response = await PostAsync(
                "auth/token",
                [("client_id", clientId), ("client_secret", ClientSecret(clientId)), ("code", code.Reveal()), ("grant_type", "authorization_code")],
                cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                LogExchangeFailed(logger, (int)response.StatusCode);
                return null;
            }

            var body = await ReadAsync(response, cancellationToken).ConfigureAwait(false);
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("refresh_token", out var refresh) || refresh.ValueKind != JsonValueKind.String || refresh.GetString() is not { Length: > 0 } token
                || !root.TryGetProperty("id_token", out var idToken) || idToken.ValueKind != JsonValueKind.String
                || SubjectOf(idToken.GetString()) is not { } subject
                || !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(subject), Encoding.UTF8.GetBytes(expectedSubject)))
            {
                // A code for another identity (or a body we can't read) is never kept against this account.
                LogExchangeRefused(logger);
                return null;
            }

            return new AppleRefreshToken(clientId, new Sensitive<string>(token));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException or InvalidOperationException or FormatException)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                throw;
            }

            LogExchangeFailed(logger, 0);
            return null;
        }
    }

    public async Task<AppleRevokeOutcome> RevokeAsync(AppleRefreshToken token, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(token);
        if (!options.HasAppleKey)
        {
            LogNotConfigured(logger);
            return AppleRevokeOutcome.Unavailable;
        }

        try
        {
            using var response = await PostAsync(
                "auth/revoke",
                [
                    ("client_id", token.ClientId), ("client_secret", ClientSecret(token.ClientId)),
                    ("token", token.Token.Reveal()), ("token_type_hint", "refresh_token"),
                ],
                cancellationToken).ConfigureAwait(false);
            if (response.IsSuccessStatusCode)
            {
                return AppleRevokeOutcome.Revoked;
            }

            // invalid_grant: the token is already revoked or gone, which is what we wanted.
            if ((int)response.StatusCode == 400 && await IsInvalidGrantAsync(response, cancellationToken).ConfigureAwait(false))
            {
                return AppleRevokeOutcome.Revoked;
            }

            LogRevokeFailed(logger, (int)response.StatusCode);
            return AppleRevokeOutcome.Unavailable;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                throw;
            }

            LogRevokeFailed(logger, 0);
            return AppleRevokeOutcome.Unavailable;
        }
    }

    public void Dispose()
    {
        if (key.IsValueCreated)
        {
            key.Value?.Dispose();
        }
    }

    private async Task<HttpResponseMessage> PostAsync(string path, (string Name, string Value)[] form, CancellationToken cancellationToken)
    {
        var client = clients.CreateClient(HttpClientName);
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(options.AppleBaseUrl, path))
        {
            Content = new FormUrlEncodedContent(form.Select(f => new KeyValuePair<string, string>(f.Name, f.Value))),
        };
        return await client.SendAsync(request, HttpCompletionOption.ResponseContentRead, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<byte[]> ReadAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        return bytes.Length <= MaxResponseBytes ? bytes : throw new InvalidOperationException("The Apple response is too large.");
    }

    private static async Task<bool> IsInvalidGrantAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            using var document = JsonDocument.Parse(await ReadAsync(response, cancellationToken).ConfigureAwait(false));
            return document.RootElement.ValueKind == JsonValueKind.Object
                && document.RootElement.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.String && error.GetString() == "invalid_grant";
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            return false;
        }
    }

    /// <summary>The <c>sub</c> of an ID token Apple returned straight to us over TLS (not re-verified: it never passed through the app).</summary>
    private static string? SubjectOf(string? jws)
    {
        var parts = jws?.Split('.');
        if (parts is not { Length: 3 })
        {
            return null;
        }

        try
        {
            using var payload = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1]));
            return payload.RootElement.TryGetProperty("sub", out var sub) && sub.ValueKind == JsonValueKind.String ? sub.GetString() : null;
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            return null;
        }
    }

    private string ClientSecret(string clientId)
    {
        var ecdsa = key.Value ?? throw new InvalidOperationException("The Sign in with Apple key is not configured.");
        var now = clock.GetUtcNow().ToUnixTimeSeconds();
        var header = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, string> { ["alg"] = "ES256", ["kid"] = options.AppleKeyId!, ["typ"] = "JWT" });
        var payload = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, object>
        {
            ["iss"] = options.AppleTeamId!,
            ["iat"] = now,
            ["exp"] = now + 300,
            ["aud"] = Audience,
            ["sub"] = clientId,
        });
        var signingInput = Base64Url.EncodeToString(header) + "." + Base64Url.EncodeToString(payload);
        var signature = ecdsa.SignData(Encoding.ASCII.GetBytes(signingInput), HashAlgorithmName.SHA256);
        return signingInput + "." + Base64Url.EncodeToString(signature);
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Warning, Message = "Sign in with Apple is not configured; the refresh token was not exchanged or revoked.")]
    private static partial void LogNotConfigured(ILogger logger);

    [LoggerMessage(EventId = 2, Level = LogLevel.Warning, Message = "Apple refused the authorization code exchange (status {Status}).")]
    private static partial void LogExchangeFailed(ILogger logger, int status);

    [LoggerMessage(EventId = 3, Level = LogLevel.Warning, Message = "Apple's code exchange answered with an unusable body or another identity; no refresh token kept.")]
    private static partial void LogExchangeRefused(ILogger logger);

    [LoggerMessage(EventId = 4, Level = LogLevel.Warning, Message = "Apple refused to revoke the refresh token (status {Status}); the account deletion will be retried.")]
    private static partial void LogRevokeFailed(ILogger logger, int status);
}

/// <summary>The Apple refresh token as an envelope: plaintext <c>clientId LF token</c>, context bound to the account's provider subject.</summary>
internal sealed class AppleTokenVault(IEnvelopeCipher cipher) : IAppleTokenVault
{
    public async Task<byte[]> SealAsync(string subject, AppleRefreshToken token, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(token);
        var plain = Encoding.UTF8.GetBytes(token.ClientId + "\n" + token.Token.Reveal());
        try
        {
            return await cipher.EncryptAsync(plain, Context(subject), cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plain);
        }
    }

    public async Task<AppleRefreshToken?> OpenAsync(string subject, ReadOnlyMemory<byte> sealedToken, CancellationToken cancellationToken)
    {
        byte[] plain;
        try
        {
            plain = await cipher.DecryptAsync(sealedToken, Context(subject), cancellationToken).ConfigureAwait(false);
        }
        catch (EnvelopeDecryptionException)
        {
            return null;
        }

        try
        {
            var text = Encoding.UTF8.GetString(plain);
            var split = text.IndexOf('\n', StringComparison.Ordinal);
            return split <= 0 || split == text.Length - 1
                ? null
                : new AppleRefreshToken(text[..split], new Sensitive<string>(text[(split + 1)..]));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plain);
        }
    }

    private static string Context(string subject) =>
        "account/apple-rt/v1/" + Base64Url.EncodeToString(SHA256.HashData(Encoding.UTF8.GetBytes(subject)));
}
