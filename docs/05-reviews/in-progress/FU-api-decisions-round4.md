# FU-api-decisions: Security and Privacy Review

**Reviewer:** security-privacy-reviewer · **Branch:** `task/FU-api-decisions` @ `9ae53aa`
**Scope:** round 4 is `git diff e00fd92 origin/fuapi -- docs/03-technical backend`; the cumulative design is `git diff bdb4091...origin/fuapi`. Checked against SRS v1.6 on main: D-55…D-61, NFR-SEC-08, and BR-SYNC-03 as amended.
**Current verdict: CHANGES_REQUESTED.** Two majors must be fixed: R4-1 (the seat-key proof can be relayed, which bypasses the cooldown) and R4-2 (replayed signed server time defeats trusted time).

---

## History

**Round 1 (2026-11-05): CHANGES_REQUESTED.**
- 2 blockers: a shared restore token gave Gold to unlimited installs, and the Apple sign-in nonce was not checked.
- 4 majors, plus minors.
- Findings 2–8 and 10–12 were fixed at `8fe1251`. Findings 1 and 9 led to D-45…D-47 and the ADR-012 Part B design.

**Round 2 (2026-11-05): CHANGES_REQUESTED.**
- 1 blocker: R2-1, the attestation was bound to the body and not to the install.
- 3 majors and minors, R2-2…R2-10.
- The PO then replaced the 3-seat model with D-52…D-54 (SRS v1.5).

**Round 3 (2026-11-06): CHANGES_REQUESTED.**
- All ten round-2 findings were resolved in the design.
- New majors:
  - R3-1: the offline bound depended on the device's wall clock.
  - R3-2: support could move or link a purchase on proof the design itself called insufficient.
- Minors R3-3…R3-9 and info R3-10.
- The PO answered with D-55…D-61 and NFR-SEC-08 (SRS v1.6).

---

## Round 4 (2026-11-06)

### Method and dependence on CI
- **Review by reading only.** GitHub Actions is blocked by billing (BLK-05).
- **What I checked myself:** I recomputed `backend/tests/Zaghlol.Contract.Tests/vectors/seat-proof-v1.json` with an independent Python script (`cryptography`, P-256):
  - all three `valid` vectors rebuild `messageHex` byte for byte and verify;
  - all three `invalid` vectors fail.
  - The restore challenge equals the `bodyHash` of `restore-binding-v1` `ios-member-order`. `ios-seat-keys-not-hashed` confirms that `attestation.seatKeys` is outside the hash.
  - The `SeatKeyProof.publicKey` pattern `^B[A-P][A-Za-z0-9_-]{85}$` correctly matches a 65-byte 0x04-prefixed point.
- **These conclusions depend on CI and are not verified:**
  - `SeatProofVectorTests.cs` compiles and passes on net10.0 with `TreatWarningsAsErrors`. It uses `Base64Url`, `Convert.ToHexStringLower` and `ECDsa.VerifyData(…, DSASignatureFormat.IeeeP1363FixedFieldConcatenation)`, all of which exist on .NET 9 and later.
  - `DuplicateVectorsAreRejectedByTheFrameworkStrictOption` compiles. This needs `JsonDocumentOptions.AllowDuplicateProperties` (.NET 10), and it must throw a `JsonException` subtype for all three nested-duplicate vectors.
  - The new `None Update="vectors\seat-proof-v1.json"` item copies the file.
  - The T-006 contract tests still pass on the edited OpenAPI file: the `x-required-roles` for `adminDetachPurchase`, refs, and examples.
  - R2-6 / R3-8 therefore stay "resolved in spec, CI pending".

### Resolution of round-3 findings

