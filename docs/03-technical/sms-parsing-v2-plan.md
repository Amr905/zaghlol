# SMS Parsing v2 — Algorithm Plan (rev 3, not yet implemented)

_Rev 3, 2026-11-25. Checked against `main` @ cc843b8 (batch 66). The PO's 12 test cases were run through the real `ParsingPipeline` with the bundled registry (Dart 3.14, `receivedAt` 2026-11-22). Rev 1 was written from docs only; several of its "today" statements were wrong and are corrected here._

PO decisions recorded (2026-11-25): (1) Arab Bank threads are named `ArabBank` and `Arab Bank`; (2) due and statement SMS are kept and go to reminders; (3) a known bank's message that misses its templates may auto-save when the SMS-AUTO rule holds; (4) the 12 cases go in the repo as synthetic copies.

## 1. What the engine already does (so it is not rebuilt)

- Known sender → bank templates → **generic reader** (amount, currency, direction, last-4, merchant, date, ref) → review or auto-save (`genericAutoSaveEligible`).
- Unknown sender → generic reader only if sender and body hints match; else `unknownSource`.
- Senders compare case-insensitively; the inbox scan binds each sender with its lower/upper variants.

So rev 1's "four layers" mostly exist. v2 is a set of targeted changes to the generic reader, the registry and the event model.

## 2. Baseline: the 12 cases on `main`

| Case | Sender used | Result today | Wrong or missing |
|---|---|---|---|
| 1 debit purchase (AR) | bank unknown | Unknown sender: **`unknownSource`**. Under a known bank: generic, expense 375 EGP, merchant ok | last-4 `رقم 3390` not read; balance; no event |
| 2 InstaPay out | BanqueMisr | generic, transfer/expense 1985 EGP, last-4, ref, date ok | recipient stored as *merchant* `محمد م ز ا` (mask stripped); no counterparty |
| 3 purchase | ArabBank / Arab Bank | generic, purchase 170.10 EGP, last-4 ok | balance 1769.47 not read |
| 4 InstaPay in | BanqueMisr | generic, transfer/income 300 EGP, last-4, ref ok | sender name cut to 4 words (`SHAWKAT` lost), stored as merchant |
| 5 `A Trx using Card` | bank unknown | generic, 263 EGP, last-4, merchant, date ok | **direction unknown**; balance |
| 6 salary USD | ArabBank / Arab Bank | **template**, all fields ok | — |
| 7 card due reminder | CIB | generic, **ccPayment/expense 51.77**, date **2025**-11-25, merchant `حالة أن` | not a transaction; year wrong; junk merchant |
| 8 card statement | CIB | generic, **expense 51.77**, date **2025**-11-25, merchant `خلال الرابط التالي` | not a transaction; total/min due not separated |
| 9 credit purchase | HSBC | **template**, all fields ok | — |
| 10 card payment | HSBC | **`noTemplateMatched`** | everything |
| 11 card payment | HSBC | **`noTemplateMatched`** | everything |
| 12 statement | HSBC | **`noTemplateMatched`** | everything |

Score: 2 fully right, 7 partly right, 3 unreadable.

**Money risk found:** cases 7 and 8 come back from a known bank with a direction, a clean amount and a last-4, which is exactly what `genericAutoSaveEligible` (`generic_policy.dart`) accepts. A due reminder or a statement can therefore be saved as an expense without review. Read from the rule, not yet reproduced through the ingest layer.

## 3. Arab Bank "two folders"

Not reproduced in the parser: `arab_bank.json` already lists `ArabBank`, `Arab Bank`, `ARABBANK`, `ArabBankEG`, `Arab Bank EG` (and `EG` as template-only); the Guard base has both; cases 3 and 6 resolve to Arab Bank under either name, with or without the leading `EG` line.

What is actually wrong for Arab Bank today: the purchase wording of case 3 has **no template**, so it only reaches review, without its balance. Fix in package 3.

Still to check on the phone with two threads (package 1): the scan reads both, both land on one institution and one account per last-4, no duplicates. If the PO sees something else (two bank entries, missing messages from one thread), that symptom is needed.

## 4. Changes

### 4.1 Non-transaction events first (fixes cases 7, 8, 12 and the money risk)
- New events `cc_due` and `cc_statement`: never a transaction, never in totals. Fields: card last-4, total due, minimum due, due date, statement date. They feed dues/reminders.
- Generic reader gets a **notice gate** before any amount ranking: future-tense deduction (`سيتم خصم`, `will be debited`, `payment due`, `pay by`) or statement wording (`كشف حساب … هو`, `statement date`, `total amt due`, `min. amt due`) → notice, not a transaction. `genericAutoSaveEligible` refuses notices.
- Templates: CIB due (AR), CIB statement (AR), HSBC statement (EN).
- Due dates with no year resolve to the **nearest future** date; transaction dates stay nearest past.
- Boilerplate tails (`يمكنك الاطلاع…`, `للمزيد اتصل…`, `please ignore if paid`) are cut before merchant search.

