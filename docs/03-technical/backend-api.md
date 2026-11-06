# Backend API — v1 Contracts

The source of truth during Phase 5 is `backend/openapi/zaghlol-v1.yaml`, generated from this document and kept in sync by contract tests.

- **Base URL:** `https://api.zaghlol.app` (production), `https://api.staging.zaghlol.app`.
- **Transport:** HTTPS only, TLS 1.2+ (TLS 1.3 preferred), HSTS.
- **Encoding:** JSON (UTF-8) request and response bodies; gzip/brotli responses.

## 1. Conventions

| Topic | Rule |
|---|---|
| Versioning | Path prefix `/v1`. Additive changes only within v1, and clients ignore unknown fields. A breaking change means `/v2`, with v1 kept for the support window of the oldest supported app (≥ 12 months). |
| Client headers | `Zaghlol-App: <platform>/<appVersion> (<build>)`, `Zaghlol-Install: <installId>`, `Accept-Language` **not** sent (copy is localized on device). |
| Authentication | `Authorization: Bearer <installToken>` on all install-scoped calls; `Zaghlol-Account: <accountToken>` additionally when signed in. See §3. |
| Idempotency | `Idempotency-Key: <ULID>` on `POST /v1/purchases/verify`, `/v1/installs`, `/v1/accounts/signin`. A stored result is keyed by **(installId, operationId, Idempotency-Key)** and records **SHA-256 of the request body bytes**. `installId` is the install that the install token authenticates (for `POST /v1/installs`, the `installId` in the body). A replay within 24 h returns the stored result only when all four match. The same key from a **different install** is simply a different key: it is processed as a new request and never sees another install's stored body. The same install, operation and key with a **different body hash** gives **`409 IDEMPOTENCY_KEY_REUSED`**, never the stored body (R2-8). This matters most for sign-in, whose stored body holds an account token: a replay needs the same install token **and** the identical ID token and nonce. Only final results are stored (2xx, 409 and 422); `429` and 5xx are not, so a retry runs again. Records live in `idempotency_records` (`backend-schema.md`) and are purged after 24 h. |
| Response signing | Security-relevant responses carry `Zaghlol-Signature: kid=<kid>; alg=ES256; sig=<base64url>`, an ECDSA P-256 signature over the **exact response body bytes** after decompression. The app verifies it against embedded public keys (ADR-012/013) and drops unsigned or invalid bodies. |
| Time | `serverTime` (RFC 3339 UTC) in every response body. The app stores it to drive the 24 h throttle (EC-43). |
| Errors | RFC 9457 `application/problem+json`: `{type, title, status, code, detail?, retryAfterSeconds?}`. `code` is a stable `UPPER_SNAKE` string (§6). Error bodies never echo request data. |
| Rate limits | Per install token and per /24 IP (token bucket). `429` with `Retry-After`. Extra buckets: `POST /v1/purchases/restore` 5/hour per install, plus 10 restore attempts/day per purchase (keyed by SHA-256 of the token or `originalTransactionId`). Outbound Play and App Store calls share a global budget in which verify and the acknowledge sweeper have priority over restore (§4.3). |
| Request size | ≤ 64 KB, except `/v1/notifications/*` (≤ 256 KB). |
| Unknown fields in requests | **Rejected** (`400 UNKNOWN_FIELD`) in every body whose shape Zaghlol defines (app and operator calls), so the app can't accidentally send more than BR-SYNC-03 allows. **Ignored** in the three bodies whose shape Google or Apple define: the Pub/Sub push envelope (`/v1/notifications/google`), the ASSN V2 body (`/v1/notifications/apple`) and Apple's `form_post` (`/v1/apple/android-callback`). The server reads only the listed fields there and never stores or logs the rest. These operations carry `x-third-party-body: true` in the OpenAPI file, and a contract test checks that no other operation does (ADR-022 amendment). |
| Query strings | Never carry personal data or credentials (e-mails, tokens, ID tokens, codes). The server never logs query strings or raw paths, only the route template (`error-handling-and-observability.md` §3.2). |

## 2. Endpoint summary

| Method & path | Auth | Purpose | Req. |
|---|---|---|---|
| `POST /v1/installs` | none (+ rate limit) | Register install, get install token | FR-BE-01 |
| `DELETE /v1/installs/me` | install | Delete install record (Delete everything) | FR-ONB-08 |
| `POST /v1/sync` | install | Daily: catalog delta + flags + prices + entitlement + outbox upload | FR-SYNC-*, FR-BE-04/05/06/07/10 |
| `GET /v1/catalog/{version}/full` | none (CDN) | Full signed catalog snapshot (first sync, or far behind) | FR-SYNC-02 |
| `POST /v1/purchases/verify` | install | Verify a new purchase; acknowledge; return entitlement | FR-BE-02, FR-GOLD-02 |
| `POST /v1/purchases/restore` | install | Re-verify store purchases on a new phone | FR-GOLD-03 |
| `GET /v1/entitlement` | install (+ account) | Fresh signed entitlement | FR-GOLD-04/06 |
| `POST /v1/accounts/signin` | install | Verify Google/Apple ID token; link; return account token + entitlement | FR-ACCT-01/02, FR-GOLD-07 |
| `POST /v1/accounts/signout` | install + account | Unlink this install from the account | FR-ACCT-03 |
| `DELETE /v1/accounts/me` | install + account | Delete account and links (and revoke Apple token) | FR-ACCT-04 |
| `POST /v1/apple/android-callback` | none (Apple `form_post`) | Sign in with Apple web-flow callback for Android (CR-05) | FR-ACCT-01 |
| `POST /v1/notifications/google` | Google OIDC (Pub/Sub push) | RTDN ingest | FR-BE-03 |
| `POST /v1/notifications/apple` | JWS signature | App Store Server Notifications V2 ingest (prod + sandbox URLs) | FR-BE-03 |
| `GET /v1/health` | none | Liveness / readiness | — |
| `/admin/v1/*` | Operator OIDC + MFA + role | Operator API (§5) | FR-BE-08 |

## 3. Authentication & authorization (API level)

| Principal | Credential | Issued by | Lifetime | Scope |
|---|---|---|---|---|
| **Install** | `installToken`: 32 random bytes, base64url. The server stores only SHA-256(token). | `POST /v1/installs` | Until the install is deleted. Rotated by the server in any response (`rotateInstallToken`) if compromise is suspected. | Own install only: sync, purchases, entitlement, own deletion |
| **Account** | `accountToken`: ES256 JWT `{sub: accountId, iid: installId, iat, exp: +30 d, kid}` | `POST /v1/accounts/signin` | 30 days, silently refreshed in `/v1/sync` responses | Link/unlink/delete own account; read account entitlements |
| **Google Pub/Sub** | Google-signed OIDC JWT (`aud` = our push endpoint, `email` = our push service account) | Google | per request | `/v1/notifications/google` only |
| **Apple ASSN** | `signedPayload` JWS, x5c chain verified to Apple Root CA G3, bundle ID + environment checked | Apple | per request | `/v1/notifications/apple` only |
| **Operator** | OIDC (Google Workspace or Entra ID) with enforced MFA; short-lived access token (≤ 1 h) via device-code flow in `zaghlol-ops` | Company IdP | 1 h | Role-based: `catalog_editor`, `flags_admin`, `support_viewer` (read-only lookup), `support_agent` (audited support seat move, §5.3), `prices_admin`; every write audited |

