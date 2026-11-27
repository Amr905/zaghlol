# Review: hotfix `task/freeze-fix` (start-up freeze after the v7 upgrade)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus; code and security, C4: data migration and start-up) |
| Date | 2026-11-27 |
| Commit / diff | `git diff origin/main...ec40852a`, plus the reviewer fix on top (branch `task/freeze-review`) |
| Verdict | **APPROVED** with the reviewer fix (F-1) included. Without F-1 it was CHANGES_REQUESTED. |

## Acceptance criteria (from the brief)
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Old dangling FK rows don't stop the upgrade. Every row is kept unchanged | PASS | `migration_dirty_fk_test.dart`: v6 to v7 with 4 dangling kinds, in background and foreground modes, byte-for-byte `exactRows` |
| A violation that a step adds still fails and is restored | PASS | same file: "a step that adds a violation…" (`restored == true`, `cause == DB_MIGRATION_FK_VIOLATION`) |
| A new violation can't hide behind an old one that was removed (equal counts) | PASS after F-1 | new test "clears an old violation and adds a new one…". It fails on `ec40852a` and passes with F-1. It also checks that the restored file holds the original values |
| The failure carries only a code as its cause | PASS | `_afterFailure`: `cause` is set only when the error is a `SafeException`, whose codes the lint requires to be UPPER_SNAKE constants. Otherwise it is null |
| A failed open shows a screen with Try again, in ar/en, RTL/LTR | PASS | `db_open_gate_test.dart`, run through the real `ZaghlolApp` builder |
| Debug print in debug builds only, codes only | PASS | `db_open_debug.dart` is guarded by `kDebugMode` and prints codes and versions only. The allowlist adds exactly one file |

## Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F-1 | **major (fixed by reviewer)** | `app/lib/core/db/app_database.dart` `_fkViolationCounts` | Violations were counted per (child, parent) table pair. Counts can hide a new violation: a step that clears one old dangling reference and creates another in the same pair passes, and the new dangling data gets committed. No current step can do this: the steps copy every row and check the row count, and no step updates or deletes rows. A future step could. | **Done on `task/freeze-review`:** `_fkViolations()` now builds a multiset keyed on child table, parent, the child's PK columns and the values of the broken FK columns. It doesn't use rowid or fkid, so it still works when a rebuild renumbers them. Column lists are cached per (table, fkid), so the cost is one extra query per violating row. Test: `FakeNextMode.fkSwap` plus the new case in `migration_dirty_fk_test.dart`. It fails without the fix. About 40 production lines changed, slightly over the 30-line guide, so the Lead should check the delta. |
| F-2 | minor | `app/lib/app/db_open_gate.dart:66-90` | Every state other than `updateFailed` shows the generic "couldn't open" text with Try again. For `appUpdateRequired` (schema too new) a retry can never succeed. `keyStoreFailed` and `wipeIncomplete` have their own copy in error-handling §1. | Follow-up (FU): map each `DbGateState` to its own copy and action. |
| F-3 | minor | `app/lib/core/db/app_database.dart` onUpgrade | The upgrade now keeps old dangling rows on purpose, and `foreign_keys = ON` afterwards. Screens that inner-join on `account_id` or `category_id` may hide those transactions. Nobody knows yet how the rows came to dangle. | Follow-up: find which delete path left the dangling references, and decide on a repair with the PO. The repair must not delete rows silently. |
| F-4 | minor | `app/lib/app/db_open_gate.dart:29` | While a slow open (a large migration) is loading, nothing is shown except the lock gate's blank cover. This is correct, since it raises no false error, but the user gets no sign of progress. | Follow-up: a "still updating" hint after a few seconds. |
| F-5 | nit | `app/test/core/db/migration_dirty_fk_test.dart` | No test of large-file cost. `foreign_key_check` now runs twice per upgrade, and each run is an indexed scan of every child table. That costs seconds at most, and only on upgrade. | None needed. Note it if a device run shows a slow upgrade. |

Data safety, confirmed by reading the code:
- No path deletes or rewrites user rows to make the upgrade pass.
- The check runs inside the upgrade transaction. A throw rolls the transaction back, and `_afterFailure` restores `.migrate.tmp`, but only when `_ownsCopy` is set, which is the unchanged behaviour.
- A failed open closes its `db` in `_openAndConfirm` before rethrowing, so Try again (`ref.invalidate`) doesn't leak a second handle. The provider registers `onDispose` only on success.
- `appDatabaseProvider` keeps `retry: _noRetry`, so a failing migration is not re-run with backoff.
- A retry re-runs the same upgrade on the restored file, so the result is the same each time.

## Checklist
- [x] `dart analyze --fatal-infos` clean; `dart format` clean; `zaghlol_lints` 0 issues
- [x] Tests passing: `flutter test test/core/db test/app test/privacy test/features/security test/features/backup` ran 1386 tests, all passed (1 skipped), including F-1
- [x] RTL and LTR verified (gate test checks `Directionality`)
- [x] No hard-coded strings (the existing `errorsStorage*` and `commonActionTryAgain` keys)
- [x] No `double` money (not touched)
- [x] No sensitive data in logs (codes and versions only, `kDebugMode`)
- [x] Scope: the listed files plus the F-1 test support (`fake_next_database.dart`)

## Notes for the Lead: does this explain "the logo never goes away"?
The native launch screen stays up until Flutter draws its first frame. There is no `setKeepOnScreenCondition` in Android. A failed DB open happens after `runApp`, so before this fix it left a blank cover in the app's background colour, not the logo. If the PO really sees the **logo**, the first frame may never have been drawn. Rule out these on the device (a debug build with `adb logcat -s flutter`, then look for the `ZAGHLOL_DB_OPEN_FAILED` line):
1. The awaits in `main()` before `runApp` (`initDateFormatting`, `resolveDbDirectory`, `_resumeWipe` → `resumePendingWipe`, `ensureDefaultRegistry`). A hang here, for example a keystore or platform-channel call that never returns, means no frame is ever drawn. In release builds the early error handlers mute it.
2. Native main-thread work at launch: Kotlin receivers or services, or the headless ingestion engine holding the bootstrap lease while the UI engine waits.
3. Whether the blank cover or the lock cover looks like the logo on that device's theme.
If none of these turns anything up, then the blank cover from the failed migration (fixed here) is the explanation.

## Lead delta check (reviewer fix cf04f770)

The set-based `_fkViolations()` (about 40 lines) reads each violating row by `rowid`; no table in the schema is `WITHOUT ROWID` (checked `app_schema*.dart`), so the rowid read is always valid. `dart analyze --fatal-infos` on lib and the touched test folders is clean; `migration_dirty_fk_test.dart` (incl. `fkSwap`) and `db_open_gate_test.dart` pass (8). **Hotfix: APPROVED.**
