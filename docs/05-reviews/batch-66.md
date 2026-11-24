# Review — batch 66 (T-236, T-237, T-238, T-239)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus, code + security; Opus because T-238 touches the user-data wipe and T-237 touches alerts) |
| Date | 2026-11-24 |
| Commit / diff | `batch/2026-11-24-66` @ cf609cb4, `git diff origin/main...HEAD -- . ':!**/*.png' ':!**/generated/**'` |
| Verdict | T-236 APPROVED · T-237 APPROVED · T-238 CHANGES_REQUESTED · T-239 APPROVED |

Commands run:
- `flutter test --exclude-tags golden test/features/settings test/features/notifications test/features/export_import test/core test/app test/features/security`: 1758 passed, 1 skipped.
- `flutter analyze lib integration_test test/...`: clean.
- `bash -n` on the four device scripts: ok.
- A scratch drift test (not committed; it is described under M-1).

---

## T-238 — export Gold/Free, language + digits, app lock, delete everything (C2; the fixes touch the user-data wipe) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| E2E-09 Free: preview only. Gold: CSV header and row count | PASS | `e2e_export_device_test.dart`, run 45453874654 |
| E2E-10 ar/en × digits, every tab, no FlutterError | PASS | `e2e_locale_device_test.dart` |
| E2E-11 lock screen shown; FLAG_SECURE matches the setting | PASS | `e2e_lock_device_test.dart` + `secure_state` in the script |
| E2E-12 Welcome screen, empty DB, settings reset, **scheduled notifications cleared** | PARTIAL | The first three are asserted. Scheduled notifications are only logged, never asserted, and the test schedules none before the wipe (minor m-1). |
| Bug fixes have unit tests | PASS (with M-1) | `delete_everything_test.dart` "a database close that never returns…". The provider close fix has no unit test. |

### Data after a timed-out close (Lead question 1)
- **Is the wiped data fully gone? Yes.**
  - After the close step (timed out or not), `_deleteKeySlots` runs, then `_deleteDbFiles`, which deletes the main file, `-wal` and `-shm` and fails if `anyExists()`. On Android/iOS, unlinking a file that is still open works.
  - The native `LocalDataWiper` then does the rest:
    - cancels and prunes WorkManager;
    - `NotificationManager.cancelAll()`;
    - `NotificationPresenter.cancelAll()`, which cancels pending quiet-hours/reminder alarms and calls `ScheduleBook.clear()` (the T-230 boot re-arm store);
    - forgets the Guard user;
    - deletes every Keystore alias;
    - clears `filesDir`, `noBackupFilesDir` (where T-230's `notif/schedules.txt` and T-224's launch-theme file live) and `cacheDir`.
  - The old connection keeps the SQLCipher key only in its isolate's memory. The key slot is gone, so a reopen cannot read old data.
  - **Scheduled notifications/alarms are cancelled, so no major on that.** The test scheduled nothing before the wipe, so the 4 `dumpsys alarm` lines are not app notification alarms. Most likely they are WorkManager or system entries that name the package. See m-1 for the missing proof.
