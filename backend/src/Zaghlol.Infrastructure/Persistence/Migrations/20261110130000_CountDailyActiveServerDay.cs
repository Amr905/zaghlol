using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-128 security review S3: <c>zaghlol.count_daily_active</c> takes no day (the database's UTC date) and accepts only
    /// <c>android</c> or <c>ios</c>. No model change, so this migration is hand-written (the generator's empty migration has no
    /// snapshot change and the CI workflow only commits a migration together with one); the designer is the previous model.
    /// </summary>
    public partial class CountDailyActiveServerDay : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(DailyActiveServerDaySql.Up);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(DailyActiveServerDaySql.Down);
        }
    }
}
