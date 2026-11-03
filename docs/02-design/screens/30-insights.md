# Screens 30 — Insights tab (S-20 … S-25)

Tab 2 root is a segmented control: **Charts · Budget · Bills** (C-35). The card filter (C-08) and currency switcher (C-09) sit above the segments and apply to all three.

---

## S-20 Charts — الشارتات
**Purpose:** browse the 12 charts for the selected period, card and currency. FR-CHT-01/02/04/05.

```
┌──────────────────────────────┐
│ Insights          (All cards ▾)│
│ ( Charts | Budget | Bills )   │
│ (EGP)(USD)   (This cycle ▾)   │ currency + period
├──────────────────────────────┤
│ ┌ Cash flow ──────────────┐  │ C-13 (Free)
│ │  ▇▅ ▇▅ ▇▃ ▇▅ ▇▅ ▇▂      │  │ income / spent / saved bars
│ │  Saved 12,200 (38%)     │  │
│ │  [Explain]              │  │
│ └─────────────────────────┘  │
│ ┌ Where your money went ──┐  │ donut (Free)
│ ┌ Top merchants ──────────┐  │ top 5 (Free)
│ ┌ Burn-rate to payday 🔒 ─┐  │ C-13 locked (blurred) [Unlock with Gold]
│ … 12 cards in fixed order (FR-CHT-01) …
└──────────────────────────────┘
```
Order: 1 Cash flow · 2 Category donut · 6 Top merchants · (Budget progress lives in Budget segment) · 3 Burn-rate · 4 50/30/20 · 5 Day-of-week & hour · 7 This month vs 3-month avg · 8 Installments timeline · 9 Subscriptions ×12 · 10 Cards & wallets · 11 Net worth growth · 12 Personal inflation. Free charts first (A-06).
**Interactions:** tap card → S-21. Explain → S-21 with explainer opened. Locked → S-68. Period sheet: this cycle, last cycle, month picker, last 3/6/12 months, custom.
**Validation:** custom range start ≤ end.
**States:** *Loading* — chart-shaped skeletons. *Empty* (< 1 cycle of data) — each chart C-13 empty variant: "Comes alive after your first full cycle" (EC-23); charts needing net worth show "Add accounts or assets" → S-40. *Approx* — when ≈ chip selected, every chart shows ≈ badge. *Error* — per-card C-29 (one chart failing doesn't blank the page).

---

## S-21 Chart detail & explanation — شرح الشارت
**Purpose:** read one chart fully and get Zaghlol's explanation and tip. FR-CHT-03/05/06, FR-MAS-01, C-15.

```
┌──────────────────────────────┐
│ ← Where your money went       │
│ CIB •1234 · EGP · This cycle  │ filter context line
│        ( donut )              │
│ 🛒 Groceries   5,400  27%  ▸  │ legend rows, tap → S-11 filtered
│ 🏠 Rent & bills 4,200 21%  ▸  │
│ 🍔 Dining      3,850  19%  ▸  │
├──────────────────────────────┤
│ ~~~ professor                 │ C-15 explainer
│ "Delivery and coffee took     │
│  3,850 — cut Talabat twice a  │
│  week and save ~1,200."       │
│ 💡 Tip: cap dining at 3,000   │
│ [ Explain it to me ]          │ shown before first open
└──────────────────────────────┘
```
Chart 10 variant (Cards & wallets, FR-CHT-06): rows per card with spend per currency; tap a card → S-41.
**Interactions:** tap chart segments/bars → tooltip with exact value; legend row → S-11 filtered. Explain → typing indicator (≤ 600 ms) then text. Free users get the basic tip; Gold gets deep coaching (content per copy deck, OQ-07).
**Validation:** none.
**States:** *Locked* (Free, Gold chart) — the whole screen shows preview + paywall CTA. *Empty* — chart empty variant; explainer says what's needed. *Error* — explainer failed → hide bubble, show chart.

---

## S-22 Budget — الميزانية
**Purpose:** track the payday cycle against category budgets. FR-BUD-01…06, BR-BUD-01…04, BR-MAS-01.

```
┌──────────────────────────────┐
│ ( Charts | Budget | Bills )   │
│ 25 Oct → 24 Nov · 7 days left │ cycle header (EGP)
│ ━━━━━━━━━━━━━━━━━━━━──  90%    │ overall: 19,800 / 22,000
│ Safe to spend 314 / day       │
│ ~~~ shocked: "Dining at 96% …"│ C-14 when triggered
├──────────────────────────────┤
│ 🍔 Dining      3,850 / 4,000  96% ⚠ │ C-12
│ 🚗 Transport   2,150 / 2,500  86% ⚠ │
│ 🛒 Groceries   5,400 / 7,000  77%   │
│ 💡 Bills       4,200 / 4,200 100% ✖ │
│ Not budgeted   1,350          ▸      │ spend in categories without a limit
│ [ Edit budgets ]              │ → S-23
│ ‹ Previous cycle              │ cycle navigation
└──────────────────────────────┘
```
**Interactions:** tap category → S-11 (category + cycle). Previous/next cycle arrows (mirrored in RTL). Currency switcher shows budgets in that currency only (FR-BUD-02, BR-FX-02).
**Validation:** none.
**States:** *Empty* (no budgets) — C-28 "Set limits to see safe-to-spend" + **Set budgets** (→ S-23); still shows cycle spend. *No payday set* — header says "Calendar month" + link "Set payday" (A-43). *Loading/Error* — standard.

---

## S-23 Edit budgets — تعديل الميزانية
**Purpose:** set category limits, alerts, rollover and annual budgets. FR-BUD-02/03/05/06, A-16.

```
│ ✕ Budgets (EGP ▾)       [Save]│ currency of this budget set
│ Overall  ◉ Sum of categories  │
│          ○ Set a total [22,000]│
│ 🛒 Groceries      [ 7,000 ]   │ amount fields per category
│ 🍔 Dining         [ 4,000 ]   │
│ …                              │
│ Alerts at  [80]% and [100]%    │ FR-BUD-03
│ ⏻ Roll over unused budget     │ FR-BUD-05
│ Annual budgets ▸               │ FR-BUD-06 (e.g. school fees)
│ Payday  25 ▸                   │ → S-72 stepper
```
**Validation:** limits ≥ 0 (0/blank = no budget); thresholds 1–150 and first < second; total ≥ 0; currency required.
**States:** *Unsaved* — discard dialog. *Error* — save failed inline.

---

## S-24 Bills & installments — الفواتير والأقساط
**Purpose:** see subscriptions (monthly ×12), installments/BNPL, card dues and gameya; never miss a due date. FR-SUB-01…05, chart 8/9 data.

```
┌──────────────────────────────┐
│ ( Charts | Budget | Bills )   │
│ This month: 2,900 due · 1,300 subscriptions/mo
├──────────────────────────────┤
│ Detected: Netflix 320/mo  ~~~detective
│   [ Track it ] [ Not a subscription ]
├──────────────────────────────┤
│ Upcoming                       │ C-36 timeline
│ 5 Nov  🟠 valU · Tradeline 4/6  1,000  [Mark paid]
│ 12 Nov 🟢 Sympl · Zara  last!     450
│ 15 Nov 💳 HSBC card payment     1,450
│ 20 Nov 🤝 Gameya (manual)       2,000
├──────────────────────────────┤
│ Subscriptions        ×12/year  │
│ 🏋 Gym        750/mo   9,000/yr │
│ 🎬 Netflix+Shahid 320  3,840    │
│ Total 1,300/mo = 15,600/yr      │
│ [ + Add bill or installment ]   │ → S-25
└──────────────────────────────┘
```
**Interactions:** Mark paid → status paid, remaining count −1 (auto when payment captured, FR-SUB-05). Tap item → S-25 edit. Detected card actions (FR-SUB-01).
**Validation:** none.
**States:** *Empty* — "No bills or installments yet. We'll spot subscriptions automatically." + Add. *Overdue* — item shows danger "Overdue 2 days". *Loading/Error* — standard.

---

## S-25 Add / edit bill or installment — إضافة قسط / اشتراك
**Purpose:** manually track a subscription, installment plan, card due or gameya. FR-SUB-03/04, A-17.

```
│ ✕ Add                    [Save]│
│ Type ( Subscription | Installment | Card payment | Gameya )
│ Name        [ valU · Tradeline ] │
│ Amount      [EGP ▾] [ 1,000 ]   │
│ Repeats     ( Monthly ▾ )       │
│ Next due    [ 5 Nov 2026 ]      │
│ Paid / total  [ 3 ] of [ 6 ]    │ installments & gameya only
│ Remind me   [ 3 ] days before   │
│ Account     ( Cash ▾ )  optional │
│ [ Delete ]  (edit mode)          │
```
**Validation:** name 1–30; amount §5.6; next due date required (may be future); paid ≤ total, total 1–120; reminder days 0–30.
**States:** standard.
