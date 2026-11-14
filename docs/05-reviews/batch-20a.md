# Batch 20a review (code + security, Opus)

Batch branch `batch/2026-11-14-20` @ `927e37ff`. Reviewer covers T-063, T-065, T-166, FU-194 + FU-195, plus the Lead merge resolutions for the iOS capture host and the capture pigeon. Sprint rule: only blockers and majors touching money, security, privacy or data loss block.

**Checks run**
- `flutter test --exclude-tags benchmark,golden` on `test/features/capture/data`, `test/app/app_restart_test.dart`, `test/features/security/application/delete_everything_test.dart`, `test/features/settings/privacy_delete_test.dart`, `test/features/settings/settings_screens_test.dart`, `test/app/url_launcher_opener_test.dart`, `test/features/backup/presentation/restore_side_effects_test.dart`, `test/ingestion/native_drain_hold_test.dart`: 94 passed.
- `dart run pigeon --input pigeons/capture_api.dart` on the batch tree, then `dart format`: the Dart, Swift and Kotlin outputs match the committed files exactly. The regenerated pigeon is consistent.
- Swift and Kotlin were read, not built. Each task had a green `ci/<task>` run.

## Lead merge resolutions: OK
- `IosCaptureHostApi` (pigeon, `CaptureApi.g.swift`, `capture_api.g.dart`) has every method: `writeGuardConfig`, `drainSpool`, `ackSpool`, `holdSpool`, `getSpoolStatus`, `clearSpoolAlerts`, `registerBackgroundRefresh`, `wipeLocalData`, `holdDrain`, `isHeadlessDrainActive`, `releaseDrainHold`. `IosCaptureHost.swift` implements all of them and keeps `guardRuntime`, `wipe` and `drainHold`/`stopHeadless` as injected seams.
- There is one `IosCaptureHostPort`, in `features/capture/data/ios_capture_host_port.dart`, with T-063's `writeGuardConfig` and T-066's capabilities and `scheduleIngestionNow`. The T-063 copy in `capture_host_port.dart` is gone. The provider picks the port on iOS.
- Android `AndroidCaptureHost` / `CaptureRuntime` keep both the T-166 `wiper` seam and the FU-194 `drainHold` seam, UI host only.
- `main.dart` keeps `deleteEverythingWiringOverrides`, `appRestartProvider` and `externalUrlOpenerOverride` inside the `AppRestartScope` builder.

---

## T-063 App Intents (C4): **APPROVED**

What I checked:
- **Order.** `IntentCapture.run` follows Guard → `SpoolStore.write` → `headless()`, and only on `.spooled`. On a drop, a refusal or a thrown write, no engine starts and no entry is written; the store cleans up its `.tmp`.
- **Dialogs.** There are four fixed `LocalizedStringResource` keys with no interpolation, so no amount, sender or body can reach a dialog.
- **Run log.** It is encrypted with AAD `zaghlol.capture.v1|intent_runs` and holds times only.
- **FU-196 (one shared key).** `KeychainSpoolKeyProvider` uses the shared `SpoolKeychain`. Reads go through `existing()`, which never creates a key. Only `keyCreatingIfNeeded` → `loadOrCreate` creates one, which is the spool writer policy.
- **062-1 (re-read before delete).** `confirmUnderCurrentKey` runs before both delete-on-proof paths, including the lost-key shortcut. A changed key gets a second decrypt. An unreadable Keychain keeps the entry.
- **`writeGuardConfig`.** Errors are code-only (`CONFIG_INVALID` / `IO_ERROR` / `NOT_AVAILABLE`) and the call goes to the same process-wide `GuardRuntime` the intents use.
- **Spike removal.** The Dart entrypoints, `lib/ingestion/ios_intent_spike.dart`, the Swift spike, its tests and the CI job are all gone.
- **FU-194 interaction.** `HeadlessIngestion.run` now refuses with `.held` while a restore holds the drain. The intent then answers "saved for later" and the entry stays in the spool, which is correct.

Findings (non-blocking):
| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 063-1 | minor | `app/ios/Shared/SpoolCipher.swift:55` (`reloadKey`) | When nothing is cached yet (`before == nil`), the result is `.changed`. That forces a second decrypt that cannot succeed. The result is correct, only the work is wasted. | Return `.unchanged` when `before == nil`, or document it. |
| 063-2 | minor | AC 1 | "Run while the app is closed" is only a device step, and it has not been run (Release build on iOS 17 and 26). | Keep it on the device checklist (manual steps 1–6). |

## T-065 iOS Share Extension (C4): **APPROVED**

