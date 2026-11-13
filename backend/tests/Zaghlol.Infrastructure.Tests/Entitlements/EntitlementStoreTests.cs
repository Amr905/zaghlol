using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Tests.Seats;

namespace Zaghlol.Infrastructure.Tests.Entitlements;

/// <summary>T-132: the support-link notice delivery proof (R4-7(2), R5-7), the change detector and the seat reads, in SQL.</summary>
public sealed class EntitlementStoreTests(EntitlementFixture fixture) : IClassFixture<EntitlementFixture>
{
    private static readonly CancellationToken None = CancellationToken.None;

    private SeatDb Db => fixture.Db;

    private Task SetNoticeAsync(Guid purchase) =>
        fixture.ExecAsync($"UPDATE zaghlol.purchases SET support_link_notice_pending = true WHERE id = '{purchase}'");

    private Task<bool> PendingAsync(Guid purchase) =>
        fixture.ScalarAsync<bool>($"SELECT support_link_notice_pending FROM zaghlol.purchases WHERE id = '{purchase}'");

    [Fact]
    public async Task R57TheNoticeAndAFreshTokenRepeatUntilASyncProvesDeliveryAndOtherInstallsNeverSeeIt()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(buyer);
        await Db.SeatAsync(purchase, holder);
        await SetNoticeAsync(purchase);

        var first = await rig.Entitlements.GetAsync(buyer, null, None);
        rig.Time.Now += TimeSpan.FromMinutes(5);
        var second = await rig.Entitlements.GetAsync(buyer, null, None);

        Assert.Equal("gold_linked_by_support", first.SupportNotice);
        Assert.Equal("gold_linked_by_support", second.SupportNotice);
        Assert.Null((await rig.Entitlements.GetAsync(holder, null, None)).SupportNotice);
        Assert.Null((await rig.Entitlements.GetAsync(await Db.InstallAsync(), null, None)).SupportNotice);
        var newest = DateTimeOffset.FromUnixTimeSeconds(second.Claims.Iat);

        await rig.Store.ClearDeliveredSupportNoticeAsync(buyer, newest.AddSeconds(-1), None);
        Assert.True(await PendingAsync(purchase), "an older entitlementIssuedAt keeps the flag");
        await rig.Store.ClearDeliveredSupportNoticeAsync(holder, newest, None);
        Assert.True(await PendingAsync(purchase), "another install can't clear it");
        await rig.Store.ClearDeliveredSupportNoticeAsync(buyer, newest, None);

        Assert.False(await PendingAsync(purchase));
        Assert.Null((await rig.Entitlements.GetAsync(buyer, null, None)).SupportNotice);
    }

    [Fact]
    public async Task ATokenIssuedBeforeTheNoticeWasEverRecordedCantClearIt()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(buyer);
        await Db.SeatAsync(purchase, buyer);
        await SetNoticeAsync(purchase);

        await rig.Store.ClearDeliveredSupportNoticeAsync(buyer, rig.Now.AddDays(1), None);

        Assert.True(await PendingAsync(purchase));
    }

    [Fact]
    public async Task TheRecordedIatOnlyMovesForward()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(buyer);
        await SetNoticeAsync(purchase);
        var t = new DateTimeOffset(2026, 11, 13, 12, 0, 0, TimeSpan.Zero);

        await rig.Store.RecordSupportNoticeIatAsync(buyer, t, None);
        await rig.Store.RecordSupportNoticeIatAsync(buyer, t.AddMinutes(-10), None);

        var stored = await fixture.ScalarAsync<DateTime>($"SELECT support_link_notice_iat FROM zaghlol.purchases WHERE id = '{purchase}'");
        Assert.Equal(t.UtcDateTime, stored);
    }

    [Fact]
    public async Task ChangedSinceSeesAnEventOnABoughtOrHeldPurchaseAndNothingElse()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var stranger = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(buyer);
        await Db.SeatAsync(purchase, holder);
        var since = DateTimeOffset.UtcNow.AddMinutes(-10);
        Assert.False(await rig.Store.ChangedSinceAsync(buyer, since, None));

        await fixture.ExecAsync(
            $"INSERT INTO zaghlol.purchase_events (id, purchase_id, from_state, to_state, cause, occurred_at) VALUES (gen_random_uuid(), '{purchase}', 'active', 'refunded', 'rtdn:VOIDED', now())");

        Assert.True(await rig.Store.ChangedSinceAsync(buyer, since, None));
        Assert.True(await rig.Store.ChangedSinceAsync(holder, since, None));
        Assert.False(await rig.Store.ChangedSinceAsync(stranger, since, None));
        Assert.False(await rig.Store.ChangedSinceAsync(buyer, DateTimeOffset.UtcNow.AddMinutes(10), None));
    }

    [Fact]
    public async Task ReadFactsKeepsEachInstallsSeatsApartAndSkipsNonEntitlingLostPurchases()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var live = await Db.PurchaseAsync(buyer);
        var refunded = await Db.PurchaseAsync(buyer, state: "refunded");
        await Db.SeatAsync(live, holder);
        await Db.SeatAsync(refunded, holder);

        var buyerFacts = await rig.Store.ReadFactsAsync(buyer, rig.Now, None);
        var holderFacts = await rig.Store.ReadFactsAsync(holder, rig.Now, None);

        Assert.Empty(buyerFacts.Held);
        Assert.Equal(live, Assert.Single(buyerFacts.Lost).PurchaseId);
        Assert.Equal(2, holderFacts.Held.Count);
        Assert.Contains(holderFacts.Held, h => h.State == StoredPurchaseState.Refunded);
        Assert.Empty(holderFacts.Lost);
    }
}
