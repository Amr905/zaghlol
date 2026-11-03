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
| Idempotency | `Idempotency-Key: <ULID>` on `POST /v1/purchases/verify`, `/v1/installs`, `/v1/accounts/signin`. Replays within 24 h return the stored result. |
| Response signing | Security-relevant responses carry `Zaghlol-Signature: kid=<kid>; alg=ES256; sig=<base64url>`, an ECDSA P-256 signature over the **exact response body bytes** after decompression. The app verifies it against embedded public keys (ADR-012/013) and drops unsigned or invalid bodies. |
| Time | `serverTime` (RFC 3339 UTC) in every response body. The app stores it to drive the 24 h throttle (EC-43). |
| Errors | RFC 9457 `application/problem+json`: `{type, title, status, code, detail?, retryAfterSeconds?}`. `code` is a stable `UPPER_SNAKE` string (§6). Error bodies never echo request data. |
| Rate limits | Per install token and per /24 IP (token bucket). `429` with `Retry-After`. |
| Request size | ≤ 64 KB, except `/v1/notifications/*` (≤ 256 KB). |
| Unknown fields in requests | **Rejected** (`400 UNKNOWN_FIELD`), so the app can't accidentally send more than BR-SYNC-03 allows. |

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
| `GET /v1/apple/android-callback` | none | Sign in with Apple web-flow callback for Android (CR-05) | FR-ACCT-01 |
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
| **Operator** | OIDC (Google Workspace or Entra ID) with enforced MFA; short-lived access token (≤ 1 h) via device-code flow in `zaghlol-ops` | Company IdP | 1 h | Role-based: `catalog_editor`, `flags_admin`, `support_viewer`, `prices_admin`; every write audited |

Authorization rules:
- A call may only read or write rows of its own `installId`, plus rows of `accountId` when the account token matches **and** the install is linked to that account.
- `/v1/notifications/*` never accept bearer tokens.
- Operators have no endpoint that returns installs in bulk.
- Support lookup takes an exact install ID or account e-mail and returns entitlement status only.

## 4. Contracts

### 4.1 `POST /v1/installs`
```json
// request
{ "installId": "0193f2c4-…-uuid", "platform": "android", "appVersion": "1.0.0", "osMajor": 15 }
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
1. `purchases.subscriptionsv2.get`, or `purchases.products.get` for lifetime.
2. Require `subscriptionState = ACTIVE | IN_GRACE_PERIOD`, or a product `purchaseState = PURCHASED`. Pending gives `pending`, and nothing is granted (BR-GOLD-05).
3. Check `obfuscatedExternalAccountId == HMAC(installId)`, set by the app at purchase.
4. Upsert `purchases`, keyed by the purchase token.
5. `acknowledge` if not yet acknowledged; on failure, retry from the `ix_purchases_unacked` sweeper every 15 min.
6. Sign and return the entitlement.

**Server procedure (iOS):**
1. Verify the JWS x5c chain against Apple Root CA G3.
2. Check `bundleId`, `environment` and `appAccountToken == HMAC(installId)`.
3. Call App Store Server API `Get Transaction Info` and `Get All Subscription Statuses` for the authoritative state.
4. Upsert by `originalTransactionId`.

**Restore** (`POST /v1/purchases/restore`) takes `{platform, purchaseTokens[] | signedTransactions[]}` and runs the same procedure for each. For tokens bound to another install, if the store says they're valid for the same store account, the purchase is **re-bound** to the calling install (FR-GOLD-03), and `purchase_events` records the move.

**Entitlement token** (JWS compact, ES256, `kid` header):
```json
{ "iss": "zaghlol", "sub": "<installId>", "acct": "<accountId|null>", "plan": "yearly",
  "status": "active", "exp": 1798790400, "graceUntil": 1799395200, "iat": 1793570520,
  "src": [ { "store": "google_play", "product": "zaghlol_gold_yearly" } ], "v": 1 }
```
The app grants Gold while `now < graceUntil`, where graceUntil = `exp` + 7 days (BR-GOLD-03, A-38). For lifetime, `exp` = `iat` + 30 days, rolling, so a revoked lifetime purchase still loses Gold.

### 4.4 `GET /v1/entitlement`
Returns `{entitlement: {token}, serverTime}`, merging install and account purchases. It is called after a purchase restore, after sign-in, and when the cached token is within 3 days of `exp`.

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

### 4.6 Accounts
```json
// POST /v1/accounts/signin
{ "provider": "apple", "idToken": "eyJ…", "nonce": "sha256-of-client-nonce", "authorizationCode": "c1a…" }
// 200 (signed)
{ "accountId": "uuid", "accountToken": "eyJ…", "entitlement": { "token": "eyJ…" }, "linkedInstalls": 2, "serverTime": "…" }
```

**Verification:**
- **Google:** `aud` must be one of our OAuth client IDs; check `iss` and `exp`; JWKS from Google.
- **Apple:** `aud` must be our Services ID or bundle ID; `iss = https://appleid.apple.com`; the nonce must match. The `authorizationCode` is exchanged for a refresh token, stored encrypted and used **only** to revoke on deletion.