| ID | Finding | Status | Evidence / residual |
|---|---|---|---|
| R3-1 (major) | Offline bound depended on the wall clock | **Partially resolved** | The trusted-time contract is specified: `backend-api.md:285-322`, ADR-012:199-207, `security-model.md:15`, `platform-channels.md:212-245`. Monotonic advance, a 10-min rollback test, `BOOT_COUNT`, and a 6-h reboot charge are all sound in principle. **New gaps:** R4-2 (major: replayed signed time re-anchors and clears `tampered`) and R4-3 (minor: an honest quick reboot is flagged as tampering). |
| R3-2 (major) | Support move or attach on insufficient proof | **Resolved per D-57** | Live order-ID check (`backend-api.md:494-500`) with the order ID never stored. Attach gate (`:506-510`). Correction by move-back and detach (`:503`, `:519`). The window restarts (D-56). `movedBy: support`. Alerts now have runbook actions (`:529-533`). A single agent is the PO's explicit choice and is not re-raised. Residual: the order ID proves store-account access, not ownership against household members (R4-7, info). |
| R3-3 | Repeatable attach reclaim | **Resolved** | `attach_reclaim_used_at` is never cleared, including on account deletion (`backend-api.md:374`, `:388`; `backend-schema.md` purchases). EC-72 holds. |
| R3-4 | Single claimant slot; exact move time leaked | **Resolved** | `seat_claimants` holds up to 3 entries, each for 7 days, under the seat lock. `next_move_at` is `ceil_hour`, enforced exactly, with a CHECK constraint, and `last_moved_at` is never sent. |
| R3-5 | Sign-in 409 rolled back the attach | **Resolved** | Steps 1–4 always commit. Sign-in returns 200 `moveRefused` (`backend-api.md:381`). `replay_guard` is committed before and outside the transaction (`:363`). |
| R3-6 | Idempotency hardening | **Resolved** | CSPRNG key; `expires_at > now()` on every lookup; install and account deletes purge records; a deleted account's token gets 401 (`backend-api.md:16`, `:57`). `registerInstall` no longer stores a token-bearing response. A same-key, same-body replay before the first authenticated call mints a fresh token and kills the unused one (`:71`). Knowing the support code alone yields nothing. |
| R3-7 | Plan change from another install skipped the cooldown | **Resolved per D-59 / D-61(a)** | The move happens when no cooldown is running; inside a cooldown the payer becomes a claimant and gets `seatHeldElsewhere`; payment is never blocked (`backend-api.md:164-171`). New gap: the account rule is not applied (R4-4). |
| R3-8 | Vector test only checked itself | **Resolved in spec; CI pending** | Nested duplicate vectors; explicit `AllowDuplicateProperties=false`; T-132 endpoint test and T-145 Dart counterpart assigned (`backend-api.md:200-202`). |
| R3-9 | Operator CLI sign-in | **Resolved** | FIDO2 required for `support_agent`, auth-code + PKCE with loopback, device-code disabled, named staff, quarterly review (`backend-api.md:53`). Enforceability of the `amr` check is in R4-6 (info). |
| R3-10 | Sharing within the rules | **Resolved** | D-60 cuts the window to 7 d (basic 6 d). FR-GOLD-04 still holds with the 12 h refresh (ADR-012:80-81). |

### New findings

