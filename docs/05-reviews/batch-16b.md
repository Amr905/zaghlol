# Batch 16, review half B (T-091, T-105, T-113, T-155)

Reviewer: code-reviewer (Opus). Branch `batch/2026-11-13-16`, per-task diffs against `origin/main`. Sprint rule: only blockers and majors that touch money, security, privacy or data block.

Checks run: `flutter test --exclude-tags benchmark,golden test/features/transactions test/features/insights test/features/wealth test/features/export_import test/core/l10n` (328 passed), `dart test` in `packages/zaghlol_domain` (332 passed), `chart_benchmark_test.dart` with the benchmark tag (all charts well under 100 ms; slowest 12 ms median). ARB spot-check (T-029/T-087): `app_ar.arb` and `app_en.arb` both hold 1662 keys, no key missing on either side; placeholder differences seen are only ICU plural/select branch words, not real mismatches.

Note: the T-105 branch is built on T-091, so its diff also contains the T-091 files; only T-105's own files were reviewed under T-105.

## Fix list (blocks under the sprint rule)

| ID | Task | Severity | File:line | Required change |
|----|------|----------|-----------|-----------------|
| 155-1 | T-155 | major | `import_csv.dart:274-287`, `drift_csv_import_store.dart:80-105` | The export has no `is_internal` column and an import never pairs transfers, so every imported `transfer_out` / `transfer_in` is stored as a real (non-internal) row. Own-account transfers then count as spend and as income, and reimbursed/refunded expenses lose their links. Run the transfer pairing (and refund matching) over the imported rows inside the same transaction, or at least report unpaired transfer rows in `ImportSummary` so the caller can resolve them before totals are shown. Add a test: export a book with a paired internal transfer, import into an empty book, and assert cycle spend/income equal the original. |

## T-091 Splits and reimbursements: APPROVED

Traced: `planReimbursement` grants `min(requested, expense remaining, named friend's unsettled share, transfer left)`, rejects duplicates per expense, other-currency and non-positive requests, and never exceeds `sourceRemaining`. `assign` reads and writes in one transaction, and the schema triggers are the race guard (a lost race surfaces as `REIMB_CONFLICT`). A reimbursement is not counted as income because income is computed from the links (`_netIncome` in T-105 and `aggregateCycle`); `unassign` deletes only `reimbursement` links. EC-40: `linksToRemove` drops the newest links (stable tie-break) until the rest fits, on both sides of a link. AC (1,200 bill + 400 + 400 gives net 400; reimbursement excluded from income) are covered and green.

