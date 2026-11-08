# Screens 50 — Money tab (S-40 … S-46)

---

## S-40 Money overview — فلوسي
**Purpose:** all accounts, cards and (Gold) assets in one place, and net worth per currency/unit. FR-WLT-01/05, FR-ACC-01…06, FR-CUR-03/04.

```
┌──────────────────────────────┐
│ Money                [+ Add ▾]│ add: Account / Asset
├──────────────────────────────┤
│ Net worth                     │ C-11 hero, one page per currency/unit
│   EGP 54,000                  │
│   USD 1,200 · GBP 300         │ other currencies listed (no sum)
│   Gold 21K 24 g · 24K 5 g     │ units (Gold)
│   ≈ EGP 329,000 (rate 1 Nov)  │ only if ≈ view on
├──────────────────────────────┤
│ Cards & accounts   Compare ▸  │ → S-42
│ 🏦 NBE Visa •4567  12,400 EGP ▸│ C-07 + balance "as of" time
│ 💳 CIB Credit •1234 avail 10,000 ▸│
│ 🌍 Wise            USD 1,200  ▸│ multi-currency: first balance + "+2"
│ 💵 Cash             1,240 EGP ▸│
│ 👁‍🗨 Company card •9910 Not tracked ▸│ ignored card (C-07 ignored)
│ Hidden accounts      2 ▸     │ last row, only when ≥ 1 is hidden → hidden list
├──────────────────────────────┤
│ Assets 👑                      │ Gold section
│ 🪙 Gold 21K  24 g  ≈ 90,000 EGP▸│
│ 🏦 NBE certificate 27% 163,000 ▸│ next payout 28 Nov +3,375
│ [ Prices ▸ ]                   │ → S-45
├──────────────────────────────┤
│ 🕌 Zakah ▸                     │ ONLY when flag on → S-46
└──────────────────────────────┘
```
**Net-worth unit lines (hero):** one line per currency and per gold karat, never summed (FR-WLT-01, D-29): `EGP 54,000` · `USD 1,200` · `GBP 300` · `Gold 21K: 24 g` · `Gold 24K: 5 g` · gold coins as a count. The ≈ line appears only in the ≈ view.
**Asset rows (Gold):**
- Gold: karat and grams, valued at the current price (`≈ value`); the stale badge shows when the price is older than 24 h.
- Bank certificate: bank, rate, principal, and the next payout date and amount (FR-WLT-04).
- Cash in a currency: shown in its own currency; with no rate yet it stays in that currency and says so (EC-35).
- Stocks and funds, property, car: the user's own name and an "Estimated value" tag (entered by hand).
- Empty (Gold): one line with Add asset.

**Hidden accounts (D-69, R2-4):** the row sits at the end of the *Cards & accounts* list, shows the number of hidden accounts, and opens a plain list. Each row shows the card label and an **Unhide** action, and tapping the row opens S-43. Unhiding needs no confirmation and offers Undo. The intro line says hidden accounts still count in totals, budgets and charts. If the last account is unhidden while the list is open, the list shows an empty state, and the entry row disappears from S-40.
**Interactions:** tap card → S-41. Add ▸ Account → S-43 (new) · Asset → S-44. Free tapping Assets section → S-68 (section shows locked preview).
**Validation:** none.
**States:** *Loading* — skeleton list. *Empty* — no accounts yet: "Accounts appear automatically from your bank messages" + Add account manually. *Stale prices* — C-21 stale badge on gold values. *Error* — standard.

---

## S-41 Card / account detail — تفاصيل الكارت
**Purpose:** everything about one card: category split, merchants, trend, balance, and its capture controls. FR-CARD-02/04, FR-ACC-02/05/06, FR-CAP entry.

```
┌──────────────────────────────┐
│ ← CIB Credit •1234        ✎ ⋮ │ ✎ → S-43; ⋮ = Capture controls (S-62), Merge, Hide
│ Available 10,000 / 24,000 EGP │ credit: limit use bar; debit: balance
│ Statement due 15 Nov          │
│ (This cycle ▾)                │ period
├──────────────────────────────┤
│ Spent 4,950 EGP               │
│ ( donut by category )         │ FR-CARD-02
│ 🍔 Dining 1,750 · 🛒 Groceries 1,400 …
├──────────────────────────────┤
│ Top merchants                 │
│ Talabat 1,100 · Carrefour 900 │
│ Trend (6 months)  ▁▃▅▃▆▄      │
│ Income & refunds +350         │
├──────────────────────────────┤
│ Recent                See all ▸│ → S-11 filtered to this card
│ Capture: SMS ✓ · Notifications ✓ ▸ │ → S-62
└──────────────────────────────┘
```
Multi-currency account: currency chips under the header switch every section (FR-ACC-06).
**Interactions:** "See all" sets the global card filter to this card and opens S-11 (FR-CARD-01).
**Validation:** none.
**States:** *Empty* (no transactions in period) — "No spending on this card in this cycle". *Ignored card* — banner "Not tracked: SMS & notifications are off for this card" + [Track again]. *Loading/Error* — standard.

---

## S-42 Compare cards — مقارنة الكروت
**Purpose:** categories × cards for a period and currency. FR-CARD-03.

