# Security & Privacy Model

Covers authentication and authorization (§4), key management (§3), backup crypto (§5), the backend data boundary (§2, §6) and the threat model (§1). Baselines:
- **Mobile:** OWASP MASVS L2 + R (resilience, light).
- **Backend:** OWASP ASVS L2 (A-51).
- **Law:** Egypt PDPL 151/2020 and its Executive Regulations (Decision 816/2025).

## 1. Assets & threat model (STRIDE summary)

| Asset | Where | Threats | Controls |
|---|---|---|---|
| Financial data (messages, transactions, balances, assets, rules) | Phone DB, spool, backups | Device theft or forensic copy; malware with root; OS cloud backup leakage; lost backup file; developer logging | SQLite3MultipleCiphers AES-256 with a device-bound key (§3). Spool AES-GCM. OS backups excluded. Backup AES-256-GCM under a passphrase-wrapped key (§5). Redacting logger (§7). No telemetry SDKs. |
| DB / spool / backup keys | Keystore / Keychain | Extraction from secure storage; key copied into backups | Non-exportable Keystore key; Keychain `ThisDeviceOnly`; keys never written to the DB, files, logs or backups (FR-SEC-04) |
| Gold entitlement | Phone cache, backend | Local tampering to unlock Gold; replayed or forged purchase tokens | ES256-signed token verified on device (NFR-SEC-05); server-side store verification; token = unique key; `obfuscatedAccountId`/`appAccountToken` binding |
| Catalog & flags | Phone, backend, network | MITM injecting categories or enabling a flag | TLS + ES256 response signatures; atomic apply after verification (FR-SYNC-04) |
| Backend personal data (install ID, account e-mail, purchase IDs) | PostgreSQL | Breach; over-collection; insider access | Minimal schema; KMS encryption; RBAC + MFA; audit log; retention; no bulk export endpoints |
| Store credentials & signing keys | Backend | Leak gives forged entitlements or Play API abuse | KMS/HSM-held signing keys (sign API only); secrets manager; workload identity; rotation (§8) |
| Operator access | Admin API | Phished operator | IdP-enforced MFA (phishing-resistant FIDO2 preferred), 1 h tokens, least-privilege roles, audit |
| Users' privacy vs Play policy | Android SMS | Reading personal SMS (spyware policy) | Native Guard reads only allowlisted financial senders; inbox query filtered in SQL by sender; non-financial messages never leave memory (FR-ING-A-02) |

Out of scope: protecting a fully compromised, unlocked device in an attacker's hands. App lock reduces casual access; the root/jailbreak warning covers FR-SEC-07.

## 2. Data boundary enforcement (BR-SYNC-03)

1. **One client:** `BackendClient` is the only HTTP client in the app. Its request DTOs are generated from the OpenAPI spec and are the only types it can serialize. There is no "send map" API.
2. **Server rejects extras:** the server rejects unknown fields in every app and operator request (`backend-api.md` §1), so any accidental extra field fails loudly in testing. The only open bodies are the three that Google and Apple define (Pub/Sub, ASSN V2, the Apple `form_post`). They never come from the app, and the server ignores their unlisted fields and never stores them (ADR-022 amendment).
3. **Contributions are filtered twice** (BR-SYNC-04), on device before queuing and on the server again. A contribution is dropped if it:
   - has a person-to-person counterparty;
   - contains a digit run of 5 or more, `@`, `+20` or a phone pattern;
   - matches a person-name pattern (first-name dictionary + "two capitalized tokens without merchant keywords" heuristic);
   - comes from a custom category, or is longer than 64 characters.
4. **Privacy contract test:** an integration test runs a full session through a recording proxy and asserts that every outgoing body matches the BR-SYNC-03 allow-list. Contribution payloads must contain no amount, date, card digits, IPA or phone (FR-CAT-09 acceptance).
5. **"What Zaghlol's server knows about you"** screen (FR-ONB-07): it lists exactly those fields, and its copy is generated from the same allow-list.

