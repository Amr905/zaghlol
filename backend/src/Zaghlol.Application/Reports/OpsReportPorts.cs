namespace Zaghlol.Application.Reports;

/// <summary>Limits of the operator read side (backend-api §5, FR-BE-10).</summary>
public static class OpsReportRules
{
    /// <summary>The bank-request ranking is one page of at most this many institutions, most requested first.</summary>
    public const int MaxBankRequestItems = 500;

    public const int MinDailyActiveDays = 1;

    public const int MaxDailyActiveDays = 90;

    public const int DefaultDailyActiveDays = 14;
}

/// <summary>One ranked "request my bank" entry: how many distinct installs asked, and when last.</summary>
public sealed record BankRequestRankView(string InstitutionName, string Country, string Channel, int Count, DateTimeOffset LastRequestedAt);

/// <summary>One UTC day of the anonymous active-install counters, summed over platform and app version.</summary>
public sealed record DailyActiveDayView(DateOnly Date, int ActiveInstalls);

/// <summary>Read-only aggregates for operators (no install identifier ever leaves the store).</summary>
public interface IOpsReportStore
{
    /// <summary>Institutions by distinct installs descending, then last request descending; at most <see cref="OpsReportRules.MaxBankRequestItems"/>.</summary>
    Task<IReadOnlyList<BankRequestRankView>> RankBankRequestsAsync(CancellationToken cancellationToken);

    /// <summary>The last <paramref name="days"/> UTC days ending today, oldest first, with a zero for a day without counts.</summary>
    Task<IReadOnlyList<DailyActiveDayView>> DailyActiveAsync(int days, CancellationToken cancellationToken);
}
