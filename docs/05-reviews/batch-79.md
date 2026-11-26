# Batch review — batch 79 (`batch/2026-11-26-79`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + money/security for the C4 tasks) |
| Date | 2026-11-26 |
| Diff | `git diff origin/main...adc62e62` (main = 32b7add2), 98 files |
| Tasks | T-278 (C3), T-279 (C2), T-280 (C4 money), T-281 (C4 deletes user data), T-282 (C2), Lead glue `de028c2f` |

## Checks run (merged tree adc62e62)

| Check | Result |
|-------|--------|
| `flutter pub get --enforce-lockfile` | OK |
| `flutter analyze` (app) | No issues |
| `flutter test -x golden test/features/home test/features/transactions test/features/insights test/features/ask test/features/transfers test/features/ingestion test/core` | 2559 passed, 1 skipped, 0 failed |
| `dart test test/chat` (zaghlol_parsing, new `AskIntent.exchange`) | 13 passed |
| Scratch repro for T-280 finding M1 (throwaway test, deleted, not committed) | `buildIncomeApprox` returns 60,000.00 EGP for the input below (expected 50,000.00) |
| Goldens | not run locally (CI / app-regen) |

Follow-ups start at FU-379.

---

## T-278 — Home: EGP main page + currency cards (C3) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| PO story: EGP hero money in 29,700 «منهم … من تغيير عملة», one USD card «فاضل USD ٤٠٠٫٠٠» | PASS | `home_screen_test.dart` (PO story group) |
| Card rule: activity-only, balance-only, neither | PASS | `home_read_model_test.dart` (T-278 group) |
| Ordering + `+N` overflow with 5 currencies | PASS | `home_read_model_test.dart` `orderCurrencyCards`; `home_screen_test.dart` overflow / sheet |
| EGP-only user: no currency UI | PASS | `home_screen_test.dart` |
| Goldens ar/en light/dark, 2 cards | PRESENT | `home_cards_*` PNGs (regen commits `02d5767e`, `4cc43b48`) |
| Existing Home tests updated, not deleted | PASS with note | `pager_height_test.dart` deleted; it tested the removed `pagerHeight` helper (assumption written in the task file) |

### Code
Card figures are per currency, no summing; `left = moneyIn − spend − exchangedOut` and `out = spend + exchangedOut`, so in − out = left on the card. Hero is always the primary currency; `currencies` is unchanged, so the EGP figures and mascot inputs are untouched. Glue: card → `AppRoutes.currencyViewFor`, slot defaults to `HomeApproxLine`.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | nit | `app/lib/features/home/presentation/home_widgets.dart:301` | `HomePagerDots` is now unused; `homeHeroOtherCurrencyIncome` (arb en:356 / ar) also unused after the pager removal. | Remove in a follow-up (FU-379). |
| 2 | nit | `app/lib/features/home/presentation/home_screen.dart:3` | Header comment line is > 80 chars (format passed because it is a comment). | Wrap. |

---

