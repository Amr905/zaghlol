# Domain Algorithms (`packages/zaghlol_domain`)

Everything here is pure Dart, deterministic and unit-tested with the spec's examples as fixed test cases. Inputs are plain value objects, so the same code runs in the UI, the headless engine and tests.

## 1. Money & currency

```dart
final class Money implements Comparable<Money> {
  final int minor;            // exact integer minor units (BR-MON-01)
  final Currency currency;    // ISO 4217 code + exponent from bundled table (BR-MON-03)
  Money operator +(Money o)   // throws CurrencyMismatch if currencies differ (BR-FX-02)
  Money allocate(List<int> weights) → List<Money>   // remainder distribution for splits
}
```
- **Exponents:** the ISO 4217 table (`currencies.json`, about 180 active codes) is bundled. Exponent 3 for KWD, BHD, OMR, JOD, TND, LYD and IQD; 0 for JPY, KRW and others.
- **No implicit conversion:** there is no `Money` → `double` conversion anywhere. `MoneyFormat` renders using the locale's digits (A-29) and symbol rules (`ج.م`/`EGP`).
- **`MultiCurrencyTotal`:** a `Map<Currency, Money>` used by every total (FR-CUR-03). The UI shows the currency switcher only when there are 2 or more keys (EC-55).
- **≈ view** (FR-CUR-04/05, A-62): `approx(total, target, rates)` converts each currency at the **latest** rate, computed in integer arithmetic (`rate_e9`) with banker's rounding at the end. It returns `{value, rateDate, excludedCurrencies}`, where currencies without a rate are listed as "not included" (EC-56). The output is display-only and never stored.

## 2. Payday cycle, safe-to-spend, burn line (BR-BUD-*)

```
cycleFor(date, paydayDay ∈ 1..28):                       // A-43: no payday set → paydayDay = 1
  start = date.day ≥ paydayDay ? (date.year, date.month, paydayDay) : previousMonth(paydayDay)
  end   = nextMonth(start) − 1 day                       // "25 Oct – 24 Nov"
daysRemaining(today) = (end − today) + 1                 // inclusive of today
safeToSpend = max(0, budgetTotal − cycleSpend) ÷ daysRemaining     // per currency; integer division, floor
idealBurn(d) = budgetTotal × d ÷ cycleLength
```
- **Payday change mid-cycle** (EC-21): the current cycle ends on the day before the next occurrence of the new payday. Stored budgets are reused.
- **Zero budget** (EC-24): `safeToSpend` = null, so the UI hides it.
- **Cycle spend per currency** (BR-TXN-01, BR-FX-03): Σ expense `amount_minor` for non-internal, non-declined, non-deleted transactions in the cycle, minus Σ `offset_links` amounts whose **expense** is in the cycle. A late reimbursement therefore restates the original cycle (BR-XFR-07). Results are cached in `cycle_summaries`.
- **Budget alerts** (BR-BUD-02): after each `TransactionsChanged`, compute `pct = spend ÷ limit` for each budget in the affected currency. For each threshold crossed that is not yet in `fired_alerts(kind='budget', subject=budgetId, period=cycleStart, threshold)`, schedule a notification, respecting quiet hours (FR-NTF-02).

## 3. De-duplication & merging (BR-ING-02, EC-01/02/54)

```
key = institution | last4 | direction | currency | amount_minor
on new parsed txn T from channel C:
  if exists raw_messages.body_hash = H → drop
  candidates = txns with same key, |occurred_at − T.occurred_at| ≤ 2 min, source channel ≠ C, not deleted
  if candidates = 1 → attach raw message to it (no new txn); upgrade missing fields (merchant, balance)
  if candidates > 1 → keep T, add review 'possible_duplicate'
pending/settled (A-63): if T.event = settled or (T.status = posted and ∃ P pending with same inst+last4+merchant_norm,
  |Δamount| ≤ 5%, within 7 days) → update P (amount, status=posted), drop T
```

## 4. Self-transfers, conversions, card settlements (BR-XFR-01/02, FR-PAR-12, FR-CUR-06, BR-TXN-04)

```
on transfer_out O (or transfer_in I) persisted:
  candidates = opposite direction, same currency, same amount, different account (both user's),
               |Δt| ≤ 5 min, not already paired
  |candidates| = 1 → pair (kind=auto), mark both is_internal; emit MascotTrigger(detective, 'self_transfer')
  |candidates| > 1 → review 'transfer_ambiguous' (EC-16)
  |candidates| = 0 → wait; re-run when a matching txn arrives within the window (late SMS)
cross-currency (FR-CUR-06, A-61): opposite directions, different currencies, within 3 days,
  |O.amount × rate(day) − I.amount| ≤ 3% → review 'fx_pair_suggestion' (never auto-paired)
fx_conversion event: two legs in one multi-currency account → pair(kind=fx_conversion), both internal
cc_payment: outgoing payment to own credit card → internal transfer; the card-side credit pairs if captured
```
Pairs can be unlinked manually (FR-XFR-02). Unlinking clears `is_internal` on both legs.

