using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests;

[Collection(SchemaGroup.Name)]
public class MigrationTests(SchemaFixture fixture)
{
    private const string ObjectCountSql = """
        SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'zaghlol')
             + (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'zaghlol')
             + (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'zaghlol' AND NOT t.tgisinternal)
        """;

    [Fact]
    public async Task MigratingAgainIsANoOp()
    {
        var before = await Db.ScalarAsync(fixture.Database.Superuser, ObjectCountSql);
        var history = await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.\"__EFMigrationsHistory\"");

        await ZaghlolMigrator.MigrateAsync(fixture.Database.Migrator, CancellationToken.None);

        Assert.Equal(before, await Db.ScalarAsync(fixture.Database.Superuser, ObjectCountSql));
        Assert.Equal(history, await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.\"__EFMigrationsHistory\""));
        await using var context = new ZaghlolDbContext(ZaghlolDbContextOptions.Create(fixture.Database.Migrator));
        Assert.Empty(await context.Database.GetPendingMigrationsAsync());
        Assert.Equal(context.Database.GetMigrations().Count(), Convert.ToInt32(history, System.Globalization.CultureInfo.InvariantCulture));
    }

    [Fact]
    public void TheModelHasNoChangesMissingFromTheMigrations()
    {
        using var context = new ZaghlolDbContext(ZaghlolDbContextOptions.Create("Host=localhost;Database=unused"));

        Assert.NotEmpty(context.Database.GetMigrations());
        Assert.False(context.Database.HasPendingModelChanges());
    }

    [Fact]
    public async Task TheMigrationsHistoryLivesInTheZaghlolSchema()
    {
        var schema = await Db.ScalarAsync(
            fixture.Database.Superuser,
            "SELECT n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relname = '__EFMigrationsHistory'");

        Assert.Equal(ZaghlolDbContext.Schema, schema);
    }
}

/// <summary>Down() is never run in production, but it must work for local use; tested on a database of its own.</summary>
public class MigrationRoundTripTests : IAsyncLifetime
{
    private ZaghlolTestDatabase database = null!;

    public async Task InitializeAsync() => database = await ZaghlolTestDatabase.StartAsync();

    public async Task DisposeAsync() => await database.DisposeAsync();

    [Fact]
    public async Task DownToZeroRemovesEverythingAndUpRestoresIt()
    {
        const string objects = """
            SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'zaghlol' AND c.relkind IN ('r', 'v') AND c.relname NOT LIKE '\_\_EF%'
            """;
        var migrated = await Db.ScalarAsync(database.Superuser, objects);

        await using (var context = new ZaghlolDbContext(ZaghlolDbContextOptions.Create(database.Migrator)))
        {
            await context.GetService<IMigrator>().MigrateAsync(Migration.InitialDatabase);
        }

        Assert.Equal(0L, await Db.ScalarAsync(database.Superuser, objects));
        Assert.Equal(0L, await Db.ScalarAsync(
            database.Superuser,
            "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'zaghlol'"));

        await ZaghlolMigrator.MigrateAsync(database.Migrator, CancellationToken.None);

        Assert.Equal(migrated, await Db.ScalarAsync(database.Superuser, objects));
    }
}
