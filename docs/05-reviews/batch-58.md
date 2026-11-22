# Batch 58 review: Charts v2 (T-209, T-210, T-211)

Reviewer: code-reviewer (Sonnet). Scope: production diff `main...HEAD`, AC to test maps, goldens (layout only, block glyph font).
Run: `flutter test --exclude-tags golden test/features/insights test/features/hide_amounts` gives 424 passed, 0 failed.

## Cross-cutting checks

1. Numbers across cards. Hero spend (`dailySpend`, `_netSpend` over `_spend`) and the Categories total (`donut.total` = positive rows minus cash-covered-from-earlier) are the same sum: the cover union rows net to zero. Transfers out and fees count in both, internal transfers in neither. Uncategorized is its own row. Other currencies are listed apart, never summed. The one visible gap: when a cash-covered payment exists, the sum of the rows exceeds the title total by the covered amount (the existing donut has the same behaviour and its note). Not a v2 regression. Minor.
2. Projection. Hero (`computePace`) and the saved-months open bar both use `mulDivRound(spent, length, elapsed)` with `projectionMinDays`, and the same spend definition. They agree for a single cycle or month. For a multi-month period the hero projects the whole period, the bar projects the last month: different scopes, labelled by period, not a conflict. Past period: both unprojected.
3. Gates. `decideChart` goes through `GoldGate.chart`, which is open while `chartsOpenToFree` is true. No v2 card is locked today; the heatmap (`dayHourPattern`, index 6) locks only if the flag is flipped, as CHARTS-V2 prescribes. Hero and Coming up are ungated. OK.
4. Money. Integer minor units, one currency per card, others listed separately. Every amount, axis label, average line, tooltip and a11y string goes through `chartMoney` or `v2AxisMoney` (mask when hidden). Digits go through `digitsModeProvider`. Percent and count stay visible, as designed. No hard-coded user strings found (only keys and enum words used as ICU selectors). Directional paddings are used.
5. Edge cases. `computePace` clamps the days, treats a thin period (under 3 days or no previous) as "not enough yet", clamps a shorter previous period to its last day, and gives closed periods no projection. Empty donut shows the no-data state. The first period has no previous, so no change chips. Goldens (overview, trends) render in RTL with sensible layout.

## T-209 Overview tab: APPROVED
No blocker or major. Minors are in the FU-286 list.

## T-210 Categories tab: APPROVED
No blocker or major.

## T-211 Trends tab: APPROVED
No blocker or major.

## Proposed FU-286 (minors, nothing blocks)
- a. T-210: rows can sum to more than the title total when a cash-covered payment exists; consider showing the existing covered-earlier note or summing the rows for the title.
- b. T-211: heatmap gate would silently lock if `chartsOpenToFree` flips; add a test that pins the locked-card branch for it (T-210 does for the donut).
- c. T-209: the hero projection on a multi-month period and the saved-months bar for its last month are different numbers; consider a short caption on the hero naming the period it projects.
- d. `paceProvider`: a future period (today before `from`) gives elapsed 1 and shows day 1; confirm the picker cannot select one.
- e. `chartsOpenToFree` is a mutable static; CLAUDE.md statement "all 12 charts open" depends on it.

Verdict: APPROVED, no fix round needed.
