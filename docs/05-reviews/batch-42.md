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

## Fix list (blocking)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| SMS-po42 | `app/assets/registry/institutions/cib.json:21` | Narrow the CIB drop to competition-only phrases. Remove the bare `تطبق الشروط والاحكام`. Regenerate the Guard bases and goldens. | CIB card purchase + T&C footer is inserted (pipeline + e2e + Guard golden keep). |
| SMS-po42 | `app/assets/registry/institutions/arab_bank.json:32` | `EG` sender: template matches only. Generic results go to review, never auto-saved. | `EG` non-template body with an amount and last-4 gives a review item, 0 transactions. |
| T-156b | n/a | Branch is empty: build and push it. | n/a |