## 5. Refunds, splits, reimbursements — net spend (BR-TXN-01, BR-XFR-03…08)

```
netSpend(expense E) = E.amount − Σ offset_links(E).amount            // ≥ 0 by invariant
refund matching (BR-XFR-03): on refund R: most recent expense E at same merchant_norm (and same account if known),
  E.amount ≥ R.amount, within 60 days, not fully offset → offset_link(kind=refund). Else R counts as income-type refund.
reimbursement (manual, FR-XFR-06/07): user picks expenses for incoming I; allocate amounts with
  Σ per expense ≤ remaining(E) and Σ per I ≤ I.amount (BR-XFR-06); I's unallocated remainder stays income.
income(cycle) = Σ income + transfer_in(not internal) − Σ offset_links(kind=reimbursement).amount by source
reimbursement suggestion (FR-XFR-08, A-45): on incoming person-to-person I (IPA/phone/name counterparty):
  candidates = expenses in Dining/Entertainment/Travel or marked shared, within 7 days before I,
               remaining(E) ≥ I.amount, same currency → best = most recent; review 'reimbursement_suggestion'
edit/delete expense (EC-40): if Σ offsets > new amount → remove the newest links until valid; notify user
```

## 6. Subscriptions, installments, reminders (BR-SUB-*, FR-SUB-*)

```
detectSubscriptions (daily, debounced):
  group expenses by merchant_norm (+ account); sort by date
  find chains of ≥ 2 consecutive charges with 25 ≤ Δdays ≤ 35 and |Δamount| ≤ 10% → suggestion (BR-SUB-01)
  annual = monthly × 12 (BR-SUB-02); MascotTrigger(detective, 'subscription') on confirmation
installments: recurring_items(kind=installment) with total/paid count; due date from due_day
auto-mark paid (FR-SUB-05): expense or transfer_out matching item.merchant_norm (or account) with
  |Δamount| ≤ 2% within due_date ± 5 days → recurring_occurrences.txn_id, paid_count++
reminders: schedule local notification at due_date − reminder_days (default 3, BR-SUB-03), 10:00 local
```

## 7. Mascot trigger evaluation (BR-MAS-*, D-35)

`MascotPolicy.select(context) → MascotMessage?`. It runs on Home open and after `TransactionsChanged`, and the priority is shocked > detective > proud > tourGuide (design §4).

| State | Condition | Message source |
|---|---|---|
| shocked | Any category pct ≥ 85% while cycleDay < 20 (BR-MAS-01a); or cycle dining+delivery spend > 1.3 × mean of the previous 3 cycles (needs ≥ 3 cycles) | copy deck key + values |
| detective | Duplicate POS: same merchant + amount + card within 10 min (A-34); subscription renewal detected; self-transfer paired | event payload |
| proud | spend ≤ idealBurn(today) with ≥ 7 days into the cycle; or a goal met | — |
| tourGuide | Pending setup steps, empty states | — |
| motion-only states (D-35) | `thinking` (wait > 1 s), `scanning` (inbox scan), `counting` (import/backup/restore), `saved`, `payday` (salary detected), `oops` (error), `sleep` (empty), `pull`, `tap` | UI events (no business rule) |

Each banner message has an ID. Dismissals are remembered per ID (design C-14), and a message ID shows at most once per cycle.

## 8. Insights & explanations (FR-CHT-*)

- Charts query aggregated SQL: `GROUP BY` category/day/merchant within a period, currency and account filter. Results are memoized per `(chart, period, filter, currency)` and invalidated by events.
- **Explanations** (FR-CHT-03): a template engine (`ExplanationTemplate{conditions, keyAr, keyEn, values}`). For each chart, rules pick the most salient fact, e.g. "the largest category share" or "a category > 25% above its 3-cycle average", and one tip.
  - **Free** gets one fact and one tip.
  - **Gold** "deep coaching" adds comparison to the previous cycle, projected end-of-cycle spend at the current burn, and the top 3 merchants driving the change.
  - Numbers are always computed and never invented (FR-CHAT-03 spirit).
- **Personal inflation** (chart 12): the median unit price change for repeated merchants and categories over 12 months. It is displayed as an index, per currency.

## 9. Voice phrase parser (FR-VOI-01…05)

The input is ASR text in Arabic or English (or mixed, EC-31).
```
1 normalize (as parsing-engine §2) + map Egyptian number words:
   واحد..عشرة, حداشر..تسعتاشر, عشرين..تسعين, مية/ميت/مِيّة=100, ميتين=200, تلتمية=300 … ألف/ألفين/آلاف,
   "و" joins (ميت وخمسين = 150), نص = 0.5, ربع = 0.25, تلت = 1/3 (of the following unit: "ربع جنيه"),
   "جنيه/جنية/ج" currency EGP, "دولار"=USD, "ريال"=SAR …
2 tokenize; find amount spans (numbers or number words) with optional currency
3 split into items at amount boundaries and conjunctions ("و", "and", "،")
4 item text = words between amounts minus verbs ("دفعت", "اشتريت", "صرفت", "paid", "bought")
5 categorize item text with catalog keywords + merchant matcher (e.g. خضار→Groceries, قهوة→Dining, تاكسي/أوبر→Transport)
6 output items[{amount, currency (default primary), text, categoryGuess, confidence}]; amount-less text → item with
   amount = null flagged (EC-30); nothing saved until confirmed (FR-VOI-03)
```
Spec test: «دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي» → [150 Groceries, 45 Dining, 30 Transport]. The phrase list for FR-VOI-05 lives in `test/fixtures/voice_phrases.yaml`, with about 200 phrases written during Phase 5.

