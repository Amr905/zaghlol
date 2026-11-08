using System.Collections.Concurrent;
using System.Globalization;
using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Testing;

/// <summary>How the fake KMS misbehaves, for failure-mode tests.</summary>
public enum FakeKmsFault
{
    None,

    /// <summary>Every call throws (an unreachable KMS).</summary>
    Throw,

    /// <summary>Every call waits until cancelled, ignoring nothing else (a KMS that never answers).</summary>
    Hang,

    /// <summary>Signatures come from a different key (a wrong key reference).</summary>
    WrongKey,
}

/// <summary>
/// An in-memory KMS for tests: every key is generated per run and never written anywhere. It implements the three
/// provider ports and produces the matching <c>Kms:*</c> / <c>Signing:Keys</c> configuration.
/// </summary>
public sealed class FakeKms : ISigningKeyProvider, IHmacProvider, IDataKeyProvider, IDisposable
{
    public const string SyncKid = "s0000t";
    public const string EntitlementKid = "e0000t";

    private static readonly byte[] WrapAad = "fake-kms-wrap"u8.ToArray();

    private readonly ConcurrentDictionary<string, ECDsa> ecKeys = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, byte[]> secrets = new(StringComparer.Ordinal);
    private readonly List<SigningKey> keys = [];
    private readonly ECDsa stranger = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private int calls;

    public FakeKmsFault Fault { get; set; }

    public int Calls => Volatile.Read(ref calls);

    public IReadOnlyList<SigningKey> Keys => keys;

    public string EnvelopeKeyRef { get; set; } = "fake:envelope";

    public IList<string> PreviousEnvelopeKeyRefs { get; } = [];

    /// <summary>One active Sync key (<c>s0000t</c>), one active Entitlement key (<c>e0000t</c>), random HMAC and envelope keys.</summary>
    public static FakeKms CreateDefault()
    {
        var kms = new FakeKms();
        kms.AddSigningKey(SyncKid, SigningPurpose.Sync, SigningKeyStatus.Active);
        kms.AddSigningKey(EntitlementKid, SigningPurpose.Entitlement, SigningKeyStatus.Active);
        foreach (var key in Enum.GetValues<KeyedHashKey>())
        {
            kms.AddSecret(HmacKeyRef(key), RandomNumberGenerator.GetBytes(32));
        }

        kms.AddSecret(kms.EnvelopeKeyRef, RandomNumberGenerator.GetBytes(32));
        return kms;
    }

    public static string HmacKeyRef(KeyedHashKey key) => "fake:hmac-" + key.ToString().ToLowerInvariant();

    public static string KeyRefFor(string kid) => "fake:" + kid;

    public SigningKey AddSigningKey(string kid, SigningPurpose purpose, SigningKeyStatus status)
    {
        var ec = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var keyRef = KeyRefFor(kid);
        ecKeys[keyRef] = ec;
        var q = ec.ExportParameters(false).Q;
        var key = new SigningKey(kid, purpose, status, keyRef, EcPublicJwk.FromX963([0x04, .. q.X!, .. q.Y!]));
        keys.Add(key);
        return key;
    }

    /// <summary>Changes the status of a configured key (a rotation is a configuration change).</summary>
    public void SetStatus(string kid, SigningKeyStatus status)
    {
        var index = keys.FindIndex(k => string.Equals(k.Kid, kid, StringComparison.Ordinal));
        keys[index] = keys[index] with { Status = status };
    }

    public void AddSecret(string keyRef, byte[] secret) => secrets[keyRef] = secret;

    /// <summary>A raw signature with a configured key in any format (vector generation only).</summary>
    public byte[] SignRaw(string kid, byte[] data, DSASignatureFormat format) =>
        ecKeys[KeyRefFor(kid)].SignData(data, HashAlgorithmName.SHA256, format);

