# Review — batch 9 (`batch/2026-11-11-9`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus), also acting as security-privacy-reviewer for the correctness/security overlap of the two C4 tasks (a separate Opus security reviewer covers T-040 and T-184 in depth) |
| Date | 2026-11-12 |
| Batch head | `e7bcdb2` (merge of T-077) |
| Scope | T-040 (C4 SMS ingestion), T-184 (C4 billing/entitlements), T-021 (C3), T-077 (C3). T-182 and T-047 were reviewed earlier and are not re-reviewed here |

| Task | Diff reviewed | Verdict |
|------|---------------|---------|
| T-040 SMS receiver | `origin/task/T-047-capture...origin/task/T-040-receiver` (`9913bdd`) | **APPROVED** |
| T-184 Seat service | `origin/task/T-182-seat-proof...origin/task/T-184-seat-service` (`b4b7bb7`) | **APPROVED** |
| T-021 Diagnostic log | `origin/main...origin/task/T-021-diag-log` (`2932614`) | **CHANGES_REQUESTED** (1 major) |
| T-077 Bulk edit/undo | `origin/main...origin/task/T-077-bulk-edit` (`6bb0bd1`) | **CHANGES_REQUESTED** (1 major) |

**What I checked myself (in this workspace):**
- `flutter test` on `test/features/transactions/application/bulk_edit_test.dart`, `test/core/logging/diag_log_test.dart` and `test/ingestion/spike_guard_base_test.dart`: 41 tests, all pass. `flutter analyze` on the T-021/T-077 files: clean.
- `dotnet test Zaghlol.Application.Tests --filter Seat`: 132 tests, all pass.
- CI evidence:
  - T-184: GitHub backend-ci on the batch branch (run 43108477267, PostgreSQL 17 Testcontainers) is green, including Infrastructure 956/959. The 3 skipped tests are App Store live/recorded vectors, not seat tests. The PC runner only ran the design-note commit `7201577`.
  - T-040: `ci/T-040` app-ci is green on the head `9913bdd`. `sms-spike` passed on API 26, 30, 34 and 36 on `2faad0f`: receiver test OK, slot 0, inbox rows 3/3, spoofed `am broadcast` denied. After `2faad0f` only tests, docs and the NoSms manifest `tools:ignore` changed. The PC runner on `76680a0` is FAIL, but only on host-load benchmarks (categorizer p95, FTS search p95, guard perf); `android-unit` and `android-lint` are green.
  - T-021: the PC runner is PASS on `2932614`.
  - T-077: there is no runner result for `6bb0bd1`. The batch app-ci run was still in progress when I checked.

---

## T-040 — SMS receiver (C4, SMS ingestion) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|---|---|---|
| Personal SMS leaves no file | PASS | `CaptureIntakeTest.personalSmsLeavesTheWholeRootByteIdentical`, `.anOtpFromAKeptSenderLeavesNoTraceEither`, `CaptureRuntimeTest.aPersonalSmsThroughTheRuntimeTouchesNothing`; device `SmsReceiverEmulatorTest#armed`, which checks that the dataDir listing is unchanged, on 4 API levels |
| Bank SMS creates one spool entry | PASS | `CaptureIntakeTest.aBankSmsIsOnePriorityEntryWithEveryRecordField` checks for exactly one `.bin` on disk (since `6671082`); `SmsCaptureScenarioTest`; device `#armed` |
| Multipart message assembled once | PASS | `SmsAssemblerTest` (array order with decreasing timestamps, 6-part Arabic), `SmsCaptureScenarioTest.theLongBodyNeedsAtLeastSixUcs2Parts`; device: the long UCS-2 body arrives once and whole |
| Typed `AndroidGuardChannel` | PASS | `GuardRuntimeTest.androidGuardChannelWiresAreExactlySmsAndNotification`, `CaptureSourceScanTest.noCaptureGuardDecideOutsideTheGuardPackage`; `GuardRuntime.decide` takes only the enum |
| Writer codes / guardState table | PASS | `GuardAdaptersTest` (full mode × user-state table, code-only errors, input zeroed); `CaptureRuntimeTest.theUiHostWritesTheGuardConfigAndTheHeadlessHostCannot` |
| SMS reserve; status coalescing | PASS | `SpoolStoreTest` (400/401, byte reserve, notifications to 500); `CaptureStatusStoreTest` (burst = 1 write, first fact at once, window) |
| Receiver only in `*Sms`, `BROADCAST_SMS` | PASS | `CaptureSourceScanTest` manifest/source-set tests; `check-sms-spike-placement.sh` in app-ci; device spoof denied |
| DoD: no raw SMS in logs | PASS | `CaptureCanaryTest.canariesNeverLeak`, the source scans, the app-ci grep over `src/sms`, the device logcat canary scan |