- **Half-wiped state: no.** The marker logic is unchanged. A timed-out close is not a failed step, so the wipe goes on and finishes.
- **But the old connection stays alive across the restart, and the root cause is not understood.** See M-1.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-1 | **major** (data) | `app/lib/features/security/application/delete_everything.dart:376-379`, `delete_everything_providers.dart:88-97`, `app/lib/core/db/app_database_providers.dart:67-70` | **The 10 s timeout hides the cause of the hang and leaves the old SQLite connection open while the app reopens a new database at the same path.**<br>**Root cause (reproduced locally):** drift's `close()` runs `StreamQueryStore.close()` first. That awaits `MultiStreamController.close()` for every `watch()` listener, and the future does not complete while a subscription is **paused**. Riverpod 3 pauses the subscriptions of providers that are not visible: the tabs under the pushed Settings route are always off-screen when the user taps Delete everything.<br>**Scratch test:** `AppDatabase(NativeDatabase.memory())`, one paused `customSelect(...).watch()` subscription. `close()` had not returned after 2 s. It completed right after `sub.cancel()`.<br>**Consequences:**<br>(a) Every real wipe started from Settings probably waits the full 10 s.<br>(b) The connection to the deleted files stays open in its background isolate. It closes only when the in-process restart disposes the old container and cancels the streams. That races with the new container opening a new key and database at the same path. When the old connection closes, its WAL close gets the exclusive lock on the old inode (no other connection holds it), checkpoints, then deletes `<path>-wal` and unlinks `<path>-shm` **by name**. If the new database is already open, its WAL and SHM are deleted: commits are lost and the headless engine's second connection can corrupt the file.<br>The ConcurrentModificationError that the provider fix now swallows has the same cause: `StreamQueryStore.close` iterates `_activeKeyStreams.values` across awaits while streams are being cancelled.<br>The comment "the restart drops the connection" is wrong: the restart runs in the same process. | 1. Close the SQLite handle without waiting on paused UI streams. For example, in the wipe's `closeDatabase`, `await db.executor.close()` (bounded), then call `db.close()` without awaiting it. Alternatively, cancel or dispose the UI's stream providers before closing. Keep the timeout only as a backstop.<br>2. Make sure no new database opens while an older close is still pending. Either the restart awaits the pending close, or after a timed-out close the app does not restart in-process.<br>3. Add a test with a real `AppDatabase` (file-backed if possible) and a **paused** `watch()` subscription. Assert that the wipe's close step finishes well before the timeout and that the executor is closed before the key slots are deleted. Without the fix, this test must fail or hit the timeout.<br>4. Narrow the `onError((_, _) {})` in `app_database_providers.dart` once (1) is in. See m-2. |
| m-1 | minor | `app/integration_test/e2e_wipe_device_test.dart`, `.github/scripts/e2e-settings-device.sh` (`run_wipe`) | The AC "scheduled notifications cleared" is logged, not asserted, and nothing is scheduled before the wipe, so the check proves nothing. The code path is correct (see above). | FU: before the wipe, schedule one quiet-hours alert or bill reminder. After the wipe, assert that `dumpsys alarm` has no `NotificationAlarmReceiver` entry for the package and that `files/notif/schedules.txt` (under noBackup) is absent. |
| m-2 | minor | `app/lib/core/db/app_database_providers.dart:70` | Every close failure on dispose is now swallowed silently, including restore/restart cases unrelated to the wipe. | After M-1, swallow only the known drift error, or record it in the code-only diagnostics. |
| m-3 | minor (security: Info) | `app/lib/features/export_import/presentation/export_ports.dart:44-51` | `exportDestinationForDeviceTest` is a mutable top-level global (CLAUDE.md §8: no global singletons). `@visibleForTesting` is only an analyzer hint. Nothing in `lib/` sets it and it does not touch the Gold gate, so neither release nor prod builds are affected. | FU: read it only when `kDebugMode` is true (`kDebugMode ? exportDestinationForDeviceTest?.call() : null`), so a release build ignores it. |

### Security part (T-238)
- **§2a Gold:** the test gets Gold through `EntitlementNotifier.debugOverride`. That method already exists in `gating.dart:207` and returns early when `!kDebugMode`, so it is a no-op in profile and release. The export seam changes only where the bytes go; `gateOrPaywall` still runs. No production bypass. **OK.**
- **Exports redirected in release:** not possible. Nothing in `lib/` sets the seam (only `integration_test/e2e_export_device_test.dart:49`). Hardening is m-3.
- **Wipe:** the crypto-shred order is unchanged and the data is gone (above). The open risk is the integrity race in M-1. It cannot affect the old data; it can affect the new database.
- **Logging:** the scripts print counts, file names and the step names from the wipe marker, not contents. The test logs only ids and counts. **OK.**

---

## T-237 — manual add/edit/undo, budget alert, reimbursement (C2; fix in alerts) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| E2E-04 add / edit / delete / undo / bulk + undo, DB and list | PASS | `e2e04_manual_device_test.dart`, runs 45409776427 and 45412480180 |
| E2E-05 payday 25, 80 % alert posted (`dumpsys`, no amounts), safe-to-spend checked against an independent value | PASS | `e2e05_budget_device_test.dart` + `e2e-device.sh` |
| E2E-06 transfer pair, reimbursement, Insights totals | PASS | `e2e06_transfer_device_test.dart` |
| Bug fix has a unit test | PASS | `silent_gateway_claim_test.dart`: the silent gateway claims nothing; the real gateway claims once and shows |

