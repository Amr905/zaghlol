# Platform Channel Contracts (Dart ↔ Kotlin / Swift)

All channels are defined in Dart with **Pigeon** (`app/pigeons/*.dart`), which generates the Dart, Kotlin and Swift code. Dart owns the contract (CLAUDE.md §8). Native code does the minimum: OS integration, the Capture Guard and the encrypted spool. **No parsing or business logic runs natively**, except the Guard rules, which are generated from the same data the Dart pipeline uses.

Rules for every channel:
- **No logging:** no message body is ever logged on either side.
- **Typed errors:** errors are returned as `PlatformException(code, message: null)` with codes from §6. Native code never includes message text in an error.
- **Byte payloads:** values cross the channel as `Uint8List` and are zeroed after use where the platform allows.

## 1. Capture Guard (shared concept)

The Guard is the native gatekeeper that enforces BR-ING-01, BR-ING-03, BR-CAP-01/02 and FR-ING-A-02 **before anything is written**.

### 1.1 Guard config (written by Dart, read natively)
- **Written:** by Dart on every change to ignore rules, capture senders or custom templates, and on each app update. It is re-generated from the bundled registry plus DB state.
- **Format:** JSON, then AES-256-GCM encrypted with the **spool key** (§1.3), saved to `files/guard/guard.cfg.enc` (Android) or `Library/Application Support/guard/guard.cfg.enc` in the App Group container (iOS).
- **Size:** under 200 KB.

```json
{
  "v": 3, "registryVersion": 12,
  "senders": [                                   // SMS addresses / alphanumeric IDs → institution
    { "match": "exact", "value": "NBE", "inst": "nbe" },
    { "match": "regex", "value": "^CIB(EGY)?$", "inst": "cib" }
  ],
  "packages": [ { "value": "com.transferwise.android", "inst": "wise" } ],   // notification sources
  "shortcutKeywords": ["خصم","debited","تم تحويل","InstaPay"],              // iOS: Message trigger keywords
  "drop": {                                      // OTP / promo patterns (BR-ING-03), per institution or global
    "global": ["(?i)\\bOTP\\b", "كود التفعيل", "(?i)one[- ]time password"],
    "byInst": { "cib": ["(?i)offer|خصم خاص"] }
  },
  "last4": {                                     // card/account extraction for ignore matching (BR-CAP-02)
    "nbe": ["\\*\\*(\\d{4})", "رقم (\\d{4})"], "*": ["(?:\\*{2,}|x{2,}|ending\\s+)(\\d{4})"]
  },
  "ignore": [ { "inst": "cib", "last4": "9910", "ch": "sms" }, { "inst": "revolut", "last4": null, "ch": "notification" } ],
  "generic": {                                   // FR-PAR-13: unknown senders that look financial
    "senderHints": ["(?i)bank", "بنك", "(?i)pay"],
    "bodyHints": ["(?i)(EGP|USD|ج\\.?م|جنيه)\\s?[\\d٠-٩]", "(?i)debited|credited|خصم|إيداع"],
    "alwaysCapture": ["BDC-ALERT"]
  }
}
```

### 1.2 Guard algorithm (identical in Kotlin, Swift and Dart; shared golden tests)
```
input: channel, source (sender | package | shortcut), body, receivedAt
1. inst = resolve(source) via senders/packages; else if generic.alwaysCapture ∋ source → inst = null (generic)
   else if channel = shortcut_message or apple_pay → inst = guess by body (registry name tokens) or null (generic)
   else if senderHints match source AND bodyHints match body → generic
   else → DROP                                         (non-financial: never stored)
2. if any drop pattern (global ∪ byInst[inst]) matches body → DROP     (OTP / promo)
3. if inst ≠ null and ignore has (inst, null, channel) → DROP          (institution-level ignore)
4. last4 = first capture of last4[inst] ∪ last4["*"]
   if last4 ≠ null and ignore has (inst, last4, channel) → DROP          (card-level ignore)
5. KEEP → spool entry
```
A malformed config makes the Guard **fail closed for unknown senders** but still keep messages from built-in registry senders. The built-in sender list is compiled into the native code as a fallback, so a broken config file can't lose bank SMS (NFR-REL-01).

