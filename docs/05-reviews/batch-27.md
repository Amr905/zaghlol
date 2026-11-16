# Batch 27 review (batch/2026-11-16-27): FU-243, SMS-fuzzy, FIX-category-icons, DESIGN-polish

Reviewer: code-reviewer (Opus; code and security in one pass). Scope: FU-243, SMS-fuzzy (which includes FU-243), FIX-category-icons, DESIGN-polish.
Tests run: `dart test` in `packages/zaghlol_parsing`, 1399 pass (including `generic_fuzzy_corpus_test.dart`, 49). `flutter test --exclude-tags benchmark,golden` on `test/features/{ingestion,transactions,home,accounts,capture}` and `test/core/ui`, 919 pass.
I also ran a probe, which is not committed: the Guard over `app/assets/guard/guard_base.json`, and the pipeline with the generic fallback over `app/assets/registry`, both with synthetic bodies. Its results are below.

## FU-243 (C4 ingestion): CHANGES_REQUESTED

Checked:
- **Known bank goes to its bank's account.** `ingest_raw_messages.dart` files a known-bank generic result as `ReviewKind.unrecognized` with `institutionCode` in the payload. In the A-66 auto-save branch it resolves `institution: g.institutionCode` (match on institution + last-4) and labels the account with the bank's registry label. It never creates a `g_…` account. Both tests assert this. Correct.
- **Same rules on Dart, Kotlin and Swift.** The new patterns are byte-identical (after folding) in `guard_base.json`, the devSms `spike_guard_base.json`, `registry/shared.json` and the test fixtures. The golden is shared, so the native Guards are held to the same cases. No native code changed, and none was needed.

The probe shows real transactions dropped by the new **global** drop patterns. The Guard drops before storage, so these messages are lost for good: there is no review item and no raw row. This happens for every sender (any bank, user senders, share, Shortcuts):

| synthetic body (sender HSBC EG and NBE, same result) | Guard |
|---|---|
| `Purchase of EGP 100.00 at OFFER MART. Available limit EGP 9,000` | drop `otp_or_promo_global` |
| `Your card *1234 was charged EGP 250.00 at BEST OFFERS STORE` | drop |
| `Transfer of EGP 500.00 to WIN TRADING completed` | drop |
| `Card 1234 purchase EGP 300 at WIN BIG MARKET` | drop |
| `Your account 1234 debited EGP 2,000.00 for credit card payment. Next due date 25/11` | drop |
| `Payment of EGP 1,250.00 received for your credit card. … Minimum due now EGP 0` | drop |
| `EGP 25.00 debited from account 1234 for e-statement fee` | drop |
| `Purchase EGP 1,000 at Noon. You earned 5% cashback EGP 50` | drop |
| `Congratulations! EGP 500.00 has been credited to your account 1234` | drop |
| `تم خصم ٢٠٠ جنيه من حسابك ١٢٣٤ لدى عروض مصر` | drop |
| `تم خصم ٥٠ جنيه رسوم كشف حساب من حسابك ١٢٣٤` | drop |

Findings:
- **BLOCKER (data loss), `app/assets/guard/guard_base.json:555-559` (and the same lines in `app/assets/registry/shared.json:10-14`, `spike_guard_base.json`, and the fixtures `t1_base.json`, `guard/registry/shared.json`, `pipeline/bundle/shared.json`):** the new promo and reminder patterns match single words with no transaction context: `(?:^|[^a-z])offers?(?:[^a-z]|$)`, `(?:you|to) … win`, `win (?:a|an|up|big…)`, `congratulations`, `due date`, `e-?statement`, `minimum … due`, `[0-9]%[ ]?cashback`, `(?:ال)?عروض`, `كشف (?:ال)?حساب`. They run before every template. A merchant name, a payment confirmation, a fee debit or a credited bonus is silently and permanently dropped. **Required change:**
  - (a) Make each promo/reminder pattern need promo context **and** reject bodies that carry a completed-transaction cue (`debited|charged|was used|purchase of|paid|credited|received|transferred|خصم|تم تحويل|تم سداد|اضافه`…). The Guard's global drop can't express "not", so either split these out into a separate list that the Guard drops only when no transaction cue matches, or keep them per institution (`byInst`). Per institution is what PO decision T-035 Q6 (PO_DECISIONS Part 1, line 20: "promo drop per bank only") says.
  - (b) Never match inside the merchant span, for example by anchoring `offer`/`win` to the start of the message or to `special|exclusive|limited offer`.
  - Add each body in the table above as a golden `keep` case, so the Dart, Kotlin and Swift Guards all pin it.
