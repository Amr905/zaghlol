# ADR-012: Purchase verification & entitlement signing

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 (amended 2026-11-05, 2026-11-06) |
| Deciders | Product owner (approval), solution-architect |
| References | backend-api §4.3–4.5 |

## Context
D-13 and FR-BE-02: our own backend verifies purchases (no RevenueCat, OOS-16). Gold must survive 5 days offline (FR-GOLD-04) and can't be unlocked by editing files (NFR-SEC-05). Play Billing Library 8 is required for new releases. Apple publishes no official .NET App Store Server library; a community MIT library exists (`Enjna.AppStoreServerLibrary`).

## Options considered
1. **Trust client-side store receipts** — Insecure; forgeable.
2. ****Server verification + ES256-signed entitlement token cached on device**** — Offline-capable, tamper-proof, standard JOSE.
3. **Server verification + online check on every launch** — Breaks offline use (NFR-BE-01).

## Decision
**Option 2.**
- **Google:** `purchases.subscriptionsv2` / `products`, acknowledge server-side, purchase token as unique key, `obfuscatedExternalAccountId` = HMAC(installId).
- **Apple:** verify StoreKit 2 JWS (x5c → Apple Root CA G3), then App Store Server API for status, `appAccountToken` = HMAC(installId).
- **Lifecycle:** RTDN and ASSN V2.
- **Token:** ES256 JWS `{sub, acct, plan, status, exp, graceUntil, nextMoveAt}`, grace 7 days (A-38). Every token, lifetime included, rolls at most every 7 days (Part B (b), D-52).
- **Apple library:** decided in the Phase 5 task between `Enjna.AppStoreServerLibrary` (after a code review) and an in-house verifier using `System.Security.Cryptography` (x5c chain + ES256), preferring in-house if the review finds gaps.

## Consequences
The backend becomes critical for **new** purchases only. A background retry protects Google's 3-day acknowledge window (BR-GOLD-06). Signing keys live in the KMS with rotation via embedded next keys.

## Amendment (2026-11-05): restore payload, Play endpoints, anti-sharing and attestation (FU-006, D-45, D-46)

The SRS (FR-GOLD-02/03/07/08/09, EC-64…66, R-19) refers to this amendment. Part A covers the payload and endpoints. Part B is the anti-sharing and attestation design.

### Part A: Android restore payload and Play endpoints (FU-006)
**Context.** The T-006 review found that `POST /v1/purchases/restore` sent bare Android purchase tokens. The v1 `purchases.products.get` call needs the product ID in its path, so the server couldn't verify a lifetime purchase from a token alone. Google now documents `purchases.productsv2.getproductpurchasev2` (`GET …/applications/{packageName}/purchases/productsv2/tokens/{token}`) for one-time products. Like `subscriptionsv2.get`, it needs only the token and returns the product ID in `productLineItem[]`.

**Options.**
1. Keep bare tokens and rely on the v2 endpoints. The server can't tell a subscription token from a product token, so it has to try `subscriptionsv2.get` and then `productsv2`. That doubles Play quota use on misses and makes error mapping ambiguous.
2. Send `{productId, purchaseToken}` items and keep the v1 calls. This works, but stays on the older one-time product endpoint.
3. **Send `{productId, purchaseToken}` items and use the token-only v2 endpoints.** The product ID only routes the call and is cross-checked against what Play returns.

**Decision: option 3.**
- Android restore items are `{productId, purchaseToken}` (1–20). The app already has both from Play Billing `queryPurchasesAsync`. `productId` already appears in verify, so BR-SYNC-03 "purchase tokens/transactions" covers it.
- The server routes by its own product table: subscriptions go to `purchases.subscriptionsv2.get`, lifetime goes to `purchases.productsv2.getproductpurchasev2`. The v1 `purchases.products.get` is not used.
- The returned product ID must equal the claimed one (`PURCHASE_TOKEN_INVALID` otherwise). An unknown product ID gives `PURCHASE_WRONG_APP`.
- Acknowledgement still uses `purchases.subscriptions.acknowledge` / `purchases.products.acknowledge` with the product ID that Play returned.
- **Restore** skips the install-binding check (`obfuscatedExternalAccountId` / `appAccountToken`), because after a phone change the binding names the old install. *Superseded by Part B:* possession of the token is no longer proof of ownership, and the "3 moves per 30 days" cap is replaced by one seat per purchase with one move per rolling 30 days (D-52).
- Per-item failures fold into an aggregate `status`. The only 422 is `DEVICE_ATTESTATION_FAILED`, and the only 409 is `MOVE_COOLDOWN` (Part B).
- *Abuse limits (security review, 2026-11-05):*
  - a restore bucket of 5/hour per install;
  - a per-purchase limit of 10 attempts/day, keyed by SHA-256 of the token or `originalTransactionId`;
  - a global Play / App Store call budget with priority for verify and the ack sweeper. When the budget is short, restore gets `503` with `Retry-After`.

