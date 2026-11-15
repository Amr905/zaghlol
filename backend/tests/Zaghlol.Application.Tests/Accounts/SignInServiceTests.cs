using System.Security.Cryptography;
using System.Text;
using Zaghlol.Application.Accounts;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Application.Tests.Entitlements;
using Zaghlol.Application.Tests.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Accounts;

/// <summary>
/// The order of <see cref="SignInService"/> before it opens a transaction (backend-api §4.6): platform, nonce, age, single use. Every
/// refusal here must come without a transaction (so nothing can be linked), and the replay row must be spent by the first good
/// verification even though the transaction that follows never runs (R3-5; the committing path is covered against PostgreSQL).
/// </summary>
public class SignInServiceTests
{
    private const string RawNonce = "Q2FwdGFpblphZ2hsb2xOb25jZTEyMzQ";

    private static readonly DateTimeOffset Now = EntitlementTestKit.Now;

    private readonly FakeAccountStore store = new();
    private readonly SetReplayGuard replay = new();
    private readonly NoTransactions transactions = new();
    private readonly RecordingApple apple = new();

    private static string Hashed(string raw) => Convert.ToHexStringLower(SHA256.HashData(Encoding.ASCII.GetBytes(raw)));

    private static IdTokenResult Token(string? nonceClaim, TimeSpan? age = null, DateTimeOffset? issued = null) =>
        new(IdTokenOutcome.Verified, new VerifiedIdToken("sub-1", null, "client", nonceClaim, issued ?? Now - (age ?? TimeSpan.FromSeconds(3)), Now.AddHours(1)));

    private SignInService Service(IdTokenResult verification, ScriptedIdTokenVerifier? verifier = null)
    {
        var clock = new ManualClock(Now);
        var metrics = new RecordingSeatMetrics();
        var signer = new FakeEntitlementSigner();
        return new SignInService(
            store,
            verifier ?? new ScriptedIdTokenVerifier(verification),
            replay,
            apple,
            new IdentityVault(),
            new SeatKeyProofVerifier(metrics),
            new SeatService(new SeatKeyHasher(new CountingSeatMac(), metrics), new NullSeatTelemetry(), clock),
            transactions,
            new EntitlementService(new FakeEntitlementStore(), signer, new FakeAccountValidator(null), clock),
            signer,
            clock);
    }

    private static SignInCommand Command(string? nonce = RawNonce, IReadOnlyList<SeatKeyProofInput?>? seatKeys = null, AccountProvider provider = AccountProvider.Google, string? code = null) =>
        new(
            provider,
            new Sensitive<string>("a.b.c"),
            nonce is null ? null : new Sensitive<string>(nonce),
            code is null ? null : new Sensitive<string>(code),
            ReplaceLink: false,
            seatKeys);

    [Fact]
    public void TheNonceMatchesOnlyWhenTheClaimIsTheLowerCaseHexOfItsSha256()
    {
        Assert.True(SignInService.NonceMatches(RawNonce, Hashed(RawNonce)));
        Assert.False(SignInService.NonceMatches(RawNonce, Hashed(RawNonce).ToUpperInvariant()));
        Assert.False(SignInService.NonceMatches(RawNonce, RawNonce));
        Assert.False(SignInService.NonceMatches(RawNonce, Hashed(RawNonce)[..^1]));
        Assert.False(SignInService.NonceMatches(RawNonce, Hashed(RawNonce) + "0"));
        Assert.False(SignInService.NonceMatches(RawNonce, null));
        Assert.False(SignInService.NonceMatches(RawNonce, string.Empty));
        Assert.False(SignInService.NonceMatches("nönce", Hashed("nönce")));
    }

    [Fact]
    public async Task ARequestWithoutANonceIsRefusedBeforeTheTokenIsEvenVerified()
    {
        var verifier = new ScriptedIdTokenVerifier(Token(Hashed(RawNonce)));

        var result = await Service(Token(Hashed(RawNonce)), verifier).SignInAsync(Command(nonce: null), EntitlementTestKit.Caller, default);

        Assert.Equal(SignInResultKind.IdTokenInvalid, result.Kind);
        Assert.Equal(0, verifier.Calls);
        Assert.Equal(0, transactions.Begun);
        Assert.Empty(replay.Used);
    }

