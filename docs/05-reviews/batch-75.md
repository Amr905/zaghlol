# Batch 75 review: T-261 (C2)

Verdict: **APPROVED** (no blocker, no major).

Checks: `dart analyze --fatal-infos` clean, `dart test` 1709 pass (packages/zaghlol_parsing), `flutter analyze` clean (app).

## T-261 receipt row segments

Adversarial synthetic texts run through `ParsingPipeline.parseOcr` (scratch, not committed). All gave the right total:
- `Total 150.00 Paid 200.00 Change 50.00` and the reversed order, `Subtotal/VAT/Total` in both orders, `Total ... Remaining 50.00`, `Total 150.00 Cash 150.00` and the reverse.
- Amount-first rows with 2 and 3 labels, English and Arabic (`150.00 الاجمالي 200.00 المدفوع 50.00 الباقي`), and label-first Arabic rows.
- `Total - 150.00` gives 150.00 (a spaced dash is fine). `Total: 150.00 - Paid 200.00` gives 150.00.

Merchant: real names kept (`Al Ahram Pharmacy`, `Cairo Pharmacy`, `Alex Coffee`, `صيدلية العزبي`). Empty (acceptable) for names containing a rule word: `Seller Pharmacy`, `Branch Office Supplies`, `Express Delivery Co`, `Item 7 Store`, `Mobile Hotline Shop`, `سوبر ماركت سعر حلو`. No wrong merchant seen.

Findings (minor, follow-ups from FU-342):
- minor, receipt_parser.dart `_notMerchantWords`/`_phoneLine`: substring rules on a word anywhere in the line (item, price, delivery, seller, سعر, hotline) blank legitimate names that contain them. Safe direction (empty), could be narrowed to line-start or label-with-colon.
- minor, receipt_parser.dart `_buildLine`: `Total -150.00` (dash glued to a point-amount after a space) is now unrecognized (it was accepted before). Defensible, since a negative is not a total, but it also drops a refund-style total. Hints only.