### Alert later shown exactly once (Lead question 2)
- **Headless engine:** it runs on the default `SilentNotificationGateway`. `notify` returns `unavailable` before `markFired`, so `fired_alerts` gets no row.
- **When the alert is shown:**
  - `housekeepingProvider` runs the `budget_alerts` job on cold start (forced) and on resume (throttled in memory, per engine, so the headless run cannot throttle the foreground one).
  - `BudgetAlertService` re-evaluates the cycle and calls `notify` for the highest crossed threshold. It now claims through the real gateway and shows once.
  - A second run returns `duplicate`.
- **Hide-amounts and quiet hours:** both are applied inside `notify`, from the prefs read at that later run. A later run inside quiet hours schedules the alert instead.
- **Thresholds crossed headless:** the lower ones are still claimed headless by `BudgetAlertService.markFired`. That matches BR-BUD-02 (only the highest alerts).
- **No double-fire:** the foreground engine always has the Pigeon gateway, so `unavailable` never happens there.
- **Other `notify` callers:** the salary check, auto-added recurring and due reminders treat `unavailable` as "not sent" (`shown || scheduled`), so they retry on the next run. Before this fix they recorded the alert as sent and never showed it.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| m-4 | minor | `app/lib/features/notifications/application/duplicate_charge_alerts.dart:29-31` | A duplicate-charge alert raised headless is shown later only if the app runs within `2 × duplicateWindow` (the window is rebuilt from "now"). Not a regression (before T-237 it was lost every time), but the device E2E fix does not cover it. | FU: let the duplicate check look back to the last foreground check, or record "pending" clusters. |
| n-1 | nit | `app/lib/features/notifications/data/notification_service.dart:68` | `gateway is SilentNotificationGateway` ties the service to a concrete class. | Optional: a `bool get canShow` on `NotificationGateway`. |

---

## T-236 — SMS while killed, ignored card, notification capture (C2) — APPROVED

| Criterion | Result | Evidence |
|-----------|--------|----------|
| E2E-03 force-stop and kill -9 → saved, time delta < 10 s | PASS | Run 45392652575. Design path recorded (ADR-005 launch catch-up for force-stop; receiver plus spool for kill) |
| E2E-07 ignored card stores nothing | PASS | `IGNORED txn=0 raw=0 review=0` |
| Notification capture without weakening filters | PASS | The capture uses the existing `UserSenderService` path with `com.android.shell`; `cmd notification allow_listener` is CI-only; no production filter or permission is changed |
| Logs | PASS | `killed-device.sh` echoes only the first 30 chars of the `emu` reply and the first 80 chars of the `cmd` output, never the body. Bodies are synthetic |

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| m-5 | minor | `app/integration_test/sms_killed_device_test.dart` (notif phase) | No device proof that a non-admitted package is ignored (disclosed; the Kotlin unit tests cover it). | FU only if a second poster becomes available. |

---

## T-239 — explorer survives emulator faults; restores onError (C2) — APPROVED

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Bluetooth off before tests, in CI scripts only | PASS | `device-flows.sh:51-54`, inside the CI script only; no app or manifest change |
| left-app classified as an emulator fault vs an app issue | PASS (info only) | `device-flows.sh:343-354`; it does not change the exit code and prints `LEFT-APP … treat as an app issue` when logcat shows no system fault |
| `FlutterError.onError` always restored | PASS | `explorer.dart:189-193` is idempotent and is called in the `finally` at `app_explorer_test.dart:378` |
| Widget test: the tip tap stays in the app, tap mood, next line | PASS | `home_mascot_slot_test.dart` (en only; the test is behavioural, with no new UI text) |
| Explorer jobs green on `ci/T-239`, run id reported | **MISSING** | `T-239.md` has no build section and no green run id |

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| m-6 | minor | `docs/04-tasks/tasks/T-239.md` | The AC run id is not recorded. | Lead: record the explorer job ids from the batch's device-flows dispatch before moving T-239 to DONE. |
| m-7 | minor | `.github/scripts/device-flows.sh:347` | The fault grep reads the whole logcat buffer, not the time of the left-app. An unrelated earlier system fault would label a real app left-app as `EMULATOR-FAULT`. | FU: clear logcat per part (`logcat -c` before each explorer run) or match timestamps. |

---

## Workflow (Lead question 5)
`device-flows.yml` still has `flows`, `scenario`, the `explorer` matrix (six slices on `all`), `killed`, `e2e-manual-budget` and `e2e-settings`.
- The triggers are unchanged from `main`: `workflow_dispatch` plus `ci/**` pushes. `main` pushes never ran this workflow.
- On a dispatch with default inputs, every `if:` is true, so every job runs.
- The `ci/T-233` exclusions were dropped; that is harmless.

