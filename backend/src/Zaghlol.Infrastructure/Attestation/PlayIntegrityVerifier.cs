using System.Globalization;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using NpgsqlTypes;
using Polly.CircuitBreaker;
using Polly.Timeout;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Attestation;

// decodeIntegrityToken response (T-181 design note §2). Only the members the server checks exist. R2-7: there is deliberately no
// member for deviceAttributes, recentDeviceActivity, appAccessRiskVerdict, environmentDetails or accountDetails, no
// [JsonExtensionData] and no JsonElement, so those verdicts are skipped by the reader and never materialised, stored or logged.

/// <summary><c>DecodeIntegrityTokenResponse</c>.</summary>
internal sealed class DecodeIntegrityTokenResponseDto
{
    public TokenPayloadDto? TokenPayloadExternal { get; init; }
}

internal sealed class TokenPayloadDto
{
    public RequestDetailsDto? RequestDetails { get; init; }

    public AppIntegrityDto? AppIntegrity { get; init; }

    public DeviceIntegrityDto? DeviceIntegrity { get; init; }
}

internal sealed class RequestDetailsDto
{
    public string? RequestPackageName { get; init; }

    public string? RequestHash { get; init; }

    /// <summary>An int64 that Google writes as a JSON string.</summary>
    public string? TimestampMillis { get; init; }
}

internal sealed class AppIntegrityDto
{
    public string? AppRecognitionVerdict { get; init; }
}

internal sealed class DeviceIntegrityDto
{
    public List<string>? DeviceRecognitionVerdict { get; init; }
}

internal sealed class DecodeIntegrityTokenRequestDto
{
    public required string IntegrityToken { get; init; }
}

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
    NumberHandling = JsonNumberHandling.Strict)]
[JsonSerializable(typeof(DecodeIntegrityTokenResponseDto))]
[JsonSerializable(typeof(DecodeIntegrityTokenRequestDto))]
internal sealed partial class PlayIntegrityJsonContext : JsonSerializerContext;

/// <summary>What the decode call returned: a payload, a rejection of the token, or an outage.</summary>
internal enum PlayIntegrityDecodeStatus
{
    Decoded,
    Rejected,
    Unavailable,
}

internal sealed record PlayIntegrityDecode(PlayIntegrityDecodeStatus Status, TokenPayloadDto? Payload);

/// <summary>The decode call (separate seam so the rules can be tested without HTTP).</summary>
internal interface IPlayIntegrityDecoder
{
    Task<PlayIntegrityDecode> DecodeAsync(Sensitive<string> token, CancellationToken cancellationToken);
}

/// <summary>
/// <c>POST v1/{packageName}:decodeIntegrityToken</c> over a typed <see cref="HttpClient"/>. The token travels in the body, never in
/// the URL; the span carries the URL template. A <c>400</c> is the token's fault (<see cref="PlayIntegrityDecodeStatus.Rejected"/>);
/// any other non-2xx, a timeout, an open circuit, a network error or an unreadable 2xx is an outage, never a rejection.
/// </summary>
internal sealed class PlayIntegrityClient(HttpClient http, PlayIntegrityOptions options) : IPlayIntegrityDecoder
{
    public const string UrlTemplate = "/v1/{packageName}:decodeIntegrityToken";
    public const int MaxResponseBytes = 64 * 1024;

    public async Task<PlayIntegrityDecode> DecodeAsync(Sensitive<string> token, CancellationToken cancellationToken)
    {
        var path = $"v1/{Uri.EscapeDataString(options.PackageName)}:decodeIntegrityToken";
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(options.BaseUrl, path)).SetUrlTemplate(UrlTemplate);
        request.Content = JsonContent.Create(
            new DecodeIntegrityTokenRequestDto { IntegrityToken = token.Reveal() ?? string.Empty },
            PlayIntegrityJsonContext.Default.DecodeIntegrityTokenRequestDto);
        try
        {
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseContentRead, cancellationToken);
            var status = (int)response.StatusCode;
            if (status == 400)
            {
                return new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Rejected, null);
            }

            if (status is < 200 or >= 300)
            {
                return new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Unavailable, null);
            }

            var dto = await response.Content.ReadFromJsonAsync(PlayIntegrityJsonContext.Default.DecodeIntegrityTokenResponseDto, cancellationToken);
            return dto?.TokenPayloadExternal is { } payload
                ? new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Decoded, payload)
                : new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Unavailable, null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception e) when (e is HttpRequestException or JsonException or TimeoutRejectedException or BrokenCircuitException
                                       or OperationCanceledException or PlayAccessTokenException or NotSupportedException)
        {
            return new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Unavailable, null);
        }
    }
}

/// <summary>Single use of a Play Integrity token: <c>replay_guard</c> rows (hashes only), each committed on its own.</summary>
internal interface IPlayIntegrityReplayGuard
{
    /// <summary>True when the hash was new and is now recorded; false when it was already used.</summary>
    Task<bool> TryUseAsync(byte[] tokenHash, DateTimeOffset expiresAt, CancellationToken cancellationToken);
}