**After verification:**
1. Upsert the account.
2. Link the install.
3. Attach the install's purchases to the account.

If the install was linked to a different account, the response is **409 `INSTALL_LINKED_TO_OTHER_ACCOUNT`** and the app asks the user (EC-46). Re-sending with `"replaceLink": true` confirms.

`DELETE /v1/accounts/me` removes the account and its links. Purchases stay bound to their installs.

### 4.7 Delete install (FR-ONB-08)
`DELETE /v1/installs/me` returns 202 and tombstones the install; its tokens stop working at once. The app wipes local data **before** calling this endpoint and does not depend on it succeeding. A failure is retried once, then given up, because the install expires after 12 months of no syncs anyway.

### 4.8 Shapes fixed by the OpenAPI file (T-006)
These details were not spelled out above. `backend/openapi/zaghlol-v1.yaml` is authoritative for field names, limits and patterns.
- **Success statuses without a body:** `DELETE /v1/installs/me` returns 202; `POST /v1/accounts/signout` and `DELETE /v1/accounts/me` return 204; `POST /v1/notifications/google` returns 204; `POST /v1/notifications/apple` returns 200.
- **Restore response:** `{status, restoredCount, entitlement, serverTime}`. `status` is the aggregate over all submitted purchases, with the same values as verify.
- **Full catalog snapshot** (`GET /v1/catalog/{version}/full`): `{version, ops[]}` where `ops` are upserts of the same shape as in `/v1/sync`. The signature is the `Zaghlol-Signature` header and the `.sig` file next to the snapshot.
- **`rotateInstallToken`:** an optional string in the sync, verify, restore and entitlement response bodies. Absent or `null` means keep the current token.
- **Apple Android callback** (`GET /v1/apple/android-callback`): query `state` (required), `code`, `id_token`, `error`. It answers 302 to an app link. Apple's `user` parameter (name, e-mail) is ignored and never stored.
- **Pub/Sub push body:** `{message: {data, messageId, publishTime, attributes?, orderingKey?}, subscription, deliveryAttempt?}`. The envelope is closed to the fields Pub/Sub documents.
- **Money and prices** are decimal strings (for example `"4820.00"`) with a separate ISO 4217 `currency`. They are never JSON numbers.
- **Timestamps** are RFC 3339 UTC and always end in `Z`.
- **`osMajor`** in `POST /v1/installs` is optional and is the only field beyond the BR-SYNC-03 wording (the OS major version, a diagnostic). Confirm it against BR-SYNC-03 or drop it.

## 5. Admin API (operators, v1 used by `zaghlol-ops`; web admin later per D-37)

| Method & path | Role | Purpose |
|---|---|---|
| `GET/PUT /admin/v1/catalog/draft/...` | catalog_editor | Edit draft categories/merchants/aliases/keywords |
| `POST /admin/v1/catalog/publish` | catalog_editor | Publish draft → new immutable version, build + sign full snapshot, upload to CDN |
| `GET /admin/v1/contributions?status=ready_for_review` | catalog_editor | Review queue (aggregates only) |
| `POST /admin/v1/contributions/{merchantNorm}/{inst}:promote \| :reject` | catalog_editor | Promote into the draft |
| `GET/PUT /admin/v1/flags/{key}` | flags_admin | View / change a flag (audited, takes effect on next sync) |
| `PUT /admin/v1/prices/override` | prices_admin | Override a price when the feed is wrong |
| `GET /admin/v1/support/entitlement?installId=… \| email=…` | support_viewer | Entitlement status only |
| `GET /admin/v1/bank-requests` | catalog_editor | Ranked list |
| `GET /admin/v1/metrics/daily-active` | any | Aggregate counters |

Concrete paths (OpenAPI): `GET /admin/v1/catalog/draft/{entity}` (list) and `PUT /admin/v1/catalog/draft/{entity}/{id}` (upsert), where `entity` is `categories`, `merchants`, `aliases` or `keywords`. The promote and reject actions are `POST /admin/v1/contributions/{merchantNorm}/{institutionCode}:promote` and `...:reject`. All admin calls use an operator bearer token (`operatorOidc`); every operation declares its role in `x-required-roles`.

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
| 413 | `PAYLOAD_TOO_LARGE` | The body is over the size limit (§1). A bug in the app; don't retry |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | The request wasn't `application/json`. A bug in the app; don't retry |
| 422 | `PURCHASE_TOKEN_INVALID`, `PURCHASE_NOT_OWNED`, `PURCHASE_WRONG_APP` | Show "couldn't verify purchase" + Restore; no Gold |
| 422 | `ID_TOKEN_INVALID` | Sign-in failed message |
| 429 | `RATE_LIMITED` | Respect `Retry-After` |
| 502/503 | `STORE_UNAVAILABLE`, `UPSTREAM_UNAVAILABLE` | Keep purchase pending, retry with back-off (BR-GOLD-06) |
| 500 | `INTERNAL` | Retry with back-off |

`404`, `405`, `413` and `415` with their generic codes can be returned by any endpoint, including paths that don't exist, so the OpenAPI file describes them once in the info section. It also lists `413` and `415` on every operation that takes a body.
