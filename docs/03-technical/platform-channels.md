# Platform Channel Contracts (Dart ↔ Kotlin / Swift)

All channels are defined in Dart with **Pigeon** (`app/pigeons/*.dart`), which generates the Dart, Kotlin and Swift code. Dart owns the contract (CLAUDE.md §8). Native code does the minimum: OS integration, the Capture Guard and the encrypted spool. **No parsing or business logic runs natively**, except the Guard rules, which are generated from the same data the Dart pipeline uses.

Rules for every channel:
- **No logging:** no message body is ever logged on either side.
- **Typed errors:** errors are returned as `PlatformException(code, message: null)` with codes from §6. Native code never includes message text in an error.
- **Byte payloads:** values cross the channel as `Uint8List` and are zeroed after use where the platform allows.

## 1. Capture Guard (shared concept)

The Guard is the native gatekeeper that enforces BR-ING-01, BR-ING-03, BR-CAP-01/02 and FR-ING-A-02 **before anything is written**.

### 1.1 Guard config (two parts; T-035, approved by Lead 2026-11-11)

The config is split in two so that an app update never waits for an app open and a failure to read user state never loses bank SMS.

**Base part `guard_base.json`** (registry data; public, protected by the app signature):
- **Generated** at build time from the registry by `exportGuardConfig` (`packages/zaghlol_parsing/lib/registry/guard_export.dart`) and **bundled as a Flutter asset** `app/assets/guard/guard_base.json` (asset wiring and the CI staleness step `registry_lint --check-guard-config` land with T-036, the first real registry). Native code reads it without an engine: Android through `AssetManager` (`flutter_assets/assets/guard/guard_base.json`); iOS (T-061) also copies it into the App Group container for the extensions.
- **Plaintext**, deterministic bytes (institutions sorted by code, file order within one, fixed key order), at most 200 KB.
- Values are exported in the form the Guards compare: exact senders, `alwaysCapture` ids and wallet card names as `foldKey` text (§1.2); packages trimmed; patterns as written minus a leading `(?i)`, with Arabic letter variants folded, and in the **portable regex subset** (below).

```json
{
  "v": 4, "registryVersion": 12,
  "senders":  [ { "match": "exact", "value": "nbe", "inst": "nbe" },          // value = foldKey(sender id)
                { "match": "regex", "value": "^cib-(?:egy|alert)$", "inst": "cib" } ],  // runs on foldKey(source)
  "packages": [ { "value": "com.transferwise.android", "inst": "wise" } ],
  "wallet":   [ { "name": "cib", "inst": "cib" } ],                            // registry walletCardNames, folded (apple_pay)
  "drop": { "global": [ "<OTP shapes, see §1.2>" ], "byInst": { "nbe": ["عرض خاص"] } },
  "last4": { "nbe": ["\\*\\*([0-9]{4})"], "*": ["(?:\\*\\*|xx|ending )([0-9]{4})"] },   // exactly one capture group
  "generic": { "senderHints": ["bank", "بنك"], "bodyHints": ["(?:egp|usd|ج\\.?م|جنيه) ?[0-9]"], "alwaysCapture": ["bdc-alert"] },
  "shortcutKeywords": ["خصم", "debited", "تم تحويل", "InstaPay"],
  "rate": { "perSenderPerMin": 20 }
}
```

**User part** (database state; financial: institution + last-4 pairs):
- Built by `buildGuardUserConfig` (`lib/guard/guard_user_config.dart`) from `ignore_rules`, `capture_senders.always_capture` and the senders of the user's custom templates (T-047 reads the rows and calls it on every change to them and on each app start). Sorted, deduplicated, at most 64 KB, 1,000 ignore rules and 200 senders. An invalid row or a cap overrun is an **error** (code + JSON path, never a value): the config is never truncated and the previous file stays in force.
  ```json
  { "v": 1, "baseRegistryVersion": 12,
    "ignore": [ { "inst": "cib", "last4": "9910", "ch": "sms" }, { "inst": "wise", "last4": null, "ch": "notification" } ],
    "userSenders": [ { "value": "mycoop", "ch": "sms" } ] }               // value folded like the source (§1.2)
  ```
