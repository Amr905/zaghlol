# Screens 60 — Zaghlol tab (S-50, S-51)

---

## S-50 Ask Zaghlol — اسأل زغلول
**Purpose:** ask money questions in Arabic (incl. colloquial) or English and get exact answers from local data, optionally roasted. FR-CHAT-01…05, D-06.

```
┌──────────────────────────────┐
│ Zaghlol          (All cards ▾)│ filter applies to answers
│ (Ask | Tips)                  │ Tips segment ONLY when ROI flag on
├──────────────────────────────┤
│ ~~~ "Ask me about your money" │ first-time greeting
│                               │
│            How much on coffee │ user bubble (end-aligned)
│            last 3 months? 😂   │
│ ~~~ Aug 3,620 · Sep 3,950 ·   │ Zaghlol bubble + C-33 mini bar chart
│     Oct 3,850 EGP (47 orders) │
│     [ ▅ ▇ ▆ ]                 │
│     Open in Transactions ▸    │ → S-11 with the same filters
├──────────────────────────────┤
│ (Spent on CIB this month?) (Top merchants) (Bills due) │ suggestion chips
│ 🔥 Roast me ⏻                 │ roast toggle
│ [ Type your question…    ] ➤  │
└──────────────────────────────┘
```
Supported question types (FR-CHAT-01): spend by category / merchant / card over a period; compare periods; top merchants; account balance; remaining budget; upcoming dues; biggest expense; savings this month. Answers give one figure per currency.
**Interactions:** send → typing indicator → answer. Tapping a suggestion sends it. Roast toggle changes answer style only (C-33 roast variant); numbers identical. Conversation is kept on device for the session; **Clear chat** in overflow (UX-A-04).
**Validation:** 1–300 characters; send disabled when empty.
**States:**
- *Empty* — greeting + 3 suggestion chips.
- *Unsupported question* — "I can't answer that yet. Try:" + 3 examples (FR-CHAT-03). Never invents numbers.
- *No data for period* — "No spending on coffee between … and …" (EC-33).
- *Loading* — typing indicator.
- *Error* — "Something went wrong reading your data" + retry.

---

## S-51 Smart ROI tips — نصايح زغلول (Gold · flag)
**Purpose:** show qualifying Smart ROI rules with projections. FR-ROI-01…04. **Hidden unless flag on.**

```
│ (Ask | Tips 2)                         │
│ ⓘ Not financial advice                 │ always visible (FR-ROI-02)
│ ~~~ roiBulb                             │
│ ☕ Coffee machine instead of cafés      │
│ You spend 2,450/mo at cafés.            │
│ An installment machine + beans ≈ 1,250/mo
│ Year 1: save ~14,400 · Year 2: ~24,000  │
│ [ Share ]  [ Not for me ]               │ share → S-73; dismiss hides tip
```
Rule content and numbers follow spec §12. Whether tips may name specific brands, funds or yields is **not decided** (the feature is flagged off, D-10) — see design question DQ-03 in `README.md`; the layout supports either.
**States:** *Empty* — "No tips right now — I'll tell you when I spot one." *Locked* (Free) — preview + S-68.