```
│ ← Compare cards   (EGP)(This cycle ▾) │
│            NBE•4567  CIB•1234  Cash   │ horizontal scroll if > 3 cards
│ Dining       2,100     1,750     150  │ tabular figures
│ Groceries    3,000     1,400     200  │
│ Transport      600       980     300  │
│ Total        8,910     4,950   1,200  │
│ [ Choose cards ]                       │ up to 6 (UX-A-03)
```
**Interactions:** tap a cell → S-11 filtered by card + category + period. Cards in another currency are only shown when that currency is selected.
**States:** *Empty* — fewer than 2 cards with spending: "Compare needs at least two cards with spending".

---

## S-43 Edit card / account — تعديل الحساب
**Purpose:** rename, set type, credit limit, due day; merge; hide; create manual account. FR-ACC-01/04/05.

```
│ ✕ Card details              [Save]│
│ Name       [ CIB Credit ]        │
│ Bank       CIB (read-only if auto)│
│ Last 4     [ 1234 ]              │
│ Type       ( Credit ▾ )          │ Debit, Credit, Account, Wallet, BNPL, Cash, Multi-currency
│ Currency   ( EGP ▾ )             │ multi-currency: list of balances
│ Credit limit [ 24,000 ]          │ credit only
│ Statement due day [ 15 ]         │ credit only
│ Merge with another card ▸        │ FR-ACC-04 → picker → confirm
│ Hide this account   ⏻            │
│ Capture controls ▸               │ → S-62
```
**Validation:** name 1–30 unique; last-4 exactly 4 digits; limit ≥ 0; due day 1–31; merge target must be same institution or user confirms warning; can't merge into itself.
**States:** *Merge confirm* — dialog "Move 214 transactions from •1234 (old) into •5678?" *Error* — standard.

---

## S-44 Add / edit asset — إضافة أصل (Gold)
**Purpose:** record gold, certificates, foreign cash, stocks/funds, real estate, car. FR-WLT-02/04, A-19.

```
│ ✕ Add asset                   [Save]│
│ Type ( Gold | Certificate | Cash | Stocks/funds | Property | Car )
│ — Gold —                             │
│ Karat   ( 24K | 21K | 18K | Coin )   │
│ Grams   [ 24.000 ]                   │
│ Bought on [ 12 Mar 2025 ]  Price paid [EGP ▾][ … ] optional
│ — Certificate —                      │
│ Bank [ NBE ]  Principal [EGP ▾][163,000]  Rate [27]%  Payout ( Monthly ▾ )  Maturity [ … ]
│ — Cash — Currency [ USD ▾ ]  Amount [ 400 ]
│ — Stocks/funds — Name, Currency, Value (manual)
│ — Property / Car — Name, Currency, Estimated value
```
**Validation:** type required; grams > 0 (≤ 3 decimals); amounts §5.6; rate 0–100; maturity > purchase date; dates: purchase ≤ today; maturity may be future.
**States:** *Locked* (Free) — opening shows S-68. *Error* — standard.

---

## S-45 Prices — الأسعار (Gold)
**Purpose:** see the gold and FX prices Zaghlol uses, with date, and override manually. FR-WLT-03, FR-CUR-04.

```
│ ← Prices          Updated 1 Nov, 10:05 │ or "Stale" badge if > 24 h
│ Gold (per gram)                         │
│ 24K   4,280 EGP   [Override]            │
│ 21K   3,750 EGP   [Override]            │
│ 18K   3,210 EGP   [Override]            │
│ Currencies → EGP                        │
│ USD  49.50 · SAR 13.20 · GBP 62.10 …    │ only currencies the user holds + featured
│ Manual overrides are used until you clear them. │
```
**Interactions:** Override → amount field + "Use my price"; overridden rows show "Your price" badge and **Reset**.
**Validation:** price > 0.
**States:** *Never fetched* (offline since install) — "Prices not downloaded yet" + "Enter manually". *Error* — fetch failed shows last known with stale badge (EC-34).

---

## S-46 Zakah — الزكاة (Gold · flag)
**Purpose:** per-asset Zakah in native units with hawl tracking. FR-ZAK-01…06. **Hidden unless flag on.**

```
┌──────────────────────────────┐
│ ← Zakah          ~~~ zakahAura│
│ ⓘ Estimate only — consult a   │ always visible (FR-ZAK-05)
│   scholar.                    │
│ Nisab (85 g 24K): reached ✔   │
├──────────────────────────────┤
│ Gold 24K bars 50 g            │
│   Hawl 390 days ✔             │
│   Due: 1.25 g  (≈ 5,350 EGP)  │ native + cost
│   ( Pending ▾ )               │ Pending / Partly paid / Paid
│ Gold 18K 40 g                 │
│   Hawl 120 / 354 days ⏳       │ progress, "due in 234 days (Hijri: …)"
│ USD cash & stocks $12,000     │
│   Due: $300                   │
│ EGP cash 240,000 − debts 20,000 │
│   Due: 5,500 EGP              │
└──────────────────────────────┘
```
**Validation:** payment status only.
**States:** *Empty* — no zakatable assets: "Add gold, cash or investments to calculate Zakah" → S-44. *Nisab not reached* — explanation, no amounts due. *Stale prices* — badge; cost values marked ≈.
