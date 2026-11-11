using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-130 (FU-052 S-2): idempotency keys are claimed by a short-lived row (<c>status = 0</c> with its <c>claim_id</c> lease)
    /// instead of an advisory lock held across the handler, so no connection is pinned while verify waits on Google Play.
    /// Existing rows are final results (2xx, 409, 422, no lease) and satisfy both new CHECKs.
    /// </summary>
    public partial class IdempotencyClaims : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "claim_id",
                schema: "zaghlol",
                table: "idempotency_records",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddCheckConstraint(
                name: "ck_idempotency_records_claim",
                schema: "zaghlol",
                table: "idempotency_records",
                sql: "(status = 0) = (claim_id IS NOT NULL)");

            migrationBuilder.AddCheckConstraint(
                name: "ck_idempotency_records_status",
                schema: "zaghlol",
                table: "idempotency_records",
                sql: "status = 0 OR status BETWEEN 200 AND 299 OR status IN (409, 422)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_idempotency_records_claim",
                schema: "zaghlol",
                table: "idempotency_records");

            migrationBuilder.DropCheckConstraint(
                name: "ck_idempotency_records_status",
                schema: "zaghlol",
                table: "idempotency_records");

            migrationBuilder.DropColumn(
                name: "claim_id",
                schema: "zaghlol",
                table: "idempotency_records");
        }
    }
}
