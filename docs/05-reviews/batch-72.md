# Batch 72 review (T-254, T-255, T-256)

Reviewer: batch code-reviewer (Opus; code + security, batch holds C4 T-254). Tree: `fae83763` (`batch/2026-11-25-72`), diff `origin/main...fae83763` (main `ac7699a0`).

Checks run in a throwaway worktree:
- `flutter pub get --enforce-lockfile` OK; `flutter analyze` (app): no issues.
- `flutter test -x golden test/features/capture test/core/platform test/features/gold test/core/backend`: 654 passed.
- `packages/zaghlol_parsing` `dart test`: 1671 passed.
- `tools/lints`: 636 files, 0 issues. `dart format` on the 9 changed Dart files: 0 changed.
- Not run: Android unit tests / Kotlin compile (no Android SDK here; app-ci is the gate), `test/core/db` (test-only changes; db-platform covers them), db-platform attestation step (GitHub only).
- Scratch probe (not committed) of the generic reader's signed balance, see T-256 M-1.

## T-254 (C4, native capture hardening) — APPROVED

Production diff read in full (Kotlin, both workflows, ADR-002 / platform-channels text). AC→test map in the task file is complete; the three negative proofs match the core properties (S2, C3, I-5).

Compile read (builder could not compile):
- `BoundedDispatch.run(work, onAbandoned = null, finish)`: the only production caller (`SmsReceiver`) uses named args; tests too. `finishOnce` is now `() -> Boolean`; `abandon` stays `() -> Unit`, so `timer.schedule({ abandon() }, …)` still resolves to the `Runnable` overload as before.
- `SmsCapture.missedRecorder`: `CaptureRuntime.get(context).status` and `AndroidGuardChannel.SMS.wire` exist; `CaptureStatusStore.recordMissed(String, Long, Int = 1)` matches.
- `IntentShareSource.open`: `ContentResolver.openAssetFileDescriptor(Uri, String, CancellationSignal)` (API 19) and `android.os.OperationCanceledException` are correct; `try … catch … ?: return null` parses as intended.
- `ShareActivity`: `EXECUTOR` has no remaining references; `newJob::beginCommit` fits `() -> Boolean`. `ShareWorkers` (pure Kotlin) was compiled by the builder with kotlinc.
- No compile errors found.

Behaviour:
- I-5: `abandon` runs `onAbandoned` only when the timer (or an executor rejection) wins the `done` CAS, after `finish()`. The recorder hands the write to its own daemon thread, so a Keystore stall can't delay later `finish()` calls. Correct.
- C3: `beginCommit` and `giveUp` share the job monitor. Outcome already set → no commit (writer aborted, `UNREADABLE`). Commit in progress → give-up yields. Late worker `finish` after a give-up returns false. Queued-past-deadline shares are refused by the first `checkDeadline`. Correct.
- S1: two daemon workers, queue of 8, `AbortPolicy` → `onRejected` on the main thread finishes the job before `attach` (attach delivers at once). Correct.
- FU-121 048-3: `scanned`/`skipped` reset on restart, so `first = _progress.scanned == 0` is true again; duplicates of this scan's own imports are not counted. Correct.
- FU-050: `--signer-workflow simolus3/sqlite3.dart/.github/workflows/compile_sqlite.yml` matches the signer the T-007 review read from the green run (`docs/05-reviews/T-007.md:31`), and the job runs on `ubuntu-latest` (`/usr/bin/gh` present). The APK regex matches the asset name recorded in T-007/T-190/T-208 (`lib/<abi>/libsqlite3mc.so`). If the signer pin is wrong, db-platform on this batch goes red. That run is the gate; the Lead must confirm it is green before merge.

### Security (T-254)
- **No raw SMS logged:** none of the new code logs anything. The missed record is `(channel, wallMs)` only.
- **Personal-SMS privacy (I-5):** when the budget ends a broadcast, its receive time is recorded before the Guard decided, so a personal SMS can set `firstMissedSmsAtMs`. That is a timestamp only: no sender, no body. It goes to `CaptureStatusStore` (encrypted with `seams.cipher` in `noBackupDir`) and only moves the next catch-up start earlier. The catch-up runs everything through the Guard again. Accepted, Info.
- **No new permissions:** the manifests are unchanged (`READ_SMS`/`RECEIVE_SMS` only in the `sms` flavor).
- **S2 confused deputy:** fixed for the AOSP SMS authorities (`sms`, `mms`, `mms-sms`). `uri.host` already drops a `userId@`, and any userinfo is refused anyway. Remaining gap: see FU-330 (Low).
- **Thread/lifecycle:** all new threads are daemons. Workers never touch the Activity (the job outcome is posted to main). The `CancellationSignal` is per source.

