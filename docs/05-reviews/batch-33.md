# Batch 33 review (follow-ups)

Reviewer: code-reviewer (Opus), code and security. Branch `batch/2026-11-17-33`.
Diffs: `git diff origin/main...origin/task/<branch>`.

Tests run on the merged tree: app `test/features/{backup,export_import,notifications,settings,transactions,budget,recurring,capture,categorization,security,ingestion}` and `test/privacy`: 1471 passed. `packages/zaghlol_domain`: 407 passed. Backend `Zaghlol.Application.Tests`: 1057 passed. The Docker-backed `SupportActionTests` ran on GitHub (backend-ci 44075174354, green).

## task/FU-b33-privacy (FU-139, FU-131, FU-133, FU-130, FU-141): APPROVED

Checked:
- FU-131 keyset paging. `transactions_dao.dart` `list` uses `occurred_at < ? OR (occurred_at = ? AND id > ?)` with `ORDER BY occurred_at DESC, id`. The predicate matches the sort order, the cursor is UTC milliseconds like the column, and the `seen` set still drops an edited row that moves pages. Paging is complete and stable. Ids, account ids and category ids now go through `neutralizeFormula`. Tests cover a row inserted mid-export and a row deleted mid-export.
- FU-141 privacy. `offerForTransaction` reads one row and returns early unless all of these hold: the opt-in is on, the row is live, `catalog_merchant_id IS NULL`, the row is not internal, it is not a transfer, it has a category, and both `merchant_norm` and `institution_code` are set. Manual rows never have `merchant_norm` (it is not set on add and is cleared to null when the merchant is edited), so only captured, parsed merchants are offered. The payload is still the generated `ContributionInput` allow-list {merchantNorm, institutionCode, categoryCode}, which is within BR-SYNC-03. `merchant_raw` is used only for the person and PII checks and is never stored. Turning the setting off still goes through `setOptIn`, which deletes the queue. Nothing else deletes data.
- FU-139: `on Object` after the swap committed is correct.
- FU-130: the "shown" mark lives in `db_meta` and is not carried by backups.

Minor (follow-up):
- m1 `notification_service.dart:114`: the list of waiting visible alerts is held in memory, so an alert scheduled before a process restart keeps its amounts. The code documents this as a residual. Persist the ids, or re-schedule all waiting alerts when the toggle changes.
- m2 `bulk_actions.dart:61`: the hook runs once per id, one after another, after a bulk categorize. A 500-row bulk edit makes up to 500 sequential reads. Batch the reads or filter the ids first.

## task/FU-b33-ledger (FU-142, FU-132, FU-136, FU-143): APPROVED

Checked:
- `RefundMatchingHook` runs inside the ingest savepoint on the same `db`. `RefundMatching.onPersisted` already skips rows that are linked (`linkedFromSource > 0`) or that the user unlinked, matches only `t.currency = ?` (no linking across currencies), and the UNIQUE/trigger clash is handled. The hook cannot create a double link.
- In `ignore_rules.dart`, every deleted id now gets pairing cleanup and then refund cleanup (`try/finally`). A failure on one id is counted in the result, and the Undo batch ids are kept.
- `_anchorDay` uses the most common day, and a tie goes to the later day, so Jan 31 / Feb 28 anchors to 31. Money stays integer `Money`.

Minor (follow-up):
- m3 `budget_alert_service.dart:47`: nothing in production calls `run` yet, so annual alerts (the `year:` argument) are not wired. Wire them in the alert job.
- m4 `budget_providers_ui.dart:82-84`: `tryBudgetSpecOf` is called twice per row (nit).

## task/FU-b33-ui (FU-219): APPROVED

The setting is clamped to 0–30 and the picker uses localized digits and l10n strings. A new bill takes the default until the user moves the slider. Editing an existing bill keeps its stored value.

Minor (follow-up):
- m5 `bill_edit_screen.dart:20`: the import is out of order (nit).

## task/FU-b33-tools (backend C4 support + source guard): APPROVED

Security:
- `StartDisputeFreezeAsync` sets `now() + @len` on the Postgres clock, inside the same transaction as the audit row. Both the detach path and the correction-with-move path use it.
- Tests with a clock skewed by 48 h show the freeze still lands at about 30 days from the database time.
- The source-guard regex now catches `Log.d (`, `println (`, `Logger (`, `printStackTrace (` and `fputs (`. The negative samples prove each one.

No findings.

## Fix list

No blocking findings.

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| none | | | |
