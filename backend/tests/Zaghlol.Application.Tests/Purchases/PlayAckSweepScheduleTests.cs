using Zaghlol.Application.Purchases;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-130 security M-1: the sweeper's deferral and listing rules, which the store's SQL implements.</summary>
public class PlayAckSweepScheduleTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(0, 15)]
    [InlineData(30, 15)]
    [InlineData(60, 15)]
    [InlineData(120, 30)]
    [InlineData(240, 60)]
    [InlineData(480, 120)]
    [InlineData(47 * 60, 120)]
    [InlineData(72 * 60 - 1, 120)]
    [InlineData(72 * 60, 24 * 60)]
    [InlineData(400 * 60, 24 * 60)]
    public void TheDelayIsAQuarterOfTheAgeBetween15MinutesAnd2HoursAndADayPastTheRefund(int ageMinutes, int delayMinutes) =>
        Assert.Equal(TimeSpan.FromMinutes(delayMinutes), PlayAckSweepSchedule.RetryDelay(TimeSpan.FromMinutes(ageMinutes)));

    [Fact]
    public void AnActiveRowGetsAtLeastTwelveMoreTriesInItsLastDay()
    {
        var created = Now;
        var at = created.AddHours(48);
        var tries = 0;
        while (at < created + PlayAckSweepSchedule.RefundAge)
        {
            tries++;
            at = PlayAckSweepSchedule.NextAttemptAt(created, at);
        }

        Assert.True(tries >= 12, $"{tries} tries");
    }

    [Fact]
    public void ARowIsDueWhenNeverDeferredOrItsTimeHasCome()
    {
        Assert.True(PlayAckSweepSchedule.IsDue(null, Now));
        Assert.True(PlayAckSweepSchedule.IsDue(Now, Now));
        Assert.True(PlayAckSweepSchedule.IsDue(Now.AddSeconds(-1), Now));
        Assert.False(PlayAckSweepSchedule.IsDue(Now.AddSeconds(1), Now));
    }

    [Fact]
    public void AckableBeforePendingThenNeverDeferredThenEarliestDueThenOldest()
    {
        var rows = new (string Name, StoredPurchaseState State, DateTimeOffset? Next, DateTimeOffset Created)[]
        {
            ("pending-old", StoredPurchaseState.Pending, null, Now.AddHours(-60)),
            ("deferred-late", StoredPurchaseState.Active, Now.AddMinutes(-1), Now.AddHours(-50)),
            ("new", StoredPurchaseState.CanceledActive, null, Now.AddMinutes(-2)),
            ("deferred-early", StoredPurchaseState.InGrace, Now.AddMinutes(-30), Now.AddHours(-1)),
            ("never-old", StoredPurchaseState.Active, null, Now.AddHours(-5)),
            ("pending-deferred", StoredPurchaseState.Pending, Now.AddMinutes(-40), Now.AddHours(-70)),
        };

        var order = rows.OrderBy(r => PlayAckSweepSchedule.SortKey(r.State, r.Next, r.Created)).Select(r => r.Name);

        Assert.Equal(["never-old", "new", "deferred-early", "deferred-late", "pending-old", "pending-deferred"], order);
    }

    [Theory]
    [InlineData(StoredPurchaseState.Pending, false, true)]
    [InlineData(StoredPurchaseState.Active, false, true)]
    [InlineData(StoredPurchaseState.InGrace, false, true)]
    [InlineData(StoredPurchaseState.CanceledActive, false, true)]
    [InlineData(StoredPurchaseState.Active, true, false)]
    [InlineData(StoredPurchaseState.Expired, false, false)]
    [InlineData(StoredPurchaseState.Refunded, false, false)]
    [InlineData(StoredPurchaseState.OnHold, false, false)]
    public void OnlyUnacknowledgedPendingOrAckableRowsStayQueued(StoredPurchaseState state, bool acknowledged, bool waiting) =>
        Assert.Equal(waiting, PlayAckSweepSchedule.StillWaiting(state, acknowledged));
}