## 3. On-device key management

| Key | Size / alg | Generated | Stored | Used for | Lifecycle |
|---|---|---|---|---|---|
| `K_db` | 256-bit random | First launch | `flutter_secure_storage`. Android: AES key wrapped by a Keystore key. iOS: Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable. | SQLite3MultipleCiphers `PRAGMA key` | Never leaves the device; not in backups (FR-BAK-07). If lost (Keystore invalidated) the DB is unreadable, and the app offers restore from backup. Rekey supported (`PRAGMA rekey`) for future rotation. |
| `K_spool` | AES-256-GCM | First launch | Android Keystore (non-exportable, StrongBox if present); iOS Keychain (shared access group with the Share Extension) | Spool entries, Guard config, encrypted temp files (images, PDFs, export staging) | Rotated if invalidated; pending spool is lost (rare, logged) |
| `K_bk` (backup data key) | 256-bit random | First backup setup | Secure storage (for automatic backups) **and** wrapped inside each backup file header | AES-256-GCM chunks of the backup | Re-wrapped when the passphrase changes. A new `K_bk` only if the user resets backup (old backups then need the old passphrase). |
| `KEK_pass` | Argon2id(passphrase, salt 16 B, m = 64 MiB, t = 3, p = 1) → 256-bit | At passphrase set / restore | Never stored | Wraps `K_bk` (AES-256-GCM key wrap) | Parameters stored in the header for future upgrades |
| Install token, account token, entitlement token | — | Backend | `secure_state` table in the encrypted DB | API auth / Gold | Cleared on Delete everything / sign-out |

**Background access:** iOS Keychain items use the *AfterFirstUnlock* class so Shortcuts and BG tasks can open the DB while the phone is locked after first unlock. Android Keystore keys don't require user authentication, for the same reason. The app lock is a UI gate (§4.3), not a crypto gate, because capture must keep working while the app is locked.

## 4. Authentication & authorization

### 4.1 App ↔ backend
- **Default anonymous.** An install token (opaque bearer) is scoped to its own install. There are no user passwords anywhere (FR-ONB-02).
- **Optional account** (FR-ACCT, ADR-016):
  - Google or Apple ID tokens are verified server-side with JWKS, audience, issuer and expiry checks. They also need: `iat` no more than 10 minutes old; a nonce pre-image check, where the app sends the raw nonce and the server compares `hex(SHA-256(raw))` with the claim in constant time; and single use (`replay_guard`) (ADR-016 amendment 2).
  - The server issues its own ES256 account JWT (30 d).
  - An account only *links* entitlements, and grants no access to any data other than entitlement status.
- **Purchase authorization:**
  - **Verify:** a purchase is honoured only if store verification succeeds **and** the store-side binding (`obfuscatedExternalAccountId` / `appAccountToken`) equals HMAC(installId). Verify needs no device attestation, because the binding is the proof (ADR-012 Amendment (2026-11-05) Part B).
  - **Restore** (D-45/D-46, FR-GOLD-08/09): possession of a genuine token is **not** proof of ownership. A restore is honoured only when all of these hold:
    - a valid device attestation (Play Integrity standard request / App Attest assertion) is bound to the request body;
    - store verification succeeds;
    - for an account-linked purchase, the caller is signed in to that account;
    - the purchase gets one of at most **3 seats**. A 4th install reclaims a dormant seat or evicts the least recently active one.

    Moved-away installs stop receiving Gold at their next refresh, and offline they lose it within 37 days (`exp` ≤ `iat` + 30 d, plus 7 d grace).
  - **Sign-in** gives an install a seat in its account's purchases with the verified ID token as the proof (FR-GOLD-07). A purchase is attached to an account only from its purchasing install (`backend-api.md` §4.6), never from a restore-acquired seat.
  - Seat changes are audited in `purchase_events`. Alerts carry only the purchase UUID.
