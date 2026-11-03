# Screens 70 — Settings & utilities (S-60 … S-74)

---

## S-60 Settings — الإعدادات
**Purpose:** entry point to every setting (FR-ONB-07). Layout: grouped C-16 list.

```
│ ← Settings                      │
│ ⚠ Finish setup (2 steps left) ▸ │ only if skipped (FR-ONB-11)
│ 👑 Zaghlol Gold — Free plan  ▸  │ → S-69
│ General                          │
│  Preferences ▸                   │ S-72
│  Notifications ▸                 │ S-70
│ Your data                        │
│  Capture ▸  (SMS ✓ · Notif ✓)    │ S-61
│  Categories & rules ▸            │ S-63
│  Backup ▸  Last: 30 Oct          │ S-66
│  Export & import ▸               │ S-67
│ Privacy & data ▸                 │ S-71
│ About ▸                          │ S-74
```
**States:** static; subtitles show live status (backup date, capture status).

---

## S-61 Capture settings — إعدادات اللقط
**Purpose:** see and control every capture source, ignored cards/banks, re-scan, per-bank help, request a bank, custom templates. FR-CAP-03/05/06/07, FR-ING-A-05, FR-ING-I-07/08, FR-PAR-07/14.

```
│ ← Capture                              │
│ Sources                                │
│  Bank SMS            ✓ On   ▸          │ Android: permission state; iOS: "Shortcuts" + [Check setup]
│  App notifications   ✓ On   ▸          │ Android only
│  Apple Pay           ✓ Active ▸        │ iOS only (checker result)
│  Share / paste a message ▸             │ how-to
│ Not tracked                            │ FR-CAP-06
│  👁‍🗨 Company card •9910 (SMS, Notif off) [Undo] │
│  👁‍🗨 Revolut — notifications off  [Undo]│ institution-level (FR-CAP-05)
│  + Don't track a card or bank ▸        │ FR-CAP-03 → sheet: bank, last-4 (optional = whole bank), channels
│ Tools                                  │
│  Re-scan SMS inbox ▸                   │ Android; FR-CAP-07, depth picker 6–24 mo (A-11)
│  Supported banks ▸                     │ searchable list of `institutions.md` (FR-PAR-01/10/15, FR-ING-A-07) + per-bank channel help (iOS notes, FR-ING-I-08)
│  Request support for my bank ▸         │ FR-PAR-14
│  Custom message templates 👑 ▸          │ S-65
```
**Validation:** "Don't track" sheet: bank required; last-4 empty or exactly 4 digits; ≥ 1 channel selected.
**States:** *Permission revoked* — row shows ✖ Off + [Fix]. *Re-scan running* — C-27 progress. *Error* — standard.

---

## S-62 Card capture controls — لقط الكارت
**Purpose:** per-card, per-channel capture switches. FR-CAP-01/02/04, BR-CAP.

```
│ ─── Capture for CIB Credit •1234        │ sheet
│ Bank SMS              ⏻ on              │
│ App notifications     ⏻ on              │ Android only
│ Apple Pay             ⏻ on              │ iOS only
│ When off, messages for this card are    │
│ ignored and never saved.                │
│ [ Done ]                                │
```
On turning the **last** channel off → dialog "Stop tracking CIB •1234? Existing transactions: ◉ Keep (default) ○ Delete 214 transactions" → Confirm → snackbar with Undo (Undo restores switches; deleted data cannot be undone, so Delete asks a second confirmation).
**Validation:** none beyond dialog.
**States:** standard.

---

## S-63 Categories & rules — الفئات والقواعد
**Purpose:** view categories, manage merchant rules, create custom categories (Gold), contribution opt-in shortcut. FR-CAT-07/08/09.