I traced the code paths:
- `SmsReceiver.onReceive`: no I/O on the main thread; malformed PDUs give an empty list; `goAsync` is followed by `finish()` exactly once (`BoundedDispatch`, which also covers throws and rejection).
- `CaptureIntake.process`: a non-rate-limited drop writes nothing; a refusal still triggers `afterWrite` once per broadcast; a write failure is swallowed and enqueues nothing; a Guard defect fails closed.
- The reserve check sits after `FULL` and before the generic checks.
- Coalescing never defers a new fact, and the first alert in a process always writes, because `lastWriteMono` starts null.
- `LiveEnqueueGate` only skips an enqueue while a run is `ENQUEUED`/`BLOCKED`. WorkManager sets `RUNNING` before `doWork`, so an entry written before the check is always drained.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 40-1 | minor | `docs/04-tasks/tasks/T-040.md` (negative proofs 6b and 14) | Proof 6b (batch d) and the re-run of proof 14 (batch c, status still `RUNNING` on the runner) have no recorded result. Reading the code, both mutations would turn their tests red: `aNewFactIsWrittenAtOnceInsideTheWindow` asserts `ops.opens == 2` after the first rate limit, and `aBankSms…` asserts exactly one `.bin`. | Record the runner results when the runner is back (follow-up; not blocking). |
| 40-2 | minor | `app/android/app/src/main/kotlin/app/zaghlol/platform/capture/CaptureIntake.kt:119-124`, `GuardRuntime` base load | In staging/prod `*Sms` builds every SMS is dropped with `config_invalid` until T-036 bundles the base, and a `config_invalid` drop writes no status, so nothing tells the user that SMS are being missed. This is disclosed and fails closed, but the catch-up then depends only on the watermark. | Follow-up for T-036/T-047: show something in capture health when the Guard mode is `INVALID`, so a broken base can't be silent in a release build. |
| 40-3 | nit | `app/android/app/src/main/kotlin/app/zaghlol/platform/capture/SmsCapture.kt:56` | `installForTest` is a production-dex hook that reroutes the real receiver. It can only be reached in-process, so the risk is low. | Optional: fence it to debuggable builds (`BuildConfig.DEBUG`) in T-043, which touches the same file. |

PO Q1 (80 % SMS share) is still open; the code keeps it behind one constant (`SpoolPolicy.SMS_SHARE_PERCENT`), as asked.

---

