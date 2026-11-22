# Batch 56 review: T-189 charts redesign

Reviewer: code-reviewer (Opus). Scope: `git diff origin/main...batch/2026-11-22-56`. Tests: `flutter test --exclude-tags golden test/features/insights test/features/transactions` = 519 passed, 0 failed. Goldens not assessed (CI regenerates).

## T-189 — verdict: CHANGES_REQUESTED

### Findings

| # | Sev | Location | Issue | Required change |
|---|-----|----------|-------|-----------------|
| 1 | major | `charts_screen.dart:~338-345` (`categoryIds: {for (final id in e.memberIds) ?id}`), `chart_drill.dart:drillFilter` | The null member (uncategorized) is dropped. Tapping the "Uncategorized" slice gives `categoryIds = {}`, so the list shows ALL expenses of the period; the header total then equals total spend, not the slice. An "Other" entry that folds uncategorized loses those rows too, and its header is hidden when >1 category. The slice's amount and the opened list disagree (money correctness). | Either support "uncategorized" in the list filter (e.g. a flag mapping to `category_id IS NULL`, in `TxnQuery`/`TransactionFilter`/`scopedSpend`), or disable tap-through for the uncategorized slice / Other-with-uncategorized. Add a widget test for the uncategorized slice. |
| 2 | minor | `chart_drill.dart:openChartDrill` | Shared-filter deviation: judged acceptable. `txnListFilterProvider` is in-memory only (Notifier, no persistence), so app kill cannot leak it. Back gesture/pop completes the push future, and the `finally` restores. Residual: while the drill route is open the Transactions tab's provider shows the drill filter (a deep link or tab switch during that time would see it); existing code (`app_navigation.dart:185`, `card_navigation.dart:65`) already mutates the same provider with no restore, so this is strictly better. Not a blocker. | Follow-up only: consider a route-scoped `ProviderScope` override for the drill list. |
| 3 | minor | `chart_drill.dart` header | Before-period for a user-edited custom range is the same-length preceding range; fine, but baseline is not named in the header. | FU: label the baseline in the drill header (mockup 3 says every comparison names its baseline). |
| 4 | nit | `chart_summary.dart:niceAxisStep` | Candidate list yields steps like 25 for exponent-0 currencies; fine, only noting no test for 0-exponent max < 3. | none |

### Checked, no issues
- Math (`chart_summary.dart`): integer minor units only; `percentChange` handles zero/negative baseline (none) and rounds via `mulDivRound`; one `Money` currency per call, no cross-currency sums; "same elapsed days" baseline comes from `ResolvedChartPeriod.previous`; top-5 + Other keeps amount/share/count sums equal to the donut; Other has no change chip; compact labels honour exponent and roll 999.96K to 1.0M.
- Drill filters: category/merchant/period/currency/expense type applied in `txnToRepoFilter`, DAO `merchant_norm = ?` is parameterised; `copyWith` preserves the merchant; header hides for custom-less or multi-category filters.
- Hidden amounts: figures go through `chartMoney`, a11y via `a11yAmounts`; percentages and shapes stay (tests cover `****`, no axis labels, never spoken).
- Colour: apricot up / green down via `toneOf`; no red. Text summaries and a11y labels present on strip, bubbles, rows, charts.
- ARB: ar/en parity in the diff; chart/picker strings use «شهر»/"month" via new `insightsChartsPreset*` keys, shared `commonPeriod*` untouched (payday cycle unchanged).
- NFR-PERF-04: the eight secondary charts sit behind «كل الرسوم»; lazy-build test present.
- RTL: axis side and bar-to-month mapping tested.

### Fix round
Finding 1 only (lane: insights UI + transactions filter). Minors go to FU-284.

### Follow-ups (FU-284)
Finding 2 (route-scoped filter), finding 3 (baseline label in drill header), finding 4, and builder deviations 1-3 (no daily line chart, net-worth thin state without current number, no "Other" in merchants) as tracked scope notes; new goldens for strip/drill/thin/hidden still to be added.

## Lead delta check (fix round)

- Major fixed (fb69d493): `includeUncategorized` runs through `TxnQuery` (`category_id IS NULL`, or `IS NULL OR IN (...)`), `TransactionFilter`, `scopedSpend`/`DrillScope` and the drill; the chip shows «بدون تصنيف» / "Uncategorized". Widget tests (ar + en) for the uncategorized slice and for "Other" containing it; repository test for `scopedSpend`. 1392 tests pass. **T-189 APPROVED.**
- Minors → FU-284: name the baseline in the drill header beyond "vs the period before"; axis-step edge-case test; route-scoped override for the drill filter; scope notes (no new daily line, net-worth thin state shows only the line, no "Other" place row, Gold-only charts use fl_chart's tooltip).
