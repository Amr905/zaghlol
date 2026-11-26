# Batch 83 review (T-293, T-294, T-295)

Reviewer: code-reviewer (Sonnet). Branch `batch/2026-11-26-83`, diff `origin/main...HEAD`.
Checks run in `app/`: `flutter analyze` clean. `flutter test -x golden` over `test/core/ui test/features/mascot test/app test/core/settings test/features/transactions/presentation test/features/voice test/features/ingestion/presentation`: **514 passed, 0 failed**. Kotlin, Swift, `HapticsPlanTest.kt` and goldens not run here (CI only).
T-293's `z_haptics.dart` is the one in the tree. Callers in T-294 (`ZHaptics.play(payday)`, `timelineMs`, `light()`) and T-295 (`play(saved)`, `light()`) match its API.

## T-293 Haptic patterns (C3) - APPROVED

Read carefully for compile and API errors; found none.
- Dart: `play` returns early when `enabled` is false, so there is no channel call and no fallback. Reduce motion sends one light tick through `HapticFeedback` only. Missing plugin, `PlatformException` or a `false` reply falls back on a timer, and `play` never throws. Beat table equals the task table.
- Kotlin: `HapticsPlan` is pure. `PRIMITIVE_*` ids (CLICK 1, THUD 2, TICK 7) are correct. The `Composition` path is guarded by `SDK_INT >= R` plus `areAllPrimitivesSupported`. The waveform path needs `hasAmplitudeControl`. `RuntimeException` (including `SecurityException`) is caught and the reply is `false`. Touch feedback off returns `true` (silent). Registered and unregistered in the UI engine. Declared VIBRATE is normal and needs no prompt.
- Swift: lazy engine, auto shutdown, nil on stop/reset/background, impact fallback. No compile problem seen (`as? Int` on NSNumber is fine). The pbxproj entry is checked by CI.

Findings
- nit: `ZHaptics.enabled` and `ZHaptics.reduceMotion` are not wired to any setting (`grep` finds no writer). The haptics "app setting off" row in the device check cannot be exercised yet. Pre-existing for `enabled`; the task assumed it. FU-397.
- nit: Android does not cancel a running vibration when the app is backgrounded (up to 1.4 s of buzz). iOS does stop. Acceptable.
- nit: the Swift `parse` has no XCTest (stated in the task).

AC to test map: timelines, disabled, reduce motion, missing channel, throws -> `z_haptics_patterns_test.dart` (passing); Android builder -> `HapticsPlanTest.kt` (CI); compile -> `ci/T-293` (not run by me).

## T-294 Payday sheet (C3) - CHANGES_REQUESTED

Trigger logic is sound. `paydayDecision` is pure. The txn id is stored (capped 32) before the sheet is shown, so a restart or a restore of the same data does not repeat it. Salaries older than 7 days are stored silently. The txn must be a live income row. The amount is the transaction's own `Money` (minor units, its own currency). The per-day line is EGP-only and hidden when it is absent or not positive. Hide-amounts goes through `moneyExact`. Reduce motion is honoured (OS and app). The Egyptian copy reads well.

