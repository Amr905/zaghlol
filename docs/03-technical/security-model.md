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
| Gold entitlement | Phone cache, backend | Local tampering to unlock Gold; replayed or forged purchase tokens; a proxy (stock iOS, user CA) relaying one holder's signed entitlement to other phones | ES256-signed token verified on device (NFR-SEC-05) and honoured only when its `sub` is this install's ID (account token: `iid`), so a proxied copy of another install's token grants nothing (R5-1); server-side store verification; token = unique key; `obfuscatedAccountId`/`appAccountToken` binding |
| Gold offline bound (D-52(d), D-60) | Phone clock, `secure_state` | **Clock rollback** on a phone Gold moved away from, kept offline so `now < graceUntil` stays true (R3-1); replaying an old signed response, another install's signed response or a response a proxy withheld, to pull trusted time back (R4-2); reboots to reset the monotonic clock | Expiry evaluated against the trusted-time high-water mark `hw` in the encrypted `secure_state`: advanced by the sleep-inclusive monotonic clock, never lowered by the wall clock. Only the signed echo of the app's own single outstanding **time nonce**, within 60 s, may lower it or clear the tamper flag; every other signed time only raises it (R4-2). A wall clock > 10 min below the uncharged lower bound `lb` withholds Gold until reconnect (R4-3). A reboot charges at least 6 h to `hw`. Tokens live 3 d + 4 d grace (basic 2 d + 4 d). Residual: an undetectable iOS reboot gains only time the app didn't run, so use after a move stays ≤ 7 days of app-running time (ADR-012 Part B (h)); a rooted device editing `secure_state` is out of scope (`backend-api.md` §4.3 *Trusted time*) |
| Gold seat (D-52, D-55, D-62, D-63) | Backend, iOS Keychain | Sharing one purchase across phones; cloning the iOS same-phone proof to another phone; **relaying** it from a jailbroken iPhone that signs on request (R4-1), or rewriting sign-in proofs through a user-CA proxy on a stock iPhone (R5-2) | One seat per purchase, move once per 30 days (rounded `next_move_at`), install-bound attestation. The same-iPhone proof is a Secure Enclave key, signed over a single-use, install-bound challenge. The key **can't be extracted**, but on a jailbroken iPhone a hooked app can still **use it as a signing oracle**, so: each install registers one key (element 0, `SEAT_KEY_MISMATCH` otherwise); only a key at position ≥ 1 can rebind, after which the seat follows the new install's own key; on restore App Attest covers the public keys, so a proxy can't insert one; rebinds are capped at 2 per purchase per 30 days (D-63). Residual (ADR-012 (g)): two jailbroken iPhones can swap by restore past the cap, one holder at a time, each over-cap swap restarting the window and alerting (D-65(a)); the jailbreak / Secure Enclave oracle precondition applies to restore only. **On stock iOS a user-CA proxy can drive the sign-in rebinds** (no attestation, software keys accepted): bounded by the account rule, the D-63 cap (2 cooldown-free rebinds per purchase per 30 days) and the trusted-key rule for over-cap sign-ins, where a key is trusted only after an App Attest-covered request (R5-2). Owner residual (accepted by the PO, D-66; no App Attest on sign-in): a Play-bought or other-Apple-ID owner can be refused on the holding iPhone for ≤ 30 days after a 3rd reinstall in 30 days; the app shows the support path. At rest only keyed hashes (per install, per seat); raw keys visible in transit (D-62, accepted) |
| Support move and link (D-57) | Admin API, helpdesk | Social engineering of support by a family member, ex-partner or second-hand buyer with store-account access; insider misuse; lock-out by a fraudulent link | Live order-ID check with Google/Apple (`422 OWNERSHIP_CHECK_FAILED`; order ID never stored); target limited to proven claimants, the holder (attach only) or a correction source; attach only when the buying install is gone or silent ≥ 30 days; every move restarts the cooldown (D-56); audited correction (move back, detach); the losing phone is told (`movedBy: support`); alerts with runbook actions; FIDO2 for `support_agent`; a 30-day **dispute freeze** on non-correction support actions after any correction (D-64), which only a `support_lead` other than the correcting agent can end early, audited and alerted, moving nothing (R5-5(b)); a one-time notice to the buying phone after a support link (R4-7(2)) |
| Catalog & flags | Phone, backend, network | MITM injecting categories or enabling a flag | TLS + ES256 response signatures; atomic apply after verification (FR-SYNC-04) |
| Backend personal data (install ID, account e-mail, purchase IDs) | PostgreSQL | Breach; over-collection; insider access | Minimal schema; KMS encryption; RBAC + MFA; audit log; retention; no bulk export endpoints |
| Store credentials & signing keys | Backend | Leak gives forged entitlements or Play API abuse | KMS/HSM-held signing keys (sign API only); secrets manager; workload identity; rotation (§8) |
| Operator access | Admin API | Phished operator; a phished OAuth device code | IdP-enforced MFA; **FIDO2 / passkey required for `support_agent` and `support_lead`**, enforced by IdP conditional access scoped to the CLI and admin clients; the API checks a proving claim (Entra `acrs`) only where the IdP emits one, otherwise its check is advisory (R3-9, R4-6); CLI sign-in by authorization code + PKCE with a loopback redirect, device-code grant disabled; 1 h tokens; least-privilege roles; `support_agent` and `support_lead` for named staff only, reviewed quarterly; audit |
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

   **Server side (T-128, `POST /v1/sync`).** The server normalizes `merchantNorm` and `institutionName` (control and format characters and combining marks `Mn`/`Me` removed; fullwidth forms, the ideographic space and the small commercial at `﹫` folded; digits folded to ASCII; whitespace collapsed; Latin lower-cased) and runs `ContributionPrivacy.IsAcceptable` on the normalized text, which is what is stored, **before any insert**: it drops text over 64 characters, any commercial at (`@`, `＠`, `﹫`: e-mail, InstaPay address) and any run of 6 digits (phone, card, account number). A digit is any Unicode decimal digit (`Nd`, every script: ASCII, Arabic-Indic, Extended Arabic-Indic, Devanagari, fullwidth, mathematical and so on) or another number character whose value is a single digit 0-9 (superscript, subscript, circled); up to 3 non-letter characters in a row may separate two digits of a run (whitespace, any dash or minus, tatweel `ـ`, brackets, punctuation such as `• · : |`, symbols), and combining marks and format characters between digits are ignored. Only letters (`Lu Ll Lt Lo`) break a run. Two residuals are documented and accepted (FU-061): digits written as letters (spelled-out words, CJK numerals) are letters and are not detected, the same class as person names; and a number split by more than 3 separators in a row between groups of fewer than 6 digits (`010 ---- 1234 ---- 5678`) is not a run by this rule. Both are covered by the app's own filter, the A-48 threshold and operator review. It also drops a contribution whose category is not a live system category (custom categories) and an institution code outside the `InstitutionCode` pattern. The database CHECK is only a backstop. **The server does not claim to detect person names**: a name can't be told from a merchant reliably without the transaction context, which never leaves the phone. The residual risk is covered by the app's own filter (above), the A-48 threshold (at least 5 distinct installs before a merchant is even shown for review) and mandatory operator review before promotion (T-129). Dropped items are counted by reason (`zaghlol.sync.intake`), never echoed and never logged.
