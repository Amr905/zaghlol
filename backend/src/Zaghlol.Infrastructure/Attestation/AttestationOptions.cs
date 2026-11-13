using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Attestation;

/// <summary>
/// The pinned App Attest trust anchor (T-181 design note §6): Apple App Attestation Root CA, embedded as a resource. Its SHA-256
/// must equal <see cref="Sha256Fingerprint"/>; a missing or different resource throws, which stops startup.
/// Subject <c>CN=Apple App Attestation Root CA, O=Apple Inc., ST=California</c>, serial <c>0BF3BE0EF1CDD2E0FB8C6E721F621798</c>,
/// valid 2020-03-18 to 2045-03-15.
/// </summary>
public static class AppAttestRootCertificate
{
    public const string ResourceName = "Zaghlol.Attestation.AppleAppAttestationRootCA.cer";

    /// <summary>SHA-256 of the DER bytes, lower-case hex.</summary>
    public const string Sha256Fingerprint = "1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932";

    private static readonly Lazy<byte[]> Bytes = new(Load, LazyThreadSafetyMode.ExecutionAndPublication);

    /// <summary>A copy of the pinned DER bytes.</summary>
    public static byte[] Der => (byte[])Bytes.Value.Clone();

    public static byte[] Load() => Load(typeof(AppAttestRootCertificate).Assembly.GetManifestResourceStream(ResourceName), Sha256Fingerprint);

    internal static byte[] Load(Stream? resource, string expectedFingerprint)
    {
        if (resource is null)
        {
            throw new AttestationConfigurationException("The pinned Apple App Attestation Root CA resource is missing.");
        }

        using (resource)
        using (var buffer = new MemoryStream())
        {
            resource.CopyTo(buffer);
            var der = buffer.ToArray();
            if (!string.Equals(Convert.ToHexStringLower(SHA256.HashData(der)), expectedFingerprint, StringComparison.Ordinal))
            {
                throw new AttestationConfigurationException("The pinned Apple App Attestation Root CA resource does not match its fingerprint.");
            }

            return der;
        }
    }
}

/// <summary>App Attest settings (<c>Attestation:AppAttest:*</c> plus <c>Purchases:Apple:BundleId</c>).</summary>
public sealed class AppAttestOptions
{
    /// <summary><c>&lt;TeamID&gt;.&lt;bundleId&gt;</c>, whose SHA-256 is the RP ID hash.</summary>
    public required string AppId { get; init; }

    /// <summary>Accept the <c>appattestdevelop</c> AAGUID (staging builds). Refused in Production.</summary>
    public bool AllowDevelopment { get; init; }

    /// <summary>Development and Testing only: a test root that replaces the pinned Apple root.</summary>
    public byte[]? TestRoot { get; init; }

    public byte[] TrustAnchor() => TestRoot is { } test ? (byte[])test.Clone() : AppAttestRootCertificate.Der;
}

/// <summary>Play Integrity settings (<c>Attestation:PlayIntegrity:*</c>; package from <c>Purchases:Google:PackageName</c>).</summary>
public sealed class PlayIntegrityOptions
{
    public const string ProductionBaseUrl = "https://playintegrity.googleapis.com/";

    public required string PackageName { get; init; }

    public required Uri BaseUrl { get; init; }

    public TimeSpan TotalTimeout { get; init; } = TimeSpan.FromSeconds(10);

    public TimeSpan AttemptTimeout { get; init; } = TimeSpan.FromSeconds(4);
}

/// <summary>Reads and validates <c>Attestation:*</c>. Messages name the key, never a value.</summary>
public static partial class AttestationOptionsReader
{
    public const string Section = "Attestation";

    public static AppAttestOptions ReadAppAttest(IConfiguration configuration, IHostEnvironment environment, string bundleId)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var section = configuration.GetSection($"{Section}:AppAttest");
        var relaxed = Relaxed(environment);
        var teamId = section["TeamId"]?.Trim() ?? string.Empty;
        if (!TeamIdRegex().IsMatch(teamId))
        {
            if (!relaxed || teamId.Length != 0)
            {
                throw new AttestationConfigurationException("Attestation:AppAttest:TeamId must be a 10-character Apple Team ID.");
            }

            teamId = "TESTTEAM00";
        }

        if (bundleId.Length == 0 && !relaxed)
        {
            throw new AttestationConfigurationException("Purchases:Apple:BundleId must be set for App Attest.");
        }

        var allowDevelopment = section["AllowDevelopmentEnvironment"] switch
        {
            null or "" or "false" or "False" => false,
            "true" or "True" => true,
            _ => throw new AttestationConfigurationException("Attestation:AppAttest:AllowDevelopmentEnvironment must be true or false."),
        };
        if (allowDevelopment && environment.IsProduction())
        {
            throw new AttestationConfigurationException("Attestation:AppAttest:AllowDevelopmentEnvironment is not allowed in Production.");
        }

        byte[]? testRoot = null;
        if (section["TestRootCertificate"] is { Length: > 0 } text)
        {
            if (!relaxed)
            {
                throw new AttestationConfigurationException("Attestation:AppAttest:TestRootCertificate is allowed only in Development and Testing.");
            }

            try
            {
                testRoot = Convert.FromBase64String(text);
            }
            catch (FormatException e)
            {
                throw new AttestationConfigurationException("Attestation:AppAttest:TestRootCertificate must be base64 DER.", e);
            }
        }

        return new AppAttestOptions { AppId = $"{teamId}.{bundleId}", AllowDevelopment = allowDevelopment, TestRoot = testRoot };
    }

    public static PlayIntegrityOptions ReadPlayIntegrity(IConfiguration configuration, IHostEnvironment environment, string packageName)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var section = configuration.GetSection($"{Section}:PlayIntegrity");
        var relaxed = Relaxed(environment);
        var baseUrl = new Uri(PlayIntegrityOptions.ProductionBaseUrl);
        if (section["BaseUrl"] is { Length: > 0 } text)
        {
            if (!Uri.TryCreate(text, UriKind.Absolute, out var parsed) || (!relaxed && parsed != baseUrl))
            {
                throw new AttestationConfigurationException("Attestation:PlayIntegrity:BaseUrl must be Google's Play Integrity URL outside Development and Testing.");
            }

            baseUrl = new Uri(parsed.GetLeftPart(UriPartial.Path).TrimEnd('/') + "/");
        }

        if (packageName.Length == 0 && !relaxed)
        {
            throw new AttestationConfigurationException("Purchases:Google:PackageName must be set for Play Integrity.");
        }

        return new PlayIntegrityOptions { PackageName = packageName, BaseUrl = baseUrl };
    }

    private static bool Relaxed(IHostEnvironment environment) => environment.IsDevelopment() || environment.IsEnvironment("Testing");

    [GeneratedRegex(@"^[A-Z0-9]{10}\z", RegexOptions.CultureInvariant)]
    private static partial Regex TeamIdRegex();
}

/// <summary>Invalid or missing <c>Attestation</c> configuration or trust anchor.</summary>
public sealed class AttestationConfigurationException : SafeException
{
    public AttestationConfigurationException()
        : base("Attestation is not configured correctly.")
    {
    }

    public AttestationConfigurationException(string message)
        : base(message)
    {
    }

    public AttestationConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
