# 07 — Flows: Onboarding, Adding a Card, After the Scan / Statement Import

Mockups: `mockups/23…34`. Theme: Mint Fresh (`05-theme-2026.md` §0). Copy: Egyptian colloquial (`06-voice-and-tone.md`).
These flows only use features the SRS already requires; every step lists the requirement it traces to. One new screen (S-06) is introduced to show results the SRS already requires. It adds no new behaviour.

---

## A. Onboarding

### A1. Android (time to first value ≤ 60 s — FR-ONB-09)
| # | Screen | Mockup | What happens | Traces |
|---|---|---|---|---|
| 1 | S-01 Welcome | `01-welcome` | One screen, one button «يلا نبدأ»; «أنا مستخدم زغلول قبل كده» → restore | FR-ONB-01/02/12 |
| 2 | S-02 step 1 — SMS | `19-android-capture-setup` | Three plain reasons, one button → system SMS permission | FR-ONB-05 |
| 3 | S-02 step 2 — notifications + live scan | `23-onb-scan-progress` | The historical scan starts as soon as permission is granted. A live counter and the banks found so far show while the user decides on notification access («شغّل الإشعارات» / «مش دلوقتي»). | FR-ONB-06, FR-ING-A-03, FR-ING-A-07 |
| 4 | **S-06 Scan results — "دي كروتك؟"** *(new screen)* | `24-onb-cards-found` | See §C. | FR-ONB-06, FR-ACC-01/05, FR-CAP-01, FR-ING-A-06 |
| 5 | S-10 Home, first visit | `25-onb-first-home` | If no payday is set, the hero shows **this calendar month** (A-43). Contextual cards appear once each: payday suggestion from a detected salary (FR-ONB-10), then a one-tap app-lock toggle, offered only now that transactions are visible (FR-ONB-04). Review pill for unrecognised messages. | FR-ONB-03/04/10, FR-ING-A-06 |

- **If the scan is still running** when the user taps «مش دلوقتي», go straight to Home. The scan banner stays there (`20-android-home`) and S-06 is shown as a sheet when the scan finishes.
- **Skip:** any step except Welcome can be skipped and later resumed from Settings → «كمّل الإعداد» (FR-ONB-11).

### A2. iPhone
| # | Screen | Mockup | What happens | Traces |
|---|---|---|---|---|
| 1 | S-01 Welcome | `01-welcome` | Same as Android | FR-ONB-01 |
| 2 | S-03 step 1 — add Shortcut | `02-ios-capture-setup` | One tap opens the Shortcuts import | FR-ONB-05, FR-ING-I-01/02 |
| 3 | S-03 step 2 — check setup | `26-ios-setup-check` | When the user returns from Shortcuts, the checker runs automatically. ✓ means the automation is present; anything missing shows «صلّحها» with three steps. When the checker can't tell, the screen says «هنعرف أول ما توصلك رسالة بنك» instead of reporting a failure. | FR-ING-I-06/07 |
| 4 | S-03 step 3 — first expense | `27-ios-first-expense` | Voice or typed entry gives the first value in ≤ 60 s. Links help online-bank users and offer statement import (Gold). | FR-ONB-09, FR-ING-I-08, FR-EXP-06 |
| 5 | S-10 Home | — | Same contextual cards as Android | FR-ONB-04/10 |

---

## B. Adding a credit card manually (S-43 in "create" mode)

Cards are created **automatically** the first time a bank + last-4 appears in a message (FR-ACC-01), so manual adding is the exception. It's needed when:
- no message has arrived yet;
- the card is used only through statement import;
- the user wants capture rules set before the card is ever seen (FR-CAP-03).

| # | Screen | Mockup | Content | Validation |
|---|---|---|---|---|
| 1 | Money → «+» → **What to add?** sheet | `28-add-card-type` | Info line: cards are added automatically. Types (FR-ACC-01): credit, debit/account, wallet, multi-currency, BNPL. Cash already exists (FR-ACC-03). Assets stay under the Add button. | — |
| 2 | **Which bank?** | `29-add-card-bank` | Search, Egyptian banks, foreign/online banks (`institutions.md`), and «بنكي مش موجود» (generic institution; parser fallback FR-PAR) | One institution required |
| 3 | **Card details** | `30-add-card-details` | Live card preview; name; last 4 digits (with a hint showing where they appear in the SMS); currency (any ISO code — FR-CUR-01); **credit only:** limit and due day (FR-ACC-05); capture toggles per channel (FR-CAP-01): SMS / notifications on Android, SMS / Apple Pay on iOS | Name 1–30 chars, unique; last-4 exactly 4 digits and not already used for this bank (otherwise «الكارت ده موجود — افتحه؟»); limit ≥ 0; due day 1–31; Save disabled until valid |
| 4 | **Card added** — S-41 empty state | `31-add-card-done` | Confirmation; available limit shows «—» until a message with a balance arrives (FR-ACC-02); next actions: import a statement (Gold), log a transaction manually on this card (FR-CARD-05) | — |

