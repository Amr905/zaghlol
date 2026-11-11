using System.Security.Cryptography;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Seats;

/// <summary>
/// T-184 against PostgreSQL 17 through the real App and Admin logins: every cell of the design-note state table with its event
/// rows, the window boundary, claimants, plan change, rebinds and the cap, seat-key trust (R5-2), the support primitive (R5-4),
/// concurrency (FR-GOLD-08) and the sign-in relay bound (accepted residual 1).
/// </summary>
public sealed class SeatServiceTests(SeatServiceFixture fixture) : IClassFixture<SeatServiceFixture>, IDisposable
{
    private static readonly DateTimeOffset Start = new DateTimeOffset(2026, 11, 11, 10, 17, 23, TimeSpan.Zero).AddTicks(4567890);
    private static readonly CancellationToken None = CancellationToken.None;

    private readonly ManualTime time = new(Start);
    private readonly RecordingSeatTelemetry telemetry = new();
    private readonly List<SeatKeyTestSigner> signers = [];

    private SeatDb Db => new(fixture.Database);

    private SeatService Service => new(new SeatKeyHasher(new FixedSeatMac(), new NullSeatKeyMetrics()), telemetry, time);

    private DateTimeOffset Now => SeatClock.ToDatabasePrecision(time.Now);

    public void Dispose() => signers.ForEach(s => s.Dispose());

    // ---------------------------------------------------------------------------------------------------------------------------
    // The state table (design note §4): one scenario per cell; outcome and the purchase_events rows it writes (exactly one or none).
    // ---------------------------------------------------------------------------------------------------------------------------

    [Theory]
    [InlineData("V1", SeatOutcome.Bound, "seat_bind")]
    [InlineData("V3", SeatOutcome.Unchanged, null)]
    [InlineData("V4", SeatOutcome.Unchanged, null)]
    [InlineData("V5", SeatOutcome.AccountRequired, null)]
    [InlineData("V6", SeatOutcome.Moved, "seat_move:verify")]
    [InlineData("V7", SeatOutcome.ClaimantAdded, null)]
    [InlineData("R1", SeatOutcome.AccountRequired, null)]
    [InlineData("R2", SeatOutcome.Unchanged, null)]
    [InlineData("R3", SeatOutcome.Rebound, "seat_rebind:restore")]
    [InlineData("R4", SeatOutcome.ReboundOverCap, "seat_rebind_over_cap:restore")]
    [InlineData("R5", SeatOutcome.Moved, "seat_move:restore")]
    [InlineData("R6", SeatOutcome.Refused, null)]
    [InlineData("S1", SeatOutcome.AccountRequired, null)]
    [InlineData("S2", SeatOutcome.Unchanged, null)]
    [InlineData("S3", SeatOutcome.Moved, "seat_move:account_attach")]
    [InlineData("S4", SeatOutcome.Rebound, "seat_rebind:signin")]
    [InlineData("S5", SeatOutcome.ReboundOverCap, "seat_rebind_over_cap:signin")]
    [InlineData("S6", SeatOutcome.Moved, "seat_rebind_over_cap:signin")]
    [InlineData("S7", SeatOutcome.Refused, "seat_rebind_over_cap:signin")]
    [InlineData("S8", SeatOutcome.Moved, "seat_move:signin")]
    [InlineData("S9", SeatOutcome.Refused, null)]
    [InlineData("P1", SeatOutcome.NotEligible, null)]
    [InlineData("P2", SeatOutcome.Unchanged, null)]
    [InlineData("P3", SeatOutcome.Moved, "seat_move:support")]
    public async Task EveryCellWritesTheDocumentedOutcomeAndEventRows(string cell, SeatOutcome outcome, string? cause)
    {
        var (purchase, result) = await RunCellAsync(cell);

        Assert.Equal(outcome, result.Outcome);
        Assert.Equal(cause, result.Cause);
        Assert.Equal(cause is null ? Array.Empty<string>() : new[] { cause }, await Db.EventsAsync(purchase));
        var seat = await Db.ReadSeatAsync(purchase);
        if (seat?.NextMoveAt is { } next)
        {
            Assert.Equal(SeatClock.CeilHour(next), next);
        }
    }