## T-184 — Seat service (C4, billing/entitlements) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|---|---|---|
| FR-GOLD-08: one holder under 20 concurrent moves | PASS (CI) | `SeatServiceTests.FrGold08TwentyConcurrentMovesLeaveExactlyOneHolder`, `…FirstVerifiesBindExactlyOnce`. The lock order is purchase `FOR UPDATE` → seat `FOR UPDATE`, which also serialises seat-row creation |
| R3-4 whole hour and boundary | PASS | `SeatClockTests`; `R34TheCooldownBoundaryIsTheStoredWholeHourExactly`; `SeatClock.CooldownRunning` uses only the stored `next_move_at` |
| D-58 second reclaim is an ordinary move | PASS (CI) | `D58ASecondReclaimAfterAccountDeletionAndRelink…`; `MarkAttachReclaimUsedAsync` is conditional (`IS NULL`) |
| R3-4 claimants: cap 3, 7 days | PASS (CI) | `R34AFourthClaimantReplacesTheOldest…`, `R34ClaimantsOlderThanSevenDaysAreIgnored`. I checked the `AddClaimantAsync` loop bound by hand: it keeps 2 others plus the caller |
| R4-4 plan-change table (4 cells) | PASS (CI) | `R44ThePlanChangeTableOfAnAccountLinkedPurchase` (4 cases), `SeatRulesTests` V5–V7 |
| D-55/D-63 rebinds | PASS (CI) | `D55…`, `D63AMatchOnElementZeroIsNeverARebind` (`MatchAsync` requires `position >= 1`), `D63AThirdRebind…` |
| D-65(a) over cap | PASS | `D65a…` (restore; sign-in × trust × cooldown); rules S5/S6/S7 |
| R5-2 trust only through the capability | PASS | `R52*`; `AppAttestVerifiedTests` (IL scan, internal constructor, sealed class). Trust only goes false → true (`seat_key_trusted OR @trusted`) |
| R5-4 support trio | PASS (CI) | `R54*` (4 tests); the hash comes from the target's claimant entry and is NULL on a move back; the trust flag is read from the target install now |
| R4-1(1) hash after a rebind is the caller's key | PASS | `R411TheSeatHashAfterARebind…`; L-1: `SeatKeyHashAsync` refuses position ≥ 1, and holder/claimant hashes come only from `SeatKeyHashForHolderAsync` |
| Exactly one `purchase_events` row per outcome | PASS as amended (see 184-1) | `EveryCellWritesTheDocumentedOutcomeAndEventRows` (24 cells, asserts one row or none per cell) |
| Accepted residual 1 bounded | PASS (CI) | `Residual1ASignInChain…`, `Residual1FromAtTheCap…` |

I traced the code paths:
- `SeatRules` matches the design-note table cell by cell; the first match wins and P2 comes before eligibility.
- `ApplyAsync` for each action:
  - Rebind keeps the window and appends to `recent_rebinds`.
  - An over-cap rebind restarts the window and leaves `recent_rebinds` unchanged.
  - The `basic` proof survives a rebind.
  - The caller's claimant row is deleted when it takes the seat.
- Registration hashes before taking the lock and decides against the locked value. A mismatch writes nothing.
- The support path never writes `recent_rebinds` (no ops_rw grant).

### Builder-flagged points, judged
- **No event row for no-ops:** accepted. The `cause` CHECK has no no-op seat cause, and §4.3 says a refusal writes nothing that affects Gold. The callers' own `verify` and `restore` events cover the request. The AC text should match (184-1).
- **The Google successor doesn't inherit `device_key_hash`:** accepted. The hash is `HMAC(K_seat, purchaseId ‖ pk)`, so the predecessor's value can never match on the successor, and the server can't re-key it without the public key. It is written again by the holder's next keyed verify, restore or sign-in (V3/R2/S2 refresh). Until then, a same-iPhone rebind on the successor falls back to an ordinary move under the cooldown. This is rare (an iOS holder of a Google purchase), documented in backend-api §4.3 and backend-schema, and fails closed.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 184-1 | minor | `docs/04-tasks/tasks/T-184.md` (AC "Every outcome writes exactly one `purchase_events` row") | The AC text still says "every outcome", but the built behaviour (§6 of the design note, backend-schema) is one row per change and none for a no-op. | Lead: amend the AC to "per the §6 table" when closing the task. No code change. |
| 184-2 | minor | `backend/src/Zaghlol.Application/Seats/SeatService.cs:193`, `:202` | The support primitive trusts `request.MoveBack` as proof that the target is the move-back target. It cannot check this itself (design note §7(c)). A wrong flag from T-186 would allow a move to any install, with the key cleared. | Follow-up for T-186: derive `MoveBack` from the audit row inside the same transaction and test that a non-claimant target without a matching move-back record gets `NotEligible`. |
| 184-3 | minor | `backend/src/Zaghlol.Application/Seats/SeatService.cs:85-99` | Successor inheritance copies the seat but not the predecessor's pending claimants. A claimant waiting on the old token loses its 7-day entry, and with it its support eligibility. The spec doesn't address this. | Follow-up for T-132/T-186: decide whether claimants carry over; if not, say so in backend-api §4.3. |
| 184-4 | nit | task branch CI | The PC runner only ran the design-note commit, and the code commits were checked through `ci/T-184` and the batch backend-ci. That is acceptable for this round. | None. |