4. **Privacy contract test:** an integration test runs a full session through a recording proxy and asserts that every outgoing body matches the BR-SYNC-03 allow-list. Contribution payloads must contain no amount, date, card digits, IPA or phone (FR-CAT-09 acceptance).
5. **"What Zaghlol's server knows about you"** screen (FR-ONB-07): it lists exactly those fields, and its copy is generated from the same allow-list.

## 2a. Privacy-notice and store-disclosure requirements (T-137, D-62, R4-8)

The privacy notice ("What Zaghlol's server knows about you", FR-ONB-07) and the App Store privacy details / Play data-safety form must state, in plain words:
1. **Same-iPhone seat keys (D-62):** on iPhone, restore and sign-in send a key proof from this install and from up to 4 earlier Zaghlol installs on the same iPhone, so Zaghlol's server can tell that those installs were on the same iPhone. The server keeps only a scrambled (keyed-hash) form, per purchase and per install, and never logs the keys.
2. **"Delete everything" on iPhone (R4-8):** it keeps the seat keys on the phone (so Gold can come back to this iPhone without using the monthly move) and the server keeps a keyed hash of the key with the purchase until the purchase is deleted. Erasing the iPhone removes the keys.
3. **Time nonce (R4-2):** some requests carry a random one-time number used to check the time; it contains nothing about the phone or the user and isn't stored.
4. **Support links (R4-7(2)):** if support links Gold to an account, the phone that bought it is told when it next connects; the server keeps repeating the notice until that phone's next sync proves it stored it (R5-7), so a lost response doesn't lose it.

The copy is UX-owned (Egyptian colloquial with standard Arabic for the legal text, `06-voice-and-tone.md`) and generated from the same allow-list as the screen (§2 item 5).

