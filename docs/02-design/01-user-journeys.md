# 01 — User Journeys

Source: SRS v1.0 (`docs/01-requirements/requirements.md`). Personas P-01…P-06 (SRS §4). Screen IDs refer to `02-screen-inventory.md`.

Each journey lists the trigger, the happy path (screen by screen), the main alternate/failure paths, the success signal, and the requirements it proves. Journeys marked **[flag]** run only when the remote feature flag is on.

---

## J-01 First launch → first value (Android) — P-01
**Trigger:** installs Zaghlol, opens it. **Goal:** see own categorized spending in ≤ 60 s (FR-ONB-09).

| # | Screen | User does | System does |
|---|--------|-----------|-------------|
| 1 | S-01 Welcome | Reads one-line privacy promise, taps **Start** | — |
| 2 | S-02 Capture setup (Android) | Taps **Allow reading bank SMS** | Shows system SMS permission |
| 3 | system dialog | Allows | Starts historical scan in background (FR-ONB-06) |
| 4 | S-02 (step 2) | Optionally taps **Also read bank-app notifications** → system settings → returns; or **Skip** | — |
| 5 | S-10 Home | Watches the feed fill; scan banner shows progress | Parses, categorizes, pairs self-transfers |
| 6 | S-10 Home | Sees safe-to-spend card in "calendar month" mode (A-43) | Mascot: Tour-guide state, one tip |
| 7 | S-10 (later) | Sees prompt "Is the 25th your payday?" after salary detected | FR-ONB-10 |

**Alternates:** SMS denied → S-02 shows degraded-mode card (notifications + share/paste + manual) → Home with "capture limited" banner (FR-ING-A-05). No bank SMS found → Home empty state with "Add your first expense" + voice. Play has not granted SMS → same as denied.
**Success:** ≥ 1 categorized transaction on Home within 60 s. **Proves:** FR-ONB-01…06/09, FR-ING-A-01…05, FR-CAT-03, FR-XFR-01.

## J-02 First launch (iOS) — P-04
| # | Screen | User does | System does |
|---|--------|-----------|-------------|
| 1 | S-01 Welcome | **Start** | — |
| 2 | S-03 iOS setup | Taps **Add Zaghlol shortcut** | Opens Shortcuts with the package (FR-ING-I-06) |
| 3 | Shortcuts app | Adds automations, returns | — |
| 4 | S-03 step 2 | Taps **Check my setup** | Setup checker lists which automations are active (FR-ING-I-07) |
| 5 | S-03 step 3 | Taps **Log your first expense** | Opens S-31 Voice (or S-13 manual) |
| 6 | S-10 Home | Sees first transaction | — |

**Alternates:** user skips setup → Home with "Finish setup" card (FR-ONB-11). Speech unavailable → manual entry (EC-32).
**Proves:** FR-ONB-05/09/11, FR-ING-I-01/02/06/07, FR-VOI-01…03.

## J-03 Restore on a new phone (Free or Gold)
1. S-01 → **I already use Zaghlol** (FR-ONB-12) → 2. S-04 Restore: choose Google Drive / iCloud → sign in to that storage → backup found (date, size) → 3. enter backup passphrase → 4. progress → 5. S-10 Home with all data; banner "Re-allow capture on this phone" → S-02/S-03 (FR-BAK-07).
**Alternates:** no backup found → message + Start fresh. Wrong passphrase → inline error, retry (no lockout; A-23). Backup from newer app version → "Update Zaghlol to restore" (EC-26). Forgotten passphrase → cannot restore (EC-27), clear explanation.
**Proves:** FR-BAK-03/06/07/08, FR-ONB-12.

## J-04 Daily check-in — P-01
Notification or habit → S-05 App lock (if on) → S-10 Home: safe-to-spend per day, days to payday, cycle spend → taps a new transaction → S-12 detail → back. If "3 need your review" card shows → S-14 Review queue.
**Proves:** FR-HOME-01…04, FR-SEC-02, FR-BUD-04.

## J-05 Fix a category and teach Zaghlol — P-01/P-02
S-14 Review (or S-12 detail) → taps a category chip → bottom sheet "Always use *Groceries* for *KAZYON*?" → **Always** → rule saved; option "Also apply to 12 past transactions" (A-13) → snackbar with Undo.
**Proves:** FR-CAT-04/05/08, BR-CAT-01.

## J-06 Log cash by voice — P-02
FAB → S-30 Quick add → **Speak** → S-31: listening (mascot Voice-listener) → transcript appears live → parsed items list (amount, category, account = Cash) → edit any item → **Save 3** → snackbar on Home.
**Alternates:** no amount understood → item flagged "Amount?" requiring input (EC-30). Free limit reached (15/month) → S-31 shows remaining count; at 0 → Gold prompt S-68 + manual entry offered (FR-VOI-04). No mic permission → explainer → manual.
**Proves:** FR-VOI-01…05, FR-CARD-05.

## J-07 Restaurant bill reimbursed by friends — P-01 (D-20)
1. Card SMS: −1,200 EGP at a restaurant → S-10 feed. 2. Next day InstaPay +400 from Ahmed arrives → Zaghlol shows suggestion card "Is this from the *Cilantro* bill?" (FR-XFR-08) → **Yes** → reimbursement linked. 3. +400 from Karim → suggestion → **Yes**. 4. S-12 of the expense shows *Paid 1,200 · Reimbursed 800 · Your share 400*.
**Manual path:** S-12 of incoming transfer → **This is money back for…** → S-15 pick expense → amount to assign → Save (FR-XFR-06/07).
**Alternates:** reimbursement > remaining → excess stays income (BR-XFR-06), shown in the assign sheet.
**Proves:** FR-XFR-04…09, BR-XFR-05…08.