---

## T-021 — Redacting diagnostic log (C3) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|---|---|---|
| Free-text fields rejected at compile time | **FAIL in part** (see 21-1) | The "compile-time barrier" group (probes for a `String` code, a `String` field and a `String` key) is good, but a public factory builds a `DiagCode` from any runtime string |
| Ring buffer trims correctly | PASS | The "ring buffer" group: 2000 rows, the 7-day edge, prune after each append |
| DoD | PASS | analyze clean, runner PASS, sentinel tests (SMS, key, `toString`), `debugPrint` muted |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 21-1 | **major** | `app/lib/core/logging/diag_code.dart:18-19` (also `diag_exporter.dart:29`, `diag_field.dart:112-114`) | `DiagCode.tryFromStored(Object?)` is a **public** static that builds a `DiagCode` from any runtime `String` matching `^[A-Z][A-Z0-9_]{0,63}$`. So `DiagEvent(code: DiagCode.tryFromStored('CARD_4111111111111111')!)` and `DiagField.errorCode(DiagCode.tryFromStored('EGP_1234_50_PHONE_01012345678')!)` both compile and are stored. A card number, phone number, amount or an upper-case hex key fits the shape. This breaks the task's central claim ("instances exist only as `static const` entries of `DiagCodes`"; also stated in error-handling-and-observability §3.1 as built), so self-check §6 fails. The exporter also checks only the shape for the row `code`, not membership in the registry. | Make the stored-code re-reader unreachable from outside `core/logging`: keep it library-private, for example put the exporter's validation in `diag_code.dart` or use a `part`. Validate the row `code` on export against the `DiagCodes` registry set, and keep the shape check only for `error_code` values from `SafeException`. Add a probe to the compile-time barrier group showing that `DiagCode.tryFromStored(...)` (or whatever replaces it) can't be called from a file outside the library. |
| 21-2 | minor | `app/lib/core/logging/diag_error_handlers.dart:27-35`; `app/lib/main.dart` | `installDiagErrorHandlers` and `DiagLogger` have no call site: not in `main`, not in the headless ingestion isolate, and no provider. The Settings → About export screen and the native (Swift) bridge are not built either. The builder flagged this. It is acceptable under "Affected components: `app/lib/core/logging/`", but nothing owns the rest. T-039 also expects T-021 to record capture status counts as `DiagEvent`s, which is not done. | Lead: add follow-ups with owner tasks for the main/headless wiring plus provider, the Settings → About «بيانات تشخيص» view/share screen (both locales, RTL), the native diag bridge, and capture-status events. |
| 21-3 | minor | `app/lib/core/logging/diag_field.dart:72-157` | `DiagLogger.record` never throws, but building a `DiagField` does (`DiagFieldException` on a bad shape). A caller logging an unexpected institution code (lower case, or more than 16 characters) therefore throws in its own code path, against "diagnostics must never crash the app". | Add `tryInstitution`/`tryTemplateId`/`tryVersion` (returning null) or a dropping builder, and say in the dartdoc which one callers should use. |
| 21-4 | nit | `app/lib/core/logging/diag_error_handlers.dart:27-35` | Replacing `FlutterError.onError` and `debugPrint` unconditionally also hides errors in debug builds. | Consider chaining to `FlutterError.presentError` when `kDebugMode`. |
| 21-5 | nit | `app/ios/Shared/BackupExclusion.swift:117` | `static var handler` is unsynchronised global mutable state. It compiles in Swift 5 mode, but would need `nonisolated(unsafe)` or a lock under Swift 6. | Handle it when the native bridge task installs the handler. |

---

