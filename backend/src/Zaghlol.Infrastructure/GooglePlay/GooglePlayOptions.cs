using System.Globalization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.GooglePlay;

/// <summary>Where the Play client's OAuth access token comes from (<c>Purchases:Google:CredentialSource</c>).</summary>
public enum PlayCredentialSource
{
    /// <summary>Development and Testing only: no Authorization header (the WireMock stand-in needs none).</summary>
    None,

    /// <summary>
    /// Preferred: Application Default Credentials, i.e. workload identity federation or the platform's service identity; no key
    /// in the deployment.
    /// </summary>
    ApplicationDefault,

    /// <summary>A service-account JSON key from the secrets manager (<c>Purchases__Google__Credential</c>), never a file in the repo.</summary>
    ServiceAccountJson,
}

/// <summary>The outbound budget (T-130 design note §2), per process: a token bucket shared by every lane.</summary>
public sealed record PlayBudgetOptions(int TokenLimit, int TokensPerPeriod, TimeSpan Period)
{
    /// <summary>About 187 K calls a day per process, under Play's default 200 K/day quota (PO question 4).</summary>
    public static PlayBudgetOptions Default { get; } = new(600, 130, TimeSpan.FromMinutes(1));
}

/// <summary>
/// The Play client's resilience pipeline (T-130 design note §2). Only Development and Testing may change the defaults
/// (<c>Purchases:Google:Resilience:*</c>); elsewhere the defaults are always used.
/// </summary>
public sealed record PlayResilienceOptions(
    TimeSpan AttemptTimeout,
    TimeSpan TotalTimeout,
    int MaxRetries,
    TimeSpan RetryBaseDelay,
    double FailureRatio,
    int MinimumThroughput,
    TimeSpan SamplingDuration,
    TimeSpan BreakDuration)
{
    public static PlayResilienceOptions Default { get; } = new(
        TimeSpan.FromSeconds(5),
        TimeSpan.FromSeconds(20),
        3,
        TimeSpan.FromMilliseconds(400),
        0.5,
        10,
        TimeSpan.FromSeconds(30),
        TimeSpan.FromSeconds(30));
}

/// <summary>
/// <c>Purchases:Google:*</c>, read and validated once at startup (T-130 design note §1 step 2 and §7). Outside Development and
/// Testing a missing package, product table or credential stops the host; Production also refuses a test package or test
/// product, any Play base URL other than Google's, and the <see cref="PlayCredentialSource.None"/> source. Values are never
/// echoed in the error.
/// </summary>
public sealed partial class GooglePlayOptions
{
    public const string Section = "Purchases:Google";
    public const string ProductionBaseUrl = "https://androidpublisher.googleapis.com";

    /// <summary>The three Gold products and the plan each one grants (backend-api §4.3).</summary>
    public static IReadOnlyDictionary<GoldPlan, PlayProductKind> PlanKinds { get; } = new Dictionary<GoldPlan, PlayProductKind>
    {
        [GoldPlan.Monthly] = PlayProductKind.Subscription,
        [GoldPlan.Yearly] = PlayProductKind.Subscription,
        [GoldPlan.Lifetime] = PlayProductKind.OneTime,
    };

    public required PlayProductCatalog Catalog { get; init; }

    public required Uri BaseUrl { get; init; }

    public required PlayCredentialSource CredentialSource { get; init; }

    /// <summary>The service-account JSON, only for <see cref="PlayCredentialSource.ServiceAccountJson"/>. Never logged.</summary>
    public Sensitive<string>? CredentialJson { get; init; }

    public required PlayOrderLookupPath OrderLookup { get; init; }

    public required PlayBudgetOptions Budget { get; init; }

    public required PlayResilienceOptions Resilience { get; init; }

    /// <summary>Reads and validates the section; throws <see cref="PlayConfigurationException"/> naming the key, never a value.</summary>
    public static GooglePlayOptions Read(IConfiguration configuration, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);

        var section = configuration.GetSection(Section);
        var relaxed = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        var production = environment.IsProduction();

        var packageName = section["PackageName"]?.Trim() ?? string.Empty;
        if (packageName.Length == 0)
        {
            if (!relaxed)
            {
                throw new PlayConfigurationException("Purchases:Google:PackageName must be set.");
            }
        }
        else if (!PackageNameRegex().IsMatch(packageName))
        {
            throw new PlayConfigurationException("Purchases:Google:PackageName is not a valid Android package name.");
        }

        var products = ReadProducts(section.GetSection("Products"));
        if (products.Count == 0 && !relaxed)
        {
            throw new PlayConfigurationException("Purchases:Google:Products must list the three Gold products.");
        }

        if (products.Count > 0)
        {
            // Exactly the three IDs: one per plan, subscriptions for monthly/yearly, a one-time product for lifetime.
            if (products.Count != 3 || PlanKinds.Any(p => products.Values.Count(d => d.Plan == p.Key && d.Kind == p.Value) != 1))
            {
                throw new PlayConfigurationException(
                    "Purchases:Google:Products must hold exactly three products: monthly and yearly subscriptions and a lifetime one-time product.");
            }

            if (packageName.Length == 0)
            {
                throw new PlayConfigurationException("Purchases:Google:PackageName must be set when products are configured.");
            }
        }

        if (production && (IsTestPackage(packageName) || products.Keys.Any(id => id.StartsWith("android.test.", StringComparison.Ordinal))))
        {
            throw new PlayConfigurationException("Purchases:Google names a test package or test product in Production.");
        }