```
│ ← Categories & rules                    │
│ ( Categories | Rules )                  │
│ Categories                              │
│  🛒 Groceries  · 4 subcategories   ▸    │ system categories (FR-CAT-01, read-only names)
│  …14 system                             │
│  + New category 👑                       │ → S-64
│ Rules (32)                               │
│  🔍 search                               │
│  KAZYON → 🛒 Groceries        ✎ 🗑        │
│  mohamed.tarek@instapay → 🏠 Rent ✎ 🗑    │
```
**Interactions:** edit rule → category picker; delete → confirm + Undo. System category tap → subcategory list (read-only for Free; Gold can add subcategories).
**Validation:** n/a here.
**States:** *Empty rules* — "When you fix a category, I'll offer to remember it." *Error* — standard.

---

## S-64 Edit category — تعديل فئة (Gold)
**Purpose:** create/edit custom category or subcategory. FR-CAT-07.

```
│ ✕ New category                [Save]│
│ Name   [ Business trips ]           │
│ Parent ( None ▾ )                   │ choose to make it a subcategory
│ Bucket ( Wants ▾ )                  │ Needs / Wants / Obligations / Savings / Income / Giving
│ Icon   (grid)   Colour (palette)    │ palette = approved category set
│ [ Delete category ]  (edit)         │ → dialog: move its transactions to ▾
```
**Validation:** name 1–30 unique; bucket required; delete requires replacement category (FR-CAT-07).
**States:** standard.

---

## S-65 Custom message template — قالب رسالة مخصص (Gold)
**Purpose:** teach Zaghlol a message format from an unsupported sender. FR-PAR-07.

```
│ ← New template                          │
│ 1. Paste or pick a message              │
│  [ From review queue ▾ ] / [ Paste ]    │
│ 2. Tap the parts                         │
│  "XYZ: You paid ⟦220.00⟧ ⟦USD⟧ at ⟦AMAZON⟧ on 23/10" │ tap-to-tag tokens
│  Tags: (Amount)(Currency)(Merchant)(Last 4)(Balance)(Date)
│  Direction ( Expense ▾ )                 │
│ 3. Test                                   │
│  ✔ Matches 4 of 4 similar messages        │
│ [ Save template ]                         │
```
**Validation:** amount tag required; direction required; template must parse its own sample; sender name required.
**States:** *Test fails* — shows which message didn't match and why. *Empty* (no sample) — paste field only.

---

## S-66 Backup & restore — النسخ الاحتياطي
**Purpose:** create and manage encrypted cloud backups; Free = one slot, Gold = schedule + 5 versions. FR-BAK-01…09, BR-BAK-02.

```
│ ← Backup                                 │
│ Where  ◉ Google Drive  ○ iCloud           │ iCloud iOS only
│ Account  amr…@gmail.com  Change ▸        │
│ Last backup  30 Oct 2026, 10:12 · 2.4 MB  │
│ [ Back up now ]                           │ Free: "Replaces your current backup"
│ Automatic 👑  ( Off | Daily | Weekly | Monthly )│ Gold
│ Versions 👑  30 Oct · 23 Oct · 16 Oct …    │ Gold, up to 5
│ Passphrase  Change ▸                      │
│ Restore from backup ▸                     │ → S-04 flow
│ ⓘ Includes all your transactions, settings,│
│   categories, rules and ignored cards.     │
```
First backup → passphrase setup sheet (C-32) with warning: "If you forget this passphrase, nobody — not even us — can open your backup." + checkbox "I understand".
**Validation:** passphrase ≥ 10 chars (UX-A-01), confirmation matches, checkbox required.
**States:** *Never backed up* — Free nudge copy + Back up now. *In progress* — C-27 (cancellable before upload completes). *Error* — network/storage full/auth expired: C-20 error with Try again; last good backup stays (FR-BAK). *Reminder* — free backup > 30 days old: warning banner (A-67).

---

## S-67 Export & import — تصدير واستيراد
**Purpose:** CSV/Excel export, CSV import/restore, PDF & online-bank statement import. FR-EXP-01…07, BR-CAP-03.

