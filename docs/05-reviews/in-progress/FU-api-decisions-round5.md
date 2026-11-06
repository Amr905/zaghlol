# FU-api-decisions: Security and Privacy Review

**Reviewer:** security-privacy-reviewer · **Branch:** `task/FU-api-decisions` @ `d296a7f`
**Scope:** round 5 is `git diff 9ae53aa origin/fuapi -- docs/03-technical backend`. The cumulative design is `git diff e47127e...origin/fuapi`. Checked against SRS v1.7 on main: D-48 (v1.7 addendum), D-62…D-65, NFR-SEC-08, BR-SYNC-03 and NFR-PRIV-07 as amended.
**Current verdict: CHANGES_REQUESTED.** One major is blocking: **R5-1**. The app never checks that an entitlement token was issued to *its own* install, so on stock iOS a user-CA proxy can hand the holder's signed token to any number of phones. The fix is one rule plus one unit test. If that text lands (with the R5-2 wording correction), I can approve from a targeted delta check without another full round. Everything else in this round is minor or info, and can be accepted as a documented residual with an owner task.

---

## History

**Round 1 (2026-11-05): CHANGES_REQUESTED.**
- 2 blockers: a shared restore token gave Gold to unlimited installs, and the Apple sign-in nonce wasn't checked.
- 4 majors, plus minors. Findings 2–8 and 10–12 were fixed at `8fe1251`. Findings 1 and 9 led to D-45…D-47 and ADR-012 Part B.

**Round 2 (2026-11-05): CHANGES_REQUESTED.**
- 1 blocker: R2-1, the attestation was bound to the body and not to the install.
- 3 majors and minors (R2-2…R2-10). The PO replaced the 3-seat model with D-52…D-54 (SRS v1.5).

**Round 3 (2026-11-06): CHANGES_REQUESTED.**
- All round-2 findings were resolved in the design.
- New majors: R3-1 (the offline bound depended on the wall clock) and R3-2 (support acted on insufficient proof). Minors R3-3…R3-9, info R3-10.
- The PO answered with D-55…D-61 and NFR-SEC-08 (SRS v1.6).

**Round 4 (2026-11-06): CHANGES_REQUESTED.**
- Majors:
  - R4-1: the seat-key proof could be relayed from one jailbroken iPhone, giving unlimited cooldown-free rebinds.
  - R4-2: any newer signed `serverTime` re-anchored trusted time and cleared `tampered`.
- Minors: R4-3 (reboot rules), R4-4 (the plan-change account rule), R4-5 (`seatKeys` linkability).
- Info: R4-6 (`amr`/`acr`), R4-7 (single-agent support), R4-8 (retention notice).
- The PO answered with D-62…D-65 (SRS v1.7). D-62 explicitly accepts linkability in transit.

---

## Round 5 (2026-11-06)

### Method and dependence on CI
**I reviewed by reading only.** GitHub Actions is still blocked by billing (BLK-05).

**What I checked myself:**
- I recomputed `backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json` with an independent Python script (`cryptography`, P-256, run with `-I`):
  - all 4 `valid` vectors rebuild `jcs` and `bodyHashHex`;
  - all 3 iOS vectors rebuild `seatKeysDigestHex` and `clientDataHashHex`, including SHA-256 of the empty string when there are no keys;
  - all 3 seat-key signatures in `ios-seat-keys-not-hashed` and `ios-two-seat-keys` verify over `"zaghlol-seat-v1"‖0‖"restore"‖0‖installId‖0‖bodyHash`.
- I parsed `zaghlol-v1.yaml` (PyYAML). All six anchoring operations (sync, verifyPurchase, restorePurchases, getEntitlement, signIn, signOut) have a signed 200 with a `timeNonce` → `TimeNonceEcho` property.
- The `TimeNonce` pattern `^[A-Za-z0-9_-]{21}[AQgw]$` is the correct canonical form for exactly 16 bytes.
- `SupportNotice`, `accountRequired` and `restoreSuggested` are present. `SEAT_KEY_MISMATCH` is in `ProblemCode`.

