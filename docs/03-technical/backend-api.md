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
| Idempotency | `Idempotency-Key: <ULID>` on `POST /v1/purchases/verify`, `/v1/installs`, `/v1/accounts/signin`. The app generates every key with a CSPRNG (`Random.secure()` for the 80 random bits of the ULID), never reuses one for a different request, and never logs it (R3-6). **Authenticated operations** (verify, sign-in): a stored result is keyed by **(installId, operationId, Idempotency-Key)** and records **SHA-256 of the request body bytes**. `installId` is the install that the install token authenticates. A replay within 24 h returns the stored result only when all four match and the record has not expired: every lookup requires `expires_at > now()`, so a row the daily purger hasn't reached yet is never served. The same key from a **different install** is a different key: it is processed as a new request and never sees another install's stored body. The same install, operation and key with a **different body hash** gives **`409 IDEMPOTENCY_KEY_REUSED`**, never the stored body (R2-8). Only final results are stored (2xx, 409 and 422); `429` and 5xx are not, so a retry runs again. `DELETE /v1/installs/me` deletes that install's records, and `DELETE /v1/accounts/me` deletes every sign-in record that holds that account's token. **`POST /v1/installs`** stores no response: see §4.1 (R3-6). Records live in `idempotency_records` (`backend-schema.md`). |
| Response signing | Security-relevant responses carry `Zaghlol-Signature: kid=<kid>; alg=ES256; sig=<base64url>`, an ECDSA P-256 signature over the **exact response body bytes** after decompression. The app verifies it against embedded public keys (ADR-012/013) and drops unsigned or invalid bodies. The signature binds the body only, not the request or the install, so a signed body proves *what the server said*, not *to whom or when it was asked*; the time nonce below adds that binding where trusted time needs it (R4-2). Every 200 of the six anchoring operations is signed, the sync throttle answer included. `sig` is the IEEE P1363 `r‖s` encoding (64 bytes, 86 base64url chars, no padding; high-S accepted). Kids are `s<yyyy><a-z>` for response signatures and catalog `.sig` files and `e<yyyy><a-z>` for JWS tokens (entitlement, account); the app accepts each prefix only in its own place (T-123 design note). |
| Time | `serverTime` (RFC 3339 UTC) in every response body. The app stores it to drive the 24 h throttle (EC-43). |
| Time nonce (R4-2, NFR-SEC-08) | The app sends `Zaghlol-Time-Nonce: <22 base64url chars>`, 128 bits fresh from a CSPRNG, on every **anchoring request**: `POST /v1/sync`, `GET /v1/entitlement`, `POST /v1/purchases/verify`, `POST /v1/purchases/restore`, `POST /v1/accounts/signin` and `POST /v1/accounts/signout`. The server copies it unchanged into the signed 200 body as `timeNonce` (`null` when the header was absent), so the echo is covered by `Zaghlol-Signature`. It is a random per-request value with no device data, never stored, logged or traced on either side, and never reused (D-48 classification, SRS v1.7). A malformed value is `400 VALIDATION_FAILED`. Only a body echoing the app's single outstanding nonce, within 60 s, may lower trusted time or clear `tampered` (§4.3 *Trusted time*). An `Idempotency-Key` replay returns the stored body, whose echo is the original request's nonce, so it can only raise trusted time. |
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
| `GET /v1/health` | none | Readiness: `SELECT 1` as `app_rw` (1 s timeout, cached 2 s); `503 UPSTREAM_UNAVAILABLE` while the DB is unreachable (FU-003). Liveness is a process check | — |
| `/admin/v1/*` | Operator OIDC + MFA + role | Operator API (§5) | FR-BE-08 |

## 3. Authentication & authorization (API level)

| Principal | Credential | Issued by | Lifetime | Scope |
|---|---|---|---|---|
| **Install** | `installToken`: 32 random bytes, base64url. The server stores only SHA-256(token). | `POST /v1/installs` | Until the install is deleted. Rotated by the server in any response (`rotateInstallToken`) if compromise is suspected. | Own install only: sync, purchases, entitlement, own deletion |
| **Account** | `accountToken`: ES256 JWT `{sub: accountId, iid: installId, iat, exp: +30 d, kid}` | `POST /v1/accounts/signin` | 30 days, silently refreshed in `/v1/sync` responses. A token whose account no longer exists, or whose install is no longer linked to it, is rejected with `401 ACCOUNT_TOKEN_EXPIRED` even before `exp` (R3-6) | Link/unlink/delete own account; read account entitlements; required for account-linked Gold (D-61(c)) |
| **Google Pub/Sub** | Google-signed OIDC JWT (`aud` = our push endpoint, `email` = our push service account) | Google | per request | `/v1/notifications/google` only |
| **Apple ASSN** | `signedPayload` JWS, x5c chain verified to Apple Root CA G3, bundle ID + environment checked | Apple | per request | `/v1/notifications/apple` only |
| **Operator** | OIDC (Google Workspace or Entra ID) with enforced MFA; short-lived access token (≤ 1 h). `zaghlol-ops` signs in with **authorization code + PKCE and a loopback redirect** (RFC 8252); the device-code grant is disabled for its client (R3-9). `support_agent` and `support_lead` additionally require **phishing-resistant MFA (FIDO2 / passkey)**. **The IdP is the enforcement point** (R4-6): a conditional-access policy scoped to the `zaghlol-ops` and admin-app clients requires phishing-resistant MFA for the support group (Entra: an authentication-strength policy, ideally bound to an authentication context so the token carries it in `acrs`; Google Workspace: security-key-only 2SV enforcement for the support OU). The API also checks the claim that proves it **only if** T-136 confirms the chosen IdP emits one (Entra `acrs` containing the configured context ID; Entra's documented `amr` values have no FIDO2-specific value, only `mfa`/`rsa`/`ngcmfa`; Google Workspace OIDC tokens generally carry neither). Without such a claim the API check is **advisory** (it requires the MFA signal the IdP does emit and logs a diag counter) and the runbook records the IdP policy as the control | Company IdP | 1 h | Role-based: `catalog_editor`, `flags_admin`, `support_viewer` (read-only lookup), `support_agent` (audited support seat move and detach, §5.3; named staff only, reviewed quarterly), `support_lead` (audited dispute-freeze unfreeze only, §5.3, R5-5(b); named support leads only, reviewed quarterly), `prices_admin`; every write audited |

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
- `installId` is generated on device (UUID v4, CSPRNG). If the ID already exists, the server returns **409 `INSTALL_EXISTS`**. The client then regenerates the ID; this happens only after an interrupted delete or a lost registration response.
- **Retry after a lost response (R3-6).** The install ID is shown to the user as the support code, so it is not a secret, and the server never stores a response holding an `installToken`. Instead it keeps `installs.registration_key_hash` = SHA-256(`Idempotency-Key`) and `registration_body_sha256`. A replay with the same key and the same body bytes, within 24 h and **before the install has made any authenticated call**, gets `201` with a **freshly generated** `installToken`; the token hash is replaced, so the earlier token, which nobody ever used, stops working. After the first authenticated call (which clears both columns), after 24 h, or with a different key or body, the answer is `409 INSTALL_EXISTS` (or `409 IDEMPOTENCY_KEY_REUSED` for the same key with a different body), and the client registers a new install ID. Knowing the support code alone therefore never yields a token.
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
  "accountToken": null,                                                   // refreshed token when signed in & < 7 d to expiry
  "supportNotice": null,                                                  // "gold_linked_by_support" once, to the buying install (R4-7(2))
  "timeNonce": "kq3V9w0bQ2FwdGFpblphZw"                                   // echo of Zaghlol-Time-Nonce (§1, R4-2)
}
```

**Rules:**
- **Size:** the response is ≤ 2 KB when nothing changed (NFR-BE-03). Unchanged blocks are `null`.
- **Server checks:** the server validates every contribution against BR-SYNC-04, and silently drops non-conforming ones (`accepted` counts only rows actually stored: valid and not already present). The request body is closed at every level (`400 UNKNOWN_FIELD`); more than 50 `contributions` or 10 `bankRequests`, a negative cursor or a missing or malformed `Zaghlol-App` (`<platform>/<appVersion> (<build>)`, the `appVersion` form of `InstallRequest`) is `400 VALIDATION_FAILED` for the whole call. Per item (T-128): `merchantNorm` and `institutionName` are normalized (control and format characters removed, fullwidth forms folded, whitespace collapsed, Latin lower-cased) and must pass `ContributionPrivacy` before any insert (no `@`, no run of 6 digits in any script, at most 64 characters, at least 2); `institutionCode` must match `InstitutionCode`, `categoryCode` must be a live system category (custom categories are dropped), `country` and `channel` must match the schema. Duplicates are removed by key (`merchantNorm`, `institutionCode`) and (`institutionName`, `country`, `channel`) per install: one install has one vote per merchant, and a re-sent or changed category is ignored. Rows carry `install_hash` (KMS HMAC), never the install ID; if the KMS can't compute it, that call's intake is dropped and the sync still succeeds.
- **No `Idempotency-Key`:** the throttle is the idempotency mechanism (a repeat inside the window gets the throttle answer; a repeated item is deduped by key).
- **Composition:** `catalog` is `null` when `catalogVersion` equals the latest published version (or nothing is published); `mode: "full"` when it is 0, ahead of the server, more than 20 versions behind, or the delta would exceed `Sync:MaxDeltaOps` ops; `fromVersion` echoes the request. `flags` is sent when its `version` differs from `flagsVersion` **or** the `Zaghlol-App` version differs from the one stored for the install (an app update can change a `minAppVersion` rule's outcome). `prices` is sent when there is a block and its `asOf` differs from `pricesAsOf` (compared at whole seconds). Platform comes from the install row; a `Zaghlol-App` platform that disagrees is ignored.
- **Failures:** a failure reading the catalog (including a missing `catalog_versions` row for the latest version), the flags or the entitlement block is `503 UPSTREAM_UNAVAILABLE` with `Retry-After: 30` and nothing written, so the window is not consumed; a failure reading prices only makes `prices` `null`. A flag whose stored rules don't parse strictly is evaluated OFF for every install (FU-056), not a failure.
- **Full catalog:** `mode: "full"` is returned when `catalogVersion` is 0 or more than 20 versions behind. The full snapshot is about 1 MB compressed and signed (`.sig` file next to it).
- **Throttle:** the 24 h rule is applied by the server too. A sync within the window returns **200** with only `serverTime`, `nextSyncNotBefore` and `timeNonce`, so a wrong device clock can't hammer the API. The throttle answer is signed like every sync 200, and it carries the caller's nonce echo, so a throttle answer harvested by another install can't re-anchor this one (R4-2). The window is per install and uses the server clock only: `installs.last_sync_at` (set only by an effective sync, not by other calls) is claimed by a conditional `UPDATE ... WHERE last_sync_at IS NULL OR last_sync_at <= now - 24 h` in the same short transaction as the intake inserts and the daily-active count, so two concurrent syncs give exactly one full answer and one count. A throttled call writes nothing (not even `last_seen_at`); its contributions stay in the app's outbox. The body is still validated first. A full answer's `nextSyncNotBefore` is `serverTime + 24 h`; the throttle answer's is the previous sync + 24 h. If a full answer is lost on the wire, the retry gets the throttle answer and the app keeps its cursors and outbox until the next window (data is delayed, never lost).
- **Support-link notice (R4-7(2), SRS v1.7):** when support attached a purchase to an account (§5.3), the purchase's **buying install** (`purchases.install_id`) gets `supportNotice: "gold_linked_by_support"` in its signed sync and entitlement 200s. **Cleared on delivery, not on sending (R5-7):** every response that carries the notice also carries a fresh entitlement token, whose `iat` the server records in `purchases.support_link_notice_iat`. The flag `purchases.support_link_notice_pending` is cleared at the **next authenticated request from that install that proves delivery**: a `POST /v1/sync` whose `entitlementIssuedAt` is at or after `support_link_notice_iat` (the app stored that response). Until then each sync or entitlement 200 repeats the notice with a fresh token, so a lost response or a crash before storing loses nothing. The app writes the notice to `secure_state` when it stores the response and deletes it only after the user dismissed it, so a crash before display doesn't lose it either; a repeated notice that is already shown or dismissed is ignored (no new data from the app, BR-SYNC-03). The app shows a one-time message ("support linked your Gold to an account"), with the support link and the support code. A detach of that link clears the flag too. Other installs never see it.
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
// POST /v1/purchases/verify — iOS (StoreKit 2 signed transaction, JWS) + this install's seat key (D-55, optional)
{ "platform": "ios", "signedTransaction": "eyJhbGciOiJFUzI1NiIsIng1YyI6W…",
  "seatKeys": [ { "publicKey": "BPx…(65 bytes, base64url)", "signature": "Mz…(64 bytes, base64url)" } ] }
// 200 (signed)
{ "status": "active", "entitlement": { "token": "eyJ…" }, "seatHeldElsewhere": false, "accountRequired": false, "nextMoveAt": null,
  "serverTime": "…", "timeNonce": "…" }
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
5. If `seatKeys` is present, verify its single element over `op = verify` with `challenge = SHA-256(signedTransaction)` (§4.3 *Same-iPhone recognition*), and only after steps 1–4 succeeded. A valid key **registers** as this install's key if the install has none yet (`installs.seat_key_hash`, R4-1(1)), **untrusted** (`seat_key_trusted` stays false, R5-2: verify has no App Attest, so on stock iOS a user-CA proxy can swap the key; the store binding proves the payment, not the key's origin); when this install binds or holds the seat, its key hash is stored on the seat. A proof that fails verification, or whose key isn't this install's registered key, is **ignored** (nothing registered or stored, a diag counter incremented), never an error, because verify is the payment path (BR-GOLD-06).

**Seat at verify** (ADR-012 Part B (a), D-59, D-61(a)):
- A purchase with no seat yet: bind it to this (buying) install, `proof = binding`. Not a move.
- An existing seat held by this install: refresh; nothing moves.
- An existing seat held by another install, for a verify that is **not** a new payment from this install (for example a re-verify of an old transaction): the holder is unchanged, and this install gets no Gold from it.
- **A new payment from this install** for a purchase whose seat another install holds. This is a Google successor (`linkedPurchaseToken` names an existing purchase, whose seat, `account_id`, `attach_reclaim_used_at` and `next_move_at` the successor inherits), or an Apple transaction whose `transactionId` is new for its `originalTransactionId` with `transactionReason = PURCHASE`: an upgrade, downgrade, crossgrade or re-subscription. Then:
  - **account rule first (R4-4, D-46):** if the purchase is account-linked (`account_id` set, for Google also inherited by the successor), the move also requires a valid `Zaghlol-Account` token **for that account** on this verify request. Without it the seat **stays** on the holder whatever the cooldown, this install becomes a pending claimant (`channel = verify`), and the response is `200` with `seatHeldElsewhere: true`, **`accountRequired: true`** and `nextMoveAt` (or `null` when no cooldown runs). The app says the payment worked and asks the user to sign in here with the account that owns Gold; that sign-in is then an ordinary sign-in move (§4.6). So someone with access to the store account can't pull an account-linked seat to an install that isn't signed in to the account, and can't restart the owner's window that way;
  - **no cooldown running** (and the account rule met): the seat moves here (`seat_move:verify`, `next_move_at = ceil_hour(now + 30 d)`), and the old holder gets `status: moved`;
  - **cooldown running:** the seat stays on the holder, which keeps Gold on the new plan. This install becomes a pending claimant. The response is `200` with `seatHeldElsewhere: true`, `nextMoveAt`, and a token without that purchase; the app says the payment worked, Gold is on the other phone, and when it can move.
  - **Never refused:** in every case the purchase is verified and acknowledged before the seat decision. The seat decision never turns a valid payment into an error (BR-GOLD-06).

**Restore** (`POST /v1/purchases/restore`): FU-006, plus one-phone Gold and attestation per D-45, D-46, D-52…D-54 (FR-GOLD-02/03/07/08/09). Design: ADR-012 Amendment (2026-11-05), Part B as revised 2026-11-06.
```json
// Android: items from Play Billing queryPurchasesAsync (1–20) + Play Integrity standard-request token
{ "platform": "android",
  "purchases": [ { "productId": "zaghlol_gold_lifetime", "purchaseToken": "opaque-token-from-play" } ],
  "attestation": { "type": "play_integrity", "token": "eyJ…" } }
