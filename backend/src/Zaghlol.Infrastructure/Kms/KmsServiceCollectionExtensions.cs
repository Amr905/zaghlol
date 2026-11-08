using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Zaghlol.Infrastructure.Kms;

public static class KmsServiceCollectionExtensions
{
    /// <summary>
    /// Registers <see cref="ISigner"/>, <see cref="IKeyedHasher"/> and <see cref="IEnvelopeCipher"/> over the provider
    /// named by <c>Kms:Provider</c>, and a startup check that refuses to start on a misconfigured ring (T-123).
    /// Tests replace the three provider ports with an in-memory fake.
    /// </summary>
    public static IServiceCollection AddZaghlolKms(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton(new KmsCallPolicy());
        services.TryAddSingleton(provider => KmsSettings.Parse(provider.GetRequiredService<IConfiguration>()));
        services.TryAddSingleton(provider => new SigningKeyRing(provider.GetRequiredService<KmsSettings>().SigningKeys));

        services.TryAddSingleton<LocalKms>(SelectLocal);
        services.TryAddSingleton<ISigningKeyProvider>(provider => provider.GetRequiredService<LocalKms>());
        services.TryAddSingleton<IHmacProvider>(provider => provider.GetRequiredService<LocalKms>());
        services.TryAddSingleton<IDataKeyProvider>(provider => provider.GetRequiredService<LocalKms>());

        services.TryAddSingleton<ISigner, Signer>();
        services.TryAddSingleton<IKeyedHasher, KeyedHasher>();
        services.TryAddSingleton<IEnvelopeCipher, EnvelopeCipher>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, KmsStartupCheck>());
        return services;
    }

    /// <summary>The only provider so far. Fails closed outside Development/Testing; cloud adapters arrive with T-140.</summary>
    internal static LocalKms SelectLocal(IServiceProvider provider)
    {
        var settings = provider.GetRequiredService<KmsSettings>();
        var environment = provider.GetRequiredService<IHostEnvironment>();
        if (!string.Equals(settings.Provider, KmsSettings.LocalProvider, StringComparison.Ordinal))
        {
            throw new KmsConfigurationException("Kms:Provider names no available adapter (Local only; cloud adapters arrive with T-140).");
        }

        if (!environment.IsDevelopment() && !environment.IsEnvironment("Testing"))
        {
            throw new KmsConfigurationException("Kms:Provider = Local is allowed only in the Development and Testing environments.");
        }

        if (string.IsNullOrWhiteSpace(settings.LocalKeyDirectory))
        {
            throw new KmsConfigurationException("Kms:Local:KeyDirectory must be set.");
        }

        return new LocalKms(settings.LocalKeyDirectory);
    }
}

/// <summary>
/// Fails host start unless every published JWK equals its KMS public key, each active key passes a sign-then-verify
/// probe, every HMAC key answers, and an envelope round-trips. Readiness never goes green on a wrong ring.
/// </summary>
internal sealed partial class KmsStartupCheck(
    SigningKeyRing ring,
    ISigningKeyProvider signingProvider,
    ISigner signer,
    IKeyedHasher hasher,
    IEnvelopeCipher cipher,
    KmsCallPolicy policy,
    TimeProvider clock,
    ILogger<KmsStartupCheck> logger) : IHostedService
{
    private static readonly byte[] Probe = "zaghlol-kms-startup-probe-v1"u8.ToArray();

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        foreach (var key in ring.All)
        {
            var point = await KmsCall.RunAsync(
                policy, clock, "public_key", ct => signingProvider.GetPublicKeyAsync(key.KeyRef, ct), cancellationToken);
            if (!point.AsSpan().SequenceEqual(key.PublicJwk.ToX963()))
            {
                throw new KmsConfigurationException($"Signing:Keys: the public JWK of kid {key.Kid} does not match its KMS key.");
            }
        }

        var sync = await signer.SignAsync(SigningPurpose.Sync, Probe, cancellationToken);
        if (!ring.Active(SigningPurpose.Sync).PublicJwk.Verifies(Probe, sync.Signature.Span))
        {
            throw new KmsConfigurationException("Signing:Keys: the sign-then-verify probe failed for the active Sync key.");
        }

        _ = await signer.CreateJwsAsync(SigningPurpose.Entitlement, new { probe = 1 }, cancellationToken);

        foreach (var key in Enum.GetValues<KeyedHashKey>())
        {
            _ = await hasher.HmacSha256Async(key, Probe, cancellationToken);
        }

        var blob = await cipher.EncryptAsync(Probe, "kms-startup-probe", cancellationToken);
        var round = await cipher.DecryptAsync(blob, "kms-startup-probe", cancellationToken);
        if (!round.AsSpan().SequenceEqual(Probe))
        {
            throw new KmsConfigurationException("Kms:Envelope: the encrypt-then-decrypt probe failed.");
        }

        LogVerified(logger, ring.All.Count);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Information, Message = "KMS key ring verified ({KeyCount} published keys)")]
    private static partial void LogVerified(ILogger logger, int keyCount);
}
