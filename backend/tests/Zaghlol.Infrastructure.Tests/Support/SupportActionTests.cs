using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Tests.Seats;

namespace Zaghlol.Infrastructure.Tests.Support;

/// <summary>
/// T-186 against PostgreSQL 17 through the real Admin login (<c>ops_rw</c>): the three support writes, the dispute freeze, R6-1, the
/// order-ID sentinel and the audit rows. The store call is a counting fake; a refusal before the ownership check must leave
/// <see cref="FakeOwnership.Calls"/> at zero.
/// </summary>
public sealed class SupportActionTests(SupportActionFixture fixture) : IClassFixture<SupportActionFixture>
{
    private const string Sentinel = "GPA.SENTINEL-0000-1111-2222";
    private static readonly CancellationToken None = CancellationToken.None;

    private readonly FakeOwnership store = new();
    private readonly RecordingSupportAlerts alerts = new();

    private SeatDb Db => new(fixture.Database);

    private SupportActionService Service => fixture.Service(store, alerts);

    // ---------------------------------------------------------------------------------------------------------------------------
    // seat:move
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task AMoveToAClaimantRestartsTheWindowRemovesTheClaimantAndWritesOneAuditRow()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();

        var result = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.LostOrBrokenPhone), None);

        Assert.Equal(SupportActionStatus.Ok, result.Status);
        var value = result.Value!;
        Assert.True(value.Moved);
        Assert.False(value.Attached);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(claimant.Value, seat.Holder);
        Assert.Equal("support", seat.Proof);
        Assert.Equal(SeatClock.CeilHour(seat.NextMoveAt!.Value), seat.NextMoveAt);
        Assert.InRange(seat.NextMoveAt!.Value - DateTimeOffset.UtcNow, TimeSpan.FromDays(30) - TimeSpan.FromMinutes(1), TimeSpan.FromDays(30) + TimeSpan.FromHours(1) + TimeSpan.FromMinutes(1));
        Assert.Equal(seat.NextMoveAt, value.NextMoveAt);
        Assert.Empty(await Db.ClaimantsAsync(p));
        Assert.Equal(["seat_move:support"], await Db.EventsAsync(p));
        var row = Assert.Single(await AuditAsync(p));
        Assert.Equal((agent, "support_seat_move", "moved", "pass", value.AuditId), (row.Operator, row.Action, row.Outcome, row.OwnershipOutcome, row.Id));
        Assert.Equal(holder.Value.ToString("D"), row.Details.GetProperty("from_install").GetString());
        Assert.Equal(claimant.Value.ToString("D"), row.Details.GetProperty("to_install").GetString());
        Assert.Equal(1, store.Calls);
    }

    [Fact]
    public async Task TheOrderIdReachesOnlyTheStoreCallAndNeverAnAuditRow()
    {
        var (agent, p, _, claimant) = await ScenarioAsync();
        var lead = await fixture.OperatorAsync("support_lead");

        await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        store.Next = OwnershipOutcome.Fail;
        await Service.DetachAsync(new SupportDetachCommand(agent, p, "T-1", new Sensitive<string>(Sentinel), 1), None);
        await Service.UnfreezeAsync(new SupportUnfreezeCommand(lead, p, "T-2", new Sensitive<string>(Sentinel)), None);

        Assert.All(store.OrderIds, id => Assert.Equal(Sentinel, id));
        var rows = await fixture.RowsAsync("SELECT count(*) FROM zaghlol.audit_log WHERE details::text ILIKE '%SENTINEL%' OR target ILIKE '%SENTINEL%'");
        Assert.Equal(0L, rows[0][0]);
        Assert.Equal(3, (await AuditAsync(p)).Count);
    }

    [Theory]
    [InlineData(OwnershipOutcome.Fail, SupportActionStatus.OwnershipFailed, "ownership_failed", "fail")]
    [InlineData(OwnershipOutcome.Unavailable, SupportActionStatus.Unavailable, "upstream_unavailable", "unavailable")]
    public async Task AFailedOwnershipCheckChangesNothingAndIsAudited(OwnershipOutcome check, SupportActionStatus status, string outcome, string ownership)
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        store.Next = check;
        var before = await Db.ReadSeatAsync(p);

        var result = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Reinstall), None);

        Assert.Equal(status, result.Status);
        Assert.Equal(Shape(before), Shape(await Db.ReadSeatAsync(p)));
        Assert.Equal(holder.Value, before!.Holder);
        Assert.Single(await Db.ClaimantsAsync(p));
        Assert.Empty(await Db.EventsAsync(p));
        var row = Assert.Single(await AuditAsync(p));
        Assert.Equal((outcome, ownership), (row.Outcome, row.OwnershipOutcome));
    }

    [Fact]
    public async Task ATargetThatIsNeitherClaimantNorHolderNorMoveBackSourceIs409()
    {
        var (agent, p, _, _) = await ScenarioAsync();
        var stranger = await Db.InstallAsync();

        var result = await Service.MoveSeatAsync(Move(agent, p, stranger, SupportReason.Other), None);

        Assert.Equal(SupportActionStatus.Conflict, result.Status);
        Assert.Equal(["refused"], (await AuditAsync(p)).Select(r => r.Outcome));
    }

    [Fact]
    public async Task AnExpiredClaimantIs409()
    {
        var (agent, p, _, claimant) = await ScenarioAsync();
        await Db.AgeClaimantAsync(p, claimant, DateTimeOffset.UtcNow.AddDays(-8));

        Assert.Equal(SupportActionStatus.Conflict, (await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None)).Status);
    }

    [Fact]
    public async Task AnAccountLinkedPurchaseNeedsATargetLinkedToThatAccount()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var account = await Db.AccountAsync(holder);
        await Db.LinkPurchaseAsync(p, account);

        Assert.Equal(SupportActionStatus.Conflict, (await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None)).Status);

        await fixture.ExecAsync("INSERT INTO zaghlol.account_installs (account_id, install_id) VALUES (@a, @b)", account, claimant.Value);
        Assert.Equal(SupportActionStatus.Ok, (await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None)).Status);
    }

    [Fact]
    public async Task MovingToTheCurrentHolderChangesNothingAndIsAuditedAsNoop()
    {
        var (agent, p, holder, _) = await ScenarioAsync();
        var before = await Db.ReadSeatAsync(p);

        var result = await Service.MoveSeatAsync(Move(agent, p, holder, SupportReason.Other), None);

        Assert.False(result.Value!.Moved);
        Assert.Equal(Shape(before), Shape(await Db.ReadSeatAsync(p)));
        Assert.Equal(["noop"], (await AuditAsync(p)).Select(r => r.Outcome));
    }

    [Fact]
    public async Task AMissingPurchaseIs404AndAudited()
    {
        var agent = await fixture.OperatorAsync("support_agent");
        var missing = Guid.NewGuid();

        var result = await Service.MoveSeatAsync(Move(agent, missing, SeatDb.NewInstallId(), SupportReason.Other), None);

        Assert.Equal(SupportActionStatus.NotFound, result.Status);
        Assert.Equal(0, store.Calls);
        Assert.Single(await AuditAsync(missing));
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Attach gate (D-57(d), R4-7(2), R5-7)
    // ---------------------------------------------------------------------------------------------------------------------------

    [Theory]
    [InlineData(29, false)]
    [InlineData(31, true)]
    public async Task TheAttachGateNeedsABuyingInstallSilentFor30Days(int silentDays, bool allowed)
    {
        var (agent, p, holder, _) = await ScenarioAsync();
        await fixture.ExecAsync("UPDATE zaghlol.installs SET last_seen_at = now() - make_interval(days => @a) WHERE id = (SELECT install_id FROM zaghlol.purchases WHERE id = @b)", silentDays, p);
        var account = await Db.AccountAsync(holder);

        var result = await Service.MoveSeatAsync(Move(agent, p, holder, SupportReason.BuyingPhoneGone, attach: true), None);

        Assert.Equal(allowed ? SupportActionStatus.Ok : SupportActionStatus.Conflict, result.Status);
        var purchase = await PurchaseAsync(p);
        if (allowed)
        {
            Assert.True(result.Value!.Attached);
            Assert.False(result.Value.Moved);
            Assert.Equal(account, purchase.Account);
            Assert.Equal("support", purchase.LinkedBy);
            Assert.True(purchase.NoticePending);
            Assert.Null(purchase.NoticeIat);
            Assert.Equal(["attached"], (await AuditAsync(p)).Select(r => r.Outcome));
            Assert.Equal(account.ToString("D"), (await AuditAsync(p))[0].Details.GetProperty("attached_account_id").GetString());
        }
        else
        {
            Assert.Null(purchase.Account);
        }
    }

    [Fact]
    public async Task AGoneBuyingInstallAllowsMoveAndAttachTogether()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        await fixture.ExecAsync("DELETE FROM zaghlol.installs WHERE id = (SELECT install_id FROM zaghlol.purchases WHERE id = @a)", p);
        await fixture.ExecAsync("UPDATE zaghlol.purchases SET install_id = NULL WHERE id = @a", p);
        var account = await Db.AccountAsync(claimant);

        var result = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.BuyingPhoneGone, attach: true), None);

        Assert.True(result.Value!.Moved);
        Assert.True(result.Value.Attached);
        Assert.Equal(["moved_and_attached"], (await AuditAsync(p)).Select(r => r.Outcome));
        Assert.Equal(account, (await PurchaseAsync(p)).Account);
        Assert.NotEqual(holder.Value, (await Db.ReadSeatAsync(p))!.Holder);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // R5-4: device_key_trusted through this endpoint
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task R54AMoveFromATrustedHolderToAnUntrustedClaimantIsUntrusted()
    {
        var (agent, p, _, claimant) = await ScenarioAsync(holderTrusted: true);
        var key = RandomNumberGenerator.GetBytes(32);
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-1), key);
        await RegisterKeyAsync(claimant, trusted: false);

        await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);

        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(key, seat.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted);
    }

    [Fact]
    public async Task R54AMoveToAClaimantWhoseInstallKeyIsTrustedCopiesTrue()
    {
        var (agent, p, _, claimant) = await ScenarioAsync(holderTrusted: true);
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-1), RandomNumberGenerator.GetBytes(32));
        await RegisterKeyAsync(claimant, trusted: true);

        await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);

        Assert.True((await Db.ReadSeatAsync(p))!.DeviceKeyTrusted);
    }

    [Fact]
    public async Task R54AMoveBackLeavesNoKeyAndNoTrustEvenForATrustedInstall()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync(holderTrusted: true);
        await RegisterKeyAsync(holder, trusted: true);
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await ClaimAsync(p, holder, DateTimeOffset.UtcNow.AddHours(-1), RandomNumberGenerator.GetBytes(32));

        var back = await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);

        Assert.Equal(SupportActionStatus.Ok, back.Status);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(holder.Value, seat.Holder);
        Assert.Null(seat.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted);
        Assert.Empty(await Db.ClaimantsAsync(p));
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Detach (D-57(e), R5-7)
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task DetachRemovesOnlyASupportLinkNamedByItsAttachRowAndClearsBothNoticeColumns()
    {
        var (agent, p, holder, _) = await ScenarioAsync();
        await SilenceBuyerAsync(p);
        var account = await Db.AccountAsync(holder);
        var attach = await Service.MoveSeatAsync(Move(agent, p, holder, SupportReason.BuyingPhoneGone, attach: true), None);
        await fixture.ExecAsync("UPDATE zaghlol.purchases SET support_link_notice_iat = now() WHERE id = @a", p);
        var seatBefore = await Db.ReadSeatAsync(p);

        var result = await Service.DetachAsync(Detach(agent, p, attach.Value!.AuditId), None);

        Assert.True(result.Value!.Detached);
        var purchase = await PurchaseAsync(p);
        Assert.Null(purchase.Account);
        Assert.Null(purchase.LinkedBy);
        Assert.False(purchase.NoticePending);
        Assert.Null(purchase.NoticeIat);
        Assert.NotNull(purchase.FrozenUntil);
        Assert.Equal(Shape(seatBefore), Shape(await Db.ReadSeatAsync(p)));
        var row = (await AuditAsync(p)).Single(r => r.Action == "support_detach");
        Assert.Equal(("detached", account.ToString("D")), (row.Outcome, row.Details.GetProperty("detached_account_id").GetString()));
    }

    [Fact]
    public async Task ASignInLinkCannotBeDetached()
    {
        var (agent, p, holder, _) = await ScenarioAsync();
        var account = await Db.AccountAsync(holder);
        await Db.LinkPurchaseAsync(p, account);

        var result = await Service.DetachAsync(Detach(agent, p, 1), None);

        Assert.Equal(SupportActionStatus.Conflict, result.Status);
        Assert.Equal(account, (await PurchaseAsync(p)).Account);
    }

    [Fact]
    public async Task DetachingAnUnlinkedPurchaseIsANoop()
    {
        var (agent, p, _, _) = await ScenarioAsync();

        var result = await Service.DetachAsync(Detach(agent, p, 1), None);

        Assert.False(result.Value!.Detached);
        Assert.Equal(["noop"], (await AuditAsync(p)).Select(r => r.Outcome));
        Assert.Null((await PurchaseAsync(p)).FrozenUntil);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Dispute freeze (D-64, D-65(b)) and the move-back target (FU-112 184-2)
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task ANegativeProofSeatMoveDuringAFreezeIs409WithNoStoreCallAndTheSeatUnchanged()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        var frozenSeat = await Db.ReadSeatAsync(p);
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-1));
        var calls = store.Calls;
        alerts.Raised.Clear();

        var refused = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        var attach = await Service.MoveSeatAsync(Move(agent, p, holder, SupportReason.BuyingPhoneGone, attach: true), None);

        Assert.Equal((SupportActionStatus.Conflict, SupportActionStatus.Conflict), (refused.Status, attach.Status));
        Assert.Equal(calls, store.Calls);
        Assert.Equal(Shape(frozenSeat), Shape(await Db.ReadSeatAsync(p)));
        var rows = await AuditAsync(p);
        Assert.Equal(["dispute_frozen", "dispute_frozen"], rows.TakeLast(2).Select(r => r.Outcome));
        Assert.Equal(["not_run", "not_run"], rows.TakeLast(2).Select(r => r.OwnershipOutcome));
        Assert.Equal(2, alerts.Raised.Count(a => a.StartsWith("dispute_frozen:", StringComparison.Ordinal)));
    }

    [Fact]
    public async Task AFurtherCorrectionIsAllowedAndRestartsTheFreeze()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        var firstFreeze = (await PurchaseAsync(p)).FrozenUntil;
        await fixture.ExecAsync("UPDATE zaghlol.purchases SET dispute_frozen_until = now() + interval '2 days' WHERE id = @a", p);
        var second = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        Assert.Equal(SupportActionStatus.Conflict, second.Status);

        // The correction row names the first move again: the move back of the move back is not offered, but a correction to the same source is.
        await fixture.ExecAsync("UPDATE zaghlol.purchase_seats SET install_id = @b WHERE purchase_id = @a", p, claimant.Value);
        var again = await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value.AuditId), None);

        Assert.Equal(SupportActionStatus.Ok, again.Status);
        var restarted = (await PurchaseAsync(p)).FrozenUntil!.Value;
        Assert.True(restarted > DateTimeOffset.UtcNow.AddDays(29));
        Assert.NotEqual(firstFreeze, restarted);
    }

    [Fact]
    public async Task ACorrectionAimedAtAnInstallThatIsNotTheSourceIsRefusedAndMovesNothing()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        var stranger = await Db.InstallAsync();
        var before = await Db.ReadSeatAsync(p);

        var wrongTarget = await Service.MoveSeatAsync(Correction(agent, p, stranger, first.Value!.AuditId), None);
        var unknownRow = await Service.MoveSeatAsync(Correction(agent, p, holder, 999_999), None);

        Assert.Equal((SupportActionStatus.Conflict, SupportActionStatus.Conflict), (wrongTarget.Status, unknownRow.Status));
        Assert.Equal(Shape(before), Shape(await Db.ReadSeatAsync(p)));
        Assert.Null((await PurchaseAsync(p)).FrozenUntil);
    }

    [Fact]
    public async Task ACorrectionNeverNamesAnotherPurchasesRow()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        var (_, q, qHolder, _) = await ScenarioAsync();

        var result = await Service.MoveSeatAsync(Correction(agent, q, holder, first.Value!.AuditId), None);

        Assert.Equal(SupportActionStatus.Conflict, result.Status);
        Assert.Equal(qHolder.Value, (await Db.ReadSeatAsync(q))!.Holder);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Unfreeze (R5-5(b), R6-1)
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task UnfreezeWithNoFreezeIsANoopWithNoStoreCall()
    {
        var (_, p, _, _) = await ScenarioAsync();
        var lead = await fixture.OperatorAsync("support_lead");

        var result = await Service.UnfreezeAsync(Unfreeze(lead, p), None);

        Assert.False(result.Value!.Unfrozen);
        Assert.Equal(0, store.Calls);
        var row = Assert.Single(await AuditAsync(p));
        Assert.Equal(("noop", "not_run"), (row.Outcome, row.OwnershipOutcome));
        Assert.Equal(["unfreeze:" + p], alerts.Raised);
    }

    [Fact]
    public async Task ANegativeProofUnfreezeByTheCorrectingOperatorIs409WithNoStoreCall()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        var calls = store.Calls;
        var frozen = (await PurchaseAsync(p)).FrozenUntil;

        var result = await Service.UnfreezeAsync(Unfreeze(agent, p), None);

        Assert.Equal(SupportActionStatus.Conflict, result.Status);
        Assert.Equal(calls, store.Calls);
        Assert.Equal(frozen, (await PurchaseAsync(p)).FrozenUntil);
        var row = (await AuditAsync(p)).Last();
        Assert.Equal(("support_unfreeze", "refused", "not_run"), (row.Action, row.Outcome, row.OwnershipOutcome));
    }

    [Fact]
    public async Task ANegativeProofUnfreezeBefore24HoursByADifferentOperatorIs409WithNoStoreCall()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        var lead = await fixture.OperatorAsync("support_lead");
        var calls = store.Calls;

        var early = await Service.UnfreezeAsync(Unfreeze(lead, p), None);

        Assert.Equal(SupportActionStatus.Conflict, early.Status);
        Assert.Equal(calls, store.Calls);
        Assert.NotNull((await PurchaseAsync(p)).FrozenUntil);
        Assert.Equal(("refused", "not_run"), ((await AuditAsync(p)).Last().Outcome, (await AuditAsync(p)).Last().OwnershipOutcome));

        await AgeFreezeAsync(p);
        Assert.True((await Service.UnfreezeAsync(Unfreeze(lead, p), None)).Value!.Unfrozen);
    }

    [Fact]
    public async Task AnotherLeadWithAPassingCheckEndsTheFreezeAndMovesNothing()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-2));
        var lead = await fixture.OperatorAsync("support_lead");
        await AgeFreezeAsync(p);
        var seat = await Db.ReadSeatAsync(p);
        var purchaseBefore = await PurchaseAsync(p);
        var claimantsBefore = await Db.ClaimantsAsync(p);

        var result = await Service.UnfreezeAsync(Unfreeze(lead, p), None);

        Assert.True(result.Value!.Unfrozen);
        var after = await PurchaseAsync(p);
        Assert.Null(after.FrozenUntil);
        Assert.Equal(purchaseBefore with { FrozenUntil = null }, after);
        Assert.Equal(Shape(seat), Shape(await Db.ReadSeatAsync(p)));
        Assert.Equal(Shape(claimantsBefore), Shape(await Db.ClaimantsAsync(p)));
        var row = (await AuditAsync(p)).Last();
        Assert.Equal(("unfrozen", "pass"), (row.Outcome, row.OwnershipOutcome));
        Assert.NotEqual(JsonValueKind.Null, row.Details.GetProperty("frozen_until").ValueKind);
        Assert.Contains("unfreeze:" + p, alerts.Raised);
    }

    [Fact]
    public async Task R61UnfreezeByTheOperatorOfTheReversedRowIs409()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var other = await fixture.OperatorAsync("support_agent");
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(other, p, holder, first.Value!.AuditId), None);
        var calls = store.Calls;

        var byReversed = await Service.UnfreezeAsync(Unfreeze(agent, p), None);
        var byFreezer = await Service.UnfreezeAsync(Unfreeze(other, p), None);

        Assert.Equal((SupportActionStatus.Conflict, SupportActionStatus.Conflict), (byReversed.Status, byFreezer.Status));
        Assert.Equal(calls, store.Calls);
        Assert.NotNull((await PurchaseAsync(p)).FrozenUntil);
    }

    [Fact]
    public async Task R61AFreezeWithNoCorrectionRowFailsClosed()
    {
        var (_, p, _, _) = await ScenarioAsync();
        var lead = await fixture.OperatorAsync("support_lead");
        await fixture.ExecAsync("UPDATE zaghlol.purchases SET dispute_frozen_until = now() + interval '3 days' WHERE id = @a", p);

        var result = await Service.UnfreezeAsync(Unfreeze(lead, p), None);

        Assert.Equal(SupportActionStatus.Conflict, result.Status);
        Assert.Equal(0, store.Calls);
    }

    [Fact]
    public async Task R61TheUnfreezingOperatorCannotMakeTheNextOrdinaryMoveFor24HoursButAnotherAgentCan()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        var leadAgent = await fixture.OperatorAsync("support_lead", "support_agent");
        var otherAgent = await fixture.OperatorAsync("support_agent");
        await AgeFreezeAsync(p);
        Assert.True((await Service.UnfreezeAsync(Unfreeze(leadAgent, p), None)).Value!.Unfrozen);
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-1));
        var calls = store.Calls;

        var blocked = await Service.MoveSeatAsync(Move(leadAgent, p, claimant, SupportReason.Other), None);

        Assert.Equal(SupportActionStatus.Conflict, blocked.Status);
        Assert.Equal(calls, store.Calls);
        var row = (await AuditAsync(p)).Last();
        Assert.Equal(("refused", "not_run"), (row.Outcome, row.OwnershipOutcome));

        var allowed = await Service.MoveSeatAsync(Move(otherAgent, p, claimant, SupportReason.Other), None);
        Assert.Equal(SupportActionStatus.Ok, allowed.Status);
    }

    [Fact]
    public async Task R61TheLockEndsAfter24Hours()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        var first = await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await Service.MoveSeatAsync(Correction(agent, p, holder, first.Value!.AuditId), None);
        var leadAgent = await fixture.OperatorAsync("support_lead", "support_agent");
        await AgeFreezeAsync(p);
        await Service.UnfreezeAsync(Unfreeze(leadAgent, p), None);
        await fixture.ExecAsync("UPDATE zaghlol.audit_log SET at = now() - interval '25 hours' WHERE action = 'support_unfreeze' AND target = @a", p.ToString("D"));
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-1));

        Assert.Equal(SupportActionStatus.Ok, (await Service.MoveSeatAsync(Move(leadAgent, p, claimant, SupportReason.Other), None)).Status);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // Alerts and audit shape
    // ---------------------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task AThirdSupportMoveInNinetyDaysRaisesTheMovesAlertAndEveryCallWritesOneRow()
    {
        var (agent, p, holder, claimant) = await ScenarioAsync();
        await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        await ClaimAsync(p, holder, DateTimeOffset.UtcNow.AddHours(-1));
        await Service.MoveSeatAsync(Move(agent, p, holder, SupportReason.Other), None);
        Assert.DoesNotContain(alerts.Raised, a => a.StartsWith("moves:", StringComparison.Ordinal));
        await ClaimAsync(p, claimant, DateTimeOffset.UtcNow.AddHours(-1));

        await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);

        Assert.Contains("moves:" + p, alerts.Raised);
        Assert.Equal(3, (await AuditAsync(p)).Count);
    }

    [Fact]
    public async Task MoreThanFiveOwnershipFailuresInADayRaisesTheOperatorAlert()
    {
        var (agent, p, _, claimant) = await ScenarioAsync();
        store.Next = OwnershipOutcome.Fail;

        for (var i = 0; i < 6; i++)
        {
            await Service.MoveSeatAsync(Move(agent, p, claimant, SupportReason.Other), None);
        }

        Assert.Equal(["ownership_failures:" + agent], alerts.Raised);
    }

    [Fact]
    public void TheAuditEntriesHaveNoMemberForAnOrderIdAnEmailOrFreeText()
    {
        var entries = new AuditEntry[]
        {
            new SupportSeatMoveAudit(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "other", "ZG-1", null, null, "pass", "moved"),
            new SupportDetachAudit(Guid.NewGuid(), Guid.NewGuid(), "ZG-1", 4, "pass", "detached"),
            new SupportUnfreezeAudit(Guid.NewGuid(), "ZG-1", 4, DateTimeOffset.UtcNow, "pass", "unfrozen"),
        };

        foreach (var entry in entries)
        {
            var details = entry.Details();
            Assert.DoesNotContain('@', details);
            Assert.DoesNotContain("order", details.Replace("ownership_check\":\"order_id", string.Empty, StringComparison.Ordinal), StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task ATicketThatIsNotATicketNumberCannotReachAnAuditRow()
    {
        var (agent, p, _, claimant) = await ScenarioAsync();
        var command = Move(agent, p, claimant, SupportReason.Other) with { TicketRef = "call me at a@b.example" };

        await Assert.ThrowsAsync<ArgumentException>(() => Service.MoveSeatAsync(command, None));
        Assert.Empty(await AuditAsync(p));
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------------------------------------------------------------

    private static string Shape(StoredSeat? seat) => seat is null
        ? "none"
        : string.Create(
            CultureInfo.InvariantCulture,
            $"{seat.Holder}|{seat.Proof}|{seat.BoundAt:O}|{seat.LastMovedAt:O}|{seat.NextMoveAt:O}|{(seat.DeviceKeyHash is null ? "-" : Convert.ToHexString(seat.DeviceKeyHash))}|{seat.DeviceKeyTrusted}|{string.Join(',', seat.RecentRebinds.Select(r => r.ToString("O", CultureInfo.InvariantCulture)))}");

    private static string Shape(List<(Guid Install, DateTimeOffset ClaimedAt, string Channel, byte[]? Hash)> claimants) => string.Join(
        ';',
        claimants.Select(c => string.Create(CultureInfo.InvariantCulture, $"{c.Install}|{c.ClaimedAt:O}|{c.Channel}|{(c.Hash is null ? "-" : Convert.ToHexString(c.Hash))}")));

    private static SupportSeatMoveCommand Move(Guid agent, Guid purchase, InstallId to, SupportReason reason, bool attach = false) =>
        new(agent, purchase, to, reason, "ZG-100", new Sensitive<string>(Sentinel), attach, null);

    private static SupportSeatMoveCommand Correction(Guid agent, Guid purchase, InstallId to, long corrects) =>
        new(agent, purchase, to, SupportReason.Correction, "ZG-101", new Sensitive<string>(Sentinel), false, corrects);

    private static SupportDetachCommand Detach(Guid agent, Guid purchase, long corrects) =>
        new(agent, purchase, "ZG-102", new Sensitive<string>(Sentinel), corrects);

    private static SupportUnfreezeCommand Unfreeze(Guid lead, Guid purchase) => new(lead, purchase, "ZG-103", new Sensitive<string>(Sentinel));

    /// <summary>A purchase bought and held by one install, in cooldown, with one fresh pending claimant.</summary>
    private async Task<(Guid Agent, Guid Purchase, InstallId Holder, InstallId Claimant)> ScenarioAsync(bool holderTrusted = false)
    {
        var agent = await fixture.OperatorAsync("support_agent");
        var holder = await Db.InstallAsync();
        var claimant = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(purchase, holder, SeatClock.CeilHour(DateTimeOffset.UtcNow.AddDays(10)), holderTrusted ? RandomNumberGenerator.GetBytes(32) : null, holderTrusted);
        await ClaimAsync(purchase, claimant, DateTimeOffset.UtcNow.AddDays(-1));
        return (agent, purchase, holder, claimant);
    }

    private Task ClaimAsync(Guid purchase, InstallId install, DateTimeOffset at, byte[]? hash = null) => fixture.ExecAsync(
        """
        INSERT INTO zaghlol.seat_claimants (purchase_id, install_id, claimed_at, channel, device_key_hash)
        VALUES (@a, @b, @c, 'restore', @d)
        ON CONFLICT (purchase_id, install_id) DO UPDATE SET claimed_at = EXCLUDED.claimed_at, device_key_hash = EXCLUDED.device_key_hash
        """,
        purchase,
        install.Value,
        at.UtcDateTime,
        (object?)hash ?? DBNull.Value);

    private Task RegisterKeyAsync(InstallId install, bool trusted) => fixture.ExecAsync(
        "UPDATE zaghlol.installs SET seat_key_hash = COALESCE(seat_key_hash, @b), seat_key_trusted = @c WHERE id = @a",
        install.Value,
        RandomNumberGenerator.GetBytes(32),
        trusted);

    /// <summary>Moves the correction rows 25 h into the past, so the R6-1 24 h wait is over.</summary>
    private Task AgeFreezeAsync(Guid purchase) => fixture.ExecAsync(
        "UPDATE zaghlol.audit_log SET at = now() - interval '25 hours' WHERE target = @a AND action IN ('support_seat_move', 'support_detach')",
        purchase.ToString("D"));

    private Task SilenceBuyerAsync(Guid purchase) => fixture.ExecAsync(
        "UPDATE zaghlol.installs SET last_seen_at = now() - interval '40 days' WHERE id = (SELECT install_id FROM zaghlol.purchases WHERE id = @a)",
        purchase);

    private async Task<List<AuditRow>> AuditAsync(Guid purchase)
    {
        var rows = await fixture.RowsAsync("SELECT id, operator_id, action, details::text FROM zaghlol.audit_log WHERE target = @a ORDER BY id", purchase.ToString("D"));
        return [.. rows.Select(r => new AuditRow((long)r[0]!, (Guid)r[1]!, (string)r[2]!, JsonDocument.Parse((string)r[3]!).RootElement.Clone()))];
    }

    private async Task<PurchaseState> PurchaseAsync(Guid purchase)
    {
        var rows = await fixture.RowsAsync(
            "SELECT account_id, account_linked_by, support_link_notice_pending, support_link_notice_iat, dispute_frozen_until FROM zaghlol.purchases WHERE id = @a",
            purchase);
        var r = rows.Single();
        return new PurchaseState((Guid?)r[0], (string?)r[1], (bool)r[2]!, (DateTimeOffset?)r[3], (DateTimeOffset?)r[4]);
    }

    private sealed record PurchaseState(Guid? Account, string? LinkedBy, bool NoticePending, DateTimeOffset? NoticeIat, DateTimeOffset? FrozenUntil);
}
