# SMS-auto: bank SMS read and saved automatically (C4, ingestion)

PO report (real Android phone, 2026-11-16, after batch 29): HSBC SMS are not read, and Home shows "124 transactions waiting for your review". PO decision SMS-AUTO in `docs/workflow/PO_DECISIONS.md` Part 1.

## Design note

**Finding (HSBC).** The two PO messages (synthetic digits) parse on current `main` through the whole Dart path for senders `HSBC`, `HSBC EG`, `HSBC-EG`, `HSBC_EGY`: Guard keeps, template `hsbc.card_used_limit.en` matches (confidence 950), the transaction is stored, `available` is the limit, USD with an EGP limit is not currency-ambiguous. The generic reader also reads both cleanly (no `currencyAmbiguous`). What fails on a phone that already ran an older build is state: the messages (and 100+ others) were stored as `review` raw rows by the build before the HSBC template fix, and `registryVersion` stayed `1` through every registry/template change since, so the T-076 re-parse job (which only looks at rows stamped with an older registry version) never looked at them again, while body-hash dedupe stops the same text from being ingested again. Fix: bump the registry version (manifest, Guard bases) and re-parse review rows under the new rules.

**Confidence rule (generic result, auto-save).** All must hold:
1. the sender resolved to a registry institution (`institutionCode != null`);
2. origin is background capture, inbox scan or re-parse (never share/paste/OCR: the user is looking at those);
3. direction is set (expense, income, or a settlement/transfer event) and none of `directionConflict`, `directionUnknown`, `amountAmbiguous`, `currencyAmbiguous` is among the reasons;
4. amount > 0 with a currency read next to it (field confidence amount >= 700, currency >= 850);
5. a card last-4 or a merchant was read (not sparse).
Otherwise it goes to review as before. The A-66 path (3 confirmations + "always capture") stays for unknown senders and still leaves a `low_confidence` review item; the new path leaves none.

**Settlement.** A message with a card word and a payment-received cue ("payment received on your credit card", `تم استلام سداد`) is `GenericEvent.ccPayment`, direction income, stored as `transfer_in` on the card account; "paid/debited ... to your credit card" is `transfer_out` from the paying account. Never an expense or income. Template-level `cc_payment` already maps to transfers (`dispositionOf`).

**Review card.** Shows the original message text from the raw row (decrypted DB, on screen only), collapsed by default.

**Re-parse.** `_reparseOne` lets a generic result that meets the rule promote the same raw row and write one transaction; a row that does not meet it is stamped, no new review item. A raw row maps to at most one transaction, so re-running never duplicates.

**Registry templates.** Settlement templates for HSBC, CIB, NBE, Banque Misr, QNB (EN + AR), `source: synthetic-unverified`.

## Missing l10n keys
(see end of file)