```
│ ← Export & import                        │
│ Export                                    │
│  Format ( CSV | Excel )                   │
│  Dates  ( This cycle ▾ )  Categories (All ▾) Cards (All ▾)
│  Preview (first 20 rows)                  │ Free sees preview only (FR-EXP-02)
│  [ Export 👑 ]                             │
│  ⚠ Exported files aren't encrypted.       │ FR-EXP-05
│ Import 👑                                  │
│  Zaghlol CSV ▸                             │
│  Bank statement (PDF): CIB, NBE, QNB, Banque Misr ▸ │
│  Online bank statement: Wise, Revolut, Monzo, bunq, N26, Payoneer ▸ │ FR-EXP-06
```
Import flow: pick file → parse → summary "182 transactions found · 37 already in Zaghlol (skipped) · 3 cards not tracked (skipped ▾)" → [Import 142].
**Validation:** file type matches chosen import; date range start ≤ end.
**States:** *Loading* — parsing progress. *Empty* — "No transactions found in this file". *Error* — "This file isn't a supported statement from …" + supported list; password-protected PDF → ask password (used locally only).

---

## S-68 Zaghlol Gold — زغلول جولد (paywall)
**Purpose:** explain Gold and buy it. FR-GOLD-01…05, BR-GOLD-05/06.

```
┌──────────────────────────────┐
│ ✕                             │
│      ~~~ proud + crown        │
│  Zaghlol Gold                 │
│  ✔ All 12 charts + deep coaching
│  ✔ Unlimited voice logging    │
│  ✔ Export & import, statements │
│  ✔ Automatic backups (5 versions)
│  ✔ Gold, certificates, assets │
│  ✔ Custom categories & templates
│ ◉ Yearly   [price] · best value│ C-31, prices from store
│ ○ Monthly  [price]             │
│ ○ Lifetime [price]             │
│ [  Continue  ]   (Gold button) │
│ Restore purchases · Terms · Privacy
└──────────────────────────────┘
```
**Interactions:** Continue → store sheet → "Verifying your purchase…" → success (confetti unless reduce-motion) → returns to origin, unlocked (N-05).
**Validation:** plan selected.
**States:** *Loading* — prices loading skeleton; prices unavailable → "Can't load prices — check connection" + retry. *Pending* — "Payment pending — Gold starts when it's complete" (BR-GOLD-05). *Verifying offline* — "We'll finish verifying when you're online" (BR-GOLD-06). *Already Gold* — shows current plan + Manage subscription link. *Error* — store error message + retry.

---

## S-69 Account & subscription — الحساب والاشتراك
**Purpose:** plan status, restore, optional sign-in for cross-platform Gold, delete account. FR-ACCT-01…04, FR-GOLD-03/06/07.

```
│ ← Gold & account                         │
│ Plan  Gold · Yearly · renews 1 Nov 2027  │ or Free [See Gold] → S-68
│ Manage subscription ▸                    │ opens store
│ Restore purchases ▸                      │
│ Use Gold on your other phone (optional)  │
│  [ Sign in with Google ]                 │
│  [ Sign in with Apple ]                  │
│  We only link your Gold plan. Your money │
│  data is never sent.                     │
│ — signed in —                            │
│  amr…@gmail.com · Sign out ▸ · Delete account ▸ │
```
**Validation:** none.
**States:** *Signing in* — button loading. *Error* — sign-in cancelled/failed message. *Delete account* — dialog explaining store purchases remain with the store account.

---

## S-70 Notifications — الإشعارات
**Purpose:** switch each alert type and quiet hours. FR-NTF-01…03, FR-SUB-04.

```
│ ← Notifications                         │
│ Budget alerts           ⏻               │
│ Spending spikes         ⏻               │
│ Bills & installments due ⏻  [3] days before │
│ Duplicate charges       ⏻               │
│ Subscription renewals   ⏻               │
│ Backup problems         ⏻               │
│ Weekly summary          ⏻               │
│ Quiet hours  ⏻  23:00 – 08:00           │
│ Hide amounts on lock screen  ⏻          │
```
**Validation:** reminder days 0–30; quiet hours start ≠ end. Weekly summary is sent on Friday morning (UX-A-07). Reimbursement suggestions are in-app only (FR-XFR-08), not notifications.
**States:** *OS notifications off* — banner "Notifications are off for Zaghlol" + Open settings.

