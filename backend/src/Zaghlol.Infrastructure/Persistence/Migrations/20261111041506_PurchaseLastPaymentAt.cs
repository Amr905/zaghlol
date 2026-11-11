using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-131 design note §4: <c>purchases.last_payment_at</c>, the <c>purchaseDate</c> of the newest Apple <c>PURCHASE</c>-reason
    /// transaction a binding-checked verify has seen. Advancing it is the new-payment signal (D-59/D-61(a)); only <c>app_rw</c>
    /// may update it (T-134's notifications must never advance it). Existing rows start NULL. Dropping the column also drops its
    /// column grant.
    /// </summary>
    public partial class PurchaseLastPaymentAt : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "last_payment_at",
                schema: "zaghlol",
                table: "purchases",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.Sql(GrantMatrix.ToSql(GrantMatrix.PurchaseLastPaymentAt));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "last_payment_at",
                schema: "zaghlol",
                table: "purchases");
        }
    }
}