## T-077 — Bulk edit and undo (C3) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|---|---|---|
| 10 selected → all updated and every total changes | **PASS for direct queries, FAIL for the cycle/budget totals** (see 77-1) | `AC1 category change…` checks the per-category sum by direct query; `AC1 account change…` only checks `account_id` (no total); `AC1 delete…` |
| One Undo restores all 10 | PASS | `AC2 category/account/delete undo restores exactly` (snapshot of every column), and undo keeps earlier user categories |
| DoD | PASS locally | 20 tests green, analyze clean; no `double`, amounts never written (`AC1` asserts `amount_minor`/`currency` unchanged on KWD rows) |

The logic is otherwise careful:
- Apply is all or none, and conditional restores never overwrite a later edit.
- Undo has exactly one winner (`deleteById == 1`), and a corrupt image keeps the batch.
- Created or re-pointed rules are undone only while they still point at the batch's category.
- The 24 h boundary is consistent between `apply`, `undo` and `purgeExpired`.

### Builder-flagged point, judged
- **Bulk account move doesn't check currency:** correct as built. Accounts hold several currencies (FR-ACC-06 `account_balances` per currency; `default_currency` is only the billing currency), and a foreign-currency row on an EGP card is normal. The single-edit path (T-074) behaves the same way.
- **It doesn't re-pair transfers:** a paired `is_internal` row moved to another account keeps `is_internal = 1` and its pair. This matches T-074's single edit. Minor follow-up 77-3.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 77-1 | **major** | `app/lib/features/transactions/application/bulk_edit.dart:129-226` (apply), `:234-281` (undo), `:331`, `:346`, `:359` (`updatedAt: Value(r.upd)`) | Domain §14 step 5 ("Emit events") is not met, and Undo **rewinds `updated_at`**. The design note says watchers cover it, but they don't: the `cycle_summaries` cache serves closed cycles until it gets a `TransactionsChanged(accountIds, cycleKeys)` (domain-algorithms §1 "Cache"; T-051 note §6 names **T-077** as an emitter that must include affected cycles, also for expenses whose offset links change, BR-XFR-07). Budget alerts (BR-BUD-02) and the mascot also run only after that event. The fallback, `CycleCacheInvalidator.sweepSince`, finds changes by `updated_at > lastForeground`, and Undo puts back the old `updated_at`, so an undone bulk edit is invisible to it even after resume. Result: re-categorising, moving or deleting last month's rows (and undoing that) leaves stale per-category and per-account cycle totals and missed budget alerts, which breaks the "every total changes" AC on the budget/charts surfaces. | (a) `apply` and `undo` each produce the `TransactionsChanged` data for what they touched: the old and new `accountIds`, and the cycle of every affected row plus the expense cycles of any offset links whose source was deleted or restored. Return it in `BulkEditResult`/`UndoResult` (as `IngestResult.event` does), or publish through an injected bus port, so T-079 or the composition root can publish it. (b) Undo writes `updated_at = now` (undo time) instead of the old value; the conflict check still uses the batch stamp. (c) Tests: the event's cycle keys and account ids for each of the three kinds and for undo, and that `sweepSince(beforeUndo)` finds the undone rows. Adjust the "restores exactly" snapshots to exclude `updated_at`. |
| 77-2 | minor | `test/features/transactions/application/bulk_edit_test.dart:126-133` | `AC1 account change updates 10 rows` asserts `account_id` only; no per-account total is checked, which the AC asks for. | Add a per-account sum before and after (both accounts). |
| 77-3 | minor | `bulk_edit.dart:184-200` | Moving one half of an internal transfer keeps `is_internal`/`transfer_pair_id`. If both halves end up on the same account, or the move breaks the pairing logic, totals can be wrong, and nothing tells the user. The single edit (T-074) has the same behaviour. | Follow-up for the transfer-pairing owner: decide whether an account change re-runs pairing; T-079 could warn when the selection contains paired rows. |
| 77-4 | minor | process | There is no PC-runner result for `6bb0bd1`, and the task file has no AC→test map or self-check statement (self-check §7). | Builder: add both in the fix round. |

---