**These conclusions depend on CI and are not verified:**
- The new `IosClientDataHashCoversTheSeatPublicKeysInOrder` test compiles and passes on net10.0 with `TreatWarningsAsErrors`. It uses `Base64Url.DecodeFromChars`, `Convert.ToHexStringLower`, a byte collection expression containing a literal `0`, and LINQ `Reverse()` on `JsonArray`.
- The new `TimeNonceIsSentAndEchoedExactlyOnAnchoringOperations` test passes. It relies on the existing `Spec.Resolve` and `ParameterRefs` helpers.
- The adding of `signOut` to `SignedOperations`, and the removal of the `InstallExists` and `InstallLinkedToOtherAccount` responses, leave no dangling `$ref` and pass the existing T-006 contract tests.
- These carry over from round 4 and still wait on their first green run: `SeatProofVectorTests`, `DuplicateVectorsAreRejectedByTheFrameworkStrictOption` (`AllowDuplicateProperties`, .NET 10), and the `None Update` copy of the vector files.
- R2-6, R3-8 and the R4-1(3) vectors are therefore **resolved in spec, CI pending**.

### Resolution of round-4 findings

| ID | Finding | Status | Evidence / residual |
|---|---|---|---|
| R4-1 (major) | Seat-key proof relay | **Resolved for restore. Bounded for sign-in, within the D-63 cap.** | (1) Element 0 is registered per install, set once (`backend-api.md:267-269`, `backend-schema.md:50-57`), with `SEAT_KEY_MISMATCH` on any other key. (2) A rebind needs a match at position 1 or later, and the seat then follows the caller's registered key (`:275-281`). (3) The cap is `recent_rebinds` ≤ 2, with a CHECK constraint (`backend-schema.md` purchase_seats). (4) App Attest `clientDataHash` covers the public keys in order (`:210`; vectors verified above). A stock iPhone behind a proxy can no longer insert a relayed key on restore. (5) The oracle residual is documented (ADR-012:205-208). **New gaps:** R5-2 (on stock iOS, verify and sign-in registrations can be proxied, so a key marked "trusted" need not be a Secure Enclave key) and R5-4 (trust flag on a support move). |
| R4-2 (major) | Replayed signed time | **Resolved** | A 128-bit CSPRNG `Zaghlol-Time-Nonce` is sent on the 6 anchoring operations and echoed in the signed body (`backend-api.md:17-19`). The app keeps a single outstanding nonce, in memory only, accepted within 60 s on the same boot (`:320`, `:329-333`). Every other signed time is raise-only. An `Idempotency-Key` replay is raise-only. The throttle answer carries the echo (`:126`). The required tests cover another install's body, a withheld response, a double use and an idempotent replay (`:354-356`). Another install that copies the victim's nonce gets only the *current* signed time, which is harmless. Its token is a separate problem: see R5-1. D-48 v1.7 classifies the nonce. |
| R4-3 (minor) | Reboot rules | **Resolved** | New `lb` state with the invariant `lb ≤ hw`. The tamper test runs on `lb + lower`. The 6 h charge goes to `hw` only. On iOS, when the boot reference shifts with `m ≥ mono`, the charge is `max(m − mono, 6 h)` (`backend-api.md:313-341`, ADR-012:217-219). Tests were added (`:352-353`). Small trade-off, accepted: on a real iOS reboot whose uptime has already passed `mono`, the charge is up to `mono` less than in round 4. That only widens the accepted "undetected iOS reboot" residual, by the time the app wasn't running. |
| R4-4 (minor) | Plan change ignored the account rule | **Resolved** | The account rule is checked first. Without a matching account token the seat stays, the payer becomes a claimant, and the response carries `accountRequired: true`. Payment is never blocked (`backend-api.md:174`, ADR-012:91, OpenAPI `accountRequired`). The claimant set and the support account rule are consistent (`:548`, `:551`). |
| R4-5 (minor, privacy) | `seatKeys` linkability; wrong ADR claim | **Accepted by the PO (D-62). Docs corrected.** | The ADR-012:209 claim is corrected. `backend-api.md:289` and `security-model.md` §2a item 1 state the in-transit linkability. Not re-raised. Doc nit carried in R5-9 (an extra at-rest hash and verify-time sending versus the D-62 / BR-SYNC-03 wording). |
| R4-6 (info) | `amr`/`acr` enforceability | **Resolved** | The IdP's conditional access is the control. The API checks `acrs` only where T-136 confirms the IdP emits it, and is otherwise advisory with a diag counter (`backend-api.md:54`, ADR-012:162, OpenAPI `operatorOidc`). |
| R4-7 (info) | Single-agent support residual | **Addressed per D-64 / D-65(b)** | (1) The dispute freeze is checked before the ownership call and audited as `dispute_frozen` (`backend-api.md:541-546`). (2) `supportNotice` is sent once, to the buying install only (`:127`, `:557`). (3) The runbook prefers the buying install via `isBuyingInstall` (`:548`, `:524`). (4) A fallback exists for when `orders.get` is unavailable (`:537`). Residuals: R5-5 (freeze), R5-7 (notice delivery), R5-8 (deprecated Play field). |
| R4-8 (info) | Retention notice for `device_key_hash` | **Resolved** | `security-model.md` §2a items 1–4 and deletion step 4. T-137 owns the copy (ADR-012:247). |