// iOS: StoreKit 2 signed transactions (1–20) + App Attest assertion over clientDataHash (attestationObject only on a new key's first use)
{ "platform": "ios", "signedTransactions": [ "eyJ…" ],
  "attestation": { "type": "app_attest", "keyId": "…=", "assertion": "o2lzaWduYXR1cmVY…", "attestationObject": "o2NmbXRv…",
                   "seatKeys": [ { "publicKey": "BPx…", "signature": "Mz…" }, { "publicKey": "BKq…", "signature": "Rt…" } ] } }
// 200 (signed)
{ "status": "active", "restoredCount": 1, "movedFromOtherPhone": true, "entitlement": { "token": "eyJ…" }, "serverTime": "…", "timeNonce": "…" }
// 409 (problem+json): every move was refused by the 30-day cooldown and nothing else grants Gold
{ "type": "https://api.zaghlol.app/problems/move-cooldown", "title": "Move not yet possible", "status": 409,
  "code": "MOVE_COOLDOWN", "nextMoveAt": "2026-12-06T10:00:00Z" }   // always a whole UTC hour (R3-4)
```
Possession of a genuine token is **not** proof of ownership. A token presented without valid attestation, or from an install that the seat or account rules exclude, counts as replayed (FR-GOLD-02) and grants nothing. The checks run in this order:

1. **Strict parse and request binding** (R2-1, R2-6).
   - The server parses the body **once** into a JSON object. Duplicate member names at any depth (inside `purchases[]` items and inside `attestation` too) and lone (unpaired) UTF-16 surrogates in any string give **`400 VALIDATION_FAILED`**. The DTO is bound from this same object, so the hashed and the processed body can't differ.
   - **Duplicate rejection is explicit (R3-8).** System.Text.Json accepts duplicate properties by default (the last one wins). The API therefore parses with `JsonDocumentOptions.AllowDuplicateProperties = false` (.NET 10; `JsonSerializerOptions.AllowDuplicateProperties = false` where the serializer reads directly), or an equivalent `Utf8JsonReader` pre-pass, plus its own lone-surrogate check.
   - `bodyHash = SHA-256("zaghlol-restore-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body without "attestation"))`, where JCS is RFC 8785 canonical JSON and `installId` is the lower-case hyphenated UUID text (36 ASCII bytes) of the install that the **install token** authenticates. It is never taken from the body or from `Zaghlol-Install`.
   - The app computes the same hash, from the body it is about to send and its own install ID, before asking the platform for a proof. A proof made for one install fails on every other install, even for a byte-identical body.
   - **Shared test vectors:** `backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json`. The Dart implementation (T-183) and the .NET one (T-185) must both reproduce them, and a contract test checks them. **Test requirements (R3-8):** T-185 posts every `invalid` vector to `/v1/purchases/restore` through the real pipeline and expects `400 VALIDATION_FAILED`; T-183 runs every `invalid` vector through the Dart strict parser and expects a rejection before any hash is computed.
2. **Attestation** (FR-GOLD-09, D-53; BR-SYNC-03 amended, D-45: the proof is the only device data sent, and no device identifier is stored). It is required on every restore. A missing, invalid or replayed proof, a proof not bound to this install and body, or (Android only) a stale one, fails the whole call with **422 `DEVICE_ATTESTATION_FAILED`**, and nothing is written.
   - **Android (Play Integrity, standard request).**
     - The app calls `prepareIntegrityToken` (warm-up, only when the user starts a restore) and then `request` with `requestHash = b64u(bodyHash)`.
     - The server calls `decodeIntegrityToken` and requires all of: `requestDetails.requestHash == b64u(bodyHash)`; `requestPackageName` = our package; `timestampMillis` no more than 5 min old (the only "expired" case, D-53); `appIntegrity.appRecognitionVerdict = PLAY_RECOGNIZED`; and `deviceIntegrity.deviceRecognitionVerdict` containing `MEETS_DEVICE_INTEGRITY`, or else `MEETS_BASIC_INTEGRITY` (see *Basic integrity* below).
     - **Optional verdicts are off** (R2-7): `deviceAttributes`, `recentDeviceActivity`, `appAccessRiskVerdict` and `environmentDetails` stay disabled in Play Console (T-140 checklist). If a decoded payload carries them anyway, the server ignores them: the DTO has no member for them, and they are never stored or logged.
     - Each token is single-use: its SHA-256 goes into `replay_guard` for 15 min.
   - **iOS (App Attest).**
     - **`clientDataHash` covers the seat public keys (R4-1(3)).** `seatKeysDigest = SHA-256(pk₀ ‖ … ‖ pkₙ₋₁)`, the raw 65-byte points of `attestation.seatKeys` in request order (SHA-256 of the empty string when `seatKeys` is absent), and `clientDataHash = SHA-256("zaghlol-restore-attest-v1" ‖ 0x00 ‖ bodyHash ‖ seatKeysDigest)`. The signatures stay outside it (each one signs `bodyHash`), so there is no circularity: the app signs `bodyHash` with its seat keys first, then asks App Attest for the assertion. A proxy with a user-installed CA therefore can't add, drop, reorder or replace a public key in a genuine install's restore (the R4-1 relay), because the assertion would no longer verify. Vectors: `restore-binding-v1.json` (`seatKeysDigestHex`, `clientDataHashHex`).
     - The app sends `assertion = generateAssertion(keyId, clientDataHash)`.
     - The server loads the key registered to **this** install (`app_attest_keys`) and checks: the signature over `nonce = SHA-256(authenticatorData ‖ clientDataHash)` with the stored public key; the RP ID hash = SHA-256(`<TeamID>.<bundleId>`); and a counter strictly greater than the stored one, which is then updated. iOS failure cases are an unknown or unattested key, a bad signature and a counter that doesn't increase (D-53).
     - **First use of a key:** the body also carries `attestationObject`, made with the **same** install-bound `clientDataHash` as the assertion. The server validates it per Apple's App Attest rules: the x5c chain to the Apple App Attestation Root CA; the nonce extension equals `SHA-256(authData ‖ clientDataHash)`; `keyId` = SHA-256 of the credential public key; App ID; counter 0; `aaguid` = production (or development in staging). Only then does it register the key, to the install named in the hash. A key therefore only ever registers to its own install. A key ID already registered to another install is refused.
     - **No server challenge** (D-53). Every proof is bound to the install whose token authenticates the request, so it is useless anywhere else. Within that install, Play tokens are single-use and expire after 5 minutes, assertions are counter-protected, and a replayed `attestationObject` only registers a key to the install it was made for, without the private key. A stored, unused proof could only be spent by the install that could make a fresh one anyway, so a challenge would add a round trip and server state and no security.
     - **Seat keys (D-55, D-62):** `attestation.seatKeys` carries the seat-key proofs over `op = restore` and `challenge = bodyHash` (*Same-iPhone recognition* below). Like the assertion, it is outside `bodyHash` and signs it; its public keys are inside `clientDataHash`.
     - **Key lifecycle:** one App Attest key per install. It is generated lazily at the first restore. The `keyId` is kept in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, so it never travels in backups or to a new phone). The app re-attests (new key plus `attestationObject`) when `generateAssertion` fails with `invalidKey`, when the server answers `DEVICE_ATTESTATION_FAILED` to a request without `attestationObject` (key unknown, for example after the server purged the install), and on every new install. "Delete everything" deletes the key row together with the install.
   - **Transport:** release Android builds trust only system CAs (`network_security_config`), so a user-installed CA can't read or rewrite restore bodies and proofs (ADR-012 Part B (d)).
