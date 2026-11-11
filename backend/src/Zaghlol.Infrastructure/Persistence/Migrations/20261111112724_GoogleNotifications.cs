using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-133 design note §2: one CHECK, <c>ck_store_notifications_google_shape</c>. A <c>google_play</c> row has no subtype and no
    /// environment (known only from Play's read), and its <c>external_id</c> is a Pub/Sub <c>messageId</c>, a <c>voided:</c> key or a
    /// <c>sweep:</c> key. No column and no grant: the worker already writes only state, expires_at and last_verified_at. No Google row
    /// exists before T-133, so the constraint can't reject existing data. Down drops exactly the constraint.
    /// </summary>
    public partial class GoogleNotifications : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddCheckConstraint(
                name: "ck_store_notifications_google_shape",
                schema: "zaghlol",
                table: "store_notifications",
                sql: "store <> 'google_play' OR (subtype IS NULL AND environment IS NULL AND (external_id ~ '^[A-Za-z0-9_-]{1,100}$' OR external_id ~ '^voided:[0-9a-f]{64}$' OR external_id ~ '^sweep:[0-9a-f-]{36}:[0-9]{1,12}$'))");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_store_notifications_google_shape",
                schema: "zaghlol",
                table: "store_notifications");
        }
    }
}