Authorization rules:
- A call may only read or write rows of its own `installId`, plus rows of `accountId` when the account token matches **and** the install is linked to that account.
- `/v1/notifications/*` never accept bearer tokens.
- Operators have no endpoint that returns installs in bulk.
- Support lookup takes an exact install ID or account e-mail **in a POST body** (never a query string) and returns entitlement status only.

## 4. Contracts

### 4.1 `POST /v1/installs`
```json
// request
{ "installId": "0193f2c4-…-uuid", "platform": "android", "appVersion": "1.0.0" }
// 201 response
{ "installToken": "q3V…base64url", "serverTime": "2026-11-03T18:22:01Z" }
```
- `installId` is generated on device (UUID v4, CSPRNG). If the ID already exists, the server returns **409 `INSTALL_EXISTS`**. The client then regenerates the ID; this happens only after an interrupted delete.
- Called lazily: on first sync, or first purchase, whichever comes first. Onboarding never waits for it.

### 4.2 `POST /v1/sync` (daily, FR-SYNC-01/07)
```json
// request
{
  "catalogVersion": 41,
  "flagsVersion": 7,
  "pricesAsOf": "2026-11-02T09:00:00Z",
  "entitlementIssuedAt": "2026-10-30T10:00:00Z",
  "registryVersion": 12,                       // bundled SMS-template version (diagnostic, BR-SYNC-03 'app version' class)
  "contributions": [                           // only if opted in (D-16); max 50 per call
    { "merchantNorm": "koshary el tahrir", "institutionCode": "nbe", "categoryCode": "dining" }
  ],
  "bankRequests": [ { "institutionName": "Banque du Caire", "country": "EG", "channel": "sms" } ]
}
// 200 response (signed)
{
  "serverTime": "2026-11-03T18:22:02Z",
  "nextSyncNotBefore": "2026-11-04T18:22:02Z",
  "catalog": {
    "fromVersion": 41, "toVersion": 43,
    "mode": "delta",                            // or "full" → client fetches fullUrl (and verifies its own signature)
    "fullUrl": null,
    "ops": [
      { "t": "merchant", "op": "upsert", "id": 812, "canonical": "Koshary El Tahrir", "nameAr": "كشري التحرير", "category": "dining" },
      { "t": "alias", "op": "upsert", "merchantId": 812, "alias": "koshary el tahrir", "match": "exact" },
      { "t": "alias", "op": "delete", "merchantId": 77, "alias": "old alias" },
      { "t": "keyword", "op": "upsert", "keyword": "صيدلية", "lang": "ar", "category": "health", "weight": 60 },
      { "t": "category", "op": "upsert", "code": "subscriptions", "nameAr": "اشتراكات", "nameEn": "Subscriptions", "icon": "repeat", "color": "#7C83D6", "bucket": "obligations", "sort": 9 }
    ]
  },
  "flags": { "version": 8, "values": { "zakah": false, "smart_roi": false, "roi_named_products": false } },
  "prices": {
    "asOf": "2026-11-03T15:00:00Z", "stale": false,
    "gold": [ { "symbol": "XAU24_G", "currency": "EGP", "price": "4820.00" },
              { "symbol": "XAU21_G", "currency": "EGP", "price": "4217.50" },
              { "symbol": "XAU18_G", "currency": "EGP", "price": "3615.00" },
              { "symbol": "XAU24_G", "currency": "USD", "price": "98.40" } ],
    "fx": { "base": "USD", "rates": { "EGP": "48.9500", "SAR": "3.7500", "EUR": "0.9210", "GBP": "0.7840", "KWD": "0.3070" } }
  },
  "entitlement": { "token": "eyJhbGciOiJFUzI1NiIsImtpZCI6ImUxIn0…" },   // present if changed since entitlementIssuedAt
  "accepted": { "contributions": 1, "bankRequests": 1 },
  "accountToken": null                                                    // refreshed token when signed in & < 7 d to expiry
}
```

**Rules:**
- **Size:** the response is ≤ 2 KB when nothing changed (NFR-BE-03). Unchanged blocks are `null`.
- **Server checks:** the server validates every contribution against BR-SYNC-04, and silently drops non-conforming ones (counted in `accepted`).
- **Full catalog:** `mode: "full"` is returned when `catalogVersion` is 0 or more than 20 versions behind. The full snapshot is about 1 MB compressed and signed (`.sig` file next to it).
- **Throttle:** the 24 h rule is applied by the server too. A sync within the window returns **200** with only `serverTime` and `nextSyncNotBefore`, so a wrong device clock can't hammer the API.
- **Client apply:** steps 1–5 below run in one DB transaction (FR-SYNC-03).
  1. Verify the signature.
  2. Apply `ops` in order.
  3. Set `catalog_meta.version`.
  4. Store flags, prices and the entitlement.
  5. Delete sent outbox rows.
  6. Re-categorize eligible transactions (FR-SYNC-05).

  Step 6 runs as a follow-up job, outside the transaction.

### 4.3 Purchases
```json
// POST /v1/purchases/verify — Android
{ "platform": "android", "productId": "zaghlol_gold_yearly", "purchaseToken": "opaque-token-from-play" }
// POST /v1/purchases/verify — iOS (StoreKit 2 signed transaction, JWS)
{ "platform": "ios", "signedTransaction": "eyJhbGciOiJFUzI1NiIsIng1YyI6W…" }
// 200 (signed)
{ "status": "active", "entitlement": { "token": "eyJ…" }, "serverTime": "…" }
// status ∈ active | pending | expired | refunded | invalid
```

**Server procedure (Android):**
1. Look up `productId` in the server's product table. Unknown → **422 `PURCHASE_WRONG_APP`**. The product type picks the call; both calls take only the package name and the token:
   - subscriptions (`zaghlol_gold_monthly`, `_yearly`): `purchases.subscriptionsv2.get`;
   - lifetime (`zaghlol_gold_lifetime`): `purchases.productsv2.getproductpurchasev2`. This is Google's current endpoint for one-time products; the v1 `purchases.products.get` is not used.
2. Require the product ID Play returns (`lineItems[].productId`, or `productLineItem[].productId`) to equal `productId`; otherwise **422 `PURCHASE_TOKEN_INVALID`**.
3. Require `subscriptionState = ACTIVE | IN_GRACE_PERIOD`, or `purchaseStateContext.purchaseState = PURCHASED`. Pending gives `pending`, and nothing is granted (BR-GOLD-05). `environment` is `sandbox` when Play returns `testPurchase` (subscriptions) or `testPurchaseContext` (products).
4. Check `obfuscatedExternalAccountId == HMAC(installId)`, set by the app at purchase (verify only; see Restore).
5. Upsert `purchases`, keyed by the purchase token.
6. If `acknowledgementState` is not acknowledged, acknowledge with `purchases.subscriptions.acknowledge` or `purchases.products.acknowledge`. Both still need the product ID in the path; the server uses the one Play returned in step 2. On failure, retry from the `ix_purchases_unacked` sweeper every 15 min.
7. Sign and return the entitlement.

