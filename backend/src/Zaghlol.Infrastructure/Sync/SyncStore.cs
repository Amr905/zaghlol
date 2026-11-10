using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Sync;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Sync;

/// <summary>
/// The sync's <c>installs</c> read and its one write transaction, on the App login (<c>app_rw</c>). The claim is the
/// authoritative throttle: a conditional UPDATE that only one of two concurrent calls can win; the intake and the
/// daily-active upsert commit with it or not at all.
/// </summary>
internal sealed class SyncStore(IAppDbContextFactory contexts) : ISyncStore
{
    private const string ClaimSql = """
        UPDATE zaghlol.installs
        SET last_sync_at = @now, last_seen_at = @now, catalog_version = @catalog_version, app_version = @app_version
        WHERE id = @id AND deleted_at IS NULL AND (last_sync_at IS NULL OR last_sync_at <= @cutoff)
        """;

    // No conflict target: app_rw may not read these tables (FU-021 grants), and the only possible conflict is the dedupe key.
    private const string ContributionsSql = """
        INSERT INTO zaghlol.merchant_contributions (id, merchant_norm, institution_code, category_code, install_hash, received_at)
        SELECT u.id, u.merchant_norm, u.institution_code, u.category_code, @install_hash, @now
        FROM unnest(@ids, @merchants, @institutions, @categories) AS u(id, merchant_norm, institution_code, category_code)
        ON CONFLICT DO NOTHING
        """;

    private const string BankRequestsSql = """
        INSERT INTO zaghlol.bank_requests (institution_name_norm, country, channel, install_hash, received_at)
        SELECT u.institution_name_norm, u.country, u.channel, @install_hash, @now
        FROM unnest(@names, @countries, @channels) AS u(institution_name_norm, country, channel)
        ON CONFLICT DO NOTHING
        """;

    // app_rw has no privilege on daily_active_counts; this SECURITY DEFINER function can only add 1 (SyncSql).
    private const string DailyActiveSql = "SELECT zaghlol.count_daily_active(@day, @platform, @app_version)";

    public async Task<SyncInstall?> FindInstallAsync(InstallId installId, CancellationToken cancellationToken)
    {
        var id = installId.Value;
        await using var db = contexts.CreateDbContext();
        var row = await db.Installs
            .AsNoTracking()
            .Where(i => i.Id == id && i.DeletedAt == null)
            .Select(i => new { i.Platform, i.AppVersion, i.LastSyncAt })
            .SingleOrDefaultAsync(cancellationToken);
        return row is null ? null : new SyncInstall(DbEnumMaps.Platforms.ToDb(row.Platform), row.AppVersion, row.LastSyncAt);
    }

    public async Task<SyncClaimResult> ClaimAsync(SyncClaim claim, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(claim);

        var now = claim.Now.ToUniversalTime();
        await using var db = contexts.CreateDbContext();
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        await using (var update = new NpgsqlCommand(ClaimSql, connection, transaction))
        {
            update.Parameters.AddWithValue("now", now);
            update.Parameters.AddWithValue("cutoff", now - claim.Window);
            update.Parameters.AddWithValue("catalog_version", claim.CatalogVersion);
            update.Parameters.AddWithValue("app_version", claim.AppVersion);
            update.Parameters.AddWithValue("id", claim.InstallId.Value);
            if (await update.ExecuteNonQueryAsync(cancellationToken) != 1)
            {
                await transaction.RollbackAsync(cancellationToken);
                return SyncClaimResult.Lost;
            }
        }

        var contributions = 0;
        var bankRequests = 0;
        if (claim.InstallHash is { IsEmpty: false } hash)
        {
            if (claim.Contributions.Count > 0)
            {
                await using var insert = new NpgsqlCommand(ContributionsSql, connection, transaction);
                insert.Parameters.AddWithValue("ids", claim.Contributions.Select(_ => Guid.CreateVersion7(now)).ToArray());
                insert.Parameters.Add(Texts("merchants", claim.Contributions.Select(c => c.MerchantNorm)));
                insert.Parameters.Add(Texts("institutions", claim.Contributions.Select(c => c.InstitutionCode)));
                insert.Parameters.Add(Texts("categories", claim.Contributions.Select(c => c.CategoryCode)));
                insert.Parameters.Add(new NpgsqlParameter("install_hash", NpgsqlDbType.Bytea) { Value = hash.ToArray() });
                insert.Parameters.AddWithValue("now", now);
                contributions = await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            if (claim.BankRequests.Count > 0)
            {
                await using var insert = new NpgsqlCommand(BankRequestsSql, connection, transaction);
                insert.Parameters.Add(Texts("names", claim.BankRequests.Select(b => b.InstitutionNameNorm)));
                insert.Parameters.Add(Texts("countries", claim.BankRequests.Select(b => b.Country)));
                insert.Parameters.Add(Texts("channels", claim.BankRequests.Select(b => b.Channel)));
                insert.Parameters.Add(new NpgsqlParameter("install_hash", NpgsqlDbType.Bytea) { Value = hash.ToArray() });
                insert.Parameters.AddWithValue("now", now);
                bankRequests = await insert.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        // At most one increment per install per UTC day follows from the 24 h window.
        await using (var active = new NpgsqlCommand(DailyActiveSql, connection, transaction))
        {
            active.Parameters.AddWithValue("day", DateOnly.FromDateTime(now.UtcDateTime));
            active.Parameters.AddWithValue("platform", claim.Platform);
            active.Parameters.AddWithValue("app_version", claim.AppVersion);
            await active.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return new SyncClaimResult(true, contributions, bankRequests);
    }

    private static NpgsqlParameter<string[]> Texts(string name, IEnumerable<string> values) =>
        new(name, NpgsqlDbType.Array | NpgsqlDbType.Text) { TypedValue = values.ToArray() };
}
