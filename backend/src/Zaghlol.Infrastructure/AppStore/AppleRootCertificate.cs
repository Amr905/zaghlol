using System.Security.Cryptography;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>
/// The pinned trust anchor of the Apple JWS verifier (T-131 design note §2 step 3): Apple Root CA - G3, embedded as a resource.
/// Its SHA-256 fingerprint must equal <see cref="Sha256Fingerprint"/>, the value Apple publishes (apple.com/certificateauthority
/// and support.apple.com "List of available root certificates", checked 2026-11-11: serial 2D C5 FC 88 D2 C5 4B 95, expires
/// 2039-04-30). A missing or different resource throws, which stops startup (<see cref="AppStoreStartupCheck"/>).
/// </summary>
public static class AppleRootCertificate
{
    public const string ResourceName = "Zaghlol.AppStore.AppleRootCA-G3.cer";

    /// <summary>SHA-256 of the DER bytes, lower-case hex.</summary>
    public const string Sha256Fingerprint = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

    private static readonly Lazy<byte[]> Bytes = new(Load, LazyThreadSafetyMode.ExecutionAndPublication);

    /// <summary>A copy of the pinned DER bytes.</summary>
    public static byte[] Der => (byte[])Bytes.Value.Clone();

    /// <summary>Reads the resource and checks its fingerprint; throws <see cref="AppStoreConfigurationException"/> otherwise.</summary>
    public static byte[] Load() => Load(typeof(AppleRootCertificate).Assembly.GetManifestResourceStream(ResourceName), Sha256Fingerprint);

    internal static byte[] Load(Stream? resource, string expectedFingerprint)
    {
        if (resource is null)
        {
            throw new AppStoreConfigurationException("The pinned Apple Root CA - G3 resource is missing.");
        }

        using (resource)
        using (var buffer = new MemoryStream())
        {
            resource.CopyTo(buffer);
            var der = buffer.ToArray();
            if (!string.Equals(Convert.ToHexStringLower(SHA256.HashData(der)), expectedFingerprint, StringComparison.Ordinal))
            {
                throw new AppStoreConfigurationException("The pinned Apple Root CA - G3 resource does not match its published fingerprint.");
            }

            return der;
        }
    }
}

/// <summary>Invalid or missing <c>Purchases:Apple</c> configuration or trust anchor. The message names the key, never a value.</summary>
public sealed class AppStoreConfigurationException : SafeException
{
    public AppStoreConfigurationException()
        : base("Purchases:Apple is not configured correctly.")
    {
    }

    public AppStoreConfigurationException(string message)
        : base(message)
    {
    }

    public AppStoreConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