**Server procedure (iOS):**
1. Verify the JWS x5c chain against Apple Root CA G3.
2. Check `bundleId`, `environment` and `appAccountToken == HMAC(installId)`.
3. Call App Store Server API `Get Transaction Info` and `Get All Subscription Statuses` for the authoritative state.
4. Upsert by `originalTransactionId`.

**Restore** (`POST /v1/purchases/restore`): FU-006, plus one-phone Gold and attestation per D-45, D-46, D-52…D-54 (FR-GOLD-02/03/07/08/09). Design: ADR-012 Amendment (2026-11-05), Part B as revised 2026-11-06.
```json
// Android: items from Play Billing queryPurchasesAsync (1–20) + Play Integrity standard-request token
{ "platform": "android",
  "purchases": [ { "productId": "zaghlol_gold_lifetime", "purchaseToken": "opaque-token-from-play" } ],
  "attestation": { "type": "play_integrity", "token": "eyJ…" } }
// iOS: StoreKit 2 signed transactions (1–20) + App Attest assertion (attestationObject only on a new key's first use)
{ "platform": "ios", "signedTransactions": [ "eyJ…" ],
  "attestation": { "type": "app_attest", "keyId": "…=", "assertion": "o2lzaWduYXR1cmVY…", "attestationObject": "o2NmbXRv…" } }
// 200 (signed)
{ "status": "active", "restoredCount": 1, "movedFromOtherPhone": true, "entitlement": { "token": "eyJ…" }, "serverTime": "…" }
// 409 (problem+json): every move was refused by the 30-day cooldown and nothing else grants Gold
{ "type": "https://api.zaghlol.app/problems/move-cooldown", "title": "Move not yet possible", "status": 409,
  "code": "MOVE_COOLDOWN", "nextMoveAt": "2026-12-06T09:12:00Z" }
```
Possession of a genuine token is **not** proof of ownership. A token presented without valid attestation, or from an install that the seat or account rules exclude, counts as replayed (FR-GOLD-02) and grants nothing. The checks run in this order:

1. **Strict parse and request binding** (R2-1, R2-6).
   - The server parses the body **once** into a JSON object. Duplicate member names and lone (unpaired) UTF-16 surrogates in any string give **`400 VALIDATION_FAILED`**. The DTO is bound from this same object, so the hashed and the processed body can't differ.
   - `bodyHash = SHA-256("zaghlol-restore-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body without "attestation"))`, where JCS is RFC 8785 canonical JSON and `installId` is the lower-case hyphenated UUID text (36 ASCII bytes) of the install that the **install token** authenticates. It is never taken from the body or from `Zaghlol-Install`.
   - The app computes the same hash, from the body it is about to send and its own install ID, before asking the platform for a proof. A proof made for one install fails on every other install, even for a byte-identical body.
   - **Shared test vectors:** `backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json`. The Dart implementation (T-145) and the .NET one (T-132) must both reproduce them, and a contract test checks them.
2. **Attestation** (FR-GOLD-09, D-53; BR-SYNC-03 amended, D-45: the proof is the only device data sent, and no device identifier is stored). It is required on every restore. A missing, invalid or replayed proof, a proof not bound to this install and body, or (Android only) a stale one, fails the whole call with **422 `DEVICE_ATTESTATION_FAILED`**, and nothing is written.
   - **Android (Play Integrity, standard request).**
     - The app calls `prepareIntegrityToken` (warm-up, only when the user starts a restore) and then `request` with `requestHash = b64u(bodyHash)`.
     - The server calls `decodeIntegrityToken` and requires all of: `requestDetails.requestHash == b64u(bodyHash)`; `requestPackageName` = our package; `timestampMillis` no more than 5 min old (the only "expired" case, D-53); `appIntegrity.appRecognitionVerdict = PLAY_RECOGNIZED`; and `deviceIntegrity.deviceRecognitionVerdict` containing `MEETS_DEVICE_INTEGRITY`, or else `MEETS_BASIC_INTEGRITY` (see *Basic integrity* below).
     - **Optional verdicts are off** (R2-7): `deviceAttributes`, `recentDeviceActivity`, `appAccessRiskVerdict` and `environmentDetails` stay disabled in Play Console (T-140 checklist). If a decoded payload carries them anyway, the server ignores them: the DTO has no member for them, and they are never stored or logged.
     - Each token is single-use: its SHA-256 goes into `replay_guard` for 15 min.
   - **iOS (App Attest).**
     - The app sends `assertion = generateAssertion(keyId, clientDataHash = bodyHash)`.
     - The server loads the key registered to **this** install (`app_attest_keys`) and checks: the signature over `nonce = SHA-256(authenticatorData ‖ clientDataHash)` with the stored public key; the RP ID hash = SHA-256(`<TeamID>.<bundleId>`); and a counter strictly greater than the stored one, which is then updated. iOS failure cases are an unknown or unattested key, a bad signature and a counter that doesn't increase (D-53).
     - **First use of a key:** the body also carries `attestationObject`, made with the **same install-bound** `clientDataHash`. The server validates it per Apple's App Attest rules: the x5c chain to the Apple App Attestation Root CA; the nonce extension equals `SHA-256(authData ‖ clientDataHash)`; `keyId` = SHA-256 of the credential public key; App ID; counter 0; `aaguid` = production (or development in staging). Only then does it register the key, to the install named in the hash. A key therefore only ever registers to its own install. A key ID already registered to another install is refused.
     - **No server challenge** (D-53). Every proof is bound to the install whose token authenticates the request, so it is useless anywhere else. Within that install, Play tokens are single-use and expire after 5 minutes, assertions are counter-protected, and a replayed `attestationObject` only registers a key to the install it was made for, without the private key. A stored, unused proof could only be spent by the install that could make a fresh one anyway, so a challenge would add a round trip and server state and no security.
     - **Key lifecycle:** one App Attest key per install. It is generated lazily at the first restore. The `keyId` is kept in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, so it never travels in backups or to a new phone). The app re-attests (new key plus `attestationObject`) when `generateAssertion` fails with `invalidKey`, when the server answers `DEVICE_ATTESTATION_FAILED` to a request without `attestationObject` (key unknown, for example after the server purged the install), and on every new install. "Delete everything" deletes the key row together with the install.
   - **Transport:** release Android builds trust only system CAs (`network_security_config`), so a user-installed CA can't read or rewrite restore bodies and proofs (ADR-012 Part B (d)).