## 3. On-device key management

| Key | Size / alg | Generated | Stored | Used for | Lifecycle |
|---|---|---|---|---|---|
| `K_db` | 256-bit random | First launch | `flutter_secure_storage`. Android: AES key wrapped by a Keystore key. iOS: Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable. | SQLite3MultipleCiphers `PRAGMA key` | Never leaves the device; not in backups (FR-BAK-07). If lost (Keystore invalidated) the DB is unreadable, and the app offers restore from backup. Rekey supported (`PRAGMA rekey`) for future rotation. |
| `K_spool` | AES-256-GCM | First launch | Android Keystore (non-exportable, StrongBox if present); iOS Keychain (shared access group with the Share Extension) | Spool entries, Guard config, encrypted temp files (images, PDFs, export staging) | Rotated if invalidated; pending spool is lost (rare, logged) |
| `K_bk` (backup data key) | 256-bit random | First backup setup | Secure storage (for automatic backups) **and** wrapped inside each backup file header | AES-256-GCM chunks of the backup | Re-wrapped when the passphrase changes. A new `K_bk` only if the user resets backup (old backups then need the old passphrase). |
| `KEK_pass` | Argon2id(passphrase, salt 16 B, m = 64 MiB, t = 3, p = 1) → 256-bit | At passphrase set / restore | Never stored | Wraps `K_bk` (AES-256-GCM key wrap) | Parameters stored in the header for future upgrades |
| Install token, account token, entitlement token | — | Backend | `secure_state` table in the encrypted DB | API auth / Gold | Cleared on Delete everything; the account token and the cached entitlement are dropped at sign-out (D-61(c)) |
| Trusted-time state (`hw`, `lb`, monotonic and boot reference, `lastServerTime`, `tampered`; the outstanding time nonce in memory only) | — | App | `secure_state` in the encrypted DB | Gold expiry against trusted time (NFR-SEC-08) | Re-anchored only by the echo of the outstanding time nonce (R4-2); cleared on Delete everything |
| Seat keys (iOS, D-55) | P-256, Secure Enclave | Per install, at first need | Keychain generic-password item holding the SE-wrapped key, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable; up to 5 (this install + 4 earlier) | Same-iPhone recognition proofs (`seatKeys`); the own key is registered to the install by the server (keyed hash) | Never leave the Secure Enclave, but usable as a signing oracle on a jailbroken phone (bounded server-side, §1). **Kept by "Delete everything"** (D-55: same-iPhone Delete everything is not a move) and by app deletion; lost on device erase. Hold no financial or account data |

**Background access:** iOS Keychain items use the *AfterFirstUnlock* class so Shortcuts and BG tasks can open the DB while the phone is locked after first unlock. Android Keystore keys don't require user authentication, for the same reason. The app lock is a UI gate (§4.3), not a crypto gate, because capture must keep working while the app is locked.

## 4. Authentication & authorization

### 4.1 App ↔ backend
- **Default anonymous.** An install token (opaque bearer) is scoped to its own install. There are no user passwords anywhere (FR-ONB-02).
- **Optional account** (FR-ACCT, ADR-016):
  - Google or Apple ID tokens are verified server-side with JWKS, audience, issuer and expiry checks. They also need: `iat` no more than 10 minutes old; a nonce pre-image check, **required for both providers** (R2-9), where the app sends the raw nonce and the server compares `hex(SHA-256(raw))` with the claim in constant time; and single use (`replay_guard`) (ADR-016 amendments 2 and 3).
  - The server issues its own ES256 account JWT (30 d).
  - An account only *links* entitlements, and grants no access to any data other than entitlement status.
