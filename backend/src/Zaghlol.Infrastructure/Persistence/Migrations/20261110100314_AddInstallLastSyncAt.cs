using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddInstallLastSyncAt : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "last_sync_at",
                schema: "zaghlol",
                table: "installs",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "last_sync_at",
                schema: "zaghlol",
                table: "installs");
        }
    }
}
