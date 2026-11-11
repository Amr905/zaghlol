using Zaghlol.Application.Seats;
using static Zaghlol.Application.Seats.HolderRelation;

namespace Zaghlol.Application.Tests.Seats;

/// <summary>The state table of the T-184 design note §4, cell by cell (holder × channel × cooldown × key match × cap × trusted).</summary>
public sealed class SeatRulesTests
{
    public static TheoryData<string, SeatFacts, SeatOutcome, SeatAction, SeatClaimantChannel?, string?, bool, bool> Cells => new()
    {
        // Verify (backend-api §4.3 Seat at verify; R4-4, D-59, D-61(a)).
        { "V1", new(SeatChannel.Verify, None), SeatOutcome.Bound, SeatAction.Bind, null, "seat_bind", false, false },
        { "V1", new(SeatChannel.Verify, None, Cooldown: true, NewPayment: true, AccountBlocks: true), SeatOutcome.Bound, SeatAction.Bind, null, "seat_bind", false, false },
        { "V3", new(SeatChannel.Verify, Self, Cooldown: true, NewPayment: true, AccountBlocks: true), SeatOutcome.Unchanged, SeatAction.Refresh, null, null, false, false },
        { "V4", new(SeatChannel.Verify, Other), SeatOutcome.Unchanged, SeatAction.None, null, null, false, false },
        { "V4", new(SeatChannel.Verify, Vacant), SeatOutcome.Unchanged, SeatAction.None, null, null, false, false },
        { "V5", new(SeatChannel.Verify, Other, NewPayment: true, AccountBlocks: true), SeatOutcome.AccountRequired, SeatAction.None, SeatClaimantChannel.Verify, null, false, false },
        { "V5", new(SeatChannel.Verify, Other, Cooldown: true, NewPayment: true, AccountBlocks: true), SeatOutcome.AccountRequired, SeatAction.None, SeatClaimantChannel.Verify, null, false, false },
        { "V6", new(SeatChannel.Verify, Other, NewPayment: true), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:verify", false, false },
        { "V6", new(SeatChannel.Verify, Vacant, NewPayment: true), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:verify", false, false },
        { "V7", new(SeatChannel.Verify, Other, Cooldown: true, NewPayment: true), SeatOutcome.ClaimantAdded, SeatAction.None, SeatClaimantChannel.Verify, null, false, false },

        // Restore (backend-api §4.3 step 5; D-55, D-63, D-65(a)).
        { "R1", new(SeatChannel.Restore, Self, AccountBlocks: true), SeatOutcome.AccountRequired, SeatAction.None, null, null, false, false },
        { "R1", new(SeatChannel.Restore, Other, KeyMatch: true, AccountBlocks: true), SeatOutcome.AccountRequired, SeatAction.None, null, null, false, false },
        { "R2", new(SeatChannel.Restore, Self, Cooldown: true, KeyMatch: true, CapReached: true), SeatOutcome.Unchanged, SeatAction.Refresh, null, null, false, false },
        { "R3", new(SeatChannel.Restore, Other, Cooldown: true, KeyMatch: true), SeatOutcome.Rebound, SeatAction.Rebind, null, "seat_rebind:restore", false, false },
        { "R3", new(SeatChannel.Restore, Vacant, Cooldown: true, KeyMatch: true), SeatOutcome.Rebound, SeatAction.Rebind, null, "seat_rebind:restore", false, false },
        { "R4", new(SeatChannel.Restore, Other, Cooldown: true, KeyMatch: true, CapReached: true), SeatOutcome.ReboundOverCap, SeatAction.RebindOverCap, null, "seat_rebind_over_cap:restore", false, true },
        { "R4", new(SeatChannel.Restore, Other, KeyMatch: true, CapReached: true, KeyTrusted: false), SeatOutcome.ReboundOverCap, SeatAction.RebindOverCap, null, "seat_rebind_over_cap:restore", false, true },
        { "R5", new(SeatChannel.Restore, Other), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:restore", false, false },
        { "R5", new(SeatChannel.Restore, Vacant), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:restore", false, false },
        { "R5", new(SeatChannel.Restore, None, KeyMatch: true), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:restore", false, false },
        { "R6", new(SeatChannel.Restore, Other, Cooldown: true), SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.Restore, null, false, false },
        { "R6", new(SeatChannel.Restore, Vacant, Cooldown: true, CapReached: true, KeyTrusted: true), SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.Restore, null, false, false },

        // Sign-in (backend-api §4.6 steps 4–5; D-58, D-61(b), D-65(a), D-66).
        { "S1", new(SeatChannel.SignIn, Self, AccountBlocks: true), SeatOutcome.AccountRequired, SeatAction.None, null, null, false, false },
        { "S2", new(SeatChannel.SignIn, Self, Cooldown: true, KeyMatch: true, ReclaimEligible: true), SeatOutcome.Unchanged, SeatAction.Refresh, null, null, false, false },
        { "S3", new(SeatChannel.SignIn, Other, Cooldown: true, KeyMatch: true, ReclaimEligible: true), SeatOutcome.Moved, SeatAction.Reclaim, null, "seat_move:account_attach", false, false },
        { "S3", new(SeatChannel.SignIn, Vacant, Cooldown: true, ReclaimEligible: true), SeatOutcome.Moved, SeatAction.Reclaim, null, "seat_move:account_attach", false, false },
        { "S4", new(SeatChannel.SignIn, Other, Cooldown: true, KeyMatch: true), SeatOutcome.Rebound, SeatAction.Rebind, null, "seat_rebind:signin", false, false },
        { "S5", new(SeatChannel.SignIn, Other, Cooldown: true, KeyMatch: true, CapReached: true, KeyTrusted: true), SeatOutcome.ReboundOverCap, SeatAction.RebindOverCap, null, "seat_rebind_over_cap:signin", false, true },
        { "S6", new(SeatChannel.SignIn, Other, KeyMatch: true, CapReached: true), SeatOutcome.Moved, SeatAction.Move, null, "seat_rebind_over_cap:signin", true, true },
        { "S7", new(SeatChannel.SignIn, Other, Cooldown: true, KeyMatch: true, CapReached: true), SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.SignIn, "seat_rebind_over_cap:signin", true, true },
        { "S8", new(SeatChannel.SignIn, Other), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:signin", false, false },
        { "S8", new(SeatChannel.SignIn, None), SeatOutcome.Moved, SeatAction.Move, null, "seat_move:signin", false, false },
        { "S9", new(SeatChannel.SignIn, Other, Cooldown: true), SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.SignIn, null, false, false },

        // Support (backend-api §5.3; D-56, R5-4): cooldown and cap never matter.
        { "P1", new(SeatChannel.Support, None, SupportEligible: true), SeatOutcome.NotEligible, SeatAction.None, null, null, false, false },
        { "P1", new(SeatChannel.Support, Other, Cooldown: true), SeatOutcome.NotEligible, SeatAction.None, null, null, false, false },
        { "P2", new(SeatChannel.Support, Self), SeatOutcome.Unchanged, SeatAction.None, null, null, false, false },
        { "P3", new(SeatChannel.Support, Other, Cooldown: true, CapReached: true, SupportEligible: true), SeatOutcome.Moved, SeatAction.SupportMove, null, "seat_move:support", false, false },
        { "P3", new(SeatChannel.Support, Vacant, SupportEligible: true), SeatOutcome.Moved, SeatAction.SupportMove, null, "seat_move:support", false, false },
    };

    [Theory]
    [MemberData(nameof(Cells))]
    public void EveryCellDecidesAsDocumented(
        string cell, SeatFacts facts, SeatOutcome outcome, SeatAction action, SeatClaimantChannel? claimant, string? cause, bool restoreSuggested, bool alert)
    {
        var decision = SeatRules.Decide(facts);

        Assert.Equal(cell, decision.Cell);
        Assert.Equal(outcome, decision.Outcome);
        Assert.Equal(action, decision.Action);
        Assert.Equal(claimant, decision.Claimant);
        Assert.Equal(cause, decision.Cause);
        Assert.Equal(restoreSuggested, decision.RestoreSuggested);
        Assert.Equal(alert, decision.Alert);
    }

    [Fact]
    public void EveryDocumentedCellIsCovered()
    {
        var covered = Cells.Select(row => (string)row[0]).ToHashSet();
        string[] table = ["V1", "V3", "V4", "V5", "V6", "V7", "R1", "R2", "R3", "R4", "R5", "R6", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "P1", "P2", "P3"];

        Assert.Equal(table.Order(), covered.Order());
    }

    [Fact]
    public void EveryCauseIsADocumentedPurchaseEventCause()
    {
        var pattern = new System.Text.RegularExpressions.Regex(
            "^(verify|restore|seat_bind|sweep|seat_move:(restore|signin|support|account_attach|verify)|seat_rebind:(restore|signin)"
            + "|seat_rebind_over_cap:(restore|signin)|(rtdn|assn):[A-Za-z0-9_]{1,64})$");
        foreach (var cause in typeof(SeatCauses).GetFields().Select(f => (string)f.GetRawConstantValue()!))
        {
            Assert.Matches(pattern, cause);
        }
    }

    [Fact]
    public void AMatchOnElementZeroIsNeverARebind()
    {
        // The service only reports a match for positions >= 1 (T-182 MatchSeatAsync); without one, a cooldown refuses.
        Assert.Equal(SeatOutcome.Refused, SeatRules.Decide(new(SeatChannel.Restore, Other, Cooldown: true, KeyMatch: false)).Outcome);
        Assert.Equal(SeatOutcome.Refused, SeatRules.Decide(new(SeatChannel.SignIn, Other, Cooldown: true, KeyMatch: false)).Outcome);
    }

    [Fact]
    public void VerifyIsNeverRefusedAndNeverRebinds()
    {
        foreach (var holder in Enum.GetValues<HolderRelation>())
        {
            foreach (var bits in Enumerable.Range(0, 64))
            {
                var facts = new SeatFacts(
                    SeatChannel.Verify, holder, (bits & 1) != 0, (bits & 2) != 0, (bits & 4) != 0, (bits & 8) != 0, (bits & 16) != 0, (bits & 32) != 0);
                var decision = SeatRules.Decide(facts);
                Assert.NotEqual(SeatOutcome.Refused, decision.Outcome);
                Assert.DoesNotContain(decision.Action, new[] { SeatAction.Rebind, SeatAction.RebindOverCap });
            }
        }
    }

    [Fact]
    public void AnUnknownChannelIsRefused() =>
        Assert.Throws<ArgumentOutOfRangeException>(() => SeatRules.Decide(new((SeatChannel)99, Other)));
}