### The sign-in deviation from D-65(a): opinion for the PO

**Is the gate necessary? Yes.**
- **The relevant attacker is a stock iPhone behind a user-CA proxy, not a modified app.** A modified app can just show Gold locally, so the server's seat rules only restrain unmodified apps. iOS has no system-CA-only switch and no pinning (ADR-012:132), so a proxy can rewrite every unattested body.
- **What a proxy can do on sign-in:**
  - The sign-in body has no App Attest, and the proxy can see everything a seat-key signature covers: `installId` (header), the raw `nonce` (body), and therefore the challenge.
  - On a sharer's first sign-in, it can replace `seatKeys` with **software keys**. Element 0 is then registered to a key the attacker exports.
- **Without the gate:** every over-cap sign-in match is "never refused", and an over-cap rebind ignores the cooldown (restarting the window costs a rebind nothing). Two or more stock iPhones signed in with shared account credentials, for example a throwaway Google account created only for Zaghlol, could pass Gold back and forth **without limit**. D-52 would fail for every account-linked purchase.
- **With the gate:** an over-cap sign-in needs `device_key_trusted`. The key a sign-in rebind leaves on the seat is untrusted, so a chain of sign-ins gets at most one over-cap hop and then falls back to the cooldown. The documented bound (`backend-api.md:288`, `:418`) is correct, *provided* "trusted" can't be manufactured. R5-2 shows that it partly can, through verify, but even then only once per chain.

**Is the owner truly never locked out? No. The claim at `backend-api.md:284` and ADR-012:203 is too strong.**
- The fallback is "`restoreSuggested` → Restore". Restore needs a StoreKit `signedTransaction` for the purchase on *this* iPhone.
- It doesn't exist for:
  - **Gold bought on Google Play** and carried to the iPhone by sign-in, which is exactly what FR-GOLD-07 sign-in is for;
  - an App Store purchase made under a **different Apple ID** from the one on this iPhone.
- In both cases every seat key on that iPhone came from sign-in, so it is **never** trusted. This holds even for the first install, which got the seat by an ordinary sign-in move.
- A third reinstall within 30 days, while the window runs, then gives `moveRefused`. The owner waits up to 30 days or goes to support, and support can itself be blocked by a dispute freeze (R5-5). The case is rare but real: see R5-3.

