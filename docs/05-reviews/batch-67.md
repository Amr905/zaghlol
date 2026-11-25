# Review — batch 67 (T-240, T-241, T-246)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus, code + security; Opus because T-241 is C4 money) |
| Date | 2026-11-25 |
| Commit / diff | `batch/2026-11-25-67` @ 994e593, `git diff cc843b8...HEAD` |
| Verdict | T-240 APPROVED · T-241 CHANGES_REQUESTED · T-246 CHANGES_REQUESTED |

Commands run:
- `dart test` in `packages/zaghlol_parsing`: 1632 passed (PO suite: cases 6, 7, 8, 9, 12 pass; 1–5, 10, 11 pending T-242/T-243; negatives pass, T&C footer pending T-243).
- `dart test` in `packages/zaghlol_domain`: 507 passed.
- `flutter test test/ingestion test/features/ingestion test/features/salary test/features/onboarding test/core/settings test/features/b53`: 579 passed, 8 failed. All 8 are `review_screen_golden_test.dart` goldens (known local font issue).
- `flutter analyze` (app): **exit 1**, one warning (see T-241 M-2).
- Scratch probe (not committed, deleted): a throwaway test in `packages/zaghlol_parsing/test/` that ran past-tense debit messages carrying a due-date tail through `ParsingPipeline` on the batch tree and on `main`. Results are under T-241 M-1.

---

## T-241 — card due reminders and statements are notices (C4, money) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| PO cases 7, 8, 12 pass, pending markers removed | PASS | `po_suite_test.dart`, `card_notice_test.dart` "templates" group |
| Ingest: each of the three gives zero transactions, never auto-saved | PASS | `card_notice_ingest_test.dart` "NEGATIVE PROOF cib/hsbc …" |
| Past-tense CIB card payment still saves as `cc_payment` | PASS | `card_notice_ingest_test.dart` "a past-tense CIB card payment …" |
| Negative proof: auto-save eligibility for a due notice from a known bank is false | PASS | `card_notice_test.dart` "NEGATIVE PROOF: a due notice …" |
| Registry lint green; package `dart test` and app ingestion tests green | PARTIAL | Tests are green. App `flutter analyze` is red (M-2). |