### 1.3 Spool (encrypted, ack-after-commit)

| | Android | iOS |
|---|---|---|
| Key | Keystore AES-256-GCM key `zaghlol_spool_v1`, non-exportable, `setUserAuthenticationRequired(false)`, StrongBox if available | Keychain item `spool_key_v1` (32 random bytes) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, shared access group with the Share Extension |
| Location | `noBackupFilesDir/spool/` | App Group container `spool/`, `isExcludedFromBackup = true` |
| Entry file | `<ulid>.bin` = nonce(12) ‖ AES-GCM(CBOR{channel, source, body, receivedAt, simSlot, guardInst, guardLast4}) ‖ tag | same |
| Write | atomic: write `.tmp`, fsync, rename | `Data.write(options: .atomic)` |
| Delete | only on `ackSpool(ids)` after the DB commit | same |

## 2. Android (`CaptureHostApi`, `CaptureEventsApi`)

```dart
@HostApi()
abstract class AndroidCaptureHostApi {
  CaptureCapabilities getCapabilities();          // sms granted? notif access? POST_NOTIFICATIONS? device locale for speech
  @async bool requestSmsPermission();             // READ_SMS + RECEIVE_SMS (only in the 'sms' flavor — ADR-004)
  void openNotificationAccessSettings();
  bool isIgnoringBatteryOptimizations();
  void requestIgnoreBatteryOptimizations();       // shown only if live capture is observed to be delayed
  void writeGuardConfig(Uint8List encryptedConfig);
  InboxPage queryInbox(InboxQuery query);         // paged historical scan; native filters by sender list in SQL
  List<SpoolEntry> drainSpool(int max);           // returns decrypted entries (in memory only)
  void ackSpool(List<String> ids);
  void scheduleIngestionNow();                    // expedited WorkManager
}

class InboxQuery { int sinceEpochMs; List<String> senderAddresses; String? afterCursor; int pageSize; /* ≤ 500 */ }
class InboxPage  { List<RawInboxMessage> items; String? nextCursor; int scannedTotal; }
class RawInboxMessage { String address; String body; int dateMs; int? simSlot; String providerId; }
class SpoolEntry { String id; String channel; String source; String body; int receivedAtMs; int? simSlot; }
class CaptureCapabilities { bool smsGranted; bool smsFlavor; bool notificationAccess; bool postNotifications; int sdkInt; }

@FlutterApi()
abstract class CaptureEventsApi { void onSpoolChanged(int pendingCount); void onPermissionChanged(CaptureCapabilities c); }
```

**Native components:**
- **`SmsReceiver`** (`SMS_RECEIVED`, priority default):
  1. Assembles multipart PDUs by sender and timestamp (EC-09).
  2. Runs the Guard and spools the message.
  3. Calls `goAsync()`, which is bounded to 5 s.
  4. Enqueues `IngestionWorker` (expedited, `OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST`).
  5. Calls `CaptureEventsApi.onSpoolChanged` if an engine is attached.
- **`BankNotificationListener`:**
  - Gets the `onNotificationPosted` callback and filters `packageName` against `packages`.
  - Reads `EXTRA_TITLE`, `EXTRA_TEXT` and `EXTRA_BIG_TEXT`.
  - Ignores ongoing and group-summary notifications.
  - Then runs Guard → spool as above.
- **`IngestionWorker`:**
  1. Starts a `FlutterEngine` with entrypoint `ingestionMain`, or reuses the cached engine if the app is alive.
  2. Waits for Dart to finish draining (`MethodChannel` completion), 60 s maximum.
  3. Destroys the engine.
  4. If the spool is still non-empty, re-enqueues with back-off.
