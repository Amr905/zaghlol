# Review — batch 24a (T-120, T-161, FU-backend-2)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security) |
| Date | 2026-11-15 |
| Commit / diff | `origin/batch/2026-11-15-24` @ fc069cca; per task `git diff origin/main...origin/task/<branch>` |
| Verdicts | T-120 CHANGES_REQUESTED · T-161 CHANGES_REQUESTED · FU-backend-2 APPROVED |

Tests run on the merged tree: `flutter test --exclude-tags benchmark,golden test/features/voice test/privacy test/features/capture test/features/transactions test/core/ui` (592 passed); `dart test test/ocr` in `packages/zaghlol_parsing` (51 passed). Backend Docker tests (trigger, stores) were not run here; GitHub runs them. Swift and Kotlin were read, not built.

---

## T-120 — Voice logger S-31 (task/T-120-voice) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Nothing saved without confirmation | PASS | `voice_logger_test`: "parsed list ... saves NOTHING before Save", "closing without saving saves and counts nothing" |
| 16th Free log blocked with upsell | PASS | "Free, 15 used: limit screen before listening", "the limit is rechecked at Save (16th is blocked)", "Gold: unlimited". Gold comes from `entitlementStateProvider` (the backend-signed entitlement) |
| On-device first, online only with consent (D-42, R-05 "detect support") | FAIL on Android | F1 |
| Money per currency, nothing converted | PARTIAL | No conversion, but F2 sends the item to an account the user didn't see |
| DoD: no hard-coded strings, RTL, no `double` money, no logging | PASS | Level is a `double` but it isn't money; no logging in the diff; privacy suite `voice_permission_test` (plugin imported only in the adapter, no `dart:io`/HTTP) |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | **major (privacy)** | `app/lib/features/voice/application/voice_controller.dart:125`, `app/lib/features/voice/data/speech_to_text_port.dart:41` | `onDevice: true` does not guarantee that recognition stays on the device on Android. In speech_to_text 7.5.0 (`SpeechToTextPlugin.kt` `createRecognizer`), when the API level is below 31 or `SpeechRecognizer.isOnDeviceRecognitionAvailable()` is false, the plugin quietly falls back to `createSpeechRecognizer()`, the default recognizer that can use the network. The only remaining guard is `EXTRA_PREFER_OFFLINE`, which is a hint. It can also be left out, because `setupRecognizerIntent` caches the intent on a key that doesn't include `onDevice` (for example, a device whose default locale is ar-EG gets the intent `createRecognizer` built with `onDevice=false`). On those phones audio can reach Google's servers before the consent sheet appears, which breaks D-42. The fact that `error_network` / `error_server_disconnected` from the "on-device" attempt are mapped to `unavailable` shows that a network attempt is expected there. Device check #2 in the task file assumes this attempt fails; the code does not ensure it. | Before the first `listen`, find out whether on-device recognition is really available. On Android this means API ≥ 31 and `SpeechRecognizer.isOnDeviceRecognitionAvailable(context)` (and `checkRecognitionSupport` for the locale on API ≥ 33), through a small host method behind `SpeechPort` (e.g. `Future<bool> onDeviceSupported(localeId)`). If support is not confirmed, go straight to `needConsent` without calling `start`. iOS is fine (`requiresOnDeviceRecognition = true`). |
| F2 | **major (money)** | `app/lib/features/voice/application/voice_controller.dart:301-313`, `app/lib/features/voice/presentation/voice_logger_screen.dart:558-566` | `accountFor` quietly stores an item on "the first live account in that currency" when the spoken currency differs from the account chip (e.g. chip "Cash (EGP)", the user says "20 dollars", and the item is saved to whichever USD account sorts first). The row and the chip still show the chosen account, so the user confirms a write to an account they never saw. This changes that account's balance and totals. | Show the account the item will actually be stored on in each row where it differs from the chip, with a tap to change it (or disable Save until the user picks one). Test: chip EGP plus a USD item shows the USD account on the row before Save, and the saved leg uses the account that was shown. |
| F3 | minor | `voice_controller.dart:213`, `:361` | A partial save (some `editor.add` calls succeed, then one throws) followed by Try again or closing leaves rows stored and no voice log counted, so the quota can be bypassed by one log at a time. `_savedKeys.clear()` on Try again also forgets which rows were already written. | Count the log once the first row is written (or count in the same transaction). Follow-up. |
| F4 | minor | `voice_providers.dart` `voiceOpenSettingsProvider` | "Open settings" on the mic-denied explainer reuses the notification-settings opener; on Android it lands on the notification page, not app details (the builder noted this). | Follow-up: an app-details opener. |
| F5 | minor | `app/ios/Runner/InfoPlist.xcstrings` | The Arabic permission strings are the builder's draft and are not in the copy deck. | Copy review (T-058 owner). |
| F6 | nit | `voice_logger_screen.dart` parsed title | `' 👌'` is a literal appended to a localized title. | Move it into the ARB string when ARB edits reopen. |

