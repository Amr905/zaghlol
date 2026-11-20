using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>One KMS adapter: the three provider ports in one object (T-200 design note §1).</summary>
internal interface IKmsBackend : ISigningKeyProvider, IHmacProvider, IDataKeyProvider;

/// <summary>
/// A provider that publishes some Retired kids without holding their keys (T-201 review C1: the T-200 <c>file:</c> kids after
/// the switch to OpenBao). The startup check doesn't ask it for their public keys; their pins are its own check.
/// </summary>
internal interface IVerifyOnlySigningKeys
{
    bool IsVerifyOnly(string keyRef);
}

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

        services.TryAddSingleton<IKmsBackend>(SelectProvider);
        services.TryAddSingleton<ISigningKeyProvider>(provider => provider.GetRequiredService<IKmsBackend>());
        services.TryAddSingleton<IHmacProvider>(provider => provider.GetRequiredService<IKmsBackend>());
        services.TryAddSingleton<IDataKeyProvider>(provider => provider.GetRequiredService<IKmsBackend>());

        services.TryAddSingleton<ISigner, Signer>();
        services.TryAddSingleton<IKeyedHasher, KeyedHasher>();
        services.TryAddSingleton<IEnvelopeCipher, EnvelopeCipher>();

        // T-201: the OpenBao key attributes and pins are proved first (a no-op for the other providers), then the ring.
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, OpenBaoStartupCheck>());
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, KmsStartupCheck>());
        return services;
    }

    /// <summary>
    /// The provider named by <c>Kms:Provider</c> (T-200 design note §1): <c>Local</c> (Development/Testing only) or <c>File</c>
    /// (hardened key files, Linux) or <c>OpenBao</c> (Transit, T-201). Any other name refuses the start.
    /// </summary>
    internal static IKmsBackend SelectProvider(IServiceProvider provider)
    {
        var settings = provider.GetRequiredService<KmsSettings>();
        return settings.Provider switch
        {
            KmsSettings.LocalProvider => SelectLocal(provider),
            FileKms.ProviderName => FileKms.Load(settings, provider.GetRequiredService<IHostEnvironment>()),
            OpenBaoKms.ProviderName => OpenBaoKms.Create(
                settings,
                provider.GetRequiredService<IHostEnvironment>(),
                provider.GetRequiredService<TimeProvider>(),
                provider.GetRequiredService<KmsCallPolicy>()),
            _ => throw new KmsConfigurationException("Kms:Provider names no available adapter (Local for development, File, OpenBao)."),
        };
    }

    /// <summary>The development provider. Fails closed outside Development/Testing.</summary>
    internal static LocalKms SelectLocal(IServiceProvider provider)
    {
        var settings = provider.GetRequiredService<KmsSettings>();
        var environment = provider.GetRequiredService<IHostEnvironment>();

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
/// probe, every HMAC key answers, and an envelope round-trips. Readiness never goes green on a wrong ring. Under
/// <c>Kms:Scope = Envelope</c> (the worker, T-201) only the envelope round trip runs.
/// </summary>
internal sealed partial class KmsStartupCheck(
    KmsSettings settings,
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
        if (settings.Scope == KmsScope.Envelope)
        {
            await CheckEnvelopeAsync(cancellationToken);
            LogVerifiedEnvelope(logger);
            return;
        }

        foreach (var key in ring.All)
        {
            if (key.Status == SigningKeyStatus.Retired && signingProvider is IVerifyOnlySigningKeys verifyOnly && verifyOnly.IsVerifyOnly(key.KeyRef))
            {
                continue;
            }

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

        await CheckEnvelopeAsync(cancellationToken);
        LogVerified(logger, ring.All.Count);
    }

    private async Task CheckEnvelopeAsync(CancellationToken cancellationToken)
    {
        var blob = await cipher.EncryptAsync(Probe, "kms-startup-probe", cancellationToken);
        var round = await cipher.DecryptAsync(blob, "kms-startup-probe", cancellationToken);
        if (!round.AsSpan().SequenceEqual(Probe))
        {
            throw new KmsConfigurationException("Kms:Envelope: the encrypt-then-decrypt probe failed.");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Information, Message = "KMS key ring verified ({KeyCount} published keys)")]
    private static partial void LogVerified(ILogger logger, int keyCount);

    [LoggerMessage(Level = LogLevel.Information, Message = "KMS envelope keys verified (Kms:Scope = Envelope)")]
    private static partial void LogVerifiedEnvelope(ILogger logger);
}