**Consequences (Part A).** T-130 implements the v2 calls. T-132 implements restore. T-145 sends items instead of bare tokens. Sources: Google Play Developer API reference for [`purchases.productsv2.getproductpurchasev2`](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2) and the [one-time product lifecycle guide](https://developer.android.com/google/play/billing/lifecycle/one-time), checked 2026-11-05.

### Part B: one-phone Gold, move cooldown and install-bound restore attestation (D-45, D-46, D-52…D-54)
*Revised 2026-11-06 for D-52 (one install at a time, one move per rolling 30 days), D-53 (attestation wording), D-54 (no self-service relink) and security re-review round 2 (R2-1…R2-10). The 3-seat design of 2026-11-05 (eviction, least-recently-used order, dormant reclaim, `seatsReleased`, `basic` seat quota) is withdrawn.*

**Context.** Every restore accepted any genuine store token, so a token posted online could give Gold to unlimited installs. The store binding can't help, because after a phone change it names the old install. The PO decided:
- **D-52** (replaces D-46's 3-seat limit): Gold from one purchase is held by **exactly one install at a time**, across Android and iOS. The owner can move it to another phone **once per rolling 30 days**; a cross-platform move (FR-GOLD-07) is that move; a same-install restore is never a move. Inside the 30 days a restore or sign-in from another install is refused, with the next-move date and a support link. Support can perform an audited manual move.
- **D-46** (still stands): attestation is required on restore, and an account-linked purchase moves only between installs signed in to that account.
- **D-53:** "expired" applies to Play Integrity only; iOS relies on install-bound App Attest keys and the counter, with no server challenge.
- **D-54:** a purchase is linked to an account only from the install that bought it; anything else goes through support.

BR-SYNC-03 is amended to allow the attestation proof (D-45). FR-GOLD-02 counts a genuine token from an excluded or unattested install as *replayed*.

**Options.**
1. **Velocity cap without a seat** (3 moves per 30 days, 2026-11-04). Doesn't bound concurrent use.
2. **N seats with eviction** (2026-11-05). Bounds concurrency at N, but every eviction is free, so two sharers can trade seats indefinitely ("seat churn"), and it needs dormancy and LRU rules.
3. **One seat, moves rate-limited to one per rolling 30 days, operator override.** This is chosen (D-52).
4. **Server-issued attestation challenge.** Stronger freshness for App Attest, but an extra endpoint, round trip and state. Rejected: see (d), the install binding gives what a challenge would.

**Decision: option 3**, specified in `backend-api.md` §4.3 (restore), §4.6 (sign-in), §5.3 (support move) and `backend-schema.md` (`purchase_seats`, `app_attest_keys`, `replay_guard`, `idempotency_records`).

**(a) The seat.**
- Each purchase has **one** seat row (`purchase_seats`, primary key `purchase_id`). Its holder is one install, or none (vacant) after the holder was deleted or purged.
- **Bind (not a move):** the first `POST /v1/purchases/verify` binds the seat to the buying install (`proof = binding`). A verify of a purchase whose seat already exists never changes the holder.
- **Move:** any change of holder to a different install, including taking a vacant seat. Restore or sign-in by the current holder only refreshes it. A reinstall or "Delete everything" creates a new install ID, so a later restore on the same phone **is** a move (see (g), OQ-19).
- **Cooldown:** a restore or sign-in move is allowed only if `last_moved_at` is null or `now ≥ last_moved_at + 30 d`. Otherwise nothing is written and the call fails with **`409 MOVE_COOLDOWN`** carrying `nextMoveAt = last_moved_at + 30 d` (backend-api §6). The app shows the locale-formatted date and the support link. A refused request is never a move (EC-66).
- Every allowed move sets `last_moved_at = now` and writes a `purchase_events` row (`seat_move`, with the channel `restore | signin | support | account_attach`).
- **Exempt from the cooldown** (they neither check nor restart it):
  - the **operator support move** (§5.3, EC-68). OQ-19(b) recommendation: it does **not** restart the 30-day window, because it corrects a lost or broken phone rather than spending the owner's monthly move. Abuse is bounded by ownership checks, audit and alerts (f).
  - the **account-attach reclaim** (c): at most once per account link, and only from the store-proven buying install.
- **Upgrade chains:** a Google purchase that replaces another (`linked_purchase_token`) inherits the predecessor's `last_moved_at`. Its seat binds to the buying install like any verify.
- **Seat churn (old R2-4) is gone:** every holder change by a user counts toward the cooldown, so two sharers get at most one hand-over per 30 days, and only one of them holds Gold at a time.

**(b) Entitlement lifetime (BR-GOLD-03, BR-GOLD-07, FR-GOLD-04).**
- For **every** plan, lifetime included: `exp ≤ iat + 7 d` (subscriptions: also `≤` the store expiry). `graceUntil = exp + 7 d` (A-38). So a token is honoured offline for **at most 14 days** after it was issued.
- Tokens for a seat proven only by `MEETS_BASIC_INTEGRITY` (`proof = basic`): `exp ≤ iat + 3 d`, so at most 10 days.
- **Refresh:** the daily sync re-issues the token when the cached one is more than 24 h old or anything changed; `GET /v1/entitlement` is called when the cached token is within 3 days of `exp`. An online holder therefore always holds a token with ≥ 5 days of offline life (≥ 10 days in practice for full-integrity seats), which meets FR-GOLD-04.
- The "lifetime tokens roll every 30 days" rule of the original decision is replaced by this 7-day roll.
- **Worst-case overlap (D-52 (d), FR-GOLD-08 acceptance):** the server never issues a token covering a purchase to an install that doesn't hold its seat, and never holds more than one seat. After a move, an old phone that comes online gets `status: moved` at its next sync or entitlement call (normally within 24 h). An old phone that stays offline keeps Gold only until the `graceUntil` of the last token it received before the move: **at most 14 days after the move** (10 days if it held a `basic` seat). This is the only window in which two phones show Gold for one purchase. It replaces the 37-day residual of the 2026-11-05 design.

**(c) Account-linked purchases (D-46, D-54, FR-ACCT-05).**
- **Account rule:** a purchase with `account_id` set moves only to an install that is linked to that account and presents its account token. Otherwise the restore item is `account_required` (EC-65) and nothing moves. Restore never changes `account_id`.
- **Attach (link) only from the buying install** (P3, D-54): sign-in sets `account_id` only on purchases where `account_id IS NULL` and `purchases.install_id` is the signing-in install. There is no other self-service link path; the earlier "sole attested seat holder" path is removed. If the buying install is gone, support links or moves the purchase (§5.3).
- **Seat at link time (R2-2(a)):** after attach, the seat must be on an install linked to the account. If the holder is the buying install or another install linked to the same account, it stays. Otherwise the seat moves to the buying install (the **account-attach reclaim**, exempt from the cooldown, `seat_move` / `account_attach`), and the previous holder gets `status: moved`. A token that leaked before linking therefore can't keep Gold on a stranger's phone once the owner links.
- **Sign-in seat:** sign-in on an install linked to the account moves the seat of each account-linked purchase to that install, under the cooldown (`409 MOVE_COOLDOWN` when every such move is refused and nothing else grants Gold). This is how Gold crosses platforms (FR-GOLD-07). The ID token is the proof (`proof = account`), so no attestation is needed.
- **Sign-out** doesn't change seats: the holder keeps Gold until the next move, which needs the account.
- Owners get "sign in on this phone to protect your Gold" on the buying phone after purchase and in Settings → Gold (FR-ACCT-01).

**(d) Restore attestation, bound to the install (FR-GOLD-09, D-53, R2-1).**
- **Binding:** `bodyHash = SHA-256("zaghlol-restore-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body without "attestation"))`. `installId` is the lower-case hyphenated UUID text (36 ASCII bytes) of the install that the **install token authenticates**; the server never takes it from the body or the `Zaghlol-Install` header. JCS is RFC 8785. A proof made for one install fails on every other install, even with a byte-identical body.
- **Android:** Play Integrity standard request with `requestHash = b64u(bodyHash)`. The server decodes it with `decodeIntegrityToken` and checks the hash, the package, `timestampMillis` ≤ 5 min old (the only "expired" case, D-53), `PLAY_RECOGNIZED`, and `MEETS_DEVICE_INTEGRITY` (or `MEETS_BASIC_INTEGRITY`, below). Each token is single-use (`replay_guard`).
- **Optional verdicts stay off (R2-7, D-45):** the app's Play Console integrity settings keep `deviceAttributes`, `recentDeviceActivity`, `appAccessRiskVerdict` and `environmentDetails` **disabled** (T-140 checklist). If a decoded verdict contains them anyway, the server ignores them: it reads only the listed fields, never stores or logs the rest, and its DTO has no member for them.
- **iOS:** App Attest assertion with `clientDataHash = bodyHash`, checked against the key registered to **this** install, with a strictly increasing counter. On a key's first use the body also carries `attestationObject`, **attested over the same install-bound `bodyHash`**, validated to the Apple App Attestation Root CA, and only then registered, to the install named in that hash. A key therefore only ever registers to its own install. A key ID already registered to another install is refused.
- **Why no server challenge (D-53):** a server nonce would prove freshness. The install binding already makes every proof useless outside the install whose token authenticated the request. Within that install:
  - Play tokens are single-use and expire after 5 minutes;
  - App Attest assertions are counter-protected;
  - a replayed `attestationObject` can only register a public key to the install it was made for, and the replayer lacks the private key.

  A stored, unused proof could only be spent by the same install, which could create a fresh one anyway. A challenge would add a round trip and server state and no security.
- **Residual (proxying):** an owner can still run the genuine app on their own attested phone on behalf of another person. That needs the other person's install token on the owner's phone (a modified app fails `PLAY_RECOGNIZED` / App ID checks) and still moves the one seat under the cooldown, so it can't create a second concurrent holder.
- **Transport (R2-1):** release Android builds trust **system CAs only**, through `network_security_config` (`<base-config cleartextTrafficPermitted="false">` with `<certificates src="system"/>`, user CAs only in `<debug-overrides>`). This keeps a user-installed CA from reading or rewriting restore bodies and proofs on a stock phone. iOS has no equivalent switch without pinning (ADR-018); its residual is covered by the install binding. Owners: the app attestation task and T-145.
- **Strict JSON (R2-6):** the server parses the restore body once, with duplicate member names and lone (unpaired) UTF-16 surrogates rejected as **`400 VALIDATION_FAILED`**. It computes JCS over **that** parsed object (minus `attestation`) and binds the DTO from the same object, so the hashed and the processed body can't differ. Dart (T-145) and .NET (T-132) must pass the shared vectors in `backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json`, which a contract test also checks.
- **Basic integrity (R-19):** a Play verdict with `MEETS_BASIC_INTEGRITY` but not `MEETS_DEVICE_INTEGRITY` (often a custom ROM) may hold the single seat, under the same cooldown, with `proof = basic` and `exp ≤ iat + 3 d`. Refusing these devices outright would lock out paying owners. The cooldown already bounds what a weaker device can do, and the shorter `exp` limits the offline overlap after it loses the seat. The former 1-restore-per-day bucket is dropped, because each move already counts.
- **No verdict, App Attest unsupported:** `422 DEVICE_ATTESTATION_FAILED` and no Gold (EC-66). The way back is sign-in for an account-linked purchase, or support.
- **Outages and quota:** `503 UPSTREAM_UNAVAILABLE` with `Retry-After`, never `422`. The app retries platform-transient errors with back-off. Existing holders keep their cached Gold. T-140 checks the Play Integrity quota before launch and alerts at 50 %.
- **Verify does not require attestation.** The store-side binding to HMAC(installId) already proves that the buying install made the purchase (`PURCHASE_NOT_OWNED` otherwise). Attestation would add failure modes to the payment path (BR-GOLD-06) with no gain.

**(e) Data.** Only the proof is sent (BR-SYNC-03 amended, D-45). The server stores the App Attest public key and counter, and hashes in `replay_guard`. It stores no device identifier and no verdict payload. Proofs are never logged.

**(f) Support move and alerts.**
- `POST /admin/v1/support/seat:move` (role **`support_agent`**, distinct from read-only `support_viewer`) moves a seat to a named install, bypassing the cooldown, and can attach an unlinked purchase to the target install's account (FR-ACCT-05). The account rule still applies. It is audited in `audit_log` with the install IDs and a reason code, never an e-mail, and the row is kept **exactly 1 year** (D-47 rules).
- **Interim path (D-37, R-21):** until the admin web app ships after launch, support uses this endpoint through the `zaghlol-ops` CLI (`zaghlol-ops support move …`), which needs operator OIDC with MFA. Owners: T-136 (endpoint, role and audit), T-137 (CLI command and runbook), T-132 (seat service).
- **Alerts** carry the purchase UUID only:
  - more than 2 support moves for one purchase in 90 days, or more than 20 support moves by one operator in a day;
  - a `MOVE_COOLDOWN` refusal spike;
  - an attestation-failure spike by reason code;
  - Play Integrity quota above 50 %.

**(g) OQ-19(a): recognising "the same phone" after a reinstall or reset (recommendation for the PO).**

| Option | How | Privacy (D-45, BR-SYNC-03) | User impact | Verdict |
|---|---|---|---|---|
| 1. A reinstall is a new install | Nothing new | No new data | A reinstall or "Delete everything" followed by restore spends the month's move; a second one inside 30 days needs support | **Recommended for launch** |
| 2. iOS Keychain "seat secret" (`ThisDeviceOnly`), sent hashed on restore | Random 256-bit secret, survives app deletion in current iOS | A new app-generated pseudonymous identifier. Needs an SRS classification (as part of "anonymous install ID") | Same-phone **reinstall** stays free on iOS; **Erase All Content** still spends the move. Keychain survival after deletion is undocumented, so Apple could change it | Possible later enhancement, iOS-only |
| 3. Android Block Store secret | As 2, through Google Play services | Same as 2 | Survives reinstall only if the user has Google Backup on. It is also copied to a **new** phone during device-to-device or cloud restore, so two phones would both look like "the same phone" and could trade Gold without a cooldown | **Rejected** (breaks the cooldown) |
| 4. App Attest key reuse | Look up the old key | No new data | Keys don't survive reinstall or restore | Not feasible |
| 5. `ANDROID_ID`, identifierForVendor or another device identifier | Read from the OS | A device identifier: forbidden by FR-GOLD-09 and BR-SYNC-03 | — | **Rejected** |

Recommendation: option 1, stated in the help copy ("لو مسحت الأبلكيشن ونزّلته تاني، نقل زغلول جولد هيتحسب نقلة الشهر") and in the "Delete everything" confirmation when this install holds a seat and the cooldown is running. The entitlement token's `nextMoveAt` claim drives that copy. Revisit option 2 if support volume (R-21) shows reinstall moves are common.

**Consequences.**
- **T-122:** `purchase_seats` (one row per purchase, `last_moved_at`), `app_attest_keys`, `replay_guard`, `idempotency_records`.
- **T-130:** Play Integrity decode, with optional verdict fields ignored.
- **T-131:** App Attest attestation/assertion validation (in-house CBOR + X.509) over the install-bound hash.
- **T-132:** the seat service (bind, move, cooldown, attach reclaim, `moved` tokens), the 7-day `exp`, strict JSON + JCS binding, `MOVE_COOLDOWN`, and the restore aggregate.
- **T-135:** sign-in seat moves, attach-only-from-buying-install, Google nonce required, idempotency keyed by body hash.
- **T-136:** `support_agent` role, `seat:move` endpoint and its audit row (1 year). **T-137:** the CLI command. **T-139:** purge support-move audit rows after 1 year.
- **T-144:** handle `status: moved`, the 7-day `exp` refresh and the `nextMoveAt` claim.
- **T-145:** restore sends the install-bound attestation; `MOVE_COOLDOWN` and help UX; system-CA-only network config.
- **T-147:** Google nonce; the "sign in on this phone" prompt; `MOVE_COOLDOWN` on sign-in.
- **T-140:** quota check and the optional-verdict checklist.
- **New app task (C4):** native `AttestationHostApi` (`platform-channels.md` §4a): Play Integrity standard requests, the App Attest key lifecycle, the install-bound hash, the release network config, and device tests on real hardware.
- **New backend task (C4):** attestation verifier module (Play Integrity decode, App Attest attestation and assertion) with fakes for tests, split out of T-130/T-131.

Sources:
- [Play Integrity verdicts](https://developer.android.com/google/play/integrity/verdicts) (`requestDetails.requestHash`, `timestampMillis`, `appRecognitionVerdict`, `deviceRecognitionVerdict`; optional verdicts), checked 2026-11-05.
- [.NET client `Google.Apis.PlayIntegrity.v1`](https://developers.google.cn/api-client-library/dotnet/apis/playintegrity/v1?hl=en).
- [Android Block Store](https://developer.android.com/identity/block-store): data persists across reinstall only with Backup enabled, and is transferred during device restore; checked 2026-11-06.