#### R4-1 (Major): the seat-key proof can be relayed from one jailbroken iPhone, giving unlimited cooldown-free "rebinds"
- **Where:**
  - `backend-api.md:243` ("Element 0 is the calling install's own key", which the server cannot check)
  - `backend-api.md:216`, `:260-261`, `:377` (rebind skips the cooldown; the stored hash is replaced by whatever element 0 is)
  - ADR-012:190, :194
  - `restore-binding-v1.json` `ios-seat-keys-not-hashed` (`seatKeys` is outside the hash the App Attest assertion covers)
  - `security-model.md:16` ("not extractable, even on a jailbroken phone": true, but it doesn't prevent use as a signing oracle)
- **Exploit:**
  1. Phone A is an old, jailbreakable iPhone (checkm8-class devices still run iOS 16). It holds the seat, so the hash is `HMAC(pid‖K_A)`. A hooks the app's `SeatKeyHostApi.sign` and acts as an online signing oracle.
  2. Friend F has a stock iPhone with a user-installed CA proxy. iOS honours user-trusted CAs and there is no pinning (ADR-018). F runs a genuine restore. Its App Attest assertion covers only `bodyHash`.
  3. The proxy replaces `attestation.seatKeys` with `[{K_A, sig_A(“zaghlol-seat-v1”‖restore‖F.installId‖F.bodyHash)}]`. The signature is valid and the key matches `device_key_hash`, so F gets a rebind with no cooldown.
  4. Because element 0 is `K_A`, the stored hash stays `HMAC(pid‖K_A)`. Any further phone F2, F3… repeats step 3, and A can take Gold back with its own genuine request, all with no cooldown.
- **The same works on sign-in for account-linked purchases.** Sign-in has no App Attest at all, so a modified client with the shared account credentials can send the relayed proof directly.
- **Effect:** D-52(a)/(b) fail completely on iOS for anyone with one jailbroken iPhone. This is worse than the accepted R-19 residual: rooted Android is still bounded by the cooldown, and this is not.
- **Required change** (T-132 seat service; the new backend seat-key verifier task; the new app `SeatKeyHostApi` task; ADR-012 (g); `security-model.md:16`):
  1. **Bind element 0 to the install.** On an install's first valid `seatKeys`, store `installs.seat_key_hash = HMAC(K_seat, installId‖pk)`. Later requests whose element 0 differs get `400` (restore, sign-in) or are ignored (verify). A rebind must match a **non-zero** element. After the rebind, the seat hash becomes the **caller's registered** key. A relayed `K_A` can then pull the seat once, after which the next hop needs the new holder's Secure Enclave as an oracle.
  2. **Cap rebinds:** at most 2 per purchase per rolling 30 days. Beyond that the request is an ordinary move under the cooldown, and it is audited as a `seat_rebind` alert. Genuine reinstalls are rare, so owners don't notice. Without this cap, two jailbroken phones can still ping-pong.
  3. **Restore:** put the `seatKeys` public keys, not the signatures, inside the hashed body (or fold `SHA-256(pk₀‖…‖pkₙ)` into the App Attest `clientDataHash`). A proxy can then no longer rewrite a genuine install's keys.
  4. Correct the `security-model.md:16` wording, and add the oracle residual to ADR-012 (h) or (g).

#### R4-2 (Major): any newer signed `serverTime`, including one from another install or a withheld response, re-anchors `hw` downward and clears `tampered`
- **Where:**
  - `backend-api.md:298-300` (anchor from "any signed response"; "If S > lastServerTime … hw = S … tampered = false")
  - `backend-api.md:17` (`Zaghlol-Signature` covers the body bytes only, with no binding to a request or install)
  - ADR-012:128 (iOS has no system-CA-only switch)
- **Exploit:** phone A loses the seat and is kept offline by a user-CA proxy (stock iOS), or it is a rooted Android phone.
  1. The proxy feeds A signed `/v1/sync` bodies with increasing `serverTime` values. They can come from a second install of the attacker's, which can request throttle responses at any time, or from A's own responses that the proxy captured earlier and never delivered.
  2. Each one has `S > lastServerTime` but `S < hw`. So `hw` drops back to `S` and `tampered` clears, which also forgives a clock rollback.
  3. With one harvested time per second over the 7-day window, A keeps its pre-move token alive indefinitely.
- **Effect:** NFR-SEC-08, EC-70 and the 7-day bound of D-60 / FR-GOLD-08 fail on stock iOS.
- **Required change** (T-144; the API response-signing owner; `backend-api.md` §1 / §4.3):
  - A response may lower `hw` or clear `tampered` only if it is bound to the current request. The app sends a fresh 128-bit `Zaghlol-Time-Nonce` (CSPRNG) per anchoring request; the server echoes it inside the signed body. The app accepts only the echo for its single outstanding request, within 60 s of sending it, and discards older nonces.
  - Every other signed `serverTime` and `iat` may only raise `hw`: `hw = max(hw, S)`. It never clears `tampered`.
  - Add unit tests for "another install's signed body" and "withheld older response".
  - BR-SYNC-03: the nonce is a random per-request value with no device data, of the same kind as the D-48 sign-in nonce. It needs only a D-48-style classification note, not a new data class.

#### R4-3 (Minor): the advance algorithm flags honest reboots as tampering and double-counts on iOS
- **Where:** `backend-api.md:304-307`; ADR-012:203 ("A legitimate holder loses at most 6 h per quick offline reboot").
- **(a) Honest reboot flagged:** after a detected reboot, `cand = hw + max(m, 6 h)`. Step 3 then compares `w < cand − 10 min`.
  - Example: a holder used the app less than about 6 h before a quick offline reboot (the phone died and was recharged while travelling). Its wall clock is correctly about `hw + minutes`, so step 3 sets `tampered`, and Gold is withheld until it reconnects.
  - That breaks FR-GOLD-04 and the ADR's own claim. It fails closed, so it is not a security issue.
- **(b) iOS double-count:** on iOS, a wall-clock correction of more than 10 min without a reboot (NITZ or NTP after a long offline period) shifts `wall − m` and is treated as a reboot. `elapsed = m` (the uptime since the real boot) then counts `mono` a second time, and can burn days of an honest holder's window.
- **Required change (T-144):**
  - Run the tamper test against the uncharged lower bound, `hw + (same boot ? m − mono : m)`. Apply the 6-h charge only to `hw` afterwards.
  - On iOS, when `b` shifts but `m ≥ mono`, charge `max(m − mono, 6 h)`.
  - Add both cases to the required unit tests. The existing "5-day guarantee with one reboot" test should catch (a) once it exists.

#### R4-4 (Minor): a plan-change move ignores the account rule, so a sharer can strand an account-linked seat
- **Where:** `backend-api.md:168-171`; ADR-012:89-91. Both say the seat "moves to the paying install" with no account check. Contrast `backend-api.md:212` and the claimant text at `:502`.
- **Path:**
  1. A person with access to the store account upgrades the plan from install X, which is not signed in to the owner's Zaghlol account. The Google successor inherits `account_id`.
  2. The seat moves to X, and `next_move_at` restarts.
  3. X gets `paused`, because it has no account token. The owner gets `moved` and must wait 30 days to move Gold back.
- **Impact:** a paid griefing path. It violates D-46 ("moves only between installs signed in to that account").
- **Required change (T-130 / T-132):** for an account-linked purchase, the plan-change move also requires a valid `Zaghlol-Account` token for that account on the verify request. Otherwise the seat stays and the payer becomes a claimant, with the `seatHeldElsewhere` response or an `account_required` hint. Payment is still never blocked.

#### R4-5 (Minor, privacy): `seatKeys` reveals the chain of earlier installs and is over-sent; the ADR's privacy claim is wrong
- **Where:**
  - ADR-012:195 ("a key never appears in any request after its install is replaced"). This is false: up to 4 earlier keys are re-sent by every later install.
  - `backend-api.md:243`, `:252-254`. Up to 5 keys go on **every** iOS restore and sign-in, including sign-ins for users with no purchases.
  - `platform-channels.md:227-234`.
- **Issue:**
  - Each restore or sign-in sends, in clear inside TLS, the raw public keys of the last ≤ 5 installs on that iPhone.
  - At rest only per-purchase HMACs exist, and logging is banned, so the exposure is in transit and in process memory. Even so, anyone with code access to the API could build a per-device install graph from traffic that has nothing to do with any seat.
  - D-55 requires the server to learn "same iPhone" only when recognising a reinstall.
- **Fit with BR-SYNC-03 / D-55:** a public key plus a signature is a "derived, non-reversible proof" of a Secure Enclave secret and carries no other device data, so the field **fits the wording**. Sending old keys when no seat can match is beyond what the purpose needs (data minimisation, NFR-PRIV-01).
- **Less-linkable design (recommended)** (app seat-key task, T-132, T-147, ADR-012 (g)):
  - Use **per-purchase seat keys**. When an install becomes or stays the holder of a purchase, it creates (or reuses) a Secure Enclave key whose Keychain item is labelled with a local `HMAC(appLocalKey, originalTransactionId)`.
  - On restore or sign-in it sends at most one key per purchase item it knows from StoreKit: the key labelled for that purchase. It sends nothing for purchases it has no key for, and nothing at all for installs with no Gold.
  - Server storage stays the same. Keys then never link purchases or installs beyond the one seat they protect, and this composes with R4-1(1)–(2): register per (install, purchase) instead of per install.
- **If the architect keeps the current design:** correct ADR-012:195, and send `seatKeys` on sign-in only when the account has a linked purchase whose seat is held elsewhere. The server can announce this in a pre-flight, or the app can retry once after a `moveRefused`.

#### R4-6 (Info): `amr` / `acr` enforcement depends on the IdP
- **Where:** `backend-api.md:53`.
- **Issue:** Entra ID signals authentication strength through `acrs` (authentication context) or `amr`, depending on configuration. Google Workspace OIDC tokens generally don't carry a FIDO2 `amr`.
- **Required (T-136):** confirm on the chosen IdP which claim proves FIDO2. If none does, enforce it through IdP conditional access scoped to the CLI and admin clients, and document that the API check is advisory.

#### R4-7 (Info): residual risk of single-agent support (no second approver requested)
- **The gap:** a Play or App Store order ID is visible to anyone signed in to the store account (order history, receipt e-mail). It proves the same thing the claimant rule already does: store-account access. A household member or ex-partner can pass it.
- **What contains it:** the attach gate, the correction path and `movedBy: support`.
- **The remaining weakness is a ping-pong dispute:** both parties present the same evidence to different agents.
- **Optional mitigations that keep one agent per action:**
  1. A server-side **dispute freeze**: after any `correction`, further non-correction support actions on that purchase are refused for 30 days (`409 ADMIN_CONFLICT`).
  2. A support attach also marks the purchase so that the buying install, if it reappears, gets a one-time "your Gold was linked to an account by support" notice.
  3. The runbook asks support to prefer the claimant that matches the purchase's `obfuscatedExternalAccountId` lineage, meaning the install that made the purchase.
- Separately, confirm in T-130 that the Play Developer API `orders.get` is generally available for the app's account and returns `purchaseToken`. If it isn't, fall back to `purchases.subscriptionsv2` `latestOrderId` / `productsv2` order-ID comparison.

#### R4-8 (Info): data retention for `device_key_hash`
- `device_key_hash` is kept after `DELETE /v1/installs/me` and the 12-month purge (`backend-schema.md` purchase_seats). It is pseudonymous, scoped to one purchase, and deleted with the purchase, so this is acceptable.
- The privacy notice entry for D-55 should say that "Delete everything" on iOS keeps the seat keys on the phone and a keyed hash on the server. The "Delete everything" copy already partly does (`security-model.md`, deletion step 4).

### New attack surface checked with no finding
- **Seat-proof replay:**
  - The restore challenge is the install-bound `bodyHash`, and the App Attest counter makes it single-use.
  - The sign-in challenge is `SHA-256(raw nonce)`, single-use through `replay_guard`.
  - The verify challenge `SHA-256(signedTransaction)` can be repeated, but only by the same install, and verify never rebinds.
  - Cross-install replay fails on `installId` (the `other-install` vector). Forgery needs the Secure Enclave, or the oracle in R4-1.
- **`secure_state` rollback:**
  - It lives in the SQLCipher DB, keyed through Keystore / Keychain, and app data is excluded from OS backups. Rolling it back needs root or a jailbreak, which is out of scope (MASVS-R light).
  - An iOS reinstall deletes the DB, so the cached token goes with it.
- **iOS clock source:** `CLOCK_MONOTONIC_RAW` on Darwin is continuous time and counts sleep. The T-144 device test confirming this is correctly required (device-dependent, not CI).
- **iOS reboot evasion:** the residual at ADR-012:206 is accurate, provided R4-2 and R4-3 are fixed. Each undetected cycle gains only time the app wasn't running, and the wait grows every cycle. Accepted under R-19.
- **Paused state:**
  - The server excludes account-linked purchases without a matching account token.
  - The app drops its cached token at sign-out even when offline, and honours `acct` tokens only with a matching unexpired account token (`backend-api.md:277-281`, `:383`).
  - No bypass found short of a modified app.
- **Support detach:** only links with `account_linked_by='support'` can be detached. A detach requires the ownership check and a matching `correctsAuditId`, and leaves the seat in place. It cannot reverse an owner's own link.
- **`registerInstall` fresh-token rule:** a replay needs the 80-bit CSPRNG key plus the exact body, works only before the first authenticated call, and invalidates the never-used earlier token. A race just leaves the last token issued as the valid one.
- **Order ID handling:** it is never stored or logged, the DTO is marked `[Sensitive]`, the CLI uses a no-echo prompt, and the audit row records only the outcome.

### BR-SYNC-03 / egress check (D-45, D-48, D-55)
- **`seatKeys` fits the D-55 wording:** a derived, non-reversible proof of a ThisDeviceOnly Keychain-held secret, with no other device data. iOS only (Android schemas reject it). The server keeps a per-purchase keyed hash, never the raw key.
- **Minimisation and the ADR claim:** see R4-5.
- **R4-2's fix adds a per-request random nonce.** It needs only a D-48-style classification note ("random per-request value, no device data"), not a new data class.
- **Nothing else new leaves the app:** `movedBy`, `paused`, `seatHeldElsewhere`, `moveRefused` and `nextMoveAt` all flow from server to app. The order ID goes from user to helpdesk to the operator API and never through the app.

### Regression check
- **No regressions against the round 1–3 fixes:**
  - Apple and Google nonces are still required.
  - New admin DTOs have `additionalProperties: false`.
  - `ticketRef` is still a regex, not free text.
  - No credentials or order IDs in query strings.
  - Support lookup still uses only the HMAC e-mail.
  - Alerts carry the purchase UUID only.
  - Store binding still has priority on verify.
  - System-CA-only on Android is kept.
- **One regression against D-46:** the account rule on plan changes (R4-4).

### Product-owner decisions needed
1. **R4-5:** approve per-purchase seat keys (recommended), or explicitly accept that every iOS restore and sign-in reveals to the backend, in transit, the public keys of the last ≤ 5 Zaghlol installs on that iPhone, even when no seat can match. Either choice is within D-55's wording. The second goes beyond its purpose.
2. **R4-1(2):** approve a cap of 2 same-iPhone rebinds per purchase per 30 days. Beyond that, a reinstall restore counts as the move. This is a small amendment to D-55 ("not a move", up to the cap).
3. **R4-7 (optional):** the 30-day dispute freeze after a support correction. This does not add a second approver.

### Verdict
**CHANGES_REQUESTED.**
- Seven of the nine round-3 actionable findings (R3-2…R3-6, R3-8, R3-9) and the R3-10 PO decision are resolved, with R3-8 still waiting on its first green CI run. R3-1 is only partially resolved because of R4-2 and R4-3. R3-7 is resolved per D-59 / D-61(a), with the account-rule gap carried as R4-4.
- **Before approval, the architect must specify:**
  - **R4-1:** element-0 registration per install (or per install and purchase), the rebind cap, and `seatKeys` public keys covered by the App Attest hash on restore.
  - **R4-2:** request-bound signed time. Only an echoed, fresh nonce may lower `hw` or clear `tampered`.
- **R4-3, R4-4 and R4-5 are minors.** Fix each in this branch, or log it in the acceptance criteria of its owner task before merge:
  - R4-3: T-144.
  - R4-4: T-130 / T-132.
  - R4-5: the app seat-key task, T-132 and T-147, plus the ADR-012:195 correction, which must happen in this branch.
- **Round-5 scope:** the R4-1 and R4-2 text, the PO decisions above, and the first CI run that includes `RestoreBindingVectorTests`, `SeatProofVectorTests` and the duplicate-property test.

**Relevant files (at `origin/fuapi`):**
- `/home/claude/zaghlol/docs/03-technical/adr/ADR-012-purchase-verification-entitlements.md`
- `/home/claude/zaghlol/docs/03-technical/backend-api.md`
- `/home/claude/zaghlol/docs/03-technical/security-model.md`
- `/home/claude/zaghlol/docs/03-technical/platform-channels.md`
- `/home/claude/zaghlol/docs/03-technical/backend-schema.md`
- `/home/claude/zaghlol/backend/openapi/zaghlol-v1.yaml`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/SeatProofVectorTests.cs`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/vectors/seat-proof-v1.json`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json`