## T-279 — Per-currency view `/home/currency/:iso` + budget offer (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| USD view: in 1,000, exchanged out 600, left 400, feed with salary + exchange, no EGP figure | PASS | `currency_view_screen_test.dart` |
| Budget offer: once, dismiss remembered, Yes opens editor with USD, never when a USD budget exists | PASS | `currency_view_screen_test.dart` (offer group) |
| Transactions list currency filter | PASS | `currency_filter_test.dart` |
| Unknown ISO → empty state, no crash | PASS | `currency_view_screen_test.dart`, `currency_route_test.dart` |
| Goldens ar/en light/dark | PRESENT | `currency_view_*` PNGs |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/home/application/currency_view_providers.dart:93-98` | The feed's "in this cycle" test uses `occurredAt.toLocal()` (device zone) instead of the row's stored `occurredTzOffsetMin`, which the cycle totals use. A USD row stored at 23:30 +03:00 on the last cycle day, viewed with the device on UTC, lands on the previous/next day and can drop out of (or into) the feed while still being in the hero totals. | Build the civil date with `CivilDate.fromLocalMs(ms, occurredTzOffsetMin)` like the transactions list does. FU-380. |
| 2 | nit | `app/lib/features/home/application/currency_view_providers.dart:92` | Fetch is capped at 50 rows and then filtered to the cycle; with > 50 future-dated or post-cycle USD rows the feed is short. Unlikely. | Filter the query by the cycle range instead. Same FU-380. |

---

## T-280 — ≈ money-in line on Home + rate sheet + Q2 auto-on (C4, money) — **CHANGES_REQUESTED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| PO story 29,700 + 400 × 49.60 = ≈ 49,540, minor units; KWD (3) and JPY (0) | PASS | `income_approx_test.dart` |
| Missing rate → no line; stale → "old rate"; setting off → no line | PASS | `income_approx_test.dart`, `home_approx_providers_test.dart` "setting off", `home_approx_line_test.dart` |
| Q2: on once; user turns it off → stays off after a new currency | PASS | `home_approx_providers_test.dart` (4 tests) |
| NP: never a partial total; never an exchanged amount counted twice; never without "≈" | **FAIL (NP2)** | The double-count proof only covers foreign → target. Target → foreign double-counts (M1). |
| Widget ar/en for line + sheet | PASS | `home_approx_line_test.dart` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M1 | **major** | `app/lib/features/wealth/domain/income_approx.dart:121-128` (target branch) | An exchange **from the target into a foreign currency** is counted twice. The target contributes its full `moneyIn` (exchanged-out EGP is never subtracted), and the foreign currency's `held = moneyIn − exchangedOut` includes what it received from that same exchange. Failing input (verified with a scratch test): EGP `moneyIn` 50,000.00 (salary), EGP `exchangedOut` 10,000.00; USD `moneyIn` 200.00 (exchanged in), USD `exchangedOut` 0; daily rate 50.00 → total **60,000.00** EGP. Correct: **50,000.00**. This breaks the AC's NP2 ("never an exchanged amount counted twice"), plan §3 "What never happens", and Q3 ("doesn't move when you exchange": the line rises by 10,000 the moment the user buys dollars). | Make the exchange neutral in both directions. Minimal fix: subtract the target's own `exchangedOut` too, i.e. pass the target's `exchangedOut` into `IncomeApproxInput` and use `max(0, targetIn − targetExchangedOut)` for the target. That keeps the PO story at 49,540 (EGP exchangedOut 0) and gives 50,000 above. Add an EGP → USD test (and USD → EUR → EGP chain) to `income_approx_test.dart` as the negative proof; it must fail on the current code. Also update `homeApproxSheetOwn` wording if the target figure shown in the sheet changes. |
| 2 | minor | `app/lib/features/home/application/home_approx_providers.dart:38-46` | The bank rate shown in the sheet is `foreign.exchangedOut / target.exchangedIn`. If the one foreign currency also exchanged into a third currency (USD 600 → EGP 29,700 and USD 100 → EUR 92), the rate is computed from 700 USD vs 29,700 EGP = 42.43, a wrong "bank rate". Display only; the total is unaffected. | Read the rate from the target-side exchange pairs only (e.g. `ChartRepository.exchangePairs` filtered to `received.currency == target`), or omit the bank rate when the foreign currency has exchanges into a non-target currency. FU-381. |
| 3 | minor | `app/lib/core/l10n/app_ar.arb` (`homeApproxSheetBody`, `homeApproxSheetOwn`, `homeApproxSheetExchanged`, `homeApproxSheetExchangedBank`) | Use «حولته / حولتها». The batch rule and the plan §6 row this task ships (`home.approx.sheet.body`, now «للي غيّرته») say «غيّرت», not «حولت». | Change to «غيّرته / غيّرتها». Trivial; can go in the M1 fix pass. |
| 4 | minor | `app/lib/core/l10n/app_ar.arb` `homeMascotFirstForeign` / `home_approx_providers.dart:71-87` | The notice says «قبضت بالدولار» but the trigger is any second currency with **any** activity (spending included). An EGP user who pays one SAR card purchase gets "you got paid in dollars". The copy is the plan's; the trigger is wider than the copy. | Either restrict the trigger to foreign money in, or make the line currency-neutral and not income-specific (copy is a PO/UX call → FU-382). |
| 5 | nit | `app/lib/core/l10n/app_en.arb:491` | `homeApproxSheetClose` is defined but unused. | Drop or use it (FU-379). |

### Security / money (C4)
- Integer minor units throughout; one half-even rounding per currency via `FxTable.convertApprox`; overflow → `IncomeApproxNone`. No `double`. Per-unit display uses `10^exponent`, so KWD and JPY are right.
- Never a partial total: any held currency without a rate returns `IncomeApproxNone` (tested). Fully exchanged currencies need no rate (correct).
- The figure is display-only, never persisted; always prefixed "≈" and read as «تقريبي» first.
- Q2 writer: reads settings with `ref.read`, watches only the cycle totals, writes the never-reset `approx_view.auto_on_done` **before** enabling, and skips the enable when already on. It cannot loop and cannot re-enable after the user turns the view off (tested). It runs only while the cards row is built (the slot is under the cards), which matches "a second currency card appears".
- No new network calls: rates come from the existing prices repository (FR-BE-04). No logging.

---

## T-281 — Exchange as one row; delete/undo as a unit; FU-364 merge (C4, deletes user data) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| One row per exchange, ar/en, under a currency filter | PASS | `exchange_row_test.dart` |
| Delete exchange → both legs and pair gone; Undo → all back; cycle totals identical | PASS | `exchange_unit_test.dart` "delete exchange (out / in / both leg picked) …" |
| Single-leg delete path: no freed leg counted as income/spending | PASS | `exchange_unit_test.dart` rule-driven delete (out/in), onPersisted heal; ordinary transfer unchanged |
| FU-364 merged / resolved together | PASS | `ingest_raw_messages_test.dart` group "T-281 FU-364" (merged; only sent leg matches → second pair + item; delete flagged exchange removes both) |
| Detail as one unit, exchange delete copy, Undo | PASS | `exchange_detail_test.dart` |
| ≤ 3 negative proofs | PASS | NP1–NP3 as listed in the task file |

### Code
- `_takeExchanges` runs inside `BulkEditUseCase.apply`'s transaction before the soft deletes; a failing soft delete rolls back the pair delete too. The legs keep `is_internal = 1` and lose `transfer_pair_id` via `ON DELETE SET NULL` (checked in `v2_financial_a.dart:44`), so nothing is counted between delete and Undo.
- Undo re-inserts the pair only when both legs were restored and neither was re-paired; otherwise the legs stay internal and the skip is counted. `BulkActions.undo` then runs `onPersisted` on both legs, which sees the restored pair with a live partner and leaves it alone.
- `onRemoved` / `onPersisted` heal keep an exchange survivor internal; ordinary transfers still free their other leg. No path deletes anything without a user tap: only `BulkActions.delete` (list, selection, detail, T-250 review Remove) takes both legs.
- FU-364 merge requires: not user-confirmed; exactly one cross-channel match on the out leg (different source, 2-minute window, last-4 compatible); that leg in a live `fx_conversion`/`cross_currency` pair; exactly one match on the in key and it is that pair's in leg in the same account. Stored legs are not patched; only the raw message and balance are recorded. SQL is parameterized; no logging.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/ingestion/application/ingest_raw_messages.dart:1317-1361` | The merge leaves no mark on the stored exchange that it already has its other-channel copy. Failing input: SMS for conversion A (USD 100 → EGP 4,950) is stored at 10:00; A's notification is never delivered (listener off); at 10:01 a notification for a **second, real** conversion B with the same amounts in the same account arrives → it matches A on both legs and is merged, and B is lost. Same exposure as the existing dedupe-2 attach for ordinary rows and needs identical amounts both sides within 2 minutes, so not blocking. | Follow-up FU-383: record the attached channel (e.g. a `cross_channel_source` on the out leg or a link from the raw message) and skip candidates that already have a copy from the incoming channel; apply to ordinary attach too. |
| 2 | minor | `app/lib/features/transactions/presentation/list/transactions_list_screen.dart:291-325` | In selection mode an exchange row toggles only the leg it was drawn from. Delete is safe (`wholeExchanges`), but bulk Set category / Set account then change only one leg, and Set account can split the pair across accounts with no warning. | Either expand a selected exchange row to both legs for every bulk action or disable Set account / Set category while an exchange is selected. FU-384. |
| 3 | nit | `docs/04-tasks/tasks/T-281.md:12` | Status still `TODO`. | Lead sets it with the batch status update. |

