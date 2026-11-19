using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// BUG-009: <c>installs.catalog_version</c> is a catalog cursor and can't be negative. The API already refuses a negative
    /// <c>catalogVersion</c> (400); this puts the same rule in the database, like <c>ck_installs_platform</c>. Fails to apply only if a
    /// row already holds a negative value, which no API path can write.
    /// </summary>
    public partial class InstallsCatalogVersionNonNegative : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddCheckConstraint(
                name: "ck_installs_catalog_version",
                schema: "zaghlol",
                table: "installs",
                sql: "catalog_version >= 0");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_installs_catalog_version",
                schema: "zaghlol",
                table: "installs");
        }
    }
}
