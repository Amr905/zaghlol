# Screens 20 — Home & Transactions (S-10 … S-16)

---

## S-10 Home — الرئيسية
**Purpose:** answer "how am I doing this cycle and what can I spend today?" and show what was just captured. FR-HOME-01…05, FR-CUR-03/04, FR-CARD-01, FR-BUD-04, FR-MAS-01, FR-ONB-10/11.

```
┌──────────────────────────────┐
│ Zaghlol      (All cards ▾) ⚙ │  C-01 large + C-08 filter + Settings
│ (EGP) (USD) (≈ EGP)          │  C-09 — only if >1 currency
├──────────────────────────────┤
│ Safe to spend today           │  C-11 hero (one page per currency)
│   314 EGP / day               │  display
│ 7 days to payday · 25 Oct–24 Nov
│ ┌────────┬────────┬────────┐  │
│ │Income  │Spent   │Left    │  │  C-10 ×3
│ │32,000  │19,800  │2,200   │  │
│ └────────┴────────┴────────┘  │
│ ● ○                           │  pager dots (currencies)
├──────────────────────────────┤
│ ~~~ "You're on track! Saved   │  C-14 mascot banner (1 at a time)
│     2,200 more than last…" × │
├──────────────────────────────┤
│ ⚠ 3 need your review      ▸  │  card → S-14 (only if count > 0)
│ ✨ Is the 25th your payday? ▸ │  contextual prompt (FR-ONB-10)
├──────────────────────────────┤
│ Recent                See all ▸│ → S-11
│ 🛒 Carrefour Maadi    −450 EGP│  C-05 rows (latest 10)
│    NBE •4567 · 2:14 pm · SMS  │
│ 🍔 Talabat            −285 EGP│
│ ⇄ To myself NBE→CIB  1,000    │  internal (muted, "Excluded")
│    Excluded from spending     │
└──────────────────────────────┘
│  Home  Insights  (+)  Money  Zaghlol │  C-02
```
**Components:** C-01, C-08, C-09, C-11, C-10, C-14, C-05, C-20 (capture/scan banners), C-02.
**Interactions:**
- Card filter → multi-select sheet; all figures and the feed update (FR-CARD-01). Currency chips switch the hero page and feed currency.
- Tap hero → S-22 Budget. Tap KPI "Spent" → S-11 filtered to cycle expenses.
- Tap a row → S-12. Swipe row: start = change category (C-06 sheet), end = split/reimbursed (S-15).
- Pull to refresh: re-runs pairing/categorization on recent items (local only) and triggers catalog sync if due (FR-SYNC-01) — no visible network error.
- Mascot banner × dismisses that message id.
- Settings gear → S-60.
**Validation:** none.
**States:**
- *Loading* — skeleton hero + 5 rows (> 300 ms only).
- *Scanning* (first run) — C-20 info banner "Reading your messages… 342 found" with progress; feed fills live.
- *Empty* (no transactions) — C-28: "No transactions yet" + one action: Android with SMS on → "We'll show them as soon as a bank message arrives"; otherwise **Add your first expense** (→ S-30). Hero shows "Set your budget to see safe-to-spend" (no zeros).
- *No budget yet* — hero shows cycle spend and days to payday; "safe to spend" replaced by **Set a budget** (→ S-23) (EC-24).
- *Filter empty* — "No transactions for CIB •1234 this cycle" + Clear filter.
- *Capture limited* — persistent C-20 warning when SMS permission missing/revoked or iOS checker failing, with **Fix**.
- *Finish setup* — card at top if onboarding steps skipped.
- *Error* — DB read failure: C-29 inline.

---

## S-11 Transactions — الحركات
**Purpose:** find, filter, browse and bulk-edit transactions. FR-TXN-01/03/06, FR-CARD-01/04.

