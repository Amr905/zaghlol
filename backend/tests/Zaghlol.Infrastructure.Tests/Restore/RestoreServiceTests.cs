using System.Security.Cryptography;
using Npgsql;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Application.Purchases.Restore;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Entitlements;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Infrastructure.Tests.Entitlements;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Restore;

/// <summary>
/// T-185 through the real seat service, seat transactions and entitlement service over PostgreSQL: attestation and store fakes,
/// no HTTP. Covers the order of the checks (nothing written on a failed proof), the seat outcomes and the limits.
/// </summary>
public sealed class RestoreServiceTests(EntitlementFixture fixture) : IClassFixture<EntitlementFixture>, IDisposable
{
    private readonly List<SeatKeyTestSigner> signers = [];

    private SeatDb Db => fixture.Db;

    public void Dispose() => signers.ForEach(s => s.Dispose());

    // ---- seat outcomes, Android -------------------------------------------------------------------------------------------

    [Fact]
    public async Task AMoveFromAnotherPhoneGrantsGoldWritesOneEventAndSaysSo()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null);

        var result = await rig.RestoreAsync(caller, rig.Android(caller, p));

        Assert.Equal(RestoreResultKind.Completed, result.Kind);
        Assert.Equal("active", result.Status);
        Assert.Equal(1, result.RestoredCount);
        Assert.True(result.MovedFromOtherPhone);
        Assert.NotNull(result.EntitlementToken);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(caller.Value, seat.Holder);
        Assert.Equal("attested", seat.Proof);
        Assert.Equal(SeatClock.NextMoveAfter(rig.Time.Now), seat.NextMoveAt);
        Assert.Equal(["seat_move:restore"], await Db.EventsAsync(p));
    }

    [Fact]
    public async Task ARestoreByTheCurrentHolderIsNeverAMove()
    {
        var rig = NewRig();
        var caller = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(caller);
        await Db.SeatAsync(p, caller, SeatClock.NextMoveAfter(rig.Time.Now));
        var before = await Db.ReadSeatAsync(p);

        var result = await rig.RestoreAsync(caller, rig.Android(caller, p));

        Assert.Equal("active", result.Status);
        Assert.False(result.MovedFromOtherPhone);
        Assert.Equal(before, await Db.ReadSeatAsync(p));
        Assert.Empty(await Db.EventsAsync(p));
    }

    [Fact]
    public async Task ABasicIntegrityRestoreStoresBasicProofAndAShortToken()
    {
        var rig = NewRig();
        rig.Play.Result = AttestationResult.Verified(ProofLevel.Basic);
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null);

        var result = await rig.RestoreAsync(caller, rig.Android(caller, p));

        Assert.Equal("active", result.Status);
        Assert.Equal("basic", (await Db.ReadSeatAsync(p))!.Proof);
        var claims = rig.Signer.Entitlements.Last();
        Assert.Equal(caller.ToString(), claims.Sub);
        Assert.True(claims.Exp - claims.Iat <= TimeSpan.FromDays(2).TotalSeconds);
    }

    [Fact]
    public async Task TheCooldownIs409WithTheStoredHourMakesTheCallerAClaimantAndChangesNothingElse()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        var next = SeatClock.NextMoveAfter(rig.Time.Now.AddDays(-5));
        await Db.SeatAsync(p, holder, next);
        var before = await Db.ReadSeatAsync(p);

        var result = await rig.RestoreAsync(caller, rig.Android(caller, p));

        Assert.Equal(RestoreResultKind.MoveCooldown, result.Kind);
        Assert.Equal(next, result.NextMoveAt);
        Assert.Equal(TimeSpan.Zero, result.NextMoveAt!.Value.TimeOfDay - TimeSpan.FromHours(result.NextMoveAt.Value.Hour));
        Assert.Equal(before, await Db.ReadSeatAsync(p));
        Assert.Empty(await Db.EventsAsync(p));
        Assert.Equal(caller.Value, Assert.Single(await Db.ClaimantsAsync(p)).Install);
        Assert.Contains(rig.Telemetry, t => t == "cooldown");
    }

    [Fact]
    public async Task AnItemThatMovedWinsOverARefusedOneAndTheCallIsA200()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var free = await Db.PurchaseAsync(holder);
        var held = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(free, holder, null);
        await Db.SeatAsync(held, holder, SeatClock.NextMoveAfter(rig.Time.Now));

        var result = await rig.RestoreAsync(caller, rig.Android(caller, free, held));

        Assert.Equal(RestoreResultKind.Completed, result.Kind);
        Assert.Equal("active", result.Status);
        Assert.Equal(1, result.RestoredCount);
        Assert.Equal(holder.Value, (await Db.ReadSeatAsync(held))!.Holder);
    }

    [Fact]
    public async Task AnAccountLinkedPurchaseWithoutTheAccountTokenIsAccountRequiredAndMovesNothing()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var account = await Db.AccountAsync(holder);
        var p = await Db.PurchaseAsync(holder, account);
        await Db.SeatAsync(p, holder, null);
        var before = await Db.ReadSeatAsync(p);

        var without = await rig.RestoreAsync(caller, rig.Android(caller, p));
        var wrong = await rig.RestoreAsync(caller, rig.Android(caller, p), account: "valid:" + Guid.NewGuid());

        Assert.Equal("account_required", without.Status);
        Assert.Equal("account_required", wrong.Status);
        Assert.Null(without.EntitlementToken);
        Assert.Equal(0, without.RestoredCount);
        Assert.Equal(before, await Db.ReadSeatAsync(p));
        Assert.Empty(await Db.ClaimantsAsync(p));

        var signedIn = await rig.RestoreAsync(caller, rig.Android(caller, p), account: "valid:" + account);
        Assert.Equal("active", signedIn.Status);
        Assert.Equal(caller.Value, (await Db.ReadSeatAsync(p))!.Holder);
    }

    [Fact]
    public void TheAggregateFollowsThePrecedence()
    {
        Assert.Equal("active", RestoreService.Aggregate([RestoreItemOutcome.Invalid, RestoreItemOutcome.Active, RestoreItemOutcome.Pending]));
        Assert.Equal("pending", RestoreService.Aggregate([RestoreItemOutcome.AccountRequired, RestoreItemOutcome.Pending]));
        Assert.Equal("account_required", RestoreService.Aggregate([RestoreItemOutcome.Expired, RestoreItemOutcome.AccountRequired]));
        Assert.Equal("expired", RestoreService.Aggregate([RestoreItemOutcome.Refunded, RestoreItemOutcome.Expired]));
        Assert.Equal("refunded", RestoreService.Aggregate([RestoreItemOutcome.Invalid, RestoreItemOutcome.Refunded]));
        Assert.Equal("invalid", RestoreService.Aggregate([RestoreItemOutcome.Invalid]));
    }

    [Fact]
    public async Task NonActiveStoreResultsFoldWithoutTouchingASeat()
    {
        var rig = NewRig();
        var caller = await Db.InstallAsync("android");
        var expired = rig.Script("expired", new StoreVerificationResult(VerifyStatus.Expired, null, Guid.NewGuid(), GoldPlan.Monthly, null, PurchaseEnvironment.Production, null, true));
        var pending = rig.Script("pending", new StoreVerificationResult(VerifyStatus.Pending, null, Guid.NewGuid(), GoldPlan.Monthly, null, PurchaseEnvironment.Production, null, false));
        var invalid = rig.Script("invalid", StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid));

        Assert.Equal("pending", (await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, expired, pending, invalid))).Status);
        Assert.Equal("expired", (await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, invalid, expired))).Status);
        var last = await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, invalid));
        Assert.Equal("invalid", last.Status);
        Assert.Null(last.EntitlementToken);
    }

    // ---- order of checks: nothing is written on a failed proof ------------------------------------------------------------

    [Theory]
    [InlineData(AttestationFailure.HashMismatch)]
    [InlineData(AttestationFailure.Stale)]
    [InlineData(AttestationFailure.Replayed)]
    [InlineData(AttestationFailure.NoIntegrity)]
    public async Task AFailedProofIs422ReportedByReasonAndNothingIsWrittenOrAskedOfTheStore(AttestationFailure failure)
    {
        var rig = NewRig();
        rig.Play.Result = AttestationResult.Failed(failure);
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null);
        var before = await Db.ReadSeatAsync(p);

        var result = await rig.RestoreAsync(caller, rig.Android(caller, p));

        Assert.Equal(RestoreResultKind.AttestationFailed, result.Kind);
        Assert.Equal(0, rig.PlayStore.Calls);
        Assert.Equal(before, await Db.ReadSeatAsync(p));
        Assert.Empty(await Db.EventsAsync(p));
        Assert.Empty(await Db.ClaimantsAsync(p));
        Assert.Contains(rig.Telemetry, t => t == "android:" + AttestationCodes.Of(failure));
    }

    [Fact]
    public async Task AnAttestationOutageIs503AndNeverA422()
    {
        var rig = NewRig();
        rig.Play.Result = AttestationResult.Unavailable;
        var caller = await Db.InstallAsync("android");

        var result = await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, rig.Script("t1", StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid))));

        Assert.Equal(RestoreResultKind.Unavailable, result.Kind);
        Assert.True(result.RetryAfterSeconds > 0);
        Assert.Empty(rig.Telemetry);
    }

    [Fact]
    public async Task AStoreOutageAbortsBeforeAnySeatChangesAndABudgetShortageIsMarked()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null);
        var good = rig.ScriptPurchase("good", p);
        rig.PlayStore.Failures["down"] = new StoreUnavailableException(StoreFailureKind.Store, 17);
        rig.PlayStore.Failures["budget"] = new StoreUnavailableException(StoreFailureKind.Budget, 600);

        var down = await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, good, "down"));
        var budget = await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, good, "budget"));

        Assert.Equal(RestoreResultKind.StoreUnavailable, down.Kind);
        Assert.False(down.BudgetShort);
        Assert.Equal(17, down.RetryAfterSeconds);
        Assert.Equal(RestoreResultKind.StoreUnavailable, budget.Kind);
        Assert.True(budget.BudgetShort);
        Assert.Equal(holder.Value, (await Db.ReadSeatAsync(p))!.Holder);
        Assert.Empty(await Db.EventsAsync(p));
    }

    // ---- limits ------------------------------------------------------------------------------------------------------------

    [Fact]
    public async Task TheEleventhAttemptOnOnePurchaseInADayAcrossInstallsIsRefused()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null);
        var token = rig.ScriptPurchase("shared-token", p);
        var results = new List<RestoreResultKind>();
        for (var i = 0; i < 11; i++)
        {
            var caller = await Db.InstallAsync("android");
            results.Add((await rig.RestoreAsync(caller, RestoreRig.AndroidTokens(caller, token))).Kind);
        }

        Assert.All(results.Take(10), kind => Assert.NotEqual(RestoreResultKind.PurchaseRateLimited, kind));
        Assert.Equal(RestoreResultKind.PurchaseRateLimited, results[10]);

        rig.Time.Now = rig.Time.Now.AddHours(25);
        var later = await Db.InstallAsync("android");
        Assert.NotEqual(RestoreResultKind.PurchaseRateLimited, (await rig.RestoreAsync(later, RestoreRig.AndroidTokens(later, token))).Kind);
    }

    // ---- FU-112: fixed lock order -------------------------------------------------------------------------------------------

    [Fact]
    public async Task ItemsAreSeatedInAscendingPurchaseOrderWhateverTheRequestOrder()
    {
        var rig = NewRig();
        var holder = await Db.InstallAsync("android");
        var caller = await Db.InstallAsync("android");
        var first = await Db.PurchaseAsync(holder);
        await Task.Delay(5);
        var second = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(first, holder, null);
        await Db.SeatAsync(second, holder, null);
        Assert.True(first.CompareTo(second) < 0);

        await rig.RestoreAsync(caller, rig.Android(caller, second, first));

        var order = await ScalarListAsync("SELECT purchase_id FROM zaghlol.purchase_events WHERE purchase_id IN (@a, @b) ORDER BY id", first, second);
        Assert.Equal([first, second], order);
    }

    [Fact]
    public async Task TwoRestoresOverTheSamePurchasesInOppositeOrderNeverDeadlock()
    {
        var holder = await Db.InstallAsync("android");
        var purchases = new List<Guid>();
        for (var i = 0; i < 6; i++)
        {
            var p = await Db.PurchaseAsync(holder);
            await Db.SeatAsync(p, holder, null);
            purchases.Add(p);
        }

        var a = NewRig();
        var b = NewRig();
        var one = await Db.InstallAsync("android");
        var two = await Db.InstallAsync("android");
        var forward = a.Android(one, [.. purchases]);
        var backward = b.Android(two, [.. purchases.AsEnumerable().Reverse()]);

        var results = await Task.WhenAll(a.RestoreAsync(one, forward), b.RestoreAsync(two, backward));

        // One of them seats everything; the other then meets the cooldown. Either way both finish: no deadlock, no exception.
        Assert.Contains(results, r => r.Kind == RestoreResultKind.Completed);
        Assert.All(results, r => Assert.True(r.Kind is RestoreResultKind.Completed or RestoreResultKind.MoveCooldown));
    }

    // ---- iOS: App Attest, seat keys ------------------------------------------------------------------------------------------

    [Fact]
    public async Task R56AnElementZeroThatIsNotTheRegisteredKeyIs400AndTheCounterSeatAndRowsAreUnchanged()
    {
        var rig = NewRig();
        var registered = Signer();
        var other = Signer();
        var holder = await Db.InstallAsync("ios");
        var caller = await Db.InstallAsync("ios");
        var p = await Db.PurchaseAsync(holder);
        await Db.SeatAsync(p, holder, null);
        await rig.RegisterKeyAsync(caller, registered);
        await SeedAppAttestKeyAsync(caller, 5);
        var seatBefore = await Db.ReadSeatAsync(p);
        var keyBefore = await Db.InstallKeyAsync(caller);

        var result = await rig.RestoreAsync(caller, rig.Ios(caller, p, [other, registered]));

        Assert.Equal(RestoreResultKind.SeatKeyMismatch, result.Kind);
        Assert.Equal(5, await AppAttestCounterAsync(caller));
        Assert.Equal(seatBefore, await Db.ReadSeatAsync(p));
        var keyAfter = await Db.InstallKeyAsync(caller);
        Assert.Equal(keyBefore.Hash, keyAfter.Hash);
        Assert.Equal(keyBefore.Trusted, keyAfter.Trusted);
        Assert.Empty(await Db.EventsAsync(p));
        Assert.Empty(await Db.ClaimantsAsync(p));
        Assert.Equal(0, rig.AppleStore.Calls);

        // The same assertion with a matching element 0 does advance the counter, so the rollback above was the mismatch's doing.
        var ok = await rig.RestoreAsync(caller, rig.Ios(caller, p, [registered]));
        Assert.Equal("active", ok.Status);
        Assert.Equal(6, await AppAttestCounterAsync(caller));
    }

    [Fact]
    public async Task R52APassingRestoreRegistersElementZeroTrustedAndUpgradesAnUntrustedOne()
    {
        var rig = NewRig();
        var fresh = await Db.InstallAsync("ios");
        var upgraded = await Db.InstallAsync("ios");
        var freshKey = Signer();
        var untrustedKey = Signer();
        var p1 = await Db.PurchaseAsync(fresh);
        var p2 = await Db.PurchaseAsync(upgraded);
        await SeedAppAttestKeyAsync(fresh, 1);
        await SeedAppAttestKeyAsync(upgraded, 1);
        await rig.RegisterKeyAsync(upgraded, untrustedKey);
        Assert.False((await Db.InstallKeyAsync(upgraded)).Trusted);

        await rig.RestoreAsync(fresh, rig.Ios(fresh, p1, [freshKey]));
        await rig.RestoreAsync(upgraded, rig.Ios(upgraded, p2, [untrustedKey]));

        Assert.True((await Db.InstallKeyAsync(fresh)).Trusted);
        Assert.NotNull((await Db.InstallKeyAsync(fresh)).Hash);
        Assert.True((await Db.InstallKeyAsync(upgraded)).Trusted);
    }

    [Fact]
    public async Task D65aAThirdSameIPhoneRestoreWithinThirtyDaysPassesRestartsTheWindowAndRaisesTheAlert()
    {
        var rig = NewRig();
        var keys = Enumerable.Range(0, 4).Select(_ => Signer()).ToArray();
        var installs = new List<InstallId>();
        for (var i = 0; i < 4; i++)
        {
            installs.Add(await Db.InstallAsync("ios"));
            await SeedAppAttestKeyAsync(installs[i], 1);
        }

        var p = await Db.PurchaseAsync(installs[0]);
        await Db.SeatAsync(p, installs[0], null, HMACSHA256.HashData(FakeKms.FixedSeatKey, SeatKeyHasher.SeatKeyInput(p, keys[0].PublicPoint)));
        var results = new List<string>();
        for (var i = 1; i < 4; i++)
        {
            rig.Time.Now = rig.Time.Now.AddDays(9);
            var result = await rig.RestoreAsync(installs[i], rig.Ios(installs[i], p, [keys[i], keys[i - 1]]));
            Assert.Equal("active", result.Status);
            Assert.False(result.MovedFromOtherPhone);
            results.Add(string.Join(",", await Db.EventsAsync(p)));
        }

        Assert.Equal(["seat_rebind:restore,seat_rebind:restore,seat_rebind_over_cap:restore"], results.Skip(2));
        Assert.Equal([p], rig.SeatTelemetry.Alerts);
        var seat = (await Db.ReadSeatAsync(p))!;
        Assert.Equal(installs[3].Value, seat.Holder);
        Assert.Equal(SeatClock.NextMoveAfter(rig.Time.Now), seat.NextMoveAt);
    }

    [Fact]
    public async Task R413AReorderedOrReplacedSeatKeyAfterTheAssertionWasMadeIs422()
    {
        var rig = NewRig();
        var a = Signer();
        var b = Signer();
        var c = Signer();
        var caller = await Db.InstallAsync("ios");
        var p = await Db.PurchaseAsync(caller);
        await SeedAppAttestKeyAsync(caller, 1);
        var original = rig.Ios(caller, p, [a, b]);
        rig.AppAttest.ExpectedClientDataHash = RestoreRequestParser.ClientDataHash(original.BodyHash, DigestOf(a, b));

        Assert.Equal("active", (await rig.RestoreAsync(caller, original)).Status);

        var reordered = original with { SeatKeys = [original.SeatKeys![1], original.SeatKeys![0]] };
        var replaced = original with { SeatKeys = [original.SeatKeys![0], new SeatKeyProofInput(c.PublicKey, original.SeatKeys![1].Signature)] };
        Assert.Equal(RestoreResultKind.AttestationFailed, (await rig.RestoreAsync(caller, reordered)).Kind);
        Assert.Equal(RestoreResultKind.AttestationFailed, (await rig.RestoreAsync(caller, replaced)).Kind);
    }

    [Fact]
    public async Task ABadSeatKeySignatureIs400AfterAttestationAndAMalformedSetIs400BeforeIt()
    {
        var rig = NewRig();
        var key = Signer();
        var caller = await Db.InstallAsync("ios");
        var p = await Db.PurchaseAsync(caller);
        await SeedAppAttestKeyAsync(caller, 1);
        var request = rig.Ios(caller, p, [key]);

        var badSignature = request with { SeatKeys = [SeatKeyTestSigner.Defective(request.SeatKeys![0], SeatKeyDefect.FlippedSignatureBit)] };
        var malformed = request with { SeatKeys = [new SeatKeyProofInput("not-a-key", "nope")] };

        Assert.Equal(RestoreResultKind.ValidationFailed, (await rig.RestoreAsync(caller, badSignature)).Kind);
        Assert.Equal(1, rig.AppAttest.Assertions);
        Assert.Equal(RestoreResultKind.ValidationFailed, (await rig.RestoreAsync(caller, malformed)).Kind);
        Assert.Equal(1, rig.AppAttest.Assertions);
        Assert.Equal(1, await AppAttestCounterAsync(caller));
    }

    // ---- plumbing ------------------------------------------------------------------------------------------------------------

    private static byte[] DigestOf(params SeatKeyTestSigner[] keys) => SHA256.HashData([.. keys.SelectMany(k => k.PublicPoint)]);

    private SeatKeyTestSigner Signer()
    {
        var signer = new SeatKeyTestSigner();
        signers.Add(signer);
        return signer;
    }

    private RestoreRig NewRig() => new(fixture, signers);

    private async Task SeedAppAttestKeyAsync(InstallId install, long counter) => await fixture.ExecAsync(
        $"INSERT INTO zaghlol.app_attest_keys (key_id, install_id, public_key, sign_count, environment) VALUES ('\\x{Convert.ToHexString(RandomNumberGenerator.GetBytes(32))}', '{install}', '\\x{Convert.ToHexString(new byte[65])}', {counter}, 'production')");

    private async Task<long> AppAttestCounterAsync(InstallId install) =>
        await fixture.ScalarAsync<long>($"SELECT sign_count FROM zaghlol.app_attest_keys WHERE install_id = '{install}'");

    private async Task<List<Guid>> ScalarListAsync(string sql, Guid a, Guid b)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("a", a);
        command.Parameters.AddWithValue("b", b);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<Guid>();
        while (await reader.ReadAsync())
        {
            rows.Add(reader.GetGuid(0));
        }

        return rows;
    }
}