    [Theory]
    [InlineData("no-claim")]
    [InlineData("raw-as-claim")]
    [InlineData("other-hash")]
    [InlineData("stale")]
    [InlineData("from-the-future")]
    [InlineData("no-iat")]
    public async Task ABadClaimOrAgeIsRefusedWithoutSpendingTheReplayRowOrOpeningATransaction(string defect)
    {
        var token = defect switch
        {
            "no-claim" => Token(null),
            "raw-as-claim" => Token(RawNonce),
            "other-hash" => Token(Hashed("a-different-nonce-0123456789")),
            "stale" => Token(Hashed(RawNonce), age: SignInService.MaxTokenAge + TimeSpan.FromSeconds(1)),
            "from-the-future" => Token(Hashed(RawNonce), issued: Now + SignInService.MaxIssuedInFuture + TimeSpan.FromSeconds(1)),
            _ => new IdTokenResult(IdTokenOutcome.Verified, new VerifiedIdToken("sub-1", null, "client", Hashed(RawNonce), null, Now.AddHours(1))),
        };

        var result = await Service(token).SignInAsync(Command(), EntitlementTestKit.Caller, default);

        Assert.Equal(SignInResultKind.IdTokenInvalid, result.Kind);
        Assert.Equal(0, transactions.Begun);
        Assert.Empty(replay.Used);
    }

    [Fact]
    public async Task ATokenAtTheTenMinuteLimitIsStillFresh()
    {
        var service = Service(Token(Hashed(RawNonce), age: SignInService.MaxTokenAge));

        // It gets as far as the (refusing) transaction factory: the replay row is spent, nothing before it refused.
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.SignInAsync(Command(), EntitlementTestKit.Caller, default));

        Assert.Equal(1, transactions.Begun);
        Assert.Single(replay.Used);
    }

    [Fact]
    public async Task TheReplayRowIsSpentBeforeTheTransactionOpens_SoAFailingTransactionCannotMakeTheTokenReusable()
    {
        var service = Service(Token(Hashed(RawNonce)));
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.SignInAsync(Command(), EntitlementTestKit.Caller, default));
        Assert.Equal(1, transactions.Begun);
        Assert.Single(replay.Used);

        var second = await service.SignInAsync(Command(), EntitlementTestKit.Caller, default);

        Assert.Equal(SignInResultKind.IdTokenInvalid, second.Kind);
        Assert.Equal(1, transactions.Begun);
    }

    [Fact]
    public async Task UnavailableKeysAndInvalidTokensAreDistinct_AndNeitherSpendsTheReplayRow()
    {
        var down = await Service(IdTokenResult.Unavailable).SignInAsync(Command(), EntitlementTestKit.Caller, default);
        var invalid = await Service(IdTokenResult.Invalid).SignInAsync(Command(), EntitlementTestKit.Caller, default);

        Assert.Equal(SignInResultKind.Unavailable, down.Kind);
        Assert.Equal(SignInResultKind.IdTokenInvalid, invalid.Kind);
        Assert.Empty(replay.Used);
        Assert.Equal(0, transactions.Begun);
    }

    [Fact]
    public async Task SeatKeysFromAnAndroidInstallAreRefusedFirst_AndADeletedInstallIs401Material()
    {
        var keys = new SeatKeyProofInput?[] { new("k", "s") };
        var verifier = new ScriptedIdTokenVerifier(Token(Hashed(RawNonce)));
        store.Platform = "android";
        var android = await Service(Token(Hashed(RawNonce)), verifier).SignInAsync(Command(seatKeys: keys), EntitlementTestKit.Caller, default);
        store.Platform = null;
        var gone = await Service(Token(Hashed(RawNonce)), verifier).SignInAsync(Command(), EntitlementTestKit.Caller, default);
        store.Platform = "ios";
        var malformed = await Service(Token(Hashed(RawNonce)), verifier).SignInAsync(Command(seatKeys: keys), EntitlementTestKit.Caller, default);

        Assert.Equal(SignInResultKind.ValidationFailed, android.Kind);
        Assert.Equal(SignInResultKind.InstallGone, gone.Kind);
        Assert.Equal(SignInResultKind.ValidationFailed, malformed.Kind);
        Assert.Equal(0, verifier.Calls);
        Assert.Empty(replay.Used);
    }

    [Fact]
    public void ResultsAndCommandsNeverRenderTheirSecrets()
    {
        var command = Command(code: "authcode-secret", provider: AccountProvider.Apple);
        var result = new SignInResult(SignInResultKind.Completed, Guid.NewGuid(), new Sensitive<string>("account-token-secret"), new Sensitive<string>("entitlement-secret"));

        Assert.DoesNotContain("secret", command.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("secret", result.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("secret", new VerifiedIdToken("subject-secret", "mail-secret", "aud", "n", Now, Now).ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("secret", new AppleRefreshToken("c", new Sensitive<string>("token-secret")).ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("secret", new AccountForDelete(AccountProvider.Apple, "subject-secret", [1]).ToString(), StringComparison.Ordinal);
    }
}
