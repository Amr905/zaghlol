# ADR-017: Localization approach

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-L10N-*, NFR-UX-01 |

## Context
Arabic (Egyptian colloquial, RTL) and English (LTR); digits per preference (A-29); no hard-coded strings; copy deck keyed (Phase 2 part 2).

## Options considered
1. ****Flutter gen-l10n (ARB + ICU plurals/select), `ar_EG` + `en`**** — First-party, type-safe getters, works with `intl` number/date formatting.
2. **easy_localization / slang** — Runtime loading or alternative codegen; extra dependency.

## Decision
**gen-l10n** with `app_ar.arb` as the template locale (Arabic first). A `DigitsMode` preference wraps `NumberFormat` (`ar_EG` gives Arabic-Indic digits, `en` gives Western). `Directionality` follows the locale. Currency display rules live in `MoneyFormat`. Lints forbid string literals in widgets.

## Consequences
Copy-deck keys map 1:1 to ARB keys. Golden tests run per locale.
