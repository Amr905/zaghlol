# Batch 34 review

Reviewer: code-reviewer (Opus), code and security. Branch `batch/2026-11-17-34`; diff `git diff origin/main...origin/batch/2026-11-17-34`.

Tests run on the merged tree: `packages/zaghlol_domain` 423 passed; `packages/zaghlol_parsing test/categorize` 68 passed; `tools/catalog_build` 59 passed; app `test/features/{insights,budget,home,transactions,categorization,roi}`, `test/ingestion`, `test/core/ui`, `test/core/catalog` (excluding benchmark and golden tags): 914 passed.

## task/CAT-cash (C4, financial math): CHANGES_REQUESTED

Checked:
- The pool math is right. The SQL closed form `S - min(0, min S)` is the Lindley recursion of `allocateCashPool`. `before - p` equals `min(amount, before)`. Both sort by local ms, then withdrawal before payment, then id. Rows are partitioned by currency and amounts are integers. A DAO test pins SQL to the reference on a mixed sequence in two currencies.
- No double counting in Home, left-to-spend, budgets or charts (the case with no offsets). `aggregateCycle` takes the cover out of spend and out of `sys:cash`, and floors Cash at 0. `coveredEarlier` is derived from the totals, so cached cycles carry it. The donut and 50/30/20 subtract the negative Cash row from the total and from wants. ROI, Ask and the weekly summary all read `ChartRepository`, so they get the same numbers. Exports and the transaction list read raw rows.
- Withdrawals and payments are limited to rows that are live, posted or pending, not internal and `expense`. A bank-to-cash internal transfer is not a withdrawal, so cash payments after it count as new spending, which is correct. Soft-delete and undo keep the row, so `_hasCashRows` still matches and the cache is dropped from the earliest changed cycle onward.
- A user-chosen category is never overwritten. The categorizer applies user rules first. The recategorizer skips rows that are verified or `user`, and it now also skips `sys:cash` and `sys:instapay` rows unless the change comes from a user rule. The merge path only categorizes rows whose source is `none`.
- The seed is signed with the dev key `s0000a` only. The ensure step is idempotent (`bySystemCode`, archived rows left alone) and runs only when the meta row already exists. The body is used only for the InstaPay cue boolean, and the text is not stored or logged.

Findings:
- **M1 major (money, double count)** at `app/lib/core/db/cash_cover_sql.dart:21` (`t.amount_minor AS amt`), `packages/zaghlol_domain/lib/budget/cycle_totals.dart:149-154` and `app/lib/features/insights/data/chart_repository.dart:49-50`. The pool uses up a payment's gross amount, but the cover is clamped to the net amount (gross minus offset links). When a covered cash payment has a split reimbursement or a refund link, the linked part leaves the pool but is never taken out of spend or out of Cash. Example: withdraw 1000, pay 300 cash, get 200 back through a split link, then pay 800 cash. The app shows a spend of 1100. The true spend is 900 (1000 + 100 new − 200 reimbursed). Required change: use the same amount for the pool and for the cover. Recommended: cover = min(pool, gross), counted = net − cover (this can go negative by up to the linked amount, so the offset reduces spend), Cash −cover. Apply this in the domain, `_cover` and `_netSpend`, and update the comment about clamping to the net amount.
- m1 minor at `recategorizer.dart:84`. The recategorizer emits no `TransactionsChanged`, so a user rule that moves an ATM row out of `sys:cash` leaves cached later cycles stale. The underlying gap existed before this task; the spend impact is new. Follow-up.
- m2 minor at `cycle_repository.dart:117`. With an account filter, the cover still comes from the whole book. A view filtered to the Cash account shows spend 0 and moves the amount into `coveredEarlier`. Document this or scope it.
- m3 minor at `cycle_cache_invalidator.dart:34`. `_hasCashRows` scans the whole table on every change in a book with no cash rows. Add an index or a flag. Not blocking.
- m4 minor (follow-up, as noted in the task). Only new rows get the hint, and manual InstaPay has none.

## task/FAB-mockup: CHANGES_REQUESTED

Checked: `endFloat` puts the button at bottom-end (on the left in RTL; the test covers ar and en). It is 56 dp with radius 18, and the bar no longer holds the button. Home, Money, Insights, Budget and Bills use `fabClearance`. The scan banner now sits under the hero card, as in mockup 20.

Findings:
- **B1 blocker (functional)** at `app/lib/core/ui/shell/app_shell.dart:132`. The floating button is shown on every tab, including the Zaghlol (Ask) tab. That tab's input row sits at the bottom of the body (`ask_screen.dart:561`, 8 dp bottom padding), and the Send button (`ask-send`, 44 dp) is at the end. The FAB floats 16 dp above the bar at the end, so it covers Send, and a tap there opens Add instead. This brings back FU-246. Required change: hide the FAB on the Ask tab (`selected == 3`), or give the Ask input row end/bottom clearance of at least `fabClearance`.
- m5 minor. Nothing tests that content clears the button on each tab.

## Fix list

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| CAT-cash | `cash_cover_sql.dart:21`, `cycle_totals.dart:149-154`, `chart_repository.dart:49-50` | Use the same amount for pool consumption and for the cover: cover = min(pool, gross); spend = net − cover, so offsets still reduce spend | Domain and SQL: withdraw 1000, pay 300 cash with a 200 split link, pay 800 cash → spend 900; donut total, cycle spend and category sum agree |
| FAB-mockup | `app_shell.dart:132` | Hide the FAB on the Zaghlol/Ask tab, or add clearance so it never covers `ask-send` | Widget test in ar and en: the `ask-send` rect does not intersect the `ZAddButton` rect, and tapping Send sends |

## Lead delta check (fix round, 2026-11-17)

- **CAT-cash (4f491310, 15 production lines):** one cover definition everywhere, `cover = min(pool, gross)`; `spend = net − cover`. A split or refund link on a covered cash payment now still lowers spend. The SQL already matched. The review case (withdraw 1000, pay 300 cash with 200 split back, pay 800 cash) gives **900** in the domain, cycle totals, the donut and cash flow (new DAO test). Per-category floors are unchanged.
- **FAB-mockup (16eae50e):** the Ask mockup (15) shows the Add button, so it stays. On Android the input row keeps `fabSize + 2·lg` clear at the end. ar + en test at 1.3×: Send and Add don't overlap, and tapping Send sends.

Verdict: both tasks **APPROVED**.
- **FU-254:** batch-34 minors; rows saved before CAT-cash keep their old category; manual entry has no InstaPay method.
- **Perf (b551fb53, Lead check):** app-ci's chart benchmark caught the cash-cover CTE being re-evaluated per row (cashFlow 14.8 s, dayHour 14.6 s, burnCurve 1.3 s on 10k rows). The fix marks it `MATERIALIZED`: 16, 12 and 9 ms, same results. This needs SQLite ≥ 3.35; db-platform checks the bundled SQLCipher on the emulator.
