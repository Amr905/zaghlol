# Screens 40 — Quick add (S-30 … S-32)

---

## S-30 Quick add — سجل بسرعة
**Purpose:** one place to add anything manually in ≤ 2 taps. FR-HOME-04.

```
┌──────────────────────────────┐
│ ─────                         │ drag handle
│ What do you want to add?      │
│ ┌──────┐┌──────┐┌──────┐┌──────┐│
│ │ 🎙   ││ ⌨    ││ 📷   ││ 🪙  ││
│ │ Say  ││ Type ││ Scan ││Asset ││ Asset shows Gold badge for Free
│ └──────┘└──────┘└──────┘└──────┘│
│ Voice left this month: 12/15  │ Free only (FR-VOI-04)
└──────────────────────────────┘
```
**Interactions:** Say → S-31 · Type → S-13 · Scan → S-32 · Asset → S-44 (Free → S-68). Centre button triggers haptic (spec §10).
**Validation / States:** n/a (static sheet). Voice count hidden for Gold.

---

## S-31 Voice logger — قول لزغلول
**Purpose:** log one or more cash expenses by speaking Egyptian Arabic or English. FR-VOI-01…05, BR-GOLD-02.

Listening
```
┌──────────────────────────────┐
│ ✕                             │
│        ~~~ listening ~~~       │ wings pulse with input level
│  Tell me what you paid…       │
│  e.g. "دفعت ١٥٠ جنيه خضار و   │ example (AR or EN by locale)
│   ٤٥ قهوة و ٣٠ تاكسي"          │
│  "Paid 150 vegetables, 45…"   │ live transcript (grows)
│            [ ■ Done ]          │ stop button (record icon not mirrored)
└──────────────────────────────┘
```
Parsed
```
│ I understood 3 items:         │
│ 🥬 Vegetables & fruit  150 EGP  ( Groceries ▾ ) ✎ ✕ │
│ ☕ Coffee               45 EGP  ( Dining ▾ )    ✎ ✕ │
│ 🚕 Taxi                 30 EGP  ( Transport ▾ ) ✎ ✕ │
│ Account ( Cash ▾ )   Date ( Today ▾ )               │ applies to all
│ [ Save 3 ]   Try again                              │
```
**Interactions:** starts listening on open (mic permission first time: C-25 explainer). Auto-stops after 2 s silence or 30 s max (UX-A-02). Each item editable (amount, label, category) or removable. Save → snackbar "3 expenses saved" + Undo; counts as one voice log (A-14). Try again discards and re-listens (doesn't count — only confirmed recordings count).
**Validation:** each item needs amount > 0 and a category; if an item has no amount it's shown with an "Amount?" field in error state and Save disabled until fixed or removed (EC-30); ≥ 1 item to save.
**States:**
- *Loading* — "Understanding…" ≤ 2 s (NFR-PERF-05).
- *Empty* — nothing recognized: "I didn't catch an amount. Try: '150 vegetables'" + Try again + Type instead.
- *Error* — no on-device Arabic recognition: "Voice isn't available for Arabic on this phone" + Type instead (EC-32, OQ-06). Mic denied: explainer + Open settings + Type instead.
- *Limit reached* (Free, 15 used) — before listening: "You've used your 15 voice logs this month" + **Unlimited with Gold** (S-68) + **Type instead**. Counter resets on the 1st (A-15).

---

## S-32 Scan screenshot / receipt — قراءة سكرين شوت
**Purpose:** turn a screenshot (e.g. InstaPay receipt, online-bank app screen) into a transaction. FR-ING-I-04, FR-ING-I-08. Entry also via share sheet / Back-Tap shortcut on iOS.

```
┌──────────────────────────────┐
│ ← Scan                        │
│  ▢ (image preview)            │
│  Found:                        │
│  Amount     1,250.00 EGP  ✎   │
│  To/From    ahmed.ali@instapay ✎│
│  Reference  62910482112       │
│  Date       23 Oct 2026       │
│  Category   ( Choose ▾ )      │
│  Account    ( NBE •4567 ▾ )   │
│  [ Save ]   Choose another image │
└──────────────────────────────┘
```
**Interactions:** opens photo picker if not launched with an image. Fields editable before save. Dedupe check against existing transactions (same amount + reference/time) → "Already captured from SMS" with [View] [Save anyway].
**Validation:** amount §5.6; currency required; date ≤ today; account required.
**States:** *Loading* — "Reading image…" spinner. *Empty* — no text/amount found: "Couldn't find a payment in this image" + Choose another / Type instead. *Error* — unsupported file type → message; photo permission denied → explainer.