**Recommendation to the PO:**
- **Accept the deviation.** The gate is necessary.
- **Pair it with one of the following:**
  - **(a) Preferred.** Add an *optional* App Attest assertion to iOS sign-in: `clientDataHash = SHA-256("zaghlol-signin-attest-v1"‖0‖installId‖SHA-256(nonce)‖seatKeysDigest)`. When it is present and valid, the registered key counts as trusted, and the over-cap sign-in takes the full D-65(a) never-refused path. Honest apps always attest, so the deviation then affects only stripped (proxied) requests. This extends D-45 / FR-GOLD-09 attestation to iOS sign-in. It is the same data class, but it needs a one-line PO amendment.
  - **(b)** Record the cross-store / other-Apple-ID case as an accepted residual, with support as the path and a note in the D-65(a) text.

### New findings

#### R5-1 (Major, blocking): the app doesn't bind an entitlement token to its own install, so a proxy on stock iOS can give the holder's token to any number of phones
**Where:**
- `backend-api.md:307-310` (*App rules*): it checks the signature, `status`, trusted time and `acct`, but **not `sub`**.
- `backend-api.md:294`: the token's `sub` is `<installId>`.
- `backend-api.md:17`: the signature binds the body only, "not … to whom".
- ADR-012:132: "everything it could profit from rewriting is covered by a proof". This omits the entitlement token itself.
- T-144 (`docs/04-tasks/tasks/T-144.md:22`, `:29`): no `sub` check in scope or in the acceptance criteria.
- The gap dates from round 1. The earlier rounds, mine included, missed it.

**Exploit (stock iOS, no jailbreak):**
1. H holds the seat. Its traffic goes through the group's mitmproxy (user-installed CA, which iOS honours, and no pinning). The proxy records H's bearer `installToken`, or just H's signed `GET /v1/entitlement` bodies.
2. A, B, C… run the genuine app through the same proxy. On each anchoring call the proxy answers with a body it fetched *as H*.
   - Since R4-2, the proxy can even copy the victim's `Zaghlol-Time-Nonce` into H's request, so the echo is "fresh". The R4-2 design itself is correct; this is not a fault in it.
3. Each app sees a validly signed token with `status: active` and an `exp` in trusted time, and grants Gold.
4. Tokens live up to 7 days, and the proxy refreshes them on demand. **Any number of concurrent holders, indefinitely.**

**Effect:**
- D-52, FR-GOLD-08 and BR-GOLD-07 fail completely on iOS. The same applies to the `acct` check, because H's account token can be copied too and its `iid` isn't checked by the app.
- Android is safe only because of the system-CA-only config (needs root, R-19).

**Required change** (§4.3 *App rules*, T-144, ADR-012 (d) line 132):
- The app honours an entitlement token only if `sub` equals **its own current install ID**, and an account token only if `iid` equals its own install ID.
- Otherwise it ignores the token. The body's time may still raise-only, but it never re-anchors from a body whose token fails this check.
- A `sub` mismatch increments a diag counter only.
- After a re-registration (`INSTALL_TOKEN_INVALID` → new install ID) the cached token is dropped.
- Add T-144 unit tests: "a validly signed token for another install grants nothing" and "an account token with a foreign `iid` is not honoured".
- Correct ADR-012:132 to list the `sub` binding as the control for the token.

#### R5-2 (Minor): "trusted" seat keys and element-0 registration can be set by a proxy through verify or sign-in, so on stock iOS the sign-in rebind budget needs no jailbreak
**Where:**
- `backend-api.md:167`: verify registers its `seatKeys` element as the install's key.
- `backend-api.md:270`: a verify counts as "a request whose proof binds it to this install".
- `backend-schema.md:55`.
- ADR-012:202-203: "an honest seat key comes from the buying install's verify".
- ADR-012:208 and `security-model.md:16`: "relaying … from a jailbroken iPhone".

**Issue:**
- The store binding (`appAccountToken` = HMAC(installId)) proves that this install made the *payment*. It doesn't prove that the `seatKeys` element came from its Secure Enclave.
- Verify has no App Attest, and the proxy knows `installId` and `SHA-256(signedTransaction)`.

