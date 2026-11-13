using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using static Zaghlol.Application.Tests.Entitlements.EntitlementTestKit;

namespace Zaghlol.Application.Tests.Entitlements;

/// <summary>T-132: the pure token decision (status, plan, lifetimes, account rule, moved).</summary>
public sealed class EntitlementRulesTests
{
    [Fact]
    public void AnActivePurchaseGivesAnActiveTokenForTheCallingInstall()
    {
        var token = Build(Facts(Held()));

        Assert.Equal("active", token.Status);
        Assert.Equal(Caller.ToString(), token.Sub);
        Assert.Equal("yearly", token.Plan);
        Assert.Equal("zaghlol", token.Iss);
        Assert.Equal(1, token.V);
        Assert.Null(token.Acct);
        Assert.Null(token.MovedBy);
        Assert.Equal([new EntitlementSource("google_play", "zaghlol_gold_yearly")], token.Src);
    }

    [Fact]
    public void ARefundedPurchaseGivesStatusRefunded()
    {
        Assert.Equal("refunded", Build(Facts(Held(state: StoredPurchaseState.Refunded))).Status);
        Assert.Equal("refunded", Build(Facts(Held(state: StoredPurchaseState.Revoked))).Status);
    }

    [Fact]
    public void AnEntitlingPurchaseBeatsARefundedOne()
    {
        var token = Build(Facts(Held(state: StoredPurchaseState.Refunded), Held(GoldPlan.Monthly)));

        Assert.Equal("active", token.Status);
        Assert.Equal("monthly", token.Plan);
    }

    [Theory]
    [InlineData(StoredPurchaseState.Expired)]
    [InlineData(StoredPurchaseState.OnHold)]
    [InlineData(StoredPurchaseState.Paused)]
    [InlineData(StoredPurchaseState.Pending)]
    public void ANonEntitlingStateGivesExpired(StoredPurchaseState state) =>
        Assert.Equal("expired", Build(Facts(Held(state: state))).Status);

    [Fact]
    public void AnEntitlingStateWhoseExpiryHasPassedIsExpiredNotGold() =>
        Assert.Equal("expired", Build(Facts(Held(expiresAt: Now.AddMinutes(-1)))).Status);

    [Fact]
    public void BillingGraceGivesGraceAndCanceledButPaidStaysActive()
    {
        Assert.Equal("grace", Build(Facts(Held(state: StoredPurchaseState.InGrace))).Status);
        Assert.Equal("active", Build(Facts(Held(state: StoredPurchaseState.CanceledActive))).Status);
    }

    [Fact]
    public void NoPurchaseGivesNone()
    {
        var token = Build(EntitlementFacts.Empty);

        Assert.Equal("none", token.Status);
        Assert.Equal("none", token.Plan);
        Assert.Empty(token.Src);
        Assert.Equal(Caller.ToString(), token.Sub);
    }

    [Fact]
    public void AnAccountLinkedPurchaseWithoutTheAccountTokenIsPaused()
    {
        var token = Build(Facts(Held(account: Account)), account: null);

        Assert.Equal("paused", token.Status);
        Assert.Null(token.Acct);
    }

    [Fact]
    public void AnAccountLinkedPurchaseWithAnotherAccountsTokenIsPaused() =>
        Assert.Equal("paused", Build(Facts(Held(account: Account)), account: Guid.NewGuid()).Status);

    [Fact]
    public void AnAccountLinkedPurchaseWithItsAccountTokenIsActiveAndNamesTheAccount()
    {
        var token = Build(Facts(Held(account: Account)), account: Account);

        Assert.Equal("active", token.Status);
        Assert.Equal(Account.ToString("D"), token.Acct);
    }

    [Fact]
    public void AnUnlinkedActivePurchaseBeatsAPausedLinkedOne()
    {
        var token = Build(Facts(Held(account: Account), Held(GoldPlan.Monthly)), account: null);

        Assert.Equal("active", token.Status);
        Assert.Null(token.Acct);
    }

    [Theory]
    [InlineData(SeatMovedBy.User, "user")]
    [InlineData(SeatMovedBy.Support, "support")]
    public void AFormerHolderGetsMovedWithWhoMovedIt(SeatMovedBy by, string wire)
    {
        var next = new DateTimeOffset(2026, 11, 23, 10, 0, 0, TimeSpan.Zero);
        var lost = new LostPurchase(Guid.NewGuid(), PurchaseStore.AppStore, "zaghlol_gold_yearly", GoldPlan.Yearly, next, by);

        var token = Build(new EntitlementFacts([], [lost]));

        Assert.Equal("moved", token.Status);
        Assert.Equal(wire, token.MovedBy);
        Assert.Equal("2026-11-23T10:00:00Z", token.NextMoveAt);
    }

    [Fact]
    public void MovedNeverCarriesAMovedByOnOtherStatuses() => Assert.Null(Build(Facts(Held())).MovedBy);