---

## S-71 Privacy & data — الخصوصية وبياناتك
**Purpose:** show exactly what leaves the phone, control contribution, delete everything. FR-ONB-08, FR-CAT-09, NFR-PRIV, BR-SYNC-03.

```
│ ← Privacy & data                          │
│ What stays on your phone                  │
│  Messages, transactions, balances, budgets,│
│  assets and your rules. Encrypted.         │
│ What Zaghlol's server knows                │
│  • A random app ID (not your name/number)  │
│  • Your Gold purchase (to verify it)       │
│  • Your sign-in, only if you use it        │
│  • Merchant names, only if you allow below │
│ Help improve the merchant list  ⏻ (off)    │ FR-CAT-09; info ⓘ explains exact fields
│ App lock ▸                                 │ → S-72
│ ⚠ This phone is rooted — data protection   │ only on rooted/jailbroken devices (FR-SEC-07);
│   is weaker. Learn more ▸                  │ also shown once as a C-20 banner on Home
│ Delete everything ▸                        │
```
Delete everything: dialog with last backup date, "Type DELETE (or احذف) to confirm" (C-18 type-to-confirm) → wipe → S-01.
**Validation:** confirmation text must match exactly.
**States:** *Deleting* — progress; backend delete failure doesn't block local wipe (retried silently next launch is impossible after wipe → note shown: "Server copy will expire automatically", NFR-PRIV-06).

---

## S-72 Preferences — التفضيلات
**Purpose:** language, digits, primary currency, ≈ view, theme, payday, income target, app lock. FR-ONB-03/04, FR-L10N-01/03, FR-CUR-02/04/05.

```
│ ← Preferences                             │
│ Language       ( العربية | English )      │
│ Digits         ( ١٢٣ | 123 )              │ Arabic only
│ Theme          ( System | Light | Dark )  │
│ Primary currency  EGP ▸                   │
│ Show ≈ combined total  ⏻ (off)            │ FR-CUR-04
│   Combine into  EGP ▸                     │ FR-CUR-05, visible when on
│ Payday   ( 25 ▾ )  — or "Calendar month"  │ stepper 1–28
│ Monthly income target  [ 32,000 ] EGP     │ optional
│ App lock  ⏻   Lock after ( 1 min ▾ )      │ A-10
```
**Validation:** payday 1–28; income ≥ 0 (optional); lock timeout from list (immediately, 1, 5, 15 min).
**States:** *Biometrics unavailable* — app lock row explains passcode fallback. Changing payday mid-cycle → dialog "Your current cycle will end early" (EC-21).

---

## S-73 Share studio — شارك إنجازك
**Purpose:** create a shareable achievement image with amounts hidden by default. FR-SHR-01…03, A-26.

```
│ ✕ Share                                   │
│ ┌──────────────────────┐                  │ C-34 live preview
│ │ ~~~ proud             │                  │
│ │ "I saved 38% of my    │                  │
│ │  salary this month!"  │                  │
│ │ #زغلول_ضبط_الميزانية   │                  │
│ └──────────────────────┘                  │
│ Template ( Savings | Delivery cut | Under budget ) │ only templates with data (spec §5 S-14 examples)
│ Show amounts  ⏻ (off)                      │
│ [ Share ]                                  │ system share sheet
```
**States:** *No achievement data* — templates without data are hidden; if none: "Nothing to share yet — keep going!" *Error* — image render failure → retry.

---

## S-74 About — عن زغلول
**Purpose:** version, catalog update status, legal. FR-SYNC-06.

```
│ ← About                                  │
│ Version 1.0.0 (build 100)                │
│ Merchant list updated  1 Nov 2026        │ FR-SYNC-06
│ Prices updated  1 Nov 2026               │
│ Terms · Privacy policy · Open-source licences │
│ Contact support ▸                        │ mail link (UX-A-06)
```
**States:** never synced → "Not updated yet (works offline)".
