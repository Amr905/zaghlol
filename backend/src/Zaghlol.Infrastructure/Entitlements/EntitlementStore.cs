using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Infrastructure.Seats;

namespace Zaghlol.Infrastructure.Entitlements;

/// <summary>
/// <see cref="IEntitlementStore"/> on the App login (<c>app_rw</c>): plain reads and the three support-notice statements. Every
/// statement is keyed by the calling install, so a token can only ever cover rows of its own seat (T-132 AC 3).
/// </summary>
internal sealed class EntitlementStore(IServiceProvider services) : IEntitlementStore
{
    // Seats this install holds, any purchase state (a refund or an expiry must be visible in the token).
    private const string HeldSql = """
        SELECT p.id, p.store, p.product_id, p.plan, p.state, p.expires_at, p.account_id, s.proof, s.next_move_at
        FROM zaghlol.purchase_seats s JOIN zaghlol.purchases p ON p.id = s.purchase_id
        WHERE s.install_id = @install
        """;

    // Entitling purchases this install bought whose seat another install holds, with the cause of the purchase's latest seat event.
    private const string LostSql = """
        SELECT p.id, p.store, p.product_id, p.plan, s.next_move_at,
               (SELECT e.cause FROM zaghlol.purchase_events e
                WHERE e.purchase_id = p.id AND starts_with(e.cause, 'seat_')
                ORDER BY e.occurred_at DESC LIMIT 1)
        FROM zaghlol.purchases p JOIN zaghlol.purchase_seats s ON s.purchase_id = p.id
        WHERE p.install_id = @install AND s.install_id IS NOT NULL AND s.install_id <> @install
          AND p.state IN ('active', 'in_grace', 'canceled_active') AND (p.expires_at IS NULL OR p.expires_at > @now)
        """;

    private const string NoticePendingSql = """
        SELECT EXISTS (SELECT 1 FROM zaghlol.purchases WHERE install_id = @install AND support_link_notice_pending)
        """;

    private const string RecordIatSql = """
        UPDATE zaghlol.purchases SET support_link_notice_iat = @iat
        WHERE install_id = @install AND support_link_notice_pending
          AND (support_link_notice_iat IS NULL OR support_link_notice_iat < @iat)
        """;

    private const string ClearSql = """
        UPDATE zaghlol.purchases SET support_link_notice_pending = false
        WHERE install_id = @install AND support_link_notice_pending
          AND support_link_notice_iat IS NOT NULL AND support_link_notice_iat <= @issued
        """;

    private const string ChangedSql = """
        SELECT EXISTS (
            SELECT 1 FROM zaghlol.purchase_events e
            WHERE e.occurred_at > @since
              AND (EXISTS (SELECT 1 FROM zaghlol.purchases p WHERE p.id = e.purchase_id AND p.install_id = @install)
                   OR EXISTS (SELECT 1 FROM zaghlol.purchase_seats s WHERE s.purchase_id = e.purchase_id AND s.install_id = @install)))
        """;

    private NpgsqlDataSource Source => services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);

    public async Task<EntitlementFacts> ReadFactsAsync(InstallId install, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var connection = await Source.OpenConnectionAsync(cancellationToken).ConfigureAwait(false);
        var held = new List<HeldPurchase>();
        await using (var command = new NpgsqlCommand(HeldSql, connection))
        {
            command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, install.Value);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
            while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
            {
                held.Add(new HeldPurchase(
                    reader.GetGuid(0),
                    ParseStore(reader.GetString(1)),
                    reader.GetString(2),
                    ParsePlan(reader.GetString(3)),
                    PurchaseDbText.ParseState(reader.GetString(4)),
                    reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5),
                    reader.IsDBNull(6) ? null : reader.GetGuid(6),
                    SeatDbText.ParseProof(reader.GetString(7)),
                    reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8)));
            }
        }

        var lost = new List<LostPurchase>();
        await using (var command = new NpgsqlCommand(LostSql, connection))
        {
            command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, install.Value);
            command.Parameters.AddWithValue("now", NpgsqlDbType.TimestampTz, now.ToUniversalTime());
            await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
            while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
            {
                var cause = reader.IsDBNull(5) ? null : reader.GetString(5);
                lost.Add(new LostPurchase(
                    reader.GetGuid(0),
                    ParseStore(reader.GetString(1)),
                    reader.GetString(2),
                    ParsePlan(reader.GetString(3)),
                    reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4),
                    cause == SeatCauses.MoveSupport ? SeatMovedBy.Support : SeatMovedBy.User));
            }
        }

        return new EntitlementFacts(held, lost);
    }

    public async Task<bool> SupportNoticePendingAsync(InstallId install, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(NoticePendingSql);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, install.Value);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false))!;
    }

    public async Task RecordSupportNoticeIatAsync(InstallId install, DateTimeOffset iat, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(RecordIatSql);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, install.Value);
        command.Parameters.AddWithValue("iat", NpgsqlDbType.TimestampTz, iat.ToUniversalTime());
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ClearDeliveredSupportNoticeAsync(InstallId install, DateTimeOffset issuedAt, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(ClearSql);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, install.Value);
        command.Parameters.AddWithValue("issued", NpgsqlDbType.TimestampTz, issuedAt.ToUniversalTime());
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<bool> ChangedSinceAsync(InstallId install, DateTimeOffset since, CancellationToken cancellationToken)
    {
        await using var command = Source.CreateCommand(ChangedSql);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, install.Value);
        command.Parameters.AddWithValue("since", NpgsqlDbType.TimestampTz, since.ToUniversalTime());
        return (bool)(await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false))!;
    }

    private static PurchaseStore ParseStore(string text) => text switch
    {
        "google_play" => PurchaseStore.GooglePlay,
        "app_store" => PurchaseStore.AppStore,
        _ => throw new InvalidOperationException("Unknown purchases.store value."),
    };

    private static GoldPlan ParsePlan(string text) => text switch
    {
        "monthly" => GoldPlan.Monthly,
        "yearly" => GoldPlan.Yearly,
        "lifetime" => GoldPlan.Lifetime,
        _ => throw new InvalidOperationException("Unknown purchases.plan value."),
    };
}
