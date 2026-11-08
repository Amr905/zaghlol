using System.Security.Cryptography;
using Npgsql;
using Testcontainers.PostgreSql;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Testing;

/// <summary>
/// A PostgreSQL 17 container prepared like production: <c>deploy/db/bootstrap-roles.sql</c> runs as superuser, each
/// login gets a random password, and the migrations are applied as <c>migrator</c>. Tests then connect as the
/// least-privilege logins, which also proves the grants are sufficient.
/// </summary>
public sealed class ZaghlolTestDatabase : IAsyncDisposable
{
    public const string DatabaseName = "zaghlol";

    public static readonly IReadOnlyList<string> Logins =
        ["migrator", "zaghlol_api", "zaghlol_admin", "zaghlol_worker", "zaghlol_ops_ro"];

    private readonly Dictionary<string, string> passwords = new(StringComparer.Ordinal);

    private ZaghlolTestDatabase(PostgreSqlContainer container) => Container = container;

    public PostgreSqlContainer Container { get; }

    public string Superuser => Container.GetConnectionString();

    public string Migrator => For("migrator");

    /// <summary><c>app_rw</c> (the <c>/v1</c> API).</summary>
    public string Api => For("zaghlol_api");

    /// <summary><c>ops_rw</c> (the admin API).</summary>
    public string Admin => For("zaghlol_admin");

    /// <summary><c>worker_rw</c>.</summary>
    public string Worker => For("zaghlol_worker");

    /// <summary><c>ops_ro</c>.</summary>
    public string OpsRo => For("zaghlol_ops_ro");

    /// <param name="hostPort">A fixed host port, for tests that stop and restart the container.</param>
    /// <param name="migrate">False to stop after the role bootstrap.</param>
    public static async Task<ZaghlolTestDatabase> StartAsync(int? hostPort = null, bool migrate = true)
    {
        var builder = new PostgreSqlBuilder().WithImage("postgres:17").WithDatabase(DatabaseName);
        if (hostPort is int port)
        {
            builder = builder.WithPortBinding(port, PostgreSqlBuilder.PostgreSqlPort);
        }

        var database = new ZaghlolTestDatabase(builder.Build());
        try
        {
            await database.Container.StartAsync();
            await database.BootstrapAsync();
            if (migrate)
            {
                await ZaghlolMigrator.MigrateAsync(database.Migrator, CancellationToken.None);
            }

            return database;
        }
        catch
        {
            await database.DisposeAsync();
            throw;
        }
    }

    public string For(string login)
    {
        var builder = new NpgsqlConnectionStringBuilder(Container.GetConnectionString())
        {
            Username = login,
            Password = passwords[login],
        };
        return builder.ConnectionString;
    }

    public static async Task ExecuteAsync(string connectionString, string sql)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync();
    }

    public async ValueTask DisposeAsync() => await Container.DisposeAsync();

    private async Task BootstrapAsync()
    {
        var script = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "db", "bootstrap-roles.sql"));
        await ExecuteAsync(Superuser, script);

        // Running it twice must be harmless (the provider admin may re-run it).
        await ExecuteAsync(Superuser, script);

        foreach (var login in Logins)
        {
            var password = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
            passwords[login] = password;
            await ExecuteAsync(Superuser, $"ALTER ROLE {login} PASSWORD '{password}'");
        }
    }
}