internal sealed class NpgsqlPlayIntegrityReplayGuard(IServiceProvider services) : IPlayIntegrityReplayGuard
{
    private const string InsertSql = """
        INSERT INTO zaghlol.replay_guard (key_hash, kind, expires_at) VALUES (@hash, 'play_integrity', @expires)
        ON CONFLICT (key_hash) DO NOTHING
        """;

    public async Task<bool> TryUseAsync(byte[] tokenHash, DateTimeOffset expiresAt, CancellationToken cancellationToken)
    {
        // Autocommit on its own connection, outside any restore transaction (as sign-in, R3-5): a later rollback can't make the
        // token usable again.
        var source = services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);
        await using var command = source.CreateCommand(InsertSql);
        command.Parameters.AddWithValue("hash", NpgsqlDbType.Bytea, tokenHash);
        command.Parameters.AddWithValue("expires", NpgsqlDbType.TimestampTz, expiresAt.UtcDateTime);
        return await command.ExecuteNonQueryAsync(cancellationToken) == 1;
    }
}

/// <summary>The Play Integrity rules (T-181 design note §3), in order; logs the reason code only.</summary>
internal sealed partial class PlayIntegrityVerifier(
    IPlayIntegrityDecoder decoder,
    IPlayIntegrityReplayGuard replay,
    PlayIntegrityOptions options,
    TimeProvider clock,
    ILogger<PlayIntegrityVerifier> logger) : IPlayIntegrityVerifier
{
    public const int MaxTokenLength = 16 * 1024;
    public const string PlayRecognized = "PLAY_RECOGNIZED";
    public const string MeetsDevice = "MEETS_DEVICE_INTEGRITY";
    public const string MeetsBasic = "MEETS_BASIC_INTEGRITY";

    public static readonly TimeSpan MaxAge = TimeSpan.FromMinutes(5);
    public static readonly TimeSpan MaxFutureSkew = TimeSpan.FromMinutes(1);
    public static readonly TimeSpan ReplayWindow = TimeSpan.FromMinutes(15);

    public async Task<AttestationResult> VerifyAsync(Sensitive<string> token, ReadOnlyMemory<byte> bodyHash, CancellationToken cancellationToken)
    {
        var text = token.Reveal();
        if (string.IsNullOrEmpty(text) || text.Length > MaxTokenLength || bodyHash.Length != 32)
        {
            return Fail(AttestationFailure.Chain);
        }

        var decoded = await decoder.DecodeAsync(token, cancellationToken);
        switch (decoded.Status)
        {
            case PlayIntegrityDecodeStatus.Unavailable:
                LogUnavailable(logger);
                return AttestationResult.Unavailable;
            case PlayIntegrityDecodeStatus.Rejected:
                return Fail(AttestationFailure.Chain);
        }

        var payload = decoded.Payload!;
        var details = payload.RequestDetails;
        if (!string.Equals(details?.RequestPackageName, options.PackageName, StringComparison.Ordinal))
        {
            return Fail(AttestationFailure.AppUnrecognized);
        }

        var expected = Encoding.ASCII.GetBytes(Base64Url(bodyHash.Span));
        var actual = Encoding.ASCII.GetBytes(details!.RequestHash ?? string.Empty);
        if (!CryptographicOperations.FixedTimeEquals(expected, actual))
        {
            return Fail(AttestationFailure.HashMismatch);
        }

        var now = clock.GetUtcNow();
        if (!long.TryParse(details.TimestampMillis, NumberStyles.None, CultureInfo.InvariantCulture, out var millis)
            || millis > DateTimeOffset.MaxValue.ToUnixTimeMilliseconds())
        {
            return Fail(AttestationFailure.Stale);
        }

        var issued = DateTimeOffset.FromUnixTimeMilliseconds(millis);
        if (now - issued > MaxAge || issued - now > MaxFutureSkew)
        {
            return Fail(AttestationFailure.Stale);
        }

        if (!string.Equals(payload.AppIntegrity?.AppRecognitionVerdict, PlayRecognized, StringComparison.Ordinal))
        {
            return Fail(AttestationFailure.AppUnrecognized);
        }

        var labels = payload.DeviceIntegrity?.DeviceRecognitionVerdict ?? [];
        ProofLevel level;
        if (labels.Contains(MeetsDevice, StringComparer.Ordinal))
        {
            level = ProofLevel.Device;
        }
        else if (labels.Contains(MeetsBasic, StringComparer.Ordinal))
        {
            level = ProofLevel.Basic;
        }
        else
        {
            return Fail(AttestationFailure.NoIntegrity);
        }

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        if (!await replay.TryUseAsync(hash, now + ReplayWindow, cancellationToken))
        {
            return Fail(AttestationFailure.Replayed);
        }

        return AttestationResult.Verified(level);
    }

    internal static string Base64Url(ReadOnlySpan<byte> bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private AttestationResult Fail(AttestationFailure failure)
    {
        var code = AttestationCodes.Of(failure);
        LogFailed(logger, code);
        return AttestationResult.Failed(failure);
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "attestation_failed provider=play_integrity reason={reason}")]
    private static partial void LogFailed(ILogger logger, string reason);

    [LoggerMessage(Level = LogLevel.Warning, Message = "attestation_unavailable provider=play_integrity")]
    private static partial void LogUnavailable(ILogger logger);
}
