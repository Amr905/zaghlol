# Batch 23b review: FU-ui

Reviewer: code + security, one pass. Tree: batch/2026-11-15-23. Tests run: `flutter test --exclude-tags benchmark,golden test/core test/features/{accounts,insights,onboarding,settings,capture} test/app` -> 1904 passed, 1 skipped, 0 failed.

## FU-ui: CHANGES? No. Verdict: APPROVED

Checked: card-added screen (justAdded banner, waiting header, empty state, due-day line), scan bank chips, scan results Edit link, Insights period chip, emoji map, tint tokens, renamed settings keys, notification re-check on resume, FU-045, FU-046, FU-125.

Behaviour
- Period chip: `chartsCurrentCycleProvider` returns the previous cycle via `cycleOn(current.start - 1 day)`. Every chart and explainer, plus the currency list, derives from it, so currencies and data are per currency and for the selected cycle. No cross-currency sums are introduced. `burnCurve` and `monthVsAverage` cap elapsed days to the cycle length, so a complete past cycle is not over-extended (projection equals actual). Time-based charts (net worth, installments, subscriptions, inflation) correctly ignore the chip.
- FU-045: masked text never falls back to the real amount, and the semantics label ignores a caller `semanticsLabel` when masked. No amount reaches the accessibility tree.
- FU-046: `ZColors.lerp` interpolates all fields, including the new tints; `brightness` flips at 0.5.
- FU-125: `errorBuilder` returns Home and never renders or logs the location. Good for privacy (links may carry user text).
- Notification resume re-check: observer added and removed, `mounted` guard, errors swallowed, state kept. Correct.
- Scan chips: codes only (no sender text or message content); a fallback to the count text remains. Equality and hash include the codes.
- Edit link: hidden when `onEditCard` is null; one card goes straight to the editor.
- Tints: light and dark values both defined; hard-coded colors removed from settings and add-card.
- Strings: all new text uses l10n keys that exist in ar and en. Renamed keys have no stale references.
- RTL: new layouts use `AlignmentDirectional`/`EdgeInsetsDirectional`; the period chip is `ExcludeSemantics` with the tooltip as its label, so a11y is intact.

Findings (none blocking)
1. minor, app/lib/core/ui/z_money_text.dart:12-17: the `ZMoneyText` class doc comment is now attached to `kMaskedAmountFallback` (the constant was inserted between the doc and the class). Move the constant above the doc.
2. minor, app/lib/features/accounts/presentation/card_detail/card_detail.dart (header `waiting` branch, `accountsDetailAvailableOf('—', ...)`): hard-coded em dash as a user-facing placeholder inside a localized sentence. Acceptable glyph but prefer an l10n placeholder or a ZMoneyText-style dash constant.
3. minor, card_detail.dart `_NavRow` subtitle `Column` uses `CrossAxisAlignment.start`, which is directional-safe. No change needed; noted only so it isn't re-raised.
4. minor, app/lib/features/insights/presentation/charts/charts_screen.dart:95-98: the period chip is not shown in the loading or error states, so it appears only once currencies load. Also the chip choice persists in a global provider across tab visits (never resets to "this cycle"). Product call; follow-up.
5. minor, app/lib/features/onboarding/presentation/scan_results.dart `_pickToEdit`: the sheet lists `i.label` (user card label), which is fine, but two cards with the same label are indistinguishable. Follow-up.
6. nit, app/lib/features/capture/domain/scan_plan.dart:578-585: `_sameCodes` was inserted between the `ScanProgress` doc comment and the class; same displaced-doc issue.

Security/privacy: no logging added; no backend calls; no money as double; no raw SMS content touched. Nothing to fix.

## Fix list

None (no blocking findings).
