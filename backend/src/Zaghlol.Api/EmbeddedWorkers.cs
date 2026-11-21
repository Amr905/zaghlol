using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Workers;

namespace Zaghlol.Api;

/// <summary>
/// Hosting profile for one IIS site (MonsterASP.NET, T-206, D-80): there is no second always-on process, so the worker jobs run
/// inside the API process. Off by default (the two-process layout of the container image keeps working).
/// </summary>
internal static class EmbeddedWorkers
{
    public const string EnabledKey = "Hosting:EmbeddedWorkers";

    /// <summary>The operator states that a separate worker process also runs against this database (a configuration mistake).</summary>
    public const string SeparateWorkerKey = "Hosting:SeparateWorkerRunning";

    private const string SnapshotDirectoryKey = "Catalog:Snapshots:Directory";

    /// <summary>
    /// With the embedded profile the catalog snapshots default to <c>&lt;content root&gt;/App_Data/catalog-snapshots</c>: writable on the
    /// site, hidden from static serving by <c>web.config</c>, and kept across deploys by the Web Deploy skip rule. An explicit
    /// <c>Catalog:Snapshots:Directory</c> wins; <c>Catalog:Snapshots:BaseUrl</c> (the site URL) is always supplied by the operator.
    /// </summary>
    public static void ApplyDefaults(ConfigurationManager configuration, string contentRootPath)
    {
        if (!IsEnabled(configuration) || !string.IsNullOrWhiteSpace(configuration[SnapshotDirectoryKey]))
        {
            return;
        }

        configuration.AddInMemoryCollection(
            new Dictionary<string, string?>
            {
                [SnapshotDirectoryKey] = Path.Combine(contentRootPath, "App_Data", "catalog-snapshots"),
            });
    }

    public static bool IsEnabled(IConfiguration configuration) => configuration.GetValue<bool>(EnabledKey);

    /// <summary>The database roles the API opens: App and Admin always, plus Worker when the jobs are embedded.</summary>
    public static DatabaseRole[] DatabaseRoles(IConfiguration configuration) =>
        IsEnabled(configuration)
            ? [DatabaseRole.App, DatabaseRole.Admin, DatabaseRole.Worker]
            : [DatabaseRole.App, DatabaseRole.Admin];

    /// <summary>
    /// Registers the worker jobs when <see cref="EnabledKey"/> is true. Refuses to start (constant message) when
    /// <see cref="SeparateWorkerKey"/> is also true: the advisory-locked jobs (Play/Apple processors and sweepers) would stay
    /// safe, but the price, contribution and retention jobs would run twice, so one of the two must be turned off.
    /// </summary>
    public static IServiceCollection AddEmbeddedWorkersIfEnabled(this IServiceCollection services, IConfiguration configuration)
    {
        if (!IsEnabled(configuration))
        {
            return services;
        }

        if (configuration.GetValue<bool>(SeparateWorkerKey))
        {
            throw new EmbeddedWorkersConfigurationException();
        }

        return services.AddZaghlolWorkerJobs();
    }
}

/// <summary>Both the embedded jobs and a separate worker process are declared. Constant message.</summary>
public sealed class EmbeddedWorkersConfigurationException()
    : SafeException("Hosting:EmbeddedWorkers=true and Hosting:SeparateWorkerRunning=true: run the worker jobs in one place only.");