- **Written** by `writeGuardConfig(Uint8List userConfigJson)` (§2, §3), which takes the **plaintext** JSON (Dart can't use the non-exportable spool key). Native parses it with its own reader; invalid → `CONFIG_INVALID` and the old file is kept. Otherwise it encrypts with the spool key (§1.3, `SpoolKey`; AES-256-GCM, AAD `zaghlol.guard.v1|user`), writes `noBackupFilesDir/guard/guard.user.enc` (Android; T-038 L-1, 2026-11-11) or `Library/Application Support/guard/guard.user.enc` in the App Group container (iOS, excluded from backup like the other App Group roots, T-061) via tmp + fsync + rename, and zeroes the buffer. The method runs on a Pigeon background task queue (Keystore + fsync). (T-039 renamed the Pigeon parameter from `encryptedConfig` to `userConfigJson` and moved the method to a background task queue, with the other contract changes of §2 (FU-097 L-2). The wire type, bytes, is unchanged. The Android host `AndroidCaptureHost` passes the bytes to an injected writer, wired to `GuardRuntime` by T-040, and answers `NOT_AVAILABLE` until then.) Android reader/writer: T-038 (`app.zaghlol.platform.guard.GuardRuntime`): an undecryptable or malformed user file is kept (not deleted) and reported as `GuardConfigState.userUnreadable` through `getSpoolStatus` until Dart rewrites it; a transient I/O or Keystore error is not cached (next message retries).
- An older `baseRegistryVersion` is fine: ignore rules are keyed by institution code, so an app update never loses them.

**Modes** (`parseGuardConfig(baseBytes, userBytes?)` in Dart; natives mirror it):
| Base | User | Mode | Behaviour |
|---|---|---|---|
| valid | absent | `baseOnly` | fresh install; normal |
| valid | valid | `full` | |
| valid | undecryptable, malformed, unknown key, unknown `v`, rule without `inst` | `baseOnly` + diag `CONFIG_INVALID` | registry senders still kept (NFR-REL-01). Provisional default, PO Q1 (`kGuardUserConfigFailure`): an ignored card's message may then sit encrypted in the spool until the drain-time re-check drops it |
| unreadable or invalid (incl. old `v`) | any | `invalid` | every message dropped `config_invalid` (a build defect; the Android catch-up scan recovers SMS) |

Readers are strict: unknown keys, wrong types, empty strings, values over 256 chars, patterns over 600 chars, lists over 5,000 entries, invalid UTF-8 and a regex that does not compile are errors. Error messages carry a code and a JSON path only.

**Portable regex subset** (every Guard-bound pattern: sender regexes, drop, last-4, hints; checked by the registry lint through `exportGuardConfig`, `portableRegexProblems`). Kotlin/Android (`java.util.regex`, ICU-backed) and Swift (`NSRegularExpression`, ICU) differ from Dart (ECMAScript) on `\b \w \d \s`, case folding, inline flags and nested classes, so the lint rejects: any uppercase ASCII letter (bodies are lowercased; patterns compile case-sensitive everywhere), `\b \B \w \W \d \D \s \S \p \P \u \x`, backreferences, any other escape except of `^ $ \ . * + ? ( ) [ ] { } | /` (and `-` inside a class) and `\n` (a line feed in all three engines; only the global drop patterns see one, §1.2), any raw control character (write a line feed as `\n`), inline flags, lookaround, named groups, atomic groups, possessive quantifiers, POSIX classes (including a class whose first member is `:`, `[:` or `[^:`: ICU reads `[:` as the start of `[:name:]` and scans ahead for `:]`, so `[:=]...[ :]` does not compile on Android (FU-101 M-1); write `[=:]`), `[` inside a class, `&&`/`--` inside a class, a class opening with `]`, and in `last4` anything but exactly one capture group (group 1 = the 4 digits). The backtracking heuristic and the runtime probe (adversarial bodies now include runs of `*` and `x`) apply to all of them, sender regexes included. Write `[0-9]`, a space, `(?:^|[^a-z])otp(?:$|[^a-z])`. Compile: Dart `RegExp(p, unicode: true)` (case-sensitive), Kotlin `Regex(p)`, Swift `NSRegularExpression(pattern: p, options: [])`. Match semantics are **search, not full match**: Dart `hasMatch`/`firstMatch`, Kotlin `containsMatchIn`/`find` (never `matches()`), Swift `firstMatch(in:options:range:)` with `NSRange(location: 0, length: s.utf16.count)`. The registry loader compiles these lists the same way, so the pipeline's stage 0 and the Guards run the same regex.

### 1.2 Guard algorithm (identical in Kotlin, Swift and Dart; shared golden tests; T-035)

Reference implementation: `CaptureGuard.decide` in `packages/zaghlol_parsing/lib/guard/capture_guard.dart`. Golden cases: `packages/zaghlol_parsing/test/fixtures/guard/golden.json` (one file, read in place by all three test suites; never copied).

**Normalisation.** All matching runs on `foldKey(body)` and `foldKey(source)`: Arabic-Indic and extended digits → ASCII, `٫` → `.`, `٬` → `,`; invisible marks removed (U+200B–200F, U+202A–202E, U+2066–2069, U+061C, U+2060, U+00AD, U+FEFF); tatweel (U+0640) and harakat (U+064B–0652, U+0670) removed; `أ إ آ ٱ` → `ا`, `ى` → `ي`, `ة` → `ه`; whitespace runs (U+0020, U+0009–000D, U+0085, U+00A0, U+2009, U+202F, U+2028, U+2029) → one space, trimmed; **ASCII-only** lowercase. **Exception, global drop only:** the global drop patterns run on `foldKeyLines(body)`, which is `foldKey` except that a whitespace run containing a line break (U+000A–000D, U+0085, U+2028, U+2029; not tab) becomes one `\n` (U+000A) instead of one space; so `foldKeyLines(b)` with every `\n` replaced by a space equals `foldKey(b)` (natives compute one fold and derive the other, or fold twice; golden `fold[].lines`, default `out`). Natives port it code unit by code unit: no `Normalizer`/NFKC, no locale or Unicode `lowercase()` (Turkish `İ` and the Kelvin sign stay as they are), no confusable folding (a Greek-Epsilon "NBΕ" stays unknown). The `notification` source (a package name) is only trimmed. Lengths are counted on the **raw** text in UTF-16 code units (Swift `utf16.count`).

```
input: channel, source, body           output: KEEP(kind registry|user|generic, inst?, last4?) | DROP(reason)
0. config invalid                                       → DROP config_invalid
   channel ∉ {sms, notification, shortcut_message, apple_pay, share} → DROP unknown_channel
   body > 4,000 or source > 256 UTF-16 units            → DROP too_long   (before any regex)
   foldKey(body) empty                                  → DROP empty_body
1. key = trim(source) for notification, else foldKey(source)
   inst = notification: packages[key]
          sms, shortcut_message: exact senders[key], else first sender regex matching key
          apple_pay: the longest wallet name contained in key (a tie between two institutions → none)
          share: none
   inst found                                           → kind registry
   else (channel, key) ∈ userSenders                    → kind user
   else key ∈ alwaysCapture (not for notification), or channel ∈ {apple_pay, shortcut_message, share},
        or (a senderHint matches key AND a bodyHint matches the folded body) → kind generic
   else                                                 → DROP not_financial
2. inst and a drop.byInst[inst] pattern matches         → DROP otp_or_promo_inst      (on foldKey(body))
   a drop.global pattern matches foldKeyLines(body)     → DROP otp_or_promo_global
   inst = none                                          → KEEP(kind)
3. ignoreCh = sms for sms and shortcut_message (PO Q5, provisional), notification, apple_pay; none for share
   (inst, null, ignoreCh) ∈ ignore                      → DROP ignored_institution
4. last4 = group 1 of the first match of the first pattern in last4[inst], then last4["*"],
           whose group 1 is exactly 4 ASCII digits (with several cards the first hit decides)
   last4 and (inst, last4, ignoreCh) ∈ ignore           → DROP ignored_card   (never last4 alone: EC-59)
5. KEEP(registry, inst, last4)
```
- The old "guess the institution from the body" step for `shortcut_message`/`apple_pay` is removed (ambiguous and drift-prone): those channels resolve by sender or wallet name, else are generic.
- **Global drop = OTP only** (registry `shared.json`, FU-082; reshaped after the T-035 review, M-1/M-2 and code-review finding 1). Four patterns, all on `foldKeyLines` text (line breaks kept as `\n`, Normalisation above). *Sentence end* means `.` `!` `?` `;` `؟` `؛` and a **line break** (`\n`). The line break counts as a sentence end in the keyword-first gap, in the code-first prefix (a code at the start of a line may be code-first) and in the code-first connector (code and keyword must be on the same line), and in the bare-`code` verb gap; it does **not** end the **tight** form, so `OTP:` / `482913` and `Verification code` / `482913` on two lines still drop. After the code, a line break is treated like a space (the currency check still applies). *Code* means 4 digits, 6-8 digits, or 5 digits not starting with `19` (Egyptian hotlines are `19xxx`), or a split code `482-913`, `482 913`, `48 29 13`; it must not be followed by another digit, by `[.,][0-9]` (an amount) or by a space and a word that starts like a currency (` eg…`, ` us…`, ` ج.…`, ` جم…`, ` جن…`: `egp`, `usd`, `ج.م`, `جم`, `جنيه`). Pattern (2) uses any 4-8 digits instead. (1) **English keyword first**: a keyword with a non-letter (or the start) before it, then either *tight* (an optional ` is`/` هو`/` هي` and at most 3 of `space \n : = # -`, then the code) or *same sentence*: one non-letter, then up to 24 characters without a sentence end (line break included), `:` or `=`, optionally continued after a period inside a word or number (`1,500.00`, `ج.م`; at most two such periods, up to 24 characters each), then a **lead-in** right before the code: ` is`, ` هو`, ` هي`, `:` or `=` (plus up to two spaces or colons). Digits (amounts, card masks) may sit in the gap; the code itself is only accepted after the keyword or a lead-in, so a code preceded by `*`, `x`, `ending `, `رقم `, `بطاقه `, `egp ` or `call ` never counts. (2) **Code first**: the code at the start of the message or of a line, after a sentence end, `:`, `,` or `=` (plus an optional space), or after `use `, `enter `, `customer `, `استخدم `, `ادخل `, `عميلنا `; then only connecting words (` is`, ` as`, ` هو`, ` هي`, optionally ` your`/` the`, at most 3 of `space : = -`, no line break), then a keyword; this pattern also drops a message that **starts** with `code`/`كود`/`الكود` + code (separator as tight, line break allowed). (3) **Arabic keyword first**: as (1) without the letter check. (4) **Bare `code`/`كود`**: `code` (non-letter before) or `كود`, an optional ` is`/` هو`, the separator as tight (line break allowed), the code, then within 12 non-digit characters of the same sentence and line a confirm verb (`to confirm|complete|verify|activate|authorise|authorize|log in|login`, `لتاكيد`, `للتاكيد`, `لاتمام`, `لتفعيل`). Keywords (folded): `otp`, `0tp`, one time password/passcode/pin/code, verification/verify/security/secure/activation/login/confirmation/your/instapay/enter code (code first: not instapay/enter), passcode, password, pin; رمز/كود التحقق، التفعيل، الدخول، الامان؛ كلمه السر لمره واحده؛ كلمه السر/المرور (المؤقته)؛ الرقم السري (المؤقت)؛ كودك؛ رمزك. So a footer such as "never share your OTP" on a real purchase does not drop it, whether a card number, an amount or a `19xxx` hotline follows (golden `neg.*`), and an OTP keeps being dropped when an amount, merchant or card mask sits between keyword and code (golden `otp.*`; PO Q2 default: an OTP + transaction message is dropped). **Residuals** (pinned by golden `residual.*`): a 5-digit OTP starting with `19` is kept; a keyword-to-code distance over 24 characters without a period is kept (`residual.long_gap_kept`); a same-sentence, same-line reference after a keyword and a lead-in (`... by OTP, ref is 482913`) is dropped; a keyword split by a line break (`verification` / `code 482913`) is not recognised, nor is an obfuscated keyword (`O T P`); an OTP whose code sits on the line after a keyword with words between (`Your OTP for login` / `482913`) or after a lead-in at the end of a line (`Your OTP for login is` / `482913`) is kept. Security lines on their own line next to a `Ref:`/`Txn:` line keep the transaction (golden `neg.newline.*`, `neg.ar.newline.*`). Kept OTPs reach review as unrecognised or as a template match.
- A message with both a one-time code and a transaction is dropped (PO Q2, provisional; the completed-transaction SMS normally follows). Promotional messages are dropped only by an institution's own `drop` patterns; there is no global promo list (`خصم` = debit), so other promos reach review as unrecognised (PO Q6, provisional).
- **Rate limit** (`SenderRateLimiter`, FU-084b), applied after `decide` and only to KEEP: more than `rate.perSenderPerMin` (20, PO Q3, provisional) keeps from one `(channel, key)` within a sliding 60 s window (monotonic clock) → DROP `rate_limited` (diag count only). In memory, at most 64 keys (LRU), reset with the process. Rate-limited SMS are recovered by the Android catch-up scan; rate-limited notifications are lost.
- **Drain-time re-check.** T-046 runs the Dart Guard again on every drained entry (with the current config), so ignore rules created after a message was spooled, or a native Guard running on a broken user part, are applied before the database. The Dart Guard uses the bundled base part plus a user part built with `buildGuardUserConfig` from the DB rows read inside the batch's write transaction (never the native encrypted file); if that build fails (a row the builder refuses, e.g. a 2-3 digit `last4` rule, or a cap), the rows the builder refuses one by one are left out, the valid ignore rules and every always-capture / custom-template sender stay in the Dart user part, and every registry keep is also checked with `isIgnored` in the DB; past the caps, ignore rules move to the DB check alone and user senders are kept in Dart when the base Guard calls them `not_financial` (T-046 fix round, security F1: the user's keeps are never switched off). No rate limiter at drain. An invalid base at drain stops the batch before the transaction with nothing acked (a build defect must not delete captured messages).
- **Never logged:** no body, source, last-4 or config value in logs, errors or `toString` (Dart results print the reason/kind only).
- **Spoofing:** the Guard is a privacy filter, not an authenticity check (ADR-005 *Threats*).