/// <summary>A scripted store verifier: a token (or signed transaction) maps to a result or a failure.</summary>
internal sealed class ScriptedStore(PurchaseStore store) : IStoreVerification
{
    public Dictionary<string, StoreVerificationResult> Results { get; } = [];

    public Dictionary<string, StoreUnavailableException> Failures { get; } = [];

    public int Calls { get; private set; }

    public PurchaseStore Store => store;

    public Task<StoreVerificationResult> VerifyAsync(StorePurchaseRef purchase, InstallId caller, BindingCheck binding, CancellationToken cancellationToken)
    {
        Calls++;
        Assert.Equal(BindingCheck.Skip, binding);
        var key = purchase switch
        {
            PlayPurchaseRef play => play.PurchaseToken.Reveal(),
            AppStorePurchaseRef apple => apple.SignedTransaction.Reveal(),
            _ => throw new InvalidOperationException(),
        };
        if (Failures.TryGetValue(key, out var failure))
        {
            throw failure;
        }

        return Task.FromResult(Results.TryGetValue(key, out var result) ? result : StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid));
    }
}

/// <summary>The original transaction ID of a stub JWS is the JWS text itself.</summary>
internal sealed class StubJws : IAppleJwsVerifier
{
    public AppleTransaction VerifyTransaction(Sensitive<string> jws, JwsSource source, DateTimeOffset now) => new(
        "bundle",
        AppleEnvironment.Production,
        "zaghlol_gold_lifetime",
        AppleProductType.NonConsumable,
        jws,
        jws,
        null,
        AppleOwnershipType.Purchased,
        AppleTransactionReason.Purchase,
        now,
        null,
        null,
        null,
        now);

