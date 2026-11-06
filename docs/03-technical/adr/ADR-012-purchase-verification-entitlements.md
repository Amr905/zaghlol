# ADR-012: Purchase verification & entitlement signing

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 (amended 2026-11-05, 2026-11-06, round 4 2026-11-06) |
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
- **Token:** ES256 JWS `{sub, acct, plan, status, exp, graceUntil, nextMoveAt, movedBy}`. Every token, lifetime included, lives at most 3 days plus 4 days of grace, evaluated against trusted time (Part B (b), D-60; supersedes A-38's 7-day grace and the 30-day lifetime roll).
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

### Part B: one-phone Gold, move cooldown and install-bound restore attestation (D-45, D-46, D-52…D-61)
*Revised 2026-11-06 for D-52 (one install at a time, one move per rolling 30 days), D-53 (attestation wording), D-54 (no self-service relink) and security re-review round 2 (R2-1…R2-10). The 3-seat design of 2026-11-05 (eviction, least-recently-used order, dormant reclaim, `seatsReleased`, `basic` seat quota) is withdrawn.*
*Round 4 (2026-11-06): D-55 (same-iPhone recognition), D-56 (support move restarts the window), D-57 (support ownership check), D-58 (free reclaim once per purchase), D-59 (plan change from another phone is a move), D-60 (7-day offline window, trusted time), D-61 (plan change inside the cooldown, reclaim restarts the window, sign-out pauses account-linked Gold), and security round 3 (R3-1…R3-9). SRS v1.6.*

**Context.** Every restore accepted any genuine store token, so a token posted online could give Gold to unlimited installs. The store binding can't help, because after a phone change it names the old install. The PO decided:
- **D-52** (replaces D-46's 3-seat limit): Gold from one purchase is held by **exactly one install at a time**, across Android and iOS. The owner can move it to another phone **once per rolling 30 days**; a cross-platform move (FR-GOLD-07) is that move; a same-install restore is never a move. Inside the 30 days a restore or sign-in from another install is refused, with the next-move date and a support link. Support can perform an audited manual move.
- **D-46** (still stands): attestation is required on restore, and an account-linked purchase moves only between installs signed in to that account.
- **D-53:** "expired" applies to Play Integrity only; iOS relies on install-bound App Attest keys and the counter, with no server challenge.
- **D-54:** a purchase is linked to an account only from the install that bought it; anything else goes through support.
- **D-55…D-61:** listed in the round-4 note above; each is placed in the section it changes.

BR-SYNC-03 is amended to allow the attestation proof (D-45) and, on iOS, the seat-key proof (D-55, (g)). FR-GOLD-02 counts a genuine token from an excluded or unattested install as *replayed*.

**Options.**
1. **Velocity cap without a seat** (3 moves per 30 days, 2026-11-04). Doesn't bound concurrent use.
2. **N seats with eviction** (2026-11-05). Bounds concurrency at N, but every eviction is free, so two sharers can trade seats indefinitely ("seat churn"), and it needs dormancy and LRU rules.
3. **One seat, moves rate-limited to one per rolling 30 days, operator override.** This is chosen (D-52).
4. **Server-issued attestation challenge.** Stronger freshness for App Attest, but an extra endpoint, round trip and state. Rejected: see (d), the install binding gives what a challenge would.

**Decision: option 3**, specified in `backend-api.md` §4.3 (restore, verify, entitlement token, trusted time), §4.6 (sign-in, sign-out), §5.3 (support move, detach) and `backend-schema.md` (`purchase_seats`, `seat_claimants`, `app_attest_keys`, `replay_guard`, `idempotency_records`).

**(a) The seat.**
- Each purchase has **one** seat row (`purchase_seats`, primary key `purchase_id`). Its holder is one install, or none (vacant) after the holder was deleted or purged.
- **Bind (not a move):** the first `POST /v1/purchases/verify` binds the seat to the buying install (`proof = binding`).
- **Move:** any change of holder to a different install, including taking a vacant seat, except the iOS same-phone **rebind** of (g). Restore or sign-in by the current holder only refreshes it. On Android a reinstall or "Delete everything" creates a new install ID, so a later restore on the same phone **is** a move (D-55); the app warns before "Delete everything" while it holds a seat.
- **Cooldown and `next_move_at`:** every move sets `last_moved_at = now` and `next_move_at = ceil_hour(now + 30 d)`, the next whole UTC hour (R3-4). A restore or sign-in move is allowed only if `next_move_at` is null or `now ≥ next_move_at`. The server enforces exactly the rounded value it returns, so `nextMoveAt` in the 409 and in the token agree with enforcement and never reveal the exact time of the last move. `last_moved_at` is never sent to the app.
- **Refused move:** nothing that affects Gold is written. The caller becomes a **pending claimant** (`seat_claimants`, up to **3** per purchase, each kept **7 days**; a fourth replaces the oldest; a repeat by the same install refreshes its entry). The call fails with **`409 MOVE_COOLDOWN`** and `nextMoveAt` (restore), or returns 200 without Gold and with `nextMoveAt` (sign-in, R3-5). A refused request is never a move (EC-66).
- Every move writes a `purchase_events` row `seat_move:<restore|signin|support|account_attach|verify>`; a rebind writes `seat_rebind:<restore|signin>`.
- **Who sets `next_move_at`** (all of them restart the 30-day window):
  - restore and sign-in moves;
  - the **support move**, including a correction move (D-56, (f));
  - the **account-attach reclaim** (D-58, D-61(b)), which bypasses a running cooldown but restarts the window, at most once per purchase ((c));
  - a **plan change from another install** that moves the seat (D-59, below).
- **Not a move:** the first bind, a same-holder refresh, and the iOS same-phone rebind (g). These leave `last_moved_at` and `next_move_at` unchanged.
- **Plan changes and new payments from another install (D-59, D-61(a)).** A verify is a *new payment from this install* when the store proves this install made it (`obfuscatedExternalAccountId` / `appAccountToken` = HMAC(installId)) and it is either a Google successor (`linkedPurchaseToken` names an existing purchase) or an Apple transaction with a `transactionId` not yet seen for that `originalTransactionId` and `transactionReason = PURCHASE` (an upgrade, downgrade, crossgrade or re-subscription). If the purchase's seat (for Google: the predecessor's seat, which the successor inherits together with `account_id`, `attach_reclaim_used_at` and `next_move_at`) is held by another install:
  - **no cooldown running:** the seat moves to the paying install (`seat_move:verify`, sets `next_move_at`), and the old holder gets `status: moved`;
  - **cooldown running (D-61(a)):** the seat **stays** on the current holder, which keeps Gold on the new plan. The paying install becomes a pending claimant, and the verify response is `200` with `seatHeldElsewhere: true` and `nextMoveAt`.
  - **Never refused:** in both cases the purchase is verified and acknowledged first (BR-GOLD-06); the seat decision never blocks or fails the payment path.
- **Seat churn (old R2-4) is gone:** every holder change by a user counts toward the cooldown, so two sharers get at most one hand-over per 30 days, and only one of them holds Gold at a time.

**(b) Entitlement lifetime and trusted time (BR-GOLD-03, BR-GOLD-07, FR-GOLD-04, D-60, NFR-SEC-08).**
- **Full seats** (every plan, lifetime included): `exp ≤ iat + 3 d` (subscriptions: also `≤` the store expiry), `graceUntil = exp + 4 d`. A token is honoured for **at most 7 days** of trusted time after it was issued.
- **Basic-integrity seats** (`proof = basic`): `exp ≤ iat + 2 d`, `graceUntil = exp + 4 d`, so **at most 6 days**. The basic window was 3 d of `exp` already, so it gets a shorter one than full seats. 2 d + 3 d (5 days) was considered and rejected: with the 12-hour refresh below, a holder's token can be up to 12 h old when it goes offline, which would leave only 4.5 days and break FR-GOLD-04. 6 days is the shortest window that keeps at least 5 offline days with the 12 h refresh and still leaves margin for one quick reboot ((h)).
- **Refresh cadence (tightened for D-60):** the app calls `GET /v1/entitlement` whenever it runs online (start, resume, background task) and its cached token is **at least 12 h old**, and `POST /v1/sync` re-issues the token when the cached one is more than 12 h old or anything changed. A holder that was online with the app running at time *t* therefore holds a token at most 12 h old at *t*, so it keeps Gold offline until at least *t* + 6.5 days (full) or *t* + 5.5 days (basic), minus any reboot charges ((h)). That meets FR-GOLD-04's 5 days. Load: about 2 entitlement calls per active install per day, about 2.3 req/s at 100k daily installs.
- **Trusted time (R3-1, D-60(c), NFR-SEC-08):** the app evaluates `exp` and `graceUntil` against a **trusted-time high-water mark** `hw`, not the device's wall clock; the contract is in `backend-api.md` §4.3 *Trusted time*, and its residuals are in (h).
- **Worst-case overlap (D-52 (d), D-60, FR-GOLD-08 acceptance):** the server never issues a token covering a purchase to an install that doesn't hold its seat, and never holds more than one seat.
  - **Old phone online:** it gets `status: moved` at its next refresh, which happens within 12 h of the app running online and in practice at the next start.
  - **Old phone offline, clock untouched:** it keeps Gold only until the `graceUntil` of the last token it received before the move, so **at most 7 days after the move** (6 days for a `basic` seat).
  - **Old phone offline, clock set back:** Gold is withheld as soon as the rollback is seen (wall clock more than 10 min below `hw`). Otherwise `hw` advances with the device's monotonic clock and the 7-day bound holds in *counted* time ((h)).
  - This is the only window in which two phones show Gold for one purchase. It replaces the 14-day bound of the round-3 design.

**(c) Account-linked purchases (D-46, D-54, D-58, D-61(c), FR-ACCT-05).**
- **Account rule:** a purchase with `account_id` set moves only to an install that is linked to that account and presents its account token. Otherwise the restore item is `account_required` (EC-65) and nothing moves. Restore never changes `account_id`.
- **Attach (link) only from the buying install** (P3, D-54): sign-in sets `account_id` only on purchases where `account_id IS NULL` and `purchases.install_id` is the signing-in install (`account_linked_by = 'signin'`). If the buying install is gone, support links the purchase ((f)).
- **Account-attach reclaim (R2-2(a), D-58, D-61(b), R3-3):** after attach, the seat must be on an install linked to the account. If the holder is the buying install, or another install linked to the same account, it stays. Otherwise:
  - if `purchases.attach_reclaim_used_at IS NULL`, the seat returns to the buying install **even inside a running cooldown**. The server sets `attach_reclaim_used_at = now` and `next_move_at` (the reclaim counts as the move, D-61(b)), and writes `seat_move:account_attach`. The previous holder gets `status: moved`. `attach_reclaim_used_at` is never cleared, account deletion included, so the free reclaim happens **at most once per purchase** (D-58, EC-72);
  - otherwise the return is an ordinary sign-in move under the cooldown. If refused, the seat stays and the buying install becomes a pending claimant.
- **Sign-in seat:** sign-in on an install linked to the account moves the seat of each account-linked purchase to that install, under the cooldown, with `proof = account`. The ID token is the proof, so no attestation is needed. This is how Gold crosses platforms (FR-GOLD-07).
- **Sign-out pauses account-linked Gold (D-61(c), FR-ACCT-03):** signing out doesn't release or move the seat. The server includes an account-linked purchase in an install's entitlement only when the request carries a valid account token for **that** account (`Zaghlol-Account`), so a signed-out holder gets that purchase reported as `paused`. The app drops its cached token at sign-out and uses the fresh token the sign-out response returns. Signing in again on the holder is a same-holder refresh: Gold resumes and nothing moves (EC-73). Unlinked purchases are unaffected.
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
- **Strict JSON (R2-6, R3-8):** the server parses the restore body once, with duplicate member names (at any depth, `attestation` included) and lone (unpaired) UTF-16 surrogates rejected as **`400 VALIDATION_FAILED`**. Duplicate rejection is explicit: System.Text.Json accepts duplicates by default, so the API parses with `JsonDocumentOptions.AllowDuplicateProperties = false` (.NET 10) or an equivalent reader pre-pass, and adds its own lone-surrogate check. It computes JCS over **that** parsed object (minus `attestation`) and binds the DTO from the same object, so the hashed and the processed body can't differ. Dart (T-145) and .NET (T-132) must pass the shared vectors in `backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json`, which a contract test also checks. T-132 adds an endpoint test that posts every `invalid` vector to `/v1/purchases/restore` and expects `400 VALIDATION_FAILED`; T-145 adds the Dart counterpart (its canonicalizer and its strict parser reject the same vectors).
- **Basic integrity (R-19):** a Play verdict with `MEETS_BASIC_INTEGRITY` but not `MEETS_DEVICE_INTEGRITY` (often a custom ROM) may hold the single seat, under the same cooldown, with `proof = basic`, `exp ≤ iat + 2 d` and a 6-day window ((b)). Refusing these devices outright would lock out paying owners. The cooldown already bounds what a weaker device can do, and the shorter window limits the offline overlap after it loses the seat. The former 1-restore-per-day bucket is dropped, because each move already counts.
- **No verdict, App Attest unsupported:** `422 DEVICE_ATTESTATION_FAILED` and no Gold (EC-66). The way back is sign-in for an account-linked purchase, or support.
- **Outages and quota:** `503 UPSTREAM_UNAVAILABLE` with `Retry-After`, never `422`. The app retries platform-transient errors with back-off. Existing holders keep their cached Gold. T-140 checks the Play Integrity quota before launch and alerts at 50 %.
- **Verify does not require attestation.** The store-side binding to HMAC(installId) already proves that the buying install made the purchase (`PURCHASE_NOT_OWNED` otherwise). Attestation would add failure modes to the payment path (BR-GOLD-06) with no gain.


**(e) Data.** Only the proofs are sent (BR-SYNC-03 amended, D-45, D-55). The server stores the App Attest public key and counter, hashes in `replay_guard`, and, per seat, one keyed hash of the holder's seat key ((g)). It stores no device identifier and no verdict payload. Proofs are never logged.

**(f) Support move, link and correction (D-56, D-57, R3-2, R3-9).**
- **Endpoints** (role **`support_agent`**, distinct from read-only `support_viewer`): `POST /admin/v1/support/seat:move` moves a seat past the cooldown, optionally linking an unlinked purchase to the target install's account (FR-ACCT-05). `POST /admin/v1/support/purchase:detach` removes a link that support made. One agent may act; there is no second approver (D-57(c)).
- **Ownership check (D-57(a)(b)):** both calls require `ownershipCheck`, the store order ID the user gives support (a Google Play `GPA.…` order ID or an Apple order ID from the receipt e-mail). The server checks it **live** before changing anything:
  - **Google Play:** `orders.get` (Play Developer API v3 `orders` resource); the order's `purchaseToken` must be the purchase's token or one of its `linkedPurchaseToken` chain, and the order state must not be `CANCELED`, `REFUNDED` or `PENDING_REFUND`;
  - **Apple:** App Store Server API **Look Up Order ID** (`GET /inApps/v1/lookup/{orderId}`); `status` must be `0` and one verified signed transaction must carry the purchase's `originalTransactionId`.
  A failed check is `422 OWNERSHIP_CHECK_FAILED` and changes nothing. An upstream outage is `503 UPSTREAM_UNAVAILABLE`. The order ID is **never persisted or logged**: it is held in memory for the call only, it is excluded from request logging and traces, the audit row records only `ownership_check: "order_id"` and its outcome, and `zaghlol-ops` reads it from a no-echo prompt, never from a command-line argument, so it can't reach shell history.
- **Who can receive the seat** (any other target is `409 ADMIN_CONFLICT`):
  1. one of the purchase's **pending claimants** (up to 3, each from the last 7 days): an install whose own restore, sign-in or plan-change verify passed attestation, store and account checks but was refused for the cooldown. Support picks one explicitly by `toInstallId` (the user's support code); the lookup marks each claimant;
  2. for **attach alone** (no move), the current holder, but only under the attach gate below;
  3. for a **correction** (`reasonCode: correction`, `correctsAuditId` set): the `from_install` of the referenced `support_seat_move` audit row for the same purchase, if that install still exists.