Findings (none block):
- **FU-330** (minor; security Low) `app/android/app/src/main/kotlin/app/zaghlol/platform/share/ShareSource.kt:63`: the authority deny-list misses other Telephony provider authorities (e.g. `sms-changes`, OEM/RCS authorities). Also refuse by provider package: `source.streamProviderPackage == "com.android.providers.telephony"` (the value is already resolved in `IntentShareSource`). Add a test.
- **FU-331** (minor) `ShareIntake.kt:79-80`: because the provider MIME now wins, a CSV whose provider reports `text/comma-separated-values` (the libcore/MimeTypeMap mapping on Android ≤10) or `application/octet-stream` is refused, even when the intent says `text/csv`. Before, the intent type rescued it. Add CSV aliases (`text/comma-separated-values`, `application/csv`, `text/x-csv`) to `ShareClassifier.kindForMime`. Optionally allow octet-stream when the sniff proves PDF/image.
- **FU-332** (minor) `ShareJob.kt:50` `giveUp`: once `beginCommit` is true, nothing bounds the commit. A stalled `writer.commit()` (Keystore `doFinal`) would leave the job with no outcome and the share sheet waiting. Add a second, longer give-up that applies even while committing, or document why commit can't stall.
- **FU-333** (nit) `IntentShareSource.kt:73`: if `createInputStream()` throws, the `AssetFileDescriptor` is not closed. Close it on failure.

## T-255 (C3, core follow-ups) — APPROVED

FU-138 fix read in full (`entitlement.dart:373-384, 626-634`). `tick()` only skips `evaluate()` while `_applying > 0`. The counter is decremented in `finally`, and the skip changes no state. It can't grant Gold or keep it: every Gold check calls `evaluate()` directly, so the gate isn't affected. `onResume`, `start` and the end of `_applyBody` still evaluate ungated. If an `await` inside `_applyBody` hung, the passive tick would stay off, but `evaluate()` awaits the same `_time` and would hang too. No new exposure. The test gates the token write and asserts that no phase is published by a mid-apply tick.

Closure spot-checks (2+): FU-126 true (`Settings.lastForegroundMs` in `settings_keys.dart`/`cycle_app_wiring.dart`; `DiagCodes.resumeFailed` used at `main.dart:222`). FU-144 true (`setupSalaryCreditProvider`, `home_cards.dart:30`). FU-113 is correctly left partly OPEN (native bridge).

- **FU-334** (nit) `entitlement.dart:381`: the public `tick()` exists for the timer and the test. Mark it `@visibleForTesting`, or make it private and test through a fake timer.

## T-256 (C2, parsing follow-ups) — CHANGES_REQUESTED

The FU-051/084/118 dispositions are correct (spot-check: U+2060/U+00AD stripped at `text_normalizer.dart:187-188`). FU-084(a) and FU-118 are rightly left OPEN.

- **M-1 (major, money correctness)** `packages/zaghlol_parsing/lib/generic/generic_parser.dart:1398-1413, 1453`: `_leadingMinus` covers only a sign right before the digits and not glued to a letter. Scratch probe on this tree (generic reader, sender `SOMEBANK`):

  | Body tail | balance.minor |
  |---|---|
  | `Available balance is EGP-500.00.` | **50000** |
  | `Balance: -EGP 500.00` | **50000** |
  | `Balance: - 500.00 EGP` | **50000** |
  | `Balance: EGP -500.00` | -50000 (OK) |

  So an overdrawn balance is still stored as **positive** in common bank formats: a glued currency before the sign, a sign before the currency, and a sign followed by a space. The task (T-256 notes) and CLAUDE.md §2.4 say a signed balance must never become positive. `implementation-status.md` marks FU-078 CLOSED. Required change: in `read`, treat a `-`/`−` in the gap between the anchor and the number as a sign when it directly precedes the number or a currency marker, or is followed only by spaces before the number. Negate when the sign is unambiguous; otherwise return null (no balance). Never return a positive value. A `-` glued after a currency marker (`EGP-500`) counts as a sign. Add the three rows above as tests (they fail today). Keep `REF-500`-style hyphens non-signs only where no currency marker sits before the hyphen.

## Blockers / majors
- T-256 M-1 (major): signed balances in `EGP-500.00`, `-EGP 500.00` and `- 500.00 EGP` forms are still read as positive.

T-254 and T-255: none. Gate for T-254: db-platform (attestation pin) and app-ci (Kotlin compile, Android unit tests) green on the batch run.

Follow-ups: FU-330 to FU-334 (owners: T-254 lane native for 330-333, core lane for 334).