```
┌──────────────────────────────┐
│ ← Transactions  (All cards ▾) │
│ 🔍 Search merchant, note, amount
│ (This cycle ▾)(Category ▾)(Type ▾)(Source ▾)│ filter chips, scroll
│ (EGP)(USD)                    │ C-09 if needed
├──────────────────────────────┤
│ Today                 −735 EGP│ day header with day total per currency
│ 🛒 Carrefour          −450    │
│ 🍔 Talabat            −285    │
│ Yesterday                     │
│ …                             │
└──────────────────────────────┘
```
**Interactions:** search-as-you-type (debounced 250 ms, FTS, FR-TXN-01); filter chips open sheets (date range: this cycle / last cycle / month / custom; category multi; type: expense, income, transfer, refund, reimbursement, declined; source multi). Row tap → S-12.
**Selection mode — bulk edit (FR-TXN-06, D-36):** enter with the «اختار» button in the navigation bar or a long-press on a row. Rows show check circles; the title becomes «اخترت 4». A bottom action bar offers **التصنيف** (category picker sheet), **الكارت** (account picker), **امسح** (delete) and **إلغاء** (cancel). «اختار الكل» selects every row that matches the current filters. After changing the category, an optional switch «استخدم ده دايماً للتجار دول» creates merchant rules (FR-CAT). Every bulk change shows a snackbar «اتغيرت 4 حركات — تراجع» (Undo restores all of them). Bulk delete asks first: «تمسح 4 حركات؟ مش هتقدر ترجعها بعد كده». Mixed currencies are allowed; amounts are never converted.
**Validation:** custom range: start ≤ end; end ≤ today.
**States:** *Loading* — skeleton rows. *Empty* (no data) — C-28 "Your transactions will appear here" + Add expense. *No results* — "Nothing matches '…'" + Clear search/filters. *Error* — C-29.

---

## S-12 Transaction detail — تفاصيل الحركة
**Purpose:** see everything about one transaction and fix it. FR-TXN-02…05, FR-CAT-05, FR-XFR-02/04/06/09, FR-PAR-06, spec screen "SMS inspector".

```
┌──────────────────────────────┐
│ ←                    ✎  ⋮     │ edit → S-13; ⋮ = Delete
│      🛒                       │
│   −450.00 EGP                 │ C-04 display
│   Original: USD 9.15          │ only if foreign
│   Carrefour Maadi             │
│   ( Groceries ▾ )             │ C-06 → picker sheet
├──────────────────────────────┤
│ Card       NBE Visa •4567     │ → S-41
│ Date       23 Oct 2026, 2:14 pm
│ Balance after   12,400.00 EGP │
│ Source     SMS  (badge)       │
│ Reference  —                  │
│ Note       Add a note ▸       │
├──────────────────────────────┤
│ 💸 Split / money back         │ → S-15 (expenses)
│ ⇄ Link as my transfer         │ → S-16
│ ↩ This is money back for…     │ → S-15 assign mode (incoming only)
├──────────────────────────────┤
│ How Zaghlol read this  ▾      │ collapsible
│  "NBE: Purchase of EGP 450.00 │ raw message (monospace, selectable)
│   … at CARREFOUR MAADI EG"    │
│  Amount 450.00 · Merchant …   │ parsed fields + template id + confidence
└──────────────────────────────┘
```
Contextual cards (top, when relevant): refund link "Refund for *Zara* · 23 Oct −850 → net −400" with [View original] [Not related] (FR-XFR-03, BR-XFR-03); reimbursement suggestion "Is this from the *Cilantro* bill?" [Yes][No] (FR-XFR-08); duplicate warning "Looks like a duplicate of …" [Keep both][Delete this]; reimbursed summary "Paid 1,200 · back 800 · your share 400".
**Interactions:** category change → apply + rule prompt sheet: "Always use Groceries for CARREFOUR?" [Always][Just this once] + "Also apply to 12 past" checkbox (A-13) → snackbar Undo. Delete → dialog (auto-captured: "It won't come back unless re-scanned"). Internal transfer rows show linked counterpart and **Unlink**.
**Validation:** note ≤ 200 chars.
**States:** *Loading* — skeleton. *Error* — transaction no longer exists (deleted elsewhere) → back with snackbar. *Declined* — banner "Declined — not counted" (FR-PAR-03, BR-TXN-03). *Pending verification* (Gold purchase n/a here) — n/a.

---

## S-13 Add / edit transaction — إضافة / تعديل حركة
**Purpose:** manual entry and full edit. FR-TXN-02/04, FR-CARD-05, FR-ACC-03.

```
┌──────────────────────────────┐
│ ✕  Add expense         [Save] │
│ ( Expense | Income | Transfer )│ C-35
│ [EGP ▾]  0.00                 │ C-22 amount (autofocus, numeric pad)
│ Category   ( Choose ▾ )       │ C-06
│ Merchant / person  [        ] │
│ Account    ( Cash ▾ )         │ C-07 default Cash
│ Date       Today ▾            │
│ Note       [        ]         │
└──────────────────────────────┘
```
**Interactions:** Transfer type shows From/To accounts (marks internal). Currency defaults to the selected account's currency; multi-currency accounts ask which balance. Editing an auto-captured transaction marks it user-verified (FR-TXN-02).
**Validation:** amount (§5.6), currency required, category required for expense/income, account required, date ≤ today, for transfer from ≠ to.
**States:** *Error* — save failed → inline C-29, form kept. *Unsaved* — discard dialog (N-03).

---