    private async Task<(Guid Purchase, SeatResult Result)> RunCellAsync(string cell)
    {
        var a = await Db.InstallAsync();
        var b = await Db.InstallAsync();
        var cooldown = SeatClock.NextMoveAfter(Now.AddDays(-5));
        var account = await Db.AccountAsync(a);
        var old = Signer();
        var mine = Signer();
        var oldOnSeat = SeatHash(old);
        DateTimeOffset[] full = [Now.AddDays(-3), Now.AddDays(-2)];
        Guid p;
        switch (cell)
        {
            case "V1":
                p = await Db.PurchaseAsync(a);
                return (p, await VerifyAsync(a, p, newPayment: false));
            case "V3":
                p = await Db.PurchaseAsync(a);
                await Db.SeatAsync(p, a, cooldown);
                return (p, await VerifyAsync(a, p, newPayment: true));
            case "V4":
                p = await Db.PurchaseAsync(a);
                await Db.SeatAsync(p, b);
                return (p, await VerifyAsync(a, p, newPayment: false));
            case "V5":
                p = await Db.PurchaseAsync(a, account);
                await Db.SeatAsync(p, b);
                return (p, await VerifyAsync(a, p, newPayment: true));
            case "V6":
                p = await Db.PurchaseAsync(a);
                await Db.SeatAsync(p, b);
                return (p, await VerifyAsync(a, p, newPayment: true));
            case "V7":
                p = await Db.PurchaseAsync(a);
                await Db.SeatAsync(p, b, cooldown);
                return (p, await VerifyAsync(a, p, newPayment: true));
            case "R1":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, a);
                return (p, await RestoreAsync(a, p));
            case "R2":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, a, cooldown);
                return (p, await RestoreAsync(a, p));
            case "R3":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, b, cooldown, oldOnSeat(p));
                return (p, await RestoreAsync(a, p, [mine, old]));
            case "R4":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, b, cooldown, oldOnSeat(p), rebinds: full);
                return (p, await RestoreAsync(a, p, [mine, old]));
            case "R5":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, b);
                return (p, await RestoreAsync(a, p));
            case "R6":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, b, cooldown);
                return (p, await RestoreAsync(a, p));
            case "S1":
                p = await Db.PurchaseAsync(b, await Db.AccountAsync());
                await Db.SeatAsync(p, b);
                return (p, await SignInAsync(a, p, account));
            case "S2":
                p = await Db.PurchaseAsync(a, account);
                await Db.SeatAsync(p, a, cooldown);
                return (p, await SignInAsync(a, p, account, attachedNow: true));
            case "S3":
                p = await Db.PurchaseAsync(a, account);
                await Db.SeatAsync(p, b, cooldown);
                return (p, await SignInAsync(a, p, account, attachedNow: true));
            case "S4":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, b, cooldown, oldOnSeat(p));
                return (p, await SignInAsync(a, p, account, keys: [mine, old]));
            case "S5":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, b, cooldown, oldOnSeat(p), trusted: true, rebinds: full);
                return (p, await SignInAsync(a, p, account, keys: [mine, old]));
            case "S6":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, b, null, oldOnSeat(p), trusted: false, rebinds: full);
                return (p, await SignInAsync(a, p, account, keys: [mine, old]));
            case "S7":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, b, cooldown, oldOnSeat(p), trusted: false, rebinds: full);
                return (p, await SignInAsync(a, p, account, keys: [mine, old]));
            case "S8":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, b);
                return (p, await SignInAsync(a, p, account));
            case "S9":
                p = await Db.PurchaseAsync(b, account);
                await Db.SeatAsync(p, b, cooldown);
                return (p, await SignInAsync(a, p, account));
            case "P1":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, b, cooldown);
                return (p, await SupportMoveAsync(p, a));
            case "P2":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, a, cooldown);
                return (p, await SupportMoveAsync(p, a));
            case "P3":
                p = await Db.PurchaseAsync(b);
                await Db.SeatAsync(p, b, cooldown);
                Assert.Equal(SeatOutcome.Refused, (await RestoreAsync(a, p)).Outcome);
                return (p, await SupportMoveAsync(p, a));
            default:
                throw new ArgumentOutOfRangeException(nameof(cell));
        }
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // R3-4: the window.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task R34TheCooldownBoundaryIsTheStoredWholeHourExactly()
    {
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        var next = SeatClock.NextMoveAfter(Start);
        await Db.SeatAsync(p, holder, next);

        time.Now = next.AddSeconds(-1);
        var refused = await RestoreAsync(caller, p);
        Assert.Equal(SeatOutcome.Refused, refused.Outcome);
        Assert.Equal(next, refused.NextMoveAt);
        Assert.Equal(holder.Value, (await Db.ReadSeatAsync(p))!.Holder);

        time.Now = next;
        var moved = await RestoreAsync(caller, p);
        Assert.Equal(SeatOutcome.Moved, moved.Outcome);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(caller.Value, seat.Holder);
        Assert.Equal(next, seat.LastMovedAt);
        Assert.Equal(SeatClock.CeilHour(next.AddDays(30)), seat.NextMoveAt);
        Assert.Equal(seat.NextMoveAt, moved.NextMoveAt);
    }

    [Fact]
    public async Task R34AMoveAtAnOddTimeStoresTheNextWholeUtcHour()
    {
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder);

        await RestoreAsync(caller, p);

        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(Now, seat.LastMovedAt);
        Assert.Equal(new DateTimeOffset(2026, 12, 11, 11, 0, 0, TimeSpan.Zero), seat.NextMoveAt);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // FR-GOLD-08: one holder under concurrency.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task FrGold08TwentyConcurrentMovesLeaveExactlyOneHolder()
    {
        var holder = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder);
        var callers = new List<InstallId>();
        for (var i = 0; i < 20; i++)
        {
            callers.Add(await Db.InstallAsync(i % 2 == 0 ? "ios" : "android"));
        }

        var results = await Task.WhenAll(callers.Select(c => Task.Run(() => RestoreAsync(c, p))));

        var winners = results.Where(r => r.Outcome == SeatOutcome.Moved).ToList();
        Assert.Single(winners);
        Assert.Equal(19, results.Count(r => r.Outcome == SeatOutcome.Refused));
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Contains(callers, c => c.Value == seat.Holder);
        Assert.Equal(results.Single(r => r.CallerHolds), winners[0]);
        Assert.Equal(["seat_move:restore"], await Db.EventsAsync(p));
        Assert.Equal(SeatClock.MaxClaimants, (await Db.ClaimantsAsync(p)).Count);
    }

    [Fact]
    public async Task FrGold08TwentyConcurrentFirstVerifiesBindExactlyOnce()
    {
        var p = await Db.PurchaseAsync();
        var callers = new List<InstallId>();
        for (var i = 0; i < 20; i++)
        {
            callers.Add(await Db.InstallAsync());
        }

        var results = await Task.WhenAll(callers.Select(c => Task.Run(() => VerifyAsync(c, p, newPayment: false))));

        // The purchase row lock serialises the creation of the seat row: one bind, no unique violation, the rest unchanged.
        var bound = Assert.Single(results, r => r.Outcome == SeatOutcome.Bound);
        Assert.True(bound.CallerHolds);
        Assert.Equal(19, results.Count(r => r.Outcome == SeatOutcome.Unchanged && !r.CallerHolds));
        Assert.Equal(["seat_bind"], await Db.EventsAsync(p));
        Assert.NotNull((await Db.ReadSeatAsync(p))!.Holder);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // D-58 / R3-3: the account-attach reclaim, once per purchase.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task D58ASecondReclaimAfterAccountDeletionAndRelinkIsAnOrdinaryMoveUnderTheCooldown()
    {
        var buyer = await Db.InstallAsync();
        var thief = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(buyer);
        await Db.SeatAsync(p, thief, SeatClock.NextMoveAfter(Start.AddDays(-1)));
        var first = await Db.AccountAsync(buyer);
        await Db.LinkPurchaseAsync(p, first);

        var reclaim = await SignInAsync(buyer, p, first, attachedNow: true);
        Assert.Equal(SeatOutcome.Moved, reclaim.Outcome);
        Assert.Equal(thief.Value, reclaim.PreviousHolder);
        Assert.Equal(SeatMovedBy.User, reclaim.MovedBy);
        var (_, used) = await Db.PurchaseAccountAsync(p);
        Assert.Equal(Now, used);

        // The account is deleted (attach_reclaim_used_at stays), the seat leaves again after the window, and the buying phone
        // links a new account.
        await Db.DeleteAccountAsync(first);
        var (cleared, kept) = await Db.PurchaseAccountAsync(p);
        Assert.Null(cleared);
        Assert.Equal(used, kept);
        time.Now = Start.AddDays(31);
        Assert.Equal(SeatOutcome.Moved, (await RestoreAsync(thief, p)).Outcome);
        var second = await Db.AccountAsync(buyer);
        await Db.LinkPurchaseAsync(p, second);
        time.Now = Start.AddDays(32);

        var again = await SignInAsync(buyer, p, second, attachedNow: true);

        Assert.Equal(SeatOutcome.Refused, again.Outcome);
        Assert.Equal(thief.Value, (await Db.ReadSeatAsync(p))!.Holder);
        Assert.Equal(used, (await Db.PurchaseAccountAsync(p)).Reclaim);
        Assert.Equal(["seat_move:account_attach", "seat_move:restore"], await Db.EventsAsync(p));
    }

    [Fact]
    public async Task D61bTheReclaimDoesNotFireWhenTheHolderIsLinkedToTheAccount()
    {
        var buyer = await Db.InstallAsync();
        var other = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(buyer);
        await Db.SeatAsync(p, other, SeatClock.NextMoveAfter(Start.AddDays(-1)));
        var account = await Db.AccountAsync(buyer, other);
        await Db.LinkPurchaseAsync(p, account);

        var result = await SignInAsync(buyer, p, account, attachedNow: true);

        Assert.Equal(SeatOutcome.Refused, result.Outcome);
        Assert.Null((await Db.PurchaseAccountAsync(p)).Reclaim);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // R3-4: claimants.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task R34AFourthClaimantReplacesTheOldestAndARepeatRefreshes()
    {
        var holder = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, SeatClock.NextMoveAfter(Start));
        var c = new List<InstallId>();
        for (var i = 0; i < 4; i++)
        {
            c.Add(await Db.InstallAsync());
        }

        for (var i = 0; i < 3; i++)
        {
            time.Now = Start.AddHours(i);
            await RestoreAsync(c[i], p);
        }

        time.Now = Start.AddHours(3);
        await RestoreAsync(c[0], p); // a repeat refreshes c0: c1 is now the oldest
        time.Now = Start.AddHours(4);
        await SignInRefusedAsync(c[3], p);

        var rows = await Db.ClaimantsAsync(p);
        Assert.Equal([c[2].Value, c[0].Value, c[3].Value], rows.Select(r => r.Install));
        Assert.Equal(SeatClock.ToDatabasePrecision(Start.AddHours(3)), rows[1].ClaimedAt);
        Assert.Equal("signin", rows[2].Channel);
    }

    [Fact]
    public async Task R34ClaimantsOlderThanSevenDaysAreIgnored()
    {
        var holder = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, SeatClock.NextMoveAfter(Start));
        var stale = await Db.InstallAsync();
        await RestoreAsync(stale, p);
        await Db.AgeClaimantAsync(p, stale, Start.AddDays(-7));
        var fresh = new List<InstallId>();
        for (var i = 0; i < 3; i++)
        {
            fresh.Add(await Db.InstallAsync());
            await RestoreAsync(fresh[i], p);
        }

        // The expired row neither counted (all three fresh ones stay) nor makes its install a support target.
        Assert.Equal(4, (await Db.ClaimantsAsync(p)).Count);
        Assert.Equal(SeatOutcome.NotEligible, (await SupportMoveAsync(p, stale)).Outcome);
        Assert.Equal(SeatOutcome.Moved, (await SupportMoveAsync(p, fresh[0])).Outcome);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // R4-4 / D-59 / D-61(a): plan change.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Theory]
    [InlineData(false, false, SeatOutcome.AccountRequired)]
    [InlineData(false, true, SeatOutcome.AccountRequired)]
    [InlineData(true, false, SeatOutcome.Moved)]
    [InlineData(true, true, SeatOutcome.ClaimantAdded)]
    public async Task R44ThePlanChangeTableOfAnAccountLinkedPurchase(bool withToken, bool cooldown, SeatOutcome expected)
    {
        var payer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var account = await Db.AccountAsync(holder);
        var p = await Db.PurchaseAsync(payer, account);
        var next = cooldown ? SeatClock.NextMoveAfter(Start.AddDays(-3)) : (DateTimeOffset?)null;
        await Db.SeatAsync(p, holder, next);

        var result = await VerifyAsync(payer, p, newPayment: true, presentedAccount: withToken ? account : null);

        Assert.Equal(expected, result.Outcome);
        var seat = (await Db.ReadSeatAsync(p))!;
        var claimants = await Db.ClaimantsAsync(p);
        if (expected == SeatOutcome.Moved)
        {
            Assert.Equal(payer.Value, seat.Holder);
            Assert.Equal("binding", seat.Proof);
            Assert.Equal(holder.Value, result.PreviousHolder);
            Assert.Empty(claimants);
            Assert.Equal(["seat_move:verify"], await Db.EventsAsync(p));
        }
        else
        {
            Assert.Equal(holder.Value, seat.Holder);
            Assert.Equal(next, seat.NextMoveAt);
            Assert.Equal(next, result.NextMoveAt);
            Assert.Equal(("verify", payer.Value), (Assert.Single(claimants).Channel, claimants[0].Install));
            Assert.Empty(await Db.EventsAsync(p));
        }
    }

    [Fact]
    public async Task D59AGoogleSuccessorInheritsTheSeatAccountReclaimMarkerAndWindow()
    {
        var buyer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var account = await Db.AccountAsync(holder);
        var predecessor = await Db.PurchaseAsync(buyer, account);
        var next = SeatClock.NextMoveAfter(Start.AddDays(-2));
        var key = Signer();
        await Db.SeatAsync(predecessor, holder, next, SeatHash(key)(predecessor), trusted: true, rebinds: [Start.AddDays(-1)]);
        var successor = await Db.PurchaseAsync(buyer);
        await Db.SetLinkedPurchaseAsync(successor, predecessor);

        // The successor's payer is the buying install, without an account token: the account rule keeps the seat where it is.
        var result = await VerifyAsync(buyer, successor, newPayment: true, predecessor: predecessor);

        Assert.Equal(SeatOutcome.AccountRequired, result.Outcome);
        Assert.Equal(next, result.NextMoveAt);
        var seat = (await Db.ReadSeatAsync(successor))!;
        Assert.Equal(holder.Value, seat.Holder);
        Assert.Equal(next, seat.NextMoveAt);
        Assert.Null(seat.DeviceKeyHash); // keyed per purchase: the predecessor's value could never match, so it isn't copied
        Assert.False(seat.DeviceKeyTrusted);
        Assert.Single(seat.RecentRebinds);
        Assert.Equal(account, (await Db.PurchaseAccountAsync(successor)).Account);
        Assert.Empty(await Db.EventsAsync(successor));
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // D-55 / D-63 / D-65(a) / R4-1(1): rebinds.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task D55ARebindFromPositionOnePassesWithoutCooldownAndKeepsTheWindow()
    {
        var old = Signer();
        var mine = Signer();
        var gone = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(gone);
        var next = SeatClock.NextMoveAfter(Start.AddDays(-1));
        await Db.SeatAsync(p, gone, next, SeatHash(old)(p));
        await Db.DeleteInstallAsync(gone); // "Delete everything": the seat goes vacant and keeps its key

        var result = await RestoreAsync(caller, p, [mine, old]);

        Assert.Equal(SeatOutcome.Rebound, result.Outcome);
        Assert.Null(result.PreviousHolder);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(caller.Value, seat.Holder);
        Assert.Equal("device", seat.Proof);
        Assert.Equal(next, seat.NextMoveAt);
        Assert.Equal([Now], seat.RecentRebinds);
    }

    [Fact]
    public async Task R411TheSeatHashAfterARebindIsTheCallersRegisteredKeyNotTheMatchedOne()
    {
        var old = Signer();
        var mine = Signer();
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, SeatClock.NextMoveAfter(Start), SeatHash(old)(p), trusted: true);

        await SignInAsync(caller, p, null, keys: [mine, old], linkAccount: true);

        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(SeatHash(mine)(p), seat.DeviceKeyHash);
        Assert.NotEqual(SeatHash(old)(p), seat.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted); // the caller's sign-in-registered key is untrusted; nothing kept from the old holder
        Assert.Equal(InstallHash(caller, mine), (await Db.InstallKeyAsync(caller)).Hash);
    }

    [Fact]
    public async Task D63AMatchOnElementZeroIsNeverARebind()
    {
        var key = Signer();
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, SeatClock.NextMoveAfter(Start), SeatHash(key)(p));

        var result = await RestoreAsync(caller, p, [key]);

        Assert.Equal(SeatOutcome.Refused, result.Outcome);
        Assert.Equal(holder.Value, (await Db.ReadSeatAsync(p))!.Holder);
    }

    [Fact]
    public async Task D63AThirdRebindWithinThirtyDaysIsOverCap()
    {
        var keys = Enumerable.Range(0, 4).Select(_ => Signer()).ToArray();
        var installs = new List<InstallId>();
        for (var i = 0; i < 4; i++)
        {
            installs.Add(await Db.InstallAsync());
        }

        var p = await Db.PurchaseAsync(installs[0]);
        await Db.SeatAsync(p, installs[0], null, SeatHash(keys[0])(p));

        var outcomes = new List<SeatOutcome>();
        for (var i = 1; i < 4; i++)
        {
            time.Now = Start.AddDays(i * 9);
            outcomes.Add((await RestoreAsync(installs[i], p, [keys[i], keys[i - 1]])).Outcome);
        }

        Assert.Equal([SeatOutcome.Rebound, SeatOutcome.Rebound, SeatOutcome.ReboundOverCap], outcomes);
        Assert.Equal(["seat_rebind:restore", "seat_rebind:restore", "seat_rebind_over_cap:restore"], await Db.EventsAsync(p));
        Assert.Equal([p], telemetry.Alerts);
    }

    [Fact]
    public async Task D63RebindsOlderThanThirtyDaysDoNotCount()
    {
        var old = Signer();
        var mine = Signer();
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null, SeatHash(old)(p), rebinds: [Start.AddDays(-31), Start.AddDays(-30)]);

        Assert.Equal(SeatOutcome.Rebound, (await RestoreAsync(caller, p, [mine, old])).Outcome);
        Assert.Equal([Now], (await Db.ReadSeatAsync(p))!.RecentRebinds);
    }

    [Fact]
    public async Task D65aAnOverCapRestoreMatchPassesAndRestartsTheWindow()
    {
        var old = Signer();
        var mine = Signer();
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        DateTimeOffset[] full = [Start.AddDays(-2), Start.AddDays(-1)];
        await Db.SeatAsync(p, holder, SeatClock.NextMoveAfter(Start.AddDays(-1)), SeatHash(old)(p), trusted: false, rebinds: full);

        var result = await RestoreAsync(caller, p, [mine, old]);

        Assert.Equal(SeatOutcome.ReboundOverCap, result.Outcome);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(caller.Value, seat.Holder);
        Assert.Equal(Now, seat.LastMovedAt);
        Assert.Equal(SeatClock.NextMoveAfter(Now), seat.NextMoveAt);
        Assert.Equal(full.Select(SeatClock.ToDatabasePrecision), seat.RecentRebinds);
        Assert.Equal(SeatHash(mine)(p), seat.DeviceKeyHash);
        Assert.Equal([p], telemetry.Alerts);
        Assert.Contains(("restore", "rebind_over_cap"), telemetry.Changes);
    }

    [Theory]
    [InlineData(true, false, SeatOutcome.ReboundOverCap, false)]
    [InlineData(false, false, SeatOutcome.Moved, true)]
    [InlineData(false, true, SeatOutcome.Refused, true)]
    public async Task D65aAnOverCapSignInMatchPassesOnlyFromATrustedSeatKey(bool trusted, bool cooldown, SeatOutcome expected, bool restoreSuggested)
    {
        var old = Signer();
        var mine = Signer();
        var holder = await Db.InstallAsync();
        var caller = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        var next = cooldown ? SeatClock.NextMoveAfter(Start.AddDays(-1)) : (DateTimeOffset?)null;
        await Db.SeatAsync(p, holder, next, SeatHash(old)(p), trusted, rebinds: [Start.AddDays(-2), Start.AddDays(-1)]);

        var result = await SignInAsync(caller, p, null, keys: [mine, old], linkAccount: true);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal(restoreSuggested, result.RestoreSuggested);
        Assert.Equal(["seat_rebind_over_cap:signin"], await Db.EventsAsync(p));
        Assert.Equal([p], telemetry.Alerts);
        Assert.Equal(expected == SeatOutcome.Refused ? holder.Value : caller.Value, (await Db.ReadSeatAsync(p))!.Holder);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // R5-2: seat-key registration and trust.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Theory]
    [InlineData(SeatOp.Verify)]
    [InlineData(SeatOp.SignIn)]
    [InlineData(SeatOp.Restore)]
    public async Task R52RegistrationWithoutTheCapabilityIsUntrusted(SeatOp op)
    {
        var install = await Db.InstallAsync();
        var key = Signer();

        var registration = await RegisterAsync(install, op, [key], attested: false);

        Assert.Equal(SeatKeyRegistrationStatus.Registered, registration.Status);
        Assert.False(registration.Key!.Trusted);
        await AssertInstallKeyAsync(install, InstallHash(install, key), trusted: false);
    }

    [Fact]
    public async Task R52OnlyAnAppAttestCoveredRestoreSetsTrustAndOnlyFalseToTrue()
    {
        var install = await Db.InstallAsync();
        var key = Signer();
        var other = Signer();
        Assert.False((await RegisterAsync(install, SeatOp.SignIn, [key], attested: false)).Key!.Trusted);

        var attested = await RegisterAsync(install, SeatOp.Restore, [key, other], attested: true);
        Assert.Equal(SeatKeyRegistrationStatus.AlreadyRegistered, attested.Status);
        Assert.True(attested.Key!.Trusted);

        var later = await RegisterAsync(install, SeatOp.SignIn, [key], attested: false);
        Assert.True(later.Key!.Trusted);
        await AssertInstallKeyAsync(install, InstallHash(install, key), trusted: true);
    }

    [Fact]
    public async Task R411TheRegisteredKeyIsSetOnceAndAMismatchWritesNothing()
    {
        var install = await Db.InstallAsync();
        var first = Signer();
        var second = Signer();
        await RegisterAsync(install, SeatOp.Verify, [first], attested: false);

        var mismatch = await RegisterAsync(install, SeatOp.Restore, [second, first], attested: true);

        Assert.Equal(SeatKeyRegistrationStatus.Mismatch, mismatch.Status);
        Assert.Null(mismatch.Key);
        await AssertInstallKeyAsync(install, InstallHash(install, first), trusted: false);
    }

    [Fact]
    public async Task R52ACapabilityForAnotherInstallOrOtherKeysIsRefused()
    {
        var install = await Db.InstallAsync();
        var key = Signer();
        var keys = Verify(SeatOp.Restore, install, [key]);
        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, None);

        await Assert.ThrowsAsync<ArgumentException>(() =>
            Service.RegisterElementZeroAsync(tx.Seats, keys, new AppAttestVerified(SeatDb.NewInstallId(), keys.Digest()), None));
        await Assert.ThrowsAsync<ArgumentException>(() =>
            Service.RegisterElementZeroAsync(tx.Seats, keys, new AppAttestVerified(install, new byte[32]), None));
        var signIn = Verify(SeatOp.SignIn, install, [key]);
        await Assert.ThrowsAsync<ArgumentException>(() =>
            Service.RegisterElementZeroAsync(tx.Seats, signIn, new AppAttestVerified(install, signIn.Digest()), None));
    }

    [Fact]
    public async Task R411AHolderWithoutARegisteredKeyClearsTheSeatKeyOnAMove()
    {
        var holder = await Db.InstallAsync();
        var android = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null, SeatHash(Signer())(p), trusted: true);

        await RestoreAsync(android, p);

        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Null(seat.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted);
    }

    [Fact]
    public async Task R411AnIosHolderStoresItsKeyAndTrustWhenItBindsOrStays()
    {
        var install = await Db.InstallAsync();
        var key = Signer();
        var p = await Db.PurchaseAsync(install);

        Assert.Equal(SeatOutcome.Bound, (await VerifyAsync(install, p, newPayment: true, keys: [key])).Outcome);
        var bound = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(SeatHash(key)(p), bound.DeviceKeyHash);
        Assert.False(bound.DeviceKeyTrusted);

        Assert.Equal(SeatOutcome.Unchanged, (await RestoreAsync(install, p, [key], attested: true)).Outcome);
        Assert.True((await Db.ReadSeatAsync(p))!.DeviceKeyTrusted);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // R5-4 (shared with T-186): the support primitive on the Admin login.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task R54ASupportMoveFromATrustedHolderToAnUntrustedClaimantIsUntrusted()
    {
        var (p, holder, _) = await TrustedHolderInCooldownAsync();
        var claimant = await Db.InstallAsync();
        var key = Signer();
        Assert.Equal(SeatOutcome.Refused, (await SignInRefusedAsync(claimant, p, [key])).Outcome);

        var result = await SupportMoveAsync(p, claimant);

        Assert.Equal(SeatOutcome.Moved, result.Outcome);
        Assert.Equal((holder.Value, SeatMovedBy.Support), (result.PreviousHolder!.Value, result.MovedBy!.Value));
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(claimant.Value, seat.Holder);
        Assert.Equal("support", seat.Proof);
        Assert.Equal(SeatHash(key)(p), seat.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted);
        Assert.Equal(SeatClock.NextMoveAfter(Now), seat.NextMoveAt);
        Assert.Empty(await Db.ClaimantsAsync(p));
    }

    [Fact]
    public async Task D56ASupportMoveOfAVacantSeatNamesNoLoser()
    {
        var (p, holder, _) = await TrustedHolderInCooldownAsync();
        var claimant = await Db.InstallAsync();
        await SignInRefusedAsync(claimant, p);
        await Db.DeleteInstallAsync(holder);

        var result = await SupportMoveAsync(p, claimant);

        Assert.Equal(SeatOutcome.Moved, result.Outcome);
        Assert.Null(result.PreviousHolder);
        Assert.Null(result.MovedBy);
        Assert.Equal(["seat_move:support"], await Db.EventsAsync(p));
    }

    [Fact]
    public async Task R54AMoveBackClearsTheSeatKeyEvenToATrustedInstall()
    {
        var (p, holder, holderKey) = await TrustedHolderInCooldownAsync();
        var claimant = await Db.InstallAsync();
        await SignInRefusedAsync(claimant, p, [Signer()]);
        await SupportMoveAsync(p, claimant);

        // The old holder is also a claimant now, with its trusted key's hash: a move back still takes neither.
        Assert.Equal(SeatOutcome.Refused, (await SignInRefusedAsync(holder, p, [holderKey])).Outcome);
        Assert.NotNull(Assert.Single(await Db.ClaimantsAsync(p)).Hash);

        var back = await SupportMoveAsync(p, holder, moveBack: true);

        Assert.Equal(SeatOutcome.Moved, back.Outcome);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(holder.Value, seat.Holder);
        Assert.Null(seat.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted);
        Assert.True((await Db.InstallKeyAsync(holder)).Trusted);
        Assert.Empty(await Db.ClaimantsAsync(p));
    }

    [Fact]
    public async Task R54AMoveToAClaimantWhoseInstallKeyIsTrustedCopiesTrue()
    {
        var (p, _, _) = await TrustedHolderInCooldownAsync();
        var claimant = await Db.InstallAsync();
        var key = Signer();
        Assert.Equal(SeatOutcome.Refused, (await RestoreAsync(claimant, p, [key], attested: true)).Outcome);

        await SupportMoveAsync(p, claimant);

        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(SeatHash(key)(p), seat.DeviceKeyHash);
        Assert.True(seat.DeviceKeyTrusted);
    }

    [Fact]
    public async Task R54TheTrustFlagIsReadFromTheTargetAtTheTimeOfTheMove()
    {
        var (p, _, _) = await TrustedHolderInCooldownAsync();
        var claimant = await Db.InstallAsync();
        var key = Signer();
        await SignInRefusedAsync(claimant, p, [key]);
        await RegisterAsync(claimant, SeatOp.Restore, [key], attested: true); // trusted after the refusal

        await SupportMoveAsync(p, claimant);

        Assert.True((await Db.ReadSeatAsync(p))!.DeviceKeyTrusted);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Accepted residual 1 (D-66, R4-1(5)): a chain of sign-ins with relayed keys.
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task Residual1ASignInChainGetsAtMostTwoCooldownFreeRebindsThenOrdinaryMoves()
    {
        var (p, chain) = await SignInChainAsync(nextMoveAt: null, rebinds: []);

        Assert.Equal(
            [SeatOutcome.Rebound, SeatOutcome.Rebound, SeatOutcome.Moved, SeatOutcome.Refused, SeatOutcome.Refused, SeatOutcome.Refused],
            chain);
        var events = await Db.EventsAsync(p);
        Assert.Equal(2, events.Count(e => e == "seat_rebind:signin"));
        Assert.DoesNotContain(SeatOutcome.ReboundOverCap, chain);
        // 2 rebinds, the ordinary over-cap move that spends the window (S6), then three over-cap refusals (S7, recorded too).
        Assert.Equal(6, events.Count);
        Assert.Equal(4, events.Count(e => e == "seat_rebind_over_cap:signin"));
    }

    [Fact]
    public async Task Residual1FromAtTheCapWithATrustedKeyTheChainMakesOneOverCapHop()
    {
        var (p, chain) = await SignInChainAsync(SeatClock.NextMoveAfter(Start.AddDays(-1)), [Start.AddDays(-2), Start.AddDays(-1)]);

        Assert.Equal(
            [SeatOutcome.ReboundOverCap, SeatOutcome.Refused, SeatOutcome.Refused, SeatOutcome.Refused, SeatOutcome.Refused, SeatOutcome.Refused],
            chain);
        Assert.Single(chain, o => o == SeatOutcome.ReboundOverCap);
        Assert.Equal(6, (await Db.EventsAsync(p)).Count(e => e == "seat_rebind_over_cap:signin"));
    }

    /// <summary>
    /// The owner's iPhone holds the seat with a trusted key. A relay with the account's credentials signs in from new installs,
    /// each naming its own software key as element 0 and the key currently on the seat at position 1, one hour apart.
    /// </summary>
    private async Task<(Guid Purchase, List<SeatOutcome> Chain)> SignInChainAsync(DateTimeOffset? nextMoveAt, DateTimeOffset[] rebinds)
    {
        var owner = await Db.InstallAsync();
        var account = await Db.AccountAsync(owner);
        var p = await Db.PurchaseAsync(owner, account);
        var onSeat = Signer();
        await Db.SeatAsync(p, owner, nextMoveAt, SeatHash(onSeat)(p), trusted: true, rebinds: rebinds);
        var chain = new List<SeatOutcome>();
        for (var i = 1; i <= 6; i++)
        {
            time.Now = Start.AddHours(i);
            var relay = await Db.InstallAsync();
            var own = Signer();
            var result = await SignInAsync(relay, p, account, keys: [own, onSeat]);
            chain.Add(result.Outcome);
            if (result.CallerHolds)
            {
                onSeat = own;
            }
        }

        return (p, chain);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Helpers.
    // ---------------------------------------------------------------------------------------------------------------------------

    private async Task<(Guid Purchase, InstallId Holder, SeatKeyTestSigner Key)> TrustedHolderInCooldownAsync()
    {
        var holder = await Db.InstallAsync();
        var p = await Db.PurchaseAsync(holder);
        var key = Signer();
        await RegisterAsync(holder, SeatOp.Restore, [key], attested: true);
        await Db.SeatAsync(p, holder, SeatClock.NextMoveAfter(Start.AddDays(-1)), SeatHash(key)(p), trusted: true);
        return (p, holder, key);
    }

    private async Task AssertInstallKeyAsync(InstallId install, byte[] hash, bool trusted)
    {
        var stored = await Db.InstallKeyAsync(install);
        Assert.Equal(hash, stored.Hash);
        Assert.Equal(trusted, stored.Trusted);
    }

    private SeatKeyTestSigner Signer()
    {
        var signer = new SeatKeyTestSigner();
        signers.Add(signer);
        return signer;
    }

    private static Func<Guid, byte[]> SeatHash(SeatKeyTestSigner signer) =>
        purchase => HMACSHA256.HashData(FakeKms.FixedSeatKey, SeatKeyHasher.SeatKeyInput(purchase, signer.PublicPoint));

    private static byte[] InstallHash(InstallId install, SeatKeyTestSigner signer) =>
        HMACSHA256.HashData(FakeKms.FixedSeatKey, SeatKeyHasher.InstallKeyInput(install, signer.PublicPoint));

    private static VerifiedSeatKeys Verify(SeatOp op, InstallId install, SeatKeyTestSigner[] keys)
    {
        var challenge = op switch
        {
            SeatOp.Verify => SeatChallenge.ForVerify("eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln"),
            SeatOp.Restore => SeatChallenge.ForRestore(RandomNumberGenerator.GetBytes(32)),
            _ => SeatChallenge.ForSignIn(Convert.ToHexString(RandomNumberGenerator.GetBytes(16))),
        };
        var result = new SeatKeyProofVerifier(new NullSeatKeyMetrics())
            .ParseAndVerify(keys.Select(k => (SeatKeyProofInput?)k.Prove(challenge, install)).ToList(), challenge, install);
        Assert.True(result.IsValid, result.ToString());
        return result.Keys;
    }

    private async Task<SeatKeyRegistration> RegisterAsync(InstallId install, SeatOp op, SeatKeyTestSigner[] keys, bool attested)
    {
        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, None);
        var registration = await RegisterInAsync(tx.Seats, install, op, keys, attested);
        await tx.CommitAsync(None);
        return registration;
    }

    private async Task<SeatKeyRegistration> RegisterInAsync(ISeatStore store, InstallId install, SeatOp op, SeatKeyTestSigner[] keys, bool attested)
    {
        var verified = Verify(op, install, keys);
        return await Service.RegisterElementZeroAsync(store, verified, attested ? new AppAttestVerified(install, verified.Digest()) : null, None);
    }

    private async Task<RegisteredSeatKey?> KeyAsync(ISeatStore store, InstallId install, SeatOp op, SeatKeyTestSigner[]? keys, bool attested = false)
    {
        if (keys is null)
        {
            return null;
        }

        var registration = await RegisterInAsync(store, install, op, keys, attested);
        return registration.Key ?? throw new InvalidOperationException("SEAT_KEY_MISMATCH in a test that expected a match.");
    }

    private async Task<SeatResult> VerifyAsync(
        InstallId caller, Guid purchase, bool newPayment, Guid? presentedAccount = null, Guid? predecessor = null, SeatKeyTestSigner[]? keys = null)
    {
        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, None);
        var key = await KeyAsync(tx.Seats, caller, SeatOp.Verify, keys);
        var result = await Service.VerifyAsync(tx.Seats, new VerifySeatRequest(purchase, caller, newPayment, presentedAccount, predecessor, key), None);
        await tx.CommitAsync(None);
        return result;
    }

    private async Task<SeatResult> RestoreAsync(
        InstallId caller, Guid purchase, SeatKeyTestSigner[]? keys = null, bool attested = false, Guid? presentedAccount = null)
    {
        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, None);
        var key = await KeyAsync(tx.Seats, caller, SeatOp.Restore, keys, attested);
        var result = await Service.RestoreAsync(tx.Seats, new RestoreSeatRequest(purchase, caller, RestoreProof.Attested, presentedAccount, key), None);
        await tx.CommitAsync(None);
        return result;
    }

    /// <param name="account">The signed-in account; with <paramref name="linkAccount"/> a new account linked to the purchase.</param>
    private async Task<SeatResult> SignInAsync(
        InstallId caller, Guid purchase, Guid? account, bool attachedNow = false, SeatKeyTestSigner[]? keys = null, bool linkAccount = false)
    {
        if (linkAccount)
        {
            account = await Db.AccountAsync(caller);
            await Db.LinkPurchaseAsync(purchase, account);
        }

        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.App, None);
        var key = await KeyAsync(tx.Seats, caller, SeatOp.SignIn, keys);
        var result = await Service.SignInAsync(tx.Seats, new SignInSeatRequest(purchase, caller, account!.Value, attachedNow, key), None);
        await tx.CommitAsync(None);
        return result;
    }

    /// <summary>A sign-in under a running cooldown against the purchase's account (linked first when it has none).</summary>
    private async Task<SeatResult> SignInRefusedAsync(InstallId caller, Guid purchase, SeatKeyTestSigner[]? keys = null)
    {
        var account = (await Db.PurchaseAccountAsync(purchase)).Account;
        if (account is null)
        {
            account = await Db.AccountAsync(caller);
            await Db.LinkPurchaseAsync(purchase, account);
        }

        return await SignInAsync(caller, purchase, account, keys: keys);
    }

    private async Task<SeatResult> SupportMoveAsync(Guid purchase, InstallId target, bool moveBack = false)
    {
        await using var tx = await fixture.Transactions.BeginAsync(SeatLogin.Support, None);
        var result = await Service.SupportMoveAsync(tx.Seats, new SupportSeatMoveRequest(purchase, target, moveBack), None);
        await tx.CommitAsync(None);
        return result;
    }
}
