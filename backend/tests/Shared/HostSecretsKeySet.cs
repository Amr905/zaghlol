using System.Buffers.Text;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Testing;

/// <summary>
/// T-205: a HostSecrets key ring held in settings only (no file), the way the key tool prints it: <c>ZAGHLOL_KEYS:&lt;name&gt;</c>
/// values, File pins, the ring, HMAC and envelope refs, <c>SeatCheck</c> and the custody flag. Any OS. Every key is random per
/// instance; <see cref="Sentinels"/> lists text that must never reach a log, message or response.
/// </summary>
public sealed class HostSecretsKeySet
{
    public static readonly string[] SecretNames = ["seat", "audit", "install-pepper", "envelope"];

    private readonly Dictionary<string, string?> settings = new(StringComparer.Ordinal);
    private readonly Dictionary<string, byte[]> secrets = new(StringComparer.Ordinal);
    private readonly List<string> sentinels = [];

    public HostSecretsKeySet(string syncKid = "s2026a", string entitlementKid = "e2026a")
    {
        settings["Kms:Provider"] = "HostSecrets";
        settings["Kms:AcceptSharedHostCustody"] = "true";
        settings["Kms:File:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "file:seat";
        settings["Kms:HmacKeys:Audit"] = "file:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "file:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "file:envelope";
        settings["ForwardedHeaders:NoProxy"] = "true";

        var index = 0;
        foreach (var (kid, purpose) in new[] { (syncKid, "Sync"), (entitlementKid, "Entitlement") })
        {
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            SetSigningKey(kid, key);
            var q = key.ExportParameters(false).Q;
            var prefix = string.Create(CultureInfo.InvariantCulture, $"Signing:Keys:{index++}:");
            settings[prefix + "Kid"] = kid;
            settings[prefix + "Purpose"] = purpose;
            settings[prefix + "Status"] = "Active";
            settings[prefix + "KeyRef"] = "file:" + kid;
            settings[prefix + "PublicJwk:Kty"] = "EC";
            settings[prefix + "PublicJwk:Crv"] = "P-256";
            settings[prefix + "PublicJwk:X"] = Base64Url.EncodeToString(q.X!);
            settings[prefix + "PublicJwk:Y"] = Base64Url.EncodeToString(q.Y!);
        }

        foreach (var name in SecretNames)
        {
            SetSecret(name, RandomNumberGenerator.GetBytes(32));
        }
    }

    /// <summary>Key text, key bytes and setting values: none of it may appear in a log, message or output.</summary>
    public IReadOnlyList<string> Sentinels => sentinels;

    /// <summary>A copy of the settings (configuration keys with ':'); change it freely.</summary>
    public Dictionary<string, string?> Settings() => new(settings, StringComparer.Ordinal);

    /// <summary>The same settings as environment variables ('__' for ':'), as the host injects them.</summary>
    public Dictionary<string, string> EnvironmentVariables() =>
        settings.Where(p => p.Value is not null).ToDictionary(p => p.Key.Replace(":", "__", StringComparison.Ordinal), p => p.Value!, StringComparer.Ordinal);

    /// <summary>The 32 bytes of a symmetric key.</summary>
    public byte[] Secret(string name) => secrets[name];

    /// <summary>Sets <c>ZAGHLOL_KEYS:&lt;name&gt;</c> to a signing key and pins it.</summary>
    public void SetSigningKey(string name, ECDsa key)
    {
        var pem = key.ExportPkcs8PrivateKeyPem() + "\n";
        settings["ZAGHLOL_KEYS:" + name] = Value(name, "pem", pem);
        settings["Kms:File:Fingerprints:" + name] = Convert.ToHexStringLower(SHA256.HashData(key.ExportSubjectPublicKeyInfo()));
        sentinels.AddRange(pem.Split('\n').Where(l => l.Length >= 16 && !l.StartsWith("-----", StringComparison.Ordinal)));
        sentinels.Add(settings["ZAGHLOL_KEYS:" + name]!);
    }

    /// <summary>Sets <c>ZAGHLOL_KEYS:&lt;name&gt;</c> to a 32-byte key and pins it; for seat, also SeatCheck.</summary>
    public void SetSecret(string name, byte[] secret)
    {
        secrets[name] = secret;
        settings["ZAGHLOL_KEYS:" + name] = Value(name, "key", Convert.ToBase64String(secret));
        settings["Kms:File:Fingerprints:" + name] = Convert.ToHexStringLower(HMACSHA256.HashData(secret, "zaghlol-kms-file-fingerprint-v1"u8));
        if (name == "seat")
        {
            settings["Kms:HmacKeys:SeatCheck"] = Convert.ToHexStringLower(HMACSHA256.HashData(secret, "zaghlol-kseat-check-v1"u8));
        }

        sentinels.Add(Convert.ToBase64String(secret));
        sentinels.Add(Convert.ToHexStringLower(secret));
        sentinels.Add(Base64Url.EncodeToString(secret));
        sentinels.Add(settings["ZAGHLOL_KEYS:" + name]!);
    }

    /// <summary>A setting value: base64url of the host-key-v1 JSON (the format the key tool prints).</summary>
    public static string Value(string name, string member, string text) =>
        Base64Url.EncodeToString(Encoding.UTF8.GetBytes(Json(name, member, text)));

    /// <summary>The host-key-v1 JSON (only '\n' needs escaping in PEM and base64 text).</summary>
    public static string Json(string name, string member, string text) =>
        "{\"zaghlol\":\"host-key-v1\",\"name\":\"" + name + "\",\"" + member + "\":\"" + text.Replace("\n", "\\n", StringComparison.Ordinal) + "\"}";
}
