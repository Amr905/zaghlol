using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Seats;

public static class SeatKeysServiceCollectionExtensions
{
    /// <summary>The configuration key of the <c>K_seat</c> startup check value (deployment §3).</summary>
    public const string SeatCheckKey = "Kms:HmacKeys:SeatCheck";

    /// <summary>
    /// The seat-key verifier and the <c>K_seat</c> keyed hashes (T-182): <see cref="SeatKeyProofVerifier"/>,
    /// <see cref="SeatKeyHasher"/> over the KMS, the metrics adapter and the <c>K_seat</c> startup check. Call after
    /// <c>AddZaghlolKms</c>. There is deliberately no fake verifier: tests use the real one with <c>SeatKeyTestSigner</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolSeatKeys(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<ISeatKeyMetrics>(provider => provider.GetRequiredService<ZaghlolMetrics>());
        services.TryAddSingleton<ISeatKeyMac, KmsSeatKeyMac>();
        services.TryAddSingleton<SeatKeyProofVerifier>();
        services.TryAddSingleton<SeatKeyHasher>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, SeatKeyStartupCheck>());
        return services;
    }
}

/// <summary><c>K_seat</c> MACs through <see cref="IKeyedHasher"/>; the key never leaves the KMS.</summary>
internal sealed class KmsSeatKeyMac(IKeyedHasher hasher) : ISeatKeyMac
{
    public ValueTask<byte[]> MacAsync(ReadOnlyMemory<byte> input, CancellationToken cancellationToken) =>
        hasher.HmacSha256Async(KeyedHashKey.Seat, input, cancellationToken);
}

/// <summary>
/// T-182 design note §6: recomputes HMAC(<c>K_seat</c>, <c>"zaghlol-kseat-check-v1"</c>) and compares it in constant time with
/// <c>Kms:HmacKeys:SeatCheck</c>. Outside Development and Testing a missing value, a mismatch or an unreachable KMS stops the
/// start, so a wrong key reference or a recreated / rotated <c>K_seat</c> can't silently turn every iOS install into
/// <c>SEAT_KEY_MISMATCH</c>. In Development and Testing the check runs when the value is set. Messages are constants and never
/// carry the configured or computed value.
/// </summary>
internal sealed partial class SeatKeyStartupCheck(
    SeatKeyHasher hasher,
    IConfiguration configuration,
    IHostEnvironment environment,
    ILogger<SeatKeyStartupCheck> logger) : IHostedService
{
    public const string MissingMessage = "Kms:HmacKeys:SeatCheck must be set outside Development and Testing.";
    public const string MalformedMessage = "Kms:HmacKeys:SeatCheck must be 64 lower-case hex characters.";
    public const string MismatchMessage =
        "Kms:HmacKeys:Seat does not match Kms:HmacKeys:SeatCheck (a wrong key reference, or a recreated or rotated K_seat).";
    public const string UnavailableMessage = "Kms:HmacKeys:Seat could not be checked: the KMS is unavailable.";

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var configured = configuration[SeatKeysServiceCollectionExtensions.SeatCheckKey];
        if (string.IsNullOrWhiteSpace(configured))
        {
            if (!environment.IsDevelopment() && !environment.IsEnvironment("Testing"))
            {
                throw new KmsConfigurationException(MissingMessage);
            }

            LogSkipped(logger);
            return;
        }

        if (!SeatCheckValue.IsWellFormed(configured))
        {
            throw new KmsConfigurationException(MalformedMessage);
        }

        byte[] computed;
        try
        {
            computed = await hasher.SeatCheckAsync(cancellationToken);
        }
        catch (KmsUnavailableException)
        {
            throw new KmsConfigurationException(UnavailableMessage);
        }

        if (!SeatCheckValue.Matches(configured, computed))
        {
            throw new KmsConfigurationException(MismatchMessage);
        }

        LogVerified(logger);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Information, Message = "K_seat startup check passed")]
    private static partial void LogVerified(ILogger logger);

    [LoggerMessage(Level = LogLevel.Warning, Message = "K_seat startup check skipped: Kms:HmacKeys:SeatCheck is not set (Development/Testing only)")]
    private static partial void LogSkipped(ILogger logger);
}