### 4.2 HSBC card payment (cases 10, 11)
- Template `hsbc.cc_payment.en`: `DDMONYY` date, source account `002-411***-001`, trailing-minus amount, card last-4, source-account balance.
- Amount parser accepts a trailing `-` as a sign marker.
- The pipeline currently hides why the generic reader gave up behind `noTemplateMatched`; keep the real reason (`genericNoAmount`, `genericDeclined`, `genericPromotion`) so it shows in diagnostics.

### 4.3 Generic reader fixes (cases 1–5)
| Gap | Change |
|---|---|
| last-4 after `رقم` (case 1) | add the anchor; reject when followed by `مرجعي` / `ref` or more than 8 digits |
| transfers store the person as merchant (2, 4) | transfer events fill **counterparty**; keep the masked name as written; no 4-word cut |
| no balance from generic (1, 3, 5) | read `balance` / `available` after balance anchors; inherit currency when none is written |
| direction unknown (5) | add `trx using card`, `has been used for` as expense cues |
| junk merchant from `في حاله`, `من خلال` | a merchant start anchor must not be followed by a date, time or function word |
| Arab Bank purchase (3) | template `arab_bank.account_purchase.ar` |

### 4.4 Bank exception rules
Kept from rev 1, smaller: most exceptions are simply a **template** (already data). Add to the institution JSON only what templates cannot say: `stripPrefix`/`stripSuffix`, extra generic cues per bank, `dateOrder`. Lint runs every bank's fixtures after any change.

### 4.5 Unknown senders (case 1 from a bank not in the registry)
Unknown senders are blocked by design unless sender and body hints match; widening that is a privacy decision, so it is not changed here. Instead: add the missing bank's sender to the registry (needs the thread name, §6).

### 4.6 Fewer unreadable messages over time
Per-sender counts of each non-parse reason plus a text-free **shape signature** in SMS diagnostics, so the most common unread pattern is visible and becomes the next template. Nothing leaves the phone.

## 5. Work packages (rev 2; superseded by §7)

| # | Package | Class | Cases |
|---|---|---|---|
| 0 | 12 cases as synthetic fixtures + baseline report in CI (red first) | C1 | all |
| 1 | Two-thread Arab Bank test (scan + ingest), no code change expected | C2 | 3, 6 |
| 2 | `cc_due` / `cc_statement` events, notice gate, auto-save refusal, due-date year rule | C4 (money) | 7, 8, 12 |
| 3 | Templates: HSBC payment + statement, CIB due + statement, Arab Bank purchase; trailing minus | C2 | 3, 7, 8, 10–12 |
| 4 | Generic reader fixes (§4.3) | C3 | 1–5 |
| 5 | Notices into reminders (storage + UI) | C3 | 7, 8, 12 |
| 6 | Real generic reason + diagnostics signatures | C2 | — |

Order: 0 → 2 → 3 → 4 → 1/6 → 5. `registryVersion` bump with package 3 so stored review rows re-parse.

## 6. Salary date and payday (PO request, 2026-11-25)

**What the PO asked for**
1. A salary can arrive late in the month before the one it pays for (for example on the 23rd or 24th). A salary credit **after day 20** counts as income of the **new month**.
2. When that happens the app's salary date (payday) setting is **changed automatically**.
3. When a month has **several** salary transfers, look at the **latest 3 months**; if the same pattern repeats, the payday is the **first** salary of the month.

**What `main` does today**
- Payday is a manual setting, 1–28; the budget cycle runs payday → day before next payday (BR-BUD-01, FR-BUD-01).
- A detected salary only raises a one-time *suggestion* (`payday_suggestion` review item, FR-ONB-10).
- D-68: only a salary on day 29–31 is special (suggest payday = 1, salary counts in the month it arrives).
- A-42: the cycle follows the configured payday, not the actual arrival.