3. **Store verification** of each item, as in verify, except the install-binding check (step 4 on Android; `appAccountToken` on iOS), which names the old install after a phone change.
4. **Account rule** (FR-GOLD-08e). A purchase with `account_id` set moves only to an install presenting a valid account token for **that** account. Otherwise the item's outcome is `account_required`, and the app says "sign in with the account that bought Gold", without revealing which account (EC-65). Restore never sets or changes `account_id` (§4.6 says when it is set).
5. **The seat** (FR-GOLD-08a–d, BR-GOLD-07, `purchase_seats`).
   - Each purchase has **one** seat, held by one install or vacant. Verify binds it to the buying install; that bind is not a move.
   - **Same holder:** if the caller already holds the seat, nothing changes and Gold is granted. A restore on the same install is never a move.
   - **Move:** otherwise (another holder, or vacant) the seat moves to the caller only if `last_moved_at` is null or at least 30 days ago. The move sets `last_moved_at = now` and writes a `purchase_events` row (`seat_move`, channel `restore`). The response's `movedFromOtherPhone` is `true`, and the app says Gold left the other phone.
   - **Cooldown:** if the move isn't allowed, that item is refused. Nothing that affects Gold is written; the server only records the caller as the purchase's **pending claimant** (`claimant_install_id`, kept 7 days), which is what a support move may target (§5.3). If no item ends `active` or `pending` and at least one was refused for the cooldown, the whole call fails with **`409 MOVE_COOLDOWN`** and `nextMoveAt` = `last_moved_at` + 30 days (the earliest one if several). The app shows the date, formatted for the locale, and a support link (EC-68). A refused restore is never a move (EC-66).
   - **A reinstall is a new install.** "Delete everything" or reinstalling the app creates a new install ID, so restoring afterwards **is** a move, even on the same phone (OQ-19(a), ADR-012 Part B (g)).
   - **The old holder** isn't issued Gold for that purchase again. At its next sync or `GET /v1/entitlement` it receives a token with `status: "moved"`, and the app shows "Gold moved to another phone". If it stays offline, its cached token lapses at its `graceUntil`: **at most 14 days after the move** (10 days for a `basic` seat).
   - **Vacant seats** come from `DELETE /v1/installs/me` and the 12-month inactive-install purge. Taking a vacant seat is a move.
   - **Operator move:** support can move a seat past the cooldown (§5.3).
6. **Basic integrity** (R-19). A Play verdict with `MEETS_BASIC_INTEGRITY` but not `MEETS_DEVICE_INTEGRITY` (often a custom ROM) is a valid attestation. The device may hold the single seat under the same cooldown, with `proof = basic` and a token `exp` ≤ `iat` + 3 days. A device with no integrity label at all (rooted, emulator) gets `422 DEVICE_ATTESTATION_FAILED`, as do devices where App Attest is unsupported. Their way to Gold is sign-in (for an account-linked purchase) or support.
- **Aggregate.** Per-item outcomes fold into `status` by the precedence `active > pending > account_required > expired > refunded > invalid`. `restoredCount` counts `active` items. `entitlement` is the merged entitlement after the restore, or `null`. The only 422 is `DEVICE_ATTESTATION_FAILED`, and the only 409 is `MOVE_COOLDOWN`.
- **Lock-out mitigations (R-19, R-21):**
  - **Sign in.** An account-linked purchase reaches the owner's other phone through sign-in (§4.6, FR-GOLD-07), under the same cooldown. The ID token is the proof there, so no attestation is needed. After purchase, the buying phone suggests "sign in on this phone to protect your Gold" (FR-ACCT-01, D-54).
  - **Support.** The operator support lookup (FR-BE-08) shows the purchase, its seat and the next-move date, and the audited support move (§5.3) handles phones lost inside the cooldown (EC-68) and buying phones gone before linking (FR-ACCT-05).
  - **Outages are not failures.**
    - Platform-side transient errors (Play Integrity `NETWORK_ERROR`, `TOO_MANY_REQUESTS`, `GOOGLE_SERVER_UNAVAILABLE`, outdated Play services; App Attest `serverUnavailable`) are retried by the app with back-off: 3 tries within 1 min, then a "try again later" message that also offers to update Play services when that's the cause. The app doesn't call restore without a proof.
    - A server-side decode failure (Google or Apple 5xx, timeouts, our quota) is **`503 UPSTREAM_UNAVAILABLE`** with `Retry-After`, never `422`.
    - The current holder keeps its cached Gold throughout.
  - **Quota.** Restores are rare (phone changes), and `prepareIntegrityToken` runs only when a restore starts. T-140 checks the Play Integrity daily quota in Play Console before launch and alerts at 50 % use, with a quota-increase request as the runbook action.
- **Abuse limits:** restore has its own bucket (5/hour per install) and a per-purchase limit (10 attempts/day across installs). Both give `429`. Store and attestation calls draw on a global Play / App Store budget that reserves capacity for verify and the ack sweeper. When the budget is short, restore gets `503 UPSTREAM_UNAVAILABLE` with `Retry-After` and never delays an acknowledgement.
- **Alerts** carry the purchase UUID only, never a token, transaction ID, install ID or account ID:
  - a spike in `MOVE_COOLDOWN` refusals;
  - more than 2 support moves for one purchase in 90 days;
  - an attestation-failure rate spike, by reason code;
  - Play Integrity quota above 50 %.
- **Verify needs no attestation** (the decision FR-GOLD-09 leaves open). The store-side binding (`obfuscatedExternalAccountId` / `appAccountToken` = HMAC(installId)) already proves that this install made the purchase. A token bound to another install fails with `PURCHASE_NOT_OWNED`, which already rejects the replay FR-GOLD-02 describes. Attestation would add latency and new failure modes to the payment path, which has to keep retrying (BR-GOLD-06), with no security gain. Verify **binds** the purchase's seat to the buying install (`proof = binding`) when the purchase has no seat yet; it never changes an existing holder.

**Entitlement token** (JWS compact, ES256, `kid` header):
```json
{ "iss": "zaghlol", "sub": "<installId>", "acct": "<accountId|null>", "plan": "yearly",
  "status": "active", "exp": 1794175320, "graceUntil": 1794780120, "iat": 1793570520,
  "nextMoveAt": null,
  "src": [ { "store": "google_play", "product": "zaghlol_gold_yearly" } ], "v": 1 }
```
The app grants Gold while `now < graceUntil`, where graceUntil = `exp` + 7 days (BR-GOLD-03, A-38). `status` ∈ `active | grace | expired | refunded | moved | none`. `moved` means the seat of a purchase this install held went to another install (FR-GOLD-08); the app then shows "Gold moved to another phone" copy and offers Restore, Sign in and support. `nextMoveAt` is the earliest time the seat of a purchase in this token can move again by restore or sign-in (`null` = no cooldown running); the app uses it for the cooldown copy, including the "Delete everything" warning.
- **Lifetime rule (D-52, BR-GOLD-07):** for **every** plan, lifetime included, `exp` ≤ `iat` + 7 days; for a subscription, also ≤ the store expiry; for a token covering a `basic` seat, `exp` ≤ `iat` + 3 days. A phone that lost the seat therefore loses Gold within 14 days offline (10 days for `basic`), and a revoked purchase within the same bound.
- **Refresh:** the daily sync returns a fresh token when the cached one (`entitlementIssuedAt`) is more than 24 h old or anything changed; the app also calls `GET /v1/entitlement` when its token is within 3 days of `exp`. A holder that refreshed before going offline keeps at least 5 days of offline Gold (FR-GOLD-04).
- **Which purchases count:** the token covers only purchases whose seat this install holds.

