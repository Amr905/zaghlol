namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>OpenAPI <c>BankRequestRank</c>; <c>LastRequestedAt</c> is an RFC 3339 UTC instant ending in <c>Z</c>.</summary>
public sealed record BankRequestRankDto(string InstitutionName, string Country, string Channel, int Count, string LastRequestedAt);

/// <summary>OpenAPI <c>BankRequestRanking</c>.</summary>
public sealed record BankRequestRankingDto(IReadOnlyList<BankRequestRankDto> Items);

/// <summary>OpenAPI <c>DailyActiveDay</c>; <c>Date</c> is <c>yyyy-MM-dd</c> (UTC).</summary>
public sealed record DailyActiveDayDto(string Date, int ActiveInstalls);

/// <summary>OpenAPI <c>DailyActiveMetrics</c>.</summary>
public sealed record DailyActiveMetricsDto(IReadOnlyList<DailyActiveDayDto> Days);
