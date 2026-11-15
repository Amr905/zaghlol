using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Zaghlol.Application.Accounts;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Testing;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Accounts;

/// <summary>
/// T-135 through the real pipeline (install token, time nonce, idempotency, response signing) over PostgreSQL 17 with the real seat,
/// entitlement and account services; only the ID-token verifier and Apple's token endpoint are scripted.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class AccountEndpointTests(AccountsHostFixture f) : IClassFixture<AccountsHostFixture>
{
    private static async Task<JsonElement> JsonOf(HttpResponseMessage response)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, $"expected 200, got {(int)response.StatusCode}: {text}");
        return JsonDocument.Parse(text).RootElement.Clone();
    }

    private async Task<(JsonElement Body, string AccountToken, Guid AccountId)> SignedInAsync(
        string installToken, string provider, string subject, string? code = null, string? timeNonce = null)
    {
        var (raw, idToken) = f.Credential(subject);
        using var response = await f.SignInAsync(installToken, AccountsHostFixture.SignInBody(provider, idToken, raw, code), timeNonce: timeNonce);
        var body = await JsonOf(response);
        return (body, body.GetProperty("accountToken").GetString()!, body.GetProperty("accountId").GetGuid());
    }

    private static string NewSubject() => "sub-" + Guid.NewGuid().ToString("N");

    [Fact]
    public async Task Fr_Gold_07_BuyOnAndroidSignInOnIPhoneMovesTheSeat_AThirdPhoneInsideTheCooldownGets200MoveRefused_AndTheTokenIsSingleUse()
    {
        var (a, tokenA) = await f.NewInstallOfAsync("android");
        var (b, tokenB) = await f.NewInstallOfAsync("ios");
        var (c, tokenC) = await f.NewInstallOfAsync("android");
        var purchase = await f.PurchaseAsync(buyer: a, holder: a);
        var subject = NewSubject();

        // The buying phone signs in: link, attach (D-54), the seat stays.
        var (first, _, accountId) = await SignedInAsync(tokenA, "google", subject);
        var attached = await f.PurchaseLinkAsync(purchase);
        Assert.Equal(accountId, attached.Account);
        Assert.Equal("signin", attached.LinkedBy);
        Assert.Null(attached.Reclaim);
        Assert.Equal(1, first.GetProperty("linkedInstalls").GetInt32());
        Assert.False(first.GetProperty("moveRefused").GetBoolean());
        Assert.Equal("active", AccountsHostFixture.StatusOf(first.GetProperty("entitlement").GetProperty("token").GetString()!));

        // The iPhone signs in to the same account: the seat moves (no cooldown yet), the 200 echoes the time nonce (R4-2).
        var nonce = FakeIdTokenVerifier.NewRawNonce();
        var (raw2, id2) = f.Credential(subject);
        using var second = await f.SignInAsync(tokenB, AccountsHostFixture.SignInBody("google", id2, raw2), timeNonce: nonce);
        var moved = await JsonOf(second);
        Assert.True(second.Headers.Contains("Zaghlol-Signature"));
        Assert.Equal(nonce, moved.GetProperty("timeNonce").GetString());
        Assert.True(moved.GetProperty("movedFromOtherPhone").GetBoolean());
        Assert.False(moved.GetProperty("moveRefused").GetBoolean());
        Assert.Equal(2, moved.GetProperty("linkedInstalls").GetInt32());
        Assert.Equal("active", AccountsHostFixture.StatusOf(moved.GetProperty("entitlement").GetProperty("token").GetString()!));
        Assert.Equal(b, (await f.SeatAsync(purchase)).Holder);
        Assert.Contains("seat_move:signin", await f.EventsAsync(purchase));

        // A third phone inside the cooldown: 200 with moveRefused (never 409), the link is committed, it waits as a claimant (R3-5).
        var (raw3, id3) = f.Credential(subject);
        var body3 = AccountsHostFixture.SignInBody("google", id3, raw3);
        var key = AccountsHostFixture.NewKey();
        using var third = await f.SignInAsync(tokenC, body3, key);
        var refused = await JsonOf(third);
        Assert.True(refused.GetProperty("moveRefused").GetBoolean());
        Assert.False(refused.GetProperty("movedFromOtherPhone").GetBoolean());
        var next = DateTimeOffset.Parse(refused.GetProperty("nextMoveAt").GetString()!, System.Globalization.CultureInfo.InvariantCulture);
        Assert.Equal(TimeSpan.Zero, new TimeSpan(next.Minute, next.Second, 0));
        Assert.True(next > f.Clock.Now);
        Assert.NotEqual("active", AccountsHostFixture.StatusOf(refused.GetProperty("entitlement").GetProperty("token").GetString()!));
        Assert.Equal(b, (await f.SeatAsync(purchase)).Holder);
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE account_id = @a AND install_id = @i", ("a", accountId), ("i", c)));
        Assert.Contains((c, "signin"), await f.ClaimantsAsync(purchase));

        // The same ID token and nonce again, under a new key: refused by replay_guard even though the first call rolled nothing back.
        using var replayed = await f.SignInAsync(tokenC, body3);
        await ProblemAssert.AssertAsync(replayed, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");

        // The same key and body: the stored result comes back before the replay check (legitimate retry).
        using var retried = await f.SignInAsync(tokenC, body3, key);
        var again = await JsonOf(retried);
        Assert.Equal(refused.GetProperty("accountToken").GetString(), again.GetProperty("accountToken").GetString());
    }

    [Fact]
    public async Task R2_9_NonceIsRequiredAndMustMatchTheClaim_StaleAndReusedTokensAre422()
    {
        var (_, token) = await f.NewInstallOfAsync("android");
        var subject = NewSubject();

        // Without nonce in the request.
        var (_, withoutNonce) = f.Credential(subject);
        using var noNonce = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", withoutNonce, null));
        await ProblemAssert.AssertAsync(noNonce, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");

        // Without a nonce claim in the ID token.
        var (rawB, noClaim) = f.Credential(subject, omitNonceClaim: true);
        using var noClaimResponse = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", noClaim, rawB));
        await ProblemAssert.AssertAsync(noClaimResponse, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");

        // A claim that isn't hex(SHA-256(raw)): the raw value itself, and another nonce's hash.
        var (rawC, rawAsClaim) = f.Credential(subject, claim: FakeIdTokenVerifier.NewRawNonce());
        using var wrongClaim = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", rawAsClaim, rawC));
        await ProblemAssert.AssertAsync(wrongClaim, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");
        var (rawD, otherHash) = f.Credential(subject, claim: FakeIdTokenVerifier.Hashed(FakeIdTokenVerifier.NewRawNonce()));
        using var otherClaim = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", otherHash, rawD));
        await ProblemAssert.AssertAsync(otherClaim, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");

        // Older than 10 minutes.
        var (rawE, stale) = f.Credential(subject, age: TimeSpan.FromMinutes(10) + TimeSpan.FromSeconds(5));
        using var staleResponse = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", stale, rawE));
        await ProblemAssert.AssertAsync(staleResponse, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");

        // None of the refusals consumed a good token; a good one passes once and only once.
        var (rawF, good) = f.Credential(subject);
        var body = AccountsHostFixture.SignInBody("google", good, rawF);
        using var ok = await f.SignInAsync(token, body);
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        using var reused = await f.SignInAsync(token, body);
        await ProblemAssert.AssertAsync(reused, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");
    }

    [Fact]
    public async Task D54_ASignInFromAnInstallThatDidNotBuyNeverSetsTheAccountOnThePurchase()
    {
        var (buyer, _) = await f.NewInstallOfAsync("android");
        var (other, otherToken) = await f.NewInstallOfAsync("ios");
        var purchase = await f.PurchaseAsync(buyer: buyer, holder: buyer);

        await SignedInAsync(otherToken, "google", NewSubject());

        var link = await f.PurchaseLinkAsync(purchase);
        Assert.Null(link.Account);
        Assert.Null(link.LinkedBy);
        Assert.Equal(buyer, (await f.SeatAsync(purchase)).Holder);
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.purchase_events WHERE purchase_id = @p", ("p", purchase)));
        Assert.NotEqual(other, buyer);
    }

    [Fact]
    public async Task R3_3_D58_TheAttachReclaimIsSpentOnce_AfterDeletingTheAccountASecondSignInIsAnOrdinaryMoveUnderTheCooldown()
    {
        var (a, tokenA) = await f.NewInstallOfAsync("android");
        var (x, _) = await f.NewInstallOfAsync("android");
        var purchase = await f.PurchaseAsync(buyer: a, holder: x);
        var subject = NewSubject();

        // The buying phone signs in while another install holds the seat: the free reclaim (inside no cooldown here, but it counts as the move).
        var (first, accountToken, _) = await SignedInAsync(tokenA, "google", subject);
        Assert.True(first.GetProperty("movedFromOtherPhone").GetBoolean());
        var afterFirst = await f.SeatAsync(purchase);
        Assert.Equal(a, afterFirst.Holder);
        Assert.NotNull(afterFirst.NextMoveAt);
        Assert.NotNull((await f.PurchaseLinkAsync(purchase)).Reclaim);
        Assert.Contains("seat_move:account_attach", await f.EventsAsync(purchase));

        using var deleted = await f.AccountCallAsync(HttpMethod.Delete, "/v1/accounts/me", tokenA, accountToken);
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        var afterDelete = await f.PurchaseLinkAsync(purchase);
        Assert.Null(afterDelete.Account);
        Assert.Null(afterDelete.LinkedBy);
        Assert.NotNull(afterDelete.Reclaim);
        Assert.Equal(a, (await f.SeatAsync(purchase)).Holder);

        // The seat is somewhere else again, inside a running cooldown.
        await f.ExecuteAsync(
            """
            UPDATE zaghlol.purchase_seats SET install_id = @x, proof = 'binding',
                next_move_at = date_trunc('hour', now() + interval '10 days'),
                last_moved_at = date_trunc('hour', now() + interval '10 days') - interval '30 days'
            WHERE purchase_id = @p
            """,
            ("x", x),
            ("p", purchase));

        var (second, _, _) = await SignedInAsync(tokenA, "google", subject);

        Assert.True(second.GetProperty("moveRefused").GetBoolean());
        Assert.Equal(x, (await f.SeatAsync(purchase)).Holder);
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.purchase_events WHERE purchase_id = @p AND cause = 'seat_move:account_attach'", ("p", purchase)));
        Assert.NotNull((await f.PurchaseLinkAsync(purchase)).Account);
    }

    [Fact]
    public async Task Delete_WhileAppleIsDown_StillDeletesAtOnce_AndQueuesOnlyTheSealedToken()
    {
        var (a, tokenA) = await f.NewInstallOfAsync("ios");
        var (_, accountToken, accountId) = await SignedInAsync(tokenA, "apple", NewSubject(), code: "code-" + Guid.NewGuid().ToString("N"));
        var before = await f.CountAsync("SELECT count(*) FROM zaghlol.pending_apple_revocations");

        f.Apple.RevokeOutcome = AppleRevokeOutcome.Unavailable;
        try
        {
            using var deleted = await f.AccountCallAsync(HttpMethod.Delete, "/v1/accounts/me", tokenA, accountToken);

            Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        }
        finally
        {
            f.Apple.RevokeOutcome = AppleRevokeOutcome.Revoked;
        }

        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.accounts WHERE id = @a", ("a", accountId)));
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i", ("i", a)));
        Assert.Equal(before + 1, await f.CountAsync("SELECT count(*) FROM zaghlol.pending_apple_revocations"));
        // Sealed: the plaintext refresh token is nowhere in the row, and the row has no reference to the account.
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.pending_apple_revocations WHERE position('refresh-for-'::bytea in sealed_blob) > 0"));
        Assert.Equal(7, await f.CountAsync("SELECT count(*) FROM information_schema.columns WHERE table_schema = 'zaghlol' AND table_name = 'pending_apple_revocations'"));
    }

    [Fact]
    public async Task Delete_WhenAppleSaysInvalidGrant_QueuesNothing()
    {
        var (_, tokenA) = await f.NewInstallOfAsync("ios");
        var (_, accountToken, accountId) = await SignedInAsync(tokenA, "apple", NewSubject(), code: "code-" + Guid.NewGuid().ToString("N"));
        var before = await f.CountAsync("SELECT count(*) FROM zaghlol.pending_apple_revocations");

        // The real client maps invalid_grant to Revoked (AppleAccountClientTests); the fake's Revoked outcome is that path.
        using var deleted = await f.AccountCallAsync(HttpMethod.Delete, "/v1/accounts/me", tokenA, accountToken);

        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.accounts WHERE id = @a", ("a", accountId)));
        Assert.Equal(before, await f.CountAsync("SELECT count(*) FROM zaghlol.pending_apple_revocations"));
    }

    [Fact]
    public async Task Delete_RevokesTheAppleToken_RemovesTheAccountLinksAndItsIdempotencyRows_AndTheTokenIsThen401BeforeItsExpiry()
    {
        var (a, tokenA) = await f.NewInstallOfAsync("ios");
        var purchase = await f.PurchaseAsync(buyer: a, holder: a);
        var (_, accountToken, accountId) = await SignedInAsync(tokenA, "apple", NewSubject(), code: "code-" + Guid.NewGuid().ToString("N"));
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.accounts WHERE id = @a AND apple_refresh_token_enc IS NOT NULL", ("a", accountId)));
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.idempotency_records WHERE account_id = @a", ("a", accountId)));
        Assert.Equal(accountId, (await f.PurchaseLinkAsync(purchase)).Account);

        using var deleted = await f.AccountCallAsync(HttpMethod.Delete, "/v1/accounts/me", tokenA, accountToken);

        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Contains(f.Apple.Revoked, t => t.StartsWith("refresh-for-code-", StringComparison.Ordinal));
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.accounts WHERE id = @a", ("a", accountId)));
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE account_id = @a", ("a", accountId)));
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.idempotency_records WHERE account_id = @a", ("a", accountId)));
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.idempotency_records WHERE install_id = @i AND operation_id = 'signIn'", ("i", a)));
        var link = await f.PurchaseLinkAsync(purchase);
        Assert.Null(link.Account);
        Assert.Null(link.LinkedBy);
        Assert.Equal(a, (await f.SeatAsync(purchase)).Holder);

        // R3-6: the token's exp is 30 days away, but its account is gone.
        using var signOut = await f.AccountCallAsync(HttpMethod.Post, "/v1/accounts/signout", tokenA, accountToken);
        await ProblemAssert.AssertAsync(signOut, HttpStatusCode.Unauthorized, "ACCOUNT_TOKEN_EXPIRED");
        using var deleteAgain = await f.AccountCallAsync(HttpMethod.Delete, "/v1/accounts/me", tokenA, accountToken);
        await ProblemAssert.AssertAsync(deleteAgain, HttpStatusCode.Unauthorized, "ACCOUNT_TOKEN_EXPIRED");
        using var noToken = await f.AccountCallAsync(HttpMethod.Delete, "/v1/accounts/me", tokenA, null);
        await ProblemAssert.AssertAsync(noToken, HttpStatusCode.Unauthorized, "ACCOUNT_TOKEN_EXPIRED");
    }

    [Fact]
    public async Task SignOut_Returns200SignedWithTheAccountLinkedPurchasePaused_DoesNotMoveTheSeat_AndSigningInAgainHereIsNotAMove()
    {
        var (b, tokenB) = await f.NewInstallOfAsync("ios");
        var purchase = await f.PurchaseAsync(buyer: b, holder: b);
        var subject = NewSubject();
        var (_, accountToken, accountId) = await SignedInAsync(tokenB, "google", subject);
        var nonce = FakeIdTokenVerifier.NewRawNonce();

        using var response = await f.AccountCallAsync(HttpMethod.Post, "/v1/accounts/signout", tokenB, accountToken, nonce);

        var body = await JsonOf(response);
        Assert.True(response.Headers.Contains("Zaghlol-Signature"));
        Assert.Equal(nonce, body.GetProperty("timeNonce").GetString());
        Assert.Equal("paused", AccountsHostFixture.StatusOf(body.GetProperty("entitlement").GetProperty("token").GetString()!));
        Assert.Equal(b, (await f.SeatAsync(purchase)).Holder);
        Assert.Equal(accountId, (await f.PurchaseLinkAsync(purchase)).Account);
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i", ("i", b)));
        using var again = await f.AccountCallAsync(HttpMethod.Post, "/v1/accounts/signout", tokenB, accountToken);
        await ProblemAssert.AssertAsync(again, HttpStatusCode.Unauthorized, "ACCOUNT_TOKEN_EXPIRED");

        // Signing in again on the same phone: it still holds the seat, so nothing moves or is refused (EC-73).
        var (back, _, _) = await SignedInAsync(tokenB, "google", subject);
        Assert.False(back.GetProperty("moveRefused").GetBoolean());
        Assert.False(back.GetProperty("movedFromOtherPhone").GetBoolean());
        Assert.Equal("active", AccountsHostFixture.StatusOf(back.GetProperty("entitlement").GetProperty("token").GetString()!));
    }

    [Fact]
    public async Task EC46_AnInstallLinkedToAnotherAccountGets409UntilReplaceLinkConfirms()
    {
        var (b, tokenB) = await f.NewInstallOfAsync("android");
        var (_, _, first) = await SignedInAsync(tokenB, "google", NewSubject());
        var (raw, id) = f.Credential(NewSubject());
        using var conflict = await f.SignInAsync(tokenB, AccountsHostFixture.SignInBody("google", id, raw));
        await ProblemAssert.AssertAsync(conflict, HttpStatusCode.Conflict, "INSTALL_LINKED_TO_OTHER_ACCOUNT");
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i AND account_id <> @a", ("i", b), ("a", first)));

        var (raw2, id2) = f.Credential(NewSubject());
        using var replaced = await f.SignInAsync(tokenB, AccountsHostFixture.SignInBody("google", id2, raw2, replaceLink: true));

        var body = await JsonOf(replaced);
        var second = body.GetProperty("accountId").GetGuid();
        Assert.NotEqual(first, second);
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i", ("i", b)));
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i AND account_id = @a", ("i", b), ("a", second)));
    }

    [Fact]
    public async Task R4_1_AMismatchingElementZeroIs400SeatKeyMismatch_NothingIsLinked_TheReplayRowStays_AndPlainSignInRegistersTheKeyUntrusted()
    {
        var (i, token) = await f.NewInstallOfAsync("ios");
        var install = InstallId.FromGuid(i);
        using var k1 = new SeatKeyTestSigner();
        using var k2 = new SeatKeyTestSigner();

        // R5-2: the first valid element 0 is registered, untrusted.
        var (raw1, id1) = f.Credential(NewSubject());
        using var first = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", id1, raw1, seatKeys: Keys(SeatChallenge.ForSignIn(raw1), install, k1)));
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.installs WHERE id = @i AND seat_key_hash IS NOT NULL AND seat_key_trusted = false", ("i", i)));

        // Another element 0 on a new subject: rejected before step 1.
        var subject = NewSubject();
        var (raw2, id2) = f.Credential(subject);
        using var mismatch = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", id2, raw2, seatKeys: Keys(SeatChallenge.ForSignIn(raw2), install, k2)));

        await ProblemAssert.AssertAsync(mismatch, HttpStatusCode.BadRequest, "SEAT_KEY_MISMATCH");
        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.accounts WHERE provider_subject = @s", ("s", subject)));
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i", ("i", i)));
        var claimHash = SHA256.HashData(Encoding.ASCII.GetBytes(FakeIdTokenVerifier.Hashed(raw2)));
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.replay_guard WHERE key_hash = @h", ("h", claimHash)));

        // The retry without seatKeys, with a fresh token and nonce, links (replacing the first account, EC-46).
        var (raw3, id3) = f.Credential(subject);
        using var retry = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", id3, raw3, replaceLink: true));
        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
        Assert.Equal(1, await f.CountAsync("SELECT count(*) FROM zaghlol.accounts WHERE provider_subject = @s", ("s", subject)));
    }

    [Fact]
    public async Task OverCapSameIPhoneSignIn_ATrustedSeatKeyPassesAndRestartsTheWindow_AnUntrustedOneInsideACooldownIsRefusedWithRestoreSuggested()
    {
        // Trusted seat key (R5-2 sets it only through restore; here the install's flag is set the way a restore would).
        var trusted = await OverCapAsync(trustedKey: true);
        Assert.False(trusted.Body.GetProperty("moveRefused").GetBoolean());
        Assert.False(trusted.Body.GetProperty("restoreSuggested").GetBoolean());
        Assert.Equal(trusted.NewInstall, trusted.Seat.Holder);
        Assert.True(trusted.Seat.NextMoveAt > f.Clock.Now.AddDays(29), "the window restarts");
        Assert.Contains("seat_rebind_over_cap:signin", trusted.Events);
        Assert.Contains(f.Telemetry.Alerts, p => p == trusted.Purchase);

        // Untrusted seat key inside a cooldown: an ordinary move, so it is refused; the app is told to offer Restore (R5-3(b)).
        var untrusted = await OverCapAsync(trustedKey: false);
        Assert.True(untrusted.Body.GetProperty("moveRefused").GetBoolean());
        Assert.True(untrusted.Body.GetProperty("restoreSuggested").GetBoolean());
        Assert.NotEqual(untrusted.NewInstall, untrusted.Seat.Holder);
        Assert.Contains("seat_rebind_over_cap:signin", untrusted.Events);
        Assert.Contains((untrusted.NewInstall, "signin"), untrusted.Claimants);
        Assert.Contains(f.Telemetry.Alerts, p => p == untrusted.Purchase);
    }

    private async Task<(JsonElement Body, Guid NewInstall, Guid Purchase, (Guid? Holder, DateTimeOffset? NextMoveAt, bool KeyTrusted, bool HasKey) Seat, List<string> Events, List<(Guid Install, string Channel)> Claimants)>
        OverCapAsync(bool trustedKey)
    {
        var (oldInstall, oldToken) = await f.NewInstallOfAsync("ios");
        var (newInstall, newToken) = await f.NewInstallOfAsync("ios");
        var purchase = await f.PurchaseAsync(buyer: oldInstall, holder: oldInstall);
        var subject = NewSubject();
        using var oldKey = new SeatKeyTestSigner();
        using var newKey = new SeatKeyTestSigner();
        var old = InstallId.FromGuid(oldInstall);

        // The earlier install on this iPhone signs in (attach, its key is stored on the seat) ...
        await SignInWithKeysAsync(oldToken, subject, old, oldKey);
        if (trustedKey)
        {
            await f.ExecuteAsync("UPDATE zaghlol.installs SET seat_key_trusted = true WHERE id = @i AND seat_key_hash IS NOT NULL", ("i", oldInstall));
            await SignInWithKeysAsync(oldToken, subject, old, oldKey);
        }

        Assert.Equal(trustedKey, (await f.SeatAsync(purchase)).KeyTrusted);

        // ... the D-63 cap is reached and, for the untrusted case, a cooldown runs.
        await f.ExecuteAsync(
            """
            UPDATE zaghlol.purchase_seats
            SET recent_rebinds = ARRAY[now() - interval '1 day', now() - interval '2 days']::timestamptz[],
                next_move_at = CASE WHEN @cooldown THEN date_trunc('hour', now() + interval '10 days') ELSE NULL END,
                last_moved_at = CASE WHEN @cooldown THEN date_trunc('hour', now() + interval '10 days') - interval '30 days' ELSE NULL END
            WHERE purchase_id = @p
            """,
            ("cooldown", !trustedKey),
            ("p", purchase));

        // The reinstalled iPhone: its new key is element 0, the old install's key is element 1.
        var install = InstallId.FromGuid(newInstall);
        var (raw, idToken) = f.Credential(subject);
        var challenge = SeatChallenge.ForSignIn(raw);
        using var response = await f.SignInAsync(
            newToken,
            AccountsHostFixture.SignInBody(
                "google",
                idToken,
                raw,
                seatKeys: [(newKey.Prove(challenge, install).PublicKey, newKey.Prove(challenge, install).Signature), (oldKey.Prove(challenge, install).PublicKey, oldKey.Prove(challenge, install).Signature)]));
        var body = await JsonOf(response);
        return (body, newInstall, purchase, await f.SeatAsync(purchase), await f.EventsAsync(purchase), await f.ClaimantsAsync(purchase));
    }

    private async Task SignInWithKeysAsync(string token, string subject, InstallId install, SeatKeyTestSigner key)
    {
        var (raw, idToken) = f.Credential(subject);
        using var response = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", idToken, raw, seatKeys: Keys(SeatChallenge.ForSignIn(raw), install, key)));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private static (string PublicKey, string Signature)[] Keys(SeatChallenge challenge, InstallId install, params SeatKeyTestSigner[] signers) =>
        [.. signers.Select(s => s.Prove(challenge, install)).Select(p => (p.PublicKey, p.Signature))];

    [Fact]
    public async Task ShapeAndPlatformRules_AreRefusedBeforeAnyTokenWork()
    {
        var (_, android) = await f.NewInstallOfAsync("android");
        var (_, ios) = await f.NewInstallOfAsync("ios");
        var (raw, idToken) = f.Credential(NewSubject());
        var calls = f.Tokens.Calls;
        using var signer = new SeatKeyTestSigner();
        var challenge = SeatChallenge.ForSignIn(raw);
        var androidId = InstallId.FromGuid(Guid.NewGuid());

        // seatKeys from an Android install.
        using var androidKeys = await f.SignInAsync(android, AccountsHostFixture.SignInBody("google", idToken, raw, seatKeys: Keys(challenge, androidId, signer)));
        await ProblemAssert.AssertAsync(androidKeys, HttpStatusCode.BadRequest, "VALIDATION_FAILED");

        using var badProvider = await f.SignInAsync(ios, AccountsHostFixture.SignInBody("facebook", idToken, raw));
        await ProblemAssert.AssertAsync(badProvider, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        using var shortNonce = await f.SignInAsync(ios, AccountsHostFixture.SignInBody("google", idToken, "short"));
        await ProblemAssert.AssertAsync(shortNonce, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        using var notAJws = await f.SignInAsync(ios, AccountsHostFixture.SignInBody("google", "not a token", raw));
        await ProblemAssert.AssertAsync(notAJws, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        using var googleCode = await f.SignInAsync(ios, AccountsHostFixture.SignInBody("google", idToken, raw, "abc"));
        await ProblemAssert.AssertAsync(googleCode, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        using var unknown = await f.SignInAsync(ios, AccountsHostFixture.SignInBody("google", idToken, raw).Replace("{", "{\"balance\":\"1\",", StringComparison.Ordinal));
        await ProblemAssert.AssertAsync(unknown, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
        using var noKey = await f.SendAsync(HttpMethod.Post, "/v1/accounts/signin", ios, AccountsHostFixture.SignInBody("google", idToken, raw));
        await ProblemAssert.AssertAsync(noKey, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(calls, f.Tokens.Calls);
    }

    [Fact]
    public async Task ForgedOrUnavailableIdTokensAre422And503_AndNothingIsLinked()
    {
        var (i, token) = await f.NewInstallOfAsync("android");
        var raw = FakeIdTokenVerifier.NewRawNonce();

        using var forged = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", "aaa.bbb.ccc", raw));
        await ProblemAssert.AssertAsync(forged, HttpStatusCode.UnprocessableEntity, "ID_TOKEN_INVALID");

        f.Tokens.Down = true;
        try
        {
            var (raw2, id2) = f.Credential(NewSubject());
            using var down = await f.SignInAsync(token, AccountsHostFixture.SignInBody("google", id2, raw2));
            await ProblemAssert.AssertAsync(down, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE");
            Assert.NotNull(down.Headers.RetryAfter);
        }
        finally
        {
            f.Tokens.Down = false;
        }

        Assert.Equal(0, await f.CountAsync("SELECT count(*) FROM zaghlol.account_installs WHERE install_id = @i", ("i", i)));
    }

    [Fact]
    public async Task NoIdTokenNonceCodeOrAccountTokenIsEverLogged()
    {
        var (_, token) = await f.NewInstallOfAsync("ios");
        var subject = NewSubject();
        var (raw, idToken) = f.Credential(subject, email: "person@example.test");
        var code = "code-" + Guid.NewGuid().ToString("N");
        using var response = await f.SignInAsync(token, AccountsHostFixture.SignInBody("apple", idToken, raw, code));
        var body = await JsonOf(response);
        var accountToken = body.GetProperty("accountToken").GetString()!;
        using var signOut = await f.AccountCallAsync(HttpMethod.Post, "/v1/accounts/signout", token, accountToken);
        using var forged = await f.SignInAsync(token, AccountsHostFixture.SignInBody("apple", "aaa.SECRETPART.ccc", FakeIdTokenVerifier.NewRawNonce()));

        var logs = string.Join('\n', f.LogSink.Entries);
        foreach (var secret in new[] { idToken.Split('.')[1], raw, code, accountToken, accountToken.Split('.')[1], subject, "person@example.test", "SECRETPART", token })
        {
            Assert.DoesNotContain(secret, logs, StringComparison.Ordinal);
        }
    }
}