- **major (process, decides (a)), `golden.json` `promo.no_inst_pattern_kept` → `_dropped`:** this flips a case that pins PO decision T-035 Q6, without a PO_DECISIONS change. `guard_policy.dart:51-58` (`kGuardPromoDropPerInstitutionOnly = true`, "there is no global promo list (generic promo words collide with transaction words)") is now false documentation. Either get the PO's change recorded in PO_DECISIONS and update the marker, or move the promo patterns to `byInst`.
- minor, `golden.json`: the case `otp.ar.one_time_password` (`كلمة السر لمرة واحدة 9921 …`) was deleted and not replaced. Restore it; it is an OTP-drop pin.
- minor, `ingest_raw_messages.dart` (auto-save label): ingest labels a newly created account with `institutionLabel`. The SMS-fuzzy confirm labels it with the raw sender (`review_providers.dart`, `label: card.sender`). The same account gets different names depending on which path creates it first.

## SMS-fuzzy (C4 ingestion/money): CHANGES_REQUESTED

This branch includes FU-243, so the FU-243 blocker above also applies here.

Checked:
- **Extractor** (`generic_parser.dart`, `generic_keywords.dart`).
  - The corpus (68 tuning + 20 hold-out, synthetic) passes per-field precision/recall floors. The 15 known-sender negatives (OTP, promo, statement, balance-only, decline) give no transaction.
  - Probe:
    - An available limit before or after the amount picks the amount.
    - Salary + balance picks the salary.
    - `$20` gives USD, the existing bare-`$` marker.
    - `US$` gives USD; `AR$` is unreadable (never USD).
    - A masked card is never taken as the amount.
    - `05/11` gives 5 Nov.
    - `Store 12/31` is not taken as a date.
    - ATM with a fee picks the withdrawal amount.
  - Confidence is still capped at 700 and `needsReview` is always true.
- **Policy.**
  - Generic results never auto-save outside the existing A-66 tier (`genericDisposition` is unchanged).
  - `oneTap` needs `prefillComplete`, a known bank, a source and a positive amount.
  - A swipe or Confirm on an incomplete suggestion does nothing (`_accept` `MessageCardModel(txnId: null)`); the widget test covers this.
  - `confirmGeneric` re-reads the item, refuses a resolved item, and builds the transaction from the stored payload, not from the widget model. The resolve is transactional.
- **Privacy.** The payload holds fields only (no body). `templateSample` reads the raw body only when the user taps, and it is not logged (the test asserts `toString` holds no body text). The builder sample is kept in memory only.
- **Money.** Amounts stay `Money` (minor + currency). The `allowForeignCurrency` bypass is used only by the generic confirm (manual input keeps the check), which matches how ingest stores foreign currency.

