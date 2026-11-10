using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Support;

/// <summary>
/// The support lookup on the Admin login (<c>ops_rw</c>, backend-api §5.2, T-136 design note §6). One transaction per call:
/// read the related purchases, write the <c>support_lookup</c> audit row, commit. Relations to the looked-up install are
/// computed in SQL, so the holder's, claimants' and buyer's install IDs never leave the database, and no token, store key or
/// transaction ID is selected. The e-mail is only ever a bound parameter: never in SQL text, a log, a span or an exception.
/// </summary>
internal sealed class SupportLookupStore(
    IZaghlolDbContextFactory contexts,
    IKeyedHasher hasher,
    IAuditWriter audit,
    TimeProvider clock) : ISupportLookupStore
{
    private const string SelectPurchases = """
        SELECT p.id, p.plan, p.state, p.store, p.expires_at, p.account_id IS NOT NULL, p.account_linked_by, p.dispute_frozen_until,
               s.install_id IS NOT NULL,
               COALESCE(s.install_id = @install, false),
               EXISTS (SELECT 1 FROM zaghlol.seat_claimants c
                       WHERE c.purchase_id = p.id AND c.install_id = @install AND c.claimed_at > @claim_cutoff),
               COALESCE(p.install_id = @install, false),
               s.last_moved_at, s.next_move_at,
               (SELECT count(*) FROM zaghlol.seat_claimants c WHERE c.purchase_id = p.id AND c.claimed_at > @claim_cutoff),
               NOT EXISTS (SELECT 1 FROM zaghlol.installs i
                           WHERE i.id = p.install_id AND i.deleted_at IS NULL AND i.last_seen_at > @silent_cutoff),
               (SELECT count(*) FROM unnest(s.recent_rebinds) AS r(ts) WHERE r.ts > @rebind_cutoff)
        FROM zaghlol.purchases p
        LEFT JOIN zaghlol.purchase_seats s ON s.purchase_id = p.id
        """;

    private const string ByInstall = SelectPurchases + """

        WHERE p.install_id = @install
           OR s.install_id = @install
           OR EXISTS (SELECT 1 FROM zaghlol.seat_claimants c
                      WHERE c.purchase_id = p.id AND c.install_id = @install AND c.claimed_at > @claim_cutoff)
        ORDER BY p.created_at DESC, p.id
        LIMIT 20
        """;

    private const string ByAccounts = SelectPurchases + """

        WHERE p.account_id = ANY(@accounts)
        ORDER BY p.created_at DESC, p.id
        LIMIT 20
        """;

    // The stored address is folded the same way as the key: NFC(trim(lower(email))).
    private const string AccountsByEmail = """
        SELECT id FROM zaghlol.accounts
        WHERE email IS NOT NULL AND normalize(btrim(lower(email)), NFC) = @email
        ORDER BY created_at, id
        LIMIT 20
        """;

    public async Task<SupportEntitlementView> LookupInstallAsync(Guid operatorId, InstallId installId, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var now = clock.GetUtcNow();
        var rows = await ReadPurchasesAsync(connection, transaction, ByInstall, installId.Value, [], now, cancellationToken);
        var view = SupportEntitlementBuilder.Build(SupportLookupKind.Install, rows, now);

        await audit.WriteAsync(connection, transaction, operatorId, SupportLookupAudit.ForInstall(installId, view.Purchases.Count), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return view;
    }

    public async Task<SupportEntitlementView> LookupEmailAsync(Guid operatorId, string normalizedEmail, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(normalizedEmail);

        var mac = await hasher.HmacSha256Async(KeyedHashKey.Audit, Encoding.UTF8.GetBytes(normalizedEmail), cancellationToken);
        var pseudonym = EmailPseudonym.FromMac(mac);

        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var accounts = new List<Guid>();
        await using (var find = new NpgsqlCommand(AccountsByEmail, connection, transaction))
        {
            find.Parameters.AddWithValue("email", normalizedEmail);
            await using var reader = await find.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                accounts.Add(reader.GetGuid(0));
            }
        }

        // Runs whether or not an account matched, so a miss costs the same queries as a hit.
        var now = clock.GetUtcNow();
        var rows = await ReadPurchasesAsync(connection, transaction, ByAccounts, null, [.. accounts], now, cancellationToken);
        var view = SupportEntitlementBuilder.Build(SupportLookupKind.Email, rows, now);

        await audit.WriteAsync(connection, transaction, operatorId, SupportLookupAudit.ForEmail(pseudonym, accounts, view.Purchases.Count), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return view;
    }

    private static async Task<List<SupportPurchaseRow>> ReadPurchasesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string sql,
        Guid? installId,
        Guid[] accountIds,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.Add(new NpgsqlParameter("install", NpgsqlDbType.Uuid) { Value = installId is { } id ? id : (object)DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("accounts", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = accountIds });
        command.Parameters.AddWithValue("claim_cutoff", now - SupportEntitlementBuilder.ClaimantWindow);
        command.Parameters.AddWithValue("silent_cutoff", now - SupportEntitlementBuilder.ThirtyDays);
        command.Parameters.AddWithValue("rebind_cutoff", now - SupportEntitlementBuilder.ThirtyDays);

        var rows = new List<SupportPurchaseRow>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new SupportPurchaseRow(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                Timestamp(reader, 4),
                reader.GetBoolean(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                Timestamp(reader, 7),
                reader.GetBoolean(8),
                reader.GetBoolean(9),
                reader.GetBoolean(10),
                reader.GetBoolean(11),
                Timestamp(reader, 12),
                Timestamp(reader, 13),
                reader.GetInt64(14),
                reader.GetBoolean(15),
                reader.GetInt64(16)));
        }

        return rows;
    }

    private static DateTimeOffset? Timestamp(NpgsqlDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? (DateTimeOffset?)null : reader.GetFieldValue<DateTimeOffset>(ordinal);
}

public static class SupportServiceCollectionExtensions
{
    /// <summary>
    /// The support lookup store (Admin login, the audit writer, <c>K_audit</c>). Call after <c>AddZaghlolDatabase</c> with
    /// <c>DatabaseRole.Admin</c> and after <c>AddZaghlolKms</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolSupport(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.AddZaghlolAudit();
        services.TryAddSingleton<ISupportLookupStore, SupportLookupStore>();
        return services;
    }
}
