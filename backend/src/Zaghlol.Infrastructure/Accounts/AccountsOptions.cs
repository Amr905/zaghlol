using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;

namespace Zaghlol.Infrastructure.Accounts;

public sealed class AccountsConfigurationException : SafeException
{
    public AccountsConfigurationException(string message)
        : base(message)
    {
    }
}

/// <summary>
/// <c>Accounts:*</c> (T-135 design note), read and validated once at startup. Outside Development and Testing the Google client IDs
/// (<c>Accounts:Google:ClientIds</c>), the Apple Services ID and bundle ID, the Sign in with Apple key (<c>TeamId</c>, <c>KeyId</c>,
/// <c>PrivateKey</c>, from the secrets manager, never a configuration file) and the Android package of the callback must be set, and the
/// Apple base URL must be Apple's. Errors name the key, never a value.
/// </summary>
public sealed partial class AccountsOptions
{
    public const string Section = "Accounts";

    public const string AppleProductionUrl = "https://appleid.apple.com";

    /// <summary>The OAuth client IDs (web, Android, iOS) Google ID tokens may carry as <c>aud</c>.</summary>
    public IReadOnlyList<string> GoogleClientIds { get; init; } = [];

    /// <summary>The Services ID (Android web flow) and the bundle ID (native iOS): the <c>aud</c> values Apple ID tokens may carry.</summary>
    public IReadOnlyList<string> AppleAudiences { get; init; } = [];

    public string? AppleTeamId { get; init; }

    public string? AppleKeyId { get; init; }

    /// <summary>The Sign in with Apple private key (PKCS#8 PEM). Never logged.</summary>
    public Sensitive<string>? ApplePrivateKey { get; init; }

    public Uri AppleBaseUrl { get; init; } = new(AppleProductionUrl);

    /// <summary>The <c>applicationId</c> the Android callback's <c>intent://</c> URL names.</summary>
    public string AndroidPackage { get; init; } = "app.zaghlol";

    public bool HasAppleKey => ApplePrivateKey is not null && AppleTeamId is not null && AppleKeyId is not null;

    public static AccountsOptions Read(IConfiguration configuration, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var relaxed = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        var production = !relaxed;
        var section = configuration.GetSection(Section);

        var google = List(section.GetSection("Google:ClientIds"));
        var servicesId = Blank(section["Apple:ServicesId"]);
        var bundleId = Blank(section["Apple:BundleId"]);
        var audiences = new[] { servicesId, bundleId }.Where(a => a is not null).Select(a => a!).Distinct(StringComparer.Ordinal).ToList();
        var teamId = Blank(section["Apple:TeamId"]);
        var keyId = Blank(section["Apple:KeyId"]);
        var privateKey = Blank(section["Apple:PrivateKey"]);
        var package = Blank(section["AndroidPackage"]) ?? Blank(configuration["Purchases:Google:PackageName"]);

        if (production)
        {
            if (google.Count == 0)
            {
                throw new AccountsConfigurationException("Accounts:Google:ClientIds must list the Google OAuth client IDs in Production.");
            }

            if (servicesId is null || bundleId is null)
            {
                throw new AccountsConfigurationException("Accounts:Apple:ServicesId and BundleId must be set in Production.");
            }

            if (teamId is null || keyId is null || privateKey is null)
            {
                throw new AccountsConfigurationException("Accounts:Apple:TeamId, KeyId and PrivateKey (Sign in with Apple key from the secrets manager) must be set in Production.");
            }

            if (package is null)
            {
                throw new AccountsConfigurationException("Accounts:AndroidPackage (or Purchases:Google:PackageName) must be set in Production.");
            }
        }

        if (google.Any(id => !ClientIdRegex().IsMatch(id)) || audiences.Any(id => !ClientIdRegex().IsMatch(id)))
        {
            throw new AccountsConfigurationException("Accounts: a client ID, Services ID or bundle ID has an invalid form.");
        }

        if ((teamId is not null || keyId is not null || privateKey is not null) && (teamId is null || keyId is null || privateKey is null))
        {
            throw new AccountsConfigurationException("Accounts:Apple:TeamId, KeyId and PrivateKey must all be set together.");
        }

        if ((teamId is not null && !AppleIdRegex().IsMatch(teamId)) || (keyId is not null && !AppleIdRegex().IsMatch(keyId)))
        {
            throw new AccountsConfigurationException("Accounts:Apple:TeamId and KeyId must be 10-character Apple identifiers.");
        }

        if (package is not null && !PackageRegex().IsMatch(package))
        {
            throw new AccountsConfigurationException("Accounts:AndroidPackage is not a valid Android package name.");
        }

        if (privateKey is not null)
        {
            // Proves the PEM is a P-256 key now, so a bad secret stops startup instead of the first deletion.
            using var probe = AppStoreApiTokenProvider.LoadKey(privateKey);
            if (production && AppStoreOptions.IsFromFileProvider(configuration, Section + ":Apple:PrivateKey"))
            {
                throw new AccountsConfigurationException("Accounts:Apple:PrivateKey must come from the secrets manager, not a configuration file.");
            }
        }

        var baseUrl = new Uri(AppleProductionUrl);
        if (Blank(section["Apple:BaseUrl"]) is { } configured)
        {
            if (!relaxed)
            {
                throw new AccountsConfigurationException("Accounts:Apple:BaseUrl is allowed only in Development and Testing.");
            }

            baseUrl = Uri.TryCreate(configured, UriKind.Absolute, out var parsed) && parsed.Scheme is "http" or "https"
                ? parsed
                : throw new AccountsConfigurationException("Accounts:Apple:BaseUrl must be an absolute http(s) URL.");
        }

        return new AccountsOptions
        {
            GoogleClientIds = google,
            AppleAudiences = audiences,
            AppleTeamId = teamId,
            AppleKeyId = keyId,
            ApplePrivateKey = privateKey is null ? null : new Sensitive<string>(privateKey),
            AppleBaseUrl = baseUrl,
            AndroidPackage = package ?? "app.zaghlol",
        };
    }

    private static List<string> List(IConfigurationSection section) =>
        [.. section.GetChildren().Select(c => Blank(c.Value)).Where(v => v is not null).Select(v => v!).Distinct(StringComparer.Ordinal)];

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    [GeneratedRegex(@"^[A-Za-z0-9._:/-]{3,200}\z", RegexOptions.CultureInvariant)]
    private static partial Regex ClientIdRegex();

    [GeneratedRegex(@"^[A-Z0-9]{10}\z", RegexOptions.CultureInvariant)]
    private static partial Regex AppleIdRegex();

    [GeneratedRegex(@"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+\z", RegexOptions.CultureInvariant)]
    private static partial Regex PackageRegex();
}