## S-14 Review queue — محتاج مراجعة
**Purpose:** clear items Zaghlol couldn't decide: uncategorized, unrecognized messages, generic-parser suggestions, ambiguous transfers. FR-CAT-04, FR-ING-A-06, FR-PAR-06/13/14, BR-XFR-02.

```
┌──────────────────────────────┐
│ ← Needs review (5)            │
│ (All)(Category)(Unread msgs)(Transfers)
├──────────────────────────────┤
│ ┌──────────────────────────┐ │ C-24 review card
│ │ 350 EGP → mohamed.tarek@ │ │
│ │ instapay · NBE •4567     │ │
│ │ What was this?           │ │
│ │ (🏠 Rent)(🤝 Gameya)(🍔 Split)(More ▾)
│ │ ☐ Always for mohamed.tarek│ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │ generic parser card
│ │ From "XYZ BANK" (new)    │ │
│ │ We think: −220.00 USD at │ │
│ │ AMAZON  (low confidence) │ │
│ │ [Confirm][Edit][Dismiss] │ │
│ │ Request support for this bank ▸ │ FR-PAR-14
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │ ambiguous transfer
│ │ +1,000 CIB •1234 matches │ │
│ │ ◉ −1,000 NBE 2:01 pm      │ │
│ │ ○ −1,000 QNB 2:03 pm      │ │
│ │ ○ Not my transfer         │ │
│ │ [Confirm]                │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```
**Interactions:** chip tap categorizes and removes the card (snackbar Undo). Swipe start = accept suggestion, end = dismiss. After confirming a generic-parser item from a new sender: sheet "Always capture messages from XYZ BANK?" (A-66). Request support → sheet prefilled with sender name + country (editable), shows "We send only the bank's name and country" → Send (FR-PAR-14). Unrecognized known-sender message → [Enter details] opens S-13 prefilled with raw text visible.
**Validation:** request sheet: bank name 2–60 chars; country required.
**States:** *Empty* — mascot proud: "All clear! Nothing to review." *Loading* — skeleton cards. *Error* — request send failed → "Couldn't send — try later" (kept as draft).

---

## S-15 Split & reimbursements — تقسيم وفلوس راجعة
**Purpose:** record that others owe/paid part of an expense, or assign an incoming transfer to expenses. FR-XFR-04…09, BR-XFR-04…08.

Mode A — from an expense
```
┌──────────────────────────────┐
│ Split  Cilantro · −1,200 EGP  │
│ People                         │
│  Ahmed     [ 400 ]  ✔ paid back (+400 InstaPay 24 Oct)
│  Karim     [ 400 ]  ○ waiting  │
│  + Add person                  │
│ Your share          400 EGP    │ computed
│ Suggestions                    │
│  +400 from KARIM M · 25 Oct [Link]│
│ [ Save ]                       │
└──────────────────────────────┘
```
Mode B — from an incoming transfer ("This is money back for…")
```
│ +800 EGP from AHMED (InstaPay) │
│ Assign to expense(s)           │
│  🔍 search recent expenses      │
│  ☑ Cilantro 23 Oct −1,200 [400]│
│  ☑ Uber 23 Oct −180      [180]│
│ Not assigned: 220 → stays income│ BR-XFR-06
│ [ Save ]                       │
```
**Interactions:** amounts default to equal split (Mode A) / to the remaining amount (Mode B). Link suggestion attaches a reimbursement. Unassign on an existing link (FR-XFR-09).
**Validation:** each share > 0; sum of shares ≤ expense amount; Mode B: sum assigned ≤ incoming amount; per expense, total reimbursements ≤ expense (BR-XFR-06); person name 1–30 chars; same currency only (cross-currency assignment not supported — message "Different currency").
**States:** *Empty* (Mode B no candidate expenses) — "No expenses found in the last 60 days" + search all. *Error* — save failure inline.

---

## S-16 Link as my transfer — ربط تحويلة لنفسي
**Purpose:** manually pair two of the user's own transactions as an internal transfer, incl. cross-currency. FR-XFR-02, FR-CUR-06.

```
│ −1,000 EGP · NBE •4567 · 23 Oct │ the source
│ Pick the matching transaction   │
│  ◉ +1,000 EGP CIB •1234  2 min later │ best matches first
│  ○ +20.05 USD Wise    1 day later  ≈ rate 49.9 │ cross-currency (A-61)
│ [ Link ]                         │
```
**Validation:** opposite directions; different accounts; if same currency amounts must be equal; cross-currency allowed with shown implied rate.
**States:** *Empty* — "No matching transaction found" + explanation (EC-15) + **Mark as transfer anyway** (one-sided internal).