### Security (C4)
- Data loss: none found. Every multi-row delete is in one transaction with an Undo image; the image format stays `v: 1` and a malformed `pairs` entry makes the image unreadable (change nothing) rather than half-restoring.
- Freed legs: none. Survivors stay internal (counted nowhere) and remain visible and deletable/unlinkable; Unlink is still an explicit tap.
- Raw SMS: the merge path stores the raw message encrypted as before and logs only `IngestDiag.mergeCrossChannel`. Test fixtures are synthetic.

---

## T-282 — Insights saved / Ask net agree with Home; Ask exchange question; SRS (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Home left == Insights saved == Ask net per currency (PO story) | PASS | `exchange_agreement_test.dart` |
| Cash-flow: exchange only in the exchange series | PASS | `exchange_agreement_test.dart` "cash flow …" |
| Ask "how much did I exchange" ar + en | PASS | `exchange_agreement_test.dart` group; parsing `dart test test/chat` |
| Existing Insights/Ask tests green | PASS | run above |

### Code
`_exchangeDaily` uses the same rule as the cycle engine (internal legs of complete `fx_conversion`/`cross_currency` pairs); `saved`, `net` and `CashFlowPoint.left` all use income + exchanged in − spend − exchanged out. `exchangePairs` groups per currency pair and never sums across pairs. Integer rate math only.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/ask/application/ask_engine.dart:470` | Ask savings skips a currency whose only activity this month is an exchange **out** (USD salary last month, USD 600 exchanged this month): Home shows USD left −600, Ask omits USD. Agreement holds wherever Ask shows a figure, so not blocking. | Include a currency when any of income / exchanged in / exchanged out is non-zero. FU-385. |
| 2 | minor | `docs/01-requirements/requirements.md:657` | Scope item 3 names BR-FX-01 (bank rate first for exchanged money); it is unchanged (FR-CUR-04 was updated). | Add the bank-rate-first sentence to BR-FX-01. Docs-only; FU-385. |
| 3 | nit | `packages/zaghlol_parsing/lib/chat/ask_grammar.dart:177-185` | Cues «غيرت» and "exchange" at weight 100 are broad ("غيرت رأيي", "exchange rate today?"). | Watch in the M9 chat eval; no change now. |

---

## Summary

| Task | Class | Verdict | Blocker / major |
|------|-------|---------|-----------------|
| T-278 | C3 | APPROVED | — |
| T-279 | C2 | APPROVED | — |
| T-280 | C4 | **CHANGES_REQUESTED** | M1: target → foreign exchange counted twice in the ≈ line |
| T-281 | C4 | APPROVED | — |
| T-282 | C2 | APPROVED | — |
| Glue `de028c2f` | — | OK | — |

Cross-task consistency: the Home cards follow the card filter (T-278), the currency view reads the same `homeModelProvider` (T-279), the ≈ line deliberately uses all cards (T-280, written in its assumptions), and Insights/Ask take their own account filter (T-282). With no filter all four agree on per-currency left; with a filter the ≈ line is the only figure that does not narrow, as documented.

Follow-ups proposed: FU-379 (dead pager code + unused strings), FU-380 (currency view feed day/tz), FU-381 (≈ sheet bank-rate attribution), FU-382 (first-foreign notice trigger vs copy, PO/UX), FU-383 (cross-channel merge marker), FU-384 (bulk actions on an exchange row), FU-385 (Ask exchange-out-only currency + BR-FX-01 text).

### Lead delta check (fix79)

- T-280 major fixed in `income_approx.dart` (3 production lines): the target currency now uses `max(0, moneyIn − exchangedOut)` like the others. New test "negative proof: target exchanged out is not counted twice" (EGP 50,000 in, 10,000 out, USD 200 in, rate 50 → ≈ 50,000.00) failed before the fix (12 pass / 1 fail) and passes after (13/13); the PO story still gives ≈ 49,540. Arabic ≈ sheet strings now say «غيّرته/غيّرتها». **T-280: APPROVED.**