3. **Store verification** of each item, as in verify, except the install-binding check (step 4 on Android; `appAccountToken` on iOS), which names the old install after a phone change.
4. **Account rule** (FR-GOLD-08e, D-61(c)). A purchase with `account_id` set moves to, or is granted on, only an install presenting a valid account token for **that** account, the current holder included. Otherwise the item's outcome is `account_required`, and the app says "sign in with the account that bought Gold", without revealing which account (EC-65). Restore never sets or changes `account_id` (§4.6 says when it is set).
5. **The seat** (FR-GOLD-08a–d/f, BR-GOLD-07, `purchase_seats`).
   - Each purchase has **one** seat, held by one install or vacant. Verify binds it to the buying install; that bind is not a move.
   - **Same holder:** if the caller already holds the seat, nothing changes and Gold is granted. A restore on the same install is never a move.
   - **Same iPhone, new install (D-55, D-63, D-65(a)):** if the caller presents in `attestation.seatKeys`, at a position **other than 0**, a key whose keyed hash equals the seat's `device_key_hash`, and element 0 is the caller's registered key (see *Same-iPhone recognition* below), the seat passes to the caller as a **rebind**: no cooldown check, `next_move_at` unchanged, `seat_rebind:restore`, `movedFromOtherPhone: false`. At most **2 rebinds per purchase per rolling 30 days** (D-63). Over the cap the same match is an **over-cap rebind** (D-65(a)): the seat still passes to the caller and is never refused, but the window restarts (`last_moved_at = now`, `next_move_at = ceil_hour(now + 30 d)`), `seat_rebind_over_cap:restore`, and the `seat_rebind` alert fires.
   - **Move:** otherwise (another holder, or vacant), the seat moves to the caller only if `next_move_at` is null or `now ≥ next_move_at`. The move sets `last_moved_at = now` and `next_move_at = ceil_hour(now + 30 d)`, the next whole UTC hour (R3-4), and writes `seat_move:restore`. The response's `movedFromOtherPhone` is `true`, and the app says Gold left the other phone.
   - **Cooldown:** if the move isn't allowed, that item is refused. Nothing that affects Gold is written. The server only records the caller as one of the purchase's **pending claimants** (`seat_claimants`: up to 3 per purchase, each kept 7 days; a fourth replaces the oldest; a repeat by the same install refreshes its entry). The entry also keeps the keyed hash of the caller's registered seat key, if any. A support move may target a claimant (§5.3). If no item ends `active` or `pending` and at least one was refused for the cooldown, the whole call fails with **`409 MOVE_COOLDOWN`** and `nextMoveAt` = the stored, hour-rounded `next_move_at` (the earliest one if several). The server enforces exactly that value. The app shows the date, formatted for the locale, and a support link (EC-68). A refused restore is never a move (EC-66).
   - **Android reinstall:** "Delete everything" or reinstalling creates a new install ID, so restoring afterwards **is** a move, even on the same phone (D-55). The app warns before "Delete everything" while it holds a seat.
   - **The old holder** isn't issued Gold for that purchase again. At its next sync or `GET /v1/entitlement` it receives a token with `status: "moved"` (and `movedBy`). If it stays offline, its cached token lapses at its `graceUntil` in trusted time: **at most 7 days after the move** (6 days for a `basic` seat).
   - **Vacant seats** come from `DELETE /v1/installs/me` and the 12-month inactive-install purge. Taking a vacant seat is a move, unless it is a same-iPhone rebind.
   - **Operator move:** support can move a seat past the cooldown, and that move restarts the window (§5.3, D-56).
6. **Basic integrity** (R-19). A Play verdict with `MEETS_BASIC_INTEGRITY` but not `MEETS_DEVICE_INTEGRITY` (often a custom ROM) is a valid attestation. The device may hold the single seat under the same cooldown, with `proof = basic` and a token `exp` ≤ `iat` + 2 days (6-day window, below). A device with no integrity label at all (rooted, emulator) gets `422 DEVICE_ATTESTATION_FAILED`, as do devices where App Attest is unsupported. Their way to Gold is sign-in (for an account-linked purchase) or support.
- **Aggregate.** Per-item outcomes fold into `status` by the precedence `active > pending > account_required > expired > refunded > invalid`. `restoredCount` counts `active` items. `entitlement` is the merged entitlement after the restore, or `null`. The only 422 is `DEVICE_ATTESTATION_FAILED`, and the only 409 is `MOVE_COOLDOWN`.
- **Lock-out mitigations (R-19, R-21):**
  - **Sign in.** An account-linked purchase reaches the owner's other phone through sign-in (§4.6, FR-GOLD-07), under the same cooldown. The ID token is the proof there, so no attestation is needed. After purchase, the buying phone suggests "sign in on this phone to protect your Gold" (FR-ACCT-01, D-54).
  - **Support.** The operator support lookup (FR-BE-08) shows the purchase, its seat, its claimants and the next-move date. The audited support move (§5.3), after a live order-ID check, handles phones lost inside the cooldown (EC-68) and buying phones gone before linking (FR-ACCT-05).
  - **Outages are not failures.**
    - Platform-side transient errors (Play Integrity `NETWORK_ERROR`, `TOO_MANY_REQUESTS`, `GOOGLE_SERVER_UNAVAILABLE`, outdated Play services; App Attest `serverUnavailable`) are retried by the app with back-off: 3 tries within 1 min, then a "try again later" message that also offers to update Play services when that's the cause. The app doesn't call restore without a proof.
    - A server-side decode failure (Google or Apple 5xx, timeouts, our quota) is **`503 UPSTREAM_UNAVAILABLE`** with `Retry-After`, never `422`.
    - The current holder keeps its cached Gold throughout.
  - **Quota.** Restores are rare (phone changes), and `prepareIntegrityToken` runs only when a restore starts. T-140 checks the Play Integrity daily quota in Play Console before launch and alerts at 50 % use, with a quota-increase request as the runbook action.
- **Abuse limits:** restore has its own bucket (5/hour per install) and a per-purchase limit (10 attempts/day across installs). Both give `429`. Store and attestation calls draw on a global Play / App Store budget that reserves capacity for verify and the ack sweeper. When the budget is short, restore gets `503 UPSTREAM_UNAVAILABLE` with `Retry-After` and never delays an acknowledgement.
- **Alerts** carry the purchase UUID only, never a token, transaction ID, install ID or account ID:
  - a spike in `MOVE_COOLDOWN` refusals;
  - more than 2 support moves for one purchase in 90 days, with the runbook action of §5.3;
  - `seat_rebind`: an over-cap same-iPhone rebind (D-63, D-65(a)), with the runbook action of §5.3;
  - an attestation-failure rate spike, by reason code;
  - Play Integrity quota above 50 %.
- **Verify needs no attestation** (the decision FR-GOLD-09 leaves open). The store-side binding (`obfuscatedExternalAccountId` / `appAccountToken` = HMAC(installId)) already proves that this install made the purchase. A token bound to another install fails with `PURCHASE_NOT_OWNED`, which already rejects the replay FR-GOLD-02 describes. Attestation would add latency and new failure modes to the payment path, which has to keep retrying (BR-GOLD-06), with no security gain. Verify **binds** the purchase's seat to the buying install (`proof = binding`) when the purchase has no seat yet. It changes an existing holder only for a new payment from this install (D-59), and only when no cooldown is running (D-61(a)); see *Seat at verify*.

**Same-iPhone recognition** (D-55, D-62, D-63, D-65(a); ADR-012 Part B (g); BR-SYNC-03 amended).
- **On the phone:** each iOS install creates one Secure Enclave P-256 **seat key**. Its wrapped key is kept in a Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, so it survives an app reinstall but no device erase, and never moves to another device. The app keeps its own key and the keys of up to 4 earlier installs on the same iPhone, newest first. "Delete everything" keeps the seat keys and deletes everything else.
- **Field `seatKeys`:** an array of `{publicKey, signature}`. Element 0 is the calling install's own key; the others are earlier installs' keys (D-62 keeps this multi-key design). The public keys are distinct; a repeated key is `400 VALIDATION_FAILED`.
  - `publicKey`: X9.63 uncompressed P-256 point, 65 bytes, base64url without padding.
  - `signature`: ECDSA P-256 / SHA-256, IEEE P1363 `r‖s` (64 bytes), base64url, over

    `message = "zaghlol-seat-v1" ‖ 0x00 ‖ op ‖ 0x00 ‖ installId ‖ 0x00 ‖ challenge`

    `installId` is the lower-case UUID text of the install that the install token authenticates. `op` and `challenge` (32 bytes) are:

    | Where | `op` | `challenge` | Max keys | Public keys covered by |
    |---|---|---|---|---|
    | `POST /v1/purchases/verify` (top level) | `verify` | SHA-256 of the `signedTransaction` string | 1 | — (verify never rebinds) |
    | `POST /v1/purchases/restore` (inside `attestation`, outside `bodyHash`) | `restore` | the install-bound `bodyHash` | 5 | the App Attest `clientDataHash` (step 2, R4-1(3)) |
    | `POST /v1/accounts/signin` (top level) | `signin` | SHA-256 of the raw `nonce` | 5 | nothing: sign-in has no device attestation (bounded below) |
  - **Binding:** every signature covers this install and a single-use challenge (the attested body, or the single-use sign-in nonce), so a proof can't be replayed for another install or request. The private key can't be extracted from the Secure Enclave, so a key can't be **cloned** to another phone. It can still be **used remotely**: on a jailbroken iPhone a hooked app can sign any message a relay asks for (a *signing oracle*). The rules below bound what an oracle gains.
  - **iOS installs only:** the Android request schemas have no such member, and `seatKeys` on sign-in from an Android install is `400 VALIDATION_FAILED`. On restore and sign-in, a point that isn't on the curve or an invalid signature is `400 VALIDATION_FAILED`. On verify it is ignored instead (payment path, BR-GOLD-06).
  - **Shared vectors:** `backend/tests/Zaghlol.Contract.Tests/vectors/seat-proof-v1.json` (signatures) and `restore-binding-v1.json` (the restore `clientDataHash`), checked by contract tests. T-183 (Dart), T-182 (.NET seat-key verifier) and T-185 (restore) must pass them.
