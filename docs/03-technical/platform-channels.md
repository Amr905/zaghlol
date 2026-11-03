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

## 5. Other hosts

| API | Methods | Notes |
|---|---|---|
| `ICloudBackupHostApi` (iOS) | `isAvailable()`, `upload(path, name)`, `list() → [BackupMeta]`, `download(name) → path`, `delete(name)` | Ubiquity container `iCloud.app.zaghlol`, `Documents/Backups/`. The file is already encrypted (ADR-011). |
| `DeviceSecurityHostApi` | `isDeviceRooted()`, `setSecureWindow(bool)`, `isDeviceSecure()` (passcode set) | FR-SEC-02/07. The heuristic checks warn, never block. |
| `WidgetBridgeHostApi` | `updateSnapshot(WidgetSnapshot)` | Snapshot = {safeToSpendText or "•••", daysToPayday, currency, updatedAt}. Stored in the widget's own shared storage. **Only already-formatted, redaction-aware strings** are stored there (FR-WID-01). |
| Speech | via `speech_to_text` plugin (no custom channel) | `onDevice: true` preferred; online only with consent (ADR-010). |
| Secure storage | via `flutter_secure_storage` | Android: `encryptedSharedPreferences` off; uses Keystore-wrapped AES. iOS: `first_unlock_this_device`. |

## 6. Error codes (native → Dart)

`PERMISSION_DENIED`, `NOT_AVAILABLE`, `SPOOL_DECRYPT_FAILED` (entry quarantined and deleted after 3 failures, with a diag code logged), `KEY_INVALIDATED` (Keystore key lost after a security change: regenerate it, re-write the Guard config, and accept that pending spool entries are lost; this is user-visible in Settings as "re-scan" on Android), `CONFIG_INVALID`, `ICLOUD_UNAVAILABLE`, `OCR_FAILED`, `IO_ERROR`.
