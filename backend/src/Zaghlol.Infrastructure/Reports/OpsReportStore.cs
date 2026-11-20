using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Reports;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Reports;

/// <summary>
/// The operator read side on the Admin login (<c>ops_rw</c> has SELECT on <c>bank_requests</c> and <c>daily_active_counts</c>, and
/// on nothing else these queries touch). Only aggregates leave: the install hash is counted, never returned.
/// </summary>
internal sealed class OpsReportStore(IZaghlolDbContextFactory contexts, TimeProvider clock) : IOpsReportStore
{
    public async Task<IReadOnlyList<BankRequestRankView>> RankBankRequestsAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        var rows = await db.BankRequests.AsNoTracking()
            .GroupBy(r => new { r.InstitutionNameNorm, r.Country, r.Channel })
            .Select(g => new
            {
                g.Key.InstitutionNameNorm,
                g.Key.Country,
                g.Key.Channel,
                Count = g.Select(r => r.InstallHash).Distinct().Count(),
                Last = g.Max(r => r.ReceivedAt),
            })
            .OrderByDescending(x => x.Count)
            .ThenByDescending(x => x.Last)
            .ThenBy(x => x.InstitutionNameNorm)
            .ThenBy(x => x.Country)
            .ThenBy(x => x.Channel)
            .Take(OpsReportRules.MaxBankRequestItems)
            .ToListAsync(cancellationToken);
        return [.. rows.Select(x => new BankRequestRankView(
            x.InstitutionNameNorm, x.Country, DbEnumMaps.BankRequestChannels.ToDb(x.Channel), x.Count, x.Last))];
    }

    public async Task<IReadOnlyList<DailyActiveDayView>> DailyActiveAsync(int days, CancellationToken cancellationToken)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(days, OpsReportRules.MinDailyActiveDays);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(days, OpsReportRules.MaxDailyActiveDays);

        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var first = today.AddDays(1 - days);
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        var sums = await db.DailyActiveCounts.AsNoTracking()
            .Where(d => d.Day >= first && d.Day <= today)
            .GroupBy(d => d.Day)
            .Select(g => new { Day = g.Key, Total = g.Sum(d => (long)d.Installs) })
            .ToDictionaryAsync(x => x.Day, x => x.Total, cancellationToken);

        var result = new List<DailyActiveDayView>(days);
        for (var i = 0; i < days; i++)
        {
            var day = first.AddDays(i);
            result.Add(new DailyActiveDayView(day, sums.TryGetValue(day, out var total) ? (int)Math.Min(total, int.MaxValue) : 0));
        }

        return result;
    }
}

public static class OpsReportServiceCollectionExtensions
{
    /// <summary>The operator reports on the Admin login. Call after <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Admin</c>.</summary>
    public static IServiceCollection AddZaghlolOpsReports(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<IOpsReportStore, OpsReportStore>();
        return services;
    }
}