- **Server-to-server:**
  - Pub/Sub push carries Google-signed OIDC (audience + service-account e-mail pinned).
  - Apple notifications are JWS-verified to Apple Root CA G3 with bundle and environment checks.
  - Outbound calls use workload identity / service-account keys from the secrets manager.
- **Operators:** OIDC with enforced MFA; RBAC roles (`backend-api.md` §3); every write goes to `audit_log`.

### 4.2 Authorization matrix (backend)

| Resource | Install | Account (linked) | Operator role | Notes |
|---|---|---|---|---|
| Own install record (delete) | ✔ | — | support_viewer (read) | — |
| Sync payload | ✔ | ✔ (adds account entitlement) | — | Same for everyone |
| Purchases verify/restore | ✔ own (restore: attestation + seat rules) | ✔ (account-linked purchases move only between the account's installs) | — | Store is source of truth for state; seats and attestation decide which installs get Gold |
| Entitlement read | ✔ own | ✔ | support_viewer | Status only |
| Account delete | — | ✔ own | — | Revokes the Apple token |
| Catalog draft/publish | — | — | catalog_editor | Publish needs a second operator's approval in the web admin later; v1 CLI logs the operator |
| Flags | — | — | flags_admin | — |
| Prices override | — | — | prices_admin | — |

### 4.3 App lock (FR-SEC-02, FR-ONB-04, A-08, A-10)
- **Unlock:** `local_auth` with biometrics, falling back to the device passcode. No custom PIN.
- **When it locks:** on cold start and after 60 s in background (configurable).
- **While locked:** a blank lock screen sits over the router. On Android, `FLAG_SECURE` + `setRecentsScreenshotEnabled(false)` hide the app-switcher snapshot; on iOS, a privacy overlay is drawn on `sceneWillResignActive`.
- **Notifications:** amounts are hidden on the lock screen when the user chooses (FR-NTF-03). This is the default when app lock is on.

## 5. Backup cryptography (ADR-011, FR-BAK-*)

```
file  = header ‖ chunk_1 ‖ … ‖ chunk_n
header (CBOR, authenticated as AAD of every chunk):
  magic "ZGLB", format 1, appVersion, schemaVersion, createdAt, platform, contents manifest digest,
  kdf {alg: argon2id, salt, m, t, p}, wrapped_bk = AES-256-GCM(KEK_pass, K_bk) with nonce,
  chunkSize 1 MiB
chunk_i = nonce_i(12: 8-byte random prefix ‖ 4-byte counter i) ‖ AES-256-GCM(K_bk, plaintext_i, AAD = header ‖ i ‖ isLast) ‖ tag
plaintext = tar-like stream: db.snapshot, settings.json, manifest.json
  db.snapshot = online copy via the SQLite backup API into a temp DB keyed with K_snap = HKDF(K_bk, "db-snapshot"),
                so the DB pages are never written unencrypted, even in temp storage
```
- **Integrity:** truncation, reordering or swapping chunks fails authentication, thanks to the counter and `isLast` in the AAD.
- **Passphrase:** a wrong one fails at the key unwrap, giving the clear error «الباسورد ده مش بيفتح النسخة دي».
- **Strength:** minimum 8 characters, strength-meter guidance. The user is warned that it can't be recovered (EC-27).
- **Contents:** everything in FR-BAK-06, nothing in FR-BAK-07.
- **Storage:** Drive `appDataFolder` (D-11) or iCloud ubiquity container. Free = 1 slot, overwritten (FR-BAK-08). Gold keeps the last 5 (A-25).
- **Restore:** verify the header → unwrap → stream-decrypt to a temp encrypted DB → open it with `K_snap` → copy (SQLite backup API) into a new DB under this device's fresh `K_db` → swap atomically.

## 6. Backend security controls

| Area | Control |
|---|---|
| Transport | TLS 1.2+ only (1.3 preferred), HSTS, modern ciphers; managed certificates |
| Pinning (OQ-15) | **No TLS certificate pinning** (ADR-018). Integrity of security-relevant data comes from ES256 response signatures with keys embedded in the app, which survive certificate rotation. |
| Input validation | FluentValidation on every DTO; unknown fields rejected (except the three third-party bodies, which ignore them); size limits; regex timeouts; no personal data or credentials in query strings, and query strings never logged |
| Rate limiting & abuse | Token bucket per install and per /24; registration limited per IP; WAF managed rules |
| Secrets | Cloud secrets manager; no secrets in config files or images; CI uses OIDC federation (no long-lived keys) |
| Signing keys | ES256 keys in KMS/HSM (`sign` permission for the API identity only). Each `kid` has a 12-month active life. The app embeds current + next public keys, and rotation ships in an app release before activation. |
| Data at rest | Managed PostgreSQL encryption; Apple refresh tokens additionally envelope-encrypted with KMS |
| DB access | Separate least-privilege roles; no public IP (private networking); operator access only through the admin API |
| Dependencies | Dependabot/Renovate; `dotnet list package --vulnerable` and SCA in CI; container image scanning; SBOM per release |
| Logging privacy | IP truncation at ingestion; no request bodies logged; install IDs hashed in logs |
| PDPL | DPO appointed; PDPC licence (and cross-border permit if hosted abroad, CR-03); records of processing; breach notification to the PDPC within 72 h and users within 3 days of that (the Executive Regulations rule) |

## 7. Mobile hardening checklist (MASVS mapping)

- **Storage:** no plaintext financial data outside the encrypted DB. A `tools/privacy_scan` integration test greps the app sandbox after a scripted session for amounts, card digits, sample merchant names and message fragments (FR-SEC-03 acceptance).
- **Logging:**
  - `debugPrint` is stripped in release builds.
  - The local diagnostic log stores **codes + non-sensitive fields only**, through a typed `DiagEvent` API with an allow-listed field set.
  - Exceptions in parsing paths wrap the original exception without its message text.
- **No OS backups** (FR-SEC-05; T-165 design note):
  - Android: `allowBackup=false`, `fullBackupContent` and `dataExtractionRules` exclude every domain for both `cloud-backup` and `device-transfer` (on API 31+, `allowBackup=false` alone does not stop D2D), and `hasFragileUserData=false`.
  - iOS: `isExcludedFromBackup` is set natively in `AppDelegate` before the engine starts, on the `Library/Application Support`, `Documents`, `Caches` and `tmp` roots and on the App Group `spool/`, `Library/Application Support` and `Caches` directories. No app data goes in `UserDefaults`.
  - Secure storage is `ThisDeviceOnly`.
  - **Orphaned data:** a DB without its key (an OEM transfer or a leaked restore) is deleted at startup, and the app starts in first-launch state offering restore. It is never partially opened.
- **IPC:**
  - The share intent and extension accept only declared MIME types.
  - Exported Android components are limited to the SMS receiver (permission-protected `BROADCAST_SMS`), the notification listener (`BIND_NOTIFICATION_LISTENER_SERVICE`) and the share activity.
  - Deep links can't trigger destructive actions.
- **Exports/share cards** (FR-SEC-06): written only to a user-chosen location after an unencrypted-file warning. Staging files are encrypted with `K_spool` and deleted after sharing.
- **Clipboard:** paste is user-initiated only; the app never reads the clipboard silently.
- **Root/jailbreak:** warn once (FR-SEC-07); never block.
- **Delete everything** (FR-ONB-08, EC-29):
  1. Cancel jobs (backup, WorkManager).
  2. Close the DB.
  3. Delete the DB, spool, temp files and widget snapshot.
  4. Delete the Keystore/Keychain items.
  5. Call `DELETE /v1/installs/me` (best effort).
  6. Restart in first-launch state.
