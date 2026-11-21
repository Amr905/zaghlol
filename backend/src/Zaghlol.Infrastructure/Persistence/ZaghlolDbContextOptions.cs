using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Npgsql.EntityFrameworkCore.PostgreSQL.Infrastructure;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>The single place where the EF provider is configured (runtime, migration job and design time).</summary>
public static class ZaghlolDbContextOptions
{
    public static DbContextOptions<ZaghlolDbContext> Create(NpgsqlDataSource dataSource)
    {
        ArgumentNullException.ThrowIfNull(dataSource);

        return new DbContextOptionsBuilder<ZaghlolDbContext>().UseNpgsql(dataSource, ConfigureNpgsql).Options;
    }

    public static DbContextOptions<ZaghlolDbContext> Create(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);

        return new DbContextOptionsBuilder<ZaghlolDbContext>().UseNpgsql(connectionString, ConfigureNpgsql).Options;
    }

    public static NpgsqlDataSource CreateDataSource(string connectionString, DatabaseRole role, DatabaseSettings? settings = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);

        if (IncludesErrorDetail(connectionString))
        {
            throw new ArgumentException("Include Error Detail must not be set: server error details carry row values (FU-025).", nameof(connectionString));
        }

        var builder = new NpgsqlDataSourceBuilder(connectionString);
        builder.ConnectionStringBuilder.ApplicationName = DatabaseRoles.ApplicationName(role);
        ApplySettings(builder, role, settings);
        return builder.Build();
    }

    /// <summary>
    /// T-207: the pool size (setting, else the connection string, else the free-plan default) and the provider CA that
    /// <c>SSL Mode=VerifyFull|VerifyCA</c> verifies against.
    /// </summary>
    public static void ApplySettings(NpgsqlDataSourceBuilder builder, DatabaseRole role, DatabaseSettings? settings)
    {
        ArgumentNullException.ThrowIfNull(builder);

        var connection = builder.ConnectionStringBuilder;
        var explicitPool = connection.ShouldSerialize("Maximum Pool Size");
        if (settings?.PoolOverride(role) is int size)
        {
            connection.MaxPoolSize = size;
        }
        else if (!explicitPool)
        {
            connection.MaxPoolSize = DatabaseSettings.DefaultMaxPoolSize(role);
        }

        if (settings?.LoadCaCertificates() is { } roots)
        {
            builder.UseRootCertificates(roots);
        }
    }

    /// <summary>
    /// FU-025: <c>Include Error Detail=true</c> makes Npgsql put the server's DETAIL (for a CHECK failure, "Failing row
    /// contains (…)", i.e. row values) into exception messages, which the API logs. Runtime and migration logins never set it.
    /// </summary>
    public static bool IncludesErrorDetail(string? connectionString) =>
        !string.IsNullOrWhiteSpace(connectionString) && new NpgsqlConnectionStringBuilder(connectionString).IncludeErrorDetail;

    private static void ConfigureNpgsql(NpgsqlDbContextOptionsBuilder npgsql) =>
        npgsql.MigrationsHistoryTable(HistoryRepository.DefaultTableName, ZaghlolDbContext.Schema);
}

/// <summary>
/// Used only by <c>dotnet ef</c> (migrations add, has-pending-model-changes). It never opens a connection.
/// </summary>
public sealed class ZaghlolDesignTimeDbContextFactory : IDesignTimeDbContextFactory<ZaghlolDbContext>
{
    public ZaghlolDbContext CreateDbContext(string[] args) =>
        new(ZaghlolDbContextOptions.Create("Host=localhost;Database=zaghlol_design_time"));
}

/// <summary>Configuration names of <see cref="DatabaseRole"/>.</summary>
public static class DatabaseRoles
{
    /// <summary>Keyed-service key of the readiness probe's own one-connection data source (App credentials).</summary>
    public const string ReadinessDataSourceKey = "zaghlol-readiness";

    /// <summary>The <c>ConnectionStrings</c> key of a role.</summary>
    public static string ConnectionStringName(DatabaseRole role) => role switch
    {
        DatabaseRole.App => "App",
        DatabaseRole.Admin => "Admin",
        DatabaseRole.Worker => "Worker",
        DatabaseRole.Migrator => "Migrator",
        _ => throw new ArgumentOutOfRangeException(nameof(role), role, null),
    };

    /// <summary>The <c>application_name</c> the connection reports (visible in <c>pg_stat_activity</c>).</summary>
    public static string ApplicationName(DatabaseRole role) => role switch
    {
        DatabaseRole.App => "zaghlol-api",
        DatabaseRole.Admin => "zaghlol-admin",
        DatabaseRole.Worker => "zaghlol-worker",
        DatabaseRole.Migrator => "zaghlol-migrator",
        _ => throw new ArgumentOutOfRangeException(nameof(role), role, null),
    };
}