### 4.4 `GET /v1/entitlement`
Returns `{entitlement: {token}, serverTime}`, covering the purchases whose seat this install holds (install and account purchases alike). It is called after a purchase restore, after sign-in, and when the cached token is within 3 days of `exp`. It never moves a seat: only restore, sign-in and the support move do. If this install lost a seat since its last token, the new token has `status: moved`.

### 4.5 Store notifications
- **Google RTDN:** Pub/Sub **push** subscription, authenticated with an OIDC token.
  1. The body `message.data` (base64) holds a `subscriptionNotification`, `oneTimeProductNotification` or `voidedPurchaseNotification`.
  2. The handler stores it in `store_notifications` (dedupe on `messageId`), returns **204 immediately**, and leaves processing to a worker.
  3. The worker re-reads the authoritative state from the Play API rather than trusting the notification body.
  4. A daily reconciliation calls `voidedpurchases.list` so a missed refund is still caught.
- **Apple ASSN V2:** `{signedPayload}`.
  1. The chain is verified and `notificationUUID` is deduped.
  2. Types handled: `SUBSCRIBED`, `DID_RENEW`, `DID_FAIL_TO_RENEW` (grace), `EXPIRED`, `GRACE_PERIOD_EXPIRED`, `REFUND`, `REVOKE`, `DID_CHANGE_RENEWAL_STATUS`.
  3. The handler returns 200 after storing; Apple retries otherwise.
- **Both envelopes are open** (FU-007): a field Google or Apple add later is ignored, not rejected. Authenticity comes from the OIDC token and the JWS chain, not from the envelope shape.
- **Order of checks (Google):**
  1. The authentication handler verifies the OIDC JWT **before the body is read**: JWKS signature, `iss` = `https://accounts.google.com` (or `accounts.google.com`), `aud` = the pinned push audience, `email` = the push service account, `email_verified = true`, and `exp`. On failure it returns `401` without buffering the body.
  2. Only then is the body bound.
- **Order of checks (Apple):**
  1. Only `signedPayload` is read.
  2. The x5c chain to Apple Root CA G3, the signature, `bundleId` and `environment` are verified, then the nested `signedTransactionInfo` / `signedRenewalInfo` JWS.
  3. Nothing is written before all of these pass; a failure returns `401`.
- **What is stored:** only the explicit extracted columns of `store_notifications` and `payload_digest`. The raw envelope is never stored. DTOs list exactly the fields read. `[JsonExtensionData]`, `JsonElement`/`JsonNode` catch-all members and dictionary "rest" properties are forbidden (a review checklist item for T-133/T-134).
- **Test requirement (T-133/T-134):** post a valid notification with a sentinel unknown field (and a sentinel value inside `message.attributes`) and assert the sentinel is absent from the database, the logs and the trace spans.

### 4.6 Accounts
```json
// POST /v1/accounts/signin
{ "provider": "apple", "idToken": "eyJ…", "nonce": "<raw client nonce, ≥128-bit base64url>", "authorizationCode": "c1a…" }
// 200 (signed)
{ "accountId": "uuid", "accountToken": "eyJ…", "entitlement": { "token": "eyJ…" }, "linkedInstalls": 2, "movedFromOtherPhone": false, "serverTime": "…" }
```

**Verification:**
- **Google:** `aud` must be one of our OAuth client IDs; check `iss` and `exp`; JWKS from Google.
- **Apple:** `aud` must be our Services ID or bundle ID; `iss = https://appleid.apple.com`. The `authorizationCode` is exchanged for a refresh token, stored encrypted and used **only** to revoke on deletion.
- **Nonce and replay (both providers, ADR-016 amendments 2 and 3):**
  - The app generates a **raw** nonce: ≥ 128 bits from a CSPRNG, base64url without padding (`^[A-Za-z0-9_-]{22,128}$`). It gives the provider only `hex(SHA-256(raw))`, the lower-case hex SHA-256 of the raw string's ASCII bytes. It sends the **raw** value in `nonce`.
  - The server computes `hex(SHA-256(nonce))` and compares it with the token's `nonce` claim in constant time. Someone holding only the token knows the claim but not its pre-image, so a copied claim doesn't pass.
  - **Required for both providers** (R2-9). A request without `nonce`, or an ID token without a `nonce` claim, gives `422 ID_TOKEN_INVALID`. Google: the app passes the hashed nonce to Credential Manager (`GetGoogleIdOption` / `GetSignInWithGoogleOption.setNonce`) on Android and to GoogleSignIn-iOS (`signIn(withPresenting:hint:additionalScopes:nonce:)`) on iOS; `google_sign_in` 7.x exposes it as `initialize(nonce:)` (T-147 checks that a fresh nonce can be set for every attempt).
  - A token whose `iat` is more than 10 minutes old gives `422 ID_TOKEN_INVALID`.
  - Single use: the server inserts the nonce claim's hash into `replay_guard` (`backend-schema.md`), kept until the token's `exp`. A second use of the same token gives `422 ID_TOKEN_INVALID`.
  - An `Idempotency-Key` replay returns the stored result before this check runs, so legitimate retries still work. The stored result is returned only to the same install, for the same key and an identical body (§1), so it can't hand an account token to anyone else.

**After verification** (one transaction; if it ends in `409 MOVE_COOLDOWN`, nothing is written, the link included, except the pending-claimant record of §4.3 step 5):
1. Upsert the account.
2. Link the install.
3. **Attach** (D-54, FR-ACCT-05). Set `account_id` only on purchases with no account yet **and** `purchases.install_id` = this install, the buying install bound by verify. There is no other self-service attach: a purchase whose buying install is gone (reset, lost, sold or purged) is linked only by support (§5.3). Restore-acquired seats never attach a purchase, so someone with a leaked token can't lock the owner out.
4. **Seat at attach time** (R2-2(a)). After attach, the seat must be on an install linked to this account. If the holder is this install or another install linked to the account, it stays. Otherwise the seat moves to this (buying) install: the *account-attach reclaim*, which neither checks nor restarts the cooldown and is recorded as `seat_move` with channel `account_attach`. The previous holder gets `status: moved`.
5. **Seat moves** (FR-GOLD-07/08, D-52). For each purchase linked to the account whose seat is on another install (or vacant), the seat moves to this install under the 30-day cooldown of §4.3 step 5 (`proof = account`; the ID token is the proof, so no attestation is needed). The response's `movedFromOtherPhone` is `true` when a seat moved. If at least one move was refused for the cooldown and, after the call, this install holds no seat that grants Gold, the call fails with **`409 MOVE_COOLDOWN`** and `nextMoveAt`. A purchase that isn't linked to the account is never moved by sign-in: on a new phone it is reached only through restore (FR-ACCT-05).

Sign-out (`POST /v1/accounts/signout`) unlinks the install and doesn't change seats: the holder keeps Gold until the next move, which needs the account.

