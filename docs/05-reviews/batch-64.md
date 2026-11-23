# Batch 64 review (T-231, T-232)

Reviewer: code-reviewer (Opus). Ran: `flutter test --exclude-tags golden` on mascot, settings, insights, backup, gold, account (1083 passed); generator run twice (`zaghlol.riv` and `moods.json` byte-identical to the committed files); `verify/check.mjs` 59/59.

## T-231 (C2/C3): APPROVED

- Allow-list (`explorer_allow.dart`) is keyed by screen + kind, with `where` for most entries; each has a reason and is printed in the report ("Allowed" table). No blanket ignore. Real bugs fixed: Apple button hidden on Android (`appleSignInOfferedProvider`, ar+en test with `apple:false`); donut legend and Insights card chip overflow (tests in insights_screen_test, covered_earlier_test). Assertions not weakened.
- Workflow split: `flows` (60 min) + `explorer` matrix of 6 slices (60 min each, fail-fast false); same plan names covered (base-a/b, variants-a/b/c, new). Publishing to `device-shots` retries and uses per-job folders. OK.
- Findings (minor, proposed FU-292):
  - m1 `explorer_allow.dart` (link-transfer dead-tap, the "restore" picker list, the emoji-title `^[^A-Za-z...]{1,6}$` rule) have no `where`, so they cover every control on those screens. Add `where` or document why not.
  - m2 `where: GestureDetector` on Re-scan, Restore and Note matches any gesture area on the screen; narrow to the radio/handle if the explorer label allows.
  - m3 Restore with no Google account and the old-messages options are allow-listed, not changed (the banner already says why). Acceptable; confirm on the next device run.

## T-232 (C3): CHANGES_REQUESTED (one major)

- Generator deterministic (two runs identical to committed bytes), stdlib only, reads the Lab HTML and rig SVG from the repo, no network. Verifier 59/59. Moods screen: `mascotMoodsEnabledProvider` = `kIsDevBuild` (const), row in About gated by it, test at mascot_moods_screen_test.dart:85 asserts off in a plain build; reduce motion honoured (`reduceMotionProvider` or `disableAnimations`).
- **M1 (major)** `rive_mascot.dart` `_RiveMascotState._load` (~line 138): `controller.stateMachine.onStateChanged(RiveMascotProbe.stateNames.add)` runs in every build, including production. `stateNames` is a static list that is never trimmed, so it grows for every state change for the life of the app (looping layers breath/tail/blink change state continuously) and a native callback is registered per mascot. The brief requires the probe to cost nothing in production. Required change: register the listener only when probing is on (a `RiveMascotProbe.recordStates` flag that the integration test sets, or `kDebugMode`/`kIsDevBuild`), and/or cap the list. The `loaded`/`failedToLoad`/`paintFailed` int counters are fine. No data leaks (state names only, nothing logged).
- m4 `ignore_for_file: invalid_use_of_internal_member` widens the file-level ignore; scope it to the `onStateChanged` line when fixing M1.
- m5 `scores.json` and the large `expectations.json` are generated; fine, but note `lab_expect.py` must be rerun when the Lab changes (README says so).

## Verdict
- T-231: APPROVED (minors m1-m3 as FU-292).
- T-232: CHANGES_REQUESTED until M1 is fixed (about 5 lines; Lead delta check is enough). m4, m5 as FU-292.
