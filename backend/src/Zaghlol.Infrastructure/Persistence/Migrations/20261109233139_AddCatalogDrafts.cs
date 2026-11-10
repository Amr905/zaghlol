using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCatalogDrafts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "catalog_drafts",
                schema: "zaghlol",
                columns: table => new
                {
                    entity = table.Column<string>(type: "text", nullable: false),
                    entry_key = table.Column<string>(type: "text", nullable: false),
                    seq = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    body = table.Column<string>(type: "jsonb", nullable: false),
                    deleted = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    published = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    changed = table.Column<bool>(type: "boolean", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_drafts", x => new { x.entity, x.entry_key });
                    table.CheckConstraint("ck_catalog_drafts_entity", "entity IN ('categories','merchants','aliases','keywords')");
                });

            migrationBuilder.CreateIndex(
                name: "ux_catalog_drafts_seq",
                schema: "zaghlol",
                table: "catalog_drafts",
                column: "seq",
                unique: true);

            // Grants are explicit (no default privileges); rendered from the list frozen with this migration.
            migrationBuilder.Sql(GrantMatrix.ToSql(GrantMatrix.CatalogDrafts));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "catalog_drafts",
                schema: "zaghlol");
        }
    }
}