What I checked:
- **Encryption.** Body and meta are AES-GCM under the shared spool key. The AADs bind the id and the role: `zaghlol.spool.v1|file|<id>.bin` for the body (the OCR layout) and `zaghlol.share.v1|meta|<id>` for the meta. The meta is written last and is the commit point. Both writes go through `.tmp` + rename, and a failure removes every file of the share.
- **Nothing in plaintext.** The extension reads the system's temporary copy inside the handler and zeroes its buffers. It writes nothing at the App Group root (only `spool/files/`) and calls `ensureExcluded` before the first write.
- **Unsupported types.** They leave only the encrypted one-byte reason slot, as designed. The type is decided from magic bytes, not the declared UTI.
- **Entitlements.** `ShareExtension.entitlements` and its Info.plist use `group.$(ZAGHLOL_APP_BUNDLE_ID)` and `$(AppIdentifierPrefix)$(ZAGHLOL_APP_BUNDLE_ID).shared`. These equal the app's App Group and its second keychain group.
- **Guard bypass.** Shared text skips the Guard, which matches platform-channels §2.1: it is user-initiated and always confirmed.
- **FU-198.** The OCR root is now `OcrRoots.filesDirectory()` (App Group `spool/files/`), with a non-existent fallback path, so OCR refuses paths elsewhere.

Findings (non-blocking):
| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 065-1 | minor | `app/ios/Runner/Platform/OCR/OcrHost.swift:54` | `SharedSpoolKeyProvider` calls `loadOrCreate()` on a read path. That goes against the T-063/FU-196 rule "reads never create". On an `unusable` item the OCR reader can replace the key and orphan the spool, the Guard file and the shares. | Use `SpoolKeychain().existing()` and return nil unless `.found`. |
| 065-2 | minor | `app/ios/Shared/ShareStore.swift:231,242,276` | Delete-on-`notAuthentic` has no 062-1 re-read. The app's `SpoolRuntime.shared` cipher can hold a stale key, for example after an in-process "Delete everything" when the extension then mints a new key. A genuine share would then be deleted. | Call `cipher.reloadKey()` and retry once before `removeAll`, as `SpoolStore` does. |
| 065-3 | minor (AC gap) | AC 1 / open question `ocrPath` | "Shared screenshot appears in app OCR confirmation" cannot be shown. `ShareReceived` is emitted, but no Dart screen consumes it, and Dart has no path to hand to `OcrHost`. | FU: add `ocrPath` to `ShareDescriptor` (or OCR from bytes) and give the share-confirmation UI an owner task. |
| 065-4 | nit | open question | The Back Tap guide is not built and needs copy keys. | Follow-up. |

## T-166 Delete everything (C4, deletes user data): **CHANGES_REQUESTED**

What I checked:
- **Order.** Steps run marker → creds snapshot (memory only) → seat-key rotation (iOS) → jobs → DB close → both `SecretSlot`s deleted under the bootstrap lease → DB files (main last) and temp → native.
- **Native order.** Android cancels jobs, notifications and the Guard user part, deletes Keystore aliases, then clears contents. iOS cancels BGTasks and notifications, deletes Keychain items (generic passwords one by one by persistent ref, skipping `app.zaghlol.seatkey`), then clears contents and re-excludes the roots.
- **Keys before files.** This holds on both layers.
- **Seat keys.** They are generic passwords under `app.zaghlol.seatkey`. The Secure Enclave key lives as a `dataRepresentation` blob, and CryptoKit creates no `kSecClassKey` item, so the blanket `kSecClassKey` delete cannot hit it. `rotateForNewInstall` is idempotent, so a repeat on resume is safe.
- **Server delete.** It runs on a throwaway client over a `MemoryBackendStateStore`, gets one retry, is never queued and never awaited. Nothing reaches disk.
- **Confirm.** It is still the T-162 type-to-confirm. `wipeEverythingProvider` runs only after `confirmed == true`. The EC-69 warning is Android-only.
- **Android leftovers (judged acceptable).** `databases/` holds only WorkManager's store, cancelled and pruned. `shared_prefs/`: the app writes none, and no dependency keeps financial data there; `google_sign_in` is signed out.
- **Widget snapshot (T-118).** The files are cleared: Android `noBackupFilesDir/widget/`, iOS App Group `Library/Application Support/widget/`. The key is deleted. See 166-3 for what the widget still shows.