- **Account rule:** for an account-linked purchase, the target must be linked to that account.
- **Attach gate (D-57(d)):** `attachToAccount` is allowed only when the purchase has no account, the target is linked to an account, and the **buying install is gone or silent**: `purchases.install_id IS NULL`, or that install is tombstoned, or its `last_seen_at` is at least 30 days ago. Otherwise `409 ADMIN_CONFLICT`, and the owner links from the buying phone (D-54). A support attach sets `account_linked_by = 'support'`. It is not a reclaim and doesn't touch `attach_reclaim_used_at`.
- **Effect (D-56):** the seat moves to the target (`seat_move:support`), and the move **restarts the window** (`last_moved_at = now`, `next_move_at = ceil_hour(now + 30 d)`). A correction move does the same. The losing install gets `status: moved` with **`movedBy: "support"`** at its next refresh. The app then shows that support moved Gold, with the support link and the support code, and no operator data (D-57(f)).
- **Correction path (D-57(e)):**
  - **move back:** `seat:move` with `reasonCode: correction`, `correctsAuditId` = the move being reversed, and `toInstallId` = that row's `from_install`;
  - **detach:** `purchase:detach` with `correctsAuditId` = the support attach being reversed. Only a link made by support (`account_linked_by = 'support'`) can be detached; a self-service link from the buying phone can't. Detach sets `account_id = NULL` and leaves the seat where it is. A re-link is then an ordinary `seat:move` with `attachToAccount` under the attach gate.
  - Every correction row references the row it reverses (FR-BE-11).
