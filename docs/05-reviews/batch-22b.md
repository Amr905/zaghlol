# Batch 22b review: design pass (DESIGN-home, DESIGN-onboarding, DESIGN-txn, DESIGN-insights, DESIGN-money)

Reviewer: Opus-level code + security pass, sprint rules. Merged tree `batch/2026-11-14-22` at 7ca1506c.
Tests run: `flutter test --exclude-tags benchmark,golden` over home, onboarding, transactions, ingestion, ask, insights, budget, recurring, accounts, money, settings, gold, `test/core`, `test/a11y`. Result: 2729 passed, 1 skipped, **8 failed** (all `a11y_rest_test.dart: split sheet a11y *`, see F1).

## Cross-cutting checks (all tasks)

- **Money.** `MoneyFormat.format(dropZeroFraction)` only clears a fraction that is all zeros (`^0*$`); `1.50`, `0.05`, KWD `1.500` keep their digits, and the integer and sign paths are untouched. `HomeFormat.money/number` pass it. `trimZeroFraction` (insights) is display-only; `[.٫][0٠]+(?![0-9٠-٩])` cannot strip `.05` or `.50`, and does not touch `ج.م`. `trimCurrency` is used only in the budget screen (which has a per-currency selector and currency note, semantics keep the full label) and the single-currency donut/legend. No `double` money; `_progress` is a display ratio only. OK.
- **`commonDateRange(end, start)`.** Home hero call is now (end, start) and renders `start – end`. OK. See F5 for the transactions filter call, which is still reversed.
- **Defaults (PO 2026-11-14).** Language `ar`, theme `light`, `appThemeModeProvider`, `ZaghlolApp(themeMode)` are identical in all five branches (merge clean). Saved prefs are unaffected; only unset ones change. Settings and preferences screens read the same defaults. OK.
- **Shared `core/ui`.** `ZHeroCard`, `ZProgressBar`, `ZMascotBubble`, `ZCategoryGlyph`, `ZMoneyText(unit, hero)`, `ZBanner(icon)`, `ZSheetBody(centerTitle)`, `ShellScaffold/ZAddButton` are additive with defaults; other screens that use `ZMoneyText`, `ZListRow`, `ZBanner`, `ZSheetBody` pass their tests. `ZMoneyText` with `unit` keeps the semantics label `"$shown $unit"`. Masked text still hides the number. Gold badge on the Add sheet's asset entry kept (`!gold`).
- **Theme.** New hero and progress gradients are tokens in both `ZColors.light` and `.dark`. Hard-coded colours that remain are listed in F6.
- **Strings.** New keys exist in both ARBs; plural and placeholder blocks (`insightsChartsMonthsCount`, `budgetOverviewZaghlolWarn`, `insightsChartsSavedFootnote`) are valid and generated files are in sync. No new literal user-facing strings found in the production diff (emoji glyphs in `ZCategoryGlyph` are not text copy).
- **Behaviour preserved (spot-checked by grep and tests).** Keys and callbacks still present: `ask-send`, `ask-roast-toggle`, clear tooltip, `onSubmitted`; paywall close tooltip, restore/buy/manage, links; budget prev/next with `hasPrevious/isCurrent`; chart detail back tooltip; bills `openBillEditor`/accept/dismiss; card `card-merge/-hide/-capture-link`; onboarding `setup-*` and `ios-setup-*` keys; home card filter, share, settings, spent KPI, set-budget.

## DESIGN-home: APPROVED

Findings:
- **F3 (major, non-blocking, a11y)** `core/ui/z_card.dart` `ZHeroCard`: when `onTap != null` the whole card is wrapped in `MergeSemantics`. Home's hero contains other interactive items (the "Spent" KPI `InkWell` with `onSpentTap`, and the "Set budget" `ZButton`). Merged into one node, a screen-reader user can no longer reach those separately (one tap action wins). Pointer behaviour and tests are fine, so nothing catches it. Required change: do not merge descendants (use `Semantics(container: true)` / `button: true` on the card, or only the header block), keep KPI and button as separate nodes. Add a semantics test that finds the spent KPI and set-budget as separate tappable nodes.
- **F2 (major, non-blocking, RTL)** chevron direction, see below (`home_widgets.dart` review banner and `_Kpi`).
- **F4 (minor)** `core/ui/shell/add_sheet.dart:~150`: `voiceLeft` is never passed by the wiring (the voice-quota line never shows), and when it is it renders digits with a hard-coded Arabic-Indic mapping, ignoring the digits preference. Wire it and use `DigitsMode.render`.
- **nit** `z_card.dart` `ZListRow.showDivider`: the `DecoratedBox(position: foreground, decoration: BoxDecoration())` is a no-op wrapper; drop it.
- **nit** Tab bar: selected and unselected icons are now identical (outlined); selection relies on the indicator pill and colour. Acceptable (indicator is present), but `selectedIcon` could be filled.

## DESIGN-onboarding: APPROVED

