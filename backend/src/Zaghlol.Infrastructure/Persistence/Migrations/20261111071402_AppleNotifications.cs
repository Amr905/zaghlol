using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-134 design note §5: the ASSN V2 processor's back-off column <c>store_notifications.next_attempt_at</c> (NULL = never failed;
    /// existing rows start NULL) and its partial index over unprocessed rows, CHECKs that keep <c>type</c>/<c>subtype</c> to store-defined
    /// names, and the worker grants of <see cref="GrantMatrix.AppleNotifications"/>: UPDATE (product_id, plan) on purchases (FU-092
    /// item 1) and INSERT on store_notifications (the history job). Down revokes exactly those grants; dropping the column drops nothing
    /// else.
    /// </summary>
    public partial class AppleNotifications : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "next_attempt_at",
                schema: "zaghlol",
                table: "store_notifications",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_store_notifications_due",
                schema: "zaghlol",
                table: "store_notifications",
                columns: new[] { "store", "next_attempt_at", "received_at" },
                filter: "processed_at IS NULL")
                .Annotation("Npgsql:IndexNullSortOrder", new[] { NullSortOrder.NullsFirst, NullSortOrder.NullsLast, NullSortOrder.NullsLast });

            migrationBuilder.AddCheckConstraint(
                name: "ck_store_notifications_subtype",
                schema: "zaghlol",
                table: "store_notifications",
                sql: "subtype IS NULL OR subtype ~ '^[A-Z0-9_]{1,64}$'");

            migrationBuilder.AddCheckConstraint(
                name: "ck_store_notifications_type",
                schema: "zaghlol",
                table: "store_notifications",
                sql: "type ~ '^[A-Z0-9_]{1,64}$'");

            migrationBuilder.Sql(GrantMatrix.ToSql(GrantMatrix.AppleNotifications));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                "REVOKE UPDATE (product_id, plan) ON zaghlol.purchases FROM worker_rw;\n"
                + "REVOKE INSERT ON zaghlol.store_notifications FROM worker_rw;\n");

            migrationBuilder.DropIndex(
                name: "ix_store_notifications_due",
                schema: "zaghlol",
                table: "store_notifications");

            migrationBuilder.DropCheckConstraint(
                name: "ck_store_notifications_subtype",
                schema: "zaghlol",
                table: "store_notifications");

            migrationBuilder.DropCheckConstraint(
                name: "ck_store_notifications_type",
                schema: "zaghlol",
                table: "store_notifications");

            migrationBuilder.DropColumn(
                name: "next_attempt_at",
                schema: "zaghlol",
                table: "store_notifications");
        }
    }
}
