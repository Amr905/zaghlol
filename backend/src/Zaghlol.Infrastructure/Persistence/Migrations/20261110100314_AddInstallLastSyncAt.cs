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

            // The daily-active counter increment for app_rw (T-128); app_rw keeps no table privilege on daily_active_counts.
            migrationBuilder.Sql(SyncSql.CreateCountDailyActive);

            // T-127 review nit 5: the CHECKs added to merchant_contributions and bank_requests by AddPriceFeedColumns (FU-018)
            // were validated against empty tables. From this migration on the sync writes those tables, so a later migration
            // that tightens one of their CHECKs must clean or migrate existing rows first (deployment.md, "Migrations").
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(SyncSql.DropCountDailyActive);

            migrationBuilder.DropColumn(
                name: "last_sync_at",
                schema: "zaghlol",
                table: "installs");
        }
    }
}