Findings
- **major** `app/lib/app/home_mascot_slot.dart:46-55` with `payday_celebration.dart:100-110`. The celebration is consumed (`_shown.add` and the persisted txn mark) before the sheet is allowed to open. The post-frame guard then silently drops it when `ModalRoute.isCurrent != true` or the slot is unmounted. Input: the user adds a cash salary in the Add screen, which is a root route pushed over the shell. The salary state changes while Add is still on top, or the async provider re-run lands before the pop settles. The guard returns, the id is already marked, and the celebration is lost forever. The task explicitly requires "right after the cash save returns to Home". Required: do not mark celebrated until the sheet has actually opened, or keep the pending celebration and retry when Home becomes current. Add a test that emits while a route is on top, then pops.
- **major** `home_mascot_slot.dart:49`. `ModalRoute.isCurrent` is true for the shell route even while the user is on another tab. The slot lives in an `indexedStack` branch that stays mounted offstage, and the provider is watched while offstage. A salary SMS landing while the user is on Insights, Money or Zaghlol opens the sheet over that tab ("never over another screen or mid-task"). Required: also gate on the Home branch being active. Check `StatefulNavigationShell.currentIndex == 0`, or use `TickerMode.of(context)`. Defer instead of dropping (see above). Add a test with another tab selected.
- minor `home_mascot_slot.dart:34`. `_shown` is per `State`. `paydayCelebrationProvider` is a non-autoDispose `StreamProvider` that keeps its last value, and `build` calls `_celebrate(ref.read(...).value)`. If the slot is ever remounted in a session (rebuild of Home, locale change), the same txn can open the sheet again. Persisted marks do not help because the provider does not re-run. Required: keep the "shown this session" set in a provider, or clear the emitted value once consumed. FU-398.
- minor `payday_celebration.dart:84-92`. If the newest fresh candidate is not income or is deleted, the loop silently goes to the next one. Fine. But `all` marks every candidate, so a fresh salary whose txn lookup throws is never retried. Low risk; noted.
- nit `app_ar.arb`: `voiceLoggerSaved` is probably unused now (the voice screen uses the toast). The old `mascotPaydayLine` was removed in both locales. Prune the unused keys. FU-399.

AC to test map (read the provider and sheet tests only by name; they pass): new SMS salary once, restart not again, old salary, cash on/off, USD amount -> `payday_celebration_test.dart`. Sheet ar/en, per-day hidden, buttons, reduce motion -> `payday_sheet_test.dart`. Goldens ar/en light/dark -> `payday_sheet_golden_test.dart` (not run). **Missing:** any test of the route-not-current or other-tab path (the two majors).

## T-295 Saved! toast (C2) - CHANGES_REQUESTED

Plumbing is right: one `showSnackBar` path, `clearSnackBars`, `persist: false`, 2.5 s, Undo kept (`onUndo`), one `play(saved)` from `didChangeDependencies`, reduce motion gives one tick. It is called from the Add flow only for a new, non-transfer add (so not for edits), from voice, and from review "Keep". It is not called from the bulk or background paths I traced (accept, swipe, ingestion). Money uses `MoneyFormat` in the transaction's currency, and the line shows only when remaining > 0.

Findings
- **major** `app/lib/core/ui/z_saved_toast.dart:23-60` (design note in T-295). The "Add button never covered" criterion is asserted on a false premise ("the Scaffold moves the FAB up"). The shell has no FAB: `app_shell.dart:127-155` builds a `Scaffold` with no `bottomNavigationBar` or FAB. The bar and the raised Add circle (`addRaise` 34) are laid out by `_ShellLayout` over the Scaffold body. A floating `SnackBar` with no margin is positioned at the bottom of the Scaffold that shows it. For the shell Scaffold that is over `ZBottomBar` and the Add circle. For a page Scaffold it still sits within 34 px of the bar, where the raised Add circle overlaps its centre. Required: set `SnackBar.margin` (bottom = bar height + `addRaise` + gap, using the same measurements the shell uses, or reserve it in the shell), or place the toast in the body slot. Add a widget test that renders the toast inside `ShellScaffold` and asserts the toast rect does not intersect the Add button rect. The current tests and goldens render the snackbar in isolation. I could not verify on device.
- minor `voice_logger_screen.dart:~80-100`. The budget lookup is awaited before `Navigator.pop`, so the voice screen stays up while `budgetScreenDataProvider` loads. Fast in practice; no timeout. A multi-draft save now says only "Saved!" with no count (the count string was dropped). Acceptable, but confirm the copy with the PO. FU-400.
- minor `transaction_edit_screen.dart` (new block before `navigator.pop`). The toast is shown through the root `messenger` captured before the pop. It is not shown for the salary path. T-295's scope allowed that, but the cash-salary add then gets no feedback besides the T-294 sheet (which can be lost, see T-294 majors). Fine once those are fixed.
- minor: the remaining-budget line may lag one cycle-cache refresh (documented by the builder). Acceptable.

AC to test map: with and without the budget line, Undo kept -> `z_saved_toast_test.dart`, `transaction_edit_screen_test.dart` (pass). "Not shown for bulk/background" -> only indirect (callers). **Missing:** the Add-button non-overlap test. Goldens ar/en light/dark -> `saved_toast_*` (not run).

