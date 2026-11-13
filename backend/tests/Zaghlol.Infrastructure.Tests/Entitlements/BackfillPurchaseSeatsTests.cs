using Zaghlol.Infrastructure.Persistence.Migrations;
using Zaghlol.Infrastructure.Tests.Seats;

namespace Zaghlol.Infrastructure.Tests.Entitlements;

/// <summary>T-132 / FU-112 (PO): the backfill gives every earlier purchase a seat bound to its buyer, with no cooldown and no event.</summary>
public sealed class BackfillPurchaseSeatsTests(EntitlementFixture fixture) : IClassFixture<EntitlementFixture>
{
    private SeatDb Db => fixture.Db;

    private Task BackfillAsync() => fixture.ExecAsync(BackfillPurchaseSeats.Sql);

    [Fact]
    public async Task EveryPurchaseWithoutASeatGetsOneBoundToItsBuyerWithNoCooldownEventOrSpentReclaim()
    {
        var buyer = await Db.InstallAsync();
        var account = await Db.AccountAsync(buyer);
        var plain = await Db.PurchaseAsync(buyer);
        var linked = await Db.PurchaseAsync(buyer, account);
        var refunded = await Db.PurchaseAsync(buyer, state: "refunded");

        await BackfillAsync();

        foreach (var purchase in new[] { plain, linked, refunded })
        {
            var seat = await Db.ReadSeatAsync(purchase);
            Assert.Equal(buyer.Value, seat!.Holder);
            Assert.Equal("binding", seat.Proof);
            Assert.NotNull(seat.BoundAt);
            Assert.Null(seat.LastMovedAt);
            Assert.Null(seat.NextMoveAt);
            Assert.Null(seat.DeviceKeyHash);
            Assert.False(seat.DeviceKeyTrusted);
            Assert.Empty(seat.RecentRebinds);
            Assert.Empty(await Db.EventsAsync(purchase));
            Assert.Null((await Db.PurchaseAccountAsync(purchase)).Reclaim);
        }
    }

    [Fact]
    public async Task AnExistingSeatIsNeverTouchedAndARunTwiceChangesNothing()
    {
        var buyer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var moved = await Db.PurchaseAsync(buyer);
        var next = new DateTimeOffset(2026, 12, 1, 10, 0, 0, TimeSpan.Zero);
        await Db.SeatAsync(moved, holder, nextMoveAt: next);
        var before = await Db.ReadSeatAsync(moved);
        var fresh = await Db.PurchaseAsync(buyer);

        await BackfillAsync();
        var once = await Db.ReadSeatAsync(fresh);
        await BackfillAsync();

        Assert.Equal(before, await Db.ReadSeatAsync(moved));
        Assert.Equal(once, await Db.ReadSeatAsync(fresh));
    }

    [Fact]
    public async Task APurchaseWhoseBuyerIsGoneGetsAVacantSeat()
    {
        var buyer = await Db.InstallAsync();
        var orphan = await Db.PurchaseAsync(buyer);
        var neverKnown = await Db.PurchaseAsync(null);
        await Db.DeleteInstallAsync(buyer);

        await BackfillAsync();

        foreach (var purchase in new[] { orphan, neverKnown })
        {
            var seat = await Db.ReadSeatAsync(purchase);
            Assert.Null(seat!.Holder);
            Assert.Null(seat.Proof);
        }
    }
}
