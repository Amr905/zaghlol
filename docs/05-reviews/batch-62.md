# Batch 62 review (`batch/2026-11-23-62`, T-223..T-228)

Reviewer: code-reviewer (Opus). Production diff read; `flutter test --exclude-tags golden test/features/notifications test/features/insights test/core/platform`: 572 passed.

## T-223 Charts "Other" row and thin net worth: APPROVED
- `chart_repository.dart` `otherMerchants` uses the same filter, currency and `_netSpend` as `topMerchants`, with the same `ORDER BY s DESC, m` and `OFFSET n`, so it is exactly the tail of the same currency; it never sums currencies. Null when the tail is empty.
- The "Other" row has an empty `merchantNorm` and is not tappable. Thin net worth reads the amount through `chartMoney`, which honours hide-amounts. Repository and redesign tests cover both.
- Minor: none.

## T-224 Launch theme: CHANGES_REQUESTED
- **major** `MainActivity.kt` (`attachBaseContext` -> `LaunchTheme.wrap`): the night bits are forced for the whole activity lifetime. Flutter's `platformBrightness` is read from the activity resources, and the manifest lists `uiMode` in `configChanges`, so the activity is not re-created. If the user picks Dark, then switches back to "System" while the phone is Light, `ThemeMode.system` keeps resolving to dark until the activity is re-created (restart). The same holds for Light forced while the system turns dark. The choice file is only read at attach time. Required change: when the stored choice changes between forced and system (or between forced values) at runtime, make the app re-resolve. Either call `recreate()` from the `set` handler when the value differs from the one the activity was attached with, or stop relying on `platformBrightness` once forced (the Dart side resolves `system` from a native "real system brightness" value). Add a test or a documented device check for dark -> system.
- Checked, no issue: keyboard/IME (separate process, unaffected); `NotificationTapActivity` is a non-exported trampoline with no UI and keeps the system theme; `createConfigurationContext` keeps the override across later system config changes while forced; the allow-list (`light|dark|system`) is enforced on write and read, with an atomic tmp+rename; the file is in `noBackupFilesDir` and `data_extraction_rules` excludes everything. iOS: file in Application Support (T-165 excluded), allow-list, `SceneDelegate` sets `overrideUserInterfaceStyle` only (the system launch screen still follows the system, as documented). The same stale-until-restart caveat does not apply on iOS (the override is set once, but the Dart theme follows the user's mode, and iOS `system` -> `unspecified` is applied only at the next scene connect; same minor below).
- minor (FU-290a): iOS also applies the override only at scene connect, so dark -> system within a session leaves the window's native chrome (keyboard, alerts) in dark until restart. Set `overrideUserInterfaceStyle` in the `set` handler too.
- minor (FU-290b): `main.dart` import order (`launch_theme.dart` placed before `logging/diag_error_handlers.dart`); `dart format` does not reorder, so it passes.

## T-225 Supply-chain pins and gitleaks: APPROVED
- `.gitleaks.toml` diff is three deleted `paths` lines (`backend/docker-compose*.yml`, `run_backend_local.sh`, `api_db_followup.py`) and nothing added, so it is strictly narrower. GitHub `security-scan` and `app-ci` on `ci/T-225` are green (run 45187592937).
- The builder's one history finding (T-212.md, off-main branch) is pre-existing and not caused by this task.
- Open and honestly recorded: CI-only image digests (proxy 403) stay as FU-264.

## T-226 Triage FU-233..237: APPROVED
- Spot-checks: `roiTipCountProvider` has no consumer (only its own definition in `roi_tips_providers.dart`); FU-237a "fixed in batch 53" matches `implementation-status.md:827`; FU-233e/f stay open as backend items. No code changed.
- Minor (FU-290c): the FU-237a row cites `smart_roi/application/roi_tips_providers.dart`, but the file is `roi/presentation/roi_tips_providers.dart`.

## T-227 Triage FU-238..258: APPROVED
- Spot-checks: FU-258 #2 is true (`payAfterGate` waits for unlock, then confirms); FU-258 #1 is true (`NotificationTapActivity` is `exported="false"`, manifest line 47); FU-249 backend-only is consistent.
- Minor (FU-290d): the task file's Result table still says FU-258 #1, #3, #4 are open, but T-228 closed #3 and #4 and the status row says so. Update the task file.

## T-228 Notifications: APPROVED
- `cancel(id)` is present in the Pigeon contract, Dart gateway, Kotlin (`NotificationPresenter.cancel`: `nm.cancel`, alarm with the same requestCode and the same `filterEquals` intent, `FLAG_NO_CREATE`, then the pending-id file) and Swift (pending and delivered, string id). Unknown ids are no-ops. Generated code matches the contract.
- Reminder cancel: id = FNV of `type|itemId|dueIso|threshold` for thresholds {0,1,3} (the same dedupe key `sendDueReminders` uses). It touches exactly that item and date; other items and the next due date are untouched. "Fired" claims stay, so a cancelled reminder is not re-sent. All three paths are covered: the bills screen, the notification action (via `BillsActions.markPaid`) and the `autoMarkPaid` marks.
- Friday nudge: the title and body are the amount-free `weeklyHidden` text in every mode; `scheduleAt` honours the per-type toggle (cancels when off) and quiet hours (`nextAllowed`); the id is stable per Friday, so re-scheduling replaces it. The real summary runs on Fridays only, and `cancelWeeklyNudge(today)` removes that same Friday's nudge (scheduled or delivered) before the summary, so there is no duplicate. No financial data in the payload (`/insights` route only).
- Minor (FU-290e): the nudge is lost after a reboot until the app is next run (inexact alarms; already noted in the status row).
- Minor (FU-290f): if the user disables the weekly-summary type after a nudge is scheduled, the nudge is cancelled only at the next app run; the pending alarm can still fire once. The toggle path should call `cancelWeeklyNudge`.

## Verdicts
- T-223 APPROVED, T-224 CHANGES_REQUESTED (1 major), T-225 APPROVED, T-226 APPROVED, T-227 APPROVED, T-228 APPROVED.
- Proposed FU-290: a-f above (owner T-224 for a/b, doc tasks for c/d, notifications lane for e/f).

## Fix round (T-224 major, FU-290 a, b, d, f)
- T-224 major: chose the preferred fix (no activity recreation, no forcing change). Native reports the phone's real night mode (`Resources.getSystem().configuration.uiMode`, unaffected by the forced bits) over `zaghlol/launch_theme`: getter `systemIsDark` plus a push from `MainActivity.onConfigurationChanged`. Dart (`effectiveThemeModeProvider`) maps the "system" choice to explicit light/dark from that value; light/dark choices and hosts that do not answer (iOS, tests) are unchanged. Chosen over clearing the forced bits at runtime because the activity cannot re-resolve resources without a recreate.
- FU-290a: iOS `set` handler now applies `overrideUserInterfaceStyle` to all windows (dark -> system clears it). FU-290b: import order in `main.dart`. FU-290d: T-227 task file updated. FU-290f: turning the weekly-summary toggle off calls `cancelWeeklyNudgeProvider` (cancels the next Friday's nudge).
- Tests: Kotlin `isNightReadsOnlyTheNightBits`; Dart system brightness follows value and updates on push; explicit choice ignores it; `cancelWeeklyNudgeProvider` cancels the scheduled id. Local: format, analyze, `test/core/platform`, `test/features/notifications` green.
