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

## Amendment (2026-11-05): Android restore payload and Play endpoints (FU-006)
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
- **Restore** skips the install-binding check (`obfuscatedExternalAccountId` / `appAccountToken`), because after a phone change the binding names the old install. Proof of ownership is that the device's store account could produce the token or transaction.
- Re-binding is capped at 3 moves per purchase in 30 days; past that the item is `invalid` and an alert fires.
- Per-item failures fold into an aggregate `status` (active > pending > expired > refunded > invalid), and restore has no 422.
- *Abuse limits (security review, 2026-11-05):*
  - a restore bucket of 5/hour per install;
  - a per-purchase limit of 10 attempts/day, keyed by SHA-256 of the token or `originalTransactionId`;
  - a global Play / App Store call budget with priority for verify and the ack sweeper. When the budget is short, restore gets `503` with `Retry-After`.

**Consequences.** T-130 implements the v2 calls. T-132 implements the restore rules, the rebind cap and the aggregate. T-145 sends items instead of bare tokens. Sources: Google Play Developer API reference for [`purchases.productsv2.getproductpurchasev2`](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2) and the [one-time product lifecycle guide](https://developer.android.com/google/play/billing/lifecycle/one-time), checked 2026-11-05.
