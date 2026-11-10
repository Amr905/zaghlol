using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Contributions;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Catalog;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Contributions;

/// <summary>
/// The review queue and its two decisions on the <c>ops_rw</c> login (FR-BE-07, backend-api §5.2). Both decisions find their
/// aggregate with <b>one</b> query that excludes <c>collecting</c>, so an absent key and a collecting key take the same path
/// and give the same answer. The status change is a conditional UPDATE (<c>WHERE status = ready_for_review</c>), so two
/// operators deciding at once get one winner and one <c>409</c>. Promote runs under the catalog draft lock (the same advisory
/// lock as the catalog admin store), edits only the draft, and never publishes: nothing goes live without a publish.
/// </summary>
internal sealed class ContributionAdminStore(
    IZaghlolDbContextFactory contexts,
    CatalogAdminStore catalog,
    IAuditWriter audit,
    TimeProvider clock) : IContributionAdminStore
{
    public async Task<IReadOnlyList<ContributionAggregateView>> ListAsync(ContributionReviewStatus status, CancellationToken cancellationToken)
    {
        var stored = ToStored(status);
        await using var db = Open();
        var rows = await db.ContributionAggregates.AsNoTracking()
            .Where(a => a.Status == stored)
            .OrderByDescending(a => a.DistinctInstalls)
            .ThenBy(a => a.MerchantNorm)
            .ThenBy(a => a.InstitutionCode)
            .Take(ContributionRules.MaxQueueItems)
            .ToListAsync(cancellationToken);
        return [.. rows.Select(a => new ContributionAggregateView(a.MerchantNorm, a.InstitutionCode, a.TopCategoryCode, a.DistinctInstalls, status))];
    }

    public async Task<ContributionDecision> PromoteAsync(
        Guid operatorId,
        ContributionKey key,
        int? merchantId,
        string? categoryCode,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(key);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await CatalogAdminStore.LockAsync(db, cancellationToken);

        var aggregate = await FindReviewableAsync(db, key, cancellationToken);
        if (aggregate is null)
        {
            return new ContributionDecision(ContributionOutcome.NotFound);
        }

        if (aggregate.Status != AggregateStatus.ReadyForReview)
        {
            return new ContributionDecision(ContributionOutcome.Conflict);
        }

        var norm = aggregate.MerchantNorm;
        string categoryUsed;
        int targetMerchant;
        if (merchantId is { } existing)
        {
            // The merchant keeps its own category; a given categoryCode is not used.
            if (!await CatalogAdminStore.IsLiveAsync(db, CatalogEntity.Merchants, existing.ToString(CultureInfo.InvariantCulture), cancellationToken))
            {
                return new ContributionDecision(ContributionOutcome.Conflict);
            }

            targetMerchant = existing;
            categoryUsed = string.Empty;
        }
        else
        {
            categoryUsed = categoryCode ?? aggregate.TopCategoryCode;
            var fields = new CatalogFields { Canonical = norm, NameAr = norm, Category = categoryUsed };
            if (!CatalogValidation.IsValid(CatalogEntity.Merchants, fields))
            {
                return new ContributionDecision(ContributionOutcome.Conflict);
            }

            var created = await catalog.CreateMerchantInAsync(db, fields, cancellationToken);
            if (created.Status != DraftStatus.Ok)
            {
                return new ContributionDecision(ContributionOutcome.Conflict);
            }

            targetMerchant = created.Op!.Key.MerchantId;
        }

        var aliasFields = new CatalogFields { Match = "exact" };
        if (!CatalogKeys.TryParse(CatalogEntity.Aliases, CatalogKeys.AliasPathId(targetMerchant, norm), out var aliasKey)
            || (await catalog.ApplyPutAsync(db, aliasKey, aliasFields, cancellationToken)).Status != DraftStatus.Ok)
        {
            // Rolls back with the transaction, including a merchant created just above.
            return new ContributionDecision(ContributionOutcome.Conflict);
        }

        if (!await DecideAsync(db, aggregate, AggregateStatus.Promoted, operatorId, cancellationToken))
        {
            return new ContributionDecision(ContributionOutcome.Conflict);
        }

        await audit.WriteAsync(
            db,
            operatorId,
            new ContributionDecisionAudit(
                ContributionDecisionKind.Promote,
                aggregate.InstitutionCode,
                CatalogKeys.EncodeText(norm),
                targetMerchant,
                merchantId is null ? categoryUsed : null),
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new ContributionDecision(ContributionOutcome.Ok, ContributionReviewStatus.Promoted, targetMerchant);
    }

    public async Task<ContributionDecision> RejectAsync(Guid operatorId, ContributionKey key, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(key);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        var aggregate = await FindReviewableAsync(db, key, cancellationToken);
        if (aggregate is null)
        {
            return new ContributionDecision(ContributionOutcome.NotFound);
        }

        if (aggregate.Status != AggregateStatus.ReadyForReview
            || !await DecideAsync(db, aggregate, AggregateStatus.Rejected, operatorId, cancellationToken))
        {
            return new ContributionDecision(ContributionOutcome.Conflict);
        }

        await audit.WriteAsync(
            db,
            operatorId,
            new ContributionDecisionAudit(ContributionDecisionKind.Reject, aggregate.InstitutionCode, CatalogKeys.EncodeText(aggregate.MerchantNorm), null, null),
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new ContributionDecision(ContributionOutcome.Ok, ContributionReviewStatus.Rejected);
    }

    /// <summary>The one lookup of both decisions: the aggregate with this key in any state except <c>collecting</c>.</summary>
    private static Task<ContributionAggregate?> FindReviewableAsync(ZaghlolDbContext db, ContributionKey key, CancellationToken cancellationToken) =>
        db.ContributionAggregates.AsNoTracking()
            .Where(a => a.MerchantNorm == key.MerchantNorm && a.InstitutionCode == key.InstitutionCode && a.Status != AggregateStatus.Collecting)
            .SingleOrDefaultAsync(cancellationToken);

    /// <summary>False when another operator decided in between (the conditional UPDATE hit no row).</summary>
    private async Task<bool> DecideAsync(
        ZaghlolDbContext db,
        ContributionAggregate aggregate,
        AggregateStatus decision,
        Guid operatorId,
        CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var norm = aggregate.MerchantNorm;
        var institution = aggregate.InstitutionCode;
        var updated = await db.ContributionAggregates
            .Where(a => a.MerchantNorm == norm && a.InstitutionCode == institution && a.Status == AggregateStatus.ReadyForReview)
            .ExecuteUpdateAsync(
                s => s.SetProperty(a => a.Status, decision)
                    .SetProperty(a => a.ReviewedBy, operatorId)
                    .SetProperty(a => a.ReviewedAt, now),
                cancellationToken);
        return updated == 1;
    }

    private static AggregateStatus ToStored(ContributionReviewStatus status) => status switch
    {
        ContributionReviewStatus.ReadyForReview => AggregateStatus.ReadyForReview,
        ContributionReviewStatus.Promoted => AggregateStatus.Promoted,
        _ => AggregateStatus.Rejected,
    };

    private ZaghlolDbContext Open() => contexts.CreateDbContext(DatabaseRole.Admin);
}