### Exhaustive handling of `ParseNotice`
- `_persist` switch is exhaustive and routes to `_notice`. `_wouldGoToReview` includes it, so a personal sender's notice from an inbox scan is dropped. `_institutionOf` and `_templateIdOf` are covered.
- **Reparse** (`ingest_raw_messages.dart:370-405`): a notice is neither `ParseGeneric` nor `ParseParsed`, so `create == null` and the row is only stamped. A notice can never become a transaction on reparse. OK.
- **OCR / share / paste** (`scan_draft.dart:47`): `result is! ParseParsed` gives null, so it never produces a draft. OK.
- **Custom templates / startup reparse:** these use the same pipeline and reparse path. OK.
- **Review UI:** no review item is written for a notice, so the UI never sees one.
- **`dispositionOf`:** `ccDue`/`ccStatement` → `UndirectedEvent` (review), a safe fallback that is unreachable. OK.
- **Template path** (`parsing_pipeline.dart:293`): a `cc_due`/`cc_statement` template always returns `ParseNotice`. The schema lint rejects a money direction on those events. OK.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-1 | **major** (money: lost spending) | `packages/zaghlol_parsing/lib/generic/generic_parser.dart:47` and `:250`; `generic_keywords.dart` (`noticeFutureKeywords`, `noticePurchaseConflictCues`) | **The notice gate silently swallows completed transactions that carry a due-date tail.** The gate fires on any cue in the head: `due date`, `payment due`, `موعد السداد`, `تاريخ الاستحقاق`, `statement balance`, `الحد الادني للسداد`. The only override is the narrow purchase list (`تم شراء`, `purchase of`, `was used` …), which has no general past-tense money-moved cue (`تم خصم`, `تم سداد`, `تم دفع`, `was debited`, `was charged`, `received`). A `ParseNotice` writes **no transaction and no review item**, and T-245 does not exist yet, so these messages disappear without trace. Scratch probe, known sender `BanqueMisr` (no template), batch tree vs `main`:<br>• `تم خصم 200 جم من بطاقتك 1234 لدى كارفور. تاريخ الاستحقاق 25/12` → **NOTICE ccDue** (main: generic expense, auto-save eligible)<br>• `Your card 1234 was charged EGP 450.00 at UBER. Payment due 25/12` → **NOTICE** (main: expense, eligible)<br>• `تم خصم 500.00 جم من حسابك لسداد قسط القرض. موعد السداد القادم 05/12` → **NOTICE** (main: expense, review)<br>• `Your account was debited EGP 1,250.00 for loan installment. Next due date 05/12/2026` → **NOTICE** (main: expense, review)<br>• `تم سداد 3000 جم لبطاقتك المنتهية ب 1234. الحد الأدنى للسداد 0 جم` → **NOTICE ccStatement** (main: expense, eligible)<br>• `Payment of EGP 3,000.00 received for credit card ending 1234 … Statement balance EGP 0.00` → **NOTICE** (main: income, eligible)<br>• valU `تم دفع قسط 750 جم. موعد سداد القسط القادم 1/1` → **NOTICE** (main: expense, review)<br>Installment and loan debits with a "next due date" line are common in Egyptian bank and BNPL SMS. This is a regression from `main`, where the same texts became a transaction or a review item. The design note's own rule ("a possibly real transaction is never silently swallowed") is not met. | 1. Any past-tense money-moved cue in the head (at least `تم خصم`, `تم الخصم`, `تم سداد`, `تم دفع`, `تم تحويل`, `was debited`, `has been debited`, `was charged`, `has been charged`, `received`, `credited`) next to a gate cue → `genericNoticeConflict` (review), like a purchase cue. Keep future forms (`will be debited`, `سيتم خصم`) out of that list. Do not reuse `completedTransactionCues` as is: it has `debited`/`paid`, which match `will be debited`.<br>2. Add the probe texts above (synthetic) to `card_notice_test.dart` as cases that must **not** be `ParseNotice`, plus one ingest test showing such a message ends in a transaction or a review item. These tests must fail on the current tree.<br>3. Recommended (Lead/PO call): until T-245 lands, a **generic** (non-template) notice should also create a review item, so a gate false positive is visible instead of silent. Template notices may stay silent. |
| M-2 | **major** (CI gate) | `app/test/ingestion/card_notice_ingest_test.dart:13` | `flutter analyze` reports `unused_import` (`package:zaghlol_domain/zaghlol_domain.dart`) and exits 1, so app-ci fails. | Remove the import. |
| m-1 | minor | `packages/zaghlol_parsing/lib/registry/template_extractor.dart:404` | `nearest_future` uses "on or after the day of receipt" strictly. A reminder for `25/11` that arrives or is backfilled on 26/11 resolves to **2027-11-25**, so T-245 would book a due a year late. | FU (owner T-245): allow a short grace window (for example, a date up to ~7 days in the past stays this year), with a test. |
| m-2 | minor | `app/lib/features/ingestion/application/ingest_raw_messages.dart:405` | Old `parsed` rows whose CIB due or statement notice was auto-saved as spending before this batch keep that fake transaction. Reparse only stamps them, and nothing points the user at them. | FU (owner T-245): on reparse, a `parsed` row that now reads as a notice and whose transaction is not user-verified raises one review item ("this looks like a due reminder"). Delete nothing. |
| m-3 | minor | `generic_parser.dart` `_noticeGate` | The gate also catches non-card bills (telecom or utility "due date" texts from a known sender) and types them `ccDue` with no last-4. T-245 must not attach these to a card. | FU (owner T-245): only template notices, or notices that carry a last-4 matching a card, go to card dues. |
| n-1 | nit | `packages/zaghlol_parsing/lib/registry/registry_schema.dart:551` | The lint allows `cc_due`/`cc_statement` with **no** direction, while the design note says "must declare `neutral`". | Require `direction == neutral` explicitly. |

### Security part (T-241)
- **Privacy:** `ParseNotice` and `CardNoticeEvent` carry only typed fields (kind, last-4, money, dates, ids). No body or sender. No `toString` exposes text. The batch adds no `print`, log or diagnostics call in `lib/`. The PO-suite `print` writes counts only. **OK.**
- **No double money:** amounts are `Money`; dates are civil dates. **OK.**
- **Fixtures:** the new CIB and HSBC fixtures and the test bodies are synthetic (example.invalid links, replaced digits). **OK.**
- **Auto-save:** `genericAutoSaveEligible` now takes `ParseResult` and is false for anything that is not `ParseGeneric`. A notice can never be saved. The open risk is the opposite one: a real transaction lost as a notice (M-1).
- **Hook failure:** `CardNoticeHook` runs inside the message savepoint, and a throw rolls the message back (documented). The default hook does nothing. **OK.**

---

## T-246 — payday follows the salary (C3) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Domain examples (24/23/24 → 23; 25 + 5 → 25; 30/31/29 → 28; typed 1 with 23/24/23 → 23; typed 1 with 23/1/24 stays 1; two months, never set → set) | PASS | `payday_detection_test.dart` (one test per example + property test). Traced against `detectPayday`: correct. |
| App: a salary ingest flips the setting and shows the banner once | PASS | `payday_auto_test.dart` "AC: a salary ingest flips …" (idempotent second run, dismiss) |
| Undo restores | PARTIAL | The `payday_day` value is restored, but the cycle history is not restored after a first-ever auto-set (M-1). |
| Widget tests ar/en | PASS | `payday_auto_banner_test.dart` (both locales, Undo). No goldens (m-5). |

