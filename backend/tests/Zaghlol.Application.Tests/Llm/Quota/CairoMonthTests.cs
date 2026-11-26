using Zaghlol.Application.Llm.Quota;

namespace Zaghlol.Application.Tests.Llm.Quota;

/// <summary>T-335 AC 1: the Africa/Cairo calendar month, DST and the reset instant.</summary>
public class CairoMonthTests
{
    [Fact]
    public void SelfCheckPassesWhereTheZoneDatabaseIsInstalled() => Assert.True(CairoMonth.SelfCheck());

    [Fact]
    public void The30thNovember2350AndThe1stDecember0005CairoAreDifferentMonths()
    {
        // Cairo is UTC+2 in winter: 23:50 on 30 Nov is 21:50 UTC; 00:05 on 1 Dec is 22:05 UTC on 30 Nov.
        var november = new DateTimeOffset(2026, 11, 30, 21, 50, 0, TimeSpan.Zero);
        var december = new DateTimeOffset(2026, 11, 30, 22, 5, 0, TimeSpan.Zero);
        Assert.Equal(202611, CairoMonth.MonthKey(november));
        Assert.Equal(202612, CairoMonth.MonthKey(december));
        Assert.Equal(new DateTimeOffset(2026, 11, 30, 22, 0, 0, TimeSpan.Zero), CairoMonth.ResetsAt(november));
    }

    [Fact]
    public void ResetsAtUsesTheSummerOffsetWhenDaylightTimeIsOn()
    {
        // 1 Aug 00:00 Cairo is UTC+3, so 31 Jul 21:00 UTC; 1 Dec is UTC+2.
        Assert.Equal(new DateTimeOffset(2026, 7, 31, 21, 0, 0, TimeSpan.Zero), CairoMonth.ResetsAt(new DateTimeOffset(2026, 7, 10, 9, 0, 0, TimeSpan.Zero)));
        Assert.Equal(new DateTimeOffset(2026, 11, 30, 22, 0, 0, TimeSpan.Zero), CairoMonth.ResetsAt(new DateTimeOffset(2026, 11, 10, 9, 0, 0, TimeSpan.Zero)));
    }

    [Fact]
    public void DecemberRollsIntoNextYear()
    {
        Assert.Equal(202701, CairoMonth.MonthKey(new DateTimeOffset(2026, 12, 31, 22, 30, 0, TimeSpan.Zero)));
        Assert.Equal(new DateTimeOffset(2026, 12, 31, 22, 0, 0, TimeSpan.Zero), CairoMonth.ResetsAt(new DateTimeOffset(2026, 12, 5, 0, 0, 0, TimeSpan.Zero)));
        Assert.Equal(202512, CairoMonth.PreviousKey(new DateTimeOffset(2026, 1, 15, 0, 0, 0, TimeSpan.Zero)));
    }

    [Fact]
    public void ResetsAtIsExactlyTheMonthBoundaryInEveryMonthAcrossDaylightChanges()
    {
        for (var year = 2024; year <= 2032; year++)
        {
            for (var month = 1; month <= 12; month++)
            {
                // Noon on the 15th and on the last day, both UTC.
                foreach (var probe in new[] { new DateTimeOffset(year, month, 15, 12, 0, 0, TimeSpan.Zero), new DateTimeOffset(year, month, DateTime.DaysInMonth(year, month), 12, 0, 0, TimeSpan.Zero) })
                {
                    var key = CairoMonth.MonthKey(probe);
                    var resets = CairoMonth.ResetsAt(probe);
                    Assert.True(resets > probe);
                    Assert.Equal(key, CairoMonth.MonthKey(resets.AddMilliseconds(-1)));
                    Assert.NotEqual(key, CairoMonth.MonthKey(resets));
                }
            }
        }
    }
}