- **`InboxReader`:** `ContentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, …, "address IN (?, …) AND date > ?", …)`, paged by `_id`. Only allowlisted senders are ever read into memory.
- **Manifest:**
  - `android:allowBackup="false"`;
  - `dataExtractionRules` exclude everything (FR-SEC-05);
  - `FLAG_SECURE` plus `setRecentsScreenshotEnabled(false)` when app lock is on (FR-SEC-02);
  - share intent filters for `text/plain`, `image/*`, `application/pdf`, `text/csv`.

## 3. iOS (`IosCaptureHostApi`, App Intents, extensions)

```dart
@HostApi()
abstract class IosCaptureHostApi {
  void writeGuardConfig(Uint8List encryptedConfig);
  List<SpoolEntry> drainSpool(int max);
  void ackSpool(List<String> ids);
  ShortcutSetupStatus getShortcutSetupStatus();   // from per-intent last-run timestamps recorded natively
  String shortcutInstallUrl();                    // iCloud link of the signed Zaghlol.shortcut
  void registerBackgroundRefresh();               // BGAppRefreshTask 'app.zaghlol.ingest'
}
class ShortcutSetupStatus { int? lastMessageIntentAtMs; int? lastWalletIntentAtMs; List<String> keywordsSeen; }
```

**App Intents** (in the Runner target, so they run in the app process; iOS 17+):
```swift
struct LogBankMessageIntent: AppIntent {           // Shortcuts "Message contains <keyword>" → Run Immediately
  static var title: LocalizedStringResource = "سجّل رسالة البنك"
  static var openAppWhenRun = false
  @Parameter(title: "Message") var message: String
  @Parameter(title: "Sender") var sender: String?  // Shortcut passes 'Sender' when available
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try CaptureGuard.shared.process(channel: .shortcutMessage, source: sender, body: message)   // → spool
    StatusStore.recordRun(.message)
    return .result(dialog: "زغلول سجلها ✓")       // short, no amounts (lock-screen privacy)
  }
}
struct LogWalletTransactionIntent: AppIntent {     // Shortcuts "Transaction" (Wallet) automation
  @Parameter(title: "Amount") var amount: String   // e.g. "EGP 450.00"
  @Parameter(title: "Merchant") var merchant: String
  @Parameter(title: "Card") var card: String       // card/pass name, e.g. "CIB Visa"
  // Guard maps card name → institution via registry `walletCardNames`; ignore channel = apple_pay
}
struct ZaghlolShortcuts: AppShortcutsProvider { … }  // exposes both intents in the Shortcuts app
```

**Other iOS pieces:**
- **Share Extension:** accepts text, images and PDFs.
  - Text goes through Guard → spool with channel `share`.
  - Images and PDFs are copied **encrypted** (spool key) to `spool/files/` and processed in the app with user confirmation (FR-ING-A-04, FR-ING-I-04).
  - The extension never parses or displays amounts.
- **Back Tap:** documented in setup. It runs a Shortcut that takes a screenshot and shares it to Zaghlol, then follows the same path as the Share Extension.
- **Data protection:** the DB file and spool use `NSFileProtectionCompleteUntilFirstUserAuthentication`, so Shortcuts can run while the phone is locked after the first unlock.

## 4. OCR (`OcrHostApi`, both platforms)

```dart
@HostApi()
abstract class OcrHostApi {
  @async OcrResult recognize(String encryptedImagePath, List<String> languages);   // ['ar','en']
  List<String> supportedLanguages();
}
class OcrResult { List<OcrLine> lines; }
class OcrLine { String text; double confidence; List<double> box; /* x,y,w,h normalized */ }
```
- **iOS:** Vision `VNRecognizeTextRequest`, `.accurate`. `recognitionLanguages` comes from `supportedRecognitionLanguages()` at runtime; Arabic is used only if listed.
- **Android:** ML Kit Text Recognition v2 (Latin) **plus** Tesseract4Android with `ara` (fast model, bundled) for Arabic lines. Results are merged by bounding box (ADR-009).
- The image is decrypted in memory only. Its temp file is deleted in a `finally` block, and receipt images are never persisted (FR-SEC-03).