### Rule vs plan §8 A4–A10
- A4 (day ≥ 21 counts for the next month), A5 (±2, earliest wins), A7 (1–2 months only when never set), A8 (cap 28), A9 (first per month) and A10 (primary currency) are implemented as written.
- A6: a typed payday is changed only when all 3 months differ by more than 2.
- An auto payday is not flipped within ±2.
- Suppressed days are never re-applied.
- A typed payday is recognized as "configured and ≠ `autoDay`". After Undo, the restored value counts as typed, which is the right safe default.
- **Housekeeping idempotency:** `run()` returns early when `day == current` or the day is suppressed, so repeat runs write nothing. Verified by the test.
- **l10n:** ar is Egyptian colloquial (`خلّيت يوم القبض … تراجع`) and en matches. Digits go through `HomeFormat.count`. No hard-coded strings.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-1 | **major** (data: cycle history) | `app/lib/features/salary/application/payday_auto_service.dart:73-90` (with `payday_schedule_store.dart:66-69`) | **Undo of a first-ever auto-set does not restore the cycle history.** The first auto-set runs with `payday_eras == null` and `kFirstPaydayRewritesHistory`, so eras become `[(null, 23)]` and all history is recomputed on day 23. Undo then calls `setPayday(1)` on a non-null schedule, which gives `[(null, 23), (today, 1)]`. Every past cycle (budgets, summaries, charts, cycle keys) stays on day 23. Before the auto-set it was day 1 with no eras. This is the most common path (new users never set a payday). The AC test only covers `previous = 5` and checks only `payday_day`. | Store the `payday_eras` text from before the change in `PaydayAutoState` (or a flag that it was null), and restore it on Undo. When it was null, reset `payday_eras`/`payday_day` to unset and invalidate the cycle caches. Add a test: never set → auto-set → Undo → `payday_eras` is null again (or equal to the snapshot). The test must fail today. |
| m-1 | minor | `app/lib/features/salary/application/payday_auto_hook.dart:15` | The design note says the rule runs after **income credits** only. In fact it runs a 12-month query plus settings reads after **every** inserted transaction, inside the ingest write transaction. That is heavy during inbox backfill. | FU: add the direction (or "is income") to `PersistedTxn`, or check the row's direction first, and return early for non-income rows. |
| m-2 | minor | `app/lib/features/salary/application/payday_auto_service.dart:119` | Every `sys:income` credit counts as salary, including any income the user files under Income (gifts, freelance). For a user who never set a payday, the first such credit sets the payday. The task says "whatever salary rules already treat as salary". | FU / PO: limit this to `salary` template events, salary-matcher ties and the explicit "this is my salary" mark, or confirm the broader rule in PAYDAY-AUTO. |
| m-3 | minor | `packages/zaghlol_domain/lib/salary/payday_detection.dart:73` | `_agree` compares days linearly. A salary that moves across the month end for weekends (28 / 30→28 / 1) never agrees, so nothing is detected. This is safe (no wrong apply) but misses a common Egyptian pattern. | FU: compare circular distance (mod month), with a test. |
| m-4 | minor | `app/lib/features/salary/application/payday_auto_hook.dart:18` | `on Object` swallows a failure that happens after `setPayday` and before `paydayAuto` is written. The payday is then changed with no banner and no Undo, and later counts as typed. | FU: write the state first (or both in one settings transaction), or roll back the payday on failure. |
| m-5 | minor | `app/test/features/salary/presentation/payday_auto_banner_test.dart` | No golden for the new Home banner (DoD: widget/golden in ar and en). | FU: add ar/en goldens, or note that ZBanner goldens cover it. |
| m-6 | minor | `app/lib/core/l10n/app_*.arb` `paydayAutoBanner` | With a 29–31 salary, the copy says "your salary lands on day 28", which is not true. | FU: use a second placeholder for the real salary day, or wording for the capped case. |
| n-1 | nit | `app/lib/features/home/presentation/cards/home_cards_view.dart:111`, `home_cards.dart:115,135` | The `SetupSuggestionKind.payday` branches can no longer be reached (`nextSetupSuggestion` never yields it). | FU: remove the dead branches or mark them deprecated. |

---

## T-240 — PO SMS suite (C1, spot-check) — APPROVED

- The suite loads the bundled registry, compares fields per case and prints `po_suite: X/12 pass, Y pending`. Pending cases name their task. "No unmarked case fails" is enforced.
- Senders follow the task (ArabBank / `Arab Bank` / `EG`, BanqueMisr, CIB, HSBC).
- **Spot check:** the source doc and the test bodies are the synthetic copy (replaced digits and names, `example.invalid` links). No real data found.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| m-1 | minor | `packages/zaghlol_parsing/test/po_suite/po_suite_test.dart:264` | The AC says "negatives pass", but the T&C-footer negative is marked pending T-243. This is accepted by the Lead's doc commit 7cd0dcc. | Track under T-243. No action in this batch. |
| m-2 | minor | `po_suite_test.dart` | The suite has no negatives of the M-1 kind (past-tense debit plus due-date tail). | Add them with the T-241 M-1 fix. |

---

## Blocker / major summary
- T-241 M-1 (major, money): the notice gate swallows past-tense debits and payments that carry a due-date or statement tail, with no transaction and no review item.
- T-241 M-2 (major, CI): unused import makes `flutter analyze` exit 1.
- T-246 M-1 (major, data): Undo after a first-ever auto-set leaves all past cycles on the auto day.

Follow-ups: the minors and nits above, from FU-295 on (Lead to number and assign).