**Exploit:** a buyer who shares Gold, with his own phone behind a proxy at purchase time.
1. The proxy swaps the verify `seatKeys` for a software key `K_sw`. That key registers on the buying install **as trusted**, and the seat stores `HMAC(pid‖K_sw)`, trusted.
2. Friends on stock iPhones behind proxies sign in with the shared account and send `[K_Fi_sw, sig_Ksw]`. They get 2 cooldown-free rebinds plus 1 over-cap hop (from the trusted seat) per 30 days. Then they fall back to the cooldown.

**Effect:**
- The *numbers* match the documented bound and D-63. What is wrong is the *precondition*: no jailbreak or Secure Enclave oracle is needed, only a proxy, and "trusted" doesn't mean "Secure Enclave key".
- An install whose registration was proxied can never use restore rebinds afterwards: the genuine app's Secure Enclave key gets `SEAT_KEY_MISMATCH`. That damage falls only on the attacker.

**Required change** (T-132, ADR-012 (g), `security-model.md:16`):
- Set `seat_key_trusted` **only** from an App Attest-covered request: restore now, and the attested sign-in if the PO takes recommendation (a).
- Keep verify registration, because it is functionally needed so that a reinstall straight after purchase is recognised, but leave it untrusted.
- Correct ADR-012:208 and `security-model.md:16`: on stock iOS a proxy can drive the sign-in rebinds (bounded by the cap). The jailbreak / oracle precondition applies only to restore.

**Honest-user impact of the fix:** an iPhone buyer who never restored has an untrusted key. A third reinstall then gets `restoreSuggested`, and restore works for an App Store purchase on the same Apple ID. So no new lock-out beyond R5-3.

#### R5-3 (Minor): the over-cap sign-in fallback (Restore) doesn't exist for Play-bought or other-Apple-ID Gold, so the holding iPhone can be refused for up to 30 days
**Where:** `backend-api.md:284`, `:416`; ADR-012:203 ("the owner is never locked out"); D-65(a).

**Path:**
1. Gold is bought on Android, account-linked, and moved to an iPhone by sign-in. The seat key is registered at sign-in, so it is untrusted.
2. The owner reinstalls the app on that iPhone 3 times within 30 days. That is not unusual while troubleshooting, and the first move to the iPhone itself started the window.
3. The third reinstall's sign-in gets `moveRefused` and `restoreSuggested`. Restore has no iOS transaction to send.
4. The owner waits up to 30 days, or goes to support (unless frozen, R5-5).

**Required change** (owner T-132 / T-135 / T-147):
- Either take recommendation (a) above (optional App Attest on iOS sign-in; a PO decision),
- or replace "never locked out" with the explicit residual. In that case, have the app show the support path (not Restore) when the purchase isn't an App Store purchase visible to this iPhone. The app knows this from StoreKit.

#### R5-4 (Minor): a support move copies the claimant's key hash but doesn't say what happens to `device_key_trusted`
**Where:**
- `backend-api.md:562`: `device_key_hash` takes the claimant entry's hash, or `NULL`.
- `backend-api.md:273` and `backend-schema.md:156`: the flag is "copied from the holder's `installs.seat_key_trusted` when `device_key_hash` is written".
- `seat_claimants` stores no trust flag.

**Risk:** if an implementation keeps the previous holder's `true`, a claimant whose key was registered by a proxied sign-in inherits a trusted seat. That gives one extra over-cap sign-in hop after a social-engineered support move.

**Required change** (T-132 / T-136): on a support move, set `device_key_trusted` from the target install's `seat_key_trusted` (false when the hash is `NULL`, or on a move back). Add one test.

#### R5-5 (Minor, PO residual): the dispute freeze doesn't stop correction ping-pong, and can strand an owner who loses the phone just after a correction
**Where:** `backend-api.md:541-546`, `:550`; ADR-012:153; D-64 / D-65(b).

