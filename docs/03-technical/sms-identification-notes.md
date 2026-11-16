# SMS identification and parsing: research notes

Task SMS-improve (2026-11-16). Paraphrased notes from public sources and what we applied. No message text from real users is quoted; every example is synthetic.

## 1. How financial SMS are told apart in practice

**Sender headers.** Banks send from an alphanumeric sender id (up to 11 characters), not a phone number. Egyptian banks use short brand ids (`CIB`, `NBE`, `QNB`, `BanqueMisr`, `HDB`...); wallets and InstaPay use brand names too. In India the DLT regime adds an operator or circle prefix and a category suffix (`VM-HDFCBK`, `AX-ICICIB-S`), so open-source parsers match the *core* of the header, case-insensitively, and ignore the prefix. Our registry already matches senders per institution (exact or regex); a regex rule such as `^[A-Z]{2}-?CIB(-[A-Z])?$` is the pattern to use if an operator ever adds a prefix.
Sources: [transaction-sms-parser](https://github.com/saurabhgupta050890/transaction-sms-parser), [BankSMSParser (PennyWise port)](https://github.com/rahatsayyed/BankSMSParser) (`isKnownBankSender`, one parser per bank, factory by sender).

**Cue scoring.** The common approach is a two-step test: (1) the sender is a known bank, or the body holds a money cue (currency marker next to a number) plus a transaction verb (debited, credited, purchase, transfer, withdrawn); (2) negatives win: OTP and "do not share", promotions, "declined", balance-only alerts. Our generic extractor already does this (decline, promo and OTP guards, then amount ranking by nearest cue).

**Field extraction.** Library consensus:
- Amount: a number touching a currency marker; ignore numbers after "balance/available/limit"; a number with no currency marker is not an amount (this is why a hotline such as `19666` never becomes one).
- Direction: verb dictionaries (debited/withdrawn/spent/paid vs credited/received/deposited), nearest to the amount; opposite verbs close together cancel to "unknown" rather than guess.
- Account: a cue (`a/c`, `card`, `ending`, `xx`, `المنتهي بـ`) then 3-4 digits; masks like `****0938` are normal.
- Merchant: after `at / to / from / info:`; strip terminal ids and city codes afterwards.
- Reference: after `ref / rrn / txn / utr`; must hold a digit.
- Date and time: several formats; time is optional.
Sources: the two repos above; [expensms](https://github.com/albertusdev/expensms) (Android SMS expense tracker).

## 2. What we applied (generic extractor, `packages/zaghlol_parsing/lib/generic/`)

| Idea | Change |
|---|---|
| Arabic transfer-out wording | expense cues `تنفيذ تحويل`, `من حسابك/حسابكم`, `from your account`, `made from your` |
| Receiver wording must not read as spend | `received ... transfer of` no longer counts `transfer of` as an expense cue |
| Reference cue in Arabic | `برقم مرجعي`, `رقم مرجعي`, `مرجعي` (the digit rule still applies) |
| Time of day | a `hh:mm` right after the date replaces the receipt time of day (`17-05-2026 22:32`) |
| Merchant stop words | `برقم`, `بالرقم`, `للمزيد`, `for more` end a merchant/counterparty span |
| Hotlines | already safe: a number without a currency marker is never an amount; tested with `الاتصال بـ 19666` and `call 19666` |

## 3. Registry (data)

CIB's instant transfer (`تم تنفيذ تحويل لحظي ... من حسابك المنتهي بـ ****NNNN برقم مرجعي ... بتاريخ dd-MM-yyyy hh:mm`) is a template (`cib.instapay_out.ar`, source `po-sample`). The same four shapes (out/in, ar/en) were added as `synthetic-unverified` for CIB, NBE, Banque Misr, QNB, ALEXBANK, Credit Agricole, AAIB, HDB, Faisal, Banque du Caire, FABMISR and ADIB. Each has 4 fixtures (plain, thousands, minimal, Arabic digits). Replace the wording when real samples arrive.

## 4. Known gaps

- Incoming instant-transfer wording of the other banks is a guess.
- Template dates are `d-M-yyyy` only for these shapes; a 12-hour clock with am/pm is not read by the generic reader (templates can use the `time` group).
- No `transfers` or `cash` system category exists in the seed; transfers are classified by direction and ATM withdrawals carry the withdrawal event. Adding categories is a product decision (bucket, budgets).