    /// <summary>The configuration the IaC would write for this ring.</summary>
    public Dictionary<string, string?> Settings()
    {
        var settings = new Dictionary<string, string?>(StringComparer.Ordinal);
        for (var i = 0; i < keys.Count; i++)
        {
            var prefix = string.Create(CultureInfo.InvariantCulture, $"Signing:Keys:{i}:");
            var key = keys[i];
            settings[prefix + "Kid"] = key.Kid;
            settings[prefix + "Purpose"] = key.Purpose.ToString();
            settings[prefix + "Status"] = key.Status.ToString();
            settings[prefix + "KeyRef"] = key.KeyRef;
            settings[prefix + "PublicJwk:Kty"] = key.PublicJwk.Kty;
            settings[prefix + "PublicJwk:Crv"] = key.PublicJwk.Crv;
            settings[prefix + "PublicJwk:X"] = key.PublicJwk.X;
            settings[prefix + "PublicJwk:Y"] = key.PublicJwk.Y;
        }

        foreach (var key in Enum.GetValues<KeyedHashKey>())
        {
            settings["Kms:HmacKeys:" + key] = HmacKeyRef(key);
        }

        settings["Kms:Envelope:KeyRef"] = EnvelopeKeyRef;
        for (var i = 0; i < PreviousEnvelopeKeyRefs.Count; i++)
        {
            settings[string.Create(CultureInfo.InvariantCulture, $"Kms:Envelope:PreviousKeyRefs:{i}")] = PreviousEnvelopeKeyRefs[i];
        }

        return settings;
    }

    /// <summary>Replaces the configured provider ports with this fake.</summary>
    public void Use(IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.RemoveAll<ISigningKeyProvider>();
        services.RemoveAll<IHmacProvider>();
        services.RemoveAll<IDataKeyProvider>();
        services.AddSingleton<ISigningKeyProvider>(this);
        services.AddSingleton<IHmacProvider>(this);
        services.AddSingleton<IDataKeyProvider>(this);
    }

    /// <summary>
    /// A container with <c>AddZaghlolKms</c> over this fake and its configuration (plus <paramref name="extra"/> settings).
    /// </summary>
    public ServiceProvider BuildServices(IDictionary<string, string?>? extra = null, Action<IServiceCollection>? configure = null)
    {
        var settings = Settings();
        foreach (var (key, value) in extra ?? new Dictionary<string, string?>())
        {
            settings[key] = value;
        }

        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        services.AddLogging();
        services.AddZaghlolKms();
        Use(services);
        configure?.Invoke(services);
        return services.BuildServiceProvider();
    }

    public async ValueTask<byte[]> SignDigestAsync(string keyRef, ReadOnlyMemory<byte> sha256, CancellationToken cancellationToken)
    {
        await EnterAsync(cancellationToken);
        var key = Fault == FakeKmsFault.WrongKey ? stranger : ecKeys[keyRef];
        return key.SignHash(sha256.Span, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }

    public async ValueTask<byte[]> GetPublicKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        await EnterAsync(cancellationToken);
        var q = ecKeys[keyRef].ExportParameters(false).Q;
        return [0x04, .. q.X!, .. q.Y!];
    }

    public async ValueTask<byte[]> HmacSha256Async(string keyRef, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        await EnterAsync(cancellationToken);
        return HMACSHA256.HashData(secrets[keyRef], data.Span);
    }

    public async ValueTask<DataKey> GenerateDataKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        await EnterAsync(cancellationToken);
        var plaintext = RandomNumberGenerator.GetBytes(DataKey.Size);
        var wrapped = new byte[12 + DataKey.Size + 16];
        RandomNumberGenerator.Fill(wrapped.AsSpan(0, 12));
        using var aes = new AesGcm(secrets[keyRef], 16);
        aes.Encrypt(wrapped.AsSpan(0, 12), plaintext, wrapped.AsSpan(12, DataKey.Size), wrapped.AsSpan(12 + DataKey.Size), WrapAad);
        return new DataKey(plaintext, wrapped);
    }

    public async ValueTask<DataKey> DecryptDataKeyAsync(string keyRef, ReadOnlyMemory<byte> wrapped, CancellationToken cancellationToken)
    {
        await EnterAsync(cancellationToken);
        if (wrapped.Length != 12 + DataKey.Size + 16 || !secrets.TryGetValue(keyRef, out var secret))
        {
            throw new CryptographicException();
        }

        var plaintext = new byte[DataKey.Size];
        using var aes = new AesGcm(secret, 16);
        aes.Decrypt(wrapped.Span[..12], wrapped.Span.Slice(12, DataKey.Size), wrapped.Span[(12 + DataKey.Size)..], plaintext, WrapAad);
        return new DataKey(plaintext, wrapped.ToArray());
    }

    public void Dispose()
    {
        foreach (var key in ecKeys.Values)
        {
            key.Dispose();
        }

        stranger.Dispose();
    }

    private async Task EnterAsync(CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref calls);
        switch (Fault)
        {
            case FakeKmsFault.Throw:
                throw new HttpRequestException("fake KMS unreachable");
            case FakeKmsFault.Hang:
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                break;
        }
    }
}
