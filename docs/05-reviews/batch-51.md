# Batch 51 review (branch batch/2026-11-20-51), FU sweep

Reviewer: code-reviewer (Opus 5.5). Diff: `origin/batch/2026-11-20-50...batch/2026-11-20-51`. Read-only on code.
Tests run locally: all 13 touched app test files (153 tests) and `zaghlol_parsing` `ask_parser_test.dart` pass. Analyze and goldens are left to CI.
OBSOLETE spot-check: I checked 11 of the 58 OBSOLETE closures against the code: FU-151b, 161c, 165b, 165c, 165e (age-out at purchase.dart:120), 168d, 169b, 178b, 180a, 209a/c and 229e. All 11 are fixed in the code. One caveat: FU-180a's "subcategories unprotected" part is fixed only if callers pass bucket-derived ids. `essentialCategoryIdsProvider` does that, so I accept the closure.

## core (task/FU51-core): CHANGES_REQUESTED

- **major**: `app/lib/features/gold/application/purchase.dart:272-278`. FU-165a is marked FIXED, but the case it names is still unfixed. The batch-18a finding 145-2 and backend-api §4.3 (line 356) describe a re-verify from a non-holder, or onto a vacant seat. The server answers `active` with `seatHeldElsewhere:false` and **a token that does not contain the purchase**. Locally that is `r.entitlement != null` and the phase is not Gold, so the code still takes the final `else` branch: `_retryLater` for 14 days, and the iOS transaction is never finished. The new branch handles `entitlement == null` instead, and production does not produce that answer: `PurchaseEndpoints.cs:141` and `VerifyGrant.cs` always issue a token for an active, written purchase, and Play and App Store verification always set `PurchaseId`. The test (`purchase_test.dart:364`, `withToken: false`) covers that unreachable shape. Safety: the branch never grants Gold, and it cannot drop a purchase the server accepted, because it is unreachable. It is still dead code under a FIXED label on a C4 path. A second problem: `e.attempts` also counts transient failures (5xx, PlatformException), so the "3 answers" rule would fire on the first such answer after 2 outages.
  Required: either (a) implement 145-2 as written: for `active` + token + not Gold + `seatHeldElsewhere != true`, return a typed outcome, complete the purchase and offer Restore. This needs a way to tell "the token lacks this purchase" apart from "a holder's token failed local evaluation", which must keep failing closed. Or (b) remove the new branch and set FU-165a back to OPEN with the reason. Neither option may grant Gold.
- minor: `purchase.dart:45-51`. The new constant was inserted between `outboxMaxAge` and its doc comment. `maxNoEntitlementAttempts` now carries both comments, and `outboxMaxAge` has none.
- minor: `account_service.dart:225-228` (FU-189c). `GoogleSignIn.signOut` also ends the session that `GoogleSignInDriveAuthorizer` uses for `attemptLightweightAuthentication`. After a Gold sign-out, scheduled (non-interactive) Drive backups fail with `signInRequired` until the user signs in again. No spec covers this. Confirm with the PO, or show a backup-reconnect hint.
- minor: `security/application/delete_everything_providers.dart:58` calls `GoogleSignIn.instance.signOut()` outside `GoogleSignInGate`. That breaks the FU-189b serialization rule, though a race there is harmless.
- nit: `core/platform/google_sign_in_gate.dart` is a process-wide singleton (CLAUDE.md §8 says no global singletons). The plugin is itself global, so this is justified, but the tests share its epoch state. Give it a short comment or a provider-overridable instance.
- OK: FU-189b. The gate's tail swallows errors and the next session runs (tested). The Drive authorizer re-initializes after a nonce session through the epoch, and nothing re-enters the gate from inside a body, so no deadlock.
- OK: FU-189d. `linkedGold` returns false when `ensureInstalled` fails and requires `sub == installId` (tested).
- OK: FU-234a. `formatBp(250, digits)` is tested; the zakah goldens change in CI.

## ui-a (task/FU51-ui-a): APPROVED (minors)

- FU-179a/b merge resolution (`categories_admin.dart:269-304`): coherent, and it runs once inside the delete transaction. Steps: children set to `parent_id NULL`, colliding budgets found under the full `UNIQUE(category_id, currency, period)`, their `fired_alerts` (subject = budget id) deleted before the budgets, the rest re-pointed, then the category archived. No leftovers from either lane. The replacement cannot be a child of the deleted category (guard at line 244). Both lanes' tests pass.
- FU-179c: support code shown only for a typed `CategoriesAdminException`; tested.
- FU-155a (`budget_saver.dart:27`): the whole rewrite is in `db.transaction`. Minor: no test shows a rollback (for example, an insert that throws leaves the old rows). FU-273.
- FU-158c: the currency chip is locked on edit; tested. Nit: a wrong currency on a manual row can now only be fixed by deleting and re-adding it. That matches "never silently converted".
- FU-171b: `updateManual` returning false now throws `notFound`; tested. FU-172b: hide-amounts is written first and restored on failure or non-enable; tested. FU-173a: `catchError` on deferred jobs.

## ui-b (task/FU51-ui-b): APPROVED (minors)

- FU-181a (`drift_transfers_sheet_port.dart:158`): removals, shrinks and adds share one `_db.transaction`, and the nested `inTransaction` calls become savepoints on the same database. Minor: no rollback test. FU-273.
- FU-229a (`voice_controller.dart:403-406`): the quota is counted after the first written row, once per session, and reset only by "Try again". Tested, including partial save + retry. Minor: if `countOne` throws after a row is written, the session shows `saveFailed` and the retry counts on the next unsaved row. If none is left, the log is never counted. This is a narrow case; FU-273.
- FU-187a: Ignore is hidden without last4; tested. `assign_sheet` `firstWhere` guard and split-sheet undo catch are correct. The share channel row has been added to platform-channels.md.

## parsing-test: APPROVED

- FU-157c: courtesy stop words added, with a test. The OBSOLETE rows checked (209a/c) hold.

## native: APPROVED

- FU-164a is a comment only (`CaptureRuntime.kt:285`). FU-229e checked: the once-only `done` guard is in `SpeechSupportRegistration.kt:57-63`.

## backend-ci: APPROVED

- FU-271: `dart analyze --fatal-infos` from the repo root keeps the old rule (infos fatal). The annotation grep matches `dart analyze` output. The plugin-probe step after it still guards against riverpod_lint failing to load. The first real run is in CI.

## Verdicts

| Lane | Verdict |
|---|---|
| core | CHANGES_REQUESTED (FU-165a major) |
| ui-a | APPROVED |
| ui-b | APPROVED |
| parsing-test | APPROVED |
| native | APPROVED |
| backend-ci | APPROVED |

Follow-up row for the minors: **FU-273**. It covers the purchase.dart doc-comment order, the effect of 189c sign-out on Drive backup, the ungated delete-everything sign-out, the gate singleton note, the missing FU-155a/181a rollback tests, and the voice `countOne` edge case.
