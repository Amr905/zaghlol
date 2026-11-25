# Review — batch 68 (T-242, T-243, T-245)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus, code + money/security) |
| Date | 2026-11-25 |
| Commit / diff | `batch/2026-11-25-68` @ 668e0d6e, `git diff origin/main...HEAD` (main 2b53739) |
| Verdict | T-242 CHANGES_REQUESTED · T-243 CHANGES_REQUESTED · T-245 APPROVED |

Commands run:
- `dart analyze --fatal-infos` (repo root): no issues.
- `dart test` in `packages/zaghlol_parsing`: 1659 passed (PO suite 12/12, negatives pass).
- `dart test` in `tools/registry_lint`: 8 passed.
- `flutter test test/ingestion test/features/ingestion test/features/accounts test/features/recurring test/features/settings test/features/backup`: 971 passed, 8 failed. All 8 are `review_screen_golden_test.dart` (known local font issue).
- Scratch probes (not committed, deleted): (a) an app ingest test that stores an HSBC statement for card 9225 and then ingests PO case 10 for that card through `buildIngestRawMessages` with the bundled registry; (b) a parsing test that runs fee messages through `ParsingPipeline` on the batch tree and on `origin/main`. Results are under T-242 M-1 and T-243 M-2.

---

## T-242 — HSBC card payment, Arab Bank templates, trailing minus (C2) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| PO cases 1, 3, 5, 10, 11 pass | PASS (parse level) | `po_suite_test.dart`; but see M-1 for what case 10/11 becomes in the app |
| Registry lint green with new fixtures (≥4 per template) | PASS | `tools/registry_lint` 8/8; 4 fixtures each under `app/test/fixtures/sms/arab_bank/`, `hsbc/` |
| No other bank's fixtures change result | PASS | registry lint + parsing suite green |
| Trailing `-`/`+` is a sign marker, never negative | PASS | `stripTrailingSignMarker` in `amount_parser.dart`; used for every template amount group |
| `ddMMMyy` / `MMM` dates | PASS | `template_extractor.dart` `parseTemplateDate`, schema shape |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-1 | **major** (money) | `app/assets/registry/institutions/hsbc.json:194,196` | `hsbc.cc_payment_transfer.en` has `direction: expense` and `last4` = the card. `dispositionOf(ccPayment, expense)` (`ingest_rules.dart:81`) gives `transfer_out`, and the account is resolved by the card's last-4 (kind `credit`). Probe: statement for card 9225, then case 10 → `transactions`: `acc_9225, transfer_out, 219995, balance_after_minor 0`; `account_balances`: card balance set to **0** (that is the *source account's* available balance); stored `card_due.hsbc.9225` stays `paid: 0`. So the payment is recorded as money leaving the card (debt goes up, not down), the card gets another account's balance, and T-245's hook (it only counts `transfer_in` on a credit card) never sees it, so the due is never marked paid. The existing `hsbc.cc_payment.en` and the generic settlement path (batch 30, `ingest_raw_messages.dart:1981-1986`) both store a card payment as `transfer_in` on the card; this template contradicts them. | Store it as a transfer **into** the card: `direction: income` (→ `transfer_in` on the card account), like `hsbc.cc_payment.en`. Do not record the trailing "available balance" on the card (it belongs to the unidentified source account): drop the `balance` capture for this template or make it a non-captured group. Adjust PO suite cases 10/11 (the PO's "outflow"/"source account balance" describes the source account, which the app cannot identify; the PO note "classified as internal card settlement to avoid double-counting" supports transfer-in); add a short comment in the suite. Add one app ingest test: case-12-style statement for the card, then case 10 → one `transfer_in` on the card, no card balance row from it, due `isPaid` (min ≤ amount). |
| m-1 | minor | `app/lib/features/ingestion/application/ingest_raw_messages.dart:1100` | The source account mask `002-411***-001` is stored as `counterparty_kind = person`. It is an own account, not a person; a later P2P categorizer rule could treat it as a person transfer. | FU-298 (owner T-242 lane): map an account-mask counterparty to a non-person kind or to `reference_no`. |
| m-2 | minor | `app/assets/registry/institutions/arab_bank.json:30-33` | The `EG` sender is `templateOnly` for Arab Bank (pre-existing). The new `arab_bank.account_purchase.ar` shape (`شراء بمبلغ EGP … من حساب ***NNNN`) is generic enough that another bank sending from `EG` would be attributed to Arab Bank. | FU-299: confirm with sample data that `EG` is Arab Bank only, or require the `EG` path to match only the card templates. |
| n-1 | nit | `packages/zaghlol_parsing/lib/registry/template_extractor.dart:353` | `_monthNumber` accepts any word with a month prefix (`mayor` → 5). | Optional: accept only the 3-letter or full month name. |

---

## T-243 — generic reader v2 (C3) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| PO cases 2 and 4 pass (counterparty from `BanqueMisr`) | PASS | `po_suite_test.dart` |
| Generic-only re-run of cases 1, 3, 5: amount, direction, last-4, merchant, balance | PASS | `generic_v2_test.dart` "PO cases 1, 3, 5 without a template" |
| Existing generic tests and FR-PAR-13 unseen set do not drop; report before/after % | PARTIAL | Tests green; one unseen row changed `merchant`→`counterparty` (spec item 2). The before/after percentage is not reported in the task file (m-3). |
| T&C footer is not a transaction; pending marker removed | PASS, but over-broad (M-2) | `po_suite_test.dart` negatives |
| Counterparty stored on auto-save and one-tap confirm | PASS | `sms_auto_e2e_test.dart` "generic transfer: counterparty stored, no merchant"; `review_providers.dart`/`review_repository.dart` pass `counterpartyKind/Value` |

### Auto-save widening (focus 2)
`genericAutoSaveEligible` now accepts a counterparty as the party. The other SMS-AUTO gates are unchanged (known institution, direction read with no direction reason, income needs an event, amount ≥700 and currency ≥850 confidence, no amount/currency ambiguity). `_counterparty` runs only when a direction is known and a transfer keyword is present, and only after the amount, so it cannot change the amount or direction; it only replaces the merchant as the anchor. The SMS-AUTO rule still holds. The generic `balance`/`available` are read but not written by the generic ingest path, so no wrong balances come from them.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-2 | **major** (data loss) | `packages/zaghlol_parsing/lib/generic/generic_parser.dart:52,1271-1290`; `generic_keywords.dart:719-734` | `_onlyFeeFooter` drops every sentence that holds any fee word (`late fee`, `fee of`, `غرامه تاخير`, …) **including its completed-transaction cue** (comment at :1289), then rejects the message as `genericPromotion`. A real, posted fee is a one-sentence message, so it is now dropped. Probe (sender with no template, share channel), batch vs `main`: "A late fee of EGP 150.00 has been charged to your card ending 1234." → `genericPromotion` (main: generic expense, last-4 1234); "Late fee EGP 150.00 debited from your card ending 1234" → `genericPromotion` (main: generic expense); "تم خصم غرامه تاخير 150 جم من بطاقتك المنتهية 1234" → `genericPromotion` (main: generic expense); "Annual fee of EGP 300.00 debited from account 1234" → `genericPromotion` (main: generic expense). A charge the bank took no longer reaches review or the ledger. | Treat a sentence as a footer only when it is hypothetical: it holds a conditional/terms cue (`applies if`, `apply if`, `may be charged`, `will be charged`, `terms and conditions`, `terms apply`, `تطبق الشروط`, `الشروط والاحكام`) **and** no completed cue inside the same sentence (`has been charged`, `debited`, `تم خصم`, …). Plain fee nouns (`late fee`, `fee of`, `غرامه تاخير`, `رسوم تاخير`) must not on their own make a sentence a footer. Add the four probe messages as tests that must stay generic transactions, next to the existing T&C negative. |
| m-3 | minor | `docs/04-tasks/tasks/T-243.md` | AC asks to report the unseen-set before/after percentage; not reported. | FU-300: add the numbers to the task file. |
| n-2 | nit | `packages/zaghlol_parsing/lib/generic/generic_policy.dart:65` | Doc comment still says "a card last-4 or a merchant was read". | Add "or a transfer counterparty". |
| n-3 | nit | `generic_parser.dart` (`_balances`) | `TODO(T-242)` for the trailing-minus helper: T-242's `stripTrailingSignMarker` is now in the same batch. | Use the helper or drop the TODO. |

---

## T-245 — card dues from notices (C3, money) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Case 7/8/12 fixtures update the card's due, no transaction | PASS | `card_dues_ingest_test.dart` "case 7 …", "case 8 …", "case 12 …" |
| A later notice replaces an older; an older never replaces a newer | PASS | `card_dues_ingest_test.dart` "a later notice replaces …"; `card_due_test.dart` `mergeNotice` (older and equal rejected) |
| Payment marks paid; partial keeps reminding for the rest | PASS | `card_dues_ingest_test.dart` "payments" group (CIB `transfer_in` template). The HSBC case 10/11 payment does not reach it today: T-242 M-1. |
| No card: kept and applied when the card is created | PASS | "a notice with no card is kept and applied …"; `syncCardDues` → `applyPending` |
| Typed due day changes only for a newer notice | PASS | "the typed due day is kept …", "a newer notice moves the typed due day" |
| Card due line widget test in `ar` and `en` (light/dark goldens if the screen has goldens) | PARTIAL | `card_due_line_test.dart` (ar/en, light/dark, finders). `card_detail` has goldens, but no golden with the due line (m-6). |

### Security / money
- Never paid on doubt: `CardDue.isPaid` needs a known positive threshold (min, else total); with neither the due is never paid. Payment counted once per txn id, same currency only, on or after the statement date (notice day when unknown). OK.
- Older notice never overwrites: `mergeNotice` rejects `noticeAtMs <= existing`. Order is the message's received time; a re-parse keeps the original time. OK.
- Generic notices without last-4 never attach (FU-295 m-3): `onNotice` returns when institution, last-4 or currency is missing. OK.
- Settings keys `card_due.<inst ≤40>.<last4>` are at most 54 chars of `[a-z0-9_.]`, so they pass the backup `settings.json` key check (`backup_contents.dart:47`) and restore with the DB; "delete everything" removes the DB, so the keys go with it. Values are amounts, dates and txn ids only; nothing is logged. OK.
- `double`: none. Strings in ARB (ar Egyptian colloquial). RTL: plain `Text` in the existing column.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| m-4 | minor | `app/lib/features/recurring/data/card_dues.dart:116-175` | When a newer notice moves the account's `statement_due_day`, an existing item's `due_day` is not updated. The next `syncCardDues` sees `item.dueDay != day` and resets `next_due_date` to `nextDueOnOrAfter(today, day)`; for a notice whose due date has passed, that hides an unpaid due by a month. `progressAfterPayment` also uses the stale `item.dueDay`. | FU-301: also write `dueDay: Value(day)` in the update branch. |
| m-5 | minor | `app/lib/features/recurring/data/card_notice_hooks.dart:29` | The payment hook swallows any error inside the message savepoint; a failure after `_write` (settings says counted) but before the item update leaves the two out of step. | FU-302: run `onPayment` in its own nested savepoint so a failure rolls back both writes. |
| m-6 | minor | `app/test/features/accounts/presentation/card_due_line_test.dart` | No golden of the due line although `card_detail_golden_test.dart` exists (AC). | FU-303: add the due-line state to the card detail goldens (ar/en, light/dark). |
| m-7 | minor | `app/lib/features/recurring/data/card_dues.dart:142-147` | A statement with zero due creates or updates a reminder of EGP 0 that never becomes paid (`isPaid` needs a threshold > 0); the card shows "Due EGP 0.00". | FU-304: treat a zero total/minimum as settled (no reminder, line says nothing is due). |
| n-4 | nit | `app/lib/core/l10n/app_ar.arb` (new keys) | `@description` is `"L"` for the five new keys. | Write real descriptions. |

---

## Checklist
- [x] `dart analyze --fatal-infos` clean
- [x] Tests added and passing (parsing 1659, registry lint 8, app 971 + 8 known golden font failures)
- [x] RTL + LTR verified (T-245 due line, ar/en tests)
- [x] No hard-coded strings
- [x] No `double` money, explicit currency
- [x] No sensitive data in logs (fixtures synthetic; nothing logs message text)
- [x] Stays within the tasks' scope

## Notes for the Lead
- Fix round: T-242 M-1 (parsing lane, registry + suite + one app ingest test) and T-243 M-2 (parsing lane, same files as T-243). Both are in the parsing lane; one fix agent can take both.
- M-1 changes the PO suite expectation for cases 10/11 (`direction`, `balanceMinor`). The PO note for those cases ("internal card settlement to avoid double-counting") supports a transfer into the card; record the change in the batch PR.
- Follow-ups: FU-298 … FU-304 as listed above.

## Lead delta check (fix round, `fix/fix68-parse`)

About 40 production lines; read in full by the Lead, each new test confirmed failing on the old tree by the fix agent.
- **M-1 RESOLVED:** `hsbc.cc_payment_transfer.en` v9 is `income` (transfer_in on the card), the source account's available balance is matched but not captured; registryVersion 9, guard bases regenerated; app test: statement then case 10 → one transfer_in on the card, no balance row, due paid. PO suite cases 10/11 now expect `income` and no balance (PO note: internal card settlement).
- **M-2 RESOLVED:** fee nouns removed from `feeFooterKeywords`; a conditional sentence with a money-moved cue is never a footer; the four posted-fee probes stay transactions; the T&C-footer negative still rejects.
- **FU-295 m-1 FIXED:** `nearest_future` keeps a due day up to 7 days late (year scan starts one year back for January backfills). **n-1:** schema already required `direction` (neutral for notices); regression test added.
- Checks: `dart analyze --fatal-infos` clean; PO suite 12/12; parsing notices/generic suites green.
