using System.Collections.Concurrent;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Npgsql;
using Zaghlol.Application.Health;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>Creates <see cref="ZaghlolDbContext"/> instances bound to one database login.</summary>
public interface IZaghlolDbContextFactory
{
    /// <summary>A new context on the given role's connection pool. The caller disposes it.</summary>
    ZaghlolDbContext CreateDbContext(DatabaseRole role);
}

/// <summary>Connection strings by role, read from <c>ConnectionStrings:App|Admin|Worker</c>.</summary>
public sealed class DatabaseConnectionOptions
{
    public Dictionary<DatabaseRole, string?> ConnectionStrings { get; } = [];

    public string? For(DatabaseRole role) => ConnectionStrings.GetValueOrDefault(role);
}

public static class PersistenceServiceCollectionExtensions
{
    /// <summary>
    /// Registers one pooled <see cref="NpgsqlDataSource"/> per role (keyed by <see cref="DatabaseRole"/>) and
    /// <see cref="IZaghlolDbContextFactory"/>. Each role's connection string is required and checked at startup.
    /// The API registers <see cref="DatabaseRole.App"/> for <c>/v1/*</c> and <see cref="DatabaseRole.Admin"/> for
    /// <c>/admin/v1/*</c>; workers register <see cref="DatabaseRole.Worker"/>. The migrator role is never registered:
    /// only the migration job (<see cref="ZaghlolMigrator"/>) uses it.
    /// </summary>
    public static IServiceCollection AddZaghlolDatabase(this IServiceCollection services, params DatabaseRole[] roles)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(roles);
        if (roles.Length == 0 || roles.Contains(DatabaseRole.Migrator))
        {
            throw new ArgumentException("Register at least one runtime role; the migrator role is not a runtime role.", nameof(roles));
        }

        var required = roles.Distinct().ToArray();
        var names = string.Join(", ", required.Select(r => $"ConnectionStrings:{DatabaseRoles.ConnectionStringName(r)}"));

        services.AddOptions<DatabaseConnectionOptions>()
            .Configure<IConfiguration>((options, configuration) =>
            {
                foreach (var role in required)
                {
                    options.ConnectionStrings[role] = configuration.GetConnectionString(DatabaseRoles.ConnectionStringName(role));
                }
            })
            .Validate(options => required.All(r => !string.IsNullOrWhiteSpace(options.For(r))), $"{names} must be set.")
            .ValidateOnStart();

        foreach (var role in required)
        {
            services.TryAddKeyedSingleton(role, (provider, _) =>
                ZaghlolDbContextOptions.CreateDataSource(
                    provider.GetRequiredService<IOptions<DatabaseConnectionOptions>>().Value.For(role)!,
                    role));
        }

        services.TryAddSingleton<IZaghlolDbContextFactory, ZaghlolDbContextFactory>();

        // SEC F11: stop the process if any of these logins is privileged, the owner, or in the wrong group.
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, DatabaseRoleGuardService>());
        return services;
    }

    /// <summary>
    /// Readiness of the <see cref="DatabaseRole.App"/> database for <c>GET /v1/health</c> (FU-003), probed on a
    /// one-connection pool of its own built from <c>ConnectionStrings:App</c>. Call after
    /// <see cref="AddZaghlolDatabase"/> with <see cref="DatabaseRole.App"/>.
    /// </summary>
    public static IServiceCollection AddDatabaseReadiness(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddKeyedSingleton(PostgresDatabaseReadiness.DataSourceKey, (provider, _) =>
            PostgresDatabaseReadiness.CreateProbeSource(
                provider.GetRequiredService<IOptions<DatabaseConnectionOptions>>().Value.For(DatabaseRole.App)
                ?? throw new InvalidOperationException("ConnectionStrings:App must be set for the readiness probe.")));
        services.TryAddSingleton<IDatabaseReadiness, PostgresDatabaseReadiness>();
        return services;
    }

    private sealed class ZaghlolDbContextFactory(IServiceProvider services) : IZaghlolDbContextFactory
    {
        private readonly ConcurrentDictionary<DatabaseRole, DbContextOptions<ZaghlolDbContext>> options = new();

        public ZaghlolDbContext CreateDbContext(DatabaseRole role) =>
            new(options.GetOrAdd(
                role,
                r => ZaghlolDbContextOptions.Create(services.GetRequiredKeyedService<NpgsqlDataSource>(r))));
    }
}
