# Batch 42 review (Opus, code + security)

Branch `batch/2026-11-18-42`. Tests run: `packages/zaghlol_parsing` (1556 pass), `tools/registry_lint` (8 pass), app `test/ingestion` + `test/features/categorization` (275 pass). I also ran adversarial bodies through the bundled registry in a scratch test, which I deleted afterwards.

## SMS-po42: PO real-phone SMS reports, verdict CHANGES_REQUESTED

Good: USD salary keeps `USD` (5966 minor, not converted). Hotline 19100 is never read as the amount (e2e). The Mashreq terminal-id strip works. Salary maps to `sys:income`, which is seeded. `registryVersion` is 6. Guard bases are regenerated (app + devSms spike), and `golden.json` is updated for the Kotlin/Swift runners. Fixtures are synthetic. A plain CIB `تم سحب مبلغ` still reads as a withdrawal.

| # | Sev | File:line | Finding | Required change |
|---|-----|-----------|---------|-----------------|
| 1 | **major (data loss)** | `app/assets/registry/institutions/cib.json:21` | The drop runs before template matching (`parsing_pipeline.dart:62,130`). The bare `تطبق الشروط والاحكام` alternative drops real CIB transactions that carry a T&C footer. Verified: the CIB card-purchase fixture with `استمتع بخصم 10% تطبق الشروط والأحكام` appended gives `ParseDropped`, so nothing is stored. | Drop only on the competition-specific phrases (`ترخيص رقم`, `هذه المسابقه`, `مسابقه تحت اشراف`, `دخول السحب`). Remove the bare T&C alternative, or guard it with a negative lookahead on completed cues (`تم\|عمليه شراء\|بمبلغ`). Regenerate the Guard bases and goldens. Test: a CIB purchase plus a T&C footer is inserted. |
| 2 | **major (money)** | `app/assets/registry/institutions/arab_bank.json:32` | The exact alias `EG` maps any `EG`-sender text to Arab Bank. That text is Guard-kept, and the generic path auto-saves it when it has a direction plus a merchant or last-4 (`generic_policy.dart:68`). Verified: `EG` + `تم دفع 250.00 جنيه فاتورة كهرباء` gives `ParseGeneric inst=arab_bank`. `EG` is a generic country-code sender, so other senders' texts can be filed as Arab Bank spend. | For the `EG` alias, accept template matches only. A generic result from that sender always goes to review (never auto-saved). Test: a non-template `EG` body with an amount and last-4 gives a review item, no transaction. |
| 3 | minor | `packages/zaghlol_parsing/lib/generic/generic_keywords.dart:224` | Arabic promo words match as substrings. `عرض` hits `معرض`, so `عملية شراء ... لدى معرض الاثاث` (CIB) moves from generic purchase to unrecognized. `تم سحب` is not in `completedTransactionCues`, so an ATM text with a promo footer (`فرصتك`) is unrecognized. Both go to review, so no loss. | Use an Arabic word boundary for `عرض`/`فرصه`/`شهاده`. Add `تم سحب` to `completedTransactionCues`. FU. |
| 4 | minor | `app/lib/features/ingestion/domain/ingest_rules.dart:264` | The `'sys:income'` literal sits beside `kCashCategoryId`/`kInstapayCategoryId` constants. | Add a `kIncomeCategoryId` constant. FU. |
| 5 | minor | `vodafone_cash.json` | All 7 templates are `synthetic-unverified`, at baseConfidence 0.9. | Re-verify against real PO samples. FU. |

## T-156b: PDF statements, 3 layouts + scanned path, verdict CHANGES_REQUESTED (not built)

`origin/task/T-156b` equals `origin/main` (38042fb4). It has no commits, and nothing from it is merged into batch 42. Nothing to review. When it is built, the review will require the following:

- Rows that fail balance reconciliation go to a user review/flag step, never silently dropped.
- A statement without a year (the scanned sample) asks the user to confirm the year, or flags the rows. No silent fallback to "today".
- Rendered OCR images are deleted, the scan goes through the existing `OcrHost` (Android T-159 + iOS) and nothing is uploaded.
- Integer minor units and an explicit currency.
- No re-import of the page-2 by-type/checks tables.