**(a) Ping-pong continues through corrections:**
- Corrections stay allowed and each one restarts the freeze.
- A correction's target is the `from_install` of *any* `support_seat_move` row for the purchase from the last year, correction rows included.
- So two parties who both hold the order ID can keep asking different agents for "corrections".
- What contains it: the >2-moves-in-90-days alert and lead review. This is the PO's single-agent choice, and I accept it.

**(b) No path for ≤ 30 days:**
- After a correction, the window has also restarted (a correction move sets `next_move_at`).
- An owner whose phone is then lost or broken has neither self-service (cooldown) nor support (freeze) for up to 30 days.
- "Goes to a support lead through the ticket" (`:546`) names a person but no capability: no endpoint lets the lead act.
- **Abuse variant:** someone with store-account access gets a wrongful support move, and the correction that follows freezes support for the owner.

**Options for the PO:**
- (i) Accept (b) as a residual and state it in the D-64 copy for support.
- (ii) Add a narrow `support_lead` action, `purchase:unfreeze`. It is audited, it must be done by a different operator from the last correction's agent, and it doesn't move anything. This isn't a second approver on ordinary actions.
- Owner: T-136 / T-137.

#### R5-6 (Info): `SEAT_KEY_MISMATCH` handling details
**Where:** `backend-api.md:269`, `:415`, `:592`; `platform-channels.md:241`.

- **As an oracle: no finding.** The check compares element 0 only with the *calling* install's own registered key, and needs that install's bearer token. It reveals nothing about other installs or seats. Rebind outcomes already reveal seat matches by design.
- **Order on restore:** say whether the element-0 check runs before App Attest verification, so the counter isn't consumed. "Nothing is written" otherwise contradicts the counter update. Either way is safe, because the assertion is install-bound. The point is consistency for T-132.
- **Forced downgrade:** error bodies are unsigned, so a proxy can inject a fake `400 SEAT_KEY_MISMATCH` to make the app retry without keys. That only hurts the proxy's own user, so it is out of scope.
- **App behaviour:** after one confirmed mismatch, the app should persist "own seat key unusable for this install" and stop sending `seatKeys`. Otherwise every sign-in costs a 400 plus a second Apple/Google prompt.
- Owner: T-145 / T-147 and the app seat-key task.

#### R5-7 (Info): `supportNotice` is cleared when sent, not when delivered
**Where:** `backend-api.md:127`.

- **Privacy: no leak.** The notice carries no account data, goes only to `purchases.install_id`, and never to the throttle answer or to other installs.
- **Delivery:** the flag clears when the response is built. A lost response or an app crash before display loses the protective notice for good.
- **Suggestion:** clear it on the *next* authenticated request from that install after delivery (an implicit acknowledgement), or keep re-sending it until the app sends an acknowledgement field. The second option is a BR-SYNC-03 "app version"-class boolean that needs a note.
- Owner: T-136 / T-144.

#### R5-8 (Info): the Play ownership-check fallback uses a deprecated field
**Where:** `backend-api.md:537`; ADR-012:145.
- `SubscriptionPurchaseV2.latestOrderId` is deprecated. Google says to use `lineItems[].latestSuccessfulOrderId` instead.
- Owner: T-130. Fix the field name when the fallback is implemented.

#### R5-9 (Info, doc correctness)
1. **Per-install hash at rest.** D-62, BR-SYNC-03 and NFR-PRIV-07 say that at rest the server keeps "a keyed hash **per purchase**". The design adds `installs.seat_key_hash`, a per-install keyed hash (`backend-schema.md:50-57`). It is keyed with the install ID, can't be joined across installs, and is deleted with the install, so it adds no linkability. `security-model.md` §2a already discloses it. Ask the PO to add it to the SRS wording at the next revision.
2. **Verify sends `seatKeys`.** BR-SYNC-03 lists `seatKeys` "with each restore and sign-in". The design also sends element 0 on **verify** (`backend-api.md:142-144`, `:167`). That is needed (R5-2), so the SRS wording should name verify too.
3. **Stale audit text.** ADR-012:160 lists `ownership_outcome: pass|fail|unavailable` without `not_run`, unlike `backend-api.md:572` and the schema.