        var baseText = section["BaseUrl"] is { Length: > 0 } configured ? configured : ProductionBaseUrl;
        if (!Uri.TryCreate(baseText, UriKind.Absolute, out var baseUrl) || baseUrl.Query.Length > 0 || baseUrl.UserInfo.Length > 0
            || (baseUrl.Scheme != Uri.UriSchemeHttps && !(relaxed && baseUrl.Scheme == Uri.UriSchemeHttp)))
        {
            throw new PlayConfigurationException("Purchases:Google:BaseUrl must be an absolute https URL.");
        }

        if (production && !string.Equals(baseUrl.GetLeftPart(UriPartial.Path).TrimEnd('/'), ProductionBaseUrl, StringComparison.Ordinal))
        {
            throw new PlayConfigurationException("Purchases:Google:BaseUrl must be the Google Play Developer API in Production.");
        }

        var credentialJson = section["Credential"];
        var source = ReadCredentialSource(section["CredentialSource"], credentialJson, relaxed);
        if (source == PlayCredentialSource.ServiceAccountJson && string.IsNullOrWhiteSpace(credentialJson))
        {
            throw new PlayConfigurationException("Purchases:Google:Credential must hold the service-account JSON for CredentialSource=ServiceAccountJson.");
        }

        var lookup = section["OrderLookup"] switch
        {
            null or "" or "fallback" => PlayOrderLookupPath.Fallback,
            "orders" => PlayOrderLookupPath.Orders,
            _ => throw new PlayConfigurationException("Purchases:Google:OrderLookup must be 'orders' or 'fallback'."),
        };

        return new GooglePlayOptions
        {
            Catalog = new PlayProductCatalog(packageName, products),
            BaseUrl = new Uri(baseUrl.GetLeftPart(UriPartial.Path).TrimEnd('/') + "/"),
            CredentialSource = source,
            CredentialJson = source == PlayCredentialSource.ServiceAccountJson ? new Sensitive<string>(credentialJson!) : null,
            OrderLookup = lookup,
            Budget = ReadBudget(section.GetSection("Budget")),
            Resilience = relaxed ? ReadResilience(section.GetSection("Resilience")) : PlayResilienceOptions.Default,
        };
    }

    /// <summary>A package that is clearly not the store build (a debug, dev, staging or test suffix or segment).</summary>
    internal static bool IsTestPackage(string packageName) =>
        packageName.Split('.').Any(segment => segment is "test" or "tests" or "debug" or "dev" or "staging" or "sandbox");

    private static Dictionary<string, PlayProductDefinition> ReadProducts(IConfigurationSection section)
    {
        var products = new Dictionary<string, PlayProductDefinition>(StringComparer.Ordinal);
        foreach (var product in section.GetChildren())
        {
            if (!ProductIdRegex().IsMatch(product.Key))
            {
                throw new PlayConfigurationException("Purchases:Google:Products has an invalid product ID.");
            }

            var kind = product["Kind"] switch
            {
                "subscription" => PlayProductKind.Subscription,
                "onetime" => PlayProductKind.OneTime,
                _ => throw new PlayConfigurationException("Purchases:Google:Products:<id>:Kind must be 'subscription' or 'onetime'."),
            };
            var plan = product["Plan"] switch
            {
                "monthly" => GoldPlan.Monthly,
                "yearly" => GoldPlan.Yearly,
                "lifetime" => GoldPlan.Lifetime,
                _ => throw new PlayConfigurationException("Purchases:Google:Products:<id>:Plan must be 'monthly', 'yearly' or 'lifetime'."),
            };
            products[product.Key] = new PlayProductDefinition(kind, plan);
        }

        return products;
    }

    private static PlayCredentialSource ReadCredentialSource(string? text, string? credentialJson, bool relaxed)
    {
        var source = text switch
        {
            null or "" => string.IsNullOrWhiteSpace(credentialJson) ? (PlayCredentialSource?)null : PlayCredentialSource.ServiceAccountJson,
            "ApplicationDefault" => PlayCredentialSource.ApplicationDefault,
            "ServiceAccountJson" => PlayCredentialSource.ServiceAccountJson,
            "None" when relaxed => PlayCredentialSource.None,
            _ => throw new PlayConfigurationException("Purchases:Google:CredentialSource must be 'ApplicationDefault' or 'ServiceAccountJson'."),
        };
        return source ?? (relaxed
            ? PlayCredentialSource.None
            : throw new PlayConfigurationException("Purchases:Google:CredentialSource must be set (ApplicationDefault preferred, or ServiceAccountJson)."));
    }

    private static PlayBudgetOptions ReadBudget(IConfigurationSection section)
    {
        var defaults = PlayBudgetOptions.Default;
        var limit = PositiveInt(section, "TokenLimit", defaults.TokenLimit);
        var perPeriod = PositiveInt(section, "TokensPerPeriod", defaults.TokensPerPeriod);
        var seconds = PositiveInt(section, "PeriodSeconds", (int)defaults.Period.TotalSeconds);
        return new PlayBudgetOptions(limit, perPeriod, TimeSpan.FromSeconds(seconds));
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
            : throw new PlayConfigurationException($"{Section}:{section.Key}:{key} must be a positive integer.");
    }

    [GeneratedRegex(@"^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+\z", RegexOptions.CultureInvariant)]
    private static partial Regex PackageNameRegex();

    // The OpenAPI productId pattern (^[a-z0-9_.]{3,100}$), anchored with \z.
    [GeneratedRegex(@"^[a-z0-9_.]{3,100}\z", RegexOptions.CultureInvariant)]
    private static partial Regex ProductIdRegex();
}

/// <summary>Invalid or missing <c>Purchases:Google</c> configuration. The message names the key, never a value.</summary>
public sealed class PlayConfigurationException : SafeException
{
    public PlayConfigurationException()
        : base("Purchases:Google is not configured correctly.")
    {
    }

    public PlayConfigurationException(string message)
        : base(message)
    {
    }

    public PlayConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