## T-156b (review)

Head `fd8a30b2` (C4: financial import). Production diff read in full. Tests run: `packages/zaghlol_parsing test/statements` 60/60 green, `app test/features/export_import` 96/96 green. PDF sources are still `available: false` in `import_ports.dart`, so no UI can be reached and no strings are hard-coded. The missing l10n keys must be added before the sources are turned on.

**Verdict: CHANGES_REQUESTED**

Correct: the ar/en header synonyms ("Payment Type" is ignored, "Date" beats "Transaction Date"). Total/closing/end-of-transactions lines and undated brought-forward lines are skipped. The Dec→Jan rollover works in both orders. Sections with a different signature (by-type, checks) are dropped, and repeated same-signature sections are dropped at the 80% match. Money is integer `Money`, `parseStatementAmount` strips the currency markers, and `suggestedCurrency` is only a proposal. Scans: text layer first, OCR only on `noText`. The PNG gets a neutral name and is deleted in `finally`. The host seals it and deletes the plain copy. Nothing is logged and there is no network code.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | major (data loss) | `packages/zaghlol_parsing/lib/statements/pdf/statement_rows.dart:401`, `app/lib/features/export_import/application/import_statement_pdf.dart:250` | A row whose balance doesn't reconcile is dropped. It only shows up as an anonymous "bad amount" count. A real transaction is lost without the user noticing. | Keep these rows in the result as flagged rows (`needsReview`, with the parsed amount, direction and printed balance). Pass them to a review step and don't drop them. Give them their own `ImportRowProblem.balanceMismatch` and don't merge it into badAmount. |
| 2 | major (money direction) | `statement_rows.dart:324,409` | An unsigned amount with no previous balance falls back to `isExpense: false`. This hits the first row when there is no opening balance, and any row after one with no printed balance. Checked: `SHOP A 100.00 / bal 900.00` as the first row is imported as **income** with `balanceChecked=false`. | When `unsigned && derivedExpense == null`, flag the row for review (same path as #1). Never default it to income. |
| 3 | major (data) | `packages/zaghlol_parsing/lib/statements/pdf/statement_table.dart:586` | If the statement prints no full date anywhere (the scanned sample), the year silently comes from today. An older statement gets the wrong year, and dedupe by day misses the existing rows. Batch-42's first pass already required no silent fallback. | Expose `StatementTable.yearSource` (`printed` / `today`). When it is `today`, the preview asks the user to confirm or change the year before commit, and the use case doesn't commit without that answer. |
| 4 | major (AC: scans on Android) | `app/lib/features/capture/application/scan_providers.dart:25` | The Android OCR host from T-159 is merged in batch 39, but `ocrEngineProvider` still returns `UnavailableOcrEngine` on Android. Every Android scan fails as `noText`. The note at `T-156.md:59` ("T-159 deferred") is stale. | Return `PigeonOcrEngine()` on Android too (or a platform check that includes Android), and fix the note. Test: the provider gives a Pigeon engine on `TargetPlatform.android`. |
| 5 | minor | `app/lib/features/export_import/application/statement_pdf_providers.dart` | Production code never uses `statementPdfExtractorProvider` or `ImportStatementPdfUseCase` (there is no `ImportRunner` for PDF). | Wire it up when the PDF sources are turned on (follow-up). |
| 6 | minor | `statement_table.dart` (group choice) | A no-balance group with more than twice the rows beats the balance table, and then its direction can't be told. | Prefer the balance table whenever it exists, or flag the import (follow-up). |
| 7 | minor | `app/lib/features/export_import/data/pdfrx_page_rasterizer.dart` | The rendered page is a plain PNG in temp until it is sealed. This matches the existing scan path. | Follow-up: render straight to the sealed spool once the port allows it. |

## Fix list (blocking)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| SMS-po42 | `app/assets/registry/institutions/cib.json:21` | Narrow the CIB drop to competition-only phrases. Remove the bare `تطبق الشروط والاحكام`. Regenerate the Guard bases and goldens. | CIB card purchase + T&C footer is inserted (pipeline + e2e + Guard golden keep). |
| SMS-po42 | `app/assets/registry/institutions/arab_bank.json:32` | `EG` sender: template matches only. Generic results go to review, never auto-saved. | `EG` non-template body with an amount and last-4 gives a review item, 0 transactions. |
| T-156b | `statement_rows.dart:401`, `import_statement_pdf.dart:250` | Balance-mismatch rows go to a review/flag step with their own problem kind. They are never dropped. | Mismatched row is in the result, flagged, and not committed until the user confirms it. |
| T-156b | `statement_rows.dart:324,409` | An unsigned amount whose direction can't be derived is flagged for review. It never defaults to income. | First row, no opening balance, unsigned 100.00, gives a flagged row and no income. |
| T-156b | `statement_table.dart:586` | Year from today is exposed (`yearSource`), and the user confirms the year before commit. | Statement with no printed full date: commit is refused until the year is confirmed. |
| T-156b | `scan_providers.dart:25` | Android uses `PigeonOcrEngine` (T-159 host). Update the note at `T-156.md:59`. | The provider returns a Pigeon engine on Android. |
| T-156b | n/a | Branch is empty: build and push it. | n/a |

## Delta re-review (T-156b fix round)

Commit 0f117ed1 (on top of fd8a30b2), merged locally. Tests run: `packages/zaghlol_parsing test/statements` 64 pass; `app test/features/export_import test/features/capture` 449 pass.

1. Balance mismatch: FIXED. Rows move to `StatementParseResult.review` with an amount in integer minor units; `run` throws `reviewRequired` with no decision, and writes nothing. Tests (balance mismatch held, throws, store empty; keep/skip/flip) fail without the fix.
2. Unknown direction: FIXED. Unsigned and not derived gives `directionUnknown`; `keep` is rejected for those rows. Tests cover the no-balance and first-row cases.
3. Year: FIXED. `StatementYearSource.today` makes a real import throw `yearNotConfirmed` until `confirmedYear`; a printed period or statement date anchors without asking. Tests cover both paths.
4. Android OCR: FIXED. `ocrEngineProvider` returns `PigeonOcrEngine` on Android; the Android OCR host exists (`platform/ocr/OcrHosts.kt`). Images are deleted and nothing is uploaded, per the provider doc and T-159.

Findings:
- minor, statement_rows.dart (`plainIsIncome`): with no balance column and any negative sign in the amount column, unsigned rows are read as income. That is a silent default, a narrow one, and a convention rather than a derivation. Follow-up: flag these rows as unknown, or show the assumption in the preview.
- nit: `StatementRowProblem.balanceMismatch` is now unused; remove it later.
- nit: no UI caller of `run(decisions:, confirmedYear:)` was found in this diff. The review and year screens must be wired before the feature ships, or an import will throw. Track it as a follow-up.

**Verdict: APPROVED** (no blocker or major remaining).

## Lead delta check: SMS-po42 fix round (2026-11-18)

- **fa310efc:** `templateOnly` sender rules. For sender `EG` only an Arab Bank template match is filed as Arab Bank; anything else goes through the generic path as an unknown sender, so it lands in review and is never auto-saved. The registry schema and loader carry the flag. e2e test: an electricity-bill text from `EG` becomes a review item with no transaction.
- **CIB promo drop, Lead follow-up commit:** the bare T&C footer is removed (fa310efc). The Lead also narrowed `السحب على` to draw wording only (`السحب على كيلو/جوايز/جايزه…`, `السحب الجاي`), so a real `تم السحب على حسابكم` withdrawal is kept. Guard bases are regenerated; registry_lint passes 1395/1395 and the ingestion tests pass 117. New e2e test: the withdrawal is kept and the promo is dropped.

Verdict: SMS-po42 **APPROVED**; T-156b **APPROVED** (delta re-review). Batch 42 approved.
- **FU-262:** batch-42 minors: an unsigned row is read as income when other rows have minus signs; `balanceMismatch` is unused; the statement import UI (review decisions, year confirmation) and its l10n keys are not built yet, so the importer throws until those screens exist (T-156/T-158 wiring); Vodafone Cash templates wait on a real sample.