Builder questions: Q1 (friend-named link capped at the friend's unsettled share, excess stays income) is the safe reading, accept. Q2 (EC-40 may remove a refund link if it is the newest) matches the spec text, accept; the removed refund may re-match, which is harmless because it still obeys the caps. Q3 (shares above a shrunk amount flagged, not changed) accept. Q4 (pending incoming transfers not assignable) accept.

| # | Severity | File:line | Issue | Change |
|---|----------|-----------|-------|--------|
| 091-1 | minor | `reimbursements.dart:375` | `repairForNewAmount` builds its event from `txnId` only, although links on the other side (maybe another cycle, BR-XFR-07) are also removed. That cycle's cached totals refresh late. | Include the counterpart transaction ids of the dropped links in `_eventFor`. Follow-up. |
| 091-2 | minor | `reimbursements.dart:183` | `removeParticipant` runs outside `inTransaction` and does not check the expense is live. Harmless (single statement). | Optional. |
| 091-3 | minor | n/a | EC-40 repair is not yet called from `DriftTransactionRepository.edit` (FU-142). Until wired, shrinking an offset expense fails at the schema trigger (safe, not wrong). | Track in FU-142. |

## T-105 Chart query layer: APPROVED

Traced the SQL against `aggregateCycle`: spend (expense, fee, transfer_out) is net of active links whose source is live and posted/pending, income is net of what it funded, internal and soft-deleted rows are excluded, and the local day uses each row's own offset. This is the same counting, and the test `matches the cycle engine to the minor unit (refund, reimbursement)` passes. Every query takes one currency (`ChartFilter`); `currenciesWithActivity` lets the UI offer a switch; the only combined figure is `approxChartTotal`, which wraps the T-115 builder (off by default) and returns an `ApproxView`, not `Money`. Free set: `chartGateIndex` puts cash flow, donut, top merchants and budget bars at 0..3, gated by `GoldGate.chart`; top merchants are limited to 5 for Free. Net worth reads snapshots per unit, never summed. Benchmarks are far below 100 ms.

Builder questions: Q1 (EC-23 thresholds 10 / 2 / 3 / 2) reasonable, accept as defaults in `ChartThresholds`. Q2 (obligations count as needs, giving as other) acceptable; needs a PO/UX line before the labels ship. Q3 (net worth reads `networth_snapshots` directly) accept.

| # | Severity | File:line | Issue | Change |
|---|----------|-----------|-------|--------|
| 105-1 | minor | `chart_repository.dart:78-96`, `chart_providers.dart:12-15` | The memo is cleared only when `cycleDataVersionProvider` bumps. Changes to category buckets or account labels do not raise TransactionsChanged, so the 50/30/20 and cards charts can show old buckets/labels until the next transaction. No money total is wrong. | Also call `invalidate()` (or watch a version) on category and account edits. Follow-up. |
| 105-2 | nit | `chart_repository.dart:482` | Weekday/hour math uses `%` on epoch ms; wrong for dates before 1970 (not reachable, dates are validated to 2000+). | None. |

## T-113 Net worth and snapshots: APPROVED

Traced `computeNetWorth`: units are per currency code or gold symbol and never summed; gold is kept in its native milli-gram unit and valued separately (24 g of 21K at 4217.50 gives 101,220.00, rounded once, half-even); gold without a price stays in its native unit and is never zeroed; the only cross-unit figure (`currencyTotalsWithGoldValued`) is for the ≈ view. Snapshots store one row per unit, gold in milligrams, replaced if taken twice on a day; `snapshotDue` is cycle-start or 31-day based. `certificatePayouts` steps back from maturity by whole periods, clamps short months, skips dates on or before the start, and uses one rounding per payment. The `foreignAssets` to `investmentAssets` rename (FU-123, 119-4) leaves no reference behind.

| # | Severity | File:line | Issue | Change |
|---|----------|-----------|-------|--------|
| 113-1 | minor | `net_worth_repository.dart:135-144` | A `credit` / `bnpl` account balance is taken as "amount owed". `account.dart:20` says that balance may be "a debt or a limit"; if a parser stores available limit, net worth would be wrong. Conforms to domain-algorithms §11 (subtract card balances), so not a blocker. | PO/Lead to confirm the stored meaning; add a test fixing the sign convention. |
| 113-2 | minor | `net_worth.dart:199` | A unit whose assets and liabilities both reach zero is omitted from the snapshot, leaving a gap in that unit's chart. | Acceptable; note for T-117. |
| 113-3 | nit | `net_worth.dart:46` | `isGold` is `startsWith('XAU')`, which would also match the ISO code `XAU` if it were ever a currency line. | Use the explicit symbol set. |
| 113-4 | nit | `docs/04-tasks/tasks/T-113.md` | Status still `TODO`, no design note, AC map or open questions in the task file. | Lead updates in the batch status commit. |

## T-155 CSV import: CHANGES_REQUESTED

Good: insert-only (no update or delete); the whole import is one write transaction; caps (64 MiB, 200,000 rows, 4,096-rune cells, 18 h offsets, years 2000-2099); strict UTF-8 and strict RFC 4180; amounts go through digit normalisation and `Money.tryParse` (exact, negatives rejected, per-currency exponent), and the duplicate key is built from `toStorage()`; unknown accounts are rejected and never created; errors carry only codes and row numbers; the duplicate multiset logic is correct for re-import (0 new) and for a file holding the same purchase twice. The 2-3 negative proofs are enough.

| # | Severity | File:line | Issue | Change |
|---|----------|-----------|-------|--------|
| 155-1 | major | see Fix list | Imported transfers and offsets are not re-paired (builder noted the hooks are not called), so totals are overstated after a round trip. | See Fix list. |
| 155-2 | minor | `drift_csv_import_store.dart:62-77` | `existingAt` reads with `limit: 500` and compares `merchantRaw` to the sanitised import text; a stored merchant with trailing space or control characters would not match and would import again. Same-instant rows above 500 are not realistic. | Compare on the same normalised text. Follow-up. |
| 155-3 | minor | `import_csv.dart:169-222` | A database constraint failure during insert surfaces as the raw store exception rather than an `ImportCsvException`, aborting the whole file (nothing partial is kept, which is safe). | Map to a code. Follow-up. |
| 155-4 | minor | `import_csv.dart:321-323` | A real merchant/note starting with `'=` etc. loses its apostrophe (already noted by the builder). | Accept; documented. |