### Security part
- No audio file and no transcript is persisted or logged. `debugLogging: false`. The privacy suite pins the plugin to one adapter and bans `dart:io`/HTTP in the feature (with a negative proof).
- `RECORD_AUDIO` is requested at runtime only. The `<queries>` entry for `RecognitionService` is justified, and the manifest permission test was updated with a reason.
- F1 is the one gap, and it is a privacy major.

---

## T-161 — Receipt OCR + S-32 + FU-211 shared items (task/T-161-ocr) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| InstaPay receipt yields amount/IPA/reference/date | PASS | 32 template fixtures plus 9 receipt fixtures; `ocr_parse_test` (51 passing) |
| Never auto-saves | PASS | `scan_confirm_screen_test` "never auto-saved"; S-32 reuses the S-13 editor with Save |
| Duplicate check (same account, direction, currency, amount, ±1 day), never auto-merges | FAIL in practice | `duplicate_finder.dart` is correct, but it receives the wrong account (F7) |
| `sealImage` encrypts and deletes the plain file on every path | PASS | Swift reads once, then `removeItem` before any further step; Dart `finally` in `scanImagePickerProvider` deletes it again (this covers the out-of-root refusal and Android's `UnavailableOcrEngine`); AAD/layout match `ShareStore.bodyAad` |
| Images / OCR text never logged | PASS | No logging in the Dart, Swift or parsing diff; failures are codes only |
| `ShareDescriptor.ocrPath` contract | PASS | Pigeon, Swift, Kotlin and Dart regenerated; `platform-channels.md` updated; iOS image only |
| image_picker adds no permission or analytics | PASS (Android) / see F9 (iOS) | `image_picker_android` manifest declares no permission; `requestFullMetadata: false` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F7 | **major (money / data)** | `app/lib/features/transactions/presentation/edit/transaction_edit_screen.dart:155-161` | `initState` sets `_accountId = pre.accountId` and then sets `_accountId = e?.accountId` unconditionally, so for a new item the prefilled account becomes `null` and `build` falls back to Cash. The account matched by last-4 is lost, and the duplicate check runs against Cash, so a card or InstaPay receipt whose transaction was already captured from the bank SMS on the card account is **never** flagged. The user saves a second copy and spending is counted twice. The widget test misses this because the last-4 account (`acc1`) is also the default Cash account (`detail_edit_harness.dart:93`). | Use `_accountId = e?.accountId ?? pre?.accountId` (or move the prefill block after it). Add a test where the last-4 account is not the default: the saved leg uses that account, and an existing SMS transaction on it triggers the duplicate dialog. |
| F8 | minor | `app/lib/features/capture/application/scan_providers.dart:41` | On Android (no OCR host) the Scan tile opens the photo picker and only then says "not available". | Check `ScanService.isAvailable()` before opening the picker. Follow-up. |
| F9 | minor | `app/ios/Runner/Info.plist` | image_picker_ios links `PHPhotoLibrary` authorization APIs. App Store processing can reject with ITMS-90683 when `NSPhotoLibraryUsageDescription` is missing, even though PHPicker never asks for it. | Check on the first TestFlight upload, or add the key with copy. Follow-up. |
| F10 | minor | `shared_items_lifecycle.dart:119-130` | Shared PDF/CSV is shown as "not available" and then discarded (the source file stays in the other app). If `_nav.currentContext` is null at `_handle` time, the share is discarded without being shown. | Acceptable until T-158. Keep the share when there is no context. Follow-up. |
| F11 | nit | `OcrHost.swift` `sealImageNow` | The root check uses `standardizedFileURL`, which doesn't resolve symlinks. This is harmless today, because the roots and the picker path come from the same `NSTemporaryDirectory`. | Optional `resolvingSymlinksInPath()` on both sides. |

### Security part
Sealing, spool layout, AAD, key handling and plain-file deletion are correct. Shares are read only after the app lock is open and onboarding has finished, and the content is held in memory only. No new permission is added on Android. F7 is a money-correctness major, not a security one.

---

## FU-backend-2 (task/FU-backend-2) — APPROVED

| Item | Result | Evidence |
|------|--------|----------|
| Migration `InstallsTombstoneInvariants` safe on existing data | PASS | It replaces the trigger function only (`CREATE OR REPLACE` keeps the owner, the `REVOKE` and the trigger binding); BEFORE UPDATE only, so existing rows are not re-validated. Existing tombstoned rows that kept their `seat_key_hash` (`InstallStore.DeleteAsync` doesn't clear it) stay valid for any update that leaves the hash and `deleted_at` alone. No code path re-sets `deleted_at` (`DeleteAsync` filters `DeletedAt == null`), and `SeatStore.RegisterSql` only writes where the hash `IS NULL`. Down matches `InitialCreateSql.CreateInvariantTriggers` exactly. The snapshot is unchanged. |
| Liveness-only healthcheck | PASS | 2xx and 503 → 0; other statuses, refused connection and timeout → 1; `HealthProbeTests` theory |
| Dead-letter revive bounds | PASS | It selects only `processed_at` set, `next_attempt_at IS NULL`, `attempts > 0`. A completed row that once failed keeps a non-null `next_attempt_at`, so success rows are never revived. Bounds: dead for ≥ 6 h, received ≤ 7 days ago, 100 per run, `SKIP LOCKED`, under the sweep's advisory lock. Worst case is about 5 revive cycles per row. |
| Sandbox skip | PASS | Processor completes with `SANDBOX_OFF` and makes no Apple call; sweep `continue`s |
| dev-keys script safety | PASS | It refuses a non-empty folder with no `kms.env` and removes only its own `*.pem`/`*.key`/`kms.env`; `DevKeysScriptTests` covers refuse and keep |

Findings (all minor, follow-ups):
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F12 | minor | `AppleReconciliationJobs.cs:144-147` | Sandbox rows are skipped in C# after `LIMIT 100`. While `AllowSandbox` is off, leftover sandbox rows keep their place at the head of `ExpiredSql` (oldest expiry first) and can push production rows out of a run until they age out of the window. | Filter `environment` in `ExpiredSql` when sandbox is off. |
| F13 | nit | `AppleReconciliationJobTests.cs` revive test | The name says "not ... an old one", but no row older than 7 days is asserted (the Play test may cover it). | Add the old row. |
| F14 | nit | migration doc comment | It says the hash may become NULL only "in the same statement that sets `deleted_at`", but the trigger also allows clearing it later on a row that is already tombstoned. | Fix the comment. |

---

## Fix list (blocking only)
| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-120 | `voice_controller.dart:125`, `speech_to_text_port.dart:41` (+ small Android host method) | Confirm on-device support (API ≥ 31 and `isOnDeviceRecognitionAvailable`, plus locale support on API ≥ 33) before the first listen; if unconfirmed, go to the consent sheet without starting the recognizer | Controller test: a port reporting no on-device support → `needConsent` and `start` is never called; Allow → exactly one `start(onDevice: false)` |
| T-120 | `voice_controller.dart:301-313`, `voice_logger_screen.dart:558` | Show the account each item will actually be stored on (and let the user change it), or block Save until it is chosen; never redirect without showing it | Widget test: EGP chip plus a USD item shows the USD account on the row before Save; the saved leg uses the account that was shown |
| T-161 | `transaction_edit_screen.dart:161` | `_accountId = e?.accountId ?? pre?.accountId` (keep the prefilled last-4 account) | S-32 test with the last-4 account ≠ default Cash: the saved leg uses it, and an existing transaction on that account opens the duplicate dialog |

## Delta re-review (T-120, T-161 fixes)

Scope: `808ee0e0`, `b467e186`, `d416d323` (T-120, fix24v) and `b6c498ec` (T-161, fix24o), each read against its parent. Kotlin/Swift read; CI for native ran on `ci/fix24v`. `flutter test test/features/voice test/features/transactions/presentation --exclude-tags benchmark,golden`: 89 passed.

### T-120 — F1 (privacy major): resolved
- Every path into `start` is gated. `begin` resets state (`online=false`) and goes to `_startFirst`. `retry` goes to `_startFirst` unless the user already tapped Allow. Only `allowOnline` calls `_listen(onDevice: false)`. `_startFirst` treats a throw or `false` as unsupported and sets `needConsent` without calling `start` (`voice_controller.dart:136-151`).
- Dart port: if `invokeMethod` returns null, or throws (including `MissingPluginException`), the result is `false` (`speech_to_text_port.dart`).
- Android `SpeechSupportRegistration.kt`: below API 31 the result is `false`. On 31–32 it is `isOnDeviceRecognitionAvailable`. This is the same check the plugin's `createRecognizer` uses to choose `createOnDeviceSpeechRecognizer`, so a `true` here means the plugin builds the on-device recognizer. On 33+ the locale must also be in `installedOnDeviceLanguages`. `onError` and the 3 s timeout give `false`, and an exact tag match only produces false negatives, which are safe. The port does not set `intentLookup`, so the plugin's default-service branch can't be reached.
- iOS: the host returns `SFSpeechRecognizer.supportsOnDeviceRecognition`, and nil becomes false. With `onDevice: true` the plugin sets `requiresOnDeviceRecognition = true` (plugin `SpeechToTextPlugin.swift` ~L557).
- Tests: unsupported means no `start` call, supported means exactly `[true]`, and Allow means exactly one `[false]`.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| R1 | minor | `SpeechSupportRegistration.kt` `probeT` / `probe` catch | If `checkRecognitionSupport` throws synchronously after `postDelayed` is armed, the `catch` calls `done(false)`. The timeout then calls `finish(false)`, and `finished` is still false at that point, so `result.success` runs a second time. That throws "Reply already submitted" on the main looper and crashes the app. Unlikely, but possible. Also, the timeout is never removed after a normal finish. This is harmless because of the guard. | Route the catch through `finish` (or set `finished` and remove the callback). Follow-up. |

### T-120 — F2 (money major): resolved
- When `accountFor` differs from the chip, `_rowAccount` shows the account the item is actually stored on, as a tappable pill on the row (`voice-acct-<key>`). The picker lists only accounts in the same currency. `setItemAccount` stores the pick, and `accountFor` uses it only when its currency still matches the amount. Save calls the same `accountFor` (`voice_controller.dart:~383`), so the saved account is the one on screen. The test covers an EGP chip with a USD item: the row shows the USD account, and the saved leg is `usd`.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| R2 | minor | `voice_logger_test.dart` | No test picks a *different* account from the row picker and checks that the save uses it. | Add one with two USD accounts. Follow-up. |
| R3 | nit | `voice_logger_screen.dart` `accountLabel`, `kNoValueDash` | The localized "Cash" label and the dash constant were not part of the review findings. They are small, so they are accepted. | None. |

### T-161 — F7 (money/data major): resolved
- `_accountId = e?.accountId ?? pre?.accountId` (`transaction_edit_screen.dart:161`). New tests use a last-4 account (`acc2`, USD) that is not the default Cash account. Save writes `acc2`, and an existing transaction on `acc2` opens the duplicate dialog. The `kNoValueDash` change in the detail screen is a 2-line nit fix and is accepted.

### Verdicts
- **T-120: APPROVED** (R1, R2 are follow-ups).
- **T-161: APPROVED**.
