using System.Globalization;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>
/// The Apple call budget (T-131 §6, T-134 §6), a separate bucket from Play's (a different quota). The configured numbers are the
/// <b>total</b> over all processes: the worker takes <see cref="WorkerShare"/> of them, each of the <see cref="Replicas"/> API processes
/// <c>(1 − WorkerShare) / Replicas</c>. Apple publishes no fixed limits (it answers 429 per endpoint), so the defaults are conservative
/// and must be sized from observed 429s before go-live.
/// </summary>
/// <param name="Replicas">The number of <b>API</b> replicas (the worker runs its jobs on one replica through advisory locks).</param>
/// <param name="WorkerShare">The worker's fraction of the total, in (0, 1) (default 0.2).</param>
public sealed record AppleBudgetOptions(int TokenLimit, int TokensPerPeriod, TimeSpan Period, int Replicas, int VerifyPerInstallPerHour, decimal WorkerShare = AppleBudgetOptions.DefaultWorkerShare)
{
    public const decimal DefaultWorkerShare = 0.2m;

    public static AppleBudgetOptions Default { get; } = new(300, 60, TimeSpan.FromMinutes(1), 1, 10);

    public int PerReplicaLimit => Math.Max(1, (int)(TokenLimit * (1 - WorkerShare)) / Replicas);

    public int PerReplicaPerPeriod => Math.Max(1, (int)(TokensPerPeriod * (1 - WorkerShare)) / Replicas);

    public int WorkerLimit => Math.Max(1, (int)(TokenLimit * WorkerShare));

    public int WorkerPerPeriod => Math.Max(1, (int)(TokensPerPeriod * WorkerShare));
}

/// <summary>
/// <c>Purchases:Apple:*</c>, read and validated once at startup (T-131 design note §2-6). Outside Development and Testing a missing
/// bundle ID, product table, issuer, key ID or private key stops the host, and so does any base URL other than Apple's (FU-077 I-1)
/// or a test root. Production also needs <c>AllowSandbox</c> set explicitly (PO question 4), refuses a test bundle and refuses a
/// private key that a file-based configuration provider supplies (FU-077 I-4). Errors name the key, never a value.
/// </summary>
public sealed partial class AppStoreOptions
{
    public const string Section = "Purchases:Apple";
    public const string ProductionBaseUrl = "https://api.storekit.apple.com";
    public const string SandboxBaseUrl = "https://api.storekit-sandbox.apple.com";

    /// <summary>The three Gold products and the App Store kind each one must be (backend-api §4.3).</summary>
    public static IReadOnlyDictionary<GoldPlan, AppleProductType> PlanTypes { get; } = new Dictionary<GoldPlan, AppleProductType>
    {
        [GoldPlan.Monthly] = AppleProductType.AutoRenewable,
        [GoldPlan.Yearly] = AppleProductType.AutoRenewable,
        [GoldPlan.Lifetime] = AppleProductType.NonConsumable,
    };

    public required AppStoreCatalog Catalog { get; init; }

    public required Uri ProductionUrl { get; init; }

    public required Uri SandboxUrl { get; init; }

    /// <summary>App Store Connect issuer ID; <c>null</c> only in Development and Testing (then no Authorization header is sent).</summary>
    public string? IssuerId { get; init; }

    public string? KeyId { get; init; }

    /// <summary>The In-App Purchase key (PKCS#8 PEM) from the secrets manager. Never logged.</summary>
    public Sensitive<string>? PrivateKey { get; init; }

    /// <summary>Development and Testing only: a test PKI root that replaces the pinned Apple root.</summary>
    public byte[]? TestRoot { get; init; }

    public required AppleBudgetOptions Budget { get; init; }

    public required PlayResilienceOptions Resilience { get; init; }

    public bool HasCredential => PrivateKey is not null;

