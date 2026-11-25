# Batch 73 review (T-257, T-258, T-259)

Reviewer: single batch reviewer (Opus). Branch `batch/2026-11-25-73` @ 74106d37 vs main 93e30f82.
Ran: `flutter analyze` (clean); lints package tests (41 pass) and lint run over app + packages (637 files, 0 issues); parsing `po_suite` + `generic` (232 pass); app ingestion / settings-debug / l10n tests (431 pass). Kotlin and Swift not compiled locally; read by hand, CI runs them.

## T-257 — APPROVED
- Shape signature folds with `foldForMatching` before tokenising; test added. OK.
- Diagnostics LIMIT test now inserts rows and reads through the query. OK.
- Old-due offer query excludes `recurring_occurrences` (and watches the table); "already handled" snackbar uses a new ar+en key; tests added.
- Purge question: `purgeResolvedBefore` has **no callers** in `app/lib` (grep), so resolved `oldDueNotice` items are not deleted today and the T-250 "offer once" guarantee holds. The DAO comment is enough for now; not a blocker/major. Follow-up: when a purge is wired up it must exclude `oldDueNotice` (FU-335).

## T-258 — APPROVED
- Const check now requires the initializer to be an UPPER_SNAKE `SimpleStringLiteral`; `SafeException.named` and `super.named` are covered; `super.code` is flagged unless the class publishes UPPER_SNAKE `static const` codes. Fixtures and tests cover both sides; lint run is clean on the repo.
- The single ignore in `db_errors.dart` carries a reason. Exact-string copy test updated. README updated.
- Minor: `_hasCodeConstants` accepts any UPPER_SNAKE const in the class, not only the ones callers actually pass; it is a heuristic (FU-336).

## T-259 — APPROVED (minor findings)
- Kotlin commit watchdog (20 s) starts at `beginCommit`; `abandonCommit` only acts while committing with no outcome. A late `Accepted` is ignored by `complete` and its stored share is discarded via `commitAbandoned`. The race where the watchdog is scheduled after the worker finished is harmless (`outcome != null`, so false). Unit tests cover abandon, late discard and no-op cases.
- Swift `NativeDiagHook`: `NSLock` guards get/set, handler is invoked outside the lock, `import Foundation` present, and the concurrent test is sound. No compile problems seen.
- Minor (FU-337) `ShareActivity.kt:~100`: `discardLate = store::discard` is a bound reference on a `by lazy` local, so it forces `ShareStores.create` on every `finish`, including Rejected paths and the path where `create` already threw inside intake (caught). A second throw there would be outside the try and skip `ShareJobs.finish`; the 23 s `giveUp` would then still end the job. The constructor looks side-effect-light, so I rate it minor. Fix: `discardLate = { store.discard(it) }`.

## Follow-ups
- FU-335: any future purge job must exclude resolved `oldDueNotice` items.
- FU-336: `_hasCodeConstants` heuristic could check the actual constants used.
- FU-337: use a lambda for `discardLate` in `ShareActivity`.

No blockers or majors. Batch verdict: APPROVED.