    public AppleRenewalInfo VerifyRenewalInfo(Sensitive<string> jws, JwsSource source, DateTimeOffset now) => throw new NotSupportedException();

    public AppleNotification VerifyNotification(Sensitive<string> signedPayload, DateTimeOffset now) => throw new NotSupportedException();
}

internal sealed class RecordingRestoreTelemetry : IRestoreTelemetry
{
    public List<string> Events { get; } = [];

    public void AttestationFailed(string platform, string reason) => Events.Add(platform + ":" + reason);

    public void MoveCooldownRefused() => Events.Add("cooldown");
}

/// <summary>One test's wiring: real seat service, seat transactions, entitlement service and limiter over the fixture's database.</summary>
internal sealed class RestoreRig
{
    private readonly EntitlementFixture fixture;
    private readonly List<SeatKeyTestSigner> signers;
    private readonly RecordingRestoreTelemetry telemetry = new();
    private readonly RestoreService service;
    private readonly SeatKeyProofVerifier proofs = new(new NullSeatKeyMetrics());
    private readonly SeatService seats;

    public RestoreRig(EntitlementFixture fixture, List<SeatKeyTestSigner> signers)
    {
        this.fixture = fixture;
        this.signers = signers;
        Time = new ManualTime(EntitlementFixture.Start);
        Signer = new CapturingSigner();
        SeatTelemetry = new RecordingSeatTelemetry();
        seats = new SeatService(new SeatKeyHasher(new FixedSeatMac(), new NullSeatKeyMetrics()), SeatTelemetry, Time);
        var entitlements = new EntitlementService(new EntitlementStore(fixture.Services), Signer, new HeaderAccountValidator(), Time);
        service = new RestoreService(
            [PlayStore, AppleStore],
            new StubJws(),
            Play,
            AppAttest,
            proofs,
            new SeatTransactionFactory(fixture.Services),
            seats,
            new HeaderAccountValidator(),
            entitlements,
            new RestoreAttemptLimiter(Time),
            telemetry,
            Time);
    }

