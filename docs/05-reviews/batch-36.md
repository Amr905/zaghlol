# Batch 36 review (branch `batch/2026-11-18-36`)

Reviewer: code-reviewer (Opus), code + security. Date: 2026-11-17.
Tests run on the merged tree: app `test/features/{budget,notifications,gold,settings,insights,categorization,recurring,transactions}` + `test/core`: 2225 passed; `zaghlol_domain` 423 passed; `zaghlol_parsing` 1517 passed; `tools/lints` 34 passed; `tools/catalog_build` 60 passed.

## task/FU-b36-house: APPROVED
- Throttle, trailing run, `shouldStop`, the backfill marker inside the gate, and `read` (not `watch`) of the gate are all correct. The gate provider never rebuilds (`capture_providers.dart:58`), so `read` loses nothing.
- minor `housekeeping_providers.dart:~250`: `_lastStartMs` is shared, so a resume within 5 min of any after-ingest run is skipped. This is acceptable because the same steps just ran. A comment would make that clear.

## task/FU-b36-rollover: CHANGES_REQUESTED
- **major (money)** `rollover_carry.dart:20-27`: the carry is always `spec.limit − prev-cycle spend`. It ignores `budgets.created_at` and limit history. A rollover budget created (or switched to rollover) today immediately shows up to 2× its limit on the screen and in the basis, and its alerts are delayed by the same amount, even though nothing was unused last cycle (FR-BUD-05 says "unused budget"). Required: give zero carry when the budget did not exist for the whole previous cycle (`created_at` ≥ `prev.start`, or > `prev.end` if you treat "existed during" as enough). Carry `createdAt` on `BudgetSpec` or pass it in. Test: a rollover budget created in the current cycle has no carry on the screen or in alerts.
- What is correct: the carry is never negative, it is per currency, it uses integer `Money`, and annual budgets are excluded. The carry is stable within a cycle and alerts dedupe per threshold, so there is no re-alert storm.
- minor `budget_providers_ui.dart:76-79`: `tryBudgetSpecOf` runs twice per row. minor: there is no screen-level test that carry is added to the rows or the basis (only runner tests).
- minor: if the limit changes, the previous cycle's carry is recomputed with the new limit. Document this approximation.

## task/FU-triage: APPROVED
I spot-checked five claims and all hold: FU-018 (`CheckSql.DigitSeparators`), FU-034 (`failure.dart` `_codePattern`), FU-036 (`enum MascotPose`), FU-042 (`generate_pigeon.sh` refuses outputs outside the checked dirs), FU-045 (a masked amount falls back and never shows the real value).

## task/FU-b36-be: APPROVED
Each SHA matches the upstream tag: checkout `fbc6f39…` = v5.1.0, setup-dotnet `67a3573…` = v4.3.1, upload-artifact `b7c566a…` = v6.0.0. The two major version bumps (checkout v5, upload-artifact v6) are covered by the green backend-ci run 44175287216 on the same commit `f9012481`.

## task/FU-b36-parse: APPROVED
- "ألف ألف" = 1,000,000 is correct and tested.
- minor `app/lib/core/catalog/catalog_seed_loader.dart:129-134`: the seed loads only when `catalog_meta` is empty, with no hash or signature comparison. Installs that already exist will **not** get the new keywords from the seed, whatever version it carries; only backend catalog sync can deliver them. This is pre-launch, so only dev installs are affected. Follow-up: make sure the backend catalog publishes these keywords, or bump the seed version and add an upgrade path.

## task/FU-b36-ui: CHANGES_REQUESTED
- **major (billing/false claim)** `app_en.arb:6096`, `app_ar.arb:9199`: "Gold stays yours" / "الجولد فاضل بتاعك" is shown unconditionally. On Android, "Delete everything" makes this a new install that spends the month's move (D-55/D-61, EC-69). The same dialog can show `goldSeatDeleteWarning`, including a cooldown date, which this line contradicts. Required: limit the line to what is true ("Your store purchase and account aren't touched; you can restore Gold") or drop the Gold sentence. Update the copy deck §3.10 to match. Test: a widget test of the delete dialog that shows the line next to the seat warning.
- minor: `docs/02-design/copy-deck.md:2580` still has the old `privacy_delete_body`, and the new key has no copy-deck row. minor: `app_ar.arb` has no `@privacyDeleteStoreAccountKept`.
- nit `app_ar.arb` cash-flow tip: "ده هيساعدك تقفل الفرق" reads more naturally than "هيساعدك ده تقفل الفرق".
- The removed "security keys" claim (FU-039) is correct. The FU-076 and FU-124 docs match the code (`capture_coordinator.dart:134`).

## task/FU-b36-core: APPROVED (C4, security checked)
- FU-138: with a cached token and a missing record, `evaluate()` now starts tampered. A fresh install with no token is not tampered. `start()` and `onResume()` call `evaluate()` first, so deleting the record is caught on the normal paths.
- minor (security, defence in depth) `entitlement.dart:480`: `refreshIfDue()` calls `_time.advance()` without `hasToken`, although it computes `has` right below. If the record is deleted while the app runs and `refreshIfDue` is the next caller, the record is re-created untampered. Pass `has` (read before `advance`). The same applies to `raise()` (`trusted_time.dart:215`).
- `DbCorruptException` implements `FormatException`, its message is a constant, and existing handlers still work. `Failure.toString` is fine. The lint extensions are covered by fixtures.

## Fix list (blocking)

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| FU-b36-rollover | `app/lib/features/budget/application/rollover_carry.dart:20-27` | Zero carry for a budget that did not exist through the previous cycle (use `budgets.created_at`) | A rollover budget created in the current cycle: carry 0 on the screen and in `runBudgetAlerts` |
| FU-b36-ui | `app/lib/core/l10n/app_en.arb:6096`, `app_ar.arb:9199` (+ copy-deck §3.10) | Remove or qualify "Gold stays yours" so it does not contradict the Android move or cooldown warning | Delete-dialog widget test with the seat warning shown |

## Lead delta check (fix round, 2026-11-18)

- **rollover (45c06b56, ~20 production lines):** a rollover budget created after the previous cycle began now carries 0. `createdAtMs` comes from `budgets.created_at`, and the shared carry function (used by the screen and alerts) checks it. A runner test covers it (new budget alerts at 80% of its limit), and existing budgets still carry. Minor: the cut uses UTC midnight, so a budget made in the first ~2 h of a Cairo cycle still carries.
- **ui (3a5e7cc2):** `privacyDeleteStoreAccountKept` now only says the store purchase and account aren't touched. There's no Gold promise to contradict the Android seat warning. Copy deck §3.10 is updated, and the ar + en test runs with the seat warning shown.

Verdict: all seven tasks **APPROVED**.
- **FU-256:** batch-36 minors: the catalog seed loads only into an empty catalog (existing installs get new keywords only through catalog sync); `refreshIfDue` doesn't pass `hasToken`; rollover cut uses UTC midnight; budget alerts and recurring detection still hold the gate for a whole run; the backend triage items owned by T-130/135/137/140/144.
