# Batch 84 review (C2 only: T-296, T-297, T-298, T-299)

Reviewer: code-reviewer (Sonnet). Diff `origin/main...batch/2026-11-26-84`. Production diff read; Kotlin traced by hand (not compiled).
Checks run: `flutter analyze` clean. `flutter test -x golden` over test/core/ui, test/features/mascot, test/features/ingestion/presentation (296 pass) and onboarding, settings, capture, transactions/presentation, app, export_import, accounts, recurring (1092 pass). Goldens, Kotlin tests and iOS not run.

## T-296 — ZEmptyState sleeping bird, review list detective header: APPROVED
- AC map: shared `ZEmptyState` (z_empty_state_test + golden ar/en light/dark), review header (review_header_test + golden), transactions `_Message` and review `_Empty` now delegate to it, bills and Money tab empty add an inline sleep bird. All present.
- One bird per screen holds: bills empty requires suggestions, upcoming and subscriptions all empty, so the detective suggestion card and the sleep bird never co-exist. Review header counts `visible` (not the filter `shown`), matching the "All" pill. The bird is decorative (no semantic label) and the title is beside it. No button is covered.
- Arabic plural: =1 "رسالة واحدة محتاجة نظرة", =2 "رسالتين محتاجين نظرة", few/many/other forms are correct Egyptian. English has one/other. Digits go through `digitsModeProvider`.
- Minor (nit) `app/lib/core/settings/settings_providers.dart:53-55`: the new `hapticsEnabledProvider` was inserted between the `hideAmountsAppProvider` doc comment and its declaration, so the `/// The raw hide_amounts.app setting` comment now documents the wrong provider (belongs to T-298). Move it.
- Nit `money_tab.dart:16`, `bills_screen`: import ordering (mascot import sits between core imports); `dart format` passes, so cosmetic only.

## T-297 — WorkingBird on scan, re-scan, statement import: APPROVED (one minor)
- `WorkingBird` loops only while `busy`, settles to the idle pose when work ends, plays `oops` plus the oops haptic once on `failed` (initState and the false-to-true edge in didUpdateWidget; no repeat on rebuild). Reduce motion is delegated to `ZaghlolAvatar` (still image). The avatar is not wrapped in a gesture widget, so it never takes taps. Locale strings exist in both ARBs.
- One bird per screen: the Android setup scan card now holds the working bird and the bottom `OnbMascot` is pinned to `tourGuide` (the failed-phase `oops` at android_setup.dart:503 is a different phase, so no double). The Settings re-scan panel shows a bird in the running and failed states only. The statement import overlay replaces the spinner; the list below has no other bird.
- Minor `statement_import_screen.dart`: T-297 item 4 says errors switch to `oops` plus haptic. The re-scan panel does that, but the import screen's failure paths (unreadable, save failed, OCR unavailable) still show only the banner, and the Android setup failed phase (android_setup.dart:503) uses `OnbMascot` without the oops haptic. Follow-up FU-401.
- Nit `statement_import_screen.dart:541`: the overlay wraps the bird (labelled "Zaghlol is working on it") inside a `Semantics(label: exportsImportParsing, liveRegion)`, so a screen reader may read both. Set `semanticLabel` empty or exclude the bird's semantics there.
- Import placement nit: `import '../../mascot/…'` was inserted above `dart:` imports in capture_settings_screen.dart, statement_import_screen.dart and android_setup.dart (inside the header comment block). Compiles, but violates import order; move down.
- AC "Ask / backup / restore already compliant" is claimed by the task, not changed here; not verified.