    public ManualTime Time { get; }

    public CapturingSigner Signer { get; }

    public RecordingSeatTelemetry SeatTelemetry { get; }

    public FakePlayIntegrityVerifier Play { get; } = new();

    public FakeAppAttestVerifier AppAttest { get; } = new();

    public ScriptedStore PlayStore { get; } = new(PurchaseStore.GooglePlay);

    public ScriptedStore AppleStore { get; } = new(PurchaseStore.AppStore);

    public List<string> Telemetry => telemetry.Events;

    public Task<RestoreResult> RestoreAsync(InstallId install, RestoreRequest request, string? account = null) => service.RestoreAsync(
        request,
        install,
        account is null ? null : new Sensitive<string>(account),
        CancellationToken.None);

    /// <summary>Scripts a token as an active purchase row.</summary>
    public string ScriptPurchase(string token, Guid purchaseId)
    {
        PlayStore.Results[token] = Active(purchaseId);
        return token;
    }

    public string Script(string token, StoreVerificationResult result)
    {
        PlayStore.Results[token] = result;
        return token;
    }

    public AndroidRestoreRequest Android(InstallId caller, params Guid[] purchases)
    {
        var tokens = purchases.Select(p => ScriptPurchase("tok-" + p.ToString("N"), p)).ToArray();
        return AndroidTokens(caller, tokens);
    }