### New attack surface checked with no finding
- **Time nonce on the throttle answer:** it is signed and carries the caller's echo, so a throttle answer harvested by another install is raise-only. An echo obtained by copying the victim's nonce into another install's request gives only the current time, which is harmless once R5-1 rejects that install's token. A response slower than 60 s (a slow restore upstream) only means no re-anchor that time; it fails closed.
- **`lb` abuse:**
  - `lb` moves down only through a fresh echo, and forward through the wall clock or the monotonic clock.
  - Pushing it into the future makes later honest corrections set `tampered`. That fails closed, and only for the device's own user.
  - `hw = max(hw + charge, lb)` keeps `lb ≤ hw`.
  - Gold is decided on `hw`, never on `lb`.
- **`device_key_trusted` downgrade:** an outsider can't lower the trust of an owner's seat without first becoming the holder through a move (the flag is copied only when an install becomes or stays the holder), and the install flag only ever goes from false to true. The gaps are covered under R5-2 and R5-4.
- **Restore relay:**
  - The App Attest `clientDataHash` now covers the keys and their order (vectors verified).
  - Element 0 is registered after attestation, so restore registrations are trustworthy on a stock phone.
  - Two jailbroken iPhones that both pass App Attest can still swap Gold by restore past the cap. A jailbroken participant can patch the app to show Gold anyway, so the server can't do better. This is accepted under R-19.
- **Retry without `seatKeys`:** it is an ordinary request and can't rebind. The `replay_guard` commit is unchanged, so a retried sign-in needs a fresh ID token and nonce.
- **R4-4 claimant path:** a payer held back by `accountRequired` can be a support target only if linked to the account (`backend-api.md:551`).
- **Freeze bypass:** the freeze check runs before the ownership call, so a frozen purchase costs no store call and leaks nothing about the order. The refusal is audited and alerted.

### BR-SYNC-03 / egress check
- **New data from the app:** only the `Zaghlol-Time-Nonce` (random, no device data; classified by D-48 v1.7) and, optionally, the R5-3(a) sign-in assertion if the PO approves it (the same class as D-45).
- **`seatKeys`:** per D-62, with the doc wording points in R5-9.
- **Never sent by the app:** the order ID (still never stored or logged).
- **Server-to-app only:** `supportNotice`, `accountRequired` and `restoreSuggested`.
- **Logging:** nothing new is logged. The nonce is never stored, logged or traced, and the redacting logger drops `seatKeys`.

### Regression check
- **No regressions** against the round 1–4 fixes:
  - the Apple and Google nonces are still required;
  - strict JSON and the duplicate-property vectors are unchanged;
  - admin DTOs have `additionalProperties: false`;
  - `ticketRef` is still a regex;
  - no credentials go in query strings;
  - alerts carry the purchase UUID only;
  - store binding keeps priority on verify;
  - Android stays system-CA-only;
  - the idempotency scoping is unchanged.
- **Removed OpenAPI responses:** `InstallExists` and `InstallLinkedToOtherAccount` are gone; the T-006 tests must confirm no dangling refs (CI pending).

---

## Verdict
**CHANGES_REQUESTED, for R5-1 only.**
- **R5-1 is blocking.** Before approval the design must say that the app honours an entitlement token only when `sub` equals its own install ID, and an account token only when `iid` does. Add the two T-144 tests and the ADR-012:132 correction.
- **R5-2's wording correction** should be made in this branch at the same time. It is a doc correctness fix, small and in the same files.
- **Everything else** may merge as residuals or owner-task acceptance criteria:
  - R5-2 (trust only from App Attest): T-132;
  - R5-3: the PO's choice between options (a) and (b);
  - R5-4: T-132 / T-136;
  - R5-5: PO;
  - R5-6: T-145 / T-147;
  - R5-7: T-136 / T-144;
  - R5-8: T-130;
  - R5-9: SRS wording at the next revision.
