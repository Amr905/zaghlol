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
