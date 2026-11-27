using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Llm.Quota;
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

    // T-353. The row's only identity is install_hash (the KMS-peppered HMAC), and created_at is cut to the UTC day: no install ID,
    // account, IP or app version, and no time that could be matched to one sync. Duplicates per (merchant_norm, install_hash) keep the first.
    private const string ConfirmationsSql = """
        INSERT INTO zaghlol.llm_cat_confirmations (id, merchant_norm, category_code, source, install_hash, created_at)
        SELECT u.id, u.merchant_norm, u.category_code, u.source, @install_hash, @day
        FROM unnest(@ids, @merchants, @categories, @sources) AS u(id, merchant_norm, category_code, source)
        ON CONFLICT DO NOTHING
        """;

    private const string CorrectionsSql = """
        INSERT INTO zaghlol.llm_cat_corrections (id, merchant_norm, ai_category, user_category, source, install_hash, created_at)
        SELECT u.id, u.merchant_norm, u.ai_category, u.user_category, u.source, @install_hash, @day
        FROM unnest(@ids, @merchants, @ai_categories, @user_categories, @sources) AS u(id, merchant_norm, ai_category, user_category, source)
        ON CONFLICT DO NOTHING
        """;

    // Two syncs correcting one merchant at once must not both miss the third row: the merchants are locked in sorted order for the
    // transaction (one fixed order, so no deadlock) before the insert, and the next statement sees what the other committed.
    private const string LockMerchantsSql = """
        SELECT pg_advisory_xact_lock(hashtextextended('llmcat:' || m, 0))
        FROM (SELECT DISTINCT m FROM unnest(@merchants) AS m ORDER BY m) AS s
        """;

    // FR-LCAT-12: three corrections (distinct installs, by the unique key; one a rejected review doesn't count) of the very category the
    // cache holds delete that cache row. The next ask for the name goes back to the model. A correction's created_at is its UTC day
    // (midnight), so "after the row" is compared with the day the row was written, not its timestamp (FU-448): a correction made that day
    // counts; one from an earlier day (the corrections that deleted the row's predecessor) does not.
    private const string ContradictionSql = """
        DELETE FROM zaghlol.llm_cat_answer_cache c
        WHERE c.merchant_norm = ANY(@merchants)
          AND (SELECT count(*) FROM zaghlol.llm_cat_corrections x
               WHERE x.merchant_norm = c.merchant_norm AND x.ai_category = c.category_code AND x.status <> 'rejected'
                 AND x.created_at >= (date_trunc('day', c.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')) >= @threshold
        """;

    // B97-M1: feedback counts only from an install that has made an attested categorise call (the gate chain verifies the proof before
    // any quota is spent), so its counter row for the current or previous Cairo month exists with used > 0. The weaker evidence is
    // "any merchant": per-merchant evidence would need a new column (follow-up). The id is never stored with the feedback.
    private const string AttestedSql = """
        SELECT EXISTS (SELECT 1 FROM zaghlol.llm_quota_counters
                       WHERE feature = 'cat' AND subject_kind = 'install' AND subject_id = @id AND used > 0 AND month_key IN (@current, @previous))
        """;

    /// <summary>Distinct-install corrections of the cached category that remove the cache row (FR-LCAT-12).</summary>
    public const int ContradictionThreshold = 3;

    // app_rw has no privilege on daily_active_counts; this SECURITY DEFINER function can only add 1 to today's (database UTC
    // date) row of android or ios (DailyActiveServerDaySql).
    private const string DailyActiveSql = "SELECT zaghlol.count_daily_active(@platform, @app_version)";

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

        var confirmations = 0;
        var corrections = 0;
        if (claim.InstallHash is { IsEmpty: false } feedbackHash && claim.Feedback is { IsEmpty: false } feedback
            && await HasAttestedAsync(connection, transaction, claim.InstallId, now, cancellationToken))
        {
            var day = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
            if (feedback.Corrections.Count > 0)
            {
                await using var @lock = new NpgsqlCommand(LockMerchantsSql, connection, transaction);
                @lock.Parameters.Add(Texts("merchants", feedback.Corrections.Select(c => c.MerchantNorm)));
                await @lock.ExecuteNonQueryAsync(cancellationToken);
            }

            if (feedback.Confirmations.Count > 0)
            {
                await using var insert = new NpgsqlCommand(ConfirmationsSql, connection, transaction);
                insert.Parameters.AddWithValue("ids", feedback.Confirmations.Select(_ => Guid.CreateVersion7(now)).ToArray());
                insert.Parameters.Add(Texts("merchants", feedback.Confirmations.Select(c => c.MerchantNorm)));
                insert.Parameters.Add(Texts("categories", feedback.Confirmations.Select(c => c.CategoryCode)));
                insert.Parameters.Add(Texts("sources", feedback.Confirmations.Select(c => c.Source)));
                insert.Parameters.Add(new NpgsqlParameter("install_hash", NpgsqlDbType.Bytea) { Value = feedbackHash.ToArray() });
                insert.Parameters.Add(new NpgsqlParameter("day", NpgsqlDbType.TimestampTz) { Value = day });
                confirmations = await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            if (feedback.Corrections.Count > 0)
            {
                await using var insert = new NpgsqlCommand(CorrectionsSql, connection, transaction);
                insert.Parameters.AddWithValue("ids", feedback.Corrections.Select(_ => Guid.CreateVersion7(now)).ToArray());
                insert.Parameters.Add(Texts("merchants", feedback.Corrections.Select(c => c.MerchantNorm)));
                insert.Parameters.Add(Texts("ai_categories", feedback.Corrections.Select(c => c.AiCategory)));
                insert.Parameters.Add(Texts("user_categories", feedback.Corrections.Select(c => c.UserCategory)));
                insert.Parameters.Add(Texts("sources", feedback.Corrections.Select(c => c.Source)));
                insert.Parameters.Add(new NpgsqlParameter("install_hash", NpgsqlDbType.Bytea) { Value = feedbackHash.ToArray() });
                insert.Parameters.Add(new NpgsqlParameter("day", NpgsqlDbType.TimestampTz) { Value = day });
                corrections = await insert.ExecuteNonQueryAsync(cancellationToken);

                await using var contradiction = new NpgsqlCommand(ContradictionSql, connection, transaction);
                contradiction.Parameters.Add(Texts("merchants", feedback.Corrections.Select(c => c.MerchantNorm)));
                contradiction.Parameters.AddWithValue("threshold", ContradictionThreshold);
                await contradiction.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        // At most one increment per install per UTC day follows from the 24 h window. The day is the database's own.
        await using (var active = new NpgsqlCommand(DailyActiveSql, connection, transaction))
        {
            active.Parameters.AddWithValue("platform", claim.Platform);
            active.Parameters.AddWithValue("app_version", claim.AppVersion);
            await active.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return new SyncClaimResult(true, contributions, bankRequests, confirmations, corrections);
    }

    private static async Task<bool> HasAttestedAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, InstallId install, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(AttestedSql, connection, transaction);
        command.Parameters.AddWithValue("id", install.Value);
        command.Parameters.AddWithValue("current", CairoMonth.MonthKey(now));
        command.Parameters.AddWithValue("previous", CairoMonth.PreviousKey(now));
        return (bool)(await command.ExecuteScalarAsync(cancellationToken))!;
    }

    private static NpgsqlParameter<string[]> Texts(string name, IEnumerable<string> values) =>
        new(name, NpgsqlDbType.Array | NpgsqlDbType.Text) { TypedValue = values.ToArray() };
}
