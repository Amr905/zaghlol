using System.Globalization;

namespace Zaghlol.Application.Llm.Quota;

/// <summary>
/// The LLM quota month: the calendar month in <c>Africa/Cairo</c> (ask-llm §4.2, FR-LLM-10), so "resets on 1 December" is true in
/// the user's local time. <c>month_key</c> is <c>yyyymm</c>; <see cref="ResetsAt"/> is the first instant of the next Cairo month in UTC.
/// </summary>
public static class CairoMonth
{
    public const string ZoneId = "Africa/Cairo";

    private static readonly Lazy<TimeZoneInfo> Zone = new(() => TimeZoneInfo.FindSystemTimeZoneById(ZoneId));

    /// <summary>True when the time-zone id resolves and maps a known winter and summer instant to the right offsets.</summary>
    public static bool SelfCheck()
    {
        try
        {
            var zone = Zone.Value;
            // 31 Dec 22:30 UTC is already 1 Jan in Cairo (UTC+2). DST is deliberately not checked: tzdata may change it and the month maths holds either way.
            return MonthKey(new DateTimeOffset(2026, 12, 31, 22, 30, 0, TimeSpan.Zero)) == 202701
                && zone.GetUtcOffset(new DateTimeOffset(2026, 1, 15, 12, 0, 0, TimeSpan.Zero)) == TimeSpan.FromHours(2);
        }
        catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException or ArgumentException)
        {
            return false;
        }
    }

    public static int MonthKey(DateTimeOffset instant)
    {
        var local = TimeZoneInfo.ConvertTime(instant, Zone.Value);
        return (local.Year * 100) + local.Month;
    }

    /// <summary>The key of the month before the one containing <paramref name="instant"/>.</summary>
    public static int PreviousKey(DateTimeOffset instant)
    {
        var local = TimeZoneInfo.ConvertTime(instant, Zone.Value);
        var previous = new DateTime(local.Year, local.Month, 1, 0, 0, 0, DateTimeKind.Unspecified).AddMonths(-1);
        return (previous.Year * 100) + previous.Month;
    }

    /// <summary>The first instant of the next Cairo month, in UTC.</summary>
    public static DateTimeOffset ResetsAt(DateTimeOffset instant)
    {
        var zone = Zone.Value;
        var local = TimeZoneInfo.ConvertTime(instant, zone);
        var first = new DateTime(local.Year, local.Month, 1, 0, 0, 0, DateTimeKind.Unspecified).AddMonths(1);
        if (zone.IsInvalidTime(first))
        {
            first = first.AddHours(1);
        }

        return new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(first, zone), TimeSpan.Zero);
    }

    public static string KeyText(int monthKey) => monthKey.ToString(CultureInfo.InvariantCulture);
}
