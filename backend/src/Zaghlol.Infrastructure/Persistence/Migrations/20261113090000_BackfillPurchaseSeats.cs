using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-132 (FU-112, PO decision): purchases verified before the seat service shipped (T-130/T-131 wrote them, nothing wrote a seat)
    /// get a seat bound to the install that bought them (<c>proof = binding</c>, <c>bound_at = created_at</c>, no
    /// <c>last_moved_at</c> / <c>next_move_at</c>, so no cooldown, no <c>purchase_events</c> row, and
    /// <c>purchases.attach_reclaim_used_at</c> untouched, so the free account-attach reclaim stays available). A purchase whose buying
    /// install is gone (NULL, or tombstoned) gets a vacant seat: restore is the way back (PO Q2). Data only, no schema change: the
    /// model snapshot is unchanged. Idempotent (<c>NOT EXISTS</c> plus <c>ON CONFLICT DO NOTHING</c>, so a verify that binds a seat
    /// while this runs wins). Down is a no-op on purpose: a backfilled row can't be told from a seat the service wrote, and
    /// deleting seats would unseat holders.
    /// </summary>
    public partial class BackfillPurchaseSeats : Migration
    {
        /// <summary>The statement <see cref="Up"/> runs (a constant so the integration test runs exactly this text).</summary>
        internal const string Sql =
                """
                INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at, device_key_trusted, recent_rebinds)
                SELECT p.id,
                       i.id,
                       CASE WHEN i.id IS NULL THEN NULL ELSE 'binding' END,
                       CASE WHEN i.id IS NULL THEN NULL ELSE p.created_at END,
                       false,
                       '{}'
                FROM zaghlol.purchases p
                LEFT JOIN zaghlol.installs i ON i.id = p.install_id AND i.deleted_at IS NULL
                WHERE NOT EXISTS (SELECT 1 FROM zaghlol.purchase_seats s WHERE s.purchase_id = p.id)
                ON CONFLICT (purchase_id) DO NOTHING;
                """;

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql(Sql);

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
        }
    }
}
