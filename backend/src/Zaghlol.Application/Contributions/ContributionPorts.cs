using System.Diagnostics.CodeAnalysis;

namespace Zaghlol.Application.Contributions;

/// <summary>
/// The review state an operator can see (OpenAPI <c>ContributionStatus</c>). The stored <c>collecting</c> state (fewer than 5
/// distinct installs, A-48) has no member here, so no query that returns this type can expose it.
/// </summary>
public enum ContributionReviewStatus
{
    ReadyForReview,
    Promoted,
    Rejected,
}

public static class ContributionStatuses
{
    public const string ReadyForReview = "ready_for_review";
    public const string Promoted = "promoted";
    public const string Rejected = "rejected";

    public static string Wire(ContributionReviewStatus status) => status switch
    {
        ContributionReviewStatus.ReadyForReview => ReadyForReview,
        ContributionReviewStatus.Promoted => Promoted,
        _ => Rejected,
    };

    /// <summary>Exact, case-sensitive; anything else (including <c>collecting</c>) is not a status.</summary>
    public static bool TryParse(string? text, out ContributionReviewStatus status)
    {
        switch (text)
        {
            case ReadyForReview:
                status = ContributionReviewStatus.ReadyForReview;
                return true;
            case Promoted:
                status = ContributionReviewStatus.Promoted;
                return true;
            case Rejected:
                status = ContributionReviewStatus.Rejected;
                return true;
            default:
                status = default;
                return false;
        }
    }
}

/// <summary>Contribution thresholds and limits.</summary>
public static class ContributionRules
{
    /// <summary>A-48: an aggregate is shown for review only from this many distinct installs.</summary>
    public const int MinDistinctInstalls = 5;

    /// <summary>Raw rows are deleted after this many days at the latest (backend-schema §4).</summary>
    public const int RawRetentionDays = 180;

    /// <summary>The review queue is one page of at most this many aggregates, most-contributed first.</summary>
    public const int MaxQueueItems = 500;

    /// <summary>The longest <c>merchantNorm</c> the API accepts in a body (OpenAPI); stored text is at most 64.</summary>
    public const int MaxKeyLength = 80;

    public const int MinKeyLength = 2;
}

/// <summary>The identity of one aggregate: the normalized merchant text and the institution.</summary>
public sealed record ContributionKey(string MerchantNorm, string InstitutionCode);

/// <summary>One row of the review queue (OpenAPI <c>ContributionAggregate</c>): counts only, never per install.</summary>
public sealed record ContributionAggregateView(
    string MerchantNorm,
    string InstitutionCode,
    string CategoryCode,
    int DistinctInstalls,
    ContributionReviewStatus Status);

public enum ContributionOutcome
{
    Ok,

    /// <summary>No aggregate has the key, or it is still <c>collecting</c>: one query, one answer for both.</summary>
    NotFound,

    /// <summary>Already promoted or rejected, or the draft refuses the change (409 ADMIN_CONFLICT).</summary>
    Conflict,
}

/// <summary>The result of a decision; <see cref="MerchantId"/> is set by promote.</summary>
public sealed record ContributionDecision(ContributionOutcome Outcome, ContributionReviewStatus Status = default, int? MerchantId = null);

/// <summary>The operator side of the queue (Admin login). Every decision is audited in its own transaction.</summary>
public interface IContributionAdminStore
{
    /// <summary>Aggregates in one state, most installs first, at most <see cref="ContributionRules.MaxQueueItems"/>.</summary>
    Task<IReadOnlyList<ContributionAggregateView>> ListAsync(ContributionReviewStatus status, CancellationToken cancellationToken);

    /// <summary>
    /// With <paramref name="merchantId"/> the merchant text becomes an <c>exact</c> alias of that live draft merchant; without it
    /// a new draft merchant is created (<c>canonical</c> = the text) with the text as its alias, in
    /// <paramref name="categoryCode"/> or the top-voted category. The aggregate becomes <c>promoted</c>. Nothing is published.
    /// </summary>
    Task<ContributionDecision> PromoteAsync(
        Guid operatorId,
        ContributionKey key,
        int? merchantId,
        string? categoryCode,
        CancellationToken cancellationToken);

    Task<ContributionDecision> RejectAsync(Guid operatorId, ContributionKey key, CancellationToken cancellationToken);
}

/// <summary>What one aggregation run did.</summary>
/// <param name="Updated">Aggregate rows written or refreshed.</param>
/// <param name="BecameReady">Aggregates that reached <see cref="ContributionRules.MinDistinctInstalls"/> in this run.</param>
/// <param name="PurgedDecided">Raw rows deleted because their aggregate is promoted or rejected.</param>
/// <param name="PurgedExpired">Raw rows deleted for age.</param>
public sealed record AggregationRun(int Updated, int BecameReady, int PurgedDecided, int PurgedExpired);

/// <summary>The worker side (Worker login): roll raw rows up into aggregates, then purge per retention.</summary>
public interface IContributionAggregationStore
{
    Task<AggregationRun> RunAsync(int minDistinctInstalls, DateTimeOffset rawCutoff, CancellationToken cancellationToken);
}

/// <summary>Fixed event names of <c>zaghlol.contribution.events</c>.</summary>
public static class ContributionEvents
{
    public const string Ready = "ready";
    public const string Promoted = "promoted";
    public const string Rejected = "rejected";
    public const string PurgedDecided = "purged_decided";
    public const string PurgedExpired = "purged_expired";

    public static IReadOnlyList<string> All { get; } = [Ready, Promoted, Rejected, PurgedDecided, PurgedExpired];
}

public interface IContributionMetrics
{
    /// <param name="name">A value of <see cref="ContributionEvents.All"/>.</param>
    void Event(string name, int count);
}

/// <summary>One aggregation run (the worker calls it on a timer).</summary>
public sealed class ContributionAggregationJob(IContributionAggregationStore store, IContributionMetrics metrics, TimeProvider clock)
{
    public async Task<AggregationRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var cutoff = clock.GetUtcNow().AddDays(-ContributionRules.RawRetentionDays);
        var run = await store.RunAsync(ContributionRules.MinDistinctInstalls, cutoff, cancellationToken);
        metrics.Event(ContributionEvents.Ready, run.BecameReady);
        metrics.Event(ContributionEvents.PurgedDecided, run.PurgedDecided);
        metrics.Event(ContributionEvents.PurgedExpired, run.PurgedExpired);
        return run;
    }
}

/// <summary>Validation of the key and codes of the admin bodies (400 <c>VALIDATION_FAILED</c> before any lookup).</summary>
public static class ContributionKeys
{
    public static bool IsValidKey([NotNullWhen(true)] string? merchantNorm, [NotNullWhen(true)] string? institutionCode) =>
        merchantNorm is { Length: >= ContributionRules.MinKeyLength and <= ContributionRules.MaxKeyLength }
        && merchantNorm.All(c => !char.IsControl(c))
        && Zaghlol.Application.Sync.SyncIntake.IsInstitutionCode(institutionCode);
}
