# ADR-012: Purchase verification & entitlement signing

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
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
- **Token:** ES256 JWS `{sub, acct, plan, status, exp, graceUntil}`, grace 7 days (A-38). Lifetime tokens roll every 30 days.
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
- **Restore** skips the install-binding check (`obfuscatedExternalAccountId` / `appAccountToken`), because after a phone change the binding names the old install. *Superseded by Part B:* possession of the token is no longer proof of ownership, and the "3 moves per 30 days" cap is replaced by seats.
- Per-item failures fold into an aggregate `status`. The only 422 is `DEVICE_ATTESTATION_FAILED` (Part B).
- *Abuse limits (security review, 2026-11-05):*
  - a restore bucket of 5/hour per install;
  - a per-purchase limit of 10 attempts/day, keyed by SHA-256 of the token or `originalTransactionId`;
  - a global Play / App Store call budget with priority for verify and the ack sweeper. When the budget is short, restore gets `503` with `Retry-After`.

**Consequences (Part A).** T-130 implements the v2 calls. T-132 implements restore. T-145 sends items instead of bare tokens. Sources: Google Play Developer API reference for [`purchases.productsv2.getproductpurchasev2`](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2) and the [one-time product lifecycle guide](https://developer.android.com/google/play/billing/lifecycle/one-time), checked 2026-11-05.

### Part B: Gold anti-sharing and restore attestation (D-45, D-46; security review Findings 1 and 9)
**Context.** Every restore accepted any genuine store token. A token posted online could give Gold to unlimited installs. The store binding can't help, because after a phone change it names the old install. The PO decided (D-46):
- at most 3 installs per purchase at once;
- account-linked purchases move only between that account's installs;
- device attestation is required on restore.

BR-SYNC-03 is amended to allow the attestation proof (D-45). FR-GOLD-02 now counts a genuine token from an excluded or unattested install as *replayed*.

**Options.**
1. **Velocity cap** (3 moves per 30 days). This is the earlier design. It doesn't bound concurrent sharing, and it can lock out an owner who reinstalls a lot.
2. **Seats, refusing the 4th.** This is a hard bound, but a stolen or stale seat locks the real owner out until it lapses.
3. **Seats, evicting the least recently active, plus attestation and the account rule.** This is chosen.
4. **Server-issued challenge for attestation.** It's stronger freshness for App Attest, but needs an extra endpoint and state. Body binding plus Play's timestamp, App Attest's counter and `replay_guard` already stop replay.

**Decision: option 3**, specified in `backend-api.md` §4.3 (restore), §4.6 (sign-in) and `backend-schema.md` (`purchase_seats`, `app_attest_keys`, `replay_guard`).

**(a) Seats.**
- At most **N = 3** live seats per purchase, across platforms and including sign-in seats (FR-GOLD-07).
- A *move* is a binding change to a different install. Restoring on the same install is not a move.
- When a 4th install restores, the server first reclaims a dormant seat (its holder's newest token is past `graceUntil`). Otherwise it **evicts the least recently active** seat: `basic` seats go first, and the caller's seat is never evicted.
- We evict rather than refuse, so the real owner is never locked out.
- The evicted install gets a `status: moved` token at its next online refresh (within 24 h). Offline, it loses Gold at `graceUntil` (≤ 37 d).
- Releases also happen through install deletion and the 12-month inactive-install purge.

**(b) Entitlement lifetime.**
- `exp` ≤ `iat` + 30 d for every plan (subscriptions: also ≤ the store expiry; `basic` seats: ≤ `iat` + 7 d). Grace stays 7 d (BR-GOLD-03).
- Note on FR-GOLD-08's "at no moment more than 3": the server never grants more than 3 seats and never issues a token for an evicted seat. A token issued earlier stays verifiable offline until `graceUntil`. That residual is bounded by (b), as the PO accepted in D-46.

**(c) Account-linked purchases.**
- Restore re-binds a purchase with `account_id` only to an install presenting that account's token. Otherwise the outcome is `account_required` (EC-65).
- Restore never changes `account_id`.
- Sign-in sets `account_id` only from the purchasing install (`purchases.install_id`). If that install is gone, sign-in sets it from the sole live, attested seat holder. It never sets it from a restore-acquired seat while other seats exist.
- Sign-in gives the install a seat (`proof = account`) with the ID token as the proof.
- Owners get "sign in to protect your Gold": the app suggests it once after purchase.

**(d) Attestation on restore** (FR-GOLD-09).
- Every restore carries a proof bound to `SHA-256(JCS(body without attestation))`.
- **Android:** Play Integrity standard request (`requestHash`). The server uses `decodeIntegrityToken` and checks the hash, package, timestamp ≤ 5 min, `PLAY_RECOGNIZED` and `MEETS_DEVICE_INTEGRITY`. Each token is single-use.
- **iOS:** App Attest assertion (`clientDataHash`), checked against the key registered per install, with an increasing counter. `attestationObject` is sent on a key's first use and validated to the Apple App Attestation Root CA.
- **App Attest key lifecycle:** one key per install; `keyId` in the Keychain, this device only, not synchronized. Re-attest on `invalidKey`, on an unknown-key `422`, and on a new install.
- **New problem code:** `422 DEVICE_ATTESTATION_FAILED`. The client retries once (fresh token, or new key + attestation), then shows help and offers sign-in.
- **Fallbacks** (R-19, EC-66):
  - **Play `MEETS_BASIC_INTEGRITY` only:** a `basic` seat. One per purchase, never evicts a stronger seat, `exp` ≤ 7 d, 1 restore/day.
  - **No integrity verdict, or App Attest unsupported:** no Gold through restore, as EC-66 requires. The way back is sign-in, for account-linked purchases. We rejected an unattested "reduced path" because FR-GOLD-09 and EC-66 require that a missing attestation grants nothing.
  - **No Google Play services at all:** these devices have no Play Billing, so they hold no Play tokens.
  - **Attestation-service outages and quota:** `503 UPSTREAM_UNAVAILABLE` with `Retry-After`, never `422`. The app retries platform-transient errors with back-off. Existing installs keep their cached Gold. Play Integrity quota is checked before launch (T-140), and an alert fires at 50 %.
- **Verify does not require attestation.** The store-side binding to HMAC(installId) already proves that the buying install made the purchase, and a token bound to another install fails with `PURCHASE_NOT_OWNED`. Adding attestation would put new failure modes on the payment path (BR-GOLD-06) with no security gain.

**(e) Data.** Only the proof is sent (BR-SYNC-03 amended, D-45). The server stores:
- the App Attest public key and counter;
- hashes in `replay_guard`.

It stores no device identifier and no verdict payload. Proofs are never logged.

**(f) Alerts** carry the purchase UUID only:
- more than 3 evictions per purchase in 30 days;
- an attestation-failure spike by reason code;
- Play Integrity quota above 50 %.

**Consequences.**
- **T-122:** new tables `purchase_seats`, `app_attest_keys` and `replay_guard`.
- **T-130:** Play Integrity decode.
- **T-131:** App Attest attestation/assertion validation (in-house CBOR + X.509).
- **T-132:** seats, eviction, `moved` tokens, the 30-day `exp`, the account rule and the restore aggregate.
- **T-135:** sign-in seats and the attach rule.
- **T-144:** handle `status: moved` and the 30-day `exp` refresh.
- **T-145:** restore sends the attestation; retry and help UX.
- **T-147:** the "sign in to protect your Gold" prompt.
- **T-140:** quota check.
- **New app task (C4):** native `AttestationHostApi` (`platform-channels.md` §4a), covering Play Integrity standard requests, the App Attest key lifecycle and device tests on real hardware.
- **New backend task, or a split of T-130/T-131:** an attestation verifier module with fakes for tests.

Sources:
- [Play Integrity verdicts](https://developer.android.com/google/play/integrity/verdicts) (`requestDetails.requestHash`, `timestampMillis`, `appRecognitionVerdict`, `deviceRecognitionVerdict`), checked 2026-11-05.
- [.NET client `Google.Apis.PlayIntegrity.v1`](https://developers.google.cn/api-client-library/dotnet/apis/playintegrity/v1?hl=en).
