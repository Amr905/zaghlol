using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Npgsql;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The <c>Database:*</c> settings (T-207, Aiven for PostgreSQL): TLS trust, the production transport guard and pool sizes.
/// <list type="bullet">
/// <item><c>Database:CaCertificatePem</c> or <c>Database:CaCertificatePath</c>: the provider's CA (Aiven project CA) used to
/// verify the server with <c>SSL Mode=VerifyFull</c> / <c>VerifyCA</c>. A PEM may carry literal <c>\n</c> (one-line secrets).</item>
/// <item><c>Database:AllowInsecureTransport</c>: Production refuses <c>Disable</c>/<c>Allow</c>/<c>Prefer</c>/<c>Require</c> unless this
/// is <c>true</c> (self-hosted compose: the database is on a private bridge network and not published).</item>
/// <item><c>Database:MaxPoolSize:App|Admin|Worker|Migrator</c>: overrides the pool size of a role; otherwise the connection
/// string's <c>Maximum Pool Size</c>, otherwise <see cref="DefaultMaxPoolSize"/>.</item>
/// </list>
/// Connection budget on the Aiven free plan (max_connections 20, about 6 reserved): API 5 + Admin 1 + readiness 1 + Worker 3 = 10 at
/// runtime, migrator 2 only during a deploy, leaving about 2 for an operator's psql.
/// </summary>
public sealed class DatabaseSettings
{
    public const string SectionName = "Database";

    public string? CaCertificatePem { get; set; }

    public string? CaCertificatePath { get; set; }

    public bool AllowInsecureTransport { get; set; }

    public Dictionary<string, int> MaxPoolSize { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Pool defaults for the free plan (see the class remarks).</summary>
    public static int DefaultMaxPoolSize(DatabaseRole role) => role switch
    {
        DatabaseRole.App => 5,
        DatabaseRole.Admin => 1,
        DatabaseRole.Worker => 3,
        DatabaseRole.Migrator => 2,
        _ => throw new ArgumentOutOfRangeException(nameof(role), role, null),
    };

    public static DatabaseSettings From(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var settings = new DatabaseSettings();
        configuration.GetSection(SectionName).Bind(settings);
        return settings;
    }

    public bool HasCaCertificate =>
        !string.IsNullOrWhiteSpace(CaCertificatePem) || !string.IsNullOrWhiteSpace(CaCertificatePath);

    /// <summary>The configured pool size for a role, or null when only the connection string / default applies.</summary>
    public int? PoolOverride(DatabaseRole role) =>
        MaxPoolSize.TryGetValue(DatabaseRoles.ConnectionStringName(role), out var size) ? size : null;

    /// <summary>The trusted CA certificates, or null when none is configured (system trust store).</summary>
    public X509Certificate2Collection? LoadCaCertificates()
    {
        string pem;
        if (!string.IsNullOrWhiteSpace(CaCertificatePem))
        {
            pem = CaCertificatePem.Replace("\\n", "\n", StringComparison.Ordinal);
        }
        else if (!string.IsNullOrWhiteSpace(CaCertificatePath))
        {
            pem = File.ReadAllText(CaCertificatePath);
        }
        else
        {
            return null;
        }

        var collection = new X509Certificate2Collection();
        collection.ImportFromPem(pem);
        if (collection.Count == 0)
        {
            throw new InvalidOperationException("The configured database CA certificate holds no PEM certificate.");
        }

        return collection;
    }

    /// <summary>FU-278: the verified-TLS guard applies to every deployed environment (Production and Staging), not to Development or Testing.</summary>
    public static bool RequiresVerifiedTls(IHostEnvironment? environment) =>
        environment is not null && (environment.IsProduction() || environment.IsStaging());

    /// <summary>Configuration errors (empty when fine). Messages never contain connection strings or certificate text.</summary>
    public IReadOnlyList<string> Validate(IEnumerable<(DatabaseRole Role, string? ConnectionString)> connections, bool production)
    {
        ArgumentNullException.ThrowIfNull(connections);
        var errors = new List<string>();

        if (!string.IsNullOrWhiteSpace(CaCertificatePem) && !string.IsNullOrWhiteSpace(CaCertificatePath))
        {
            errors.Add("Set only one of Database:CaCertificatePem and Database:CaCertificatePath.");
        }
        else if (HasCaCertificate)
        {
            try
            {
                LoadCaCertificates();
            }
            catch (Exception ex) when (ex is InvalidOperationException or IOException or UnauthorizedAccessException
                or System.Security.Cryptography.CryptographicException or ArgumentException)
            {
                errors.Add($"Database CA certificate cannot be loaded ({ex.GetType().Name}).");
            }
        }

        foreach (var (role, connectionString) in connections)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                continue;
            }

            var name = DatabaseRoles.ConnectionStringName(role);
            SslMode mode;
            try
            {
                mode = new NpgsqlConnectionStringBuilder(connectionString).SslMode;
            }
            catch (ArgumentException)
            {
                errors.Add($"ConnectionStrings:{name} is not a valid connection string.");
                continue;
            }

            var verifies = mode is SslMode.VerifyCA or SslMode.VerifyFull;
            if (HasCaCertificate && !verifies)
            {
                errors.Add($"ConnectionStrings:{name} must use SSL Mode=VerifyFull (or VerifyCA) when a database CA certificate is configured.");
            }

            if (production && !verifies && !AllowInsecureTransport)
            {
                errors.Add($"ConnectionStrings:{name} must use SSL Mode=VerifyFull or VerifyCA in Production and Staging (or set Database:AllowInsecureTransport=true for a private network).");
            }

            if (PoolOverride(role) is int size && size < 1)
            {
                errors.Add($"Database:MaxPoolSize:{name} must be at least 1.");
            }
        }

        return errors;
    }
}
