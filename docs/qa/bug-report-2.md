# Bug report 2 (QA B57)

Independent audit of `main` @ `8b91b012` (merge of PR #104), 22 Nov 2026. Scope: what changed since the first audit
(`bug-report.md`, `bc5b9d1d`): batches 43–56 (T-187 hide amounts, T-188 chart periods, T-189 charts redesign, T-195 salary,
T-196 recurring to bills, T-197 card types, T-198 bank badges, T-199 net-worth breakdown, T-202–T-204 True Black / bottom bar /
Home, FU-240c export + import target card + PDF password, FU-206 widget lock/midnight, T-193 notification taps, FU-165a,
backend hosting T-200/T-201/T-205–T-207).

Every bug below has a failing test on branch `task/B57-qa` under `app/test/qa/`. No production code was changed.
All test data is synthetic.

| ID | Severity | Title | Where | Reproduction (failing test) | Expected | Actual |
|---|---|---|---|---|---|---|
| BUG-010 | MEDIUM | Money tab net-worth hero shows the alphabetically first currency, not the primary one | `app/lib/features/accounts/presentation/money_tab.dart:195-196` (`totals.currencies.first`; `MultiCurrencyTotal.orderedFor(primary)` exists but is unused) | `test/qa/bug_010_money_hero_currency_test.dart` "BUG-010 Money hero headline is the primary currency (EGP)…" | Primary EGP, one EGP and one AED account: hero = EGP net worth, AED as the chip (glossary "Primary currency: shown first in views"; FR-HOME-01; Home already does this via `orderCurrencies`) | Hero = `100 AED`, EGP figure demoted to a chip. Any user with an AED/CAD/CHF/… account sees it. With no accounts the hero falls back to EGP whatever the primary is (`_zeroEgp`). |
| BUG-011 | LOW | Export preview puts the `****` glyphs in the semantics tree when amounts are hidden | `app/lib/features/export_import/presentation/export_screen.dart:316-319` (plain `Text(kAmountMask)`, no `a11yAmounts` / `ZMoneyText`) | `test/qa/bug_011_export_preview_a11y_test.dart` "BUG-011 export preview: no **** in semantics when hidden" | T-187 AC 7: a screen reader says "amount hidden" | TalkBack reads "star star star star" for each preview row |
| BUG-012 | MEDIUM | Charts (and Share studio) open on the alphabetically first currency; switcher lists primary last | `app/lib/features/insights/presentation/charts/charts_screen.dart:86-90` (`orElse: () => list.first`); list comes from `chart_repository.dart:208` `ORDER BY c`; same `chartsCurrencyProvider` default in `share_cards/presentation/share_studio_screen.dart:132` | `test/qa/bug_012_charts_default_currency_test.dart` "BUG-012 charts open on the primary currency (EGP), not AED" | Charts default to the primary currency; C-09 "currencies present, primary first" (03-navigation.md:81, 04-design-system.md:128) | Selected = AED, chips `[AED, EGP]`: the summary strip, donut and every chart show the minor currency first |
| BUG-013 | LOW | After stepping a period, the period chip is announced with the original preset name | `app/lib/features/insights/presentation/charts/chart_period_bar.dart:80-84` (`presetName(resolved.selection.preset)` ignores `offset`) | `test/qa/bug_013_period_a11y_preset_test.dart` "BUG-013 stepped \"This month\" is not announced as This month" | "This month" stepped back once is announced as last month (or by its range only) | "Chart period: This month, Oct 1 – Oct 31" while today is in November. Same for Last cycle stepped forward ("Last cycle" spoken over the current cycle), This year stepped back, etc. |
| BUG-014 | MEDIUM | "Explain this chart" for net worth prints raw minor units | `app/lib/features/insights/presentation/chart_explain_l10n.dart:55-56` (`digits.render('$minor $unit')`), fed by `insights/domain/explanations.dart:1103,1105,1154` | `test/qa/bug_014_networth_explain_minor_units_test.dart` "BUG-014 net worth explanation amount is in major units" | Net worth EGP 1,234.50 reads `EGP 1,234.50` | Reads `123450 EGP`: 100x too big (1000x for KWD-class currencies), no grouping or decimal separator. Applies to `endAmount`, `startAmount` and the deep tip's `projected` figure. (Line predates T-187, which only added the masked branch; not in the first audit.) |

No HIGH bug was found in the changed scope.

## Test runs (22 Nov 2026, shared cloud workspace)

- `flutter analyze` (app, with the QA tests): **No issues found**.
- `flutter test --exclude-tags golden -j 2`: **+5257 ~35 -7**. The 7: three QA bug tests (BUG-010/011/012; 013/014 were added after
  the run started and fail on their own, see above); `transactions_search_benchmark_test.dart` "search p95 < 200 ms" and
  `categorizer_seed_test.dart` "per-message time (host p95)" (timing benchmarks, machine shared with other sessions);
  `restore_side_effects_test.dart` "FU-194: a headless drain that ends in time…" and `flags_service_test.dart` /
  `l10n_test.dart` "did not complete" (load). Re-run alone: `flags_service_test`, `l10n_test`, `restore_side_effects_test`
  **all pass (+55)**. Treat the timing tests as flaky under load, not as defects.
- Backend `dotnet test` (unit projects, Debug): Application **1058/1058**, Workers **39/39**. Ops 6, Contract 91, Api 354,
  Infrastructure 680 failures are all "Failed to connect to Docker endpoint" (Testcontainers; no Docker here), checked per test
  from the TRX files. One more Infrastructure failure, `AppStoreSentinelTests.NoIdentifierTokenOrJwsAppearsInLogsSpansOrExceptions`
  (`Assert.Equal(2, apple.Count(...))` got 3), passes 3/3 when run alone: a retry-count assertion that is timing-sensitive under
  load (flaky test, LOW, no production impact found).

## Checked, no bug

- **Hide amounts (T-187)**: every `MoneyFormat.format` call site passes `hidden:` (scripted scan of all call sites); chart axis
  labels empty and tooltips suppressed (`chartCompactMoney`, `gold_chart_bodies.dart:160`); `ZMoneyText` swaps the semantics label
  for "amount hidden"; share card forces percent-only (`share_card.dart:24`) even if the studio switch was on; notifications OR the
  app setting into `loadPrefs` and use the redacted text, scheduled alerts are re-redacted on toggle; widget ORs the app setting and
  fails closed while loading; salary nudge and auto-added-bills notice carry no amount.
- **Widget lock / midnight (FU-206)**: masked snapshot is sent at once on lock or background with lock on; nothing published while the
  lock setting loads; per-day lines carry no amount.
- **Chart periods (T-188)**: resolve/step/encode for every preset, month ends (Mar 31 vs Feb), year boundary, rolling offsets,
  custom ranges capped at today, offsets bounded on decode, previous period cut to elapsed days.
- **Charts summary (T-189)**: integer percent maths, zero/negative baselines give "none", top-5 + Other sums, compact axis rounding
  (999.96K to 1.0M), per-currency only.
- **Salary (T-195)**: payday limited to 1..28 everywhere (plan, schedule), windows −3/+5, nudge P+6..P+20, skip/decline/undo,
  merge soft-delete is conditional (one winner), never matches across currencies, amount tolerance in BigInt.
- **Bills (T-196)**: v4→v5 rebuild copies all columns and re-creates indexes; quarterly/semi-annual due-date clamping
  (`advanceDue`), yearly/monthly cost, dismissal keys on delete/edit/"Not a bill", auto-added notice deduped per day.
- **Net worth (T-199)**: per (account, currency) anchors, card owed = limit − available floored at 0, future-dated user balance
  ignored, transactions strictly after the anchor, installments not double counted with a card balance, Free excludes assets
  with a notice; empty DB shows the empty text.
- **True Black (T-202)**: no hard-coded white/black text in features; `c.primary` (white) is never used as a fill under
  `c.text`; badge colours keep 4.5:1.
- **Notification taps (T-193)**: allow-list of routes, ids/dates validated, mark-paid waits for unlock and confirmation, debug
  helpers compiled out (`kDebugMode`).
- **Export / import (FU-240c)**: preview never builds file bytes; Free opens the paywall; PDF password kept in a local only;
  statement runners are still BLOCKED (T-156/T-157), so the password and target-card paths are reachable only in tests.
- **Backend hosting (T-200/T-201/T-205–T-207)**: `Local` KMS refused outside Development/Testing; unknown provider refuses start;
  Production refuses non-verifying TLS unless explicitly allowed; BUG-002 (exit code after `RunAsync`) is fixed in both API and
  Workers.