If the install was linked to a different account, the response is **409 `INSTALL_LINKED_TO_OTHER_ACCOUNT`** and the app asks the user (EC-46). Re-sending with `"replaceLink": true` confirms.

**Sign in with Apple on Android** (CR-05, FU-008):
1. The app opens a Custom Tab to `https://appleid.apple.com/auth/authorize` with `client_id` = our Services ID, `redirect_uri` = `https://api.zaghlol.app/v1/apple/android-callback`, `response_type=code id_token`, `response_mode=form_post`, `scope=email`, a random `state` (≥ 128 bits, base64url; single-use, expires after ≤ 10 minutes, held only by the app) and `nonce` = `hex(SHA-256(raw nonce))`. When Chrome is installed, the Custom Tab is opened with an explicit Chrome package.
2. Apple POSTs `code`, `id_token`, `state` (and on the first authorization `user`) as `application/x-www-form-urlencoded` to the callback. On cancel it posts `error=user_cancelled_authorize` and `state`.
3. The callback first checks every forwarded field against its pattern; any mismatch gives `400`:
   - `state`: `^[A-Za-z0-9_-]{16,128}$`
   - `code`: `^[A-Za-z0-9._-]{1,2048}$`
   - `id_token`: compact JWS
   - `error`: `^[a-z_]{1,64}$`

   It drops `user` and any unlisted field and stores nothing. It then answers **303** to `intent://callback?<code, id_token, state | error, state>#Intent;package=<applicationId>;scheme=signinwithapple;end`, the format the `sign_in_with_apple` package expects. Chrome resolves an `intent://` URL on the device and only for that package, so the tokens never travel in an HTTP URL.
   - **Building the `Location`:** use a URI builder. Scheme `intent`, host `callback`, the configured package and the `signinwithapple` scheme are constants; each forwarded value is added as a percent-encoded query parameter. Raw input is never concatenated.
   - **Test requirement (T-135):** for each field, inputs containing `#`, `;`, `%23`, CR/LF or `&` must either get `400` or produce a `Location` with exactly one `#Intent;package=…;scheme=signinwithapple;end` tail and no injected parameter.
4. The app checks `state` against its unexpired, unused value and then discards it. It then calls `POST /v1/accounts/signin` with `{provider: "apple", idToken, nonce (raw), authorizationCode}`. That call does all verification (aud = Services ID, iss, exp, iat ≤ 10 min, nonce pre-image, single use).
5. **Browser caveat (T-147, T-172):** device tests must cover Samsung Internet and Firefox as the default browser. If a browser ignores `package=` in the intent URL, record it as a known limitation, or move the return leg to a verified Android App Link (`https://zaghlol.app/auth/apple`, with the parameters in the fragment) for that case.

`form_post` is required, not a choice. Apple accepts `response_mode=query` only with `response_type=code` and no scopes. That mode would give us no `id_token` and no e-mail for support lookup (A-47), and it would put the code in a URL. The callback body and the `Location` header are never logged.

`DELETE /v1/accounts/me` removes the account and its links. Purchases stay bound to their installs.

### 4.7 Delete install (FR-ONB-08)
`DELETE /v1/installs/me` returns 202 and tombstones the install; its tokens stop working at once. The app wipes local data **before** calling this endpoint and does not depend on it succeeding. A failure is retried once, then given up, because the install expires after 12 months of no syncs anyway.

### 4.8 Shapes fixed by the OpenAPI file (T-006; architect sign-off 2026-11-05)
These details were not spelled out above. `backend/openapi/zaghlol-v1.yaml` is authoritative for field names, limits and patterns. The solution-architect reviewed the T-006 inferences on 2026-11-05. The items below are signed off as written or corrected as noted.
- **Success statuses without a body:** `DELETE /v1/installs/me` returns 202; `POST /v1/accounts/signout` and `DELETE /v1/accounts/me` return 204; `POST /v1/notifications/google` returns 204; `POST /v1/notifications/apple` returns 200; `DELETE /admin/v1/catalog/draft/{entity}/{id}` returns 204. *Signed off.*
- **Restore:** request and response as in §4.3. *Corrected:* Android items are `{productId, purchaseToken}` (FU-006); the aggregate precedence is defined. Per D-45/D-46 and D-52, restore now requires `attestation`, returns `movedFromOtherPhone`, adds the item outcome `account_required`, and declares 422 only for `DEVICE_ATTESTATION_FAILED` and 409 only for `MOVE_COOLDOWN`. The 2026-11-05 `seatsReleased` field is withdrawn (one seat per purchase).
- **Full catalog snapshot** (`GET /v1/catalog/{version}/full`): `{version, ops[]}` where `ops` are upserts of the same shape as in `/v1/sync`. The signature is the `Zaghlol-Signature` header and the `.sig` file next to the snapshot. *Signed off.*
- **`rotateInstallToken`:** an optional string in the sync, verify, restore and entitlement response bodies. Absent or `null` means keep the current token. *Signed off.*
- **Apple Android callback:** *Corrected* (FU-008) from a `GET` with query parameters to `POST /v1/apple/android-callback` with an `application/x-www-form-urlencoded` body `{state, code?, id_token?, error?, user?}`. It answers **303** to an `intent://` URL (§4.6). `user` is dropped unread.
- **Pub/Sub push body:** `{message: {data, messageId, publishTime, attributes?, orderingKey?}, subscription, deliveryAttempt?}`. *Corrected* (FU-007): the envelope is **open**, and so are the ASSN body and the Apple callback form.
- **Money and prices** are decimal strings (for example `"4820.00"`) with a separate ISO 4217 `currency`. They are never JSON numbers.
- **Timestamps** are RFC 3339 UTC and always end in `Z`.
- **Request limits:** `POST /v1/sync` accepts at most 50 `contributions` and at most 10 `bankRequests` per call.
- **`x-required-roles: [any]`** (used by `GET /admin/v1/metrics/daily-active`) means any authenticated operator role. *Signed off.*
- **Admin bodies:** `PUT /admin/v1/prices/override` `{symbol, currency, price, reason, expiresAt?}` and `POST /admin/v1/catalog/publish` `{note?}` are *signed off*. `expiresAt` defaults to 24 h and is capped at 7 days (new column `price_quotes.override_expires_at`). *Corrected:* `PUT /admin/v1/flags/{key}` takes `{value, rules?}`, where `rules = {platforms?, minAppVersion?, rolloutPercent?}` per `feature_flags.rules`, and `FlagState` returns `rules`. The draft, contribution and support bodies are in §5.2.

## 5. Admin API (operators, v1 used by `zaghlol-ops`; web admin later per D-37)