- **Audit:** every call, successful or refused, writes one `audit_log` row naming the operator: `action ∈ {support_seat_move, support_detach}`, `target` = the purchase UUID, `details` = `{from_install, to_install, reason_code, ticket_ref, attached_account_id?, detached_account_id?, corrects_audit_id?, ownership_check: "order_id", ownership_outcome: pass|fail|unavailable, outcome}`. It never holds an e-mail, an order ID or free text, and it is kept **exactly 1 year** (D-47 rules).
- **Operator sign-in (R3-9):**
  - `support_agent` requires **phishing-resistant MFA** (FIDO2 / passkey). The IdP enforces it (Entra authentication strength "Phishing-resistant MFA", or Google Workspace security-key enforcement for the support group), and the API checks the token's `amr` / `acr` claim for every `support_agent` operation.
  - `zaghlol-ops` signs in with **authorization code + PKCE and a loopback redirect** (RFC 8252). The device-code grant is disabled for the CLI's client, so a phished device code can't mint an operator token.
  - `support_agent` is assigned only to named staff, never to shared or service accounts, and assignments are reviewed quarterly (T-137 runbook).
- **Interim path (D-37, R-21):** until the admin web app ships after launch, support uses these endpoints through `zaghlol-ops support move | detach`. Owners: T-136 (endpoints, role, `amr` check and audit), T-137 (CLI, runbook, quarterly review, helpdesk), T-132 (seat service).
- **Alerts** carry the purchase UUID only:
  - more than 2 support moves for one purchase in 90 days. D-56 already makes each one cost the cooldown. **Runbook action:** within 2 business days a support lead (not the acting agent) reviews the tickets and audit rows; if they find abuse or error, they reverse it through the correction path and record the finding on the ticket;
  - more than 20 support actions by one operator in a day. **Runbook action:** suspend that operator's `support_agent` role pending review;
  - any `ownership_outcome: fail` streak (more than 5 per operator per day);
  - a `MOVE_COOLDOWN` refusal spike;
  - an attestation-failure spike by reason code;
  - Play Integrity quota above 50 %.
