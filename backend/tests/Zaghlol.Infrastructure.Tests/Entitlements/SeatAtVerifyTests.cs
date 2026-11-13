using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Entitlements;

/// <summary>
/// T-132 against PostgreSQL through the real logins: the seat decision at verify (D-59, D-61(a), R4-4, R5-2), the token each
/// install gets from it, and that a valid payment is never turned into an error.
/// </summary>
public sealed class SeatAtVerifyTests(EntitlementFixture fixture) : IClassFixture<EntitlementFixture>, IDisposable
{
    private readonly List<SeatKeyTestSigner> signers = [];

    private SeatDb Db => fixture.Db;

    public void Dispose() => signers.ForEach(s => s.Dispose());

    [Fact]
    public async Task AFirstVerifyBindsTheSeatToTheBuyerAndGrantsActiveGold()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(buyer);

        var result = await rig.VerifyAsync(buyer, purchase, newPayment: true);

        var seat = await Db.ReadSeatAsync(purchase);
        Assert.Equal(buyer.Value, seat!.Holder);
        Assert.Equal("binding", seat.Proof);
        Assert.Null(seat.NextMoveAt);
        Assert.Equal(["seat_bind"], await Db.EventsAsync(purchase));
        Assert.NotNull(result.EntitlementToken);
        Assert.False(result.SeatHeldElsewhere);
        var claims = Assert.Single(rig.Signer.Entitlements);
        Assert.Equal("active", claims.Status);
        Assert.Equal(buyer.ToString(), claims.Sub);
    }

    [Fact]
    public async Task AReVerifyByTheHolderRefreshesAndMovesNothing()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(holder);
        await rig.VerifyAsync(holder, purchase, newPayment: true);
        var before = await Db.ReadSeatAsync(purchase);

        var result = await rig.VerifyAsync(holder, purchase, newPayment: true);

        Assert.Equal(before, await Db.ReadSeatAsync(purchase));
        Assert.Equal(["seat_bind"], await Db.EventsAsync(purchase));
        Assert.False(result.SeatHeldElsewhere);
    }

    [Fact]
    public async Task AReVerifyOfAnOldTransactionFromAnotherInstallNeverChangesTheHolder()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var other = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(purchase, holder);

        var result = await rig.VerifyAsync(other, purchase, newPayment: false);

        Assert.Equal(holder.Value, (await Db.ReadSeatAsync(purchase))!.Holder);
        Assert.Equal("none", (await rig.TokenAsync(other)).Status);
        Assert.NotNull(result.EntitlementToken);
        Assert.Empty(await Db.ClaimantsAsync(purchase));
    }

    [Fact]
    public async Task FU112AVerifyOnAVacantSeatWithNoNewPaymentLeavesItVacant()
    {
        var rig = fixture.NewRig();
        var gone = await Db.InstallAsync();
        var other = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(gone);
        await Db.SeatAsync(purchase, gone);
        await Db.DeleteInstallAsync(gone);

        await rig.VerifyAsync(other, purchase, newPayment: false);

        Assert.Null((await Db.ReadSeatAsync(purchase))!.Holder);
        Assert.Equal("none", (await rig.TokenAsync(other)).Status);
    }

    [Fact]
    public async Task APlanChangeFromAnotherInstallWithNoCooldownMovesTheSeatAndTheOldHolderIsToldMoved()
    {
        var rig = fixture.NewRig();
        var oldHolder = await Db.InstallAsync();
        var payer = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(oldHolder);
        await Db.SeatAsync(purchase, oldHolder);

        var result = await rig.VerifyAsync(payer, purchase, newPayment: true);

        var seat = await Db.ReadSeatAsync(purchase);
        Assert.Equal(payer.Value, seat!.Holder);
        Assert.Equal(SeatClock.NextMoveAfter(fixture.NewRig().Now), seat.NextMoveAt);
        Assert.Equal(["seat_move:verify"], await Db.EventsAsync(purchase));
        Assert.False(result.SeatHeldElsewhere);
        Assert.Equal("active", (await rig.TokenAsync(payer)).Status);
        var former = await rig.TokenAsync(oldHolder);
        Assert.Equal("moved", former.Status);
        Assert.Equal("user", former.MovedBy);
        Assert.Equal(oldHolder.ToString(), former.Sub);
    }

    [Fact]
    public async Task APlanChangeInsideTheCooldownKeepsTheSeatAddsAClaimantAndNeverRefusesThePayment()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var payer = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(holder);
        var next = SeatClock.NextMoveAfter(rig.Now.AddDays(-5));
        await Db.SeatAsync(purchase, holder, nextMoveAt: next);

        var result = await rig.VerifyAsync(payer, purchase, newPayment: true);

        Assert.Equal(holder.Value, (await Db.ReadSeatAsync(purchase))!.Holder);
        Assert.True(result.SeatHeldElsewhere);
        Assert.False(result.AccountRequired);
        Assert.Equal(next, result.NextMoveAt);
        var claimant = Assert.Single(await Db.ClaimantsAsync(purchase));
        Assert.Equal(payer.Value, claimant.Install);
        Assert.Equal("verify", claimant.Channel);
        Assert.NotNull(result.EntitlementToken);
        Assert.Equal("none", (await rig.TokenAsync(payer)).Status);
        Assert.Equal("active", (await rig.TokenAsync(holder)).Status);
        Assert.Empty(await Db.EventsAsync(purchase));
    }

    [Fact]
    public async Task R44PlanChangeOnAnAccountLinkedPurchaseWithoutTheAccountTokenKeepsTheSeatEvenWithNoCooldown()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var payer = await Db.InstallAsync();
        var account = await Db.AccountAsync(holder);
        var purchase = await Db.PurchaseAsync(holder, account);
        await Db.SeatAsync(purchase, holder);

        var result = await rig.VerifyAsync(payer, purchase, newPayment: true);

        var seat = await Db.ReadSeatAsync(purchase);
        Assert.Equal(holder.Value, seat!.Holder);
        Assert.Null(seat.NextMoveAt);
        Assert.True(result.SeatHeldElsewhere);
        Assert.True(result.AccountRequired);
        Assert.Null(result.NextMoveAt);
        Assert.Equal("verify", Assert.Single(await Db.ClaimantsAsync(purchase)).Channel);
        Assert.Empty(await Db.EventsAsync(purchase));
    }

    [Fact]
    public async Task R44WithTheAccountTokenForThatAccountThePlanChangeMoves()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var payer = await Db.InstallAsync();
        var account = await Db.AccountAsync(holder, payer);
        var purchase = await Db.PurchaseAsync(holder, account);
        await Db.SeatAsync(purchase, holder);

        var result = await rig.VerifyAsync(payer, purchase, newPayment: true, account: "valid:" + account);

        Assert.Equal(payer.Value, (await Db.ReadSeatAsync(purchase))!.Holder);
        Assert.False(result.AccountRequired);
        var claims = await rig.TokenAsync(payer, account: "valid:" + account);
        Assert.Equal("active", claims.Status);
        Assert.Equal(account.ToString("D"), claims.Acct);
    }

    [Fact]
    public async Task D61cAnAccountLinkedSeatHeldWithoutTheAccountTokenIsPausedAndWithItIsActive()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var account = await Db.AccountAsync(holder);
        var purchase = await Db.PurchaseAsync(holder, account);
        await Db.SeatAsync(purchase, holder);

        var paused = await rig.TokenAsync(holder);
        var active = await rig.TokenAsync(holder, account: "valid:" + account);
        var other = await rig.TokenAsync(holder, account: "valid:" + Guid.NewGuid());

        Assert.Equal("paused", paused.Status);
        Assert.Null(paused.Acct);
        Assert.Equal("active", active.Status);
        Assert.Equal(account.ToString("D"), active.Acct);
        Assert.Equal("paused", other.Status);
    }

    [Fact]
    public async Task ARefundedPurchaseGivesStatusRefunded()
    {
        var rig = fixture.NewRig();
        var holder = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(holder, state: "refunded");
        await Db.SeatAsync(purchase, holder);

        Assert.Equal("refunded", (await rig.TokenAsync(holder)).Status);
    }

    [Fact]
    public async Task ATokenNeverCoversAPurchaseWhoseSeatAnotherInstallHolds()
    {
        var rig = fixture.NewRig();
        var buyer = await Db.InstallAsync();
        var holder = await Db.InstallAsync();
        var bystander = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(buyer);
        await Db.SeatAsync(purchase, holder);

        Assert.Equal("moved", (await rig.TokenAsync(buyer)).Status);
        Assert.Equal("active", (await rig.TokenAsync(holder)).Status);
        var other = await rig.TokenAsync(bystander);
        Assert.Equal("none", other.Status);
        Assert.Empty(other.Src);
    }

    [Fact]
    public async Task AFormerHolderGetsMovedByUserAfterARestoreMoveAndBySupportAfterASupportMove()
    {
        var rig = fixture.NewRig();
        var first = await Db.InstallAsync();
        var second = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(first);
        await Db.SeatAsync(purchase, first);
        var restoreMove = await RunAsync(rig, SeatLogin.App, store => rig.Seats.RestoreAsync(store, new RestoreSeatRequest(purchase, second, RestoreProof.Attested, null, null), default));
        Assert.Equal(SeatOutcome.Moved, restoreMove.Outcome);

        var afterRestore = await rig.TokenAsync(first);

        Assert.Equal("moved", afterRestore.Status);
        Assert.Equal("user", afterRestore.MovedBy);

        rig.Time.Now += TimeSpan.FromMinutes(1);
        var supportMove = await RunAsync(rig, SeatLogin.Support, store => rig.Seats.SupportMoveAsync(store, new SupportSeatMoveRequest(purchase, first, MoveBack: true), default));
        rig.Time.Now += TimeSpan.FromMinutes(1);
        var supportAway = await RunAsync(rig, SeatLogin.Support, store => rig.Seats.SupportMoveAsync(store, new SupportSeatMoveRequest(purchase, second, MoveBack: true), default));
        Assert.Equal(SeatOutcome.Moved, supportMove.Outcome);
        Assert.Equal(SeatOutcome.Moved, supportAway.Outcome);
        var afterSupport = await rig.TokenAsync(first);

        Assert.Equal("moved", afterSupport.Status);
        Assert.Equal("support", afterSupport.MovedBy);
    }

    [Fact]
    public async Task R52AValidVerifyTimeSeatKeyRegistersUntrustedAndALaterVerifyNeverTrustsIt()
    {
        var rig = fixture.NewRig();
        var install = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(install);
        var key = Signer();
        const string Jws = "signed-transaction-1";
        var keys = new[] { key.Prove(SeatChallenge.ForVerify(Jws), install) };

        await rig.VerifyAsync(install, purchase, newPayment: true, seatKeys: keys, signedTransaction: Jws);
        var (hash, trusted) = await Db.InstallKeyAsync(install);

        Assert.NotNull(hash);
        Assert.False(trusted);
        var seat = await Db.ReadSeatAsync(purchase);
        Assert.NotNull(seat!.DeviceKeyHash);
        Assert.False(seat.DeviceKeyTrusted);

        const string Jws2 = "signed-transaction-2";
        await rig.VerifyAsync(install, purchase, newPayment: true, seatKeys: [key.Prove(SeatChallenge.ForVerify(Jws2), install)], signedTransaction: Jws2);
        var (hashAgain, trustedAgain) = await Db.InstallKeyAsync(install);
        Assert.Equal(hash, hashAgain);
        Assert.False(trustedAgain);
    }

    [Fact]
    public async Task AVerifySeatKeysWithABadSignatureOrAnotherKeyAsElementZeroIs200AndChangesNothing()
    {
        var rig = fixture.NewRig();
        var install = await Db.InstallAsync();
        var purchase = await Db.PurchaseAsync(install);
        const string Jws = "signed-transaction-3";
        var key = Signer();
        var bad = key.Prove(SeatChallenge.ForVerify("another-transaction"), install);

        var badResult = await rig.VerifyAsync(install, purchase, newPayment: true, seatKeys: [bad], signedTransaction: Jws);

        Assert.NotNull(badResult.EntitlementToken);
        Assert.Null((await Db.InstallKeyAsync(install)).Hash);
        Assert.Null((await Db.ReadSeatAsync(purchase))!.DeviceKeyHash);

        // Register key A, then present key B (valid proof) as element 0: not the registered key, so ignored.
        await rig.VerifyAsync(install, purchase, newPayment: true, seatKeys: [key.Prove(SeatChallenge.ForVerify(Jws), install)], signedTransaction: Jws);
        var registered = (await Db.InstallKeyAsync(install)).Hash;
        var other = Signer();
        var mismatch = await rig.VerifyAsync(install, purchase, newPayment: true, seatKeys: [other.Prove(SeatChallenge.ForVerify(Jws), install)], signedTransaction: Jws);

        Assert.NotNull(mismatch.EntitlementToken);
        Assert.Equal(registered, (await Db.InstallKeyAsync(install)).Hash);
    }

    [Fact]
    public async Task APendingOrUnwrittenResultNeverGetsAGrant()
    {
        var rig = fixture.NewRig();
        var install = await Db.InstallAsync();

        var none = await rig.Grant.ComposeAsync(
            new Application.Purchases.StoreVerificationResult(
                Application.Purchases.VerifyStatus.Pending, null, null, Application.Purchases.GoldPlan.Monthly, null, Application.Purchases.PurchaseEnvironment.Production, null, false),
            new Application.Purchases.VerifyContext(install, null, rig.Now),
            CancellationToken.None);

        Assert.Null(none.EntitlementToken);
        Assert.Empty(rig.Signer.Entitlements);
    }

    private SeatKeyTestSigner Signer()
    {
        var signer = new SeatKeyTestSigner();
        signers.Add(signer);
        return signer;
    }

    private static async Task<SeatResult> RunAsync(Rig rig, SeatLogin login, Func<ISeatStore, Task<SeatResult>> action)
    {
        var transaction = await rig.Transactions.BeginAsync(login, CancellationToken.None);
        await using (transaction)
        {
            var result = await action(transaction.Seats);
            await transaction.CommitAsync(CancellationToken.None);
            return result;
        }
    }
}