| Method & path | Role | Purpose |
|---|---|---|
| `GET/POST/PUT/DELETE /admin/v1/catalog/draft/...` | catalog_editor | Edit draft categories/merchants/aliases/keywords; DELETE tombstones (§5.2) |
| `POST /admin/v1/catalog/publish` | catalog_editor | Publish draft → new immutable version, build + sign full snapshot, upload to CDN |
| `GET /admin/v1/contributions?status=ready_for_review` | catalog_editor | Review queue (aggregates only; `collecting` never shown) |
| `POST /admin/v1/contributions:promote \| :reject` | catalog_editor | Promote into the draft / reject; key in the body |
| `GET/PUT /admin/v1/flags/{key}` | flags_admin | View / change a flag and its targeting rules (audited, takes effect on next sync) |
| `PUT /admin/v1/prices/override` | prices_admin | Override a price when the feed is wrong |
| `POST /admin/v1/support/entitlement:lookup` | support_viewer | Entitlement and seat status only; install ID or e-mail in the body |
| `POST /admin/v1/support/seat:move` | support_agent | Audited seat move past the cooldown, optional attach (§5.3) |
| `GET /admin/v1/bank-requests` | catalog_editor | Ranked list |
| `GET /admin/v1/metrics/daily-active` | any | Aggregate counters |

### 5.1 Concrete operations (OpenAPI)

The table above uses shorthand. These are the exact operations in `zaghlol-v1.yaml`; a contract test compares this list to the spec exactly. `entity` is `categories`, `merchants`, `aliases` or `keywords`. All admin calls use an operator bearer token (`operatorOidc`) and each operation declares its role in `x-required-roles`.

| Operation | Role |
|---|---|
| `GET /admin/v1/catalog/draft/{entity}` | catalog_editor |
| `POST /admin/v1/catalog/draft/{entity}` | catalog_editor (`entity` = `merchants` only) |
| `PUT /admin/v1/catalog/draft/{entity}/{id}` | catalog_editor |
| `DELETE /admin/v1/catalog/draft/{entity}/{id}` | catalog_editor |
| `POST /admin/v1/catalog/publish` | catalog_editor |
| `GET /admin/v1/contributions` | catalog_editor |
| `POST /admin/v1/contributions:promote` | catalog_editor |
| `POST /admin/v1/contributions:reject` | catalog_editor |
| `GET /admin/v1/flags/{key}` | flags_admin |
| `PUT /admin/v1/flags/{key}` | flags_admin |
| `PUT /admin/v1/prices/override` | prices_admin |
| `POST /admin/v1/support/entitlement:lookup` | support_viewer |
| `POST /admin/v1/support/seat:move` | support_agent |
| `GET /admin/v1/bank-requests` | catalog_editor |
| `GET /admin/v1/metrics/daily-active` | any |

### 5.2 Draft catalog keys, tombstones and body-keyed admin calls (FU-008, FU-009)

**Entry keys.** The path `{id}` of `PUT`/`DELETE /admin/v1/catalog/draft/{entity}/{id}` is the entity's natural key. Its form must match `entity`. `b64u(s)` is base64url without padding of the UTF-8 bytes of `s`, so free text (spaces, Arabic, `/`, `%`, `:`) never needs path escaping, and ASP.NET Core's `%2F` handling can't corrupt it. Keys must be **canonical**, and anything else gives `400 VALIDATION_FAILED`:
  - no `=` padding;
  - re-encoding the decoded bytes must reproduce the input exactly (rejects non-zero trailing bits and other non-canonical forms);
  - the bytes must be valid UTF-8;
  - the decoded text must equal its own normalized form (`merchant_norm` normalization for aliases, keyword normalization for keywords, `parsing-engine.md` §5);
  - the decoded text is at most 64 characters, matching the backend `merchant_norm` cap.

| Entity | Identity (= sync op key) | `{id}` form | Example | Body (non-key fields only) |
|---|---|---|---|---|
| categories | `code` | `<code>` | `dining` | `{nameAr, nameEn, icon, color, bucket, sort}` |
| merchants | `id` (integer, server-allocated, never reused) | `<id>` | `812` | `{canonical, nameAr, category}` |
| aliases | `merchantId` + `alias` (normalized) | `<merchantId>:<b64u(alias)>` | `812:a29zaGFyeSBlbCB0YWhyaXI` | `{match}` (`exact \| prefix \| token`) |
| keywords | `keyword` (normalized) + `lang` | `<lang>:<b64u(keyword)>` | `ar:2LXZitiv2YTZitip` (صيدلية) | `{category, weight}` |

- **Keys only in the path.** Key fields are never in the body, so changing a key means `DELETE` plus `PUT`. A keyword has exactly one category per language. `catalog_keywords` is keyed `(keyword_norm, lang)` on both server and device, which matches the sync `keyword` op whose delete carries only `keyword` + `lang`.
- **Create.** Categories, aliases and keywords are created by `PUT`. Merchants are created by `POST /admin/v1/catalog/draft/merchants`, which allocates the id and returns `201` with the `MerchantOp`. `PUT` on an unknown merchant id gives `404`.
- **Delete = tombstone.** `DELETE` marks the draft entry deleted and returns `204`. The next publish writes it with the new version and `deleted = true`, so deltas `(a, b]` carry `op: delete` (ADR-013). An entry that was never published is removed outright. A `PUT` on a tombstoned key revives it.
- **Cascades and conflicts.** Deleting a merchant tombstones its aliases too, and the delta lists those alias deletes before the merchant delete. Deleting a category still referenced by a live category, merchant or keyword gives **409 `ADMIN_CONFLICT`**, as does a `PUT`/`POST` that references a category or merchant that isn't live in the draft. A missing or already-deleted key gives `404`.
- **Contributions.** `:promote` takes `{merchantNorm, institutionCode, merchantId?, categoryCode?}`. With `merchantId` the string becomes an `exact` alias of that merchant; without it a new draft merchant (`canonical` = `merchantNorm`) is created. `categoryCode` defaults to the top vote. `:reject` takes `{merchantNorm, institutionCode}`. Both return `{merchantNorm, institutionCode, status, merchantId?}`. A key with no aggregate **and** a key whose aggregate is still `collecting` both give `404 NOT_FOUND`, indistinguishably: same status and body, and one query that excludes `collecting`, so there is no timing difference. `409 ADMIN_CONFLICT` is returned only for an aggregate already `promoted` or `rejected`, or for a draft conflict. **Test requirement (T-129):** a `collecting` key and an absent key return byte-identical responses on both `:promote` and `:reject`. The key moved from the path to the body because `merchantNorm` is free text.
- **Review queue privacy.** Aggregates still `collecting` (fewer than 5 distinct installs, A-48) are never returned. The API status enum is `ready_for_review | promoted | rejected`.
- **Support lookup.** `POST /admin/v1/support/entitlement:lookup` takes `{installId}` or `{email}` (exactly one) and returns `SupportEntitlement`: the status plus, per related purchase, `{purchaseId, plan, state, store, seat, accountLinked, lastMovedAt, nextMoveAt}`, where `seat` says whether the looked-up install is the `holder`, the pending `claimant` (§5.3) or `none`. An e-mail lookup lists the account's purchases. No tokens, transaction IDs or other installs' IDs are returned. The audit row stores the install ID, or `HMAC-SHA256(K_audit, NFC(trim(lower(email))))`, plus the matched `account_id` when the lookup hits an account. It never stores the e-mail. A plain SHA-256 of an e-mail can be reversed by dictionary, so a keyed HMAC is used. `K_audit` is a dedicated KMS key, separate from the `install_hash` pepper. The audit value is pseudonymous personal data kept **exactly 1 year from creation, then deleted**, even if the account is deleted earlier (D-47, FR-BE-11, NFR-PRIV-07).

