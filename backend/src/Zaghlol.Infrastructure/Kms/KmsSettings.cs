using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// KMS and key-ring configuration, written by IaC (T-140) next to the KMS keys. The key ring is configuration, not a
/// table: a database write can never change the signer.
/// <code>
/// Kms:Provider                    Local (Development/Testing only) | a cloud adapter (T-140)
/// Kms:Local:KeyDirectory          PEM P-256 keys and base64 32-byte keys, named by keyRef (local:&lt;name&gt;)
/// Kms:HmacKeys:Seat|Audit|InstallHashPepper   keyRef of each HMAC key
/// Kms:Envelope:KeyRef             keyRef of the envelope key-encryption key (new records)
/// Kms:Envelope:PreviousKeyRefs:n  older key-encryption keys that may still decrypt
/// Signing:Keys:n:Kid|Purpose|Status|KeyRef|PublicJwk:Kty|Crv|X|Y
/// </code>
/// </summary>
public sealed partial class KmsSettings
{
    public const string ProviderKey = "Kms:Provider";
    public const string LocalKeyDirectoryKey = "Kms:Local:KeyDirectory";
    public const string LocalProvider = "Local";

    private KmsSettings(
        string? provider,
        string? localKeyDirectory,
        IReadOnlyDictionary<KeyedHashKey, string> hmacKeyRefs,
        string envelopeKeyRef,
        IReadOnlyList<string> envelopeDecryptKeyRefs,
        IReadOnlyList<SigningKey> signingKeys)
    {
        Provider = provider;
        LocalKeyDirectory = localKeyDirectory;
        HmacKeyRefs = hmacKeyRefs;
        EnvelopeKeyRef = envelopeKeyRef;
        EnvelopeDecryptKeyRefs = envelopeDecryptKeyRefs;
        SigningKeys = signingKeys;
    }

    public string? Provider { get; }

    public string? LocalKeyDirectory { get; }

    public IReadOnlyDictionary<KeyedHashKey, string> HmacKeyRefs { get; }

    /// <summary>Encrypts new envelopes.</summary>
    public string EnvelopeKeyRef { get; }

    /// <summary>The current key-encryption key first, then the previous ones; an envelope naming any other is rejected.</summary>
    public IReadOnlyList<string> EnvelopeDecryptKeyRefs { get; }

    public IReadOnlyList<SigningKey> SigningKeys { get; }

    /// <summary>Reads and checks the configuration. Throws <see cref="KmsConfigurationException"/> naming the bad setting.</summary>
    public static KmsSettings Parse(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var hmac = new Dictionary<KeyedHashKey, string>();
        foreach (var key in Enum.GetValues<KeyedHashKey>())
        {
            hmac[key] = KeyRef(configuration, $"Kms:HmacKeys:{key}");
        }

        var envelope = KeyRef(configuration, "Kms:Envelope:KeyRef");
        var decrypt = new List<string> { envelope };
        foreach (var previous in configuration.GetSection("Kms:Envelope:PreviousKeyRefs").GetChildren())
        {
            decrypt.Add(KeyRef(configuration, previous.Path));
        }

        foreach (var keyRef in decrypt)
        {
            // The envelope header stores the keyRef with a one-byte length (format v1).
            if (keyRef.Length > byte.MaxValue || !keyRef.All(c => c is > ' ' and <= '~'))
            {
                throw new KmsConfigurationException("Kms:Envelope key references must be 1 to 255 printable ASCII characters.");
            }
        }

        var signing = configuration.GetSection("Signing:Keys").GetChildren().Select(ParseSigningKey).ToList();

        return new KmsSettings(
            configuration[ProviderKey],
            configuration[LocalKeyDirectoryKey],
            hmac,
            envelope,
            decrypt.Distinct(StringComparer.Ordinal).ToList(),
            signing);
    }

    private static SigningKey ParseSigningKey(IConfigurationSection entry)
    {
        var jwk = entry.GetSection("PublicJwk");
        return new SigningKey(
            Required(entry, "Kid"),
            ParsePurpose(entry),
            ParseStatus(entry),
            Required(entry, "KeyRef").Trim(),
            new EcPublicJwk(Required(jwk, "Kty"), Required(jwk, "Crv"), Required(jwk, "X"), Required(jwk, "Y")));
    }