Findings:
- **MAJOR (money/data integrity, blocking), `review_screen.dart:645-700` (`_MessageCard`) vs `review_providers.dart` `confirmGeneric`:** one tap stores, as `is_user_verified = 1`, fields the card never shows:
  - **the account.** `MessageCardModel.last4` is set but never rendered, and the bank account isn't named.
  - **the date** read from the message (`dateRead`, for example `05/11`), which can differ from the receipt date.
  - **the kind.** `genericTxnDirection` stores `transfer_out`/`transfer_in`/`refund`, but the card shows only "spent at" or "received". `You transferred EGP 2,000 to Ahmed` shows as spent at "Ahmed" and is saved as `transfer_out`, which leaves spend totals.

  `is_user_verified` means a re-parse never corrects these fields (PO T-076). This fails "confirm writes exactly the shown fields to the shown account". **Required change:** when `oneTap`, the card shows the account (bank label + `•••last4`, or "bank account" when there's no last-4), the date when `dateRead`, and the kind (transfer/refund/withdrawal) through existing or new l10n keys. Alternatively, confirm writes only what is shown (receipt date, plain expense/income). Add a widget test, in both `ar` and `en`, that the one-tap card shows last-4 and date, and a confirm test asserting `occurred_at` and `direction` equal what the card showed.
- minor, `review_screen.dart` `_confirmGeneric`: the snackbar reuses `accountsEditSaved` and `templatesBuilderTitle` with a TODO. Add the planned copy-deck keys (FU).
- minor, `review_screen.dart` `onEdit` for a suggestion: opens a blank Add screen and leaves the item unresolved. It isn't prefilled with the guess, so the user retypes and then has to dismiss the item as well. FU.
- minor, `template_builder.dart` `setSample`: pre-tags on every paste, overwriting the direction the user picked. Fine as designed, but the user's direction should win when the suggestion has none (it already does). Nit only.
- minor: no golden for the new prefilled one-tap card in either locale (goldens excluded here; check in the GitHub run).

## FIX-category-icons: APPROVED

- Every `Text(c.icon)` on the transaction list, detail, edit and filter sheets now renders `ZCategoryGlyph.glyphFor(id)`. The lint-style test (`test/core/ui/no_raw_icon_text_test.dart`) fails on `Text(x.icon` / `Text(x?.icon`. The harness now uses real icon keys (`restaurant`, `receipt_long`), and an ar/en test asserts that no icon name is shown.
- minor, the four call sites: `glyphFor(c.id)` keys on the category id, so a **user category's chosen icon** (`category_edit_screen.dart` `_icon`) is ignored and shows the fallback 🧾. `CategoryTile`/`iconFor(iconKey)` (`category_tile.dart:36`, used by budget and charts) respects it. Use the icon key here too. FU.
- nit: the lint regex only catches `Text(` with the icon as its first argument (not `Text('${c.icon}')` or `label: c.icon`). Acceptable for now.

## DESIGN-polish: APPROVED

- `money_tab.dart`: the Add control is now a labelled stadium pill (`accountsOverviewAdd`, l10n, `EdgeInsetsDirectional`), min height 48.
- `home_widgets.dart`: the greeting uses `FittedBox(scaleDown)` + `maxLines: 1`, aligned `centerStart`, so it is RTL-safe.
- `add_sheet.dart`: the Gold badge is in an `Expanded` + `Align(centerEnd)` with ellipsis, so it can no longer overflow the tile.
- `device_flows_test.dart` adds an Arabic pass. It switches language through the settings repository, uses synthetic data, and a failure there is evidence only.
- The existing ar/en tests (add sheet Gold badge, app shell at 1.3x text, home) pass.
- minor: no new widget test pins the badge at narrow width or the greeting at large text scale. Add one when goldens are refreshed (FU).
- nit: the Arabic pass in `device_flows_test.dart` finds tabs by literal Arabic text. If the copy changes, the pass fails without anyone noticing. It only prints `DEVICE_FLOWS_AR_FAILED`.

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| FU-243 (and SMS-fuzzy) | `app/assets/guard/guard_base.json:555-559`, `app/assets/registry/shared.json:10-14`, plus the spike and fixture copies | Promo/reminder drop patterns must not drop real transactions. Move them per institution (PO T-035 Q6), or require promo context and skip any body with a completed-transaction cue; never match `offer`/`win`/`عروض` inside a merchant span; don't drop payment confirmations or fee debits that mention `due date`/`statement`/`كشف حساب`; keep credited `Congratulations!` messages. Update `guard_policy.dart:51-58`, or record a PO change in PO_DECISIONS. | Golden `keep` cases for the 11 bodies in the FU-243 probe table (shared Dart/Kotlin/Swift golden); restore `otp.ar.one_time_password`. |
| SMS-fuzzy | `app/lib/features/ingestion/presentation/review/review_screen.dart:645-700`, `review_providers.dart` `confirmGeneric` | The one-tap card must show every field confirm stores as user-verified: account (bank + last-4), message date when read, and transfer/refund kind. Otherwise confirm writes only the shown fields. | Widget test (ar + en): the one-tap card shows last-4, date and kind. Repository test: the confirmed row's `account_id`, `occurred_at` and `direction` equal what the card showed. |