## Proposed follow-ups (FU-294)
FU-294a: m-1 (wipe E2E must schedule, then assert no alarm or schedule file left).
FU-294b: m-2 (narrow the swallowed close error).
FU-294c: m-3 (`kDebugMode` guard on the export seam).
FU-294d: m-4 (headless duplicate-charge alerts outside the window).
FU-294e: m-5 (negative-proof poster, if one becomes available).
FU-294f: m-7 (time-scoped fault grep).
Entered in `implementation-status.md` as FU-294 in the fix round ((a) and (b) fixed there).
m-6 is a Lead DoD item.

**Fix round:** only M-1 (T-238). It is a data-integrity major, so it qualifies under the SPRINT rules.

## Fix round (T-238, M-1 + m-1 + m-2)
Commits `675cb2b5` and the E2E follow-up on `batch/2026-11-24-66` (also pushed to `ci/T-238b`).

**M-1, fixed at the cause.**
- New `app/lib/core/db/db_handle.dart`. `closeDbHandle(db)` closes `db.executor` directly. It never calls drift's `close()`, which waits on paused `watch()` listeners. drift answers the background executor's close request before its isolate has closed SQLite. For that reason, `openEncryptedExecutor` registers an isolate exit listener (drift `isolateSetup`). The close completes only when the isolate has exited, after it closed the database. The close is idempotent.
- Closes in flight are recorded by file path. `openDatabaseWith` waits for any handle on the same file that is still closing. If that handle does not close within 10 s, the open returns `unavailable`. It never opens beside an older handle, so an old close cannot delete a new `-wal`/`-shm`. This also covers restarts other than the wipe.
- `DeleteEverything`: the close step uses `closeDbHandle` through the provider. The 10 s timeout is now only a guard. A close that fails or times out fails the wipe before anything is deleted: the marker keeps every part, `WipeIncomplete` reaches the user ("couldn't delete"), there is no restart, and the next launch finishes the wipe. The remote delete still runs.
- Provider dispose (`disposeAppDatabase`): `closeDbHandle` runs first, and its errors are not caught. drift's `close()` runs second, for the streams, and its errors are dropped only because the handle is already known closed. That covers m-2.

**Tests.** `delete_everything_test.dart`:
- Paused `watch()` during the wipe: the wipe completes in under 5 s, the old connection can no longer query, and keys, files and marker are gone. Without the fix this hits the 10 s guard.
- Restart after the wipe: the new DB's `-wal`/`-shm` and its data survive the old provider's dispose.
- A hung close now fails safely: keys, files and marker are kept and native is not run. This replaces the old "does not hold the wipe" test.

`db_handle_test.dart`:
- An open next to a handle that is still closing fails with `unavailable` and creates no file.
- `closeDbHandle` is idempotent, and an open after it proceeds.

The host could not reproduce the WAL deletion itself: on Linux the old close left the new `-wal` alone. So the restart test is a regression guard, and the negative proofs are the paused-watch timing, the closed-handle check and the "open waits" test.

**m-1.** E2E-12 now schedules an alert before the wipe. The script finds it by its epoch-ms time in `dumpsys alarm` and in `no_backup/notif/schedules.txt`. It must be present before the wipe and absent after it. The time is used because the app schedules its own weekly nudge again after the restart. E2E-12 also logs `WIPE_MS`, from the confirm tap to Welcome, and fails at 10 s or more.

**Device (device-flows, settings job only).**
- Run 45469150283 (`ci/T-238b`, workflow_dispatch `e2e_settings_only`) passed E2E-09..12.
- E2E-12 `WIPE_MS 1887`: the wipe ran from the confirm tap to the Welcome screen in 1.9 s, so the close guard never fired. The first run, 45465615984, measured 1451 ms.
- Test alarm and re-arm entry: 1 and 1 before the wipe, 0 and 0 after it. No notifications were posted.
- That first run failed only on m-1. It used whole-receiver counts, and those counted the nudge the app schedules again after the restart. The assertion now matches the test alert's time. "Receiver alarm lines" went from 2 to 3 and is only printed, not asserted. It includes the new nudge.
- Also green on the fix commit: app-ci 45465524080, db-platform 45465524168 and security-scan 45465523992.

**Verdict for T-238 after the fix round:** M-1 resolved; m-1 and m-2 fixed. Lead delta check or a Sonnet delta re-review is still needed (about 250 changed lines).