    /// <summary>The trust anchor: the test root in Development and Testing when configured, otherwise the pinned Apple Root CA - G3.</summary>
    public byte[] TrustAnchor() => TestRoot is { } test ? (byte[])test.Clone() : AppleRootCertificate.Der;

    /// <summary>Reads and validates the section; throws <see cref="AppStoreConfigurationException"/> naming the key, never a value.</summary>
    public static AppStoreOptions Read(IConfiguration configuration, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var section = configuration.GetSection(Section);
        var relaxed = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        var production = environment.IsProduction();

        var bundleId = section["BundleId"]?.Trim() ?? string.Empty;
        if (bundleId.Length == 0)
        {
            if (!relaxed)
            {
                throw new AppStoreConfigurationException("Purchases:Apple:BundleId must be set.");
            }
        }
        else if (!BundleIdRegex().IsMatch(bundleId))
        {
            throw new AppStoreConfigurationException("Purchases:Apple:BundleId is not a valid bundle ID.");
        }

        if (production && GooglePlayOptions.IsTestPackage(bundleId))
        {
            throw new AppStoreConfigurationException("Purchases:Apple:BundleId names a test bundle in Production.");
        }

        var products = ReadProducts(section.GetSection("Products"));
        if (products.Count == 0 && !relaxed)
        {
            throw new AppStoreConfigurationException("Purchases:Apple:Products must list the three Gold products.");
        }

        if (products.Count > 0)
        {
            if (products.Count != 3 || PlanTypes.Any(p => products.Values.Count(d => d.Plan == p.Key && d.Type == p.Value) != 1))
            {
                throw new AppStoreConfigurationException(
                    "Purchases:Apple:Products must hold exactly three products: monthly and yearly auto-renewable subscriptions and a lifetime non-consumable.");
            }

            if (bundleId.Length == 0)
            {
                throw new AppStoreConfigurationException("Purchases:Apple:BundleId must be set when products are configured.");
            }
        }

        var allowSandbox = section["AllowSandbox"] switch
        {
            "true" or "True" => true,
            "false" or "False" => false,
            null or "" when !production => true,
            null or "" => throw new AppStoreConfigurationException("Purchases:Apple:AllowSandbox must be set to true or false in Production (PO question 4)."),
            _ => throw new AppStoreConfigurationException("Purchases:Apple:AllowSandbox must be true or false."),
        };

        var productionUrl = ReadBaseUrl(section, "ProductionBaseUrl", ProductionBaseUrl, relaxed);
        var sandboxUrl = ReadBaseUrl(section, "SandboxBaseUrl", SandboxBaseUrl, relaxed);

        var issuerId = Blank(section["IssuerId"]);
        var keyId = Blank(section["KeyId"]);
        var privateKey = Blank(section["PrivateKey"]);
        var present = new[] { issuerId, keyId, privateKey }.Count(v => v is not null);
        if (present != 3 && (present != 0 || !relaxed))
        {
            throw new AppStoreConfigurationException("Purchases:Apple:IssuerId, KeyId and PrivateKey must all be set (In-App Purchase key from the secrets manager).");
        }

        if (issuerId is not null && !Guid.TryParseExact(issuerId, "D", out _))
        {
            throw new AppStoreConfigurationException("Purchases:Apple:IssuerId must be the App Store Connect issuer UUID.");
        }

        if (keyId is not null && !KeyIdRegex().IsMatch(keyId))
        {
            throw new AppStoreConfigurationException("Purchases:Apple:KeyId must be the 10-character App Store Connect key ID.");
        }

        if (privateKey is not null)
        {
            // Proves the PEM is a P-256 key now, so a bad secret stops startup instead of the first purchase.
            using var probe = AppStoreApiTokenProvider.LoadKey(privateKey);
            if (production && IsFromFileProvider(configuration, Section + ":PrivateKey"))
            {
                throw new AppStoreConfigurationException("Purchases:Apple:PrivateKey must come from the secrets manager, not a configuration file.");
            }
        }

        byte[]? testRoot = null;
        if (Blank(section["TestRootCertificate"]) is { } testRootText)
        {
            if (!relaxed)
            {
                throw new AppStoreConfigurationException("Purchases:Apple:TestRootCertificate is allowed only in Development and Testing.");
            }

            try
            {
                testRoot = Convert.FromBase64String(testRootText);
            }
            catch (FormatException error)
            {
                throw new AppStoreConfigurationException("Purchases:Apple:TestRootCertificate must be base64 DER.", error);
            }
        }

        return new AppStoreOptions
        {
            Catalog = new AppStoreCatalog(bundleId, products, allowSandbox),
            ProductionUrl = productionUrl,
            SandboxUrl = sandboxUrl,
            IssuerId = issuerId,
            KeyId = keyId,
            PrivateKey = privateKey is null ? null : new Sensitive<string>(privateKey),
            TestRoot = testRoot,
            Budget = ReadBudget(section.GetSection("Budget"), relaxed),
            Resilience = relaxed ? ReadResilience(section.GetSection("Resilience")) : PlayResilienceOptions.Default,
        };
    }