## Security notes (overlap only; the dedicated Opus reviewer goes deeper on T-040 and T-184)
- **T-040:** no logging in `platform/capture` or `src/sms`, redacted `toString` on every carrier type, and canaries through assembler → intake → store → status with failing ciphers. The receiver is protected by `BROADCAST_SMS` (spoof denied on 4 API levels), not direct-boot aware, and never aborts the broadcast. Decisions happen in memory before any write. Nothing blocks.
- **T-184:** the capability can't be forged (sealed class, internal constructor, IL scan); trust only goes false → true; only element 0 is ever written to a seat (L-1); KMS failures roll back. Nothing blocks.
- **T-021:** 21-1 is the privacy-relevant finding (a shape-limited free-text channel into a log the user may share).

## Blockers and majors (fix round)
| # | Task | Lane | Summary |
|---|---|---|---|
| 21-1 | T-021 | app core | The public `DiagCode.tryFromStored` lets a runtime string become a diag code. Make it library-private, check the row code against the registry on export, and add a probe test |
| 77-1 | T-077 | app core | Bulk apply/undo emit no `TransactionsChanged`, and undo rewinds `updated_at`, so the cycle cache and budget alerts go stale. Return or publish the event data, set undo's `updated_at` to now, and add tests |

Both are on the app-core lane, so one fix agent can take both. Both are probably above 30 lines, so they need a delta-only Sonnet re-review.

## Checklist (batch)
- [x] `flutter analyze` clean on the touched Dart (T-021, T-077); T-040 analyze/lint green on the runner and on GitHub
- [x] Tests added and passing (Dart 41 run here; Application seat 132 run here; Infrastructure seat tests green in batch backend-ci; Android unit tests green on runner/GitHub; T-040 device test green on API 26/30/34/36)
- [x] RTL + LTR: no UI in this batch
- [x] No hard-coded strings (no UI)
- [x] No `double` money; T-077 never writes amounts
- [ ] No sensitive data in logs: T-040 and T-184 yes; T-021 has the 21-1 escape hatch
- [x] Stays within each task's scope (T-040's spike removal follows Lead decision 3)

## Re-review 77-1 (delta)

Scope: commit 2d576f8, `bulk_edit.dart` and `bulk_edit_test.dart` only. Ran `bulk_edit_test.dart` on 2d576f8: 29 passed.

**Verdict: APPROVED**

Checked and holding:
- Event content: apply and undo name old and new account ids on an account move, the cycle key of every affected row, and both ends of every offset link on delete (apply and undo). Tests cover each case.
- Publish happens after `inTransaction` returns, so a rollback emits nothing. Undo with nothing restorable emits no event.
- Undo still checks `updated_at == batch time` before restoring, then stamps `now`. A later edit still blocks it (tested), and the resume sweep now finds undone rows (tested with a seeded cycle summary).
- All-or-nothing and "never destroy on doubt" are untouched: the event code only reads, and the restore guards are unchanged.

Blockers: none. Majors: none.

Minors:
- 77-1a: `loadSchedule` defaults to payday on the 1st and `events` to none, and no production code constructs `BulkEditUseCase` yet. When the provider is wired (T-051/T-077 UI task), pass the real schedule and the bus, or make `loadSchedule` required. A default 1st would silently name the wrong cycles for users with another payday. Follow-up for the wiring task.
- 77-1b: In the review worktree `/home/claude/wt-batch9` the index holds staged changes that revert 2d576f8 (6 files). Running tests there does not exercise the fix. Do not commit from that index; run `git restore --staged --worktree .` first.

## Lead delta check 21-1 (2d576f8)

`DiagCode.tryFromStored` is removed. `DiagCode.fromRegistry` returns only an existing `DiagCodes` constant and never builds a new instance, and the exporter drops any stored row code not in `DiagCodes.all`. The changed tamper test checks that an unregistered `CARD_4111…` row is dropped. 21-1 is resolved. Minor: nothing ties `DiagCodes.all` to the constants, so a test should check they match (FU-113). Verdict for T-021: **APPROVED**.