- **Element 0 is bound to the install (R4-1(1)).** `installs.seat_key_hash = HMAC-SHA256(K_seat, "install" ‖ 0x00 ‖ installId ‖ publicKey)` (the `"install"` label keeps it apart from the per-purchase hash, which starts with a UUID).
  - **Registration:** the first request from an install that carries a valid `seatKeys` (verify after its store checks pass, restore after attestation passes, or sign-in after the ID token is verified) stores the hash of **element 0**. It is never replaced while the install exists. The registered key is the only key that can become a seat's key for this install.
  - **Mismatch:** a later restore or sign-in whose element 0 isn't the registered key gets **`400 SEAT_KEY_MISMATCH`**, and nothing is written. The app retries once without `seatKeys`, which is then an ordinary request (no rebind possible). This happens only if the install's own key became unusable; a relay that puts someone else's key in element 0 is refused. On verify a mismatching proof is ignored. **App behaviour (R5-6):** after one `SEAT_KEY_MISMATCH` that the retry without keys confirmed (the retry succeeded), the app persists "own seat key unusable for this install" in `secure_state` and stops sending `seatKeys` from this install (it still keeps the key list for a later install on this iPhone), so later sign-ins don't each cost a 400 and a second provider prompt. The flag goes with the install ID on re-registration.
  - **Trusted registration** (`installs.seat_key_trusted`, R5-2): set **only** by an **App Attest-covered request**, that is a restore whose App Attest assertion verified over a `clientDataHash` that covers this element 0 (step 2). iOS sign-in carries no App Attest (D-66; option (a) of ADR-012 (g) was rejected), so sign-in never sets it. Verify still **registers** element 0 (so a reinstall right after purchase is recognised) but leaves it **untrusted**: its store binding proves that this install made the payment, not that the `seatKeys` element came from this iPhone's Secure Enclave, and on stock iOS a user-CA proxy can replace it. Sign-in likewise registers untrusted. The flag only goes from false to true, and it decides only the over-cap sign-in rule below.
  - **Order on restore (R5-6):** the element-0 check runs **after** App Attest verification (step 2), in the same transaction as the counter update. A mismatch is then `400 SEAT_KEY_MISMATCH` and the transaction rolls back, so the App Attest counter update is rolled back too and nothing is written; the assertion was install-bound and single-use by counter anyway, so a retry needs a fresh one. On sign-in it runs after the ID-token verification and the committed `replay_guard` insert (§4.6 step 5).
  - **Deletion:** the columns go with the install row (they are cleared when the install is tombstoned).
- **On the seat:** `purchase_seats.device_key_hash = HMAC-SHA256(K_seat, purchase_id ‖ publicKey)`, where `K_seat` is a dedicated KMS key.
  - It is written from the caller's **registered** key (element 0) whenever an iOS install becomes or stays the holder, together with `device_key_trusted` copied from the install's `seat_key_trusted`. It is set to `NULL` (and the flag to false) when a holder without a registered key takes the seat, and kept when the seat goes vacant. A support move sets both from the target install (§5.3, R5-4).
  - Matching runs only against the purchases in the request. The raw public keys are never stored or logged (D-62).
- **Rebind** (restore step 5, sign-in step 5). A non-holder caller rebinds a seat only if all of these hold:
  1. element 0 is the caller's registered key (registered in this same request if it had none);
  2. some element **at position 1 or later** has a valid signature and a keyed hash equal to the seat's `device_key_hash`. A match on element 0 is never a rebind: the caller's own key can't name a seat it doesn't hold, so it is handled as an ordinary move;
  3. attestation (restore), the ID token (sign-in) and the account rule pass, as for any move;
  4. **the cap (D-63):** fewer than 2 rebinds of this purchase in the last 30 days (`purchase_seats.recent_rebinds`, pruned under the seat lock).

  The seat then passes to the caller without checking or restarting the cooldown, `device_key_hash` becomes the hash of the **caller's registered key**, the rebind time is appended to `recent_rebinds`, and `seat_rebind:<restore|signin>` is written. The old holder, if it still exists, gets `status: moved`. Because the seat's key is now the new install's own Secure Enclave key, a relayed key can pull the seat **once**; the next hop needs the new holder's Secure Enclave as an oracle too.
