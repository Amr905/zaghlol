using Microsoft.EntityFrameworkCore;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// Applies pending migrations as the <c>migrator</c> login (<c>dotnet Zaghlol.Workers.dll --migrate</c>). EF's migration
/// lock serializes concurrent runs; EF refuses to run when the model has changes without a migration.
/// </summary>
public static class ZaghlolMigrator
{
    public static async Task MigrateAsync(string connectionString, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);

        await using var dataSource = ZaghlolDbContextOptions.CreateDataSource(connectionString, DatabaseRole.Migrator);
        await using var context = new ZaghlolDbContext(ZaghlolDbContextOptions.Create(dataSource));
        await context.Database.MigrateAsync(cancellationToken);
    }
}
