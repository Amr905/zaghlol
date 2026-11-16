using Zaghlol.Application.Audit;
using Zaghlol.Application.Support;

namespace Zaghlol.Application.Tests.Support;

/// <summary>T-186: the pure rules of the support write path (freeze, R6-1, attach gate, move-back and attach sources).</summary>
public class SupportRulesTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 16, 12, 0, 0, TimeSpan.Zero);
    private static readonly Guid Agent = Guid.NewGuid();
    private static readonly Guid Lead = Guid.NewGuid();

    private static SupportAuditRow Row(
        Guid? op = null, string action = "support_seat_move", string outcome = SupportOutcomes.Moved, Guid? from = null, Guid? attached = null, TimeSpan? age = null) =>
        new(1, op ?? Agent, action, Now - (age ?? TimeSpan.FromHours(1)), "other", outcome, from, attached, null);

    [Fact]
    public void AFreezeRunsUntilItsInstant()
    {
        Assert.True(SupportRules.Frozen(Now.AddSeconds(1), Now));
        Assert.False(SupportRules.Frozen(Now, Now));
        Assert.False(SupportRules.Frozen(null, Now));
    }

    [Fact]
    public void TheUnfreezeLockHoldsFor24HoursAndOnlyForTheUnfreezingOperator()
    {
        Assert.True(SupportRules.UnfreezeLockActive(Row(Lead, age: TimeSpan.FromHours(23)), Lead, Now));
        Assert.False(SupportRules.UnfreezeLockActive(Row(Lead, age: TimeSpan.FromHours(24)), Lead, Now));
        Assert.False(SupportRules.UnfreezeLockActive(Row(Lead, age: TimeSpan.FromHours(1)), Agent, Now));
        Assert.False(SupportRules.UnfreezeLockActive(null, Lead, Now));
    }

    [Fact]
    public void UnfreezeNeedsAnOperatorDifferentFromTheFreezerAndFromTheReversedRowsOperator()
    {
        var other = Guid.NewGuid();
        var freezer = Row(Agent);

        Assert.True(SupportRules.UnfreezeOperatorAllowed(Lead, freezer, null));
        Assert.True(SupportRules.UnfreezeOperatorAllowed(Lead, freezer, Row(other)));
        Assert.False(SupportRules.UnfreezeOperatorAllowed(Agent, freezer, null));
        Assert.False(SupportRules.UnfreezeOperatorAllowed(other, freezer, Row(other)));
        Assert.False(SupportRules.UnfreezeOperatorAllowed(Lead, null, null));
    }

    [Fact]
    public void AnUnfreezeWaitsTwentyFourHoursFromTheFreezeRow()
    {
        Assert.False(SupportRules.FreezeLockElapsed(Row(age: TimeSpan.FromHours(23)), Now));
        Assert.True(SupportRules.FreezeLockElapsed(Row(age: TimeSpan.FromHours(24)), Now));
        Assert.False(SupportRules.FreezeLockElapsed(null, Now));
    }

    [Theory]
    [InlineData(false, true, true, true)]
    [InlineData(true, true, true, false)]
    [InlineData(false, false, true, false)]
    [InlineData(false, true, false, false)]
    public void TheAttachGateNeedsNoAccountATargetAccountAndASilentBuyer(bool purchaseHasAccount, bool targetHasAccount, bool silent, bool allowed) =>
        Assert.Equal(
            allowed,
            SupportRules.AttachGate(purchaseHasAccount ? Guid.NewGuid() : null, targetHasAccount ? Guid.NewGuid() : null, silent));

    [Fact]
    public void AMoveBackSourceIsAMovedRowOfThisTargetUnderAYear()
    {
        var target = Guid.NewGuid();

        Assert.True(SupportRules.IsMoveBackSource(Row(from: target), target, Now));
        Assert.True(SupportRules.IsMoveBackSource(Row(outcome: SupportOutcomes.MovedAndAttached, from: target), target, Now));
        Assert.False(SupportRules.IsMoveBackSource(Row(from: Guid.NewGuid()), target, Now));
        Assert.False(SupportRules.IsMoveBackSource(Row(outcome: SupportOutcomes.Noop, from: target), target, Now));
        Assert.False(SupportRules.IsMoveBackSource(Row(outcome: SupportOutcomes.Attached, from: target), target, Now));
        Assert.False(SupportRules.IsMoveBackSource(Row(from: target, age: TimeSpan.FromDays(366)), target, Now));
        Assert.False(SupportRules.IsMoveBackSource(Row(action: "support_detach", from: target), target, Now));
        Assert.False(SupportRules.IsMoveBackSource(null, target, Now));
    }

    [Fact]
    public void AnAttachSourceNamesTheCurrentAccount()
    {
        var account = Guid.NewGuid();

        Assert.True(SupportRules.IsAttachSource(Row(outcome: SupportOutcomes.Attached, attached: account), account));
        Assert.True(SupportRules.IsAttachSource(Row(outcome: SupportOutcomes.MovedAndAttached, attached: account), account));
        Assert.False(SupportRules.IsAttachSource(Row(outcome: SupportOutcomes.Attached, attached: Guid.NewGuid()), account));
        Assert.False(SupportRules.IsAttachSource(Row(outcome: SupportOutcomes.Moved, attached: account), account));
        Assert.False(SupportRules.IsAttachSource(null, account));
    }

    [Theory]
    [InlineData("ZG-10422", true)]
    [InlineData("a_b-1", true)]
    [InlineData("", false)]
    [InlineData("has space", false)]
    [InlineData("a@b.example", false)]
    [InlineData("12345678901234567890123456789012x", false)]
    [InlineData("ticket\n", false)]
    public void ATicketRefIsATicketNumber(string text, bool valid) => Assert.Equal(valid, SupportTicketRef.IsValid(text));

    [Fact]
    public void TheSupportAuditEntriesAreFixedWordsWithThePurchaseAsTarget()
    {
        var purchase = Guid.NewGuid();

        Assert.Equal(("support_seat_move", purchase.ToString("D")), Pair(new SupportSeatMoveAudit(purchase, null, Guid.NewGuid(), "other", "ZG-1", null, null, "pass", "moved")));
        Assert.Equal(("support_detach", purchase.ToString("D")), Pair(new SupportDetachAudit(purchase, null, "ZG-1", 3, "pass", "noop")));
        Assert.Equal(("support_unfreeze", purchase.ToString("D")), Pair(new SupportUnfreezeAudit(purchase, "ZG-1", null, null, "not_run", "noop")));
        Assert.Throws<ArgumentException>(() => new SupportUnfreezeAudit(purchase, "a@b.example", null, null, "not_run", "noop").Details());
    }

    private static (string, string) Pair(AuditEntry entry) => (entry.Action, entry.Target);
}
