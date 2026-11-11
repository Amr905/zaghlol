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
| Key | Keystore AES-256-GCM key `zaghlol_spool_v1`, non-exportable, `setUserAuthenticationRequired(false)`, TEE-backed AndroidKeyStore, not StrongBox (bulk data; Lead decision 2026-11-10, T-060 review C1) | Keychain item `spool_key_v1` (32 random bytes) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, shared access group with the Share Extension |
| Location | `noBackupFilesDir/spool/` | App Group container `spool/`, `isExcludedFromBackup = true` |
| Entry file | `<ulid>.bin` = nonce(12) ‖ AES-GCM(record) ‖ tag, **AAD `zaghlol.spool.v1\|entry\|<ulid>`** (an entry can't be renamed or swapped). The record is a versioned binary record (T-008, Lead Q8; replaces CBOR: same fields, no dependency): `u8 v=1 \| str8 channel \| str16 source \| u32 len + UTF-8 body \| i64 receivedAtMs \| i32 simSlot (-1 none) \| opt8 guardInst \| opt8 guardLast4 \| i64 rxElapsedNs \| i32 bootCount` (big-endian; `strN` = N-bit length + UTF-8; `opt8` = present flag + str8; the last two are spike timing fields). Strict decode: unknown version, over-long field (body ≤ 4,000 chars), invalid UTF-8 or trailing bytes = malformed | same record and AAD (T-044) |
| Write | atomic: write `.tmp`, fsync, rename; a `.tmp` older than 60 s is swept on drain (one whose age can't be read is kept) | `Data.write(options: .atomic)` |
| Caps | 500 entries or 4 MiB on disk; beyond either the **new** message is refused (diag `SPOOL_FULL`), never an old one evicted | same |
| Dedupe | none in the spool (at-least-once; a hash in a file name would be a body fingerprint). The DB's unique `raw_messages.body_hash` (BR-ING-02) is the only dedupe | same |
| Delete | only on `ackSpool(ids)` after the DB commit; no age purge (unlike `share/`) | same |
| Read errors | delete only on proof: GCM tag failure, truncation or a malformed record is retried at 100/300/900 ms in that drain and the entry deleted (`SPOOL_DECRYPT_FAILED`, counted) only when every attempt proves it; any I/O or Keystore error in any attempt keeps it | same |
| Drain claim | process-wide: `drainSpool` hands entries to one engine at a time (the claim is released when that engine has acked all it drained, when it detaches, or 60 s after its last drain), so the UI and headless engines never process the same entry concurrently. While another engine holds the claim, `drainSpool` returns an empty list | n/a (one engine) |

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
  - **As built in the T-008 spike** (`src/devSms` only; T-041 productionises): unique work `zaghlol.ingest`, `APPEND_OR_REPLACE`, expedited with `RUN_AS_NON_EXPEDITED_WORK_REQUEST`, no constraints, exponential back-off from 10 s, never `setForeground` (Android 8–11 fall back to a foreground service with a low-importance localized notification). If the UI engine is attached it never starts a second engine: it calls `CaptureEventsApi.onSpoolChanged` and waits for the spool to empty. Otherwise it uses a process-wide `FlutterEngineGroup` engine (`ingestionMain` in `lib/main.dart`, body in `lib/ingestion/ingestion_main.dart`) with `automaticallyRegisterPlugins = false` and an explicit allowlist: `JniPlugin` + `JniFlutterPlugin` (path_provider_android 2.3 is JNI-based, so both engines resolve the same DB directory), `SecretStoreRegistration` (§5), the spool host (other `AndroidCaptureHostApi` methods answer `NOT_AVAILABLE` until their owner tasks), and the spike-only `zaghlol/spike_metrics` channel. Worker result: success when the spool is empty or the DB does not exist yet (the UI engine creates it and drains at start); retry on `DB_MIGRATION_PENDING`, `DB_DEFERRED`, a transient failure or the 60 s budget. Shutdown (linger end, memory trim, UI engine attach): a pending drain is answered first (bounded), then the spike channel's `close` command makes Dart wait for any running cycle and await the database close, then the engine is destroyed (bounded; T-008 review F1). T-041 keeps this order: the headless engine is never destroyed mid-transaction or with an open connection.
  - **Headless DB rule (T-008, Lead Q6):** the headless engine opens with `allowMigration` and `allowCreateOrWipe` false. It never creates the database or its key, rotates or deletes a key, wipes an orphan, deletes migration leftovers or lets drift run `onCreate`; each of those is `DB_DEFERRED` (gate `deferToForeground`) with nothing touched. A missing `zaghlol.db` is not opened at all.
- **`InboxReader`:** `ContentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, …, "address IN (?, …) AND date > ?", …)`, paged by `_id`. Only allowlisted senders are ever read into memory.
- **Manifest:**
  - `android:allowBackup="false"`;
  - `dataExtractionRules` exclude everything (FR-SEC-05);
  - `FLAG_SECURE` plus `setRecentsScreenshotEnabled(false)` when app lock is on (FR-SEC-02);
  - share intent filters for `text/plain`, `image/*`, `application/pdf`, `text/csv`.

### 2.1 Share intake (T-060; contract addition, `app/pigeons/share_intake_api.dart`)

**Approved by Lead 2026-11-10 (T-060 review).** The capture API above has no way to hand a shared file to Dart, so T-060 adds a separate Pigeon file. `AndroidCaptureHostApi` is unchanged.

```dart
enum ShareKind { text, image, pdf, csv }
enum ShareRejectReason { tooLarge, unsupportedType, unreadable, empty }
class ShareDescriptor { String id; ShareKind kind; String mimeType; int sizeBytes; int receivedAtMs; }   // metadata only
class ShareContent { ShareDescriptor descriptor; String? text; Uint8List? bytes; }                         // decrypted, in memory only

@HostApi()
abstract class ShareIntakeHostApi {
  List<ShareDescriptor> listPendingShares();   // oldest first; purges shares older than 24 h
  ShareContent readShare(String id);           // IO_ERROR (unknown id, or transient: share kept) | SPOOL_DECRYPT_FAILED (not authentic: entry deleted)
  void discardShare(String id);                // idempotent
  ShareRejectReason? takePendingRejection();   // once
}
@FlutterApi()
abstract class ShareIntakeEventsApi { void onShareReceived(ShareDescriptor d); void onShareRejected(ShareRejectReason r); }
```

- **`ShareActivity`** (exported; `ACTION_SEND`, MIME `text/plain`, `image/*`, `application/pdf`, `text/csv`; no UI, no permission, `excludeFromRecents`, empty `taskAffinity`): validates and encrypts on one worker thread, then opens `MainActivity` with an explicit intent that carries no content, only a per-process random hand-off token.
  - **Time bound:** the whole intake must finish within 20 s of the share arriving. Past it the sender's stream is closed, nothing is committed (the partial file is deleted) and the share is refused as `unreadable`; 3 s later the activity gives up on the worker regardless.
  - **Recreation:** the job id is kept in the saved instance state; a recreated activity re-attaches to the running job and never ingests the same share twice.
- **`MainActivity`** (exported launcher): a `SHARE_READY` intent is honoured only with the matching token, and only that may consume the refusal slot. On **every resume** it announces every pending share with `onShareReceived` (it reads the store only, so a spoofed intent cannot consume anything). Dart deduplicates by id and also calls `takePendingRejection()` and `listPendingShares()` at startup and on every resume.
- **Storage:** `noBackupFilesDir/share/<id>.bin` + `<id>.meta`, a directory of its own (never under `spool/`: the share store purges by age, the T-039 spool deletes only on ack). Both files are `nonce(12) || AES-256-GCM` with the spool key `zaghlol_spool_v1` (section 1.3), with AAD `zaghlol.share.v1|meta|<id>` and `zaghlol.share.v1|body|<id>|<kind>`, so files cannot be swapped between shares, roles or kinds. The key is obtained only through `SpoolKey` (`app.zaghlol.platform.spool`), which serialises get-or-create process-wide; T-039 must reuse it. Every share, text included, is stored this way until `discardShare`. Dart discards after the user confirms or cancels.
- **Read errors:** a share is deleted only on proof that it is bad (GCM authentication failure, truncation, malformed metadata): `SPOOL_DECRYPT_FAILED`. I/O or Keystore failures return `IO_ERROR` and keep the share for a retry.
- **Limits (native, on bytes read):** text 100,000 chars; image 15 MiB and at most 64,000,000 decoded pixels (bounds read with `BitmapFactory` `inJustDecodeBounds` from the first 4 MiB; an image whose bounds cannot be read is refused as `unsupportedType`); PDF 20 MiB; CSV 5 MiB. At most 10 pending shares and 100 MiB on disk; beyond either the new share is refused as `tooLarge` (before the sender's stream is opened when the count is reached). Images are accepted only as PNG, JPEG, WEBP or HEIC/HEIF by magic bytes; PDFs by `%PDF-`; text files must be valid UTF-8; CSV may be any text encoding but not binary.
- **URIs:** only `content://` is read. A URI with user info (`content://x@host/...`) is refused, and so is any host equal to this app's package or starting with `<package>.` (compared on `Uri.getHost()`, lowercase) and any authority that resolves to a provider of this app.
- **Paste** is a Dart-side clipboard read on a user tap. Native code never reads the clipboard.
- Shared text does **not** go through the Capture Guard: it is user-initiated and always shown for confirmation (FR-ING-A-04). The confirmation stays mandatory (no auto-save).
- **Dart side owners** (wiring, routing, app-lock gate): FU-067 in `docs/implementation-status.md`.

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
| `TextNormalizationHostApi` (both platforms; T-148) | `nfc(String) → String` | Unicode NFC for the backup passphrase (Android `java.text.Normalizer`, iOS `precomposedStringWithCanonicalMapping`), so both platforms derive the same key. Stateless; the argument is never logged or stored. Registered on the UI engine only (`MainActivity`, `AppDelegate`). Dart calls it only when the folded passphrase has a code point ≥ U+0300 (anything below is already NFC). Shared NFC rows: `app/test/fixtures/backup/zglb-v1-vectors.json`, mirrored in the Kotlin and Swift unit tests (a Dart test checks they match). |
| `DeviceSecurityHostApi` | `isDeviceRooted()`, `setSecureWindow(bool)`, `isDeviceSecure()` (passcode set) | FR-SEC-02/07. The heuristic checks warn, never block. |
| `WidgetBridgeHostApi` | `updateSnapshot(WidgetSnapshot)` | Snapshot = {safeToSpendText or "•••", daysToPayday, currency, updatedAt}. Stored in the widget's own shared storage. **Only already-formatted, redaction-aware strings** are stored there (FR-WID-01). |
| Speech | via `speech_to_text` plugin (no custom channel) | `onDevice: true` preferred; online only with consent (ADR-010). |
| `SecretStoreHostApi` (both platforms; T-015, ADR-002 Amendment 2026-11-10) | `acquireBootstrapLease(timeoutMs) → lease`, `releaseBootstrapLease(lease)`, `renewBootstrapLease(lease) → bool` (T-016), `read(slot) → SecretReadMsg{status, value?, attempts}`, `createIfAbsent(lease, slot, candidate) → stored`, `delete(lease, slot)`; all `@async` | Slots: `dbKey`; `backupKey` (T-148: 32-byte `K_bk`; Android Keystore key `zaghlol_bk_kek_v1`, blob `noBackupFilesDir/keys/backup_key_v1.bin`; iOS account `backup_key_v1`; same status rules, written under the lease). Status: `found`, `notFound` (positive evidence of absence), `unusable` (positive evidence the stored key can never be read: Keystore alias missing, AEAD tag failure, malformed blob, `KeyPermanentlyInvalidatedException`, API 33+ `ERROR_KEY_DOES_NOT_EXIST`/`ERROR_KEY_CORRUPTED`; iOS: wrong item length), `unavailable` (every other error, including an Android blob whose presence can't be determined; never a reason to wipe). Every non-`found` read is retried at 100/300/900 ms: one `found` wins; `notFound`/`unusable` are returned only when every attempt agrees, otherwise `unavailable` (T-015 S-1; an Android `notFound` rests on the file system proving absence and needs no confirmation). Android: Keystore AES-256-GCM key `zaghlol_db_kek_v1` wraps the key in `noBackupFilesDir/keys/db_key_v1.bin`. iOS: generic password `app.zaghlol.keys`/`db_key_v1`, `AfterFirstUnlockThisDeviceOnly`, not synchronizable, `kSecAttrAccessGroup` pinned to Runner's own `<AppIdentifierPrefix><bundle id>` group. The lease is process-wide (all engines) and expires after 30 s; writes need the current lease. `renewBootstrapLease` (T-016, S-2): if the lease is current and unexpired, its expiry becomes now + 30 s and it returns true, else false; it never takes a lease. Dart calls it through `BootstrapLease.ensureValid()` before every create or wipe step (false → `DB_LEASE_LAPSED`, stop). Same-lease renewals are unbounded, but a dead engine stops renewing and its lease still lapses after 30 s. `createIfAbsent` returns an existing usable value instead of overwriting, and refuses (`KEY_STORE_FAILED`) over an unusable or unknown one. **Register in every engine that opens the database** (UI engine: `MainActivity` / `AppDelegate`; headless engine: T-008, done in the spike's `HeadlessEngine`). No logging in the keys code; errors carry the code only. |

## 6. Error codes (native → Dart)

`PERMISSION_DENIED`, `NOT_AVAILABLE`, `SPOOL_DECRYPT_FAILED` (entry quarantined and deleted after 3 failures, with a diag code logged), `KEY_INVALIDATED` (Keystore key lost after a security change: regenerate it, re-write the Guard config, and accept that pending spool entries are lost; this is user-visible in Settings as "re-scan" on Android), `CONFIG_INVALID`, `ICLOUD_UNAVAILABLE`, `OCR_FAILED`, `IO_ERROR`, `ATTEST_TRANSIENT`, `ATTEST_PLAY_SERVICES_OUTDATED`, `ATTEST_UNAVAILABLE`, `SEAT_KEY_UNAVAILABLE` (no Secure Enclave or Keychain error: send no `seatKeys`), `KEY_STORE_FAILED` (`SecretStoreHostApi` could not write, verify or delete a secret, or refused to overwrite an unusable one: no database may be created, never a wipe), `LEASE_TIMEOUT` (the bootstrap lease was not free in time, or a write used a lease that is no longer current: retry). Secret-store errors carry the code only (`message` and `details` are null), `NORMALIZATION_FAILED` (`TextNormalizationHostApi` (T-148): code only, never the argument; Dart turns it into the backup error `io` and never falls back to an un-normalized passphrase).