- Skip, allow SMS, notification, degraded-path, install/check/first-expense and scan result keys and callbacks are all still present; the onboarding tests pass in ar and en.
- F2 applies (`onboarding_parts.dart` / `ios_setup.dart` chevrons).
- minor: `commonActionSkip` changed to `تخطي` in `app_ar.arb` (shared string); fine.

## DESIGN-txn: CHANGES_REQUESTED

- **F1 (blocker for CI, a11y)** `app/lib/features/transfers/presentation/split_sheet.dart:~444-500` (person-name `TextField`, `isDense: true`): the field renders 75x40 dp, so `a11y_rest_test.dart` "split sheet a11y" fails in all 8 variants (ar/en, light/dark, x1.0/x1.3): "Tappable objects should be at least Size(48.0, 48.0)". Money-adjacent flow (split / reimbursement) and the repo's tap-target rule. Required change: give the name field `minHeight: ZSpacing.minTarget` (constraints on the decoration or a `ConstrainedBox`), keep `isDense` visual padding if desired. Test: the existing a11y test must pass.
- **F2 (major, non-blocking)** chevrons in `txn_row.dart`/detail/split (`rtl ? chevron_left : chevron_right`).
- **F5 (minor, pre-existing)** `transactions_list_screen.dart:494` `l.commonDateRange(from, to)`: the generated signature is `(end, start)` and renders `$start – $end`, so a custom range shows `to – from`. Same bug the home hero fixed; swap the arguments.
- Ask, review queue, detail, split: callbacks, tooltips and keys preserved; transaction, ask and ingestion-review tests pass.

## DESIGN-insights: APPROVED

- Charts, chart detail, budget, bills: Gold gate on `locked_chart_card` and `gold_chart_card` unchanged in behaviour (tests pass); budget prev/next and `isCurrent` logic intact; bills accept/dismiss/edit intact.
- `startChevron/endChevron` return `chevron_left/right` and rely on `matchTextDirection`; this is correct (unlike F2) and `budget_screen` back/forward render right in RTL.
- F6 (minor): `ZChartColors` and a few tints are fixed `Color(0xFF…)` constants, not dark-aware, but contrast is acceptable for chart fills.
- Donut centre: the currency is recovered by regex (`ج\.م|[A-Z]{3}`) from the formatted string; works for the only Arabic symbol in `_arSymbols` (EGP) and ISO codes. Prefer `MoneyFormat.currencyLabel` (added in this batch) to avoid the string-parsing; minor.

## DESIGN-money: APPROVED

- Accounts tab, card detail, add-card flow, capture sheet, paywall, settings: keys, callbacks, Gold paywall (restore, buy, manage, close) preserved; money, accounts, gold and settings tests pass.
- Settings Gold card: free users still tap through to `destinations.onGold`; ARB keys `settingsMainGoldFree` / `settingsMainSeeGold` now hold the title / subtitle text respectively (key names no longer match the copy; nit).
- F2 applies to the Gold card chevron in `settings_main_screen.dart` (uses the same branch) and `money_tab.dart` uses `chevron_right_rounded` with explicit `textDirection: Directionality.of`, which is a no-op and correct.
- F6 (minor): per-row tints `Color(0xFF9585CF)`, `0xFF6A8FD8`, `0xFF3A6BC4`, `0xFF7A3A94`, `0xFF3F8C86`, `0xFF9585CF` in settings and money are hard-coded; move to tokens in a follow-up.

## F2 detail: chevron direction (major, non-blocking by sprint rule; fix recommended before release)

`Icons.chevron_left`, `chevron_right` and `chevron_right_rounded` are all `matchTextDirection: true`, so `Icon` already mirrors them in RTL. The new code branches manually (`rtl ? Icons.chevron_left : Icons.chevron_right`) and so mirrors twice: in Arabic the chevron points right (toward the text), the opposite of the mockups. The side-by-sides confirm it: `03-home.png` (review banner) and `16-settings.png` (Gold card, Preferences row) show `>` in the app against `<` in the mockup.
Locations: `home_widgets.dart` (review banner, `_Kpi`), `onboarding_parts.dart` and `ios_setup.dart` (rows), `txn_row.dart`, detail and split sheet (`rtl ? chevron_left : chevron_right`, three places), `settings_main_screen.dart` (Gold card).
Required change: use `Icons.chevron_right` unconditionally (it mirrors itself), or a single shared helper such as `endChevron` in `core/ui`. Add one RTL widget test that checks the rendered icon is `chevron_right`.

## Fix list (blocking)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| DESIGN-txn | `app/lib/features/transfers/presentation/split_sheet.dart:~444-500` | Person-name `TextField` must be at least 48x48 dp (`ZSpacing.minTarget`) | Existing `test/a11y/a11y_rest_test.dart` "split sheet a11y" (8 variants) must go green |

Recommended in the same fix pass, not blocking: F2 (chevrons), F3 (hero `MergeSemantics`), F5 (date range argument order).