**Monthly limit** (FR-VOI-04, A-14/15): `voice_usage[YYYY-MM]` is incremented on **confirm**. Free users are blocked at 15, with Gold upsell.

## 10. Ask Zaghlol chat engine (FR-CHAT-*, D-06, ADR-008)

```
utterance → normalize → intent classifier → slot filler → query plan → answer template (+ optional mini-chart)
```
- **Intents** (minimum set, FR-CHAT-01): `spend_on(category|merchant, period)`, `compare(period A, period B)`, `top_merchants(period)`, `balance(account)`, `budget_remaining(category?)`, `upcoming_dues(period)`, `biggest_expense(period)`, `savings(period)`, `spend_on_card(card, period)`, `roast`.
- **Classifier:** a weighted keyword/regex grammar per intent in AR (incl. Egyptian forms: «صرفت كام», «فاضلي كام», «إيه أكتر») and EN. Ties or a low score → fallback with suggested chips (FR-CHAT-03/05).
- **Slots:**
  - category/merchant via the catalog + user categories (fuzzy);
  - card via account labels/last-4/institution names;
  - period via a date grammar («الشهر ده», «الشهر اللي فات», «آخر ٣ شهور», «من أول السنة», "last week");
  - currency optional.
- **Answers:** one figure per currency, always from a DB query. No data → explicit "مفيش بيانات للفترة دي" (EC-33). Never fabricated.
- **Roast mode** (FR-CHAT-04): pick facts (top waste category, delivery count, the biggest single splurge) and fill humour templates from the copy deck. The A-18 rules are enforced by the copy review: only spending is targeted.

## 11. Net worth (FR-WLT-*, BR-WLT-*)

```
perUnit[unit] = Σ account balances (by currency) + Σ assets (by currency / gold unit)
                − credit card balances − remaining installments − liabilities
gold value(unit=XAU21_G) = grams × price(XAU21_G, goldCurrency)   // A-58; shown in grams + valued
certificate value = principal (accrued interest excluded until paid, A-37)
snapshot: at each cycle end + on demand → networth_snapshots (A-20) → chart 11
CD payouts (FR-WLT-04): schedule from principal × rate ÷ payouts per year on payout dates
```
Prices older than 24 h are labelled stale (FR-WLT-03, EC-34). Assets in a currency without a rate are still listed in their native unit (EC-35).

## 12. Zakah engine (flag `zakah`, FR-ZAK-*, BR-ZAK-*)

```
lots = each asset lot with acquisition date → hawl start (Hijri via a bundled Umm al-Qura table)
nisab = 85 g × price(XAU24_G, goldCurrency) (BR-ZAK-01)
zakatable(today) = cash & balances + gold (21K counts 87.5% purity toward nisab, BR-ZAK-03) + certificates principal
                   + stocks/funds market value − short-term debts due now (BR-ZAK-04)
if zakatable ≥ nisab: for each lot whose hawl (354 days, BR-ZAK-02) completed → due = 2.5% in its native unit
   (gold in grams, cash in its currency) + EGP cost shown separately (FR-ZAK-03)
```
The spec §11 table is reproduced as test cases. The disclaimer is always shown (FR-ZAK-05). Code exists but stays hidden unless the flag is on (FR-ZAK-06).

## 13. Smart ROI (flag `smart_roi`, FR-ROI-*, D-38)

There are 8 rules from spec §12, each of the form `condition(spending stats) → suggestion(kind of product, example rate, 1-y/2-y projection)`. Example: "delivery > 1,500 EGP/month → «لو حوشت نص مصاريف الدليفري في شهادة ادخار…»".
- **Product kinds only:** savings certificate, gold, money-market fund (FR-ROI-05). Rates are labelled example rates from a bundled table, and the operator can update them via the catalog.
- **No names:** CI enforces that no institution or product name appears, using a check against the institution registry names.
- **Named products** go behind a separate flag, `roi_named_products`, which stays off.

## 14. Bulk edit & undo (FR-TXN-06)

`BulkEditTransactions(ids, change)` runs in one DB transaction:
1. Snapshot the affected rows into `undo_batches` (JSON before-image).
2. Apply the change: category, account, or soft delete.
3. Mark the rows user-verified when the category changed.
4. Optionally create merchant rules ("always use this category for these merchants").
5. Emit events.

`Undo(batchId)` restores the before-image and deletes rules created by the batch. Undo batches expire after 24 h, and soft-deleted rows are purged after 30 days.
