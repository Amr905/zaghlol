using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Llm.Categorise.Review;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Catalog;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Llm.Categorise;

/// <summary>
/// The AI-category review (llm-categorise §6) on the <c>ops_rw</c> login: groups only, never a row of one install and never an
/// <c>install_hash</c> (no query here selects the column). A resolution takes the intake's per-merchant advisory lock, so a sync
/// that adds a vote at the same time is either counted or not; moves only <c>status</c> (and <c>operator_id</c>, <c>resolved_at</c>
/// of a correction), which is all <c>ops_rw</c> may update; edits only the <b>draft</b> catalog under the catalog lock, never
/// publishes; and writes one audit row in the same transaction. Parameters only; the merchant text is never logged.
/// </summary>
internal sealed class LlmCatReviewStore(
    IZaghlolDbContextFactory contexts,
    CatalogAdminStore catalog,
    IAuditWriter audit,
    TimeProvider clock) : ILlmCatReviewStore
{
    private const string CorrectionsQuerySql = """
        SELECT merchant_norm, ai_category, user_category, status, count(*)::int,
               (min(created_at) AT TIME ZONE 'UTC')::date, (max(created_at) AT TIME ZONE 'UTC')::date
        FROM zaghlol.llm_cat_corrections
        WHERE @status::text IS NULL OR status = @status
        GROUP BY merchant_norm, ai_category, user_category, status
        ORDER BY (status = 'open') DESC, count(*) DESC, merchant_norm, ai_category, user_category, status
        OFFSET @offset LIMIT @take
        """;

    // "no open correction" is per merchant: an open correction of any category hides the confirmed one.
    private const string ConfirmedQuerySql = """
        SELECT c.merchant_norm, c.category_code, count(*)::int,
               (min(c.created_at) AT TIME ZONE 'UTC')::date, (max(c.created_at) AT TIME ZONE 'UTC')::date
        FROM zaghlol.llm_cat_confirmations c
        WHERE c.status = 'collecting'
          AND NOT EXISTS (SELECT 1 FROM zaghlol.llm_cat_corrections x WHERE x.merchant_norm = c.merchant_norm AND x.status = 'open')
        GROUP BY c.merchant_norm, c.category_code
        HAVING count(*) >= @n
        ORDER BY count(*) DESC, c.merchant_norm, c.category_code
        OFFSET @offset LIMIT @take
        """;

    private const string LockMerchantSql = "SELECT pg_advisory_xact_lock(hashtextextended('llmcat:' || @merchant, 0))";

    private const string CorrectionStateSql = """
        SELECT count(*)::int, (count(*) FILTER (WHERE status = 'open'))::int
        FROM zaghlol.llm_cat_corrections
        WHERE merchant_norm = @merchant AND ai_category = @ai AND user_category = @user
        """;

    private const string CorrectionDecideSql = """
        UPDATE zaghlol.llm_cat_corrections SET status = @status, operator_id = @operator, resolved_at = @now
        WHERE merchant_norm = @merchant AND ai_category = @ai AND user_category = @user AND status = 'open'
        """;

    private const string ConfirmedStateSql = """
        SELECT (SELECT count(*)::int FROM zaghlol.llm_cat_confirmations WHERE merchant_norm = @merchant AND category_code = @category AND status = 'collecting'),
               EXISTS (SELECT 1 FROM zaghlol.llm_cat_corrections WHERE merchant_norm = @merchant AND status = 'open')
        """;

    private const string ConfirmedDecideSql = """
        UPDATE zaghlol.llm_cat_confirmations SET status = @status
        WHERE merchant_norm = @merchant AND category_code = @category AND status = 'collecting'
        """;

    public async Task<LlmCatPage<CorrectionGroupView>> QueryCorrectionsAsync(string? status, int limit, int offset, CancellationToken cancellationToken)
    {
        await using var db = Open();
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(CorrectionsQuerySql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.Add(new NpgsqlParameter("status", NpgsqlDbType.Text) { Value = (object?)status ?? DBNull.Value });
        command.Parameters.AddWithValue("offset", offset);
        command.Parameters.AddWithValue("take", limit + 1);
        var rows = new List<CorrectionGroupView>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                rows.Add(new CorrectionGroupView(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetInt32(4),
                    reader.GetFieldValue<DateOnly>(5),
                    reader.GetFieldValue<DateOnly>(6),
                    reader.GetString(3)));
            }
        }

        return Page(rows, limit, offset);
    }

    public async Task<LlmCatPage<ConfirmedGroupView>> QueryConfirmedAsync(int confirmN, int limit, int offset, CancellationToken cancellationToken)
    {
        await using var db = Open();
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand(ConfirmedQuerySql, (NpgsqlConnection)db.Database.GetDbConnection());
        command.Parameters.AddWithValue("n", confirmN);
        command.Parameters.AddWithValue("offset", offset);
        command.Parameters.AddWithValue("take", limit + 1);
        var rows = new List<ConfirmedGroupView>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                rows.Add(new ConfirmedGroupView(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.GetInt32(2),
                    reader.GetFieldValue<DateOnly>(3),
                    reader.GetFieldValue<DateOnly>(4)));
            }
        }

        return Page(rows, limit, offset);
    }

    public async Task<LlmCatDecision> ResolveCorrectionAsync(
        Guid operatorId,
        string merchantNorm,
        string aiCategory,
        string userCategory,
        CorrectionAction action,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(merchantNorm);
        ArgumentNullException.ThrowIfNull(aiCategory);
        ArgumentNullException.ThrowIfNull(userCategory);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        if (action == CorrectionAction.Promote)
        {
            await CatalogAdminStore.LockAsync(db, cancellationToken);
        }

        await LockMerchantAsync(db, merchantNorm, cancellationToken);

        int total;
        int open;
        await using (var state = Command(db, CorrectionStateSql, ("merchant", merchantNorm), ("ai", aiCategory), ("user", userCategory)))
        await using (var reader = await state.ExecuteReaderAsync(cancellationToken))
        {
            await reader.ReadAsync(cancellationToken);
            total = reader.GetInt32(0);
            open = reader.GetInt32(1);
        }

        if (total == 0)
        {
            return new LlmCatDecision(LlmCatOutcome.NotFound);
        }

        if (open == 0)
        {
            return new LlmCatDecision(LlmCatOutcome.Conflict);
        }

        int? merchantId = null;
        if (action == CorrectionAction.Promote)
        {
            merchantId = await UpsertDraftAsync(db, merchantNorm, userCategory, cancellationToken);
            if (merchantId is null)
            {
                return new LlmCatDecision(LlmCatOutcome.Conflict);
            }
        }

        int rows;
        await using (var decide = Command(
            db,
            CorrectionDecideSql,
            ("status", LlmCatReviewWire.Wire(action)),
            ("operator", operatorId),
            ("now", clock.GetUtcNow()),
            ("merchant", merchantNorm),
            ("ai", aiCategory),
            ("user", userCategory)))
        {
            rows = await decide.ExecuteNonQueryAsync(cancellationToken);
        }

        if (rows < 1)
        {
            return new LlmCatDecision(LlmCatOutcome.Conflict);
        }

        var kind = action switch
        {
            CorrectionAction.Promote => LlmCatReviewKind.CorrectionPromote,
            CorrectionAction.Reject => LlmCatReviewKind.CorrectionReject,
            _ => LlmCatReviewKind.CorrectionPromptIssue,
        };
        await audit.WriteAsync(
            db,
            operatorId,
            new LlmCatReviewAudit(kind, CatalogKeys.EncodeText(merchantNorm), aiCategory, userCategory, rows, merchantId),
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new LlmCatDecision(LlmCatOutcome.Ok, rows, merchantId);
    }

    public async Task<LlmCatDecision> ResolveConfirmedAsync(
        Guid operatorId,
        string merchantNorm,
        string category,
        ConfirmedAction action,
        int confirmN,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(merchantNorm);
        ArgumentNullException.ThrowIfNull(category);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        if (action == ConfirmedAction.Promote)
        {
            await CatalogAdminStore.LockAsync(db, cancellationToken);
        }

        await LockMerchantAsync(db, merchantNorm, cancellationToken);

        int votes;
        bool openCorrection;
        await using (var state = Command(db, ConfirmedStateSql, ("merchant", merchantNorm), ("category", category)))
        await using (var reader = await state.ExecuteReaderAsync(cancellationToken))
        {
            await reader.ReadAsync(cancellationToken);
            votes = reader.GetInt32(0);
            openCorrection = reader.GetBoolean(1);
        }

        if (votes == 0)
        {
            return new LlmCatDecision(LlmCatOutcome.NotFound);
        }

        // The query's own rule, checked again under the lock: the same list the operator saw, or nothing changes.
        if (votes < confirmN || openCorrection)
        {
            return new LlmCatDecision(LlmCatOutcome.Conflict);
        }

        int? merchantId = null;
        if (action == ConfirmedAction.Promote)
        {
            merchantId = await UpsertDraftAsync(db, merchantNorm, category, cancellationToken);
            if (merchantId is null)
            {
                return new LlmCatDecision(LlmCatOutcome.Conflict);
            }
        }

        int rows;
        await using (var decide = Command(db, ConfirmedDecideSql, ("status", LlmCatReviewWire.Wire(action)), ("merchant", merchantNorm), ("category", category)))
        {
            rows = await decide.ExecuteNonQueryAsync(cancellationToken);
        }

        if (rows < 1)
        {
            return new LlmCatDecision(LlmCatOutcome.Conflict);
        }

        await audit.WriteAsync(
            db,
            operatorId,
            new LlmCatReviewAudit(
                action == ConfirmedAction.Promote ? LlmCatReviewKind.ConfirmedPromote : LlmCatReviewKind.ConfirmedReject,
                CatalogKeys.EncodeText(merchantNorm),
                null,
                category,
                rows,
                merchantId),
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new LlmCatDecision(LlmCatOutcome.Ok, rows, merchantId);
    }

    /// <summary>
    /// Upserts the merchant and its <c>exact</c> alias into the <b>draft</b> catalog (the caller holds the catalog lock and never
    /// publishes). A live draft merchant whose canonical name is the text is reused when it is in the same category; in another
    /// category, or when the draft refuses the rows, the answer is null (409): the operator settles it in the catalog.
    /// </summary>
    private async Task<int?> UpsertDraftAsync(ZaghlolDbContext db, string norm, string category, CancellationToken cancellationToken)
    {
        if (!CatalogKeys.IsCategoryCode(category))
        {
            return null;
        }

        var existing = await db.CatalogDrafts
            .FromSql($"SELECT * FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND NOT deleted AND body ->> 'canonical' = {norm}")
            .AsNoTracking()
            .FirstOrDefaultAsync(cancellationToken);
        int merchantId;
        if (existing is not null)
        {
            if (CatalogFields.FromJson(existing.Body).Category != category
                || !int.TryParse(existing.EntryKey, NumberStyles.None, CultureInfo.InvariantCulture, out merchantId))
            {
                return null;
            }
        }
        else
        {
            var fields = new CatalogFields { Canonical = norm, NameAr = norm, Category = category };
            if (!CatalogValidation.IsValid(CatalogEntity.Merchants, fields))
            {
                return null;
            }

            var created = await catalog.CreateMerchantInAsync(db, fields, cancellationToken);
            if (created.Status != DraftStatus.Ok)
            {
                return null;
            }

            merchantId = created.Op!.Key.MerchantId;
        }

        if (!CatalogKeys.TryParse(CatalogEntity.Aliases, CatalogKeys.AliasPathId(merchantId, norm), out var aliasKey)
            || (await catalog.ApplyPutAsync(db, aliasKey, new CatalogFields { Match = "exact" }, cancellationToken)).Status != DraftStatus.Ok)
        {
            // Rolls back with the transaction, including a merchant created just above.
            return null;
        }

        return merchantId;
    }

    private static async Task LockMerchantAsync(ZaghlolDbContext db, string merchantNorm, CancellationToken cancellationToken)
    {
        await using var command = Command(db, LockMerchantSql, ("merchant", merchantNorm));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static NpgsqlCommand Command(ZaghlolDbContext db, string sql, params (string Name, object Value)[] parameters)
    {
        var transaction = db.Database.CurrentTransaction
            ?? throw new InvalidOperationException("A resolution runs inside its transaction.");
        var command = new NpgsqlCommand(sql, (NpgsqlConnection)db.Database.GetDbConnection(), (NpgsqlTransaction)transaction.GetDbTransaction());
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        return command;
    }

    private static LlmCatPage<T> Page<T>(List<T> rows, int limit, int offset) =>
        new([.. rows.Take(limit)], rows.Count > limit ? (offset + limit).ToString(CultureInfo.InvariantCulture) : null);

    private ZaghlolDbContext Open() => contexts.CreateDbContext(DatabaseRole.Admin);
}

public static class LlmCatReviewServiceCollectionExtensions
{
    /// <summary>
    /// The operator review of AI categories on the Admin login. Call after <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Admin</c>
    /// and after <c>AddZaghlolCatalog</c> (a promote edits the draft under the catalog lock).
    /// </summary>
    public static IServiceCollection AddZaghlolLlmCatReview(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.AddZaghlolAudit();
        services.TryAddSingleton<ILlmCatReviewStore, LlmCatReviewStore>();
        return services;
    }
}