    private static SigningPurpose ParsePurpose(IConfigurationSection entry) => Required(entry, "Purpose") switch
    {
        var p when p.Equals("Sync", StringComparison.OrdinalIgnoreCase) => SigningPurpose.Sync,
        var p when p.Equals("Entitlement", StringComparison.OrdinalIgnoreCase) => SigningPurpose.Entitlement,
        _ => throw new KmsConfigurationException($"{entry.Path}:Purpose must be Sync or Entitlement."),
    };

    private static SigningKeyStatus ParseStatus(IConfigurationSection entry) => Required(entry, "Status") switch
    {
        var s when s.Equals("Next", StringComparison.OrdinalIgnoreCase) => SigningKeyStatus.Next,
        var s when s.Equals("Active", StringComparison.OrdinalIgnoreCase) => SigningKeyStatus.Active,
        var s when s.Equals("Retired", StringComparison.OrdinalIgnoreCase) => SigningKeyStatus.Retired,
        _ => throw new KmsConfigurationException($"{entry.Path}:Status must be Next, Active or Retired."),
    };

    private static string Required(IConfigurationSection section, string name)
    {
        var value = section[name];
        return string.IsNullOrWhiteSpace(value)
            ? throw new KmsConfigurationException($"{section.Path}:{name} must be set.")
            : value;
    }

    private static string KeyRef(IConfiguration configuration, string path)
    {
        var value = configuration[path];
        return string.IsNullOrWhiteSpace(value) ? throw new KmsConfigurationException($"{path} must be set.") : value.Trim();
    }

    /// <summary><c>s</c> = sync, <c>e</c> = entitlement, then a year and a letter, for example <c>s2026a</c>.</summary>
    [GeneratedRegex("^[se][0-9]{4}[a-z]\\z", RegexOptions.CultureInvariant)]
    internal static partial Regex KidPattern();
}

/// <summary>The validated key ring: the startup rules of the T-123 design note hold for every instance.</summary>
internal sealed class SigningKeyRing
{
    public SigningKeyRing(IReadOnlyList<SigningKey> keys)
    {
        ArgumentNullException.ThrowIfNull(keys);

        if (keys.Select(k => k.Kid).Distinct(StringComparer.Ordinal).Count() != keys.Count)
        {
            throw new KmsConfigurationException("Signing:Keys: kids must be unique.");
        }

        if (keys.Select(k => k.KeyRef).Distinct(StringComparer.Ordinal).Count() != keys.Count)
        {
            throw new KmsConfigurationException("Signing:Keys: each kid needs its own KMS key (key references must be unique).");
        }

        foreach (var key in keys)
        {
            if (!KmsSettings.KidPattern().IsMatch(key.Kid))
            {
                throw new KmsConfigurationException("Signing:Keys: kids must match ^[se][0-9]{4}[a-z]$.");
            }

            if (key.Kid[0] != Prefix(key.Purpose))
            {
                throw new KmsConfigurationException($"Signing:Keys: kid {key.Kid} does not carry its purpose prefix (s = Sync, e = Entitlement).");
            }

            if (!key.PublicJwk.IsValidP256())
            {
                throw new KmsConfigurationException($"Signing:Keys: the public JWK of kid {key.Kid} is not a valid P-256 key.");
            }
        }

        foreach (var purpose in Enum.GetValues<SigningPurpose>())
        {
            if (keys.Count(k => k.Purpose == purpose && k.Status == SigningKeyStatus.Active) != 1)
            {
                throw new KmsConfigurationException($"Signing:Keys: exactly one Active key is required for purpose {purpose}.");
            }
        }

        All = keys;
    }

    public IReadOnlyList<SigningKey> All { get; }

    public static char Prefix(SigningPurpose purpose) => purpose == SigningPurpose.Sync ? 's' : 'e';

    public SigningKey Active(SigningPurpose purpose) =>
        All.Single(k => k.Purpose == purpose && k.Status == SigningKeyStatus.Active);

    public IReadOnlyList<SigningKey> Published(SigningPurpose purpose) => All.Where(k => k.Purpose == purpose).ToList();
}