## 4a. Device attestation (`AttestationHostApi`, both platforms; D-45/D-46, FR-GOLD-09)

Owner: T-178 (native host API and release network config). The hashes Dart passes in come from the binding library (T-183).

```dart
@HostApi()
abstract class AttestationHostApi {
  /// Android: Play Integrity StandardIntegrityManager.prepareIntegrityToken (cached provider). iOS: no-op.
  @async void prepare();
  /// bodyHash = SHA-256("zaghlol-restore-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(restore body without "attestation")),
  /// computed in Dart (RFC 8785, shared vectors restore-binding-v1.json) with this install's own installId.
  /// Android requestHash = base64url(bodyHash); iOS clientDataHash = bodyHash (also for attestKey on a new key).
  /// Android: StandardIntegrityTokenProvider.request(requestHash) → token.
  /// iOS: DCAppAttestService.generateAssertion(keyId, clientDataHash = SHA-256 bytes); on a new key also attestKey(...).
  @async AttestationProof attest(Uint8List bodyHash, bool forceNewKey);
}
class AttestationProof {
  String type;               // 'play_integrity' | 'app_attest'
  String? token;             // Android
  String? keyId;             // iOS, base64
  String? assertion;         // iOS, base64
  String? attestationObject; // iOS, base64, only for a newly generated key
}
```
- **Android:** `com.google.android.play:integrity` (standard request). The cloud project number comes from build config. Errors map to `ATTEST_TRANSIENT` (`NETWORK_ERROR`, `TOO_MANY_REQUESTS`, `GOOGLE_SERVER_UNAVAILABLE`, `INTEGRITY_TOKEN_PROVIDER_INVALID` → re-prepare once), `ATTEST_PLAY_SERVICES_OUTDATED` and `ATTEST_UNAVAILABLE`.
- **iOS:** `DeviceCheck.DCAppAttestService`. If `isSupported == false`, the result is `ATTEST_UNAVAILABLE`. The `keyId` is stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable. `forceNewKey`, or an `invalidKey` error, deletes it, generates a new key and returns an `attestationObject` too. `serverUnavailable` maps to `ATTEST_TRANSIENT`.
- **Install binding (R2-1):** native code never builds the hash and never sees the install ID; it signs exactly the 32 bytes Dart passes. On iOS a new key's `attestKey(keyId, clientDataHash:)` uses the **same** hash as the assertion, so the key registers only to this install.
- **iOS `clientDataHash` (R4-1(3)):** Dart passes `SHA-256("zaghlol-restore-attest-v1" ‖ 0x00 ‖ bodyHash ‖ SHA-256(pk₀ ‖ … ‖ pkₙ₋₁))`, not `bodyHash` itself, so the assertion covers the seat public keys of §4b. Order of calls in Dart: build `bodyHash`, `SeatKeyHostApi.sign(message over bodyHash)`, compute the digest of the returned public keys in that order, then `AttestationHostApi` with the resulting hash. Vectors: `restore-binding-v1.json` (`seatKeysDigestHex`, `clientDataHashHex`).
- **Release network config:** release Android builds ship `network_security_config` trusting system CAs only (user CAs only under `<debug-overrides>`), so a user-installed CA can't capture restore bodies and proofs. Owner: T-178, checked again in T-145.
- **Play Console:** the optional integrity verdicts (`deviceAttributes`, `recentDeviceActivity`, `appAccessRiskVerdict`, `environmentDetails`) stay off (T-140 checklist, D-45).
- **Nothing else is collected or returned:** no device identifiers, and no verdicts on device. The proof goes straight into the restore body (BR-SYNC-03 amended, D-45). Proofs are never written to the diag log.