    public static AndroidRestoreRequest AndroidTokens(InstallId caller, params string[] tokens)
    {
        var request = new AndroidRestoreRequest
        {
            Purchases = [.. tokens.Select(t => new PlayPurchaseRef("zaghlol_gold_monthly", new Sensitive<string>(t)))],
            IntegrityToken = new Sensitive<string>("integrity-token-0123456789"),
            BodyHash = RandomNumberGenerator.GetBytes(32),
        };
        return request;
    }

    public IosRestoreRequest Ios(InstallId caller, Guid purchase, SeatKeyTestSigner[] keys)
    {
        var jws = "jws-" + purchase.ToString("N");
        AppleStore.Results[jws] = Active(purchase);
        var bodyHash = RandomNumberGenerator.GetBytes(32);
        var challenge = SeatChallenge.ForRestore(bodyHash);
        var request = new IosRestoreRequest
        {
            SignedTransactions = [new Sensitive<string>(jws)],
            KeyId = RandomNumberGenerator.GetBytes(32),
            Assertion = RandomNumberGenerator.GetBytes(48),
            SeatKeys = [.. keys.Select(k => k.Prove(challenge, caller))],
            BodyHash = bodyHash,
        };
        return request;
    }

    /// <summary>Registers <paramref name="key"/> as the install's element 0, untrusted (as verify or sign-in would).</summary>
    public async Task RegisterKeyAsync(InstallId install, SeatKeyTestSigner key)
    {
        var challenge = SeatChallenge.ForVerify("eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln");
        var verified = proofs.ParseAndVerify([key.Prove(challenge, install)], challenge, install);
        await using var tx = await new SeatTransactionFactory(fixture.Services).BeginAsync(SeatLogin.App, CancellationToken.None);
        await seats.RegisterElementZeroAsync(tx.Seats, verified.Keys!, null, CancellationToken.None);
        await tx.CommitAsync(CancellationToken.None);
    }

    private static StoreVerificationResult Active(Guid purchaseId) =>
        new(VerifyStatus.Active, null, purchaseId, GoldPlan.Monthly, null, PurchaseEnvironment.Production, null, true);
}