    [Fact]
    public void NextMoveAtIsTheStoredHourOnlyWhileTheCooldownRuns()
    {
        var running = new DateTimeOffset(2026, 12, 1, 10, 0, 0, TimeSpan.Zero);

        Assert.Equal("2026-12-01T10:00:00Z", Build(Facts(Held(nextMoveAt: running))).NextMoveAt);
        Assert.Null(Build(Facts(Held(nextMoveAt: Now.AddHours(-1)))).NextMoveAt);
        Assert.Null(Build(Facts(Held())).NextMoveAt);
    }

    [Fact]
    public void TheLongestPlanNamesTheToken()
    {
        var token = Build(Facts(Held(GoldPlan.Monthly), Held(GoldPlan.Lifetime), Held(GoldPlan.Yearly)));

        Assert.Equal("lifetime", token.Plan);
        Assert.Equal(3, token.Src.Count);
    }

    [Fact]
    public void ASubscriptionTokenNeverOutlivesTheStoreExpiry()
    {
        var token = Build(Facts(Held(expiresAt: Now.AddHours(5))));

        Assert.Equal(EntitlementRules.Whole(Now.AddHours(5)).ToUnixTimeSeconds(), token.Exp);
    }

    [Fact]
    public void ABasicSeatTokenLivesTwoDaysAndOtherTokensThree()
    {
        var iat = EntitlementRules.Whole(Now);

        Assert.Equal((iat + TimeSpan.FromDays(2)).ToUnixTimeSeconds(), Build(Facts(Held(GoldPlan.Lifetime, proof: SeatProofKind.Basic))).Exp);
        Assert.Equal((iat + TimeSpan.FromDays(3)).ToUnixTimeSeconds(), Build(Facts(Held(GoldPlan.Lifetime))).Exp);
    }

    /// <summary>D-60 as a property over seeded random facts: lifetimes, grace, store expiry, install binding.</summary>
    [Fact]
    public void D60TheLifetimeBoundsHoldForEveryPlanStateAndSeatProof()
    {
        var random = new Random(2026_11_13);
        var plans = Enum.GetValues<GoldPlan>();
        var states = Enum.GetValues<StoredPurchaseState>();
        var proofs = Enum.GetValues<SeatProofKind>();
        for (var i = 0; i < 2000; i++)
        {
            var now = Now.AddSeconds(random.Next(0, 86_400 * 30)).AddTicks(random.Next(0, 10_000_000));
            var held = Enumerable.Range(0, random.Next(0, 4))
                .Select(_ =>
                {
                    var plan = plans[random.Next(plans.Length)];
                    return new HeldPurchase(
                        Guid.NewGuid(),
                        PurchaseStore.AppStore,
                        "zaghlol_gold_" + EntitlementWire.Plan(plan),
                        plan,
                        states[random.Next(states.Length)],
                        plan == GoldPlan.Lifetime ? null : now.AddSeconds(random.Next(-86_400, 86_400 * 40)),
                        random.Next(3) == 0 ? Account : null,
                        proofs[random.Next(proofs.Length)],
                        random.Next(2) == 0 ? null : now.AddHours(random.Next(-5, 700)));
                })
                .ToList();
            var presented = random.Next(2) == 0 ? Account : (Guid?)null;

            var token = EntitlementRules.Build(Caller, new EntitlementFacts(held, []), presented, now);

            Assert.Equal(Caller.ToString(), token.Sub);
            if (token.Status is "active" or "grace" && held.Count > 0 && held.All(h => h.Proof == SeatProofKind.Basic))
            {
                Assert.True(token.Exp - token.Iat <= TimeSpan.FromDays(2).TotalSeconds);
            }

            Assert.True(token.Exp - token.Iat <= TimeSpan.FromDays(3).TotalSeconds);
            Assert.Equal(TimeSpan.FromDays(4).TotalSeconds, token.GraceUntil - token.Exp);
            Assert.True(token.Exp >= token.Iat);
            if (token.Status is "active" or "grace")
            {
                var expiries = held.Select(h => h.ExpiresAt).ToList();
                Assert.True(expiries.Contains(null) || token.Exp <= expiries.Max()!.Value.ToUnixTimeSeconds());
            }
        }
    }

    [Theory]
    [InlineData(GoldPlan.Monthly)]
    [InlineData(GoldPlan.Yearly)]
    [InlineData(GoldPlan.Lifetime)]
    public void EveryPlanIncludingLifetimeIsCappedAtThreeDays(GoldPlan plan)
    {
        var token = Build(Facts(Held(plan, expiresAt: Now.AddDays(300))));

        Assert.Equal(TimeSpan.FromDays(3).TotalSeconds, token.Exp - token.Iat);
        Assert.Equal(TimeSpan.FromDays(4).TotalSeconds, token.GraceUntil - token.Exp);
    }

    [Fact]
    public void ABasicSeatGroupIsCappedAtTwoDaysInTheProperty()
    {
        var token = Build(Facts(Held(GoldPlan.Yearly, proof: SeatProofKind.Basic)));

        Assert.Equal(TimeSpan.FromDays(2).TotalSeconds, token.Exp - token.Iat);
    }

    [Fact]
    public void IatIsTheWholeSecondOfNow() =>
        Assert.Equal(new DateTimeOffset(2026, 11, 13, 9, 30, 15, TimeSpan.Zero).ToUnixTimeSeconds(), Build(EntitlementFacts.Empty).Iat);
}
