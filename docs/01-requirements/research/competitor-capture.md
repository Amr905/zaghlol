# Research — How Say and FinArt capture & parse transactions

Date: 2026-10-31 · Author: requirements-analyst · Feeds: FR-ING-A, FR-ING-I, FR-PAR, D-02, D-09, D-23

Method: public store listings, vendor websites, and comparison articles. Neither vendor documents its internals, so anything about *how* parsing works is their marketing claim, not verified. No apps were decompiled.

## 1. Summary

| | Say (sayapp.net, Egypt) | FinArt (finart.app, India-first, global) | Implication for Zaghlol |
|---|---|---|---|
| **Android — SMS** | Reads bank SMS with SMS read permission ("SMS Auto-Tracking"), a **Pro (paid)** feature. "Monitors incoming messages for transaction keywords" then "uses AI to extract the amount, merchant, and transaction type." | Reads "permitted SMS". | Both read SMS on Play → the "SMS-based money management" exception is obtainable for this category. Zaghlol keeps SMS free (growth goal) but must still pass Play review. |
| **Android — notifications** | Website says it captures "bank apps, wallets" notifications. | Uses "notification access to detect transaction alerts". | Notification listener is standard practice → keep as a first-class channel (FR-ING-A-03), not just a fallback. |
| **Android — email** | Not mentioned. | Reads "transactional emails you authorise". | Deferred (D-23). |
| **iOS — SMS** | SMS tracking described as **Android-only** in a third-party comparison; iOS relies on Apple Pay + voice. | Release notes: "Easier setup for SMS and wallet automations" → Shortcuts **Message** automation. Own site: "iOS doesn't let apps read SMS in the background, so SMS capture depends on your sharing it". | Shortcuts Message automation is the only realistic automatic SMS path on iOS. Neither competitor uses a message filter extension → supports R-02. |
| **iOS — Apple Pay** | "Bank SMS, app notifications, Apple Pay." | "Apple Pay / Wallet transactions" via Wallet automation. | Shortcuts **Transaction** automation provides Amount, Merchant, Card fields → reliable for Apple Pay taps only (not physical card or online card use). |
| **iOS — other** | Voice (AR/EN). | Email, PDF statements (via Share Sheet). | PDF import + share-sheet confirmed as useful. Zaghlol adds screenshot OCR (neither competitor advertises it). |
| **Parsing approach** | Keyword trigger + "AI" extraction; listing claims processing "securely on your device" but is ambiguous. | "On-device intelligence"; "AI expense tracker at its core". | Competitors market AI. Zaghlol's template registry + heuristics is deterministic and auditable; an on-device ML fallback for unrecognized formats could be a later enhancement (OQ-14). |
| **Account / backend** | Data-safety label says "No data collected", but stores data encrypted in transit; household sharing in terms → some backend. | Privacy label: financial info, email, user ID, messages **linked to user**; "Private Mode" keeps data on device; family sync & web → a cloud backend. | Zaghlol's "financial data never leaves the phone by default" stays a real differentiator even with the new backend (D-13). |
| **Pricing (observed)** | Pro EGP 99.99/mo or 699.99/yr (also $4.99/mo listed). | $2.99/mo, $24.99/yr; automated tracking is **paid**. | Both put auto-capture behind the paywall. Zaghlol's free auto-capture is an acquisition advantage (D-08). |

## 2. Key mechanics confirmed

**iOS Shortcuts — Message automation** (used by FinArt and similar apps such as Pocket Clear):
- Trigger: *Message → Message Contains "<keyword>"* (e.g. "خصم", "debited"); one automation per keyword; set to **Run Immediately**; action = the app's App Intent receiving *Shortcut Input* (message text).
- Implication: Zaghlol's one-tap Shortcut (FR-ING-I-06) should bundle several keyword automations (Arabic + English) and the setup checker should detect missing ones.

**iOS Shortcuts — Transaction (Wallet) automation:**
- Trigger: *Transaction* on chosen cards → Run Immediately → app intent with **Amount, Merchant, Card or Pass**.
- Dedupe needed when the same payment also arrives as a bank SMS (FR/BR-ING-02).

**Android:**
- READ_SMS / RECEIVE_SMS needs the Play exception ("SMS-based money management — e.g. apps that track and manage budget"); Play's spyware policy forbids taking non-financial SMS.
- Some apps (e.g. Pocket Clear) avoid SMS permission entirely and use notifications from chosen apps — a viable fallback if Play refuses (D-02).

## 3. Recommendations adopted into SRS v0.2
1. Notification capture is a primary Android channel alongside SMS (FR-ING-A-03 priority unchanged, wording strengthened).
2. iOS Shortcut package = multiple Arabic/English keyword Message automations + one Wallet Transaction automation (FR-ING-I-06).
3. Keep the message filter extension as a feasibility item only (R-02); no competitor relies on it.
4. Keep auto-capture **free** to differentiate (both competitors charge for it).
5. Email capture recorded as a later option (D-23, OOS-14).

## Sources
- [Say — website](https://www.sayapp.net/)
- [Say — Google Play listing](https://play.google.com/store/apps/details?id=com.moments.expenses&hl=en)
- [FinArt — App Store listing](https://apps.apple.com/us/app/finart-ai-expense-tracker/id6748001842)
- [FinArt — Automatic expense tracker for iPhone](https://finart.app/automatic-expense-tracker-iphone/)
- [FinArt — SMS expense tracker](https://finart.app/sms-expense-tracker/)
- [Flosyfeen — Best expense tracking apps in Egypt 2026 (publisher is a competitor)](https://flosyfeen.com/en/blog/best-expense-tracking-apps-egypt)
- [Pocket Clear — Auto-log Apple Pay & bank SMS with iPhone Shortcuts](https://pocketclear.app/blog/auto-log-apple-pay-bank-sms-iphone-shortcuts.html)
- [Google Play — Use of SMS or Call Log permission groups](https://support.google.com/googleplay/android-developer/answer/10208820?hl=en)
