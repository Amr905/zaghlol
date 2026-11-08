# Screens 10 — Onboarding & Security (S-01 … S-05)

Wireframe convention (all screen files): drawn in **English / LTR** for legibility. The Arabic build mirrors horizontally per `04-design-system.md` §2.8. `[ ]` = button, `( )` = chip, `◉/○` = radio, `⏻` = switch, `▢` = image/illustration, `~~~` = mascot. Standard loading/empty/error patterns (§5 of the design system) apply unless a screen states otherwise.

---

## S-01 Welcome & privacy — أهلاً بيك
**Purpose:** build trust in one screen and get the user to capture setup or restore. Traces FR-ONB-01/02/12, R-11.

```
┌──────────────────────────────┐
│                     [عربي/EN]│  language toggle (pre-set from device)
│                              │
│         ~~~ Zaghlol ~~~       │  tourGuide pose, waves once
│                              │
│  Hi! I'm Captain Zaghlol.    │  headline
│  I'll track every pound      │
│  from your bank messages.    │
│                              │
│  🔒 Your money data stays on  │  3 bullets, bodySmall
│     your phone                │
│  🏦 No bank password, ever    │
│  🚫 No ads                    │
│                              │
│  [      Let's start      ]   │  Primary
│  I already use Zaghlol →     │  Text button → S-04
│  Privacy details             │  Text link → S-71 (read-only mode)
└──────────────────────────────┘
```
**Components:** C-14 (pose only), C-03 primary + text, language toggle (C-35).
**Interactions:** Let's start → S-02 (Android) / S-03 (iOS). I already use Zaghlol → S-04. Language toggle switches the whole app immediately (FR-L10N-01).
**Validation:** none.
**States:** *Loading* — none (static). *Empty* — n/a. *Error* — n/a. *Reduce motion* — static pose.
**Copy rule:** never says "no server" (R-11).

---

## S-02 Capture setup — Android — إعداد اللقط
**Purpose:** get SMS permission (and optionally notification access) with ≤ 3 taps, then start the historical scan. FR-ONB-05/06/09/11, FR-ING-A-01…05.

Step 1 — SMS
```
┌──────────────────────────────┐
│ Step 1 of 2        ━━━━──── Skip│  C-26
│                              │
│        ~~~ (tourGuide)        │
│  Let me read your bank SMS    │  title
│                              │
│  ✔ Only messages from banks,  │  what is read
│    wallets and InstaPay       │
│  ✔ Personal messages are      │
│    never read or saved        │
│  ✔ Money data stays on this   │
│    phone                      │
│                              │
│  [ Allow reading bank SMS ]  │  Primary → system dialog
└──────────────────────────────┘
```
Step 2 — Notifications (optional)
```
┌──────────────────────────────┐
│ Step 2 of 2        ━━━━━━━━ Skip│
│  ✔ SMS allowed — found 0…342  │  C-27 progress (scan running)
│                              │
│  Also catch bank-app          │
│  notifications?               │
│  Helps with Wise, Revolut,    │
│  Payoneer and banks that      │
│  only send app alerts.        │
│                              │
│  [ Turn on notifications ]    │  Primary → system Notification access
│  [      Not now       ]       │  Secondary → S-10
└──────────────────────────────┘
```
Degraded variant (SMS denied or unavailable)
```
│  SMS reading is off.          │  C-20 warning
│  You can still:               │
│  • Catch bank-app notifications [Turn on]
│  • Share or paste a message   [How]  │
│  • Add cash by voice or typing │
│  [ Continue ]                 │
```
**Components:** C-26, C-25, C-27, C-20, C-03.
**Interactions:** Allow → system permission → on grant: scan starts (background), advance to step 2. On deny: degraded variant; "Try again" re-asks if OS allows, otherwise "Open settings". Turn on notifications → OS notification-access screen; on return the app checks status and shows ✓. Skip → S-10, records skipped step for "Finish setup" (FR-ONB-11).
**Validation:** none.
**States:** *Loading* — scan progress in step 2 and later as a Home banner. *Empty* — scan found 0 → Home empty state. *Error* — scan failure → Home banner "Couldn't read your messages — Try again"; permission revoked later → C-20 on Home (EC-13).