- **Over the cap** (2 rebinds already in the rolling 30 days; D-63, D-65(a)), conditions 1–3 holding. The server recognises "the iPhone that holds the seat" only by condition 2, the key match against the seat (or the vacant seat that this iPhone's earlier install left). A caller without that match is "an iPhone that does not hold the seat" and follows the ordinary move rules.
  - **Over-cap rebind (D-65(a)):** the seat passes to the caller and is **never refused**, so an owner who reinstalls a third time on the phone that holds Gold keeps it, even when this month's move is already used. It is charged as the window: `last_moved_at = now`, `next_move_at = ceil_hour(now + 30 d)`, `device_key_hash` as above, `recent_rebinds` unchanged, `seat_rebind_over_cap:<restore|signin>`. This applies to **every over-cap restore match** (App Attest covers the keys), and to an **over-cap sign-in match only when the seat's key is trusted** (`device_key_trusted`, set only from an App Attest-covered request, R5-2);
  - **over-cap sign-in against an untrusted seat key:** an ordinary move under the cooldown (allowed if no cooldown runs, otherwise `moveRefused` and a pending claimant, `seat_rebind_over_cap:signin`), and the response sets `restoreSuggested: true`. The restriction exists because sign-in has no device attestation (below). *This narrows D-65(a) for sign-in (a seat whose key wasn't registered by an App Attest-covered request); the PO accepted the gate in round 5 and chose R5-3 option (b), no App Attest on sign-in (D-66, SRS v1.8).*
  - **Accepted residual (D-66):** the owner is **not** guaranteed to keep Gold on the holding iPhone in this case. Restore can take the over-cap rebind only when StoreKit on this iPhone has a signed transaction for the purchase. It has none for **Gold bought on Google Play** and carried to the iPhone by sign-in, or for an App Store purchase made under **a different Apple ID**; every seat key on that iPhone then came from sign-in and is untrusted. So a **third reinstall within 30 days** on the holding iPhone can be refused (`moveRefused`) for **up to 30 days** (until `nextMoveAt`), or until support moves the seat (§5.3; a support lead can end a dispute freeze, R5-5(b)).
  - **App behaviour with `restoreSuggested` (T-147, T-145):** the app asks StoreKit (`Transaction.currentEntitlements` / `Transaction.all`) whether this iPhone has a transaction for the purchase. If it has, it offers **Restore**, which takes the over-cap rebind path. If it hasn't (Play purchase, other Apple ID), it does **not** offer Restore: it shows the cooldown date (`nextMoveAt`, locale-formatted) and the **support path** (support link and support code), in copy that says Gold is safe and can come back to this phone by that date or through support;
  - every over-cap case raises the **`seat_rebind`** alert (purchase UUID only; runbook: check the purchase's events for a relay pattern).
- **How far a relay gets (R4-1, accepted residuals):**
  - **Restore:** the public keys are covered by App Attest, so on a **stock** iPhone a proxy can't insert a relayed key. Inserting one needs a modified app on a jailbroken iPhone that still passes App Attest. Two jailbroken iPhones that act as oracles for each other can swap Gold by restore without the cooldown, but only one of them holds it at a time, each over-cap swap restarts the window, and every swap is a `seat_rebind` event for review (D-65(a), R-19).
  - **Sign-in (R4-1(5), R5-2):** there is no device attestation, so on **stock iOS a user-CA proxy** in front of the genuine app (no jailbreak, no Secure Enclave oracle needed), or a modified client, holding the account's credentials can send any proofs, including a software key as element 0 (registered on that install's first sign-in, untrusted) and an oracle-signed or software key at position 1. It is bounded by the account rule (only the account's own credentials work), the element-0 registration (each install can name only its one key) and the cap: **at most 2 cooldown-free rebinds per purchase per 30 days**. Over the cap a sign-in passes the seat only from a trusted seat key, and the key it leaves on the seat is the caller's sign-in-registered (untrusted) key, so a chain of sign-ins can make at most one over-cap hop before it falls back to ordinary moves under the cooldown. Because a key is trusted only after an App Attest-covered request, a proxied verify can no longer make the first seat key trusted (R5-2); the jailbreak / Secure Enclave oracle precondition applies only to **restore**.
- **What the server sees (D-62, accepted):** every iOS restore and sign-in sends, inside TLS, the raw public keys of the calling install and of up to 4 earlier Zaghlol installs on that iPhone, also when no seat can match. Anyone with code-level access to the running API could therefore link installs of the same iPhone **in transit**. At rest there are only keyed hashes (one per install, one per seat), the keys are never logged (the redacting logger drops `seatKeys`, and request-body logging is off), and the privacy notice says so (security-model §2a).
- **Loss:** after a device erase or Keychain reset, or if the Secure Enclave fails, the app sends a new key or none, and the request is handled as on Android: an ordinary move under the cooldown, with support for a phone lost inside it (no other lock-out; the over-cap sign-in residual is D-66 above).

**Entitlement token** (JWS compact, ES256, `kid` header):
```json
{ "iss": "zaghlol", "sub": "<installId>", "acct": "<accountId|null>", "plan": "yearly",
  "status": "active", "exp": 1793829720, "graceUntil": 1794175320, "iat": 1793570520,
  "nextMoveAt": null, "movedBy": null,
  "src": [ { "store": "google_play", "product": "zaghlol_gold_yearly" } ], "v": 1 }
```
- **Status:** `status` ∈ `active | grace | expired | refunded | moved | paused | none`.
  - `moved` means the seat of a purchase this install held went to another install (FR-GOLD-08). `movedBy` is then `"user"` (restore, sign-in, plan change or reclaim) or `"support"` (D-57(f)); it carries no operator data. The app shows "Gold moved to another phone", or for `support` "support moved your Gold to another phone", with the support link and support code, and offers Restore, Sign in and support.
  - `paused` (D-61(c)) means this install holds the seat of an account-linked purchase but the request carried no valid account token for that account (signed out, or the account token expired). The seat stays reserved. The app shows "sign in to use Gold on this phone", and signing in again on this install is not a move.
- **`nextMoveAt`** is the earliest time the seat of a purchase in this token can move again by restore or sign-in: the stored, hour-rounded `next_move_at`, or `null` when no cooldown is running. The app uses it for the cooldown copy, including the Android "Delete everything" warning.
- **`acct`** is the account whose token was presented. It is set when the token covers an account-linked purchase.
- **Lifetime rule (D-60, BR-GOLD-03/07):** for **every** plan, lifetime included, `exp` ≤ `iat` + 3 days; for a subscription, also ≤ the store expiry; for a token covering a `basic` seat, `exp` ≤ `iat` + 2 days. `graceUntil = exp + 4 days`. A token is therefore honoured for at most **7 days** of trusted time after `iat` (6 days for `basic`). A phone that lost the seat, or a revoked purchase, loses Gold offline within that bound.
- **Refresh (FR-GOLD-04):** the app calls `GET /v1/entitlement` whenever it runs online (start, resume, background task) and its cached token is at least **12 h** old. `POST /v1/sync` also returns a fresh token when the cached one (`entitlementIssuedAt`) is more than 12 h old or anything changed. A holder that was online with the app running at time *t* holds a token at most 12 h old, so it keeps Gold offline until at least *t* + 6.5 days (full) or *t* + 5.5 days (basic), less any reboot charges below. That is at least 5 days.
- **Which purchases count:** the token covers only purchases whose seat this install holds. Account-linked purchases are covered only when the request carries a valid account token for their account (D-61(c)); otherwise they are reported as `paused`.
- **App rules (T-144):**
  - **Install binding (R5-1).** The response signature binds the body, not the install (§1), so on stock iOS a user-CA proxy can hand one install's signed body to any number of phones. The app therefore **honours an entitlement token only if its `sub` equals the app's own current install ID** (the lower-case UUID text it registered with, compared as an exact string), and **an account token only if its `iid` equals the app's own current install ID**. A token that fails this check is **ignored**: it isn't cached, it grants nothing, and it doesn't replace or clear the token already cached. It also never re-anchors trusted time: a body whose entitlement or account token fails the check is treated as *any other signed body* below (raise only), even if it echoes the outstanding nonce. A mismatch only increments a local diag counter (`entitlement_sub_mismatch` / `account_iid_mismatch`); no user message, no error, no log of the token or IDs.
  - **Re-registration.** When the app re-registers (`401 INSTALL_TOKEN_INVALID` → new install ID, §6), it deletes the cached entitlement token and the account token at once, before the new registration completes, so a token whose `sub` or `iid` names the old install is never honoured again. Gold returns only through the new install's own restore or sign-in, under the ordinary rules.
  - The app grants Gold only for a signature-verified token that passes the install binding, with `status ∈ {active, grace}`, while the trusted-time check below passes and `hw < graceUntil`. `grace` is shown from `hw ≥ exp`.
  - A token with `acct` set is honoured only while the app holds an unexpired account token, itself passing the `iid` check, whose `sub` equals `acct`.
  - At sign-out the app deletes the cached entitlement token at once, whether or not the network call succeeds, and stores the fresh token the sign-out response returns (§4.6).

**Trusted time** (R3-1, R4-2, R4-3, D-60(c), NFR-SEC-08; T-144 contract). The device's wall clock never decides Gold on its own.
- **State** (one record in the encrypted `secure_state`, never in preferences or files):
  - `hw`: the trusted-time high-water mark, epoch ms. It includes the reboot charges and is what Gold is judged against;
  - `lb`: the **uncharged lower bound**, epoch ms: the latest time the device can prove has passed, without the reboot charges. Invariant `lb ≤ hw`. The tamper test uses `lb` (R4-3);
  - `mono`, `boot`: the monotonic reading and the boot reference when the state was last written;
  - `lastServerTime`: the newest signed server time seen;
  - `tampered`: a flag.

  In memory only (lost on process death, which is safe): `pending = {nonce, sentMono, sentBoot}`, the time nonce of the single outstanding anchoring request.
- **Clock sources** (`TrustedClockHostApi`, `platform-channels.md` §4b):
  - **monotonic** `m`, which includes deep sleep:
    - Android `SystemClock.elapsedRealtime()`;
    - iOS `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (`mach_continuous_time`), which keeps counting in sleep, unlike `systemUptime` and `CLOCK_UPTIME_RAW`. T-144's device test confirms this;
  - **boot reference** `b`:
    - Android `Settings.Global.BOOT_COUNT`;
    - iOS: none is public. The app uses `wall − m`;
  - **wall** `w`: the epoch clock.
- **Sending an anchoring request (R4-2).** Before each anchoring request (§1) the app draws a fresh 128-bit nonce from a CSPRNG, sends it in `Zaghlol-Time-Nonce`, and sets `pending` to it, **replacing** any earlier one: only the most recent anchoring request can re-anchor, and older nonces are discarded. The app never sends two anchoring requests with the same nonce and serializes them through one time-anchor service.
- **Receiving a signed response.** Only after its signature verifies. Let *S* be its `serverTime`, and `iat` the token's issue time when it carries a new token.
  - **Fresh echo** (re-anchor): every entitlement and account token in the body passes the install binding (*App rules*, R5-1), the body's `timeNonce` equals `pending.nonce`, the response arrived on the same boot as `pending` and within **60 s** of `sentMono` by the monotonic clock. Then `hw = lb = S`, `mono = m`, `boot = b`, `tampered = false`, `lastServerTime = max(lastServerTime, S)`, and `pending` is cleared (single use). This is the **only** way to lower `hw` or `lb` or to clear `tampered`.
  - **Any other signed body** (no echo, another nonce, a stale or reused echo, an `Idempotency-Key` replay, a body from another install, a body whose token's `sub` or `iid` isn't this install, a response the network withheld and released later): **raise only**. `hw = max(hw, S, iat)`, `lb = max(lb, S, iat)`, `lastServerTime = max(lastServerTime, S)`. `tampered` is left as it is. A signed time is real time that has passed, so raising is always safe; only its freshness was unproven.
  - An unsigned or unverified response never touches the state.
- **Advance** (at app start and resume, every 60 s while in the foreground, in background tasks, and before every Gold check):
  1. **Classify the interval** since the last write:
     - **same boot:** Android `b = boot` and `m ≥ mono`; iOS `m ≥ mono` and `|b − boot| ≤ 10 min`. Then `lower = m − mono` and `charge = lower`;
     - **reboot proven by the clock:** Android `b ≠ boot` or `m < mono`; iOS `m < mono`. Then `lower = m` (at least the uptime has passed) and `charge = max(m, 6 h)`;
     - **iOS boot reference shifted, monotonic not behind** (`m ≥ mono`, `|b − boot| > 10 min`): either a reboot whose uptime already passed `mono`, or a wall-clock correction (NITZ or NTP after a long offline spell) with no reboot. Both are consistent with `lower = m − mono`, and the charge is `max(m − mono, 6 h)`, so `mono` isn't counted twice (R4-3(b)).
  2. **Tamper test on the uncharged bound:** if `w < lb + lower − 10 min`, set `tampered = true`. The 6-hour charge is not part of this test, so an honest quick reboot is never flagged (R4-3(a)).
  3. **Update:** `lb = max(lb + lower, w)` unless the test just failed (then `lb = lb + lower`); `hw = max(hw + charge, lb)`.
  4. Persist `hw`, `lb`, `mono = m`, `boot = b` (and `tampered`).
- **Decision:**
  - **No Gold** while `tampered`: "connect to check Gold". Local data stays readable (BR-GOLD-04). Only a fresh echo clears the flag.
  - Otherwise, Gold while `hw < graceUntil`.
  - A token whose `iat` is more than 10 minutes ahead of `hw` after anchoring is not trusted.
  - Moving the clock forward only raises `lb` and `hw`, so it never extends Gold. Time-zone and DST changes don't affect the epoch clock (EC-70).
- **Required unit tests (T-144):** each runs on fake clock sources and a fake signer.
  - rollback while offline (withheld; recovered by a fresh echo);
  - small backward NTP adjustments under 10 minutes (no effect);
  - a forward jump, then an honest correction (expires early, recovers online);
  - reboot on Android (`BOOT_COUNT` change) and on iOS (`m < mono`), including the 6-hour minimum charge to `hw`;
  - **honest quick offline reboot (R4-3(a)):** used at *t*, rebooted at *t* + 5 min, opened at *t* + 7 min with a correct wall clock: not tampered, `hw` charged 6 h, `lb ≈ w`; and still not tampered on every following 60 s advance;
  - **iOS wall correction without reboot (R4-3(b)):** `m ≥ mono`, boot reference shifted by 2 h: charge `max(m − mono, 6 h)`, not `m`; tamper decided against `lb + (m − mono)`;
  - **another install's signed body (R4-2):** a validly signed sync or throttle body with a larger *S* below `hw` and a nonce this app never sent: `hw` and `lb` not lowered, `tampered` not cleared;
  - **withheld older response (R4-2):** the app's own earlier request, answered with its own nonce but delivered after a newer request was sent, or more than 60 s after sending: raise only;
  - a fresh echo used twice (second time raise only), and an `Idempotency-Key` replay whose body echoes an older nonce (raise only);
  - **a validly signed token for another install grants nothing (R5-1):** a correctly signed `GET /v1/entitlement` and sync body with `status: active`, a future `exp` and `sub` = another install ID, delivered with this app's own fresh nonce echo: no Gold, the cached token is unchanged, `hw`/`lb` only raised (no re-anchor, `tampered` not cleared), the diag counter incremented;
  - **an account token with a foreign `iid` is not honoured (R5-1):** a signed sign-in or sync body whose `accountToken` has `iid` ≠ this install, together with an entitlement token whose `acct` equals that token's `sub`: the account token isn't stored, the `acct` purchase isn't granted, and no re-anchor;
  - after re-registration (`INSTALL_TOKEN_INVALID`), the cached token for the old install ID is gone and a replayed old-`sub` body grants nothing;
  - a long offline period with the clock untouched (Gold until exactly `graceUntil`);
  - an old signed response replayed (doesn't lower `hw`);
  - an unsigned response (ignored);
  - the 12 h refresh boundary, and the 5-day holder guarantee with one reboot.

### 4.4 `GET /v1/entitlement`
Returns `{entitlement: {token}, serverTime, timeNonce, supportNotice}` (`timeNonce` echoes `Zaghlol-Time-Nonce`, §1; `supportNotice` as in §4.2), covering the purchases whose seat this install holds. Account-linked purchases count only with a valid `Zaghlol-Account` token for their account; otherwise they are `paused` (D-61(c)). The app calls it after a restore, after sign-in, and whenever it runs online with a cached token at least 12 h old (§4.3). It never moves a seat: only verify (a new payment, D-59), restore, sign-in and the support move do. If this install lost a seat since its last token, the new token has `status: moved` and `movedBy`.

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
{ "provider": "apple", "idToken": "eyJ…", "nonce": "<raw client nonce, ≥128-bit base64url>", "authorizationCode": "c1a…",
  "seatKeys": [ { "publicKey": "BPx…", "signature": "Mz…" } ] }          // iOS installs only, optional (D-55)
// 200 (signed); also when a move was refused for the cooldown (R3-5): then "moveRefused": true and "nextMoveAt" is set
{ "accountId": "uuid", "accountToken": "eyJ…", "entitlement": { "token": "eyJ…" }, "linkedInstalls": 2,
  "movedFromOtherPhone": false, "moveRefused": false, "restoreSuggested": false, "nextMoveAt": null, "serverTime": "…", "timeNonce": "…" }
```

**Verification:**
- **Google:** `aud` must be one of our OAuth client IDs; check `iss` and `exp`; JWKS from Google.
- **Apple:** `aud` must be our Services ID or bundle ID; `iss = https://appleid.apple.com`. The `authorizationCode` is exchanged for a refresh token, stored encrypted and used **only** to revoke on deletion.
- **Nonce and replay (both providers, ADR-016 amendments 2 and 3):**
  - The app generates a **raw** nonce: ≥ 128 bits from a CSPRNG, base64url without padding (`^[A-Za-z0-9_-]{22,128}$`). It gives the provider only `hex(SHA-256(raw))`, the lower-case hex SHA-256 of the raw string's ASCII bytes. It sends the **raw** value in `nonce`.
  - The server computes `hex(SHA-256(nonce))` and compares it with the token's `nonce` claim in constant time. Someone holding only the token knows the claim but not its pre-image, so a copied claim doesn't pass.
  - **Required for both providers** (R2-9). A request without `nonce`, or an ID token without a `nonce` claim, gives `422 ID_TOKEN_INVALID`. Google: the app passes the hashed nonce to Credential Manager (`GetGoogleIdOption` / `GetSignInWithGoogleOption.setNonce`) on Android and to GoogleSignIn-iOS (`signIn(withPresenting:hint:additionalScopes:nonce:)`) on iOS; `google_sign_in` 7.x exposes it as `initialize(nonce:)` (T-147 checks that a fresh nonce can be set for every attempt).
  - A token whose `iat` is more than 10 minutes old gives `422 ID_TOKEN_INVALID`.
  - Single use: the server inserts the nonce claim's hash into `replay_guard` (`backend-schema.md`), kept until the token's `exp`. A second use of the same token gives `422 ID_TOKEN_INVALID`. The insert is committed **on its own, before and outside** the account and seat transaction (R3-5), so no later rollback can make the same ID token and nonce usable again.
  - An `Idempotency-Key` replay returns the stored result before this check runs, so legitimate retries still work. The stored result is returned only to the same install, for the same key and an identical body (§1), so it can't hand an account token to anyone else.

**After verification** (one transaction, after the `replay_guard` insert above; it always commits steps 1–4, R3-5):
1. Upsert the account.
2. Link the install.
3. **Attach** (D-54, FR-ACCT-05). Set `account_id` (and `account_linked_by = 'signin'`) only on purchases with no account yet **and** `purchases.install_id` = this install, the buying install bound by verify. There is no other self-service attach: a purchase whose buying install is gone (reset, lost, sold or purged) is linked only by support (§5.3). Restore-acquired seats never attach a purchase, so someone with a leaked token can't lock the owner out.
4. **Seat at attach time** (R2-2(a), D-58, D-61(b), R3-3). After attach, the seat must be on an install linked to this account. If the holder is this install or another install linked to the account, it stays. Otherwise:
   - if `purchases.attach_reclaim_used_at IS NULL`, the seat moves to this (buying) install even inside a running cooldown: the **account-attach reclaim**. It sets `attach_reclaim_used_at = now`, `last_moved_at = now` and `next_move_at = ceil_hour(now + 30 d)`, so it counts as the move (D-61(b)), and writes `seat_move:account_attach`. The previous holder gets `status: moved`. `attach_reclaim_used_at` is never cleared, account deletion included, so this happens **once per purchase** (D-58, EC-72);
   - otherwise it is an ordinary step-5 move under the cooldown.
5. **Seat moves** (FR-GOLD-07/08, D-52, D-55). For each purchase linked to the account whose seat is on another install (or vacant):
   - first the element-0 rule of §4.3 *Same-iPhone recognition*: an element 0 that isn't this install's registered key is `400 SEAT_KEY_MISMATCH`. This check runs before step 1 so that nothing is linked by a rejected request; the `replay_guard` insert has already been committed, so the app retries with a fresh ID token and nonce, without `seatKeys`;
   - a same-iPhone **rebind** if a valid `seatKeys` proof (`op = signin`, `challenge = SHA-256(nonce)`) at position 1 or later matches the seat's `device_key_hash`, within the D-63 cap (`seat_rebind:signin`, no cooldown, §4.3). Over the cap it is the D-65(a) over-cap rebind (never refused, window restarts) when the seat's key is trusted, and otherwise an ordinary move with `restoreSuggested: true` and the D-66 accepted residual and app behaviour (§4.3; `seat_rebind` alert either way);
   - otherwise a move under the 30-day cooldown of §4.3 step 5 (`proof = account`; the ID token is the proof, so no attestation is needed). When this install becomes or stays the holder, the hash of its registered key is stored.
   - **Bound on relayed proofs (R4-1(5), R5-2):** sign-in has no device attestation, so a user-CA proxy on a stock iPhone, or a modified client, with the account's credentials controls `seatKeys` completely. What it can gain is bounded by the account rule, the element-0 registration and the D-63 cap: at most 2 cooldown-free rebinds per purchase per rolling 30 days, plus at most one over-cap hop from a trusted seat key, then ordinary moves under the cooldown (§4.3).

   The response's `movedFromOtherPhone` is `true` when a seat moved. A purchase that isn't linked to the account is never moved by sign-in: on a new phone it is reached only through restore (FR-ACCT-05).
6. **Refused moves don't undo the link (R3-5).** A move refused for the cooldown records this install as a pending claimant and changes nothing else. Steps 1–4 stay committed. The call returns **200** with the account token, `moveRefused: true`, `nextMoveAt` (the earliest refused one) and an entitlement without those purchases. Sign-in never answers `409 MOVE_COOLDOWN`, so the owner can always link and protect the purchase from the buying phone during a cooldown.

**Sign-out** (`POST /v1/accounts/signout`, D-61(c), FR-ACCT-03) unlinks the install and doesn't change, release or move seats. It returns **200** (signed) `{entitlement, serverTime, timeNonce}`: a fresh token without account-linked purchases, which are now `paused` on this phone until the user signs in again here (EC-73, not a move). Unlinked purchases are unaffected. The app deletes its cached token at sign-out even if the call fails, so account-linked Gold pauses offline too.

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

`DELETE /v1/accounts/me` removes the account and its links, revokes the Apple token, and deletes every `idempotency_records` row that holds this account's token (R3-6). Purchases keep their seats and their `attach_reclaim_used_at`; their `account_id` becomes `NULL`, so a later link from the buying phone is a new attach without a second free reclaim (D-58, EC-72). Any account token for the deleted account is rejected from then on (§3).

### 4.7 Delete install (FR-ONB-08)
`DELETE /v1/installs/me` returns 202 and tombstones the install; its tokens stop working at once. The app wipes local data **before** calling this endpoint and does not depend on it succeeding. A failure is retried once, then given up, because the install expires after 12 months of no syncs anyway.

### 4.8 Shapes fixed by the OpenAPI file (T-006; architect sign-off 2026-11-05)
These details were not spelled out above. `backend/openapi/zaghlol-v1.yaml` is authoritative for field names, limits and patterns. The solution-architect reviewed the T-006 inferences on 2026-11-05. The items below are signed off as written or corrected as noted.
- **Success statuses without a body:** `DELETE /v1/installs/me` returns 202; `DELETE /v1/accounts/me` returns 204; `POST /v1/accounts/signout` returns **200** with a signed `{entitlement, serverTime}` (*corrected* 2026-11-06 for D-61(c), previously 204); `POST /v1/notifications/google` returns 204; `POST /v1/notifications/apple` returns 200; `DELETE /admin/v1/catalog/draft/{entity}/{id}` returns 204. *Signed off*, except the sign-out correction.
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
- **Prices (T-127).** Gold is the closed set `XAU24_G`, `XAU21_G`, `XAU18_G` (per gram) in `EGP` and `USD`; FX is quoted with base `USD`. Providers are pluggable (`IPriceProvider`, `Prices:Providers`, hourly worker); a karat the feed lacks is derived from the purest karat present (`k / 24`), and a missing USD price from the EGP price and the `USD→EGP` rate, rounded to 2 decimals (`source` ends in `+derived`). The served value is an unexpired override, else the last feed value; **stale** = the newest gold feed fetch or the newest FX fetch is more than 24 h old, each kind judged on its own (T-128; an override does not hide it). `asOf` stays the newest feed time of either kind; the app may also derive staleness from it. `PUT /admin/v1/prices/override` (`prices_admin`, not idempotency-keyed) validates before anything is written, and every failure is `400 VALIDATION_FAILED`: symbol and currency in the sets above, `price` an ASCII decimal string above 0 with at most 12 integer and 6 decimal digits, `reason` 3-200 characters with no control character and no `@` (the audit CHECK forbids it; the API must refuse first), `expiresAt` omitted = now + 24 h, otherwise after now and at most now + 7 days. One `audit_log` row (`price_override`, target `price:<symbol>:<currency>`, details `{price, expires_at, reason}`) is written in the same transaction. The response is `{symbol, currency, price, asOf}`; the expiry is not echoed. Ending an override early exists as a service method (`price_override_clear` audit action; it sets the expiry to now) with no HTTP route until T-137 decides how the CLI reaches it.
- **Feature flags (T-126).** The flag set is closed: `zakah`, `smart_roi`, `roi_named_products`. A well-formed key outside the set is `404 NOT_FOUND` on both `GET` and `PUT` (a typo can't create a flag); a malformed key is `400 VALIDATION_FAILED`. A known flag nobody has set reads as `{value: false, rules: {}, version: 0, updatedAt: "1970-01-01T00:00:00Z"}` (default OFF). `PUT` is not idempotency-keyed: it sets absolute state, increments `version` by 1 and writes one `audit_log` row (`flag_update`, target `flag:<key>`) in one transaction, then posts to the ops channel (`OpsChannel:WebhookUrl`, best effort; a failed post never fails the change). A `rules` object replaces the stored rules as a whole, `{}` clears them, and an absent `rules` keeps them. `rules` members are closed (`400 UNKNOWN_FIELD`); `platforms` is a non-empty unique subset of `android`, `ios`, `minAppVersion` is `major.minor.patch` and `rolloutPercent` is 0 to 100. **Evaluation** (`FlagEvaluator`, used by `/v1/sync`): a flag is ON for an install only if its value is ON and every present rule holds; an install version with a `-pre` or `+build` suffix is compared on its numeric part; the rollout bucket is `SHA-256("zaghlol.flag.v1:" + key + ":" + installId)` over the UTF-8 text, with `installId` as the lowercase hyphenated UUID (`00000000-0000-4000-8000-000000000001`; FU-056, known-answer vectors in `FlagStrictRulesTests`), first four bytes big-endian, mod 100, and the install is in when `bucket < rolloutPercent` (stable per install and flag, and raising the percentage only adds installs). The sync response's `flags.version` is the sum of the flags' `version` values, so it rises with every change. The sync reads stored rules strictly (FU-056): an unknown or wrongly typed member, a bad `min_app_version`, a `rollout_percent` outside 0-100 or an empty `platforms` makes that flag OFF for everyone and increments `zaghlol.sync.flag_rules_invalid{flag}`; the admin read stays lenient so the operator can see and fix it.

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
| `POST /admin/v1/support/seat:move` | support_agent | Audited seat move past the cooldown (restarts the window), optional attach, correction move-back; live order-ID check (§5.3) |
| `POST /admin/v1/support/purchase:detach` | support_agent | Audited correction: remove an account link that support made (§5.3) |
| `POST /admin/v1/support/purchase:unfreeze` | support_lead | Audited early end of a dispute freeze by a different operator; moves nothing (§5.3, R5-5(b)) |
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
| `POST /admin/v1/support/purchase:detach` | support_agent |
| `POST /admin/v1/support/purchase:unfreeze` | support_lead |
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
- **Publish (T-125).** `POST /admin/v1/catalog/publish` is **`409 ADMIN_CONFLICT`** when no entry changed since the last publish (an identical `PUT` is not a change). Otherwise it writes the changed entries to the live tables with the next version, builds the full snapshot `{version, ops[]}` (upserts only, fixed member and row order), signs the JSON bytes with the active Sync key, stores `full.json.gz` and `full.json.sig` through the snapshot store and records `catalog_versions` (SHA-256 of the JSON, URL `<BaseUrl>/v1/catalog/{version}/full`, note), all in one transaction: a KMS or storage failure publishes nothing. Settings: `Catalog:Snapshots:Directory` (where the objects go; the CDN origin or a bucket-sync volume) and `Catalog:Snapshots:BaseUrl` (the public origin); a bucket adapter is T-140. A delta `(a, b]` lists upserts parents first (categories, merchants, aliases, keywords), then tombstones children first. `GET /v1/catalog/{version}/full` serves the stored snapshot (never a rebuild), is anonymous and cacheable for good, and may be up to 8 MiB (the 1 MiB signing buffer is raised for this endpoint only).
- **Contributions.** `:promote` takes `{merchantNorm, institutionCode, merchantId?, categoryCode?}`. With `merchantId` the string becomes an `exact` alias of that merchant; without it a new draft merchant (`canonical` = `merchantNorm`) is created. `categoryCode` defaults to the top vote. `:reject` takes `{merchantNorm, institutionCode}`. Both return `{merchantNorm, institutionCode, status, merchantId?}`. A key with no aggregate **and** a key whose aggregate is still `collecting` both give `404 NOT_FOUND`, indistinguishably: same status and body, and one query that excludes `collecting`, so there is no timing difference. `409 ADMIN_CONFLICT` is returned only for an aggregate already `promoted` or `rejected`, or for a draft conflict. **Test requirement (T-129):** a `collecting` key and an absent key return byte-identical responses on both `:promote` and `:reject`. The key moved from the path to the body because `merchantNorm` is free text.
- **Review queue privacy.** Aggregates still `collecting` (fewer than 5 distinct installs, A-48) are never returned. The API status enum is `ready_for_review | promoted | rejected`.
- **Support lookup.** `POST /admin/v1/support/entitlement:lookup` takes `{installId}` or `{email}` (exactly one) and returns `SupportEntitlement`: the status plus, per related purchase, `{purchaseId, plan, state, store, seat, accountLinked, linkedBy, lastMovedAt, nextMoveAt, pendingClaimants, buyingInstallSilent, isBuyingInstall, disputeFrozenUntil, rebindsLast30Days}`. `seat` says whether the looked-up install is the `holder`, one of the pending `claimant`s (§5.3) or `none`. `pendingClaimants` is how many unexpired claimants the purchase has (0–3), and `buyingInstallSilent` tells the agent whether the attach gate of §5.3 is open. `isBuyingInstall` says whether the looked-up install is the purchase's buying install (the runbook preference of §5.3; `null` for an e-mail lookup). `disputeFrozenUntil` is the end of the dispute freeze (D-64), or `null`. `rebindsLast30Days` (0–2) is how many same-iPhone rebinds the purchase had in the rolling 30 days (D-63). An e-mail lookup lists the account's purchases. No tokens, transaction IDs or other installs' IDs are returned. The audit row stores the install ID, or `HMAC-SHA256(K_audit, NFC(trim(lower(email))))`, plus the matched `account_id` when the lookup hits an account. It never stores the e-mail. A plain SHA-256 of an e-mail can be reversed by dictionary, so a keyed HMAC is used. `K_audit` is a dedicated KMS key, separate from the `install_hash` pepper. The audit value is pseudonymous personal data kept **exactly 1 year from creation, then deleted**, even if the account is deleted earlier (D-47, FR-BE-11, NFR-PRIV-07).

### 5.3 Support seat move, link and correction (D-52, D-54, D-56, D-57, EC-68, FR-ACCT-05, FR-BE-08/11)

`POST /admin/v1/support/seat:move` and `POST /admin/v1/support/purchase:detach`, role **`support_agent`** (phishing-resistant MFA, §3); `POST /admin/v1/support/purchase:unfreeze`, role **`support_lead`** (below). `seat:move` is the only way past the 30-day cooldown and the only way to link a purchase whose buying install is gone; `purchase:detach` only reverses a support link. **One agent may act; there is no second approver** (D-57(c)).

- **`seat:move` request:** `{purchaseId, toInstallId, reasonCode, ticketRef, ownershipCheck, attachToAccount?, correctsAuditId?}`.
  - `reasonCode` ∈ `lost_or_broken_phone | reinstall | buying_phone_gone | correction | other`. `correction` requires `correctsAuditId`, and `correctsAuditId` is allowed only with `correction`.
  - `ticketRef` is the support ticket number (`^[A-Za-z0-9_-]{1,32}$`). It is never free text, so no personal data enters the audit row.
  - `ownershipCheck` is the **store order ID** the user gives support: a Google Play order ID (`GPA.…`) or an Apple order ID from the App Store receipt.
  - The operator gets `purchaseId` from a support lookup (§5.2), and `toInstallId` from the user, who reads it from the app's help screen (the support code).
- **`purchase:detach` request:** `{purchaseId, reasonCode: "correction", ticketRef, ownershipCheck, correctsAuditId}`.
- **Ownership check, live (D-57(a)(b), FR-BE-08).** It runs first. On failure nothing changes, and the call is still audited.
  - **Google Play:** Play Developer API `orders.get` for the order ID. The order's `purchaseToken` must be this purchase's token or one in its `linkedPurchaseToken` chain, and its `state` must not be `CANCELED`, `REFUNDED` or `PENDING_REFUND`. **Fallback (R4-7, T-130):** if T-130 finds `orders.get` unavailable for the app's developer account, or not returning `purchaseToken`, the check compares the order ID with what the purchase's own token returns instead: `purchases.subscriptionsv2.get` `lineItems[].latestSuccessfulOrderId` (and the same field of each token in the `linkedPurchaseToken` chain; the deprecated `latestOrderId` is not used, R5-8) for subscriptions, and `purchases.productsv2.getproductpurchasev2`'s order ID for lifetime, together with the purchase state. That proves the same thing for the current and chained orders, though not for an older renewal order of the same subscription, so the runbook asks for the latest receipt.
  - **Apple:** App Store Server API **Look Up Order ID** (`GET /inApps/v1/lookup/{orderId}`). It must return `status = 0`, and one signed transaction, verified like any other, must carry this purchase's `originalTransactionId`.
  - A mismatch, an unknown order or a refunded order is **`422 OWNERSHIP_CHECK_FAILED`**. A store outage is `503 UPSTREAM_UNAVAILABLE`.
  - **The order ID is never stored**: not in a table, a log, a trace span, the audit row or the idempotency store (these calls aren't idempotency-keyed). The request-body logging ban already covers it; the admin DTO marks it `[Sensitive]` so the redacting logger drops it even from exceptions. `zaghlol-ops` reads it from a no-echo prompt, never from an argument, so it can't reach shell history.
- **Dispute freeze (D-64, D-65(b)).** After a successful **correction** on a purchase (a `seat:move` with `reasonCode: correction` that moved the seat, or a `purchase:detach` that detached), `purchases.dispute_frozen_until = now + 30 d`. Each later correction **restarts** it. While `now < dispute_frozen_until`:
  - every **non-correction** `seat:move` on that purchase (any move or `attachToAccount` with another `reasonCode`) is **`409 ADMIN_CONFLICT`**. The check runs before the ownership check, so no store call is made, and the refusal is audited (`outcome: "dispute_frozen"`);
  - corrections (`reasonCode: correction`, `purchase:detach`) stay allowed;
  - self-service is unchanged: restore, sign-in, verify and rebinds follow their own rules (D-65(b)).

  The support lookup shows `disputeFrozenUntil`. A dispute that needs more than a correction goes to a support lead through the ticket, who can end the freeze early with `purchase:unfreeze` (below).
- **Unfreeze (R5-5(b), adopted as the default).** `POST /admin/v1/support/purchase:unfreeze`, role **`support_lead`** (phishing-resistant MFA like `support_agent`, §3; named support leads only, reviewed quarterly). It exists for an owner who lost the phone during a freeze, who would otherwise have neither self-service (the correction restarted the window) nor support for up to 30 days, and against a wrongful correction used to freeze support for the real owner.
  - **Request:** `{purchaseId, ticketRef, ownershipCheck}`. `ticketRef` and `ownershipCheck` as for `seat:move`.
  - **Order of checks:** (1) no freeze running (`dispute_frozen_until IS NULL` or `≤ now`): nothing changes, `200` with `unfrozen: false`, audited `outcome: "noop"`, `ownership_outcome: "not_run"`; (2) **different operator:** the caller must not be the operator of the correction that started the current freeze (the newest successful correction row, `support_seat_move` with `reason_code = correction` and outcome `moved`/`moved_and_attached`, or `support_detach` with outcome `detached`, for this purchase). The same operator is **`409 ADMIN_CONFLICT`**, audited `outcome: "refused"`, `ownership_outcome: "not_run"`, with no store call; (3) the live ownership check, exactly as for `seat:move` (`422 OWNERSHIP_CHECK_FAILED`, `503 UPSTREAM_UNAVAILABLE`); (4) set `dispute_frozen_until = NULL`.
  - **Effect:** it ends the freeze and **moves nothing**: the seat, `account_id`, `next_move_at`, `recent_rebinds` and the claimants are untouched. An ordinary support move (by any `support_agent`, the lead included if they hold that role) can then follow. A later correction starts a new freeze as usual. It isn't a second approver on ordinary actions (D-57(c) unchanged).
  - **Response:** `{purchaseId, unfrozen, auditId}`.
  - **Audit and alert:** one `support_unfreeze` row per call (below), and every call raises the `support_unfreeze` alert to the support-lead group (purchase UUID only).
- **Who can receive the seat** (`toInstallId`). Any other target is `409 ADMIN_CONFLICT`. The target must be:
  1. one of the purchase's **pending claimants**: an install whose own restore, sign-in or plan-change verify for this purchase passed attestation (restore) and store verification, but was refused for the cooldown, or (plan-change verify only) kept off the seat by the account rule (R4-4), within the last 7 days. There are up to 3 (`seat_claimants`), and the agent picks one explicitly. **Runbook preference (R4-7(3)):** when several claimants could be the owner, prefer the one that is the purchase's **buying install** (`isBuyingInstall` in the lookup), the install whose HMAC the store binding names; or
  2. the **current holder**, for `attachToAccount` alone (no move), and only under the attach gate below; or
  3. for `reasonCode: correction`, the `from_install` of the `support_seat_move` audit row named by `correctsAuditId`. That row must be for the same purchase and less than 1 year old (audit retention), and the install must still exist. This is the **move back**.
- **Account rule** (D-46): for an account-linked purchase, the target must be linked to that account. Otherwise `409 ADMIN_CONFLICT`.
- **Attach gate** (`attachToAccount: true`; D-57(d), FR-ACCT-05). Allowed only when all of these hold; otherwise `409 ADMIN_CONFLICT`, and the owner links from the buying phone (D-54):
  - the purchase has no account;
  - the target is linked to an account;
  - the **buying install is gone or silent**: `purchases.install_id IS NULL`, or that install is tombstoned, or its `last_seen_at` ≤ now − 30 days.

  A support attach sets `account_id` and `account_linked_by = 'support'`. It is not a reclaim and doesn't touch `attach_reclaim_used_at`. It also sets `purchases.support_link_notice_pending = true`, so the buying install, if it reappears, is told until it acknowledges delivery (§4.2 *Support-link notice*, R4-7(2), R5-7).
- **Effect of a move** (D-56):
  - the seat moves to the target (`seat_move:support`) and the window restarts: `last_moved_at = now`, `next_move_at = ceil_hour(now + 30 d)`. A correction move does the same;
  - the target's claimant entry is removed;
  - the previous holder gets `status: moved` with **`movedBy: "support"`** at its next refresh, and the app shows that support moved Gold, with the support link and the support code (D-57(f));
  - `device_key_hash` takes the seat-key hash stored with the target's claimant entry (from its refused request), or `NULL` if it had none or for a move back. The new holder's next restore or sign-in with seat keys stores it again.
  - **`device_key_trusted` (R5-4)** is set from the **target install's** `installs.seat_key_trusted` at the time of the move, never kept from the previous holder: `false` whenever `device_key_hash` is `NULL` (no claimant key, and always on a move back), otherwise the target's current flag. So a claimant whose key a proxied sign-in registered can't inherit a trusted seat through a social-engineered support move. **Test requirement (T-184, T-186):** a support move from a holder with `device_key_trusted = true` to a claimant with an untrusted registered key leaves `device_key_trusted = false`; a move back leaves `device_key_hash = NULL` and `device_key_trusted = false`; a move to a claimant whose install key is trusted copies `true`.
- **Detach (correction, D-57(e)).** `correctsAuditId` must name a `support_seat_move` row for this purchase with `attached_account_id` equal to the purchase's current `account_id`, and `account_linked_by` must be `'support'`. A link the owner made from the buying phone can't be detached by support. Detach sets `account_id = NULL`, `account_linked_by = NULL`, `support_link_notice_pending = false` and `support_link_notice_iat = NULL`, and the seat stays where it is. Re-linking is an ordinary `seat:move` with `attachToAccount` under the attach gate.
- **Idempotent by nature:** moving to the install that already holds the seat, or detaching an unlinked purchase, changes nothing and returns the current state. It is still audited, with `outcome: "noop"`.
- **Responses:**
  - `seat:move`: `{purchaseId, moved, attached, nextMoveAt, auditId}`;
  - `purchase:detach`: `{purchaseId, detached, auditId}`;
  - `purchase:unfreeze`: `{purchaseId, unfrozen, auditId}`.

  `auditId` is the audit row's ID, which a later correction quotes.
- **Audit** (D-47 rules, FR-BE-11): every call, successful or refused, writes **exactly one** `audit_log` row naming the operator.
  - `action ∈ {support_seat_move, support_detach, support_unfreeze}`, `target` = the purchase UUID.
  - `details = {from_install, to_install, reason_code, ticket_ref, attached_account_id?, detached_account_id?, corrects_audit_id?, ownership_check: "order_id", ownership_outcome: "pass" | "fail" | "unavailable" | "not_run", outcome}`. `outcome` ∈ `moved | attached | moved_and_attached | detached | noop | refused | dispute_frozen | ownership_failed | upstream_unavailable`; a `dispute_frozen` refusal has `ownership_outcome: "not_run"`.
  - `support_unfreeze` rows: `details = {ticket_ref, freeze_audit_id, frozen_until, ownership_check: "order_id", ownership_outcome, outcome}`, where `freeze_audit_id` is the correction row that started the freeze (`null` for a `noop`), `frozen_until` the value that was cleared, and `outcome` ∈ `unfrozen | noop | refused | ownership_failed | upstream_unavailable`.
  - It never holds an e-mail, an order ID or free text.
  - Install IDs are pseudonymous personal data, so the row is kept **exactly 1 year from creation, then deleted**, like support-lookup rows.
- **Alerts and runbook actions** (`error-handling-and-observability.md` §4; T-137 runbook):
  - more than 2 support moves for one purchase in 90 days. Each one already costs the cooldown (D-56). **Action:** within 2 business days a support lead other than the acting agent reviews the tickets and audit rows. If the lead finds error or abuse, they reverse it through the correction path and record the finding on the ticket;
  - more than 20 support actions by one operator in a day. **Action:** suspend that operator's `support_agent` role pending review;
  - more than 5 `ownership_outcome: fail` rows for one operator in a day. **Action:** review for social-engineering attempts;
  - any `dispute_frozen` refusal (D-64). **Action:** the support lead takes over the ticket;
  - any `support_unfreeze` call (R5-5(b)). **Action:** a second support lead checks the ticket within 2 business days; an unfreeze followed by a move is also reviewed under the >2-moves rule;
  - **`seat_rebind`**: a purchase reached the D-63 rebind cap and had an over-cap rebind (§4.3). **Action:** check the purchase's events for a relay pattern (rebinds alternating between the same installs); if found, note it on any ticket for that purchase. No automatic action: the cap already bounds it.
- **Operators** (R3-9): `support_agent` and `support_lead` are assigned only to named staff, never to shared or service accounts, and the assignments are reviewed every quarter (T-137).
- **Helpdesk privacy (info, T-137, OQ-16):** a ticket links the support code (install ID) and the order ID to the user's contact details in the helpdesk tool. The privacy notice says so. T-137 records whether the helpdesk vendor is a PDPL processor and sets ticket retention.
- **Interim tooling** (D-37, R-21): until the admin web app ships after launch, operators use `zaghlol-ops support move --purchase <uuid> --to <installId> --reason <code> --ticket <ref> [--attach] [--corrects <auditId>]`, `zaghlol-ops support detach --purchase <uuid> --ticket <ref> --corrects <auditId>` and `zaghlol-ops support unfreeze --purchase <uuid> --ticket <ref>`. All three prompt for the order ID without echo, and both sign in with OIDC authorization code + PKCE (loopback) and FIDO2. T-136 owns operator auth, roles and the `amr` check; T-186 the three endpoints (move, detach, unfreeze), the dispute freeze and their audit rows; T-137 the CLI and the support runbook; and T-184 the seat service (support-move primitive) they call.

## 6. Error codes

Every error is `application/problem+json` with one of these `code` values. The same list is the `ProblemCode` enum in `backend/openapi/zaghlol-v1.yaml`, and a contract test fails if the two differ. Generated clients must treat an unknown code as its HTTP status class (for example, an unknown 4xx code is a client bug, and an unknown 5xx code is retried with back-off).

| HTTP | `code` | Meaning / client action |
|---|---|---|
| 400 | `VALIDATION_FAILED`, `UNKNOWN_FIELD` | Bug; log a local diag code, don't retry |
| 400 | `SEAT_KEY_MISMATCH` | iOS restore or sign-in only (§4.3 *Same-iPhone recognition*, R4-1(1)): element 0 of `seatKeys` isn't the seat key this install registered. Nothing was written. Retry once without `seatKeys` (for sign-in with a fresh ID token and nonce); the request is then an ordinary one, without a same-iPhone rebind. After a successful retry, persist "own seat key unusable" and stop sending `seatKeys` from this install (R5-6). On restore it is checked after App Attest and rolls back the counter update. Never sent for verify, which ignores a mismatching proof |
| 401 | `INSTALL_TOKEN_INVALID` | Re-register silently (new install ID); keep local data, but delete the cached entitlement and account tokens first, since their `sub` / `iid` name the old install (R5-1, §4.3 *App rules*) |
| 401 | `ACCOUNT_TOKEN_EXPIRED` | Clear the account token and show "sign in again" in Settings only |
| 401 | `UNAUTHORIZED` | Fallback for endpoints that have no specific 401 code (store notifications, operator API). Not sent to the app's install-scoped calls, which always use one of the two codes above. Don't retry; for the operator CLI, sign in again |
| 403 | `FORBIDDEN` | Not retried |
| 404 | `CATALOG_VERSION_UNKNOWN` | Request a full catalog |
| 404 | `NOT_FOUND` | The path or resource doesn't exist. A bug in the app (or an operator typo); don't retry |
| 405 | `METHOD_NOT_ALLOWED` | The HTTP method isn't supported on this path. A bug in the app; don't retry |
| 409 | `INSTALL_EXISTS`, `INSTALL_LINKED_TO_OTHER_ACCOUNT` | See §4.1 / §4.6 |
| 409 | `MOVE_COOLDOWN` | Restore only (§4.3, D-52): Gold was moved in the last 30 days, so it can't move to this phone yet. The body carries `nextMoveAt`, always a whole UTC hour. Show the date, formatted for the locale, and the support link (EC-68). Nothing that affects Gold was written (this install became a pending claimant); don't retry before `nextMoveAt`. Sign-in reports a refused move in a 200 instead (`moveRefused`, §4.6) |
| 409 | `IDEMPOTENCY_KEY_REUSED` | The same install sent the same `Idempotency-Key` for the same operation with a different body (§1). A bug in the app: generate a new key for a new request; don't retry with this one |
| 422 | `DEVICE_ATTESTATION_FAILED` | Restore only: the Play Integrity token or App Attest assertion is missing, invalid, stale, replayed or not bound to the body. iOS: if no `attestationObject` was sent, generate a new App Attest key and retry once with it; Android: retry once with a fresh token. Then stop, show the help message (EC-66) and offer sign-in (an account-linked purchase reaches the phone through sign-in without attestation, R-19). Gold is unchanged. Attestation-service outages are `503 UPSTREAM_UNAVAILABLE`, not this code |
| 409 | `ADMIN_CONFLICT` | Operator API only (§5.2, §5.3): the edit conflicts with the current draft catalog or review queue, or a support move, attach or detach isn't allowed (target not a claimant, holder or correction source; account rule; attach gate closed; detach of a link support didn't make; a non-correction action during a dispute freeze, D-64; an unfreeze by the operator of the correction that started the freeze, R5-5(b)). Reload and check. Never sent to the app |
| 422 | `OWNERSHIP_CHECK_FAILED` | Operator API only (§5.3, D-57): the store order ID didn't match this purchase live at Google or Apple, or the order is refunded or cancelled. Nothing changed; the attempt is audited. Ask the user to check the order ID. Never sent to the app |
| 413 | `PAYLOAD_TOO_LARGE` | The body is over the size limit (§1). A bug in the app; don't retry |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | The body wasn't the declared media type (`application/json`; the Apple callback takes `application/x-www-form-urlencoded`). A bug in the app; don't retry |
| 422 | `PURCHASE_TOKEN_INVALID`, `PURCHASE_NOT_OWNED`, `PURCHASE_WRONG_APP` | Show "couldn't verify purchase" + Restore; no Gold |
| 422 | `ID_TOKEN_INVALID` | Sign-in failed message |
| 429 | `RATE_LIMITED` | Respect `Retry-After` |
| 502/503 | `STORE_UNAVAILABLE`, `UPSTREAM_UNAVAILABLE` | Keep purchase pending, retry with back-off (BR-GOLD-06) |
| 500 | `INTERNAL` | Retry with back-off |

`404`, `405`, `413` and `415` with their generic codes can be returned by any endpoint, including paths that don't exist, so the OpenAPI file describes them once in the info section. It also lists `413` and `415` on every operation that takes a body.