## J-08 Self-transfer between own banks — P-01
InstaPay −1,000 NBE and +1,000 CIB arrive 2 min apart → auto-paired → S-10 feed shows one "Internal transfer · excluded" row (FR-XFR-01, Detective mascot). If ambiguous (two candidates) → review item in S-14 "Which transfer does this match?" (BR-XFR-02). Manual: S-12 → **Link as my transfer** → S-16 (same or cross-currency).
**Proves:** FR-XFR-01/02, FR-CUR-06.

## J-09 Budget alert → adjust — P-01/P-02
Local notification "Dining at 96% with 7 days left" → deep link to S-22 Budget with Dining highlighted (Shocked mascot) → taps Dining → transactions of that category in cycle (S-11 filtered) → or **Edit budget** S-23.
**Proves:** FR-BUD-01…04, FR-NTF-01, BR-MAS-01.

## J-10 Bills & installments — P-02
Notification "valU installment 1,000 EGP due in 3 days" → S-24 Bills & installments (timeline) → the item shows due date, remaining count → when matching payment captured, auto-marked paid (FR-SUB-05) or user taps **Mark paid**. Detected subscription → card "Looks like a monthly subscription: Netflix 320" → **Track** / **Not a subscription**.
**Proves:** FR-SUB-01…05.

## J-11 Per-card view and ignoring a company card — P-06 (D-25, D-26)
1. Home → card filter chip → choose "CIB Credit •1234" → all figures update; chip stays visible (FR-CARD-01). 2. S-40 Money → CIB card → S-41 Card detail: category donut, top merchants, trend. 3. S-42 Compare cards. 4. Company card: S-41 (or S-61 → **Add card to ignore** with bank + last-4, FR-CAP-03) → S-62 sheet: SMS off, Notifications off → "Keep or delete existing transactions?" → Keep → listed in S-61 ignored list with Undo.
**Proves:** FR-CARD-01…05, FR-CAP-01…07.

## J-12 Multi-currency user — P-06 (D-28, D-29)
Wise notifications in USD + NBE SMS in EGP → Home shows EGP card first, swipe to USD card (FR-HOME-01) → currency switcher appears on charts/budgets (FR-CUR-03) → Wise "converted 500 USD to 24,600 EGP" shown as internal conversion (FR-PAR-12) → user turns on **≈ in EGP** in S-72 → Home adds "≈ total in EGP" with rate date (FR-CUR-04).
**Proves:** FR-CUR-01…06, FR-ACC-06, BR-FX-02/03.

## J-13 Understand my spending — all personas
S-20 Charts → a chart → S-21 Chart detail → **Explain it to me (اشرحلي يا زغلول)** → Chart-professor bubble with numbers and one tip (FR-CHT-03). Locked chart (Free) → preview with **Unlock with Gold** → S-68. Tab 5 → S-50 Ask Zaghlol → "How much on coffee last 3 months?" → answer + mini chart; **Roast me** toggle → humorous answer (FR-CHAT-04).
**Proves:** FR-CHT-01…06, FR-CHAT-01…05, FR-MAS-01/02.

## J-14 Upgrade to Gold; Gold on both phones
Any Gold lock → S-68 Paywall (monthly / yearly / lifetime from store) → store sheet → "Verifying…" → Gold active (FR-GOLD-02). Pending payment → "Payment pending" state (BR-GOLD-05). Later on iPhone: S-69 Account → **Sign in with Google/Apple** → Gold from Android appears (FR-GOLD-07). **Restore purchases** on S-68/S-69 (FR-GOLD-03).
**Proves:** FR-GOLD-01…07, FR-ACCT-01…04.

## J-15 Back up (Free) and export (Gold)
After 7 days, Home tip "Back up your data" (A-65) → S-66 Backup → choose Drive/iCloud → create passphrase (with warning it can't be recovered) → **Back up now** → success with date. Gold: set schedule; versions list. Export: S-67 → CSV/Excel → date range, categories, cards → unencrypted-file warning → share sheet.
**Proves:** FR-BAK-01…09, FR-EXP-01/02/05/07.

## J-16 Message Zaghlol couldn't read
Unknown bank SMS → generic parser suggestion in S-14 Review ("We think: 350 EGP spent at …") → **Confirm** / edit / dismiss → after confirm: "Always capture this sender?" (FR-PAR-13, A-66) → or **Request support for my bank** (FR-PAR-14) → name + country prefilled → send.
**Proves:** FR-ING-A-06, FR-PAR-06/13/14.

## J-17 Wealth & net worth — P-03
Tab 4 S-40 Money → **Add asset** (or FAB → Asset) → S-44: type Gold → karat 21K, grams 24, purchase date → saved → S-40 shows Gold 21K 24 g with value at current price (S-45 shows price date; manual override) → net worth per currency/unit (FR-WLT-01). Free user: assets beyond accounts locked → S-68.
**Proves:** FR-WLT-01…05.

## J-18 Zakah **[flag]** — P-03
S-40 → **Zakah** section → S-46: per-asset hawl countdown, nisab status, zakah due per asset in native unit + cost → mark paid → disclaimer always visible (FR-ZAK-01…06).

## J-19 Share an achievement
Proud mascot moment (e.g. under budget) → **Share** → S-73 Share studio: template, amounts hidden by default (FR-SHR-02) → share sheet.
**Proves:** FR-SHR-01…03.

## J-20 Leave cleanly
S-71 Privacy & data → **Delete everything** → warning (includes "your data is only on this phone; last backup: …") → type-to-confirm → wipe → S-01 (FR-ONB-08).