- **When the first message arrives:** it attaches to this card by bank + last-4, so no duplicate is created.
- **If the bank auto-creates a different last-4:** for example, a replaced card. The user can merge the two cards (FR-ACC-04, EC-60).
- **Capture toggles:** if all are turned off, the card is "not tracked". Messages for it are discarded and never stored (BR-CAP-01). Statement import still works for it (BR-CAP-03).

---

## C. What happens after the SMS scan — S-06 «دي كروتك؟» *(new screen)*

**Purpose:** let the user check, in one glance, what Zaghlol found before landing on Home. Every action here already exists elsewhere; this screen just brings them together at the moment it matters.

| Block | Content | Action | Traces |
|---|---|---|---|
| Header | «خلصت! لقيت 342 حركة في آخر 6 شهور» | — | FR-ONB-06, A-11 |
| Stats | Auto-categorised · waiting for review · cards found | «مستنيين رأيك» → S-14 | FR-CAT, FR-ING-A-06 |
| Cards found | One row per auto-created account with its guessed type and transaction count | Row → S-43 (rename, change type, merge) or S-62 (stop reading a card that isn't yours, e.g. a work card) | FR-ACC-01/04, FR-CAP-01/04 |
| Credit-card prompt | Shown when a card looks like a credit card: «قولي الليميت وميعاد السداد» | «أيوه، ظبطه» → S-43 credit fields; «بعدين» → later | FR-ACC-05 |
| Primary button | «ورّيني فلوسي» | → Home (S-10) | — |

**States:**
- **Scan found 0 messages:** skip S-06 and go to the Home empty state with other ways to add data.
- **Scan failed:** go to Home and show the banner «مقدرتش أقرا رسايلك — جرّب تاني».
- **Re-scan of one card after un-ignoring it** (FR-CAP-07): show a toast «ضفت 23 حركة لـ CIB •1234» instead of this screen.

---

## D. Importing a bank statement (S-67 import · Gold — FR-EXP-06, BR-CAP-03, BR-ING-02)
| # | Screen | Mockup | Content |
|---|---|---|---|
| 1 | **Choose source** | `32-import-source` | Privacy line (file is read on the phone only); Egyptian bank PDFs; online-bank CSVs (with help on how to download them); Zaghlol CSV. Also reachable from the share sheet and from a card's empty state. |
| 2 | **Summary before importing** | `33-import-summary` | File name and date range. Counts: total rows · already captured from SMS/notifications (skipped as duplicates) · rows for ignored cards (skipped by default, expandable to include) · **new rows to add**. Target card (auto-matched by last-4, changeable). Button «ضيف 142 حركة». |
| 3 | **Done** | `34-import-done` | Added count; auto-categorised vs. waiting for review; top categories for the imported period; Zaghlol note that charts and budget have been updated; «راجع الـ 11» → S-14 filtered to this import; «افتح الكارت» → S-41. |

**States:**
- **Loading:** parsing progress with the row count.
- **Password-protected PDF:** ask for the password. It is used on the phone only and never saved.
- **Unsupported file:** «الملف ده مش كشف مدعوم من …» plus the list of supported banks.
- **No rows found:** «مفيش حركات في الملف ده».
- **Multi-currency CSV (e.g. Wise):** each row keeps its own currency; the summary shows counts per currency, and amounts are never converted (FR-CUR, FR-EXP-07).
- **Free user:** tapping an import source opens S-68 (the Gold paywall).

---

## Inventory change
Add **S-06 Scan results — دي كروتك؟** (Screen/sheet · Free · FR-ONB-06, FR-ACC-01/05, FR-CAP-01, FR-ING-A-06). Total: 46 screens + 2 widgets.
S-43 gains an explicit **create mode** (type → bank → details); S-41 gains an **empty state**; S-67 import gains **summary** and **done** steps. All were already implied by the existing specs.
