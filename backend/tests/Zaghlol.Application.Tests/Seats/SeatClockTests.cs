using Zaghlol.Application.Seats;

namespace Zaghlol.Application.Tests.Seats;

/// <summary>R3-4: the window is stored as a whole UTC hour and the cooldown check uses exactly that value.</summary>
public sealed class SeatClockTests
{
    [Theory]
    [InlineData("2026-11-11T10:00:00Z", "2026-11-11T10:00:00Z")]
    [InlineData("2026-11-11T10:00:00.0000001Z", "2026-11-11T11:00:00Z")]
    [InlineData("2026-11-11T10:17:23.456789Z", "2026-11-11T11:00:00Z")]
    [InlineData("2026-11-11T23:59:59.999Z", "2026-11-12T00:00:00Z")]
    [InlineData("2026-11-11T12:47:00+05:30", "2026-11-11T08:00:00Z")]
    public void CeilHourIsTheNextWholeUtcHour(string input, string expected)
    {
        var result = SeatClock.CeilHour(DateTimeOffset.Parse(input, System.Globalization.CultureInfo.InvariantCulture));

        Assert.Equal(DateTimeOffset.Parse(expected, System.Globalization.CultureInfo.InvariantCulture), result);
        Assert.Equal(TimeSpan.Zero, result.Offset);
        Assert.Equal(0, result.UtcTicks % TimeSpan.TicksPerHour);
    }

    [Fact]
    public void NextMoveIsCeilHourOfNowPlusThirtyDays()
    {
        var now = new DateTimeOffset(2026, 11, 11, 10, 17, 23, TimeSpan.Zero);

        Assert.Equal(new DateTimeOffset(2026, 12, 11, 11, 0, 0, TimeSpan.Zero), SeatClock.NextMoveAfter(now));
    }

    [Fact]
    public void TheCooldownEndsExactlyAtTheStoredValue()
    {
        var next = new DateTimeOffset(2026, 12, 11, 11, 0, 0, TimeSpan.Zero);

        Assert.True(SeatClock.CooldownRunning(next, next.AddSeconds(-1)));
        Assert.True(SeatClock.CooldownRunning(next, next.AddTicks(-1)));
        Assert.False(SeatClock.CooldownRunning(next, next));
        Assert.False(SeatClock.CooldownRunning(null, next));
    }

    [Fact]
    public void RebindsOlderThanThirtyDaysArePruned()
    {
        var now = new DateTimeOffset(2026, 11, 11, 10, 0, 0, TimeSpan.Zero);
        DateTimeOffset[] recent = [now.AddDays(-30), now.AddDays(-30).AddTicks(10), now.AddDays(-1)];

        Assert.Equal([now.AddDays(-30).AddTicks(10), now.AddDays(-1)], SeatClock.PruneRebinds(recent, now));
    }

    [Fact]
    public void DatabasePrecisionDropsSubMicrosecondTicks()
    {
        var t = new DateTimeOffset(2026, 11, 11, 10, 0, 0, TimeSpan.Zero).AddTicks(1234567);

        Assert.Equal(t.AddTicks(-7), SeatClock.ToDatabasePrecision(t));
    }
}