### 5.3 Support seat move (D-52, D-54, EC-68, FR-ACCT-05)

`POST /admin/v1/support/seat:move`, role **`support_agent`**. It is the only way past the 30-day cooldown, and the only way to link a purchase whose buying install is gone.

- **Request:** `{purchaseId, toInstallId, reasonCode, ticketRef, attachToAccount?}`.
  - `reasonCode` ∈ `lost_or_broken_phone | reinstall | buying_phone_gone | other`.
  - `ticketRef` is the support ticket number (`^[A-Za-z0-9_-]{1,32}$`). It is never free text, so no personal data enters the audit row.
  - The operator gets `purchaseId` from a support lookup (§5.2), and `toInstallId` from the user, who reads it from the app's help screen (the support code).
- **Who can receive the seat:** only an install that has itself proven possession. That is the purchase's **pending claimant**: the last install whose restore or sign-in for this purchase passed attestation, store verification and the account rule, but was refused for the cooldown, within the last 7 days (`purchase_seats.claimant_install_id`). The current holder is also accepted, for `attachToAccount` alone. An operator therefore can't send Gold to an arbitrary install. Any other target gives `409 ADMIN_CONFLICT`.
- **Account rule** (D-46): for an account-linked purchase, the target must be linked to that account. Otherwise `409 ADMIN_CONFLICT`.
- **Attach** (`attachToAccount: true`, FR-ACCT-05): allowed only when the purchase has no account and the target is linked to an account. It sets `account_id` to that account.
- **Effect:** the seat moves to the target (`seat_move`, channel `support`), and the previous holder gets `status: moved` at its next refresh. Following the OQ-19(b) recommendation, the support move **neither checks nor restarts** the cooldown: `last_moved_at` is unchanged, so `nextMoveAt` stays where it was. If the PO decides otherwise, the move sets `last_moved_at = now`.
- **Idempotent by nature:** moving to the install that already holds the seat changes nothing and returns the same result.
- **Response:** `{purchaseId, moved, attached, nextMoveAt}`.
- **Audit** (D-47 rules): every call, successful or refused, writes an `audit_log` row: `action = 'support_seat_move'`, `target` = the purchase UUID, `details` = `{from_install, to_install, reason_code, ticket_ref, attached_account_id?, outcome}`. It never holds an e-mail. Install IDs are pseudonymous personal data, so the row is kept **exactly 1 year from creation, then deleted**, like support-lookup rows.
- **Alerts:** more than 2 support moves for one purchase in 90 days, or more than 20 by one operator in a day (`error-handling-and-observability.md` §4).
- **Interim tooling** (D-37, R-21): until the admin web app ships after launch, operators use `zaghlol-ops support move --purchase <uuid> --to <installId> --reason <code> --ticket <ref> [--attach]`, with OIDC device-code sign-in and MFA. T-136 owns the endpoint, role and audit, T-137 the CLI command and the support runbook, and T-132 the seat service it calls.

## 6. Error codes

Every error is `application/problem+json` with one of these `code` values. The same list is the `ProblemCode` enum in `backend/openapi/zaghlol-v1.yaml`, and a contract test fails if the two differ. Generated clients must treat an unknown code as its HTTP status class (for example, an unknown 4xx code is a client bug, and an unknown 5xx code is retried with back-off).

| HTTP | `code` | Meaning / client action |
|---|---|---|
| 400 | `VALIDATION_FAILED`, `UNKNOWN_FIELD` | Bug; log a local diag code, don't retry |
| 401 | `INSTALL_TOKEN_INVALID` | Re-register silently (new install ID); keep local data |
| 401 | `ACCOUNT_TOKEN_EXPIRED` | Clear the account token and show "sign in again" in Settings only |
| 401 | `UNAUTHORIZED` | Fallback for endpoints that have no specific 401 code (store notifications, operator API). Not sent to the app's install-scoped calls, which always use one of the two codes above. Don't retry; for the operator CLI, sign in again |
| 403 | `FORBIDDEN` | Not retried |
| 404 | `CATALOG_VERSION_UNKNOWN` | Request a full catalog |
| 404 | `NOT_FOUND` | The path or resource doesn't exist. A bug in the app (or an operator typo); don't retry |
| 405 | `METHOD_NOT_ALLOWED` | The HTTP method isn't supported on this path. A bug in the app; don't retry |
| 409 | `INSTALL_EXISTS`, `INSTALL_LINKED_TO_OTHER_ACCOUNT` | See §4.1 / §4.6 |
| 409 | `MOVE_COOLDOWN` | Restore and sign-in (§4.3, §4.6, D-52): Gold was moved in the last 30 days, so it can't move to this phone yet. The body carries `nextMoveAt`. Show the date, formatted for the locale, and the support link (EC-68). Nothing was written; don't retry before `nextMoveAt` |
| 409 | `IDEMPOTENCY_KEY_REUSED` | The same install sent the same `Idempotency-Key` for the same operation with a different body (§1). A bug in the app: generate a new key for a new request; don't retry with this one |
| 422 | `DEVICE_ATTESTATION_FAILED` | Restore only: the Play Integrity token or App Attest assertion is missing, invalid, stale, replayed or not bound to the body. iOS: if no `attestationObject` was sent, generate a new App Attest key and retry once with it; Android: retry once with a fresh token. Then stop, show the help message (EC-66) and offer sign-in (an account-linked purchase reaches the phone through sign-in without attestation, R-19). Gold is unchanged. Attestation-service outages are `503 UPSTREAM_UNAVAILABLE`, not this code |
| 409 | `ADMIN_CONFLICT` | Operator API only (§5.2): the edit conflicts with the current draft catalog or review queue. Reload and retry. Never sent to the app |
| 413 | `PAYLOAD_TOO_LARGE` | The body is over the size limit (§1). A bug in the app; don't retry |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | The body wasn't the declared media type (`application/json`; the Apple callback takes `application/x-www-form-urlencoded`). A bug in the app; don't retry |
| 422 | `PURCHASE_TOKEN_INVALID`, `PURCHASE_NOT_OWNED`, `PURCHASE_WRONG_APP` | Show "couldn't verify purchase" + Restore; no Gold |
| 422 | `ID_TOKEN_INVALID` | Sign-in failed message |
| 429 | `RATE_LIMITED` | Respect `Retry-After` |
| 502/503 | `STORE_UNAVAILABLE`, `UPSTREAM_UNAVAILABLE` | Keep purchase pending, retry with back-off (BR-GOLD-06) |
| 500 | `INTERNAL` | Retry with back-off |

`404`, `405`, `413` and `415` with their generic codes can be returned by any endpoint, including paths that don't exist, so the OpenAPI file describes them once in the info section. It also lists `413` and `415` on every operation that takes a body.