## 4b. Trusted clock and seat keys (`TrustedClockHostApi` both platforms, `SeatKeyHostApi` iOS; D-55, D-60, R3-1)

Native owners: T-180 (`TrustedClockHostApi`), T-179 (`SeatKeyHostApi` and the Dart seat-key service). The Dart side (T-144) owns the trusted-time algorithm of `backend-api.md` §4.3 *Trusted time* (`hw`, the uncharged bound `lb`, the reboot rules of R4-3) and the state in `secure_state`, plus the in-memory outstanding time nonce (R4-2), which Dart draws from `Random.secure()` and never passes to native code. Native code only reads clocks and holds Secure Enclave keys.

```dart
@HostApi()
abstract class TrustedClockHostApi {
  /// One consistent sample. Never sent off the device (Apple required-reason API 35F9.1: elapsed time inside the app).
  ClockSample sample();
}
class ClockSample {
  int wallMs;          // epoch ms (System.currentTimeMillis / Date().timeIntervalSince1970)
  int monotonicMs;     // Android SystemClock.elapsedRealtime(); iOS clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e6 (counts sleep)
  int? bootCount;      // Android Settings.Global.BOOT_COUNT; iOS null (no public boot identifier)
}

@HostApi()   // iOS only; Android has no implementation (D-55)
abstract class SeatKeyHostApi {
  /// Ensures this install has a seat key (creates one in the Secure Enclave on first call) and returns
  /// [own, earlier…] public keys (X9.63, 65 bytes), newest first, at most 5. Empty list when the Secure Enclave is unavailable.
  List<Uint8List> publicKeys();
  /// Signs `message` (built in Dart: "zaghlol-seat-v1" ‖ 0 ‖ op ‖ 0 ‖ installId ‖ 0 ‖ challenge) with every key, same order.
  /// Returns IEEE P1363 r‖s signatures (64 bytes). A key that can't be used is dropped from the Keychain and from the result.
  List<SeatSignature> sign(Uint8List message);
  /// Called once when a new install is created: the current key becomes an "earlier" key; a new one is made lazily.
  void rotateForNewInstall();
}
class SeatSignature { Uint8List publicKey; Uint8List signature; }
```
- **Storage:** `SecureEnclave.P256.Signing.PrivateKey`; its `dataRepresentation` (an SE-wrapped blob, useless off this device) is stored in a generic-password Keychain item, service `app.zaghlol.seatkey`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`, no access group shared with extensions. FIFO cap of 5 keys.
- **Lifecycle:** "Delete everything" calls `rotateForNewInstall()` instead of deleting the items (D-55); app deletion leaves them in place (current iOS behaviour, not a documented guarantee); a device erase removes them.
- **Element 0 is fixed per install (R4-1(1)).** The server registers the first key an install sends and answers `SEAT_KEY_MISMATCH` to any other element 0. `publicKeys()` must therefore return the same own key for the whole life of an install; it may create a new own key only when the old one is unusable, and Dart then retries once without `seatKeys`. After that retry succeeds, Dart persists "own seat key unusable for this install" in `secure_state` and sends no `seatKeys` from this install again (R5-6); the flag is dropped with the install ID on re-registration. `rotateForNewInstall()` is the only other way the own key changes.
- **No identifiers leave native code** other than the public keys and signatures Dart puts into `seatKeys`. Neither is ever written to the diag log (D-62).
- **Device tests (T-179 for the seat keys, T-180 for the clocks; C4):** the Keychain item **and** the Secure Enclave key it wraps survive deleting the app and reinstalling it, on the oldest and newest supported iOS versions (R-19, SRS v1.7: a sign/verify round trip after reinstall proves the key is still usable, not only that the item exists); it survives "Delete everything"; a sign/verify round trip against `seat-proof-v1.json`'s message format; `CLOCK_MONOTONIC_RAW` advances across sleep; `BOOT_COUNT` increments after a reboot.

## 5. Other hosts

| API | Methods | Notes |
|---|---|---|
| `ICloudBackupHostApi` (iOS) | `isAvailable()`, `upload(path, name)`, `list() → [BackupMeta]`, `download(name) → path`, `delete(name)` | Ubiquity container `iCloud.app.zaghlol`, `Documents/Backups/`. The file is already encrypted (ADR-011). |
| `DeviceSecurityHostApi` | `isDeviceRooted()`, `setSecureWindow(bool)`, `isDeviceSecure()` (passcode set) | FR-SEC-02/07. The heuristic checks warn, never block. |
| `WidgetBridgeHostApi` | `updateSnapshot(WidgetSnapshot)` | Snapshot = {safeToSpendText or "•••", daysToPayday, currency, updatedAt}. Stored in the widget's own shared storage. **Only already-formatted, redaction-aware strings** are stored there (FR-WID-01). |
| Speech | via `speech_to_text` plugin (no custom channel) | `onDevice: true` preferred; online only with consent (ADR-010). |
| `SecretStoreHostApi` (both platforms; T-015, ADR-002 Amendment 2026-11-10) | `acquireBootstrapLease(timeoutMs) → lease`, `releaseBootstrapLease(lease)`, `read(slot) → SecretReadMsg{status, value?, attempts}`, `createIfAbsent(lease, slot, candidate) → stored`, `delete(lease, slot)`; all `@async` | Slots: `dbKey` (T-148 adds the backup key). Status: `found`, `notFound` (positive evidence of absence), `unusable` (positive evidence the stored key can never be read: Keystore alias missing, AEAD tag failure, malformed blob, `KeyPermanentlyInvalidatedException`, API 33+ `ERROR_KEY_DOES_NOT_EXIST`/`ERROR_KEY_CORRUPTED`; iOS: wrong item length), `unavailable` (every other error, after 3 retries at 100/300/900 ms; never a reason to wipe). Android: Keystore AES-256-GCM key `zaghlol_db_kek_v1` wraps the key in `noBackupFilesDir/keys/db_key_v1.bin`. iOS: generic password `app.zaghlol.keys`/`db_key_v1`, `AfterFirstUnlockThisDeviceOnly`, not synchronizable. The lease is process-wide (all engines) and expires after 30 s; writes need the current lease. `createIfAbsent` returns an existing usable value instead of overwriting, and refuses (`KEY_STORE_FAILED`) over an unusable or unknown one. **Register in every engine that opens the database** (UI engine: `MainActivity` / `AppDelegate`; headless engine: T-008). No logging in the keys code; errors carry the code only. |

## 6. Error codes (native → Dart)

`PERMISSION_DENIED`, `NOT_AVAILABLE`, `SPOOL_DECRYPT_FAILED` (entry quarantined and deleted after 3 failures, with a diag code logged), `KEY_INVALIDATED` (Keystore key lost after a security change: regenerate it, re-write the Guard config, and accept that pending spool entries are lost; this is user-visible in Settings as "re-scan" on Android), `CONFIG_INVALID`, `ICLOUD_UNAVAILABLE`, `OCR_FAILED`, `IO_ERROR`, `ATTEST_TRANSIENT`, `ATTEST_PLAY_SERVICES_OUTDATED`, `ATTEST_UNAVAILABLE`, `SEAT_KEY_UNAVAILABLE` (no Secure Enclave or Keychain error: send no `seatKeys`), `KEY_STORE_FAILED` (`SecretStoreHostApi` could not write, verify or delete a secret, or refused to overwrite an unusable one: no database may be created, never a wipe), `LEASE_TIMEOUT` (the bootstrap lease was not free in time, or a write used a lease that is no longer current: retry). Secret-store errors carry the code only (`message` and `details` are null).