- **Purchase authorization:**
  - **Verify:** a purchase is honoured only if store verification succeeds **and** the store-side binding (`obfuscatedExternalAccountId` / `appAccountToken`) equals HMAC(installId). Verify needs no device attestation, because the binding is the proof (ADR-012 Amendment (2026-11-05) Part B).
  - **Restore** (D-45, D-46, D-52, FR-GOLD-08/09): possession of a genuine token is **not** proof of ownership. A restore is honoured only when all of these hold:
    - a valid device attestation (Play Integrity standard request / App Attest assertion) is bound to **this install and the request body**: `SHA-256("zaghlol-restore-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body))`, with `installId` taken from the authenticated install token (R2-1);
    - store verification succeeds;
    - for an account-linked purchase, the caller is signed in to that account;
    - the purchase's **single seat** is already on this install, or may move to it because the last move was at least 30 days ago. Otherwise `409 MOVE_COOLDOWN` with `nextMoveAt`.

    The install that lost the seat stops receiving Gold at its next refresh, and offline loses it within 7 days of the move in trusted time (`exp` ≤ `iat` + 3 d, plus 4 d grace; 6 days for a basic-integrity seat; D-60). That is the worst-case overlap of two phones showing Gold. On iOS, a new install on the **same iPhone** that proves a seat key the seat recognises is a rebind, not a move (D-55).
  - **Sign-in** moves the seat of the account's purchases to this install, under the same cooldown, with the verified ID token as the proof (FR-GOLD-07). A purchase is attached to an account **only from its buying install** (`purchases.install_id`, D-54, FR-ACCT-05); there is no other self-service link path, and a purchase whose buying install is gone is linked only by an audited support action (`backend-api.md` §4.6, §5.3). At attach time the seat must be on an install linked to the account, or it returns to the buying install.
  - **Account-linked Gold needs the account token** (D-61(c)): a signed-out holder keeps the seat, but its account-linked purchases are `paused` until it signs in again.
  - **Support move and link** (`support_agent`, FIDO2): a live order-ID check first (D-57); it bypasses the cooldown but restarts it (D-56); it may target only a pending claimant (up to 3, each from the last 7 days), the holder for attach alone under the attach gate (buying install gone or silent ≥ 30 days), or a correction's source install; links made by support can be detached; every call is audited for exactly 1 year (D-47 rules).
  - Seat changes are recorded in `purchase_events`. Alerts carry only the purchase UUID.
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
| Purchases verify/restore | ✔ own (restore: install-bound attestation + one seat + 30-day cooldown; iOS seat-key rebind) | ✔ (account-linked purchases move between, and are granted only on, the account's signed-in installs) | support_agent (seat move, link, detach; live order-ID check; audited) | Store is source of truth for state; the seat decides which single install gets Gold |
| Entitlement read | ✔ own | ✔ | support_viewer | Status and seat state only |
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
| Transport | TLS 1.2+ only (1.3 preferred), HSTS, modern ciphers; managed certificates. Release Android builds trust system CAs only (`network_security_config`; user CAs in `debug-overrides` only), so a user-installed CA can't intercept restore proofs (ADR-012 Part B (d)) |
| Pinning (OQ-15) | **No TLS certificate pinning** (ADR-018). Integrity of security-relevant data comes from ES256 response signatures with keys embedded in the app, which survive certificate rotation. |
| Input validation | FluentValidation on every DTO; unknown fields rejected (except the three third-party bodies, which ignore them); size limits; regex timeouts; no personal data or credentials in query strings, and query strings never logged |
| Rate limiting & abuse | Token bucket per install and per /24; registration limited per IP; WAF managed rules |
| Secrets | Cloud secrets manager; no secrets in config files or images; CI uses OIDC federation (no long-lived keys) |
| Signing keys | ES256 keys in KMS/HSM (`sign` permission for the API identity only). Each `kid` has a 12-month active life. The app embeds current + next public keys, and rotation ships in an app release before activation. |
| Data at rest | Managed PostgreSQL encryption; Apple refresh tokens and idempotency bodies additionally envelope-encrypted with KMS (`IEnvelopeCipher`, format v1 in `deployment.md` §3: AES-256-GCM, fresh data key per record, the row's context bound as associated data) |
| DB access | Separate least-privilege roles; no public IP (private networking); operator access only through the admin API |
| Dependencies | Dependabot/Renovate; `dotnet list package --vulnerable` and SCA in CI; container image scanning; SBOM per release |
| Logging privacy | IP truncation at ingestion; no request bodies logged; install IDs hashed in logs |
| PDPL | DPO appointed; PDPC licence (and cross-border permit if hosted abroad, CR-03); records of processing; breach notification to the PDPC within 72 h and users within 3 days of that (the Executive Regulations rule). **Support tickets** link the support code (install ID) and the order ID to the user's contact details in the helpdesk tool: the privacy notice says so, and T-137 records whether the helpdesk vendor is a PDPL processor (OQ-16) and sets ticket retention |

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
  4. Delete the Keystore/Keychain items, **except the iOS seat keys** (D-55: so that restoring on the same iPhone is not a move; they hold no financial or account data, and the "Delete everything" copy says that Gold can come back to this iPhone and that the server keeps a keyed hash with the purchase, §2a item 2).
  5. Call `DELETE /v1/installs/me` (best effort).
  6. Restart in first-launch state.