**Proposed rule (to implement)**
| Step | Rule |
|---|---|
| Input | Salary events only (`salary` template event or the user's "this is my salary" mark), per currency, primary currency decides |
| Day of a month | The **first** salary credit in a calendar month is that month's salary day; later ones in the same month are extra income in the same cycle and never move the payday |
| Stable pattern | Look at the latest 3 months that have a salary. If their first-salary days agree (same day, ±2 days for weekends and holidays; use the earliest), that day is the detected payday |
| Auto-set | If the detected payday differs from the setting, change the setting and tell the user once, with Undo. A payday the user typed by hand is not overwritten unless 3 months in a row disagree with it |
| Fewer than 3 months of data | First salary seen: set payday only if the user never set one; otherwise wait for the pattern |
| Day > 20 | The cycle that starts on that day is **named and reported as the next month** (salary on 23 Nov opens the "December" cycle). Charts, monthly summary and Ask use the same naming |
| Day 29–31 | Payday is stored as 28 at most (BR-BUD-01); D-68 is replaced by this rule |
| Mid-cycle change | EC-21 stays: the current cycle ends early, the new one starts on the new payday |

**Requirement changes this needs (PO approval = this request):** FR-ONB-10 (suggest → auto-set with undo), D-68 (replaced), A-42 (cycle still follows the setting, but the setting now follows the salary), new decision for "cycle starting after day 20 is named as the next month".

**Open point:** "month" in reports. Today a cycle is shown by its date range; naming a cycle as a month is new and touches Home, charts, the weekly/monthly summary and Ask.

## 7. Work packages (replaces the order in §5)

| # | Package | Class | Covers |
|---|---|---|---|
| 0 | 12 cases as synthetic fixtures + baseline report in CI (red first) | C1 | all |
| 2 | `cc_due` / `cc_statement` events, notice gate, auto-save refusal, due-date year rule | C4 (money) | 7, 8, 12 |
| 3 | Templates: HSBC payment + statement, CIB due + statement, **Arab Bank debit purchase (case 1), account purchase (case 3), `A Trx using Card` (case 5)**; trailing minus | C2 | 1, 3, 5, 7, 8, 10–12 |
| 4 | Generic reader fixes (§4.3) | C3 | 1–5 |
| 6 | Real generic reason + diagnostics signatures | C2 | — |
| 5 | Notices into reminders (storage + UI) | C3 | 7, 8, 12 |
| 7 | Payday detection: first salary of the month, 3-month pattern, auto-set with undo (domain logic + settings) | C3 | §6 |
| 8 | Cycle naming for payday after day 20, across Home, charts, summaries, Ask | C3 | §6 |
| 9 | SRS updates: FR-ONB-10, D-68, A-42, new decision | C1 | §6 |

Order: 0 → 2 → 3 → 4 → 6 → 5, with 9 → 7 → 8 in parallel (different files). `registryVersion` bump with package 3.

Rev 3 notes: cases 1 and 5 are **Arab Bank** (PO), so both get Arab Bank templates and the old package 1 (two-thread test) is dropped: the PO withdrew that report and will describe the real issue separately.

## 8. Board tasks and Lead assumptions (2026-11-25, PO asked the Lead to assume rather than block)

| Package | Task |
|---|---|
| 0 fixtures | T-240 |
| 2 notices (due/statement) | T-241 |
| 3 templates | T-242 |
| 4 generic reader | T-243 |
| 6 reasons + signatures | T-244 |
| 5 notices into reminders | T-245 |
| 7 payday detection | T-246 |
| 8 cycle naming | T-247 |
| 9 SRS | done in batch 67 (D-81…D-83) |

Assumptions (recorded in `PO_DECISIONS.md` Part 1 as SMS-V2-* and PAYDAY-AUTO; the PO may overrule any of them in a word):
- **A1 fixtures:** the 12 cases are stored as synthetic copies (names, card digits, refs, amounts changed; wording kept), per CLAUDE.md §2.6.
- **A2 senders:** cases 1, 3, 5 and 6 are Arab Bank (PO). Case 1 and case 5 wording gets Arab Bank templates; the same wording from another known bank still reads through the generic reader.
- **A3 notices:** due reminders and statements are never transactions and never auto-saved. They are stored as a card due (amount due, minimum, due date) on the card account matched by (institution, last-4); with no such card the notice is kept and attached when the card appears. Undated due reminders take the nearest future date.
- **A4 "after day 20":** day 21 or later.
- **A5 same salary day:** first-salary days within ±2 days of each other count as the same; the earliest one is used.
- **A6 hand-set payday:** auto-set never overrides a payday the user typed unless the last 3 months with a salary all disagree with it; every auto change shows one banner with Undo.
- **A7 short history:** with 1–2 months of salaries the payday is set only if the user never set one.
- **A8 day 29–31:** payday is stored as 28 (BR-BUD-01 keeps 1–28); the old "late-month salary → payday 1" rule is retired.
- **A9 several salaries in a month:** only the first moves the payday; the rest are income of the same cycle.
- **A10 currency:** only salaries in the primary currency drive the payday.