Findings:
| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 166-1 | **major (data loss)** | `app/lib/features/security/application/delete_everything.dart:203-213`; `delete_everything_providers.dart:112,130`; `app/lib/main.dart` (`_resumeWipe` before `runApp` and in `beforeStart`) | Any failing local step (`jobs`, `close_db`, `temp`, `native`, …) writes the marker back. Every later launch and every in-process restart then runs `resume()` without asking: it closes and deletes the DB, deletes `dbKey`/`backupKey` and wipes the sandbox. A step that fails every time keeps the marker forever. Possible causes: a file the app can't remove in Caches/tmp, a Keychain class delete returning an error, a WorkManager failure. In that state the user's new data, entered after the restart into first-launch state, is deleted silently at each launch. The `privacyDeleteFailed` key is missing too, so nothing is shown. | Bound the resume so it can never destroy data created after the wipe. For example, keep the marker only while the crypto-shred is incomplete (`key_slots` or `db_files` failed), and retry other failed steps (native, temp, jobs) at most N times without touching the DB or key slots. Alternatively, store the wipe time or an attempt count in the marker, and stop deleting the DB and key slots once a newer DB key slot exists (created after the marker). After the cap, clear the marker. |
| 166-2 | minor | `app/ios/Runner/Platform/Capture/IosCaptureHost.swift:263` (`wipeAll`); `app/ios/Shared/SpoolCipher.swift:49`; `app/ios/Runner/Capture/CaptureGuardRuntime.swift:16` | The iOS wipe does not drop in-process caches. `SpoolRuntime.shared`'s `KeychainSpoolCipher.cached` key and `CaptureGuardRuntime.shared`'s user snapshot (the old ignore rules) outlive the in-process restart. Android does call `forgetUser()`. Until the process dies, App Intents apply the old user's rules and write with a key that is no longer in the Keychain, so those entries are lost on the next launch. | Add `GuardRuntime.forgetUser()` on iOS and a cipher `dropCache()`, both called from `wipeAll`. |
| 166-3 | minor | native wipe | The home-screen widget keeps showing the last safe-to-spend figure: no `WidgetCenter.reloadAllTimelines()` or `AppWidgetManager` update runs after the wipe. | Trigger a widget refresh at the end of `wipeLocalData`. |
| 166-4 | minor | native wipe (Android) | The Android native part deletes the marker (in `filesDir`) during its contents clear. Dart puts it back only if a step failed. A crash in the middle of the native part therefore leaves no marker. This is acceptable because the keys go first, so whatever is left is crypto-shredded. | Optionally skip `wipe_pending` in the clear. |
| 166-5 | minor | copy | `privacyDeleteBackupsKept` and `privacyDeleteFailed` are missing from the copy deck. | Copy-owner follow-up. |
| 166-6 | minor | ACs 1 and 3 | The full device sandbox scan and the seat-key element-1 check with T-179 are device steps that have not been run. | Device checklist. |

## FU-194 + FU-195 restore hold and URL opener (C4): **APPROVED**

What I checked:
- **Persistence and expiry.** The hold is persisted on both platforms (Android `noBackupFilesDir/capture/drain_hold`, iOS App Group `.../capture/drain_hold`, excluded from backup). The file holds only the expiry time. The TTL is capped at 10 min, and a clock set back counts as expired.
- **Admit vs. hold.** `admitEngine` and `hold` share one lock. On Android the check sits in the same main-thread step as `TOOK_OVER` and returns `HELD` → `RETRY`. On iOS, `run()` throws `.held` before setting `running`, and `engineGone()` runs in `defer`.
- **Stopping a live engine.** `holdDrain` on Android posts `headless.shutdown()`; on iOS it calls `requestStop()`.
- **Dart side.** `pause()` holds the drain and polls until no engine is active, bounded by `pauseTimeout`. A failure at any point releases the hold and reopens the gates. The hold is renewed every 3 min. `resume()` releases it, and `restore_flow` calls it in `finally`. A hold write failure refuses the restore, which is the safe direction.
- **FU-195.** `urlLauncherOpener` opens https URLs with a host only and swallows errors. Every caller passes an `AppLinks` constant, so no user data goes into a URL.

Findings (non-blocking):
| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 194-1 | minor | `app/ios/Runner/Platform/Capture/HeadlessIngestion.swift` (`DrainHold.load`) | The iOS hold is read from the file only at `DrainHold.shared` init. That is fine while only the app process runs engines. | Note in platform-channels §1.4 that extensions never run engines. |
| 194-2 | nit | `app/lib/features/backup/presentation/backup_ports.dart` | If the provider is disposed between `pause()` and `resume()`, the `_renew` timer is never cancelled. The hold still expires on its own. | Cancel it in `ref.onDispose`. |

---

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-166 | `app/lib/features/security/application/delete_everything.dart:203-213` (+ `delete_everything_providers.dart:112,130`) | A local step that keeps failing must not make every later launch delete the DB and key slots again. Keep the destructive resume only while the crypto-shred (`key_slots`, `db_files`) is incomplete, or cap the attempts. Never delete a DB whose key slot was created after the marker. Clear the marker after the cap. | `delete_everything_test.dart`: the native step always throws. After the first run, create a new DB and key slot (the post-restart first launch), call `resumePendingWipe` again, and assert the new DB and key slot survive. A second test checks that the marker is cleared after the retry cap. |