### 1.3 Spool (encrypted, ack-after-commit)

| | Android | iOS |
|---|---|---|
| Key | Keystore AES-256-GCM key `zaghlol_spool_v1`, non-exportable, `setUserAuthenticationRequired(false)`, TEE-backed AndroidKeyStore, not StrongBox (bulk data; Lead decision 2026-11-10, T-060 review C1). Obtained only through `SpoolKey`. A key whose load fails as `UNUSABLE` (T-015 `KeyErrorClassifier`) on the first attempt and on the 100/300/900 ms retries is deleted and recreated under the `SpoolKey` lock; any other failure deletes nothing (T-039) | Keychain item `spool_key_v1` (32 random bytes) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, shared access group with the Share Extension |
| Location | `noBackupFilesDir/spool/` | App Group container `spool/`, `isExcludedFromBackup = true` |
| Entry file | `<ulid>.bin` = nonce(12) ‖ AES-GCM(record) ‖ tag, **AAD `zaghlol.spool.v1\|entry\|<ulid>`** (an entry can't be renamed or swapped). File names are ULIDs and so reveal receive times (FU-086 I-2): accepted, the directory is no-backup and entries are deleted on ack and by "Delete everything". The record is a versioned binary record (T-008, Lead Q8; replaces CBOR: same fields, no dependency): `u8 v=1 \| str8 channel \| str16 source \| u32 len + UTF-8 body \| i64 receivedAtMs \| i32 simSlot (-1 none) \| opt8 guardInst \| opt8 guardLast4 \| i64 rxElapsedNs \| i32 bootCount` (big-endian; `strN` = N-bit length + UTF-8; `opt8` = present flag + str8; the last two are diagnostic timing fields, kept in production by T-039, inside the ciphertext). Strict decode: unknown version, over-long field (body ≤ 4,000 chars), invalid UTF-8 or trailing bytes = malformed | same record and AAD (T-044) |
| Write | atomic: write `<ulid>.bin.tmp`, fsync, atomic rename, best-effort directory fsync. A `.tmp` is invisible to drain. Every `.tmp` is swept **under the store lock** at drain (no write is in flight then, single process), with no age rule, so a clock change can't keep or lose one (T-039; the T-008 spike used a 60 s age) | `Data.write(options: .atomic)` |
| Caps | 500 entries or 4 MiB on disk; beyond either the **new** message is refused (`refusedFull` in the capture status), never an old one evicted. **Generic budget** (T-035 security L-3, T-039): a Guard `generic` keep is refused (`refusedGeneric`) when the spool already holds 250 entries or 2 MiB, or after 10 generic writes in the last 60 s process-wide (in memory); `registry`/`user` keeps use the full caps. **Notification reserve** (T-039 security L-1, T-040): an `sms` keep is refused when the spool already holds 400 entries or 3.2 MiB (counted as `refusedFull`, sets `firstMissedSmsAtMs`), so the last 100 entries / ~0.8 MiB stay for notifications, which no catch-up can recover. Numbers provisional (T-039 PO Q1, T-040 PO Q1). On any refusal the caller still schedules a drain and notifies an attached engine; Dart then runs the inbox catch-up from `firstMissedSmsAtMs` (Sms build) and shows the degraded state (T-047/T-048) | same |
| Dedupe | none in the spool (at-least-once; a hash in a file name would be a body fingerprint). The DB's unique `raw_messages.body_hash` (BR-ING-02) is the only dedupe | same |
| Delete | only on `ackSpool(ids)` after the DB commit (or after Dart's drain-time Guard re-check dropped it), and only ids that the same engine's host returned from `drainSpool` (a stray ack can't delete an entry that engine never received); no age purge (unlike `share/`) | same |
| Read errors | delete only on proof: GCM tag failure, truncation or a malformed record is retried at 100/300/900 ms in that drain and the entry deleted (counted as `decryptDeleted`) only when every attempt proves it; any I/O or Keystore error in any attempt keeps it. **Lost key** (FU-086 I-3): an entry whose first attempt fails the tag and whose ULID time is before the key's Keystore creation date was written under an earlier key; it is deleted without the ladder and `keyInvalidatedAtMs` is set. The clock only chooses ladder or not; a deletion always needs a tag failure | same |
| Held entries (T-041, FU-105) | `holdSpool(ids)` (only ids this engine drained) renames `spool/<ulid>.bin` → `spool/held/<ulid>.bin` (same bytes and AAD) for entries T-046 could not store even alone (`IngestBatchResult.kept`). Held entries are not drained and not `pending`, but count towards the caps; at most 50 (beyond, the entry stays pending as a stuck entry). All are renamed back when the app's `longVersionCode` differs from `spool/held/.app_version`. Deleted only by an ack after release or by "Delete everything". `SpoolStatus.held` = count | same, when iOS needs it (T-044) |
| Drain time budget (T-041, FU-104 #2) | `drainSpool` stops after the first entry that is `Unavailable` because of the cipher/Keystore, and after 5 s (`elapsedRealtime`) in any case, returning what it has; `decryptDeleted` / `keyInvalidatedAtMs` are written once per drain | T-044 decides |
| Drain claim | process-wide: `drainSpool` hands entries to one engine at a time (the claim is released when that engine has acked all it drained, when it detaches, or 60 s after its last drain), so the UI and headless engines never process the same entry concurrently. While another engine holds the claim, `drainSpool` returns an empty list | n/a (one engine) |
| Capture status | `noBackupFilesDir/capture/status.bin`, AES-GCM with the spool key, AAD `zaghlol.capture.v1\|status`: alert counters only (`seq`, `refusedFull`, `refusedGeneric`, `rateLimited`, `missedNotifications`, `firstMissedSmsAtMs`, `lastRefusedAtMs`, `decryptDeleted`, `keyInvalidatedAtMs`). Written only on an alert, never for a normal keep or a non-financial drop; a burst of alerts is coalesced (as built, T-040: an alert that adds a fact the file does not hold yet — a counter going from zero, a first missed-SMS time, a key loss — is written at once; any other alert is written only when no write succeeded in the last 10 s (monotonic), else it stays in the in-memory delta, merged by the next `getSpoolStatus`/`clearSpoolAlerts` or the next alert after the window; a process kill loses at most the counts of one window, never a fact; T-039 security L-2). Read by `getSpoolStatus`, cleared by `clearSpoolAlerts(seq)` (compare-and-clear) (T-039) | T-044/T-061 decide |

**Reading the capture status (T-047 design note, 2026-11-11).** Only the UI engine calls `getSpoolStatus` and `clearSpoolAlerts` (the headless engine never does, so there is one reader and one clearer). The app **absorbs** the counters into its own encrypted settings (missed-notification count, earliest missed-SMS time as a catch-up request, unreadable flag, the absorbed `seq`) and then calls `clearSpoolAlerts(seq)`; the UI never shows raw counters. `keyInvalidatedAtMs` alone (status file exists after any earlier alert, T-039 code #5) triggers a Guard rewrite and a silent catch-up, not a user notice; the notice needs `decryptDeleted > 0`. After a rewrite the app re-reads `guardState` and expects `full`.

## 2. Android (`CaptureHostApi`, `CaptureEventsApi`)

```dart
@HostApi()
abstract class AndroidCaptureHostApi {
  CaptureCapabilities getCapabilities();          // sms granted? notif access? POST_NOTIFICATIONS? device locale for speech
  @async bool requestSmsPermission();             // READ_SMS + RECEIVE_SMS (only in the 'sms' flavor — ADR-004)
  void openNotificationAccessSettings();
  bool isIgnoringBatteryOptimizations();
  void requestIgnoreBatteryOptimizations();       // shown only if live capture is observed to be delayed
  void writeGuardConfig(Uint8List userConfigJson); // plaintext user part (§1.1); native validates, encrypts, writes; background task queue; CONFIG_INVALID | IO_ERROR
  InboxPage queryInbox(InboxQuery query);         // paged historical scan; native filters by sender list in SQL
  List<SpoolEntry> drainSpool(int max);           // returns decrypted entries (in memory only)
  void ackSpool(List<String> ids);                // only ids this engine drained (§1.3)
  void scheduleIngestionNow();                    // expedited WorkManager
  SpoolStatus getSpoolStatus();                   // T-039; background task queue
  void clearSpoolAlerts(int seq);                 // T-039; zeroes the alert counters if seq still matches
  void holdSpool(List<String> ids);               // T-041 (FU-105): entries T-046 could not store even alone; §1.3 held; background task queue
}

enum GuardConfigState { unknown, full, baseOnly, userUnreadable, baseInvalid }
class SpoolStatus { int pending; int seq; int refusedFull; int refusedGeneric; int rateLimited; int missedNotifications;
                    int? firstMissedSmsAtMs; int decryptDeleted; int? keyInvalidatedAtMs; GuardConfigState guardState;
                    int held; /* T-041 */ }

class InboxQuery { int sinceEpochMs; List<String> senderAddresses; String? afterCursor; int pageSize; /* ≤ 500 */ }
class InboxPage  { List<RawInboxMessage> items; String? nextCursor; int scannedTotal; /* rows read in this call, kept + Guard-dropped (T-042) */ }
class RawInboxMessage { String address; String body; int dateMs; int? simSlot; String providerId; }
class SpoolEntry { String id; String channel; String source; String body; int receivedAtMs; int? simSlot; }
class CaptureCapabilities { bool smsGranted; bool smsFlavor; bool notificationAccess; bool postNotifications; int sdkInt; }

@FlutterApi()
abstract class CaptureEventsApi { void onSpoolChanged(int pendingCount); void onPermissionChanged(CaptureCapabilities c); }
```

**Native components:**
- **`SmsReceiver`** (`SMS_RECEIVED`, priority default; every `*Sms` variant, `src/sms`, never `*NoSms`; T-040 design note):
  1. On the main thread: stamps the receive time, reads the PDUs and the SIM slot, calls `goAsync()` and hands off to the SMS intake thread with a 5 s budget (`finish()` exactly once).
  2. Assembles the PDUs of the broadcast (EC-09): grouped by address, bodies joined **in PDU array order** (one broadcast normally carries one reassembled message), with the accessors that reproduce the inbox row, so live and catch-up `body_hash` match.
  3. Runs the Guard through the typed Android entry point (`AndroidGuardChannel`: `sms` or `notification` only, FU-101 L-1) and spools a keep (`registry`/`user` → priority, `generic` → generic class); a rate-limited keep is recorded in the capture status; any other drop writes nothing.
  4. If anything was written or refused, enqueues the ingestion work once per broadcast through the injected `IngestScheduler` (returns after WorkManager persisted the request; unique `zaghlol.ingest`, expedited, `OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST`; T-041 provides it outside devSms).
  5. Calls `CaptureEventsApi.onSpoolChanged` if an engine is attached.
  - **As built (T-040):** glue `src/sms/kotlin/app/zaghlol/platform/capture/SmsReceiver.kt` (manifest `src/sms`; `src/noSms` removes it with `tools:node="remove"`); everything testable in `src/main` `platform/capture`: `SmsAssembler`, `SmsIntake` / `SmsCapture` (process-wide dispatcher on its own daemon thread `zaghlol-sms-intake`, `installForTest` for the instrumented test), `CaptureIntake` (channel-agnostic, for T-043), `BoundedDispatch`, `GuardAdapters`, `SimSlot` (moved from the inbox reader, FU-109 m-3; slot extra, else the legacy `slot` extra, else the subscription id through `SubscriptionManager.getSlotIndex` on API 29+, never `READ_PHONE_STATE`). The receiver gets the runtime on the intake thread (the runtime's creation does file I/O). Steps 4–5 are `CaptureRuntime.afterSpoolWrite()` (T-041), called once per broadcast when anything was written or refused; its failure is swallowed (the entry stays). The receive stamp's boot count is read on the intake thread. The UI engine's host gets `GuardAdapters.writerFor` / `stateOf` (`CONFIG_INVALID` / `IO_ERROR` codes only; mode × user state table in `GuardAdapters.stateOf`); the headless host gets neither (`NOT_AVAILABLE` / `unknown`). Live enqueue coalescing (FU-108 security L-1, code m-2): off the main thread, `WorkManagerIngestScheduler.enqueue` skips the enqueue while a live run is `ENQUEUED` or `BLOCKED` (`LiveEnqueueGate`; the write always precedes the check, so that run drains it; unknown state → enqueue), so a burst leaves at most one waiting live run behind a running one. **devSms:** the spike receiver and `SpikeGuard` are gone; the production Guard decides with `src/devSms/assets/guard/spike_guard_base.json` (exported from the spike registry, rate raised to 600/min for the latency burst; a Dart test pins it), read by `BaseConfigSource.readForBuild` only when the bundled base (T-036) is absent; no other APK contains it (placement check). Other `*Sms` builds have no base until T-036: every SMS is dropped `config_invalid` and nothing is written.
- **`BankNotificationListener`** (main source set, every flavour; T-043 design note):
  - `onNotificationPosted` (main thread) skips its own package, group summaries, ongoing and foreground-service notifications without reading extras, and hands the rest to its own intake thread (not the SMS thread).
  - Admits only a `packageName` in the base `packages` or a user `notification` sender (never the generic hint path) **before** any extras are read.
  - Reads `EXTRA_TITLE` and `EXTRA_BIG_TEXT`, else `EXTRA_TEXT`, else `EXTRA_TEXT_LINES`; body = title + `\n` + content (either alone if the other is blank). Notification templates and fixtures use this shape.
  - Skips an identical `(package, body)` seen in the last 15 min (in memory only); an update with new text is a new message.
  - Then runs Guard → spool → enqueue as above; refused, rate-limited or overflowed notifications count as `missedNotifications` (not recoverable).
  - **As built (T-043):** `platform/capture/BankNotificationListener.kt` (glue), `NotificationExtractor` (pure; `NotificationFields` / `PostedNotification` seams), `RecentNotifications` (SHA-256(pkg ‖ 0x00 ‖ body) first 16 bytes, LRU 128, TTL 15 min, recorded only after a `Written` result), `NotificationIntake` + `NotificationDispatcher` (daemon thread `zaghlol-notif-intake`, queue 64; an overflowing item is dropped and counted on the main thread, reported by the intake thread through `CaptureStatusStore.recordMissed` before its next item), `NotificationCapture` (process-wide entry, `installForTest`), `GuardRuntime.admitsNotificationPackage` (registry package or user `notification` sender via `CaptureGuard.senderKind`; the generic hint path never admits). `CaptureRuntime.notifications` composes it with the same `CaptureIntake`, Guard and spool as SMS. Manifest: `<service>` in `src/main` with `default_filter_types=conversations|alerting|silent` and `disabled_filter_types=ongoing` (the reference documents pipe-separated keywords for both; a single value avoids the separator question). No notification replay on reconnect, no `requestRebind`.
- **`IngestionWorker`:**
  1. Starts a `FlutterEngine` with entrypoint `ingestionMain`, or reuses the cached engine if the app is alive.
  2. Waits for Dart to finish draining (`MethodChannel` completion), 60 s maximum.
  3. Destroys the engine.
  4. If the spool is still non-empty, re-enqueues with back-off.
  - **As built in the T-008 spike** (`src/devSms` only; T-041 productionises): unique work `zaghlol.ingest`, `APPEND_OR_REPLACE`, expedited with `RUN_AS_NON_EXPEDITED_WORK_REQUEST`, no constraints, exponential back-off from 10 s, never `setForeground` (Android 8–11 fall back to a foreground service with a low-importance localized notification). If the UI engine is attached it never starts a second engine: it calls `CaptureEventsApi.onSpoolChanged` and waits for the spool to empty. Otherwise it uses a process-wide `FlutterEngineGroup` engine (`ingestionMain` in `lib/main.dart`, body in `lib/ingestion/ingestion_main.dart`) with `automaticallyRegisterPlugins = false` and an explicit allowlist: `JniPlugin` + `JniFlutterPlugin` (path_provider_android 2.3 is JNI-based, so both engines resolve the same DB directory), `SecretStoreRegistration` (§5), the spool host (other `AndroidCaptureHostApi` methods answer `NOT_AVAILABLE` until their owner tasks), and the spike-only `zaghlol/spike_metrics` channel. Worker result: success when the spool is empty or the DB does not exist yet (the UI engine creates it and drains at start); retry on `DB_MIGRATION_PENDING`, `DB_DEFERRED`, a transient failure or the 60 s budget. Shutdown (linger end, memory trim, UI engine attach): a pending drain is answered first (bounded), then the spike channel's `close` command makes Dart wait for any running cycle and await the database close, then the engine is destroyed (bounded; T-008 review F1). T-041 keeps this order: the headless engine is never destroyed mid-transaction or with an open connection. **Stuck entries (T-046):** the Dart cycle remembers the delivery ids it has seen in this cycle; when a drain returns only seen ids (an entry whose batch failed every time), it ends with `OK` and a `stuck` count, does not start a batch with under 5 s of its 50 s budget left, and the worker does not re-enqueue for stuck-only entries (they stay in the spool, never deleted, and are retried on the next enqueue or app open). As built: a **transient** batch failure (`DB_WRITE_FAILED`, `DB_READ_FAILED`: busy, I/O) ends the cycle with `RETRY` at once; after any other non-transient failure the use case retries the batch one message per transaction and stores a message that still fails alone for review (raw `review` + `unrecognized`, `reason: ingestFailed`, code only; after the Guard re-check, stage-0 drop and dedupe 1), so it is acked like the rest (T-046 fix round, CR-1/F2: one poison message never blocks the spool). Only `CONFIG_INVALID` (and an oversized batch) leaves a whole batch unacked: the cycle drains again, those entries come back as stuck and the cycle ends `OK` with the code. A message that can't be stored even alone is left out of `ackable` (`IngestBatchResult.kept`, diag `ING_KEPT`), stays in the spool and ends the cycle as the only stuck entry with `INGEST_MSG_UNSTORABLE`; the rest of its batch is acked. The cycle result map gains `stuck` (int); natives ignore unknown keys.
  - **Production (T-041 design note, `docs/04-tasks/tasks/T-041.md`):** `src/main` package `app.zaghlol.platform.ingest`, in **every** flavour (notifications need it in `*NoSms`); WorkManager 2.12.0 is a dependency of all variants. Two unique works: **live** `zaghlol.ingest` (expedited, `RUN_AS_NON_EXPEDITED_WORK_REQUEST`, `APPEND_OR_REPLACE`, no constraints) **never returns `retry`**, so a new message never queues behind a head in back-off (FU-081 F5); a failed run enqueues **retry** `zaghlol.ingest.retry` (not expedited, `KEEP`, initial delay `min(10 s × 2^(n−1), 15 min)`, at most 8 attempts) and a run that leaves the spool empty cancels it. `NO_DATABASE`, `DEFERRED` and stuck-only runs end without retry (the UI engine drains at start). Never `setForeground`; no foreground-service type is declared (API 26–30 fall back to WorkManager's foreground service with the capture notification, secret on the lock screen on both notification and channel). Headless engine linger 10 s (provisional). The `close` command now also stops the cycle after the current batch, and is sent at once on a shutdown request, so an attaching UI engine waits for one batch at most; destroy still follows the DB close. The spike's `zaghlol/spike_metrics` command protocol is replaced by a Pigeon contract `app/pigeons/ingestion_api.dart`:
    ```dart
    enum IngestOutcome { ok, noDatabase, deferred, retry }
    class IngestCycleReport { IngestOutcome outcome; int drained; int inserted; int stuck; int held; String? code; }
    @FlutterApi() abstract class HeadlessIngestionApi { @async IngestCycleReport drain(); @async void close(); }
    @HostApi()    abstract class HeadlessIngestionHostApi { void ready(); }
    ```
    The headless engine's `AndroidCaptureHost` has no inbox reader and no Guard writer (`NOT_AVAILABLE`). `CaptureEventsApi.onSpoolChanged` is coalesced (one pending post) and sent after a spool write, by the worker while a UI engine is attached, and when a headless engine releases the claim with entries pending.
    **As built (T-041):** `IngestionWorker` + `WorkManagerIngestScheduler` (`IngestionWorker.kt`), the outcome table in `IngestRun` / `DrainLoop`, `HeadlessEngine` + `ShutdownSequence`, `FlutterHeadlessStarter` (allowlist), `CaptureRuntime` (`platform/capture`, the composition point: `afterSpoolWrite()`, `attachUi`/`detachUi`, held release at creation). Differences from the note: a **retry run** enqueues its successor with `APPEND_OR_REPLACE` (with `KEEP` the running retry work counts as unfinished and the successor would be dropped); a live run enqueues retry 1 with `KEEP` (a waiting retry keeps its back-off); a retry run that empties the spool does not cancel itself. Dart: `IngestionRunner` (`lib/ingestion/ingestion_runner.dart`), `ingestionMain` answers `HeadlessIngestionApi` and calls `ready()` after installing it; `close` sets a stop flag checked before each `drainSpool`, so a `close` that arrives before the first batch starts none (the entries stay for the UI engine). `IngestionCycle` calls `holdSpool(kept)` after the ack of the rest; a failed hold is ignored and the entries end the cycle as stuck (the pre-T-041 path). A held entry is reported in `IngestCycleReport.held` and is no longer pending; `INGEST_MSG_UNSTORABLE` stays the cycle's code. The registry and the devSms marks are chosen by `kIsSpikeBuild` (`appFlavor == 'devSms'`, a compile-time constant); other builds have no bundled registry until T-036 (`INGEST_SETUP_FAILED`). **As built (T-047):** `startForegroundIngestion` is gone. `main.dart` runs `CaptureLifecycle` over a `ProviderScope`; `captureCoordinatorProvider` (`features/capture/application/capture_providers.dart`) builds the UI engine's `CaptureCoordinator` once `appDatabaseProvider` has opened (the startup gate), on Android only, and only when a registry exists (no registry: no coordinator, no retry cycle). The coordinator is the `CaptureEventsApi` handler and owns the `SpoolOrchestrator` (drain at start, on resume, on `onSpoolChanged` after a 250 ms coalesce, after a rule change; re-poll 5/15/45 s while `pending > 0` after an empty drain; retry 5 s/30 s/2 min), the `GuardConfigWriter`, absorb-then-clear and the share-intake and purge hooks. The UI runner reuses the app's own database provider (one connection in the UI engine). The headless engine's files do not reference the capture module, `getSpoolStatus`, `clearSpoolAlerts` or `writeGuardConfig` (a test greps them).
  - **Headless DB rule (T-008, Lead Q6):** the headless engine opens with `allowMigration` and `allowCreateOrWipe` false. It never creates the database or its key, rotates or deletes a key, wipes an orphan, deletes migration leftovers or lets drift run `onCreate`; each of those is `DB_DEFERRED` (gate `deferToForeground`) with nothing touched. A missing `zaghlol.db` is not opened at all.
- **`InboxReader`:** `ContentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, …, "address IN (?, …) AND date > ?", …)`, paged by `_id`. Only allowlisted senders are ever read into memory.
  - **Implemented in T-042** (`capture/inbox/InboxReader.kt`; design note in `docs/04-tasks/tasks/T-042.md`): UI engine only: `AndroidCaptureHost(inbox = InboxReaders.forUiEngine(context))` for the UI engine, none for the headless one, which answers `NOT_AVAILABLE` (the line goes into T-041's `CaptureRuntime.newHost`; until then no host has a reader and `queryInbox` answers `NOT_AVAILABLE`); `*NoSms` → `NOT_AVAILABLE`; not granted → `PERMISSION_DENIED`. Each requested address must be allowlisted by the native Guard (`registry` exact/regex, `user`, `alwaysCapture`; never sender hints), then bound as its ASCII variants `{a, lower, upper}`. Selection `address IN (?,…) AND date > ? AND _id > ?`, sort `_id ASC`, projection `_id, address, body, date, sub_id`, at most 900 bound arguments per query (chunks beyond), no `LIKE`/functions/`COLLATE`/`LIMIT` in SQL. `pageSize` (1..500) counts rows read; every row is re-checked against the bound set and run through the native Guard **without** the rate limiter; drops are not returned. Opaque cursor `v1.<chunk>.<lastId>.<crc32 of the bound senders + since>`; a mismatch is `INVALID_ARGUMENT`. `since` is raised to `now − 25 months` (A-11). No spool: the page goes straight to Dart (T-048), which ingests it with origin `inbox`. The per-row re-check covers the whole selection (address in the bound set and still allowlisted, `date > since`, `_id` past the cursor) and runs before the body is read; a provider that ignores `_id > ?` so that a full page makes no progress gets `IO_ERROR` (never an endless cursor), as does a null cursor from the provider. A `since` after now returns an empty last page. A cursor stays valid only while the allowlisted subset of the request is unchanged (a Guard config change between pages gives `INVALID_ARGUMENT`; T-048 restarts the scan). **As built (T-048):** `InboxScanService` / `InboxScanner` in `features/capture/application` (task file T-048, Implementation notes): pages of 100 then 500, 100 messages per ingest transaction, restart on `INVALID_ARGUMENT` (3 times at most), registry exact senders and the user's SMS senders, user-added phone numbers only with the opt-in `capture.scan_personal_senders` and only 3 months back (FU-109 M-1).
- **Manifest:**
  - `android:allowBackup="false"`;
  - `dataExtractionRules` exclude everything (FR-SEC-05);
  - `FLAG_SECURE` plus `setRecentsScreenshotEnabled(false)` when app lock is on (FR-SEC-02);
  - share intent filters for `text/plain`, `image/*`, `application/pdf`, `text/csv`;
  - `SmsReceiver` exported with `android:permission="android.permission.BROADCAST_SMS"` (Sms variants only); `BankNotificationListener` exported with `android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"`, ongoing notifications filtered out on API 31+ by `default_filter_types` / `disabled_filter_types` meta-data.

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
  void writeGuardConfig(Uint8List userConfigJson); // plaintext user part (§1.1); native validates, encrypts, writes
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
  - Text does **not** go through the Capture Guard (same as Android, §2.1): it is user-initiated and always shown for confirmation (FR-ING-A-04). It is stored encrypted like images and PDFs and processed in the app.
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
- **Errors (T-179):** code-only `SEAT_KEY_UNAVAILABLE` (no message, no details) when the Keychain state can't be read or written (before the first unlock, any status other than success / not found). It never deletes anything; Dart treats it as "no keys".
- **As built (T-179).** Contract file `app/pigeons/seat_key.dart` (Dart + Swift outputs only; no Kotlin is generated). Native: `app/ios/Runner/Platform/Keys/SeatKeyStore.swift` / `SeatKeyHost.swift`; items use account `own` (this install) and `earlier.<10-digit sequence>` (higher = newer); `rotateForNewInstall()` is one `SecItemUpdate` rename, then a FIFO trim to 4 earlier keys; other accounts under the service are ignored. A key is dropped only after its item was read and loading, signing or verifying its own signature failed on all three attempts (0/100/300 ms); an unusable own key is replaced in the same call, so element 0 is always this install's key. Dart: `SeatKeyService` (`app/lib/features/gold/application/seat_keys.dart`) keeps `secure_state` `seat_key_install` (the install ID the own key belongs to; a different ID rotates first, so a reinstall's former key is element 1) and the R5-6 flag `seat_key_unusable` (holds the install ID it was set for; deleted on `InstallReregistered`). Callers use `prove(op, challenge)`, which builds the T-183 message with this install's ID. Residual: calls are serialized within one isolate only.
- **No identifiers leave native code** other than the public keys and signatures Dart puts into `seatKeys`. Neither is ever written to the diag log (D-62).
- **Device tests (T-179 for the seat keys, T-180 for the clocks; C4):** the Keychain item **and** the Secure Enclave key it wraps survive deleting the app and reinstalling it, on the oldest and newest supported iOS versions (R-19, SRS v1.7: a sign/verify round trip after reinstall proves the key is still usable, not only that the item exists); it survives "Delete everything"; a sign/verify round trip against `seat-proof-v1.json`'s message format; `CLOCK_MONOTONIC_RAW` advances across sleep; `BOOT_COUNT` increments after a reboot.

## 5. Other hosts

| API | Methods | Notes |
|---|---|---|
| `ICloudBackupHostApi` (iOS) | `isAvailable()`, `upload(path, name)`, `list() → [BackupMeta]`, `download(name) → path`, `delete(name)` | Ubiquity container `iCloud.app.zaghlol`, `Documents/Backups/`. The file is already encrypted (ADR-011). |
| `TextNormalizationHostApi` (both platforms; T-148) | `nfc(String) → String` | Unicode NFC for the backup passphrase (Android `java.text.Normalizer`, iOS `precomposedStringWithCanonicalMapping`), so both platforms derive the same key. Stateless; the argument is never logged or stored. Registered on the UI engine only (`MainActivity`, `AppDelegate`). Dart calls it only when the folded passphrase has a code point ≥ U+0300 (anything below is already NFC). Shared NFC rows: `app/test/fixtures/backup/zglb-v1-vectors.json`, mirrored in the Kotlin and Swift unit tests (a Dart test checks they match). |
| `DeviceSecurityHostApi` | `isDeviceRooted()`, `setSecureWindow(bool)`, `isDeviceSecure()` (passcode set), `authenticate(reason) → NativeAuthOutcome` (`@async`) | FR-SEC-01/02/07 (T-103). The first three are synchronous and return a boolean or nothing; no error codes are defined. `isDeviceRooted()` is a best-effort heuristic (Android: `su`/Magisk paths and `test-keys` build tags; iOS: jailbreak paths and a sandbox-write probe, never on the simulator) that only drives a warning, never a block. `setSecureWindow(true)`: Android `FLAG_SECURE` and `setRecentsScreenshotEnabled(false)` on API 33+ (last request kept per process, re-applied to a re-created activity), iOS a cover over the scene's windows while it is not active; `false` undoes it. `isDeviceSecure()`: a screen lock (PIN, pattern, password, passcode) is set; it reports false when it can't tell. Registered on the UI engine only (`MainActivity`, `AppDelegate`). `authenticate(reason)` (contract change 2026-11-13: replaces the `local_auth` plugin, whose iOS plugin hung the simulator at launch) returns `success`, `failed`, `cancelled`, `notAvailable` (no screen lock or no biometric UI) or `lockedOut`; it never throws for a failed or dismissed prompt, and `reason` is the only text passed in. iOS: `LAContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)` (biometric with passcode fallback). Android: `androidx.biometric` `BiometricPrompt` with `BIOMETRIC_STRONG or DEVICE_CREDENTIAL` on API 30+ and `BIOMETRIC_WEAK or DEVICE_CREDENTIAL` on API 26-29 (AndroidX rule: STRONG with a credential is unsupported below 30); no negative button (not allowed with a credential); needs the `FragmentActivity` and an AppCompat theme. |
| `WidgetBridgeHostApi` | `updateSnapshot(WidgetSnapshot)` | Snapshot = {safeToSpendText or "•••", daysToPayday, currency, updatedAt}. Stored in the widget's own shared storage. **Only already-formatted, redaction-aware strings** are stored there (FR-WID-01). |
| Speech | via `speech_to_text` plugin (no custom channel) | `onDevice: true` preferred; online only with consent (ADR-010). |
| `SecretStoreHostApi` (both platforms; T-015, ADR-002 Amendment 2026-11-10) | `acquireBootstrapLease(timeoutMs) → lease`, `releaseBootstrapLease(lease)`, `renewBootstrapLease(lease) → bool` (T-016), `read(slot) → SecretReadMsg{status, value?, attempts}`, `createIfAbsent(lease, slot, candidate) → stored`, `delete(lease, slot)`; all `@async` | Slots: `dbKey`; `backupKey` (T-148: 32-byte `K_bk`; Android Keystore key `zaghlol_bk_kek_v1`, blob `noBackupFilesDir/keys/backup_key_v1.bin`; iOS account `backup_key_v1`; same status rules, written under the lease). Status: `found`, `notFound` (positive evidence of absence), `unusable` (positive evidence the stored key can never be read: Keystore alias missing, AEAD tag failure, malformed blob, `KeyPermanentlyInvalidatedException`, API 33+ `ERROR_KEY_DOES_NOT_EXIST`/`ERROR_KEY_CORRUPTED`; iOS: wrong item length), `unavailable` (every other error, including an Android blob whose presence can't be determined; never a reason to wipe). Every non-`found` read is retried at 100/300/900 ms: one `found` wins; `notFound`/`unusable` are returned only when every attempt agrees, otherwise `unavailable` (T-015 S-1; an Android `notFound` rests on the file system proving absence and needs no confirmation). Android: Keystore AES-256-GCM key `zaghlol_db_kek_v1` wraps the key in `noBackupFilesDir/keys/db_key_v1.bin`. iOS: generic password `app.zaghlol.keys`/`db_key_v1`, `AfterFirstUnlockThisDeviceOnly`, not synchronizable, `kSecAttrAccessGroup` pinned to Runner's own `<AppIdentifierPrefix><bundle id>` group. The lease is process-wide (all engines) and expires after 30 s; writes need the current lease. `renewBootstrapLease` (T-016, S-2): if the lease is current and unexpired, its expiry becomes now + 30 s and it returns true, else false; it never takes a lease. Dart calls it through `BootstrapLease.ensureValid()` before every create or wipe step (false → `DB_LEASE_LAPSED`, stop). Same-lease renewals are unbounded, but a dead engine stops renewing and its lease still lapses after 30 s. `createIfAbsent` returns an existing usable value instead of overwriting, and refuses (`KEY_STORE_FAILED`) over an unusable or unknown one. **Register in every engine that opens the database** (UI engine: `MainActivity` / `AppDelegate`; headless engine: T-008, done in the spike's `HeadlessEngine`). No logging in the keys code; errors carry the code only. |

## 6. Error codes (native → Dart)

`PERMISSION_DENIED`, `NOT_AVAILABLE`, `SPOOL_DECRYPT_FAILED` (share intake `readShare` only: the share was proven not authentic and deleted; the Android spool never throws it: an entry proven bad after the 100/300/900 ms ladder is deleted and counted in `SpoolStatus.decryptDeleted`, §1.3), `KEY_INVALIDATED` (Keystore key lost after a security change. **Android spool (T-039): reported, not thrown**: `SpoolStatus.keyInvalidatedAtMs`, while `drainSpool` keeps returning the readable entries. Dart then re-writes the Guard config, runs the catch-up and shows "re-scan" in Settings; entries written under the old key are lost), `CONFIG_INVALID`, `ICLOUD_UNAVAILABLE`, `OCR_FAILED`, `IO_ERROR`, `ATTEST_TRANSIENT`, `ATTEST_PLAY_SERVICES_OUTDATED`, `ATTEST_UNAVAILABLE`, `SEAT_KEY_UNAVAILABLE` (no Secure Enclave or Keychain error: send no `seatKeys`), `KEY_STORE_FAILED` (`SecretStoreHostApi` could not write, verify or delete a secret, or refused to overwrite an unusable one: no database may be created, never a wipe), `LEASE_TIMEOUT` (the bootstrap lease was not free in time, or a write used a lease that is no longer current: retry), `INVALID_ARGUMENT` (T-042 `queryInbox`: more than 1,000 sender addresses, or a cursor that is malformed or belongs to another query; code only). Secret-store errors carry the code only (`message` and `details` are null), `NORMALIZATION_FAILED` (`TextNormalizationHostApi` (T-148): code only, never the argument; Dart turns it into the backup error `io` and never falls back to an un-normalized passphrase).