    /// <summary>
    /// True when a file-based provider (JSON, XML, INI, user secrets: anything deriving from <c>FileConfigurationProvider</c>)
    /// holds <paramref name="key"/>. Checked by type name, so this assembly needs no file-provider package.
    /// </summary>
    internal static bool IsFromFileProvider(IConfiguration configuration, string key)
    {
        if (configuration is not IConfigurationRoot root)
        {
            return false;
        }

        foreach (var provider in root.Providers)
        {
            if (!provider.TryGet(key, out _))
            {
                continue;
            }

            for (var type = provider.GetType(); type is not null; type = type.BaseType)
            {
                if (type.FullName == "Microsoft.Extensions.Configuration.FileConfigurationProvider")
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static Uri ReadBaseUrl(IConfigurationSection section, string key, string apple, bool relaxed)
    {
        var text = section[key] is { Length: > 0 } configured ? configured : apple;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var url) || url.Query.Length > 0 || url.UserInfo.Length > 0
            || (url.Scheme != Uri.UriSchemeHttps && !(relaxed && url.Scheme == Uri.UriSchemeHttp)))
        {
            throw new AppStoreConfigurationException($"{Section}:{key} must be an absolute https URL.");
        }

        var normalized = url.GetLeftPart(UriPartial.Path).TrimEnd('/');
        if (!relaxed && !string.Equals(normalized, apple, StringComparison.Ordinal))
        {
            throw new AppStoreConfigurationException($"{Section}:{key} must be Apple's App Store Server API URL outside Development and Testing.");
        }

        return new Uri(normalized + "/");
    }

    private static Dictionary<string, AppStoreProductDefinition> ReadProducts(IConfigurationSection section)
    {
        var products = new Dictionary<string, AppStoreProductDefinition>(StringComparer.Ordinal);
        foreach (var product in section.GetChildren())
        {
            if (!ProductIdRegex().IsMatch(product.Key))
            {
                throw new AppStoreConfigurationException("Purchases:Apple:Products has an invalid product ID.");
            }

            var type = product["Type"] switch
            {
                "auto_renewable" => AppleProductType.AutoRenewable,
                "non_consumable" => AppleProductType.NonConsumable,
                _ => throw new AppStoreConfigurationException("Purchases:Apple:Products:<id>:Type must be 'auto_renewable' or 'non_consumable'."),
            };
            var plan = product["Plan"] switch
            {
                "monthly" => GoldPlan.Monthly,
                "yearly" => GoldPlan.Yearly,
                "lifetime" => GoldPlan.Lifetime,
                _ => throw new AppStoreConfigurationException("Purchases:Apple:Products:<id>:Plan must be 'monthly', 'yearly' or 'lifetime'."),
            };
            products[product.Key] = new AppStoreProductDefinition(type, plan);
        }

        return products;
    }

    private static AppleBudgetOptions ReadBudget(IConfigurationSection section, bool relaxed)
    {
        var d = AppleBudgetOptions.Default;
        return new AppleBudgetOptions(
            PositiveInt(section, "TokenLimit", d.TokenLimit),
            PositiveInt(section, "TokensPerPeriod", d.TokensPerPeriod),
            TimeSpan.FromSeconds(PositiveInt(section, "PeriodSeconds", (int)d.Period.TotalSeconds)),
            PositiveInt(section, "Replicas", d.Replicas),
            relaxed ? PositiveInt(section, "VerifyPerInstallPerHour", d.VerifyPerInstallPerHour) : d.VerifyPerInstallPerHour,
            Share(section, "WorkerShare", d.WorkerShare));
    }

    /// <summary>A fraction strictly between 0 and 1, invariant culture (for example <c>0.2</c>).</summary>
    private static decimal Share(IConfigurationSection section, string key, decimal fallback)
    {
        if (section[key] is not { Length: > 0 } text)
        {
            return fallback;
        }

        return decimal.TryParse(text, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value) && value is > 0m and < 1m
            ? value
            : throw new AppStoreConfigurationException($"{Section}:{section.Key}:{key} must be a fraction between 0 and 1.");
    }

    private static PlayResilienceOptions ReadResilience(IConfigurationSection section)
    {
        var d = PlayResilienceOptions.Default;
        return d with
        {
            AttemptTimeout = TimeSpan.FromMilliseconds(PositiveInt(section, "AttemptTimeoutMs", (int)d.AttemptTimeout.TotalMilliseconds)),
            TotalTimeout = TimeSpan.FromMilliseconds(PositiveInt(section, "TotalTimeoutMs", (int)d.TotalTimeout.TotalMilliseconds)),
            RetryBaseDelay = TimeSpan.FromMilliseconds(PositiveInt(section, "RetryBaseDelayMs", (int)d.RetryBaseDelay.TotalMilliseconds)),
            BreakDuration = TimeSpan.FromMilliseconds(PositiveInt(section, "BreakDurationMs", (int)d.BreakDuration.TotalMilliseconds)),
            MinimumThroughput = Math.Max(2, PositiveInt(section, "MinimumThroughput", d.MinimumThroughput)),
            SamplingDuration = TimeSpan.FromMilliseconds(Math.Max(500, PositiveInt(section, "SamplingDurationMs", (int)d.SamplingDuration.TotalMilliseconds))),
        };
    }

    private static int PositiveInt(IConfigurationSection section, string key, int fallback)
    {
        if (section[key] is not { Length: > 0 } text)
        {
            return fallback;
        }

        return int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var value) && value > 0
            ? value
            : throw new AppStoreConfigurationException($"{Section}:{section.Key}:{key} must be a positive integer.");
    }

    [GeneratedRegex(@"^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+\z", RegexOptions.CultureInvariant)]
    private static partial Regex BundleIdRegex();

    [GeneratedRegex(@"^[A-Z0-9]{10}\z", RegexOptions.CultureInvariant)]
    private static partial Regex KeyIdRegex();

    // The OpenAPI productId pattern (^[a-z0-9_.]{3,100}$), anchored with \z.
    [GeneratedRegex(@"^[a-z0-9_.]{3,100}\z", RegexOptions.CultureInvariant)]
    private static partial Regex ProductIdRegex();
}

/// <summary>The one EC P-256 check of the Apple code (the API key and the JWS leaf key).</summary>
internal static class AppleKeyText
{
    public static bool IsP256(ECDsa key)
    {
        var curve = key.ExportParameters(false).Curve;
        return key.KeySize == 256 && curve.IsNamed
            && (curve.Oid.Value == "1.2.840.10045.3.1.7" || curve.Oid.FriendlyName is "nistP256" or "ECDSA_P256" or "secp256r1" or "prime256v1");
    }
}
