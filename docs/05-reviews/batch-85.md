# Batch 85 review (T-300, T-301, T-302, T-303)

Reviewer: code-reviewer (Opus), 2026-11-28. Diff `origin/main...origin/batch/2026-11-28-85`.
Local checks: `flutter analyze` clean; `flutter test -x golden test/core test/features/mascot test/features/export_import/presentation test/features/onboarding test/app` = 1788 passed, 1 skipped. Kotlin/Swift not compiled here (CI only).

## T-300 stronger vibrations — APPROVED
- Dart table: every hit >= 70 %; tick -> medium, click/thud -> heavy in the fallback. The «الاهتزاز» switch (`ZHaptics.enabled`) and the system touch-feedback check (`touchFeedbackOff`) are untouched and still run first.
- Android: `createPredefined` is guarded by `SDK_INT >= Q` (API 29); the pre-Q path uses `createWaveform(long[], int)` (API 26, the app's minSdk is >= 26 as the existing waveform call already relies on it). `EFFECT_CLICK=0` and `EFFECT_HEAVY_CLICK=5` are the correct constants. Scale floor 0.7, pulses 30/45/80 ms and amplitude >= 180 match the AC and the unit tests.
- Swift: `intensity()` clamps to 0.7..1.0; sharpness is 0.5..0.8. `.rigid` needs iOS 13; confirm the deployment target (not checked).
- minor (nit) `HapticsRegistration.kt:~116`: the `return false` after the try/catch is now unreachable (Kotlin warning only; no warnings-as-errors found in gradle files). Remove it.
- nit: for a one-beat pattern on a no-amplitude phone `predefinedEffect` ignores `pct`; fine, intended.

## T-301 bird tap retry — APPROVED (fix plausible, not confirmed)
- `rive_mascot.dart:~311-340`: `_loading` guards re-entry; `_handle != null` guard stops a second load; the `Timer` is cancelled before each re-arm and in `dispose`; automatic retries are capped at 3 (`_autoRetries` is never reset, so at most 3 timers per mounted bird); a late result after dispose disposes the handle (`!mounted` branch). Taps retry at most once per tap, only when `_failed` and no load is in flight, so there is no retry storm. The timer callback is `_load`, which re-checks the guards.
- Plausibility: the builder's root cause is by elimination (T-292 moved the preload to after the first frame, and a single failed load was permanent for that mounted widget). This matches "tip changes, bird does not animate" (`_handle == null`, so `apply` is never reached). It does not explain a permanent failure (e.g. a bad `.riv` or a native load error would fail 4 times and stay still), so the PO device check is the real gate. The dev screen now shows the load counters (`loaded / failed / paint`), which will tell the two cases apart.
- minor: `_autoRetries` is not reset after a success, so a later failure of a re-mounted-never case gets no timer retry (tap retry still works). Acceptable.

## T-302 oops bird on failures — APPROVED
- Statement import: `_failureShowsBird` excludes password / wrong-password (FU-401); the save failure shows the bird; the busy bird is wrapped in `ExcludeSemantics`. Android setup shows the `failed` bird when `ScanPhase.failed`. The oops haptic is played by `WorkingBird` on failure only (initState and didUpdateWidget transition), so it fires once per failure.
- FU cleanups: import reordering, `on Object` -> `on StateError` in `z_saved_toast.dart` (a `ProviderScope.containerOf` miss throws StateError; analyze and tests agree), payday_celebration lookup errors leave the txn unmarked (retry later) — behaviour is safe and tested.
- nit: `statement_import_screen.dart` `_failureBird` is a `const` Widget inside a method, fine.

## T-303 dev try-out sections — APPROVED
- Still gated: `about_screen.dart:116` uses `mascotMoodsEnabledProvider` (= `kIsDevBuild`). No new route or entry.
- Payday preview: `showPaydaySheet` only reads `currentCycleOverviewProvider` and the reduce-motion flag. It never reads or writes the celebrated mark or a transaction (`PaydayCelebration('dev-preview', ...)` is a value object). Toasts use `showSavedToast` with no Undo. The haptic buttons call `ZHaptics.play`, so «الاهتزاز» off and reduce-motion rules still apply; the screen says so (`devTryVibOff` / `devTryVibReduce`).
- Strings are all ARB (ar Egyptian, en). Arabic copy is colloquial («اتحفظ», «مفيش», «هتحس»). "Rive" is intentionally the same in both languages.
- minor `mascot_moods_screen.dart:~12`: the new imports are out of order (`../../../ingestion/...` after the relative mascot imports); `dart format` does not catch it and the lint did not fire. Fix when next touched.
- nit: `_usesRive()` infers Rive from probe counters, not the avatar itself, so it can say "Rive" before the first load. Labelled as a probe, fine for a dev screen.

## Blockers / majors
None.

## Follow-ups
- FU-404 (minor): remove the unreachable `return false` in `HapticsRegistration.play`; sort imports in `mascot_moods_screen.dart`.
- FU-405 (info): device check owed to the PO for T-300 (felt strength on an ERM phone and a no-amplitude phone) and T-301 (tap animates; read the dev-screen load counters if it still does not). Confirm iOS deployment target >= 13 for `.rigid`.

## Unverified
Kotlin/Swift compile, goldens (not run, per brief), device behaviour of vibrations and Rive.

### Lead delta check (CI)

- Android lint `NewApi` error: `VibrationEffect.createPredefined` (API 29) was guarded only through a nullable `effect` computed under an SDK check, which lint can't follow. The call is now inside `if (effect != null && SDK_INT >= Q)` (2 lines); the unreachable `return false` after the try/catch (FU-404 nit) is removed. Behaviour unchanged. Re-run in CI.