- **Process:** if the architect makes the R5-1 and R5-2 text changes, I will check only that delta and approve. A full round 6 isn't needed. The first green CI run must still include `RestoreBindingVectorTests` (with the new clientDataHash test), `SeatProofVectorTests`, the duplicate-property test and `TimeNonceIsSentAndEchoedExactlyOnAnchoringOperations`. Until then, those items stay "resolved in spec, CI pending".

## Acceptable residuals (for the PO to accept with an owner)
1. **Sign-in rebind budget on stock iOS behind a proxy** (R5-2, D-63): up to 2 cooldown-free rebinds plus 1 over-cap hop per purchase per 30 days for people sharing account credentials. Owner: T-132 (alerting via `seat_rebind`).
2. **Two jailbroken iPhones that pass App Attest swapping by restore past the cap**, one holder at a time, each swap alerted (R-19). Owner: T-132 / T-137 runbook.
3. **Undetected iOS reboot** gaining time the app wasn't running, slightly widened by R4-3(b) by up to `mono` per cycle (ADR-012 (h)). Owner: T-144.
4. **Same-iPhone install linkability in transit** (D-62, already accepted). Owner: T-137 disclosures.
5. **Correction ping-pong under single-agent support** (R5-5(a)), contained by alerts and lead review. Owner: T-137.
6. **Owner without a support path for ≤ 30 days after a correction** (R5-5(b)), unless option (ii) is taken. Owner: T-136 / T-137.
7. **Cross-store or other-Apple-ID owner refused on the holding iPhone for ≤ 30 days** after a third reinstall in 30 days (R5-3), unless option (a) is taken. Owner: T-147 / T-135.
8. **`supportNotice` lost** if its one response is lost (R5-7). Owner: T-136.

**Not acceptable as a residual: R5-1.** It defeats one-phone Gold on every stock iPhone.

## PO decisions needed
1. **The sign-in deviation from D-65(a):** I recommend you **accept** it. The gate is necessary; without it account sharers behind a proxy get unlimited swaps. Choose between:
   - (a) an optional App Attest assertion on iOS sign-in, which marks the key trusted and restores the full D-65(a) for honest owners (recommended; amends D-45 / FR-GOLD-09 scope to include iOS sign-in);
   - (b) accepting residual 7.
2. **R5-5(b):** accept residual 6, or add a `support_lead` `purchase:unfreeze` action (audited, different operator, no move).
3. **R5-9:** note the per-install keyed hash and the verify-time `seatKeys` in BR-SYNC-03 / D-62 / NFR-PRIV-07 at the next SRS revision.

**Relevant files (at `origin/fuapi`):**
- `/home/claude/zaghlol/docs/03-technical/backend-api.md`
- `/home/claude/zaghlol/docs/03-technical/adr/ADR-012-purchase-verification-entitlements.md`
- `/home/claude/zaghlol/docs/03-technical/security-model.md`
- `/home/claude/zaghlol/docs/03-technical/backend-schema.md`
- `/home/claude/zaghlol/docs/03-technical/platform-channels.md`
- `/home/claude/zaghlol/docs/03-technical/error-handling-and-observability.md`
- `/home/claude/zaghlol/backend/openapi/zaghlol-v1.yaml`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/RestoreBindingVectorTests.cs`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/SpecContractTests.cs`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json`
- `/home/claude/zaghlol/docs/04-tasks/tasks/T-144.md` (needs the R5-1 acceptance criterion)

**Sources:**
- [Google Play Developer API: `SubscriptionPurchaseV2.latestOrderId` deprecated, use `lineItems.latest_successful_order_id`](https://developers.google.com/android-publisher/deprecated-apis/latestOrderId.subscription.purchasev2)