## T-298 — Vibration setting, hapticsSyncProvider, measured bar height: APPROVED
- Writers: `grep "ZHaptics.(enabled|reduceMotion) ="` in `app/lib` finds only `haptics_sync.dart:11-12`. `main.dart:246` watches it once in `_LocalizedApp.build`. The Preferences switch writes `Settings.hapticsEnabled` (default true) via `_write`. Fails open to enabled while the setting loads (haptics are not sensitive), which is fine.
- `ShellBarHeightReporter`: `build` schedules one post-frame callback per build. `_measure` calls `report`, which only sets state when the value differs, and nothing watches the provider (`savedToastMargin` uses a one-shot read), so there is no rebuild or frame loop (a post-frame callback does not itself schedule a frame). dispose resets to null via microtask, guarded by `ref.mounted`. No ProviderScope falls back to the token. At 1.3x text the margin uses the measured height (saved_toast_in_shell_test has the 1.3x case).
- Minor `z_saved_toast.dart` `_measuredBarHeight`: `on Object` catch swallows everything, not only the missing-scope `StateError`. Narrow it to `StateError`.
- Minor: a stale non-null height remains if the user is on a route where the bar is hidden but the reporter stays mounted (e.g. the keyboard shrinks the bar); the toast margin reads the last measured value, which is the correct visible bar, so acceptable.
- AC map: switch + settings key (settings_repository_test, prefs goldens ar/en light/dark), sync provider (haptics_sync_test), shell height (saved_toast_in_shell_test). Present.

## T-299 — Android OcrMerger small amounts, haptics cancel on pause/stop: APPROVED (Kotlin unverified by compiler)
Hand-trace of `OcrMergerTest`:
- Test 1: latin "Total Amount" (strong, 2 words) and "85" (strong, no letters) both match Arabic idx 0 with overlap 1.0; the Arabic line (0.65, majority Arabic) passes the gate. Loop i=0: `arabicWords` gives "كلمة"; `strongAmountOverlaps`: "85" is not amountLike but `smallAmount("85")` is true via a different line holding "total" on the same row (sameRow 30/30 >= 0.5), so overlap >= 0.5 and the Arabic digits are not appended. Result "Total Amount كلمة", no "4812". i=1 is in `appended`, so no extra. Passes.
- Test 2: "Amount 85" holds its own amount word, so `smallAmount` is true; "Total" has no digit tokens. No "4812". Passes.
- Test 3: "Order Reference" / "12": no amount word, so `strongAmountOverlaps` is false and `arabicAmountTokens` appends "4812" to the first line. Passes. `Ref 12` is still not an amount.
- Existing FU-392 behaviour is untouched for tokens of 3+ digits or decimals. Real Arabic amounts are only dropped when a strong ML Kit line on the same box carries a 1-2 digit whole number AND an amount word on that line or its row (e.g. "Total Items 3" overlapping an Arabic line that holds a real total). Narrow, and the ML Kit digits are kept anyway.
- HapticsRegistration: `cancel(context)` uses `applicationContext`, the `Cancellable` seam catches RuntimeException and is unit tested (3 cases); `unregister(messenger, context = null)` default keeps other callers compiling. `onPause` and `onStop` call cancel before super.
- Nit `MainActivity.kt:271-279`: `onPause`/`onStop` were inserted between the KDoc of the share-announce `onResume` and the `onResume` function, so that KDoc now attaches to `onPause`. Move them above the comment.
- Minor `OcrMerger.kt` AMOUNT_WORDS: the Arabic words are compared exact after `lowercase()`; ML Kit Latin lines rarely carry them, so the Arabic entries are mostly dead. Harmless; note only. FU-402 owns adding "الإجمالى"/"الاجمالي" variants if wanted.

## Findings summary
Blockers: none. Majors: none.

## Follow-ups (owner)
- FU-401 (T-297 lane): oops bird plus haptic on statement import failure and Android setup failed phase.
- FU-402 (T-298 lane): narrow `_measuredBarHeight` catch to `StateError`; fix the misplaced `hapticsEnabledProvider` doc comment; import ordering nits from T-297 and the MainActivity KDoc placement.
- FU-403 (T-297 lane): avoid double screen-reader announcement in the statement import overlay.

## Unverified
Golden tests (excluded by `-x golden`, not run), Kotlin compile and unit tests (CI/PC runner only), Ask/backup/restore bird claims, real-device haptic cancel.
