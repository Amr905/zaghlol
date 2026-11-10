using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddPriceFeedColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_merchant_contributions_merchant_norm",
                schema: "zaghlol",
                table: "merchant_contributions");

            migrationBuilder.DropCheckConstraint(
                name: "ck_bank_requests_institution_name_norm",
                schema: "zaghlol",
                table: "bank_requests");

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "feed_as_of",
                schema: "zaghlol",
                table: "price_quotes",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "feed_price",
                schema: "zaghlol",
                table: "price_quotes",
                type: "numeric(20,6)",
                precision: 20,
                scale: 6,
                nullable: true);

            migrationBuilder.AddCheckConstraint(
                name: "ck_price_quotes_override_expiry",
                schema: "zaghlol",
                table: "price_quotes",
                sql: "is_override = (override_expires_at IS NOT NULL)");

            migrationBuilder.AddCheckConstraint(
                name: "ck_price_quotes_price_positive",
                schema: "zaghlol",
                table: "price_quotes",
                sql: "price > 0 AND (feed_price IS NULL OR feed_price > 0)");

            migrationBuilder.AddCheckConstraint(
                name: "ck_merchant_contributions_merchant_norm",
                schema: "zaghlol",
                table: "merchant_contributions",
                sql: "char_length(merchant_norm) <= 64 AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in merchant_norm) = 0");

            migrationBuilder.AddCheckConstraint(
                name: "ck_bank_requests_institution_name_norm",
                schema: "zaghlol",
                table: "bank_requests",
                sql: "char_length(institution_name_norm) <= 64 AND institution_name_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in institution_name_norm) = 0");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_price_quotes_override_expiry",
                schema: "zaghlol",
                table: "price_quotes");

            migrationBuilder.DropCheckConstraint(
                name: "ck_price_quotes_price_positive",
                schema: "zaghlol",
                table: "price_quotes");

            migrationBuilder.DropCheckConstraint(
                name: "ck_merchant_contributions_merchant_norm",
                schema: "zaghlol",
                table: "merchant_contributions");

            migrationBuilder.DropCheckConstraint(
                name: "ck_bank_requests_institution_name_norm",
                schema: "zaghlol",
                table: "bank_requests");

            migrationBuilder.DropColumn(
                name: "feed_as_of",
                schema: "zaghlol",
                table: "price_quotes");

            migrationBuilder.DropColumn(
                name: "feed_price",
                schema: "zaghlol",
                table: "price_quotes");

            migrationBuilder.AddCheckConstraint(
                name: "ck_merchant_contributions_merchant_norm",
                schema: "zaghlol",
                table: "merchant_contributions",
                sql: "char_length(merchant_norm) <= 64 AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].-]?){6,}' AND position('@' in merchant_norm) = 0");

            migrationBuilder.AddCheckConstraint(
                name: "ck_bank_requests_institution_name_norm",
                schema: "zaghlol",
                table: "bank_requests",
                sql: "char_length(institution_name_norm) <= 64 AND institution_name_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].-]?){6,}' AND position('@' in institution_name_norm) = 0");
        }
    }
}