- **Privacy note (info, T-137, OQ-16):** a support ticket links the install ID (support code) and the order ID to the user's contact details in the helpdesk tool. The privacy notice says so. T-137 records whether the helpdesk vendor is a PDPL processor and gets a processing agreement, and sets ticket retention so that order IDs aren't kept longer than the ticket needs.

**(g) Same-iPhone recognition (D-55, closes OQ-19(a)).**

| Option | How | Privacy (D-45, BR-SYNC-03) | Verdict |
|---|---|---|---|
| 1. A reinstall is a new install | Nothing new | No new data | **Android** (D-55): no safe equivalent there |
| 2. Random Keychain secret, HMAC proof | 256-bit secret; the server stores an HMAC verifier per seat | Derived value only | Rejected for iOS: the secret is extractable on a jailbroken phone and can be planted on a second one, making cooldown-free swaps possible. The server also has to hold verifier secrets |
| 3. **Secure Enclave seat key per install, kept in the Keychain** | P-256 key generated in the Secure Enclave, ThisDeviceOnly; the app proves possession by signing the request binding | A per-install public key plus a signature; the server stores only a keyed hash per seat | **Chosen for iOS** |
| 4. One Secure Enclave key per device | As 3, with a single key | The public key would be a stable device identifier across purchases and requests | Rejected |
| 5. Android Block Store secret | Through Google Play services | As 2 | Rejected: it is copied to a **new** phone during device restore, so two phones would look like "the same phone" |
| 6. `ANDROID_ID`, identifierForVendor or another device identifier | Read from the OS | A device identifier: forbidden by FR-GOLD-09 and BR-SYNC-03 | Rejected |

