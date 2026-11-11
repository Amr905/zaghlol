using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-130 security M-1: the acknowledge sweeper's deferral stamp. A row the sweeper can't finish gets a next-attempt time, so
    /// stuck rows leave the 200-row window instead of starving newer purchases. Existing rows start NULL (never deferred, listed
    /// first). Dropping the column also drops its column grants.
    /// </summary>
    public partial class PurchaseAckNextAttempt : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ack_next_attempt_at",
                schema: "zaghlol",
                table: "purchases",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.Sql(GrantMatrix.ToSql(GrantMatrix.PurchaseAckNextAttempt));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ack_next_attempt_at",
                schema: "zaghlol",
                table: "purchases");
        }
    }
}
