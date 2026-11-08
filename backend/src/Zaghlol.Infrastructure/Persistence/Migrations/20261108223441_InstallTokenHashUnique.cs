using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InstallTokenHashUnique : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "ux_installs_token_hash",
                schema: "zaghlol",
                table: "installs",
                column: "token_hash",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ux_installs_token_hash",
                schema: "zaghlol",
                table: "installs");
        }
    }
}