---

## S-03 Capture setup — iOS — إعداد اللقط على الآيفون
**Purpose:** install the Shortcut package, verify it, and get to a first logged expense. FR-ONB-05/09, FR-ING-I-01/02/06/07/08, R-07.

```
┌──────────────────────────────┐
│ Step 1 of 3        ━━━────── Skip│
│        ~~~ (tourGuide)        │
│  iPhone can't let apps read   │
│  SMS — so we use Shortcuts.   │
│  One tap adds:                │
│  • Bank SMS (Arabic & English │
│    keywords)                  │
│  • Apple Pay payments         │
│  [  Add Zaghlol shortcut  ]   │  → Shortcuts app
│  How it works (30 s)  ▸       │  expandable text + images
└──────────────────────────────┘
Step 2 — Check my setup
│  ✔ Bank SMS automations (6/6) │  list from setup checker
│  ✖ Apple Pay automation       │  [Fix] → instructions
│  "Run immediately" must be ON │  helper text
│  [ Check again ]              │
Step 3 — First expense
│  Nothing captured yet? Log    │
│  your first expense now.      │
│  [ 🎙 Say it ]  [ Type it ]    │  → S-31 / S-13
│  Use Wise, Revolut, Payoneer? │  link → S-61 per-bank help (FR-ING-I-08)
```
**Interactions:** Add shortcut → opens Shortcuts import; returning to the app auto-runs the checker. Fix → step-by-step text for the missing automation. Skip at any step → S-10 with "Finish setup" card.
**Validation:** none.
**States:** *Loading* — checker spinner ≤ 2 s. *Error* — checker can't determine status → "We'll confirm after your next bank SMS" (no false failure). *Empty* — n/a.

---

## S-04 Restore from backup — استرجاع نسخة
**Purpose:** restore all data and settings on a new/reset phone. FR-BAK-03/06/07/08, FR-ONB-12, EC-26/27.

```
┌──────────────────────────────┐
│ ←  Restore from backup        │
│  Where is your backup?        │
│  ◉ Google Drive               │
│  ○ iCloud (iPhone only)       │
│  [ Continue ]                 │
├──────────────────────────────┤  after storage sign-in
│  Backup found                 │
│  📦 31 Oct 2026 · 2.4 MB       │
│  From: Android · v1.0         │
│  Backup passphrase  [••••••]  │  C-32 (single field + show)
│  [ Restore ]                  │
├──────────────────────────────┤
│  Restoring…  ━━━━━━━──  70%   │  C-27, no cancel after decrypt starts
└──────────────────────────────┘
```
**Interactions:** choose storage → provider sign-in (Google account picker / iCloud uses device account) → newest Zaghlol backup listed (Gold: list of up to 5, newest first). Restore → decrypt → import → S-10 with banner "Re-allow capture on this phone" → S-02/S-03.
**Validation:** passphrase required; wrong passphrase → "That passphrase doesn't open this backup" (unlimited retries; no lockout — data never leaves the device decrypted).
**States:** *Loading* — searching for backups (spinner), restoring (progress). *Empty* — no backup found: "No Zaghlol backup on this account" + [Try another account] + [Start fresh]. *Error* — network: retry; newer-version backup: "Update Zaghlol to restore this backup" + store link (EC-26); corrupted: "This backup can't be read" + try older version (Gold) or start fresh. Forgotten passphrase: help text explains it can't be recovered (EC-27).

---

## S-05 App lock — قفل التطبيق
**Purpose:** protect the app on cold start and after background timeout. FR-SEC-02, FR-ONB-04, A-08/A-10.

```
┌──────────────────────────────┐
│                              │
│          (app icon)          │  no data visible behind
│        Zaghlol is locked      │
│                              │
│   [ Unlock with Face ID ]     │  label per available biometric
│     Use phone passcode        │
└──────────────────────────────┘
```
**Interactions:** auto-prompts biometrics on appear; fallback to device passcode (A-08). Success → previous screen (N-06). App switcher shows this screen's blank variant (FR-SEC-02).
**Validation:** OS-handled.
**States:** *Error* — biometric failed: OS message, retry; biometrics removed from device → passcode only and Settings shows "Face ID unavailable".
