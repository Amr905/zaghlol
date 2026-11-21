using System.Diagnostics;
using Npgsql;
using Testcontainers.PostgreSql;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// T-207 (AC3, AC4): the role bootstrap and the migrations work when the administrator is NOT a superuser, like Aiven's
/// <c>avnadmin</c> (LOGIN CREATEROLE CREATEDB, owner of the database). A real PostgreSQL 17 container.
/// </summary>
public sealed class ManagedPostgresBootstrapTests : IAsyncLifetime
{
    private const string Database = "defaultdb";
    private const string AdminPassword = "avnadmin-test-password";
    private PostgreSqlContainer container = null!;

    public async Task InitializeAsync()
    {
        container = new PostgreSqlBuilder().WithImage("postgres:17").WithDatabase("postgres").Build();
        await container.StartAsync();
        await ZaghlolTestDatabase.ExecuteAsync(Connection("postgres", "postgres"), "CREATE ROLE avnadmin LOGIN CREATEROLE CREATEDB PASSWORD '" + AdminPassword + "'");
        await ZaghlolTestDatabase.ExecuteAsync(Connection("postgres", "postgres"), $"CREATE DATABASE {Database} OWNER avnadmin");
    }

    public async Task DisposeAsync() => await container.DisposeAsync();

    [Fact]
    public async Task TheSqlBootstrapRunsAsANonSuperuserIsIdempotentAndLeavesLeastPrivilegeRoles()
    {
        Assert.Equal("off", await ScalarAsync(Admin(), "SHOW is_superuser"));
        var script = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "db", "bootstrap-roles.sql"));

        await ZaghlolTestDatabase.ExecuteAsync(Admin(), script);
        await ZaghlolTestDatabase.ExecuteAsync(Admin(), script);

        await AssertRolesAsync();
    }

    [Fact]
    public async Task TheMigrationsApplyAsTheMigratorAndTheApiLoginWorks()
    {
        var script = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "db", "bootstrap-roles.sql"));
        await ZaghlolTestDatabase.ExecuteAsync(Admin(), script);
        await ZaghlolTestDatabase.ExecuteAsync(Admin(), "ALTER ROLE migrator PASSWORD 'migrator-pw-1'; ALTER ROLE zaghlol_api PASSWORD 'api-pw-1'");

        await ZaghlolMigrator.MigrateAsync(Connection("migrator", "migrator-pw-1", Database), CancellationToken.None);

        Assert.Equal("migrator", await ScalarAsync(Admin(), "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'zaghlol'"));
        Assert.Equal("zaghlol_api", await ScalarAsync(Connection("zaghlol_api", "api-pw-1", Database), "SELECT current_user"));
    }

    [Fact]
    public async Task TheAivenScriptSetsPasswordsAndRunsTwice()
    {
        if (!CommandExists("bash") || !CommandExists("psql"))
        {
            return; // CI (ubuntu) has both; a developer machine without psql skips this one.
        }

        var scriptPath = Path.Combine(AppContext.BaseDirectory, "db", "aiven-bootstrap.sh");
        var builder = new NpgsqlConnectionStringBuilder(container.GetConnectionString());
        var uri = $"postgres://avnadmin:{AdminPassword}@{builder.Host}:{builder.Port}/{Database}";
        var environment = new Dictionary<string, string>
        {
            ["ZAGHLOL_ADMIN_URI"] = uri,
            ["ZAGHLOL_BOOTSTRAP_ALLOW_NO_TLS"] = "1",
            ["ZAGHLOL_MIGRATOR_PASSWORD"] = "migrator-script-password-0001",
            ["ZAGHLOL_API_PASSWORD"] = "api-script-password-0000000002",
            ["ZAGHLOL_ADMIN_API_PASSWORD"] = "admin-script-password-00000003",
            ["ZAGHLOL_WORKER_PASSWORD"] = "worker-script-password-0000004",
        };

        Assert.Equal(0, await RunAsync("bash", [scriptPath], environment));
        Assert.Equal(0, await RunAsync("bash", [scriptPath], environment));
        Assert.Equal(0, await RunAsync("bash", [scriptPath, "--passwords-only"], environment));
        await AssertRolesAsync();
        await ZaghlolMigrator.MigrateAsync(Connection("migrator", "migrator-script-password-0001", Database), CancellationToken.None);

        // Without verify-full (and without the test switch) the script refuses to run.
        environment.Remove("ZAGHLOL_BOOTSTRAP_ALLOW_NO_TLS");
        Assert.Equal(64, await RunAsync("bash", [scriptPath], environment));
    }

    private async Task AssertRolesAsync()
    {
        var privileged = await ScalarAsync(Admin(), """
            SELECT count(*) FROM pg_roles
            WHERE rolname IN ('migrator','zaghlol_api','zaghlol_admin','zaghlol_worker','zaghlol_ops_ro','app_rw','ops_rw','worker_rw','ops_ro')
              AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
            """);
        Assert.Equal("0", privileged);
        Assert.Equal("5", await ScalarAsync(Admin(), "SELECT count(*) FROM pg_roles WHERE rolcanlogin AND rolname IN ('migrator','zaghlol_api','zaghlol_admin','zaghlol_worker','zaghlol_ops_ro')"));
        Assert.Equal("4", await ScalarAsync(Admin(), "SELECT count(*) FROM pg_roles WHERE NOT rolcanlogin AND rolname IN ('app_rw','ops_rw','worker_rw','ops_ro')"));
        Assert.Equal("migrator", await ScalarAsync(Admin(), "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'zaghlol'"));
        Assert.Equal("app_rw", await ScalarAsync(Admin(), "SELECT string_agg(g.rolname, ',') FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid JOIN pg_roles u ON u.oid = m.member WHERE u.rolname = 'zaghlol_api'"));
    }

    private string Admin() => Connection("avnadmin", AdminPassword, Database);

    private string Connection(string user, string password, string database = "postgres") =>
        new NpgsqlConnectionStringBuilder(container.GetConnectionString()) { Username = user, Password = password, Database = database }.ConnectionString;

    private static async Task<string> ScalarAsync(string connectionString, string sql)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        return Convert.ToString(await command.ExecuteScalarAsync(), System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty;
    }

    private static bool CommandExists(string name) =>
        (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(Path.PathSeparator).Any(dir => File.Exists(Path.Combine(dir, name)));

    private static async Task<int> RunAsync(string file, string[] arguments, Dictionary<string, string> environment)
    {
        var info = new ProcessStartInfo(file) { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in arguments)
        {
            info.ArgumentList.Add(argument);
        }

        foreach (var (key, value) in environment)
        {
            info.Environment[key] = value;
        }

        using var process = Process.Start(info)!;
        await process.WaitForExitAsync();
        return process.ExitCode;
    }
}
