using Npgsql;
using Serilog;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Workers;

/// <summary>
/// <c>dotnet Zaghlol.Workers.dll --migrate</c>: the deploy-time migration job (same image as the worker). It connects as
/// the <c>migrator</c> login from <c>ConnectionStrings:Migrator</c>, applies pending migrations and exits.
/// </summary>
internal static class MigrateCommand
{
    public const string Flag = "--migrate";

    public static async Task<int> RunAsync(string[] args)
    {
        using var logger = new LoggerConfiguration().ConfigureZaghlol("migrate").CreateLogger();

        // The flag is not a configuration key; everything else (environment, appsettings) is read as usual.
        var builder = Host.CreateApplicationBuilder([.. args.Where(a => !string.Equals(a, Flag, StringComparison.Ordinal))]);
        var connectionString = builder.Configuration.GetConnectionString(DatabaseRoles.ConnectionStringName(DatabaseRole.Migrator));
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            logger.Error("ConnectionStrings:Migrator is not set");
            return 2;
        }

        using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(10));
        try
        {
            await ZaghlolMigrator.MigrateAsync(connectionString, cancellation.Token);
            logger.Information("Database migrations applied");
            return 0;
        }
#pragma warning disable CA1031 // Top-level job: any failure becomes a non-zero exit code for the deploy pipeline.
        catch (Exception ex)
#pragma warning restore CA1031
        {
            // Type and SQLSTATE only: driver messages can contain connection details.
            logger.Error(
                "Database migration failed ({ExceptionType}, SQLSTATE {SqlState})",
                ex.GetType().Name,
                (ex as PostgresException)?.SqlState ?? "n/a");
            return 1;
        }
    }
}