- **The secret (D-55's "install secret").** Each iOS install creates one **seat key**, a `SecureEnclave.P256.Signing.PrivateKey`. The private key never leaves the Secure Enclave, and its wrapped `dataRepresentation` is kept in a Keychain generic-password item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable. Such items survive deleting and reinstalling the app, but not a device erase, and they never move to another device (backup, iCloud Keychain or device-to-device transfer). The app keeps up to **5** seat keys: this install's own key and the keys of up to 4 earlier installs on this iPhone, newest first.
  - **"Delete everything" keeps the seat keys** and deletes everything else (D-55: a "Delete everything" on the same iPhone is not a move). They hold no financial data and no account data.
  - **Keychain survival after app deletion** is current iOS behaviour, not a documented guarantee. If Apple changes it, iOS reinstalls behave like Android (the move is spent), and nothing else breaks.
- **The proof (the D-55 field for BR-SYNC-03):** `seatKeys`, an array of `{publicKey, signature}`.
  - `publicKey` is the X9.63 uncompressed P-256 point, 65 bytes in base64url.
  - `signature` is ECDSA P-256 / SHA-256 in IEEE P1363 form (r‖s, 64 bytes, base64url) over `"zaghlol-seat-v1" ‖ 0x00 ‖ op ‖ 0x00 ‖ installId ‖ 0x00 ‖ challenge`. `op` is `verify`, `restore` or `signin`. `installId` is this install's own ID, and the server takes it from the install token. `challenge` is 32 bytes:
    - for restore, the install-bound `bodyHash`, so the proof is bound to this install, this body and its single-use attestation;
    - for verify, SHA-256 of the `signedTransaction` string;
    - for sign-in, SHA-256 of the raw nonce, which is single-use (`replay_guard`).
  - Element 0 is the calling install's own key. The others are earlier installs' keys.
  - It is sent **only by iOS installs**: in `POST /v1/purchases/verify` (element 0 only), in `POST /v1/purchases/restore` inside `attestation` (so it is outside the hash and signs the hash, like the App Attest assertion), and in `POST /v1/accounts/signin`.
  - Shared vectors: `backend/tests/Zaghlol.Contract.Tests/vectors/seat-proof-v1.json`.
- **Server storage:** `purchase_seats.device_key_hash = HMAC-SHA256(K_seat, purchase_id ‖ publicKey)`, where `K_seat` is a dedicated KMS key. It is written from element 0 whenever an iOS install becomes or stays the holder with a valid proof, and set to `NULL` when a holder without seat keys (Android, or an iOS install whose Secure Enclave failed) takes the seat. It is **kept when the seat goes vacant**, so a "Delete everything" (which deletes the install) followed by a restore on the same iPhone is still recognised. Because of the per-purchase HMAC, rows for different purchases can't be joined, and the raw public key is never stored.
- **Rebind (not a move):** a caller that isn't the holder presents, with a valid signature, a key whose hash equals the seat's `device_key_hash`. The seat then passes to the caller **without checking or restarting the cooldown** (`seat_rebind:<restore|signin>`, `last_moved_at` and `next_move_at` unchanged), and the stored hash is replaced by the caller's element 0. The old install, if it still exists, gets `status: moved`. Attestation (restore), the ID token (sign-in) and the account rule still apply in full; a rebind skips only the cooldown.
- **What the server learns:** a rebind tells it that two installs were on the same iPhone, which is exactly what D-55 asks for. Element 0 is new for every install, and a key never appears in any request after its install is replaced, so no key works as a stable device identifier across apps, across purchases or over time. Matching runs only against the seats of the purchases in the request.
- **Keychain or Secure Enclave loss** (device erase, Keychain reset, a key that can't be read): the app creates a new key and the restore is an ordinary move, or `409 MOVE_COOLDOWN`. If the Secure Enclave fails or is missing (Simulator), `seatKeys` is omitted and the request works as on Android. No lock-out results either way.
- **Android:** a reinstall or "Delete everything" is a new install and spends the move. The app warns first: the "Delete everything" confirmation names the next-move date when this install holds a seat (the token's `nextMoveAt`), and the help copy covers reinstalling. UX owns the wording.

**(h) Trusted time on the device: residuals (R3-1).** The contract is in `backend-api.md` §4.3. What it guarantees:
- **Clock moved back:** a wall clock more than 10 minutes below `hw` withholds Gold ("connect to check Gold") until a fresh signed server time arrives. Time-zone and DST changes don't move the epoch clock, so they never trigger it (EC-70).
- **Clock moved forward:** Gold is never extended (`hw` only grows), and an honest correction afterwards is cured by the next online refresh.
- **Powered on, app closed:** the monotonic clock keeps counting, so the time is counted.
- **Reboots:** the monotonic clock restarts at boot. A detected reboot adds `max(uptime since boot, 6 h)`. The 6-hour minimum stops "reboot before every use" from making each session cost only its own minutes. A legitimate holder loses at most 6 h per quick offline reboot, inside the 0.5–1.5-day margin of (b).
  - **Android** detects every reboot through `Settings.Global.BOOT_COUNT` (API 24+, below minSdk 26).
  - **iOS has no public boot identifier** (`kern.bootsessionuuid` was never API and is gone in iOS 18). A reboot is detected when the monotonic clock is lower than its stored value, or when the boot reference `wall − monotonic` shifts by more than 10 minutes.
- **Residual (iOS, accepted under R-19):** an attacker who keeps the phone offline, reboots, waits until uptime exceeds the previous record without opening the app, and then sets the clock to within 10 minutes of a computed value can make a reboot go undetected. Each such cycle gains only time during which the app wasn't running. Time with the app running is always counted, so total Gold use after the move stays at most 7 days of app-running time, and the required wait grows with every cycle. Apple offers no trusted-time API (Apple DTS, Developer Forums thread 774658).
- **Residual (both platforms):** a rooted or jailbroken device that edits the encrypted `secure_state` or hooks the clock calls is out of scope (MASVS-R light; security-model §1).

**Consequences.**
- **T-122:** `purchase_seats` (`next_move_at`, `device_key_hash`), `seat_claimants`, `purchases.attach_reclaim_used_at` and `account_linked_by`, `installs.registration_key_hash` / `registration_body_sha256`, `idempotency_records` (account scope), `app_attest_keys`, `replay_guard`.
- **T-130:** Play Integrity decode, with optional verdict fields ignored; Play `orders.get` for the ownership check.
- **T-131:** App Attest validation (in-house CBOR + X.509) over the install-bound hash; App Store Server API Look Up Order ID.
- **T-132:**
  - the seat service: bind, move, rebind, the rounded cooldown, claimants, the plan-change move or stay, the attach reclaim once per purchase, `moved` / `movedBy` / `paused` tokens;
  - the 3 d / 2 d `exp` with 4 d grace;
  - seat-key proof verification against the shared vectors;
  - the strict JSON pre-pass, with an endpoint test for every invalid vector.
- **T-135:**
  - sign-in commits the link, attach and reclaim even when the move is refused (200 with `nextMoveAt`), and `replay_guard` is inserted before and outside the seat transaction;
  - an `accountToken` whose account no longer exists is rejected;
  - sign-out returns a fresh entitlement;
  - account deletion deletes that account's `idempotency_records`.
- **T-136:** `support_agent` with FIDO2 `amr` check; `seat:move` and `purchase:detach` with the live ownership check, attach gate, claimant choice, correction rules, audit (1 year) and alerts. **T-137:** `zaghlol-ops support move | detach` (PKCE loopback, no-echo order-ID prompt), the runbook (alert actions, quarterly role review), and the helpdesk processor check. **T-139:** purge support audit rows after 1 year; purge expired claimants and idempotency rows.
- **T-144:** trusted-time high-water mark and the `TrustedClockHostApi`; Gold only while `hw < graceUntil` and not tampered; the 12 h refresh; `moved` with `movedBy`; `paused` and the sign-out token drop; unit tests for rollback, reboot, offline and forward-jump cases.
- **T-145:** restore sends the install-bound attestation and, on iOS, `attestation.seatKeys`; `MOVE_COOLDOWN` and help UX; system-CA-only network config; the Dart strict parser over the shared invalid vectors; a CSPRNG `Idempotency-Key`; the Android "Delete everything" warning.
- **T-147:** Google nonce; the "sign in on this phone" prompt; sign-in 200 with `nextMoveAt`; iOS `seatKeys` on sign-in.
- **T-140:** quota check and the optional-verdict checklist.
- **New app task (C4):** native `AttestationHostApi` (`platform-channels.md` §4a), plus the iOS seat-key functions in `SeatKeyHostApi` (§4b): Secure Enclave key lifecycle, a reinstall-survival device test, and "Delete everything" keeping the seat keys.
- **New backend task (C4):** attestation verifier module (Play Integrity decode, App Attest attestation and assertion) and the seat-key verifier, with fakes for tests, split out of T-130/T-131.

Sources:
- [Play Integrity verdicts](https://developer.android.com/google/play/integrity/verdicts) (`requestDetails.requestHash`, `timestampMillis`, `appRecognitionVerdict`, `deviceRecognitionVerdict`; optional verdicts), checked 2026-11-05.
- [.NET client `Google.Apis.PlayIntegrity.v1`](https://developers.google.cn/api-client-library/dotnet/apis/playintegrity/v1?hl=en).
- [Android Block Store](https://developer.android.com/identity/block-store): data persists across reinstall only with Backup enabled, and is transferred during device restore; checked 2026-11-06.
- [Play Developer API `orders` resource](https://developers.google.com/android-publisher/api-ref/rest/v3/orders) (`get`, `batchget`; `Order.purchaseToken`, `state`), checked 2026-11-06.
- [App Store Server API: Look Up Order ID](https://developer.apple.com/documentation/appstoreserverapi/look-up-order-id) (`GET /inApps/v1/lookup/{orderId}`).
- [Apple Developer Forums 774658, "Time verification in iOS 18+"](https://developer.apple.com/forums/thread/774658): no trusted-time API; `kern.bootsessionuuid` isn't API and was removed in iOS 18; checked 2026-11-06.
- [`JsonDocumentOptions.AllowDuplicateProperties`](https://learn.microsoft.com/en-us/dotnet/api/system.text.json.jsondocumentoptions.allowduplicateproperties) and [`JsonSerializerOptions.AllowDuplicateProperties`](https://learn.microsoft.com/en-us/dotnet/api/system.text.json.jsonserializeroptions.allowduplicateproperties) (.NET 10).