## Follow-ups
- FU-397 (T-293 owner): wire `ZHaptics.enabled` and `ZHaptics.reduceMotion` to the settings.
- FU-398 (T-294 owner): session-scoped "already shown" set for the payday sheet.
- FU-399 (T-294/T-295 owner): remove unused l10n keys (`voiceLoggerSaved` and similar).
- FU-400 (T-295 owner): the voice multi-draft toast count and the budget lookup timeout.

## Verdicts
- T-293: APPROVED
- T-294: CHANGES_REQUESTED (2 major)
- T-295: CHANGES_REQUESTED (1 major)

Unverified: Kotlin and Swift compile, the Android unit test, all goldens, real snackbar placement relative to the Add button, device haptic feel.

## Delta re-review (fix83)

Scope: `fix/fix83a` (T-294) and `fix/fix83b` (T-295) against `review/batch-83`. Tests: `flutter test -x golden test/features/mascot test/app test/core/ui test/features/voice` gives 339 passed, 0 failed.

### T-294: APPROVED
- Double celebration: no path celebrates twice in a session. `paydayShownThisSessionProvider` is a session-scoped provider, so it survives a slot remount. The id is added to it and the stored mark is written before `showPaydaySheet`, in the same frame. Kill window: if the app dies after `shown.add` but before the fire-and-forget `markPaydayCelebrated` write completes (a few ms), the salary celebrates once more on the next launch. This is acceptable because it is a rare, one-time repeat and the opposite failure (never celebrating) is worse. The provider stream also leaves the picked salary unmarked until the sheet opens, so a salary that is picked but never shown stays eligible.
- go_router: `StatefulShellRoute.indexedStack` (`app_router.dart:98`) wraps each inactive branch in `Offstage` plus `TickerMode(enabled: isActive)`. `TickerMode.valuesOf` therefore flips to false for an offstage Home branch and back to true on tab return. The call registers an inherited dependency, so `didChangeDependencies` fires on the switch and the pending celebration opens. `ModalRoute.of` likewise notifies when `isCurrent` changes (route popped back to Home).
- Rebuild loop: none. `_schedule` is guarded by `_scheduled`, and `didChangeDependencies` only schedules a post-frame callback that does not call `setState`. `_pending` is cleared before the sheet opens, so opening the sheet (isCurrent -> false) cannot retrigger it. The AppLockGate `TickerMode` (`app_lock_gate.dart:174`) also defers the sheet while the app is locked.
- Findings:
  - minor: `markPaydayCelebrated` swallows all errors via `catchError((_) {})`. A failed write silently re-celebrates after a restart. Acceptable, no action needed.
  - nit: `_pending` holds only the latest salary. If two paydays arrive while Home is hidden, the earlier one is dropped and was never marked, so it stays eligible on a later pick. Harmless.

### T-295: APPROVED
- Toast margin: `savedToastMargin` = safe-area inset + `barHeight` + `addRaise` + `sm`, with a start/end margin of `md`. This lifts the toast above the bar and the raised Add circle. Voice multi-draft: the title uses `voiceLoggerSaved(count, TxnFmt.count)`, so digits follow the locale, and a single draft keeps "Saved!" plus the budget line.
- Ordering: `pop()` now runs before the async budget lookup, so the dropped `mounted` check is safe. Only `messenger`, `container`, `l` and `lang`, all captured before the pop, are used afterwards. This fixes the earlier lost-toast case when the screen was disposed during the lookup.
- Findings:
  - minor (FU-402): `barHeight` is a fixed token. At 1.3x text scale, if the bottom bar's labels grow it, the toast can overlap the bar by the growth amount. It is not blocking. Follow-up: derive the lift from the measured bar height, or confirm the bar is height-capped.
  - nit: `title` is a new `showSavedToast` parameter with no test beyond the voice test. Fine.

### New follow-ups
- FU-402 (minor): saved-toast lift is a constant, not the measured bar height at larger text scales (owner: T-295 follow-up or shell polish).
