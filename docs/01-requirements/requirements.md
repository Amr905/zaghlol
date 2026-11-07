# Zaghlol (زغلول) — Software Requirements Specification

| | |
|---|---|
| Document | `docs/01-requirements/requirements.md` |
| Version | 1.8 — APPROVED (+ changes D-34, D-36…D-66) |
| Phase | 1 — Requirements refinement |
| Author | requirements-analyst (Lead session) |
| Date | 2026-10-31 |
| Related | `research/competitor-capture.md` (Say & FinArt capture research) · `institutions.md` (supported institutions list) |
| Source | `Zaghlol_Feature_and_Product_Specification_v4.docx` (title page says v3.0; file named v4 — treated as one source, referred to as "the spec") |
| Status | Approved by product owner 2026-11-01; D-34 approved change 2026-11-01 |

**How to read this document.** Every requirement has an ID. Anything not stated in the spec or decided by the product owner is recorded as an **Assumption (A-##)** in §14 or an **Open Question (OQ-##)** in §15 — nothing is assumed silently. Priorities use MoSCoW (**M**ust / **S**hould / **C**ould). Tier: **F** = Free, **G** = Zaghlol Gold, **F/G** = both with different limits.

### Change log
| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-10-31 | First draft from interview rounds 1–3 (D-01…D-12). |
| 0.2 | 2026-10-31 | Product-owner review round 1 (D-13…D-24): **introduces a .NET + PostgreSQL backend** for purchase verification, merchant/category catalog sync, price feed and remote feature flags; optional sign-in; opt-in anonymous merchant contribution; full-device encryption of all local data; backup now includes all settings & customizations; reimbursement of expenses by incoming transfers; frictionless onboarding; 8 currencies; competitor capture research. |
| 0.3 | 2026-11-01 | Product-owner review round 2 (D-25…D-31): **per-card spending breakdown**; **ignore SMS / notifications / Apple Pay per card** (never stored); **online & foreign banks** (Wise, Revolut, Monzo, bunq, N26, Paytm, HDFC; Klivvr already covered) for Egyptians with foreign accounts; **native multi-currency** — any ISO 4217 currency, everything reported per currency, optional approximate-EGP view (supersedes D-22's 8-currency list and EGP-equivalent rules). |
| 0.4 | 2026-11-01 | Review round 3 (D-32, D-33): **Payoneer, Emirates NBD Liv, Al Rajhi** added at launch; GCC and more Egyptian fintechs proposed; institution coverage moved to `institutions.md`; **generic parser + "request my bank"** for unlisted banks; **one free cloud backup** (Google Drive / iCloud) for Free users. Resolves OQ-13, OQ-17; mitigates R-14. |
| 1.0 | 2026-11-01 | Approved by product owner. |
| 1.1 | 2026-11-01 | Approved change D-34: whole Arabic UI in Egyptian colloquial, fun & easy (FR-L10N-02 rewritten, FR-L10N-04 added); new logo = Captain Zaghlol holding coins. |
| 1.2 | 2026-11-02 | Design-review decisions: **D-36** bulk edit of transactions (FR-TXN-06); **D-37** operator admin web app, delivered after the first release (FR-BE-08, OQ-12 resolved); **D-38** Smart ROI gives general advice only at first, named products later (FR-ROI-05). |
| 1.3 | 2026-11-03 | Phase 3 answers: D-39…D-44 (iOS approach, Tesseract OCR, local gold feed, online speech with consent, min OS, Apple sign-in on Android). OQ-02/03/06/15 resolved; OQ-16 still open. |
| 1.4 | 2026-11-05 | Product-owner decisions D-45…D-51: **device attestation** (Play Integrity / App Attest) added to BR-SYNC-03; **Gold restore anti-sharing** — max 3 installs per purchase, account-linked purchases move only between that account's installs, attestation required on restore (FR-GOLD-08/09, ADR-012 Amendment (2026-11-05)); **support-lookup audit** with HMAC e-mail pseudonym kept 1 year (NFR-PRIV-07, FR-BE-11); BR-SYNC-03 classification of version cursors, restore `productId` and sign-in `nonce`; A-47 narrowed to the ID-token `email` claim; **OEM transfer outcome** for FR-SEC-05 (keyless DB wiped → fresh Welcome + restore offer); **ISO 4217 funds codes** shown last in the currency picker, X-codes excluded (FR-CUR-07). New EC-64…EC-67, R-19/R-20, INT-22. |
| 1.5 | 2026-11-06 | Product-owner decisions D-52…D-54: **Gold on one phone at a time, moved at most once per rolling 30 days** (D-52, supersedes D-46's 3-install limit; attestation on restore and the account rule stay) — FR-GOLD-02/03/07/08/09, BR-GOLD-03, new BR-GOLD-07, R-04 role, EC-64…EC-66, new EC-68, R-19, new R-21, new OQ-19 (same-phone recognition, support move vs. window); **FR-GOLD-09 attestation wording** per platform (D-53: "expired" is Android-only, iOS App Attest uses per-install key + counter); **no self-service relinking after a phone change** — link only from the buying phone, otherwise support (D-54) — FR-ACCT-01/02, new FR-ACCT-05, EC-65. |
| 1.6 | 2026-11-06 | Product-owner decisions D-55…D-60, **OQ-19 closed**: **same-iPhone reinstall recognised** via a ThisDeviceOnly Keychain install secret, sent only as a derived non-reversible proof (D-55, amends BR-SYNC-03); Android reinstall / "Delete everything" = new install that spends the move, with a warning; **support move restarts the 30-day window** (D-56); **support ownership check** by live store order-ID verification (order ID never stored), single agent, link only if the buying phone is gone or unseen ≥ 30 days, audited and reversible, losing phone told (D-57); **free reclaim once per purchase** on first account link (D-58); **plan change from another phone counts as the move**, payment never blocked (D-59); **offline window for a phone that lost Gold cut to 7 days** (3-day token + 4-day grace; amends A-38, BR-GOLD-03/07) and **clock-rollback withholding** with trusted time (D-60). Changed: FR-GOLD-03/07/08, FR-ACCT-03/05, FR-BE-08/11, BR-GOLD-03/07, BR-SYNC-03 (+ D-48 classification list), NFR-PRIV-07, new NFR-SEC-08 (trusted time), A-38, EC-64…EC-68, new EC-69…EC-73, R-19, R-21, OQ-19 closed, new OQ-20 (plan change inside cooldown, reclaim vs. window, signed-out holder). **Same day, D-61 closes OQ-20:** (a) a plan change from another phone when the month's move is used completes the payment but leaves Gold on the current phone, the paying phone sees the next-move date (amends D-59); (b) the free reclaim counts as the month's move and restarts the window, still bypassing a running cooldown (amends D-58); (c) sign-out pauses account-linked Gold on the holder until sign-in, the seat stays reserved and no move is spent; unlinked purchases unaffected. Changed: D-58, D-59, FR-GOLD-08, FR-ACCT-03/05, BR-GOLD-07, EC-71…EC-73, OQ-20. |
| 1.7 | 2026-11-06 | Product-owner decisions D-62…D-64: **iPhone seat keys and linkability accepted** (D-62) — each iOS restore and sign-in sends `seatKeys[] {publicKey, signature}`: a proof from the current install's Secure Enclave key plus up to 4 keys from earlier Zaghlol installs on that iPhone; the backend may see in transit which installs share an iPhone, keeps only a keyed hash per purchase at rest, never logs raw keys; supersedes D-55's "derived, non-reversible proof of a Keychain secret" form; "Delete everything" on iOS keeps the seat keys on the phone and a keyed hash on the server (privacy notice); **at most 2 free same-iPhone reinstall recognitions per purchase per rolling 30 days**, beyond that the restore/sign-in counts as the monthly move (D-63, amends D-55); **30-day dispute freeze** on further support moves/links after a support correction, corrections still allowed, freeze visible to support (D-64). Classification: the random per-request **time nonce** (NFR-SEC-08) added to the D-48 list. **Support-link notice:** a buying phone that reappears after support linked its purchase to an account is told once. Changed: D-48 (addendum), D-55 (marked), BR-SYNC-03, BR-GOLD-07, FR-ONB-08, FR-GOLD-03/08, FR-ACCT-05, FR-BE-08/11, NFR-PRIV-07, NFR-SEC-08, EC-65, EC-67…EC-69, R-19, R-21, glossary (seat key, time nonce, dispute freeze); new OQ-21 (cap overflow when the month's move is used; freeze scope). **Same day, D-65 closes OQ-21 (both recommendations taken):** (a) an over-cap same-iPhone reinstall on the iPhone that holds Gold is never refused — the phone keeps Gold and the 30-day move window restarts, even if this month's move is already used; an over-cap reinstall on an iPhone that does not hold the seat follows the normal move rules; (b) the dispute freeze blocks support moves and links only (self-service move rules unchanged), each new correction restarts the 30-day freeze, and support attempts refused by the freeze are audited. Changed: D-63, D-64, FR-GOLD-03, FR-GOLD-08, FR-ACCT-05, FR-BE-08, FR-BE-11, BR-GOLD-07, EC-65, EC-68, EC-69, R-19, R-21, glossary (dispute freeze), §16 traceability row, OQ-21 (closed). |
| 1.8 | 2026-11-06 | Product-owner decision **D-66 (R5-3): accepted residual on the holding iPhone.** iOS sign-in carries **no App Attest** (PO declined to add it), so a seat key registered through sign-in is **not trusted** as "same iPhone". When Gold was bought on Android (Google Play) or under a different Apple ID, the holding iPhone has no App Store transaction to restore with; after a **3rd reinstall within 30 days** the owner **can be refused on that iPhone for up to 30 days** (until the next-move date). The app shows the next-move date and the support path; support can move the seat (unfreeze first if a dispute freeze is running). **Narrows D-65(a):** "never refused on the holder" now holds whenever the owner can restore with an App Store purchase on that iPhone. **R5-9 wording corrections (no new data):** the server also keeps a per-install keyed hash of the install's own seat key (`installs.seat_key_hash`, keyed with the install ID, not joinable across installs, deleted with the install); `seatKeys` element 0 (the install's own key) is also sent on **purchase verify**, not only restore and sign-in. **R6-1 support roles:** the operator who lifts a dispute freeze cannot redo the move the freeze protected (server-enforced); support-lead **unfreeze** action recorded (different operator from the correction's, ownership check, audited, moves nothing). Changed: D-62, D-63 (marked), D-65 (marked), BR-SYNC-03, FR-GOLD-03, FR-GOLD-08, FR-BE-08, NFR-PRIV-07, EC-69, R-19, glossary (seat key, dispute freeze), §16 traceability row. |

---

## 1. Purpose & product summary

Zaghlol is a personal-finance app for Egyptian consumers that captures spending automatically from bank, InstaPay, mobile-wallet and BNPL messages, categorizes it against an Egyptian merchant map, and coaches the user in Egyptian colloquial Arabic through a cartoon pigeon mascot, Captain Zaghlol. **All financial data — messages, transactions, balances, budgets, assets and the user's own rules — is processed and stored only on the user's phone.** A small Zaghlol backend (.NET + PostgreSQL) provides non-financial services: purchase verification, the shared merchant & category catalog, gold/FX prices, and feature flags (D-13).

## 2. Product-owner decisions (Phase 1 interview, 2026-10-31)

| ID | Decision | Effect |
|----|----------|--------|
| D-01 | Launch on **Android and iOS together**. | iOS capture is weaker by platform design; requirements cover both. |
| D-02 | Android capture: **apply for the Google Play SMS exception ("SMS-based money management") and build fallbacks** (bank-app notifications, share/paste). | App must remain useful if Play denies SMS permission. |
| D-03 | Release scope: **full spec** (not a reduced MVP). | All modules in §7 are in the launch release unless flagged. |
| D-04 | **One person per phone.** No household sharing, no multi-profile. | Single local user; "family budget" = the user's household spending. |
| D-05 | Gold & currency prices: **fetched automatically** (via the Zaghlol backend since v0.2, D-13), sending no user data; manual override; last-known price used offline. | See NFR-PRIV-03, FR-BE-04. |
| D-06 | "Ask Zaghlol" chat: **rules/templates engine**, fully offline. No LLM. | Chat answers a defined set of question types (FR-CHAT). |
| D-07 | Zakah: **build behind a feature flag, disabled at launch**, enabled only after scholar review; shows "estimate — consult a scholar" disclaimer. | FR-ZAK is built and tested but not user-visible at launch. |
| D-08 | Primary first-year goal: **user growth**. Paid tier is light-touch. | Success metrics favour activation & retention (§3). |
| D-09 | iOS: **keep all 5 capture channels as specified**, including the message-filter extension, subject to architect feasibility study. | Risk R-02 recorded. |
| D-10 | Smart ROI coach: **build behind a feature flag, disabled at launch**. | FR-ROI built but not user-visible at launch. |
| D-11 | Google Drive backup goes to the **hidden app-data folder** (`drive.appdata`). | User does not see the file in Drive; restore is via Zaghlol only. |
| D-12 | Paid tier: name **Zaghlol Gold**, structure monthly / yearly / lifetime and free-tier limits as in spec; **final prices TBD before launch**. | Spec prices (49 / 399 / 899 EGP) are placeholders. |
| D-13 | **Introduce a backend: .NET + PostgreSQL.** Jobs: (1) purchase verification & entitlements, (2) merchant & category catalog, (3) gold/FX price feed, (4) remote feature flags. It never receives transactions, messages, balances, budgets, assets or the user's own rules. | Replaces spec's "zero backend". New module BE (§7.27). Marketing claim "no server at all" must change (R-11). |
| D-14 | **Identity: anonymous by default, optional sign-in** (Google / Apple) used only to carry Gold across Android ↔ iOS. | New role R-04; FR-ACCT. |
| D-15 | **Catalog sync**: merchants, categories, keywords stored in the encrypted local DB; on app open, refresh from backend **at most once per 24 h**; app works fully with the last downloaded version. | FR-SYNC. |
| D-16 | **Opt-in anonymous merchant contribution**: if the user agrees, unknown merchant names are sent (no amounts, dates, accounts, or person names). Off by default. | FR-CAT-09, BR-SYNC-04. |
| D-17 | **SMS templates are not updated from the backend**; they ship with app releases. | FR-PAR-08 unchanged; OTA templates recorded as later option (OOS-15). |
| D-18 | **Everything stored on the phone is encrypted** and inaccessible outside the app (DB, preferences, files, caches). | FR-SEC-03…07, NFR-SEC. |
| D-19 | **Backup contains everything needed to continue on a new phone**: data, preferences, settings, custom categories, rules and every other customization. | FR-BAK-06. |
| D-20 | **Incoming transfers (InstaPay, wallet, cash) can be assigned as reimbursements of an expense** — e.g. user paid the restaurant bill, friends sent their share. | FR-XFR-06…09, BR-XFR-05…08. |
| D-21 | **Onboarding must be as easy as possible.** | FR-ONB rewritten (§7.1). |
| D-22 | ~~Supported currencies: EGP, USD, SAR, EUR, AED, QAR, KWD, BHD.~~ **Superseded by D-28/D-29.** These 8 remain the *featured* currencies (shown first in pickers). | — |
| D-23 | **No email capture for now**; recorded as a later option. | OOS-14. |
| D-24 | Capture design informed by Say/FinArt research. | `research/competitor-capture.md`; FR-ING updates. |
| D-25 | **Per-card breakdown**: every list, chart and the home screen can be filtered by card/account, and each card shows its own category split. (Per-card budgets, card default categories and card groups were *not* selected.) | FR-CARD (§7.30); OOS-17. |
| D-26 | **Ignore capture per card**, separately for SMS, app notifications and Apple Pay. Ignored messages are **never stored**. | FR-CAP (§7.31), BR-CAP. |
| D-27 | **Online & foreign banks** supported for **Egyptians with foreign accounts** (not new markets): Wise, Revolut, Monzo, bunq, N26, Paytm, HDFC Bank (+ Klivvr, already covered). The list is extensible. | FR-PAR-10, FR-ING-A-07, FR-ING-I-08, FR-EXP-06; persona P-06. Market stays Egypt (OOS-06). |
| D-28 | **Currencies are tracked natively** — balances, transactions, assets and budgets stay in their own currency; nothing is converted to EGP for storage. **Any active ISO 4217 currency** is supported. | BR-MON-03, BR-FX-01, FR-CUR (§7.32). |
| D-29 | **Reporting is per currency with a currency switcher**; an **optional, clearly labelled "≈ in EGP" view** (user setting, off by default — A-54) combines currencies using the latest backend rates. | FR-CUR-02…05. |
| D-30 | Online-bank users on iOS are captured only where Apple allows: Apple Pay (Wallet automation), screenshot OCR, statement import. App notifications from these banks cannot be read on iOS. | FR-ING-I-08; R-15. |
| D-31 | Ignoring a card applies to future messages; Android users can re-run a historical scan after un-ignoring. | BR-CAP-04. |
| D-32 | **Institution coverage expanded**: Payoneer, Emirates NBD (incl. Liv) and Al Rajhi added as launch musts; other international, GCC and Egyptian institutions supported through `institutions.md` (proposed rows to confirm) plus a generic parser and a "request my bank" flow for anything unlisted. | `institutions.md`; FR-PAR-13, FR-PAR-14. |
| D-33 | **Free users get one cloud backup** on Google Drive or iCloud. | FR-BAK-08 rewritten; §5.2; BR-BAK-02. Gold keeps automatic schedules and backup history. |
| D-34 | **The Arabic app speaks Egyptian colloquial throughout** (العامية المصرية) — labels, buttons, messages and Captain Zaghlol — fun and easy for most users. Standard Arabic only for legal texts and disclaimers. Logo = the funny Captain Zaghlol holding coins. | FR-L10N-02/04; `docs/02-design/06-voice-and-tone.md`. |
| D-36 | **Bulk edit**: the user can select several transactions and change them in one action. | FR-TXN-06. Resolves DQ-01. |
| D-37 | **Operator admin web app** for the Zaghlol team (catalog, contributed merchants, feature flags, entitlement lookup), **out of scope for the first delivery**; v1 operates with scripts. | FR-BE-08; resolves OQ-12 / DQ-02. Designed and built in a later release. |
| D-38 | **Smart ROI tips start with general advice only** (e.g. "a bank savings certificate", "gold") — no bank, fund or product names and no named yields. Naming real products is a future option. | FR-ROI-05; resolves DQ-03. |
| D-39 | **iOS capture follows the FinArt / Say approach** (CR-01): Shortcuts **Message** automations + Shortcuts **Transaction (Wallet/Apple Pay)** automation, plus voice, manual, share/screenshot OCR and statement import. The message filter extension is **dropped** (Apple blocks it from sharing data with the app). | FR-ING-I-03 removed; R-02 closed. |
| D-40 | Android Arabic OCR uses Tesseract alongside ML Kit (CR-02). | ADR-009. |
| D-41 | Gold prices come from a **local Egyptian gold-market feed** (OQ-02); provider contract TBD; FX from a licensed source. | ADR-014. |
| D-42 | If on-device Egyptian Arabic speech isn't available, the OS online recognizer may be used **with explicit consent** (OQ-06). | ADR-010. |
| D-43 | Minimum OS: Android 8.0 (API 26), iOS 17.0 (CR-04, OQ-03). | ADR-019. |
| D-44 | Sign in with Apple is also offered on Android via Apple's web flow (CR-05). | ADR-016, FR-ACCT-01. |
| D-45 | *(2026-11-05)* **BR-SYNC-03 amended: device attestation.** The app may also send a device attestation token or assertion — **Play Integrity** (Android) or **App Attest** (iOS) — used for purchase restore and possibly purchase verification. It carries no other device data. Reason: stop sharing of Gold purchase tokens. | BR-SYNC-03, FR-GOLD-09, INT-22, R-19. |
| D-46 | *(2026-11-05)* **Gold restore anti-sharing.** ~~At most **3 installs** may hold Gold from one purchase at the same time.~~ *(3-install limit superseded by D-52, 2026-11-06 — one install at a time.)* A purchase **linked to an account** moves only between installs signed in to that account. **Device attestation is required on restore.** Technical design: ADR-012 Amendment (2026-11-05), by the architect. | FR-GOLD-02/03/07, FR-GOLD-08/09, EC-64…EC-66. |
| D-47 | *(2026-11-05)* **Support-lookup audit retention.** Every operator support lookup leaves an audit row holding a **keyed (HMAC) pseudonym of the e-mail** plus the account ID. The row is kept **1 year, then deleted** — also when the account has been deleted in the meantime. | FR-BE-08, FR-BE-11, FR-ACCT-04, NFR-PRIV-07. |
| D-48 | *(2026-11-05)* **BR-SYNC-03 classification** (no new data class): the server-issued version cursors `flagsVersion`, `pricesAsOf`, `entitlementIssuedAt`, `registryVersion` count as **"catalog/app version"**; the restore `productId` counts as **"purchase tokens/transactions"**; the raw sign-in `nonce` counts as **"optional account ID token"**. *(v1.6 addendum: plan-change tokens (D-59) → "purchase tokens/transactions"; the store order ID (D-57) is never sent by the app nor stored; the iOS Keychain-derived install proof is a new class added by D-55, not a classification.)* *(v1.7 addendum: the per-request random **time nonce** (NFR-SEC-08), which carries no device data and only binds a signed server time to the app's own request → classified with the request it travels in, not new data; the iOS `seatKeys[]` field is a new class set by D-62, not a classification.)* | BR-SYNC-03. |
| D-49 | *(2026-11-05)* **A-47 narrowed.** The support e-mail comes **only** from the Apple/Google ID token's `email` claim. For Sign in with Apple on Android, `scope=email` is requested; Apple's `user` form field is **never read**. | A-47, FR-ACCT-02. |
| D-50 | *(2026-11-05)* **FR-SEC-05 outcome accepted.** If an OEM transfer tool (e.g. Samsung Smart Switch) copies app data despite the exclusion rules, the app detects a database without its key, **wipes it**, and starts at a **fresh Welcome screen with the restore offer**. | FR-SEC-05, EC-67, R-20. |
| D-51 | *(2026-11-05)* **Currency picker: funds codes shown, X-codes not.** ISO 4217 "funds" codes (e.g. BOV, CLF, UYW) are supported and listed **at the end** of the currency picker, after featured and regular currencies. Non-currency X-codes (e.g. XAU, XDR, XTS) are not offered. | FR-CUR-01, FR-CUR-07. |
| D-67 | *(2026-11-07)* **XAD hidden.** ISO 4217 List One (published 2026-09-17) flags XAD (Arab Accounting Dinar, Arab Monetary Fund) as a fund with 2 minor units. It is an accounting unit like XDR, so it is treated as a non-currency X-code and not offered. The funds set stays the 9 codes in FR-CUR-07. | FR-CUR-07, T-012. |
| D-52 | *(2026-11-06)* **Gold on one phone, moved at most once a month.** Replaces D-46's 3-install limit; the rest of D-46 stands (attestation required on restore; account-linked purchases move only between installs signed in to that account). (a) Gold from one purchase is held by **exactly one install at a time**, across Android and iOS. (b) The owner can move Gold to another phone **once per rolling 30 days**; moving between platforms counts as that move; restoring on the **same phone** is never a move. (c) Inside the 30 days, a restore or sign-in on a different phone is **refused**; the user sees when the next move is possible and is pointed to support; support can make an **audited manual move**. (d) The phone Gold moved away from loses Gold at its next online refresh, or — if it stays offline — within the entitlement token lifetime (~~**at most 14 days**, architect's design~~ *superseded by D-60: at most 7 days*); offline use of at least 5 days (FR-GOLD-04) is kept. | FR-GOLD-02/03/07/08/09, BR-GOLD-07, §5.1 R-04, EC-64…EC-66, EC-68, R-19, R-21; ADR-012 Amendment to be revised by the architect. |
| D-53 | *(2026-11-06)* **FR-GOLD-09 wording.** "Expired attestation" applies only to Android **Play Integrity**, whose verdict carries a timestamp. On iOS, **App Attest** assertions are bound to a per-install key and a monotonic counter, with no expiry and no server challenge; the iOS failure cases are unknown/unattested key, invalid signature and counter not increasing (replay). | FR-GOLD-09. |
| D-54 | *(2026-11-06)* **No self-service relinking after a phone change.** A purchase can be linked to an account **only from the phone that bought it**. If that phone is gone (reset, lost or sold without signing out), the owner must contact support. In-app guidance: "sign in on the phone you bought Gold on to protect it". | FR-ACCT-01/02/05, FR-GOLD-07/08, EC-65. |
| D-55 | *(2026-11-06, resolves OQ-19a)* **Same-iPhone reinstall is recognised.** On iOS the app keeps a random **install secret in the Keychain** with a *ThisDeviceOnly* accessibility class: it survives an app reinstall on the same device but never moves to another device (not in device-to-device transfer or backups). A reinstall or "Delete everything" on the same iPhone is therefore **not a move** *(up to the D-63 cap: at most 2 such recognitions per purchase per rolling 30 days)*. ~~The app sends the backend only a **derived, non-reversible proof** of that secret, never the secret itself — this **amends BR-SYNC-03** (a per-device Keychain-derived proof on iOS, carrying no other device data); exact form designed by the architect.~~ *(Proof form superseded by D-62, 2026-11-06: Secure Enclave seat keys sent as `seatKeys[] {publicKey, signature}`; linkability of installs on the same iPhone accepted.)* **Android has no safe equivalent:** a reinstall or "Delete everything" on Android counts as a **new install and spends the monthly move**; the app **warns the user before** a "Delete everything" (and in help copy for reinstalling) when the phone holds Gold. | BR-SYNC-03, FR-GOLD-03/08, EC-69, EC-73; ADR-012 Amendment to be revised. |
| D-56 | *(2026-11-06, resolves OQ-19b)* **A support move restarts the 30-day move window**, exactly like a self-service move. *(Supersedes OQ-19's recommendation that it should not.)* | FR-GOLD-08, FR-BE-08, BR-GOLD-07, EC-68. |
| D-57 | *(2026-11-06)* **Support's ownership check.** (a) Before support moves Gold or links a purchase to an account, the user must give the **store order ID** (Google Play order ID or Apple order ID). (b) Support checks it **live against Google or Apple**; the order ID is **never stored** — only the fact that the check passed is audited. (c) **One support agent** may act; no second approver. (d) Support may **link** a purchase to an account only when the buying phone is **gone or not seen for ≥ 30 days**; otherwise the owner links from the buying phone (D-54). (e) Every support move and link is **audited** and **reversible through an audited correction** (move back, or detach and re-link). (f) The phone that **loses Gold through a support move is told so**, with the support contact. | FR-BE-08, FR-BE-11, FR-ACCT-05, FR-GOLD-08, NFR-PRIV-07, EC-68, R-21. |
| D-58 | *(2026-11-06)* **Free reclaim once per purchase.** When the buying phone **first** links an account, a seat held outside that account (e.g. by a phone that restored via the store account only) **returns to the buying phone without the 30-day cooldown**. This happens **at most once per purchase**, even if the account is deleted and recreated; later returns follow the normal 30-day rule. *(D-61b: the reclaim **counts as the month's move and restarts the 30-day window**; it still bypasses any running cooldown at that moment.)* | FR-ACCT-05, FR-GOLD-08, EC-72. |
| D-59 | *(2026-11-06)* **A plan change counts as a move.** If the Gold plan is upgraded or downgraded (e.g. monthly → yearly) **from a phone other than the current holder**, Gold moves to that phone and this **counts as the monthly move**. The **payment itself is never blocked**. *(D-61a: if this month's move is already used, the payment still completes but Gold **stays on the current phone**; the paying phone sees the next-move date.)* | FR-GOLD-08, BR-GOLD-07, EC-71. |
| D-60 | *(2026-11-06)* **Tighter offline window + clock-rollback guard.** (a) A phone that has **lost** Gold keeps it offline for **at most 7 days**: an entitlement token of **3 days** plus **4 days of grace**. Amends A-38, BR-GOLD-03, BR-GOLD-07; FR-GOLD-08's "14 days" becomes "7 days" *(supersedes D-52(d)'s "at most 14 days")*. (b) A phone that **still holds** Gold keeps **at least 5 days** of offline use (FR-GOLD-04 holds). (c) **Security requirement:** if the device clock is detected as **set back**, Gold is **withheld until the app reconnects**, with "connect to check Gold" copy; entitlement expiry is evaluated against **trusted time**, not the raw device clock. | FR-GOLD-04/08, BR-GOLD-03/07, A-38, NFR-SEC-08, EC-64, EC-70. |
| D-61 | *(2026-11-06, resolves OQ-20)* **Seat edge cases.** (a) **Plan change from another phone when this month's move is already used:** the store payment always completes and Gold **stays on the current phone**; the paying phone shows the next-move date (no extra move). Amends D-59. (b) **Free reclaim (D-58) counts as the month's move** and restarts the 30-day window; it still bypasses a running cooldown at that moment (the seat returns even inside a cooldown). (c) **Sign-out on the holder of an account-linked purchase pauses Gold** on that phone until the user signs in again to the owning account; the seat stays reserved — signing out never removes the seat or spends a move. Purchases **not linked** to an account are unaffected by sign-out. | D-58, D-59, FR-ACCT-03/05, FR-GOLD-08, BR-GOLD-07, EC-71…EC-73, OQ-20. |
| D-62 | *(2026-11-06)* **iPhone seat keys and linkability accepted.** To recognise a reinstall on the same iPhone (D-55), each iOS **restore and sign-in** sends a proof made with the **current install's Secure Enclave key**, plus **up to 4 keys from earlier Zaghlol installs on that iPhone**; each key is sent as a **public key and a signature** (`seatKeys[] {publicKey, signature}`, iOS only). The PO **accepts** that the backend can see, **in transit**, which installs came from the same iPhone. **At rest** the server keeps only a **keyed hash per purchase**; raw keys are **never logged**. On iOS, "Delete everything" **keeps the seat keys on the phone** and the keyed hash on the server, and the privacy notice says so. Supersedes D-55's "derived, non-reversible proof" form. *(v1.8, R5-9 wording, no new data: (1) besides the per-purchase keyed hash, the server keeps a **per-install keyed hash of the install's own seat key** (`installs.seat_key_hash`), keyed with the install ID so it cannot be joined across installs, and deleted with the install; (2) `seatKeys` element 0 — the install's own key — is also sent on **purchase verify**, not only on restore and sign-in; the earlier installs' keys travel only on restore and sign-in.)* | BR-SYNC-03, FR-ONB-08, FR-GOLD-03/08, NFR-PRIV-07, EC-67, EC-69; store disclosures; ADR-012 Amendment to be revised. |
| D-63 | *(2026-11-06)* **Cap on free same-iPhone reinstall recognitions.** At most **2** same-iPhone reinstall recognitions (D-55) are free **per purchase per rolling 30 days**. Beyond that, a reinstall restore or sign-in **counts as the monthly move**. Amends D-55's "not a move" (now "not a move, up to the D-63 cap"). *(D-65a: on the iPhone that **holds** the seat, an over-cap reinstall is **never refused** — Gold stays and the 30-day move window restarts, even if this month's move is already used. Narrowed by D-66: this holds when the owner can restore with an App Store purchase on that iPhone.)* | D-55, FR-GOLD-03/08, BR-GOLD-07, EC-69, R-19; OQ-21(a) → D-65a. |
| D-64 | *(2026-11-06)* **30-day dispute freeze after a support correction.** After support **corrects** a move or link on a purchase (move back, detach / re-link, D-57e), any **further support move or link** on that purchase is **refused for 30 days**. **Further corrections are still allowed.** The freeze (and its end date) is **visible to support**. *(D-65b: the freeze covers support moves and links only — self-service move rules are unchanged; each new correction restarts the 30 days; support attempts refused by the freeze are audited.)* | FR-BE-08/11, FR-ACCT-05, EC-68, R-21; OQ-21(b) → D-65b. |
| D-65 | *(2026-11-06, resolves OQ-21)* **Cap overflow on the holder and dispute-freeze scope.** (a) **Over-cap reinstall on the iPhone that holds Gold:** a same-iPhone reinstall restore or sign-in beyond the D-63 cap (3rd or later free recognition inside the rolling 30 days) on the iPhone that **currently holds the seat** is **never refused**: the phone **keeps Gold** and the **30-day move window restarts** from that restore — also when this month's move is already used. (Recommendation taken.) *(Narrowed by D-66, v1.8: "never refused" holds whenever the owner can restore with an App Store purchase on that iPhone; an over-cap **sign-in** with no App Store transaction on the iPhone is the accepted D-66 residual.)* An over-cap reinstall restore on an iPhone that does **not** hold the seat follows the normal move rules (FR-GOLD-08 b/c): allowed and counted if no move in the last 30 days, otherwise refused with the next-move date. (b) **Dispute-freeze scope (amends D-64):** (1) the freeze blocks **support moves and support links only**; the user's own self-service monthly-move rules are **unchanged** by it; (2) **each new correction restarts** the 30-day freeze (the freeze ends 30 days after the latest correction); (3) a support move or link **refused by the freeze is audited** (FR-BE-11). (Recommendation taken.) | D-63, D-64, FR-GOLD-03/08, FR-ACCT-05, FR-BE-08/11, BR-GOLD-07, EC-68, EC-69, R-19, R-21; closes OQ-21. |
| D-66 | *(2026-11-06, R5-3)* **Accepted residual on the holding iPhone.** (a) **Background:** iOS **sign-in carries no App Attest** check, and the PO chose **not** to add one. A "same iPhone" seat key registered through sign-in is therefore **not trusted**; only a key from an App Attest-covered restore is. (b) **Residual (accepted):** an owner **can be refused on the iPhone that holds Gold for up to 30 days** (until the next-move date) after a **3rd reinstall within 30 days** — **only** when the Gold was bought on **Android (Google Play)** or under a **different Apple ID**, so that iPhone has **no App Store transaction to restore with** and can only sign in. (c) **App behaviour:** on refusal the app shows the **next-move date** and the **support path** (instead of a Restore that cannot work); **support can move the seat** after the ownership check (D-57), **unfreezing first** (support lead, FR-BE-08) if a dispute freeze is running. (d) **Narrows D-65(a):** the holding iPhone is never refused **whenever the owner can restore with an App Store purchase on that iPhone**. | D-63, D-65, FR-GOLD-03, FR-GOLD-08, FR-BE-08, EC-69, R-19; ADR-012 Amendment (R5-3 option (b)). |

## 3. Business goals & success metrics

### 3.1 Goals
| ID | Goal | Source |
|----|------|--------|
| BG-01 | Become the default expense tracker for Egyptian smartphone users by removing manual entry (auto-capture from 38 banks, InstaPay, wallets, BNPL). | Spec §1, §3 |
| BG-02 | Win trust through privacy: no account, no bank password, no server. | Spec §1, §2, Campaign #3 |
| BG-03 | Grow through word of mouth: shareable achievement cards and humorous Egyptian persona. | Spec §5 Screen 14, §6 |
| BG-04 | Minimal hosting cost (backend serves only small, non-financial services, D-13); monetize power features via in-app purchase. | Spec §2, D-13 |
| BG-05 | Outperform competitors Say and FinArt on Egypt-specific intelligence (self-transfer detection, colloquial voice entry, gold/CD tracking). | Spec §3 |

### 3.2 Success metrics (first 12 months)
Targets are **proposed** (A-01) — the spec gives none.

| ID | Metric | Proposed target |
|----|--------|-----------------|
| SM-01 | Activation: % of installs that capture ≥ 5 transactions within 48 h | ≥ 50% Android, ≥ 25% iOS |
| SM-02 | D30 retention | ≥ 25% |
| SM-03 | Auto-capture parse accuracy on the reference SMS corpus (correct amount, direction, account, merchant) | ≥ 98% amount/direction, ≥ 90% merchant |
| SM-04 | Auto-categorization rate (no manual fix needed) | ≥ 80% of captured transactions |
| SM-05 | Crash-free sessions | ≥ 99.5% (measured via store consoles only — no in-app telemetry) |
| SM-06 | Gold conversion | Tracked, not targeted in year 1 (D-08) |
| SM-07 | Store rating | ≥ 4.4 on both stores |

Note: the app has no analytics SDK (NFR-PRIV-01). SM-01/02/04 can be measured through store-console statistics, opt-in surveys, or anonymous aggregate counters on the backend (e.g. count of distinct anonymous IDs calling catalog sync per day). How to measure is OQ-01.

## 4. Target users

Personas are derived from the spec's examples (A-02).

| ID | Persona | Profile | Key needs |
|----|---------|---------|-----------|
| P-01 | **Salaried professional** ("Ahmed") | 25–40, Cairo/Alexandria, salary on day 25, NBE + CIB cards, uses InstaPay, Talabat, Uber. Android or iPhone. | Know where salary goes; safe daily spend until payday; no double-counting self-transfers. |
| P-02 | **Household manager** | Runs family groceries and bills, much spending in cash, Vodafone Cash, gameya (جمعية). Prefers Arabic. | Fast cash logging by voice; budget per category; bill & installment reminders. |
| P-03 | **Saver / investor** | Holds 21K/24K gold, bank CDs (شهادات), USD/SAR cash. | Net worth in one place; later: Zakah per asset. |
| P-04 | **iPhone user** | Same needs as P-01, frustrated that iOS apps can't read SMS. | Setup of Shortcuts/Apple Pay automations in minutes; screenshot OCR for InstaPay. |
| P-05 | **Privacy-sceptic** | Refuses apps that need bank login. | Proof nothing leaves the phone. |
| P-06 | **Egyptian with foreign accounts** (freelancer, expat, returning worker, student abroad) | Paid in USD/GBP/EUR via Wise or Revolut; may keep a Monzo/N26/bunq account from living abroad, or HDFC/Paytm from India; also has NBE/CIB at home. Several cards. | See spending per card and per currency without forced conversion; ignore cards they don't want tracked (e.g. a company card). |

Market: Egypt. Currencies: any ISO 4217 currency, tracked natively (D-28); featured: EGP, USD, SAR, EUR, AED, QAR, KWD, BHD.

## 5. User roles & permissions

### 5.1 Roles
Single local user per installation (D-04). No account is required (D-14).

| Role | How obtained | Capabilities |
|------|--------------|--------------|
| R-01 Free user | Install | All Free-tier features (§7 tier column). Identified to the backend only by a random anonymous install ID. |
| R-02 Gold subscriber | Valid monthly / yearly / lifetime purchase **verified by the backend** (FR-GOLD-02) | All Free features + Gold features on the platform where purchased. |
| R-03 Expired Gold user | Subscription lapsed, refunded or revoked | Reverts to Free limits; **data created with Gold features remains readable** (BR-GOLD-04). |
| R-04 Signed-in user (optional) | Signs in with Google or Apple (FR-ACCT) | Same as R-01/R-02, plus Gold follows the account across Android ↔ iOS — on one phone at a time, moved at most once per 30 days (D-52). Sign-in links **only the entitlement**; no financial data is attached to the account. |
| R-05 Zaghlol operator (internal) | Zaghlol staff | Manages catalog (merchants, categories, keywords), reviews contributed merchants, sets feature flags and prices source; views entitlement status for support. No access to any user financial data (none exists on the backend). Tooling is OQ-12. |

Feature flags (D-07, D-10) are controlled remotely by R-05 through the backend (FR-BE-05), with a safe default of OFF when the app has never reached the backend.

### 5.2 Entitlement matrix

| Capability | Free | Gold |
|------------|------|------|
| Automatic capture, all supported institutions | ✔ unlimited | ✔ unlimited |
| Custom SMS regex builder for unsupported senders | — | ✔ |
| 14 system categories, manual re-categorization | ✔ | ✔ |
| Save "always apply" merchant rules | ✔ (A-05) | ✔ |
| Custom categories & subcategories | — | ✔ unlimited |
| Voice cash entry | 15 / month | Unlimited |
| Manual cash entry | ✔ unlimited | ✔ unlimited |
| Charts | 4 core (A-06) | All 12 |
| Captain Zaghlol chart explanations | Basic tips | Deep coaching |
| Net worth: bank, wallet, cash balances | ✔ | ✔ |
| Net worth: gold, CDs, real estate, stocks, multi-currency | — | ✔ |
| CSV / Excel export | Preview only | ✔ |
| CSV import / restore | — | ✔ |
| Bank PDF statement import | — | ✔ |
| Encrypted Google Drive / iCloud backup | 1 backup slot, manual "Back up now" (D-33) | ✔ automatic schedule + last 5 versions |
| Ask Zaghlol chat + roast mode | ✔ (A-07) | ✔ |
| Share cards | ✔ | ✔ |
| Automatic merchant catalog updates | ✔ | ✔ |
| Per-card breakdown (filters + per-card category split) | ✔ | ✔ |
| Ignore capture per card / channel | ✔ | ✔ |
| Online & foreign banks capture (SMS / notifications / Apple Pay / OCR) | ✔ | ✔ |
| Online-bank statement import (CSV/PDF) | — | ✔ |
| Multi-currency tracking & per-currency reports | ✔ (A-55) | ✔ |
| Backup includes all settings & customizations | ✔ | ✔ |
| Gold on both Android and iOS | — | ✔ with optional sign-in |

### 5.3 Device permissions

| Permission | Platform | Requested when | Purpose | If denied |
|------------|----------|----------------|---------|-----------|
| READ_SMS, RECEIVE_SMS | Android | Onboarding capture step, after explanation | Historical scan + live capture | Fall back to notification listener + share/paste (FR-ING-A-05) |
| Notification access (NotificationListenerService) | Android | Capture setup | Read bank/wallet app push notifications | Capture limited to SMS/manual |
| POST_NOTIFICATIONS | Android 13+ / iOS | First alert-worthy event or onboarding | Budget alerts, reminders | No alerts; in-app banners only |
| Microphone + speech recognition | Both | First tap on mic | Voice cash entry | Manual entry only |
| Photos / screenshot access | iOS (and Android share) | First OCR use | Receipt / InstaPay screenshot OCR | Feature unavailable |
| Biometrics (Face ID / Touch ID / fingerprint) | Both | Onboarding toggle | App lock | PIN/device passcode fallback (A-08) |
| Google account (Drive appdata scope) | Both | First Drive backup | Backup | Backup unavailable |
| iCloud | iOS | First iCloud backup | Backup | Backup unavailable |
| Google / Apple sign-in | Both | Only when user chooses to link Gold across platforms | Cross-platform entitlement | Gold stays on the purchasing platform |
| Network | Both | Catalog sync, price refresh, flags, purchases, backup | See D-13 | App works fully offline with last-known catalog, prices and flags |

## 6. Scope overview

| Module | ID prefix | Launch state |
|--------|-----------|--------------|
| Onboarding, settings & privacy | ONB | On |
| Android capture | ING-A | On |
| iOS capture (5 channels) | ING-I | On (filter extension subject to feasibility, R-02) |
| Message parsing engine | PAR | On |
| Accounts & cards | ACC | On |
| Transactions | TXN | On |
| Categorization & merchant rules | CAT | On |
| Voice cash entry | VOI | On |
| Self-transfers, refunds & bill splits | XFR | On |
| Budget & payday cycle | BUD | On |
| Subscriptions & BNPL / installments | SUB | On |
| Home dashboard | HOME | On |
| Charts & explanations | CHT | On |
| Captain Zaghlol mascot & coaching | MAS | On |
| Ask Zaghlol chat & roast mode | CHAT | On |
| Wealth & net worth | WLT | On |
| Zakah calculator | ZAK | **Flag OFF** (D-07), switchable remotely |
| Smart ROI coach | ROI | **Flag OFF** (D-10), switchable remotely |
| Zaghlol Gold & purchases | GOLD | On |
| Optional account (sign-in) | ACCT | On |
| Per-card breakdown | CARD | On |
| Capture controls (ignore per card) | CAP | On |
| Multi-currency | CUR | On |
| Catalog sync | SYNC | On |
| Backend services (.NET + PostgreSQL) | BE | On |
| Export / import | EXP | On |
| Backup & restore | BAK | On |
| Social share cards | SHR | On |
| Notifications | NTF | On |
| Security & app lock | SEC | On |
| Localization | L10N | On |
| Home/lock-screen widgets | WID | On (Should) |

Canonical screen set: the spec's §13 16-screen set, with §5 content mapped onto it (A-09). The UX phase will reconcile numbering.

---

## 7. Functional requirements

### 7.1 Onboarding, settings & privacy (ONB)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
**Onboarding principle (D-21):** the user sees their own transactions as fast as possible; every question that isn't needed for that is skipped, defaulted, or asked later in context.

| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ONB-01 | First launch shows a single welcome + privacy screen: "your financial data stays on your phone, no bank password, no ads". | M | F | One screen, one primary button. Wording must stay true with the backend (no "no server" claim). |
| FR-ONB-02 | App works without any account or sign-in; sign-in is never part of onboarding. | M | F | No onboarding screen asks for email, phone, password or social sign-in. |
| FR-ONB-03 | Payday day, income target and language are **optional** during onboarding. Language defaults to device language; payday defaults to day 1 (calendar month) until set (A-43). | M | F | User can reach the home screen without entering any number. Values editable in Settings; payday input accepts 1–28 only (BR-BUD-01). |
| FR-ONB-04 | Biometric app lock is offered after the first transactions are visible (not before), as a one-tap toggle. | M | F | When enabled, requires biometric/passcode on cold start and after background timeout (A-10). |
| FR-ONB-05 | Capture setup in ≤ 3 taps per platform. Android: one explanation screen → system SMS permission → optional notification access. iOS: one-tap Shortcut install + setup checker. | M | F | Measured: ≤ 3 user actions from welcome to first permission granted; each permission has one plain-language reason line. |
| FR-ONB-06 | Android: historical SMS scan starts automatically right after permission, in the background, with live progress, and the home screen fills as transactions are found. | M | F | First parsed transactions visible within 10 s of permission grant on a reference device; scan depth per A-11; no duplicates. |
| FR-ONB-09 | **Time to first value**: a new Android user with bank SMS sees categorized transactions on the home screen in ≤ 60 s from first launch; iOS user sees a guided "log your first expense" (voice or manual) in ≤ 60 s. | M | F | Verified in usability test with 5 users per platform (target: 4 of 5 succeed unaided). |
| FR-ONB-10 | Contextual setup later: suggest payday when a salary-like credit is detected; suggest budgets after the first full cycle; suggest the free backup after 7 days of data (A-65). | S | F | Each suggestion appears once and can be dismissed permanently. |
| FR-ONB-11 | Every onboarding step except the welcome screen can be skipped and resumed from Settings → "Finish setup". | M | F | — |
| FR-ONB-12 | Restoring on a new phone is offered on the welcome screen ("I already use Zaghlol"). | M | F | Leads to FR-BAK-03 restore flow; works for Free and Gold backups. |
| FR-ONB-07 | Settings screen exposes: language, digits, payday, income target, app lock, capture sources, categories & rules, merchant contribution opt-in, notification preferences, backup, Gold & optional account, privacy info ("what Zaghlol's server knows about you"), data deletion. | M | F | All items reachable within 2 taps of Settings. |
| FR-ONB-08 | User can delete all data. **iOS exception (D-62):** the Secure Enclave **seat keys** are kept on the phone (so a later restore on the same iPhone can be recognised, D-55/D-63), and the server keeps its keyed hash for the purchase; the privacy notice and the "Delete everything" confirmation state this. | M | F | "Delete everything" with confirmation wipes DB, keys and cached files and asks the backend to delete the install record; app returns to first-launch state. *(v1.7: "keys" means all keys except, on iOS, the seat keys, D-62.)* **Given** an iPhone, **when** the user confirms "Delete everything", **then** all financial data, the DB key and caches are gone, the seat keys remain in the Keychain/Secure Enclave, and the confirmation copy says so. On Android nothing is kept. |

### 7.2 Android capture (ING-A)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ING-A-01 | Capture incoming SMS from supported financial senders in real time, including when the app is closed. | M | F | Given SMS permission, a supported bank SMS creates a transaction within 10 s of receipt with the app killed. |
| FR-ING-A-02 | Only messages from recognized financial senders are processed; all other SMS are ignored and never stored. | M | F | Personal SMS never appear in DB, logs or backups (Play spyware policy). |
| FR-ING-A-03 | Capture bank / wallet / InstaPay app push notifications via notification listener — a **primary** channel alongside SMS (competitors use both; see research note). | M | F | Given notification access, a supported app notification creates a transaction; same event received via SMS and notification is stored once (BR-ING-02). Only notifications from apps in the institution registry are read. |
| FR-ING-A-04 | Clipboard / share-to-Zaghlol: user shares or pastes an SMS text to parse. | M | F | Shared text is parsed and shown for confirmation before saving. |
| FR-ING-A-05 | Degraded mode when SMS permission is unavailable (denied by user or not granted by Play). | M | F | App states which capture methods are active and offers notification + share/paste + manual + voice. |
| FR-ING-A-06 | Unrecognized messages from known financial senders go to a review queue. | M | F | User can view raw text, enter fields manually, or dismiss. |
| FR-ING-A-07 | **Online & foreign banks** (D-27): capture Wise, Revolut, Payoneer, Monzo, bunq, N26 from their **app notifications** (they don't send SMS for payments — A-56); capture HDFC Bank, Paytm and GCC banks (Al Rajhi, Emirates NBD/Liv, and others in `institutions.md`) from **SMS and notifications**. | M | F | Each institution has notification/SMS templates with fixtures (FR-PAR-10). Amounts captured in their native currency (FR-CUR-01). |
| FR-ING-A-08 | All capture channels respect per-card ignore rules (FR-CAP) before anything is stored. | M | F | — |

### 7.3 iOS capture (ING-I)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ING-I-01 | Shortcuts **Message** automations ("Message Contains" an Arabic/English bank keyword, set to Run Immediately) pass the message text to Zaghlol via an App Intent. | M | F | With the provided automations installed, a bank SMS containing a configured keyword creates a transaction without opening the app. Keyword set covers ≥ 95% of reference-corpus messages. |
| FR-ING-I-02 | Shortcuts **Transaction** (Wallet) automation passes Amount, Merchant and Card to Zaghlol. | M | F | An Apple Pay payment creates a transaction; if the same payment also arrives by SMS it is stored once (BR-ING-02). Only Apple Pay payments are covered (not physical-card or online card use). |
| ~~FR-ING-I-03~~ | ~~Message filter extension~~ **Removed by D-39** (technically infeasible). | — | — | — |
| FR-ING-I-04 | Screenshot OCR: Back-Tap / share a screenshot (e.g. InstaPay receipt) → parsed transaction. | M | F | On-device OCR extracts amount, counterparty, reference; user confirms. Arabic and English receipts. |
| FR-ING-I-05 | Bank PDF statement import (also on Android). | M | G | See FR-EXP-04. |
| FR-ING-I-06 | One-tap install of the ready-made Shortcut package (all keyword Message automations + Wallet automation) with setup instructions. | M | F | User reaches a working automation in ≤ 3 steps (spec Screen 2). |
| FR-ING-I-07 | Setup checker: detects missing or inactive automations (e.g. no captures for 7 days while the user is active) and guides the user to fix them. | M | F | — |
| FR-ING-I-08 | **Online & foreign banks on iOS** (D-30): Apple Pay payments with Wise/Revolut/Monzo/bunq/N26/HDFC cards via the Wallet automation; HDFC/Paytm SMS via Message automations (if the SIM receives them); screenshot OCR of in-app transaction screens; statement import (FR-EXP-06). The app explains that iOS can't read these banks' notifications. | M | F | Setup screen for each online bank lists the channels that work on iOS. |

### 7.4 Message parsing engine (PAR)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-PAR-01 | Support every institution in `institutions.md` at its stated priority: the 53 spec formats (38 Egyptian banks, 6 InstaPay scenarios, 6 wallets/cards, 3 BNPL groups), plus added international, GCC and Egyptian fintech institutions (D-27, D-32), in Arabic and English. | M | F | Each format has ≥ 4 test fixtures (AR, EN, edge variants) passing. |
| FR-PAR-02 | Extract: institution, direction, amount, currency, card/account last-4, merchant or counterparty (name / IPA / phone), balance or available limit, reference no., transaction date/time. | M | F | Missing optional fields are null, not guessed. |
| FR-PAR-03 | Classify direction: expense, income, transfer-out, transfer-in, refund/reversal, declined. | M | F | Declined transactions are recorded as declined and excluded from spend (BR-TXN-03). |
| FR-PAR-04 | Normalize Arabic-Indic digits, Arabic decimal separator, tatweel and thousands separators before extraction. | M | F | `١٬٢٥٠٫٠٠` parses as 1250.00. |
| FR-PAR-05 | Clean merchant strings (strip POS terminal codes, city/country suffixes). | M | F | `CARREFOUR MAADI EG 041` → Carrefour. |
| FR-PAR-06 | Each parse returns a confidence and the matched template; low-confidence results go to review. | M | F | Threshold configurable in code (A-12). |
| FR-PAR-07 | Custom regex builder for unsupported senders. | S | G | User highlights amount/merchant in a sample message; Zaghlol generates and tests a template before saving. |
| FR-PAR-08 | Templates are versioned data bundled with the app; formats are updated with app releases, **not** from the backend (D-17). | M | — | Adding a bank needs only template + fixtures. |
| FR-PAR-09 | Parse a message in < 10 ms on a reference mid-range device. | M | — | See NFR-PERF-01. |
| FR-PAR-10 | **Online & foreign bank templates** (D-27) for Wise, Revolut, Monzo, bunq, N26, Paytm, HDFC Bank — English (and Hindi/English for HDFC/Paytm SMS where relevant, A-57). Covers card payments, transfers in/out, currency conversions within the app (e.g. Wise USD→EGP), top-ups, refunds, declines. | M | F | ≥ 4 fixtures per institution per event type from real samples (OQ-04). |
| FR-PAR-11 | Parse international amount formats: currency symbols and codes (`$ £ € ₹ ₺ ﷼`, `USD`, `GBP`…), symbol before or after the amount, `1,234.56` and `1.234,56` (EU) and Indian grouping `1,23,456.78`, and currencies with 0, 2 or 3 decimals. | M | F | Table-driven tests for each format. |
| FR-PAR-13 | **Generic parser** for financial messages from senders/apps not in the registry but identified as financial (e.g. sender or app name contains "bank", known financial keywords in AR/EN): heuristic extraction of amount, currency, direction, last-4, merchant. Output always goes to the review queue for confirmation; once confirmed, the user can choose "always capture this sender" (A-66). | M | F | On a test set of unseen bank formats, ≥ 80% have correct amount and currency in the review queue suggestion. |
| FR-PAR-14 | **"Request my bank"**: from the review queue or Settings, user can ask Zaghlol to support an institution. Sends only institution name, country and channel type (SMS/notification) — **never the message** (BR-SYNC-03). | S | F | Backend aggregates requests for operator prioritization (FR-BE-10). |
| FR-PAR-15 | Payoneer, Emirates NBD/Liv and Al Rajhi templates at launch (D-32): card payments, transfers in/out, currency conversions, refunds, declines; Al Rajhi and Emirates NBD in Arabic and English. | M | F | ≥ 4 fixtures per event type from real samples (OQ-18). |
| FR-PAR-12 | Currency conversion events (e.g. "You converted 500 USD to 24,600 EGP" in Wise/Revolut) are recorded as an internal transfer between two same-institution balances in different currencies, not as spend. | M | F | Spend totals unchanged by a conversion. |

### 7.5 Accounts & cards (ACC)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ACC-01 | Auto-create an account/card the first time an institution + last-4 is seen. | M | F | Types: Debit, Credit, Account, Wallet, BNPL, Cash, **Multi-currency account** (Wise/Revolut-style, holding several currency balances). User can rename and set type. |
| FR-ACC-06 | A multi-currency account keeps a separate balance per currency (e.g. Wise: USD 1,200.00, EUR 300.00, EGP 5,000.00). | M | F | Balances never summed across currencies except in the optional ≈EGP view. |
| FR-ACC-02 | Track current balance from the latest message's balance field; credit cards track available limit. | M | F | Balance shown with "as of" timestamp. |
| FR-ACC-03 | A default Cash account exists for manual and voice entries. | M | F | — |
| FR-ACC-04 | User can merge duplicate accounts and hide accounts. | S | F | Merging re-links transactions. |
| FR-ACC-05 | Credit cards: user can set statement due day and credit limit. | S | F | Used by SUB reminders and chart 10 utilisation. |

### 7.6 Transactions (TXN)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-TXN-01 | Transaction list with filters (date range, account, category, type) and full-text search (merchant, note, amount). | M | F | Search returns results in < 200 ms on 50k transactions. |
| FR-TXN-02 | Manual add / edit / delete of any transaction. | M | F | Edited auto-captured transactions are marked user-verified. |
| FR-TXN-03 | Record source of every transaction (SMS, notification, shortcut, Apple Pay, OCR, PDF, CSV, voice, manual). | M | F | Visible in transaction details. |
| FR-TXN-04 | Every transaction is stored in its **original currency** (any ISO 4217 code, D-28); no EGP amount is stored as the transaction's value. If a message states both a foreign amount and the billed amount (e.g. "USD 20.00 charged EGP 1,010.00" on an Egyptian card), both are kept: the billed amount in the card's currency counts for that card. | M | F | KWD 1.250, BHD 0.375, JPY 1500 stored and shown with the correct decimals (BR-MON-03). |
| FR-TXN-05 | Attach a note to a transaction. | C | F | — |
| FR-TXN-06 | **Bulk edit** (D-36): select several transactions (Select button or long-press) and in one action change category, change card/account, or delete. | M | F | Selecting 10 transactions and changing their category updates all 10 and every total; one **Undo** restores all of them; a bulk delete asks for confirmation first. Optional "always use this category for these merchants" creates rules (FR-CAT). |

### 7.7 Categorization & merchant rules (CAT)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-CAT-01 | Ship the 14 system categories with subcategories, budget bucket and colour from spec §4. | M | F | Names in AR and EN exactly as spec. |
| FR-CAT-02 | Ship 600+ seeded Egyptian merchant mappings **bundled in the app** (works on first launch offline) and kept current through catalog sync (FR-SYNC). | M | F | Spec lists ~150 examples; the full 600+ list must be compiled (OQ-05). |
| FR-CAT-03 | Categorize using precedence: user rule → seeded map → keyword heuristics → "needs classification" (BR-CAT-01). | M | F | — |
| FR-CAT-04 | "Needs classification" queue with one-tap category chips (swipe). | M | F | Spec Screen 5. |
| FR-CAT-05 | After a manual re-categorization, ask "always apply for this merchant/counterparty?" and save a rule if yes. | M | F | Rule applies to future and, optionally, past transactions (A-13). |
| FR-CAT-06 | Fuzzy merchant matching (handles spelling variants and Arabic/English names). | M | F | `ELEZABY`, `EL EZABY`, `صيدليات العزبي` → El Ezaby. |
| FR-CAT-07 | Create, edit, delete custom categories and subcategories. | M | G | Deleting a category requires choosing a replacement for its transactions. |
| FR-CAT-08 | Manage saved rules (list, edit, delete). User rules are stored only in the local encrypted DB and are never uploaded. | M | F | — |
| FR-CAT-09 | **Opt-in anonymous merchant contribution** (D-16): Settings toggle, off by default, explained in one sentence. When on, unknown merchant names the user categorizes are sent to the backend per BR-SYNC-04. | S | F | Payload contains only normalized merchant string, institution code, and chosen system category; inspected in tests to contain no amount, date, card, account, phone, IPA or person name. |

### 7.8 Voice cash entry (VOI)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-VOI-01 | Record a spoken phrase in Egyptian Arabic or English and convert to text on device. | M | F/G | Works offline where the device supports on-device ar-EG recognition (R-05). |
| FR-VOI-02 | Split one phrase into multiple transactions with amounts and categories. | M | F/G | "دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي" → 3 items: 150 Groceries, 45 Dining, 30 Transport. |
| FR-VOI-03 | Show parsed items for confirmation/edit before saving. | M | F/G | Nothing saved without confirmation. |
| FR-VOI-04 | Free users: 15 voice logs per month; Gold unlimited. | M | F/G | A "log" = one confirmed recording, regardless of item count (A-14). Counter resets on calendar month (A-15). |
| FR-VOI-05 | Understand spoken Egyptian number forms ("ميت وخمسين", "ربع", "نص"). | S | F/G | Covered by test phrase list to be built in Phase 3. |

### 7.9 Self-transfers, refunds & bill splits (XFR)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-XFR-01 | Auto-pair an outgoing and incoming transfer between the user's own accounts (BR-XFR-01) and mark both internal. | M | F | Spec example: −1,000 NBE *4567 and +1,000 CIB *1234 within 2 min → 0 EGP spend. |
| FR-XFR-02 | User can manually link / unlink transfers. | M | F | — |
| FR-XFR-03 | Refunds offset the original expense where matched (BR-XFR-03). | M | F | — |
| FR-XFR-04 | Bill split: user marks an expense as shared, adds participants and shares, and links incoming repayments. | M | F | Spec example: paid 1,200, received 800 → net personal spend 400. |
| FR-XFR-05 | Track unsettled split amounts per person. | S | F | — |
| FR-XFR-06 | **Assign an incoming transfer as a reimbursement** (D-20): from any incoming InstaPay / wallet / bank transfer or manual cash-in, user picks "This is money back for…" and selects an expense. | M | F | After assigning +400 to a 1,200 restaurant expense, the expense's net spend shows 800 and the incoming transfer is excluded from income (BR-XFR-05). |
| FR-XFR-07 | Multiple incoming transfers can reimburse one expense; one incoming transfer can be split across several expenses. | M | F | 1,200 bill + 400 from Ahmed + 400 from Karim → net 400. |
| FR-XFR-08 | Suggest reimbursements: when an incoming person-to-person transfer arrives within 7 days (A-45) after an expense in Dining / Entertainment / Travel (or one already marked shared) and is ≤ the remaining amount, show a one-tap "Is this from the [merchant] bill?" prompt. | S | F | Suggestion never auto-applies without a tap. |
| FR-XFR-09 | Reimbursements can be unassigned; the incoming transfer then returns to normal income classification. | M | F | — |

### 7.10 Budget & payday cycle (BUD)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-BUD-01 | Budget cycle runs from payday to the day before next payday (BR-BUD-01). | M | F | Payday 25 → cycle 25 Oct – 24 Nov. |
| FR-BUD-02 | Monthly limit per category; overall budget = sum of limits or user-set total (A-16). Each budget is set **in one currency** and counts only transactions in that currency (D-28). | M | F | An EGP Dining budget ignores a GBP restaurant payment; the user can create a separate GBP Dining budget. |
| FR-BUD-03 | Alerts at configurable thresholds (default 80% and 100%). | M | F | One alert per threshold per category per cycle. |
| FR-BUD-04 | "Safe to spend per day" figure (BR-BUD-03). | M | F | Spec: 2,200 left, 7 days → 314/day. |
| FR-BUD-05 | Optional rollover of unused budget to next cycle. | C | F | — |
| FR-BUD-06 | Annual budgets (e.g. school fees). | C | F | Spec field `is_annual`. |

### 7.11 Subscriptions & BNPL / installments (SUB)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-SUB-01 | Detect recurring subscriptions from transaction history (BR-SUB-01). | M | F | User confirms or dismisses detected subscriptions. |
| FR-SUB-02 | Show monthly cost and ×12 annual cost per subscription and total. | M | F | — |
| FR-SUB-03 | Track installments (valU, Sympl, Souhoola, etc.), credit card due payments and gameya: amount, due day, paid/remaining count. | M | F | Spec Screen 10. Gameya entered manually (A-17). |
| FR-SUB-04 | Reminder 3 days before each due date (configurable). | M | F | — |
| FR-SUB-05 | Mark an installment paid automatically when a matching payment is captured. | S | F | — |

### 7.12 Home dashboard (HOME)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-HOME-01 | Show liquid balance, days to payday, cycle income, cycle spend, safe daily spend — **per currency** (primary currency first, other currencies as swipeable cards); optional ≈EGP total when enabled (FR-CUR-04). | M | F | Excludes internal transfers. A user with only EGP sees no currency UI at all. |
| FR-HOME-05 | Card filter on the home screen (FR-CARD-01). | M | F | — |
| FR-HOME-02 | Mascot banner with contextual message (MAS rules). | M | F | — |
| FR-HOME-03 | Feed of recent captured transactions with account, category, amount; internal transfers labelled "excluded". | M | F | — |
| FR-HOME-04 | Quick-add button (centre FAB) for voice / manual / asset entry. | M | F | — |

### 7.13 Charts & explanations (CHT)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-CHT-01 | 12 charts as in spec §7: 1 Cash flow, 2 Category donut, 3 Payday burn-rate curve, 4 50/30/20 balance, 5 Day-of-week (and hour) pattern, 6 Top merchants, 7 Month vs 3-month average, 8 6-month installment timeline, 9 Subscriptions ×12, 10 Cards & wallets split, 11 Net worth growth, 12 Personal inflation tracker. | M | F/G | Each chart has empty state and works RTL/LTR. |
| FR-CHT-02 | Free users get 4 core charts: Cash flow (1), Category donut (2), Top merchants (6, top 5), Budget progress bars (A-06). Others show a Gold-locked preview. | M | F/G | — |
| FR-CHT-03 | "Explain this chart" (اشرحلي يا زغلول): a dynamic Egyptian Arabic / English explanation and one actionable tip computed from the user's data. | M | F/G | Text is generated from templates with real values; Free = basic tip, Gold = deep coaching (definition in Phase 2, OQ-07). |
| FR-CHT-04 | Charts filter by cycle / month / custom range. | S | F | — |
| FR-CHT-05 | Every chart filters by **card/account** (FR-CARD-01) and by **currency**; a chart never mixes currencies unless the ≈EGP view is on, in which case it is labelled "approximate". | M | F | — |
| FR-CHT-06 | Chart 10 (Cards & wallets) shows spend per card **per currency** and lets the user tap a card to open its breakdown (FR-CARD-02). | M | F/G | — |

### 7.14 Captain Zaghlol mascot & coaching (MAS)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-MAS-01 | Animated mascot with states: Tour guide, Proud coach, Shocked, Detective, Chart professor, Voice listener (+ ROI and Zakah states when flags on). | M | F | Triggers per BR-MAS-*. |
| FR-MAS-02 | Mascot speech in Egyptian colloquial Arabic (AR locale) or friendly English (EN locale). | M | F | All lines from approved copy deck (Phase 2). |
| FR-MAS-03 | User can reduce mascot animation (respects OS reduce-motion). | M | F | — |

### 7.15 Ask Zaghlol chat & roast mode (CHAT)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-CHAT-01 | Answer typed questions in Arabic (incl. colloquial) and English using an offline rules/templates engine (D-06). | M | F | Supported intents (minimum): spend on category/merchant over period; compare periods; top merchants; balance of account; remaining budget; upcoming dues; biggest expense; savings this month; **spend on a specific card** ("صرفت كام بكارت CIB الشهر ده؟"). Answers give one figure per currency. |
| FR-CHAT-02 | Answers can include a small inline chart. | M | F | — |
| FR-CHAT-03 | Unsupported questions get a helpful fallback with example questions. | M | F | Never fabricates numbers. |
| FR-CHAT-04 | Roast mode ("إقصف جبهتي يا زغلول"): humorous critique of spending. | S | F | Humour rules: no insults about the person, religion, body, family; only about spending (A-18). |
| FR-CHAT-05 | Suggested-question chips. | S | F | — |

### 7.16 Wealth & net worth (WLT)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-WLT-01 | Net worth = liquid accounts + assets − liabilities (BR-WLT-01), **shown per currency / unit** (e.g. EGP 54,000 · USD 1,200 · GBP 300 · Gold 24K 5 g · Gold 21K 24 g); the single combined figure appears only in the optional ≈EGP view (D-29). | M | F/G | Free: accounts/wallets/cash only. |
| FR-WLT-02 | Track gold by karat (24K, 21K, 18K) in grams and gold coins; bank certificates (principal, rate, payout frequency, maturity, currency); cash and balances in **any ISO currency**; stocks/funds (in their trading currency); real estate; car (A-19). | M | G | Each asset stored in its native unit/currency. |
| FR-WLT-03 | Get current gold (per karat, per gram, in EGP and USD — A-58) and FX rates for all supported currencies from the Zaghlol backend (FR-BE-04); manual override; last-known price used offline with its date (D-05). Prices are used only to value gold and for the optional ≈EGP view. | M | G | Request carries no holdings or user data (NFR-PRIV-03). Prices older than 24 h are labelled stale. |
| FR-WLT-04 | Upcoming CD payout dates and amounts. | S | G | Spec: "+3,375 EGP on day 28". |
| FR-WLT-05 | Net worth history (chart 11) from monthly snapshots. | M | G | Snapshot taken at least monthly (A-20). |

### 7.17 Zakah calculator (ZAK) — **feature flag OFF at launch** (D-07)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ZAK-01 | Per-asset hawl tracking from acquisition date (Hijri). | M | G | — |
| FR-ZAK-02 | Nisab check on combined zakatable wealth net of short-term due debts (BR-ZAK-*). | M | G | — |
| FR-ZAK-03 | Output Zakah per asset in its native unit plus its EGP cost, without forced conversion. | M | G | Spec §11 table reproduced as test cases. |
| FR-ZAK-04 | Track Zakah payment status per item (pending / partial / paid). | S | G | — |
| FR-ZAK-05 | Prominent disclaimer: estimate only, consult a scholar. | M | G | — |
| FR-ZAK-06 | Hidden unless the remote feature flag is on (FR-BE-05); the user cannot enable it. Default OFF if flags have never been fetched. | M | — | Turning the flag on at the backend shows the feature within one sync, no app update. |

### 7.18 Smart ROI coach (ROI) — **feature flag OFF at launch** (D-10)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ROI-01 | Evaluate the 8 rules in spec §12 against the user's spending and show qualifying suggestions with 1- and 2-year projections. | M | G (A-21) | Spec numbers become test cases. |
| FR-ROI-02 | "Not financial advice" disclaimer on every suggestion. | M | — | — |
| FR-ROI-03 | Share a projection card. | C | F | — |
| FR-ROI-04 | Hidden unless the remote feature flag is on (same mechanism as FR-ZAK-06). | M | — | — |
| FR-ROI-05 | **General advice only at first** (D-38): suggestions name kinds of products (savings certificate, gold, money-market fund) and use clearly labelled example rates; no bank, fund or brand names. Named products are a later option behind a separate flag. | M | — | No suggestion text contains an institution or product name. |

### 7.19 Zaghlol Gold & purchases (GOLD)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-GOLD-01 | Paywall showing monthly, yearly and lifetime plans with store-localized prices. | M | — | Prices from store (final TBD, D-12). |
| FR-GOLD-02 | Purchase via Google Play Billing and StoreKit 2; **every purchase is verified by the backend** (FR-BE-02) before Gold is granted; Android purchases are acknowledged by the backend. | M | — | A forged or replayed purchase token is rejected; a pending purchase does not grant Gold (BR-GOLD-05). "Replayed" includes a genuine token presented from an install that is not entitled to it under FR-GOLD-08 (one-seat/30-day move rule or account rule, D-52) or without valid device attestation where FR-GOLD-09 requires it — such a request grants nothing. |
| FR-GOLD-03 | Restore purchases (store restore → backend re-verification), subject to the anti-sharing rules (FR-GOLD-08) and device attestation (FR-GOLD-09) (D-46, D-52). **Same-phone recognition (D-55, D-62, D-63, D-65):** on iOS a restore after an app reinstall or "Delete everything" on the same iPhone is recognised through the seat keys (`seatKeys[]`: current install's Secure Enclave key + up to 4 earlier installs' keys, each as public key + signature, D-62) ~~through the Keychain-derived install proof~~ and is not a move, **up to the D-63 cap: at most 2 free recognitions per purchase per rolling 30 days; a 3rd or later recognition inside that window counts as the monthly move**. **Over-cap on the holder (D-65a):** if that iPhone currently holds the seat, an over-cap restore is **never refused** — Gold stays and the 30-day move window restarts from that restore, even if this month's move is already used; on an iPhone that does not hold the seat, the normal move rules apply (FR-GOLD-08 b/c). **Accepted residual (D-66, narrows D-65a):** iOS sign-in carries no App Attest, so a seat key registered by sign-in is not trusted; when the Gold was bought on Android (Google Play) or under a different Apple ID, the holding iPhone has no App Store transaction to restore with, and an over-cap reinstall followed by sign-in is an ordinary move under the 30-day rule — it **can be refused for up to 30 days** (until the next-move date). The app then shows the next-move date and the support path instead of Restore; support can move the seat (unfreeze first if a dispute freeze is running). The "never refused" rule holds whenever the owner can restore with an App Store purchase on that iPhone. On Android a reinstall or "Delete everything" is a new install and a restore there spends the monthly move. | M | — | **iOS residual (D-66) — given** Gold bought on Google Play on an Android phone and moved to this iPhone by sign-in on 2026-11-01 (next move from 2026-12-01), with free same-iPhone reinstall recognitions on 2026-11-06 and 2026-11-10, and no App Store transaction for the purchase on this iPhone, **when** the user reinstalls again on 2026-11-20 and signs in, **then** Gold is refused on this iPhone, the app shows the next-move date (2026-12-01) and the support path, and does **not** offer Restore; **when** a `support_agent` then moves the seat to this iPhone after the ownership check, **then** Gold returns. **Given** the same case but the Gold was bought with an App Store purchase under this iPhone's Apple ID, **then** the app offers Restore and the restore follows D-65a (never refused). Restore on the **same phone with the same install** always works and is never counted as a move. **iOS — given** Gold held by an iPhone, **when** the app is deleted and reinstalled (or "Delete everything" is used) on that same iPhone and the user taps Restore, **then** Gold returns and **no move is counted** (D-55), provided fewer than 2 free recognitions were used for that purchase in the last 30 days (D-63). **iOS cap — given** a purchase held by an iPhone whose same-iPhone reinstall restores were recognised on 2026-11-06 and 2026-11-10, **when** the user reinstalls and restores again on 2026-11-20, **then** this restore counts as the monthly move: Gold returns on that iPhone and the next move is possible from 2026-12-20 (D-63). **iOS cap, move already used (D-65a) — given** Gold moved to this iPhone on 2026-11-01 (next move from 2026-12-01) and its reinstall restores were recognised free on 2026-11-06 and 2026-11-10, **when** the user reinstalls and restores again on 2026-11-20, **then** the restore is **not refused**: Gold stays on this iPhone and the next move is possible from 2026-12-20 (window restarted, not 2026-12-01). **iOS cap, not the holder — given** Gold moved away from this iPhone to phone B on 2026-11-15, **when** an over-cap reinstall restore happens on this iPhone on 2026-11-20, **then** it follows the normal move rules: refused with next-move date 2026-12-15 and a support link. **When** instead the third reinstall happens on 2026-12-07, **then** only the 2026-11-10 recognition is still inside the rolling 30 days, so it is free and no move is counted. **iOS seat keys — given** any iOS restore or sign-in, **then** the request carries `seatKeys[]` with at most 5 entries (current + up to 4 earlier), each `{publicKey, signature}`, and no other device data (BR-SYNC-03); an iOS **purchase verify** carries only element 0, the install's own key (v1.8, R5-9). **Android — given** Gold held by an Android phone, **when** the user starts "Delete everything", **then** before deleting the app warns, in Egyptian colloquial copy, that restoring Gold afterwards counts as this month's move; after a reinstall or "Delete everything", a restore is treated as a new install: allowed and counted as the move if no move happened in the last 30 days, otherwise refused with the next-move date. Restore on a **new phone** without sign-in for the same store account works if the purchase is not account-linked to a different account and no move has happened in the last 30 days (FR-GOLD-08); it then counts as the move and the old phone loses Gold. Inside the 30 days it is refused with the next-move date and a support link. *(Superseded v1.5 wording: "Restore on the same phone always works" — on Android this now holds only while the install is unchanged, D-55.)* |
| FR-GOLD-04 | Entitlement works offline: the app caches a backend-signed entitlement and honours it until its expiry + grace period (BR-GOLD-03). | M | — | Airplane mode for 5 days does not lose Gold. |
| FR-GOLD-05 | Locked features show a preview and a non-intrusive upgrade prompt (D-08). | M | — | Max one unsolicited paywall per week (A-22). |
| FR-GOLD-06 | Renewals, cancellations, refunds and revocations reported by the stores update the entitlement (via store server notifications, FR-BE-03) and reach the app on next contact. | M | — | A refunded purchase removes Gold at next app open after grace. |
| FR-GOLD-07 | Cross-platform Gold: a signed-in user (R-04) who bought Gold on one platform gets Gold on the other after signing in there. | M | — | Buy on Android, sign in on iPhone with same account, no move in the last 30 days → Gold active on the iPhone, and the Android phone loses Gold (one install at a time, D-52). Moving between platforms counts as the one move per rolling 30 days; a second cross-platform move inside 30 days is refused with the next-move date and a support link. The purchase must first have been linked from the buying phone (D-54, FR-ACCT-05). **Given** Gold moved Android → iPhone on 2026-11-06 and the Android phone stays offline, **then** the Android phone loses Gold no later than 2026-11-13 (7 days, D-60). **Given** the user upgrades monthly → yearly on the Android phone while the iPhone holds Gold and no move has happened in the last 30 days, **then** the payment completes, Gold moves to the Android phone and the move is counted (D-59). |
| FR-GOLD-08 | **Anti-sharing (D-46, D-52).** (a) Gold from one purchase is held by **exactly one install at a time**, across Android and iOS (D-52; replaces D-46's 3-install limit). (b) The owner can **move** Gold to a different phone **once per rolling 30 days**; a cross-platform move counts as that move; a restore on the same phone is never a move. (c) Inside the 30 days, a restore or sign-in on a different phone is **refused**: no Gold, the app shows the date from which the next move is possible (locale-formatted) and a link to support; support can perform an **audited manual move** (FR-BE-08) after the ownership check (D-57); a support move **restarts the 30-day window** (D-56). (d) The phone Gold moved away from loses Gold at its next online entitlement refresh, or within **7 days** if it stays offline (3-day token + 4-day grace, D-60) *(superseded v1.5 text: "within the entitlement token lifetime (≤ 14 days)")*. (e) A purchase **linked to an account** (FR-ACCT-02) moves only between installs **signed in to that account**. (f) **Same phone (D-55, D-62, D-63):** an iOS reinstall / "Delete everything" on the same iPhone, recognised through the seat keys (D-62), is not a move **up to the D-63 cap** — at most 2 free recognitions per purchase per rolling 30 days; beyond that the reinstall restore or sign-in **counts as the monthly move**; **on the iPhone that holds the seat it is never refused (D-65a): Gold stays and the 30-day window restarts, even if this month's move is already used** — *narrowed by D-66:* this holds whenever the owner can restore with an App Store purchase on that iPhone; when the Gold was bought on Android (Google Play) or under a different Apple ID and the iPhone can only sign in (sign-in carries no App Attest, so its seat key is not trusted), an over-cap reinstall is an ordinary move under (b)/(c) and **can be refused for up to 30 days**, with the next-move date and the support path shown (accepted residual); on an iPhone that does not hold the seat the normal rules (b)/(c) apply; on Android it is a new install. **Dispute freeze (D-64, D-65b):** a support dispute freeze on the purchase blocks only support moves and links; it does not change these self-service rules. (g) **Plan change (D-59):** an upgrade or downgrade made from a phone other than the current holder moves Gold to that phone and counts as the monthly move; the store payment is never blocked by the app or backend. If this month's move is already used, the payment completes but Gold **stays on the current holder** and the paying phone shows the next-move date (D-61a). (h) **Free reclaim (D-58, D-61b):** the first account link from the buying phone pulls back a seat held outside that account even inside a running cooldown — at most once per purchase, even across account deletion and re-creation; the reclaim **counts as the month's move and restarts the 30-day window**. (j) **Sign-out (D-61c):** signing out on the holder of an account-linked purchase pauses Gold there until sign-in to the owning account; the seat stays reserved and no move is spent (FR-ACCT-03). (i) **Trusted time (D-60):** expiry and grace are evaluated against trusted time; a detected clock rollback withholds Gold until the app reconnects (NFR-SEC-08). Technical design: ADR-012 Amendment, to be revised for D-52, D-55…D-61 and D-62…D-66. | M | — | **Given** an iPhone holding Gold that has already had 2 free same-iPhone reinstall recognitions for this purchase in the last 30 days, **when** it is reinstalled again and the user signs in or restores, **then** the backend treats it as the monthly move (D-63) and the next-move date is updated accordingly; **if this month's move is already used** (e.g. Gold moved to that iPhone on 2026-11-01 and the over-cap reinstall is on 2026-11-20) **and the user restores with an App Store purchase on that iPhone**, **then** Gold is still granted on that iPhone and the next move is possible from 2026-12-20 (D-65a). **Given** the same dates but the Gold was bought on Google Play (or under a different Apple ID), so the iPhone can only sign in, **then** Gold is refused on that iPhone until 2026-12-01 and the app shows that date and the support path, not Restore (D-66); a support move after the ownership check returns Gold earlier — if a dispute freeze is running, a support lead unfreezes first and a **different** operator makes the move (FR-BE-08). **Given** a support link correction (detach and re-link, no seat moved) on the purchase on 2026-11-10 (dispute freeze until 2026-12-10) and no move in the last 30 days, **when** the user, signed in to the owning account, restores on a different phone on 2026-11-20, **then** the self-service move succeeds under rule (b) — the freeze does not block it (D-65b). **Given** a yearly Gold purchase held by phone A, **when** phone B restores it and no move has happened in the last 30 days, **then** B gets Gold, the move is recorded, and **at no moment does the server hold more than one live Gold seat for that purchase**. **Given** Gold moved A → B on 2026-11-06 and phone A then stays in airplane mode, **then** A loses Gold no later than 2026-11-13 (7 days after the move, D-60); if A comes online earlier, it loses Gold at that refresh. *(Superseded v1.5 criterion: "no later than 14 days after the move".)* The current holder B still keeps Gold through at least 5 offline days (FR-GOLD-04). **Given** Gold moved A → B on 2026-11-06, **when** phone C (or A again) tries to restore or sign in on 2026-11-20, **then** no Gold is granted and the user sees, in Egyptian colloquial copy, that the next move is possible from 2026-12-06 (٦ ديسمبر ٢٠٢٦ in Arabic-Indic digits when that setting is on), with a "contact support" link. **Given** the same purchase restored again on phone B after a sign-out/sign-in, **then** Gold stays and no move is counted. **Given** a purchase linked to account A, **when** an install that is signed out, or signed in to account B, presents its token, **then** no Gold is granted and the user is told to sign in with the account that owns it (no account details revealed). **Given** a support operator moves Gold to phone C inside the 30 days, **then** an audit row records operator, purchase and time, and only C holds Gold. **Given** that support move happens on 2026-11-15, **then** the next move (self-service) is possible from 2026-12-15, not from the earlier window's end (D-56); and phone B, at its next online refresh, shows that Gold was moved by support, with the support contact (D-57f). **Given** phone B holds Gold and the user upgrades monthly → yearly on phone A on 2026-11-10 with no move in the last 30 days, **then** the store payment is not blocked, Gold moves to A, the move is counted and the next move is possible from 2026-12-10 (D-59). **Given** Gold moved A → B on 2026-11-06 and the user upgrades monthly → yearly on phone A on 2026-11-20, **then** the payment completes, Gold **stays on B**, and A shows that the next move is possible from 2026-12-06 (D-61a). **Given** the buying phone A was never linked, phone B holds Gold through a store-account restore, and the user signs in on A for the first time, **then** the purchase is linked and Gold returns to A immediately, even inside the 30-day cooldown; the reclaim counts as the move, so if it happens on 2026-11-12 the next move is possible from 2026-12-12 (D-61b); **given** the user later deletes the account, signs in again (same or new account) and links from A, **then** no second free reclaim happens and the normal 30-day rule applies (D-58). **Given** the device clock is set back (e.g. from 2026-11-20 to 2026-11-01) while offline, **then** Gold is withheld and the app shows "connect to check Gold" copy until a successful online refresh (D-60). |
| FR-GOLD-09 | **Device attestation on restore (D-45, D-46, D-53).** A restore request carries a Play Integrity token (Android) or App Attest assertion (iOS); the backend verifies it before granting Gold. Whether purchase *verification* also requires it is decided in ADR-012 Amendment (2026-11-05). The attestation carries no other device data (BR-SYNC-03). **Platform difference (D-53):** a Play Integrity verdict carries a timestamp and can expire; an App Attest assertion has no expiry and no server challenge — it is bound to a per-install attested key and a counter. | M | — | **Android — given** a restore whose Play Integrity token is missing, fails verification, has a failing verdict, is **expired** (timestamp outside the accepted window) or was already used, **then** no Gold is granted and the app shows a retry/help message. **iOS — given** a restore whose App Attest assertion is missing, comes from a key the backend has no valid attestation for, has an invalid signature, or whose **counter is not greater** than the last one seen for that key (replay), **then** no Gold is granted and the app shows a retry/help message. **Given** a valid attestation and a valid token within the FR-GOLD-08 rules (one seat, 30-day move), **then** Gold is granted. No device identifier (IMEI, advertising ID, serial, phone number) is stored by the backend from the attestation. |

### 7.20 Export / import (EXP)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-EXP-01 | Export transactions to CSV (UTF-8 with BOM) and Excel (.xlsx) with date-range and category filters. | M | G | Arabic text opens correctly in Excel on Windows. |
| FR-EXP-02 | Free users see an export preview table only. | M | F | — |
| FR-EXP-03 | Import / restore transactions from Zaghlol CSV with duplicate detection. | M | G | Column mapping for non-Zaghlol CSV is OQ-08. |
| FR-EXP-04 | Import bank PDF statements from CIB, NBE, QNB, Banque Misr, parsed on device. | M | G | Requires real sample statements (OQ-04). |
| FR-EXP-05 | Warn that exported files are not encrypted. | M | G | — |
| FR-EXP-06 | **Import statements from online banks** (D-27): Wise, Revolut, Monzo, bunq, N26 CSV exports (and PDF where CSV isn't offered), via share sheet or file picker; multi-currency rows kept in their currency; duplicates with already-captured notifications removed (BR-ING-02). | M | G | Requires real sample statements (OQ-04). |
| FR-EXP-07 | Exports include currency code per row and optional card filter; never convert amounts. | M | G | — |

### 7.21 Backup & restore (BAK)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-BAK-01 | Encrypted full backup (`.zaghlol.enc`, AES-256-GCM) to Google Drive app-data folder (D-11) or iCloud. | M | F/G | File unreadable without the user's backup passphrase/key (A-23). |
| FR-BAK-02 | Automatic backup schedule (daily / weekly / monthly). | M | G | — |
| FR-BAK-03 | Restore on a new or reset device, including cross-platform (Android ↔ iOS via Drive) (A-24). | M | F/G | Restored data identical to source. |
| FR-BAK-04 | Show last backup time and status. | M | F/G | — |
| FR-BAK-05 | Keep the last N backups (A-25). | S | G | Free keeps exactly one (FR-BAK-08). |
| FR-BAK-06 | **Backup contents** (D-19): all transactions (incl. raw message text, A-46), accounts & cards, budgets, subscriptions & installments, splits & reimbursements, wealth assets & price overrides, Zakah ledger, **all user preferences and settings** (language, digits, payday, income target, theme, notification types & quiet hours, app-lock settings, capture-source settings, hide-amounts choices, contribution opt-in), **custom categories & subcategories, merchant rules, custom SMS templates, review-queue state, per-card ignore rules, card labels, primary currency and ≈EGP setting**, and voice-log counter for the current month. | M | G | Restore on a different phone (same or other platform) reproduces every listed item; a checklist test compares source and restored device. |
| FR-BAK-07 | Backup **excludes**: the database encryption key (new device generates its own), store entitlements (restored from store/backend), the downloaded merchant catalog (re-synced), and device-specific permissions/Shortcut installs (re-done via setup checker after restore). | M | G | After restore the app prompts once to re-grant capture permissions. |
| FR-BAK-08 | **Free backup (D-33)**: Free users get **one** encrypted backup slot on Google Drive or iCloud with the same contents as Gold (FR-BAK-06). "Back up now" replaces the previous free backup. No automatic schedule; a reminder is shown when the free backup is older than 30 days (A-67). | M | F | Free user backs up on phone A, installs on phone B, restores → identical data and settings. Backing up again replaces the old file (only one exists). |
| FR-BAK-09 | Upgrading to Gold keeps the existing free backup as the first version of the Gold history; downgrading keeps only the newest backup. | M | F/G | — |

### 7.22 Social share cards (SHR)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-SHR-01 | Generate shareable achievement images (e.g. savings %, delivery cut) from templates. | M | F | PNG via system share sheet. |
| FR-SHR-02 | "Hide amounts" option, on by default (A-26). | M | F | Hidden mode shows percentages only. |
| FR-SHR-03 | Card includes Zaghlol branding and hashtag. | M | F | — |

### 7.23 Notifications (NTF)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-NTF-01 | Local notifications for: budget thresholds, spending spikes, upcoming dues, detected duplicate charge, detected subscription renewal, backup failure, weekly summary. | M | F | Each type can be switched off. |
| FR-NTF-02 | Quiet hours (default 23:00–08:00) (A-27). | S | F | — |
| FR-NTF-03 | Notification content hides amounts on lock screen when the user chooses. | S | F | — |

### 7.24 Security & app lock (SEC)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-SEC-01 | Local database encrypted (SQLCipher, AES-256) from the first write. | M | — | Copying the DB file off a device (e.g. via adb backup / file manager on a rooted device) yields unreadable data without the key. |
| FR-SEC-02 | App lock with biometrics/passcode; app content hidden in OS app switcher. | M | F | — |
| FR-SEC-03 | **All locally stored data is encrypted** (D-18): database, preferences/settings, cached catalog, entitlement cache, queued contributions, generated images awaiting share, and temp files. Nothing financial is kept in plain SharedPreferences / UserDefaults or plain files. | M | — | Static scan of app sandbox after a test session finds no plaintext amounts, merchant names, card digits or message text. |
| FR-SEC-04 | The encryption key is generated on the device and held in Android Keystore / iOS Keychain (device-only, not synced to other devices). | M | — | Key never appears in DB, preferences, logs or backups. |
| FR-SEC-05 | App data is excluded from OS-level backups and device-to-device transfer (Android Auto Backup, iCloud device backup of the app container) — Zaghlol's own encrypted backup (FR-BAK) is the only supported transfer path. | M | — | Restoring an OS backup to a new phone does not produce a half-readable Zaghlol database. **(D-50)** **Given** an OEM transfer tool (e.g. Samsung Smart Switch) has copied Zaghlol's app data to a new phone despite the exclusion rules, **when** the app starts and finds a database whose key is not in this device's Keystore/Keychain, **then** it wipes the database and all other encrypted local data, and opens a fresh Welcome screen offering restore from Zaghlol's own backup (FR-BAK-03) — no crash, no error loop, no partial data shown. |
| FR-SEC-06 | Exports (CSV/Excel) and share images are written only to a location the user picks, after a warning that they are not encrypted (FR-EXP-05). | M | — | — |
| FR-SEC-07 | Warn (not block) when the device is rooted / jailbroken that data protection is weaker. | S | — | — |
| FR-SEC-08 | All app ↔ backend traffic over TLS 1.2+; certificate pinning per architect decision (OQ-15). | M | — | — |

### 7.25 Localization (L10N)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-L10N-01 | Full Arabic (RTL) and English (LTR) UI; default follows device language (A-28). | M | F | — |
| FR-L10N-02 | **All Arabic UI copy is Egyptian colloquial** (العامية المصرية): navigation, labels, buttons, messages, notifications and Captain Zaghlol (D-34). Legal texts and financial disclaimers use simple standard Arabic with an Egyptian one-line summary. | M | F | Copy deck reviewed by a native Egyptian speaker; follows `06-voice-and-tone.md`. |
| FR-L10N-04 | Tone is fun and friendly, but jokes never appear on errors, payments, purchases, permissions or destructive confirmations; humour never shames the user. | M | F | Copy review checklist passes. |
| FR-L10N-03 | Numbers display with Arabic-Indic or Western digits per user preference (A-29); currency shown as ج.م / EGP. | M | F | — |

### 7.26 Widgets (WID)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-WID-01 | Home-screen widget: safe daily spend + days to payday. | S | F | Respects "hide amounts" setting. |
| FR-WID-02 | Quick-add voice widget / lock-screen widget. | C | F | — |

### 7.27 Optional account (ACCT)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-ACCT-01 | Optional "Sign in with Google" (both platforms) and "Sign in with Apple" (iOS; also offered on Android if feasible) from Settings → Gold (D-14). The "sign in to protect your Gold" guidance tells the user to **sign in on the phone they bought Gold on** (D-54). | M | — | Never required for any feature except cross-platform Gold. The guidance appears on the buying phone (e.g. after purchase and in Settings → Gold) and states, in Egyptian colloquial copy, that linking is only possible from this phone. |
| FR-ACCT-02 | Signing in links the current install's entitlement(s) to the account — **only purchases made on this phone (the install that bought them) can be linked** (D-54); the backend stores only account ID, provider, email taken only from the ID token's `email` claim when present (A-47, D-49), linked purchase tokens and install IDs. | M | — | No financial data sent at sign-in. Sign in with Apple on Android requests `scope=email`; Apple's `user` form field is never read or stored. |
| FR-ACCT-03 | Sign out keeps all local data. **Signing out does not remove the seat (D-52, D-55…D-61):** the install that holds Gold keeps holding it; it is not released for another phone and signing back in on the same install is not a move. **For an account-linked purchase, Gold is paused** on that phone while signed out and resumes when the user signs in again to the owning account (D-61c). **Purchases not linked to an account are unaffected** by sign-out. *(Superseded v1.5 text: "Gold from another platform stops after cache expiry.")* | M | — | **Given** phone A holds Gold for an account-linked purchase, **when** the user signs out on A, **then** all local data stays, Gold features on A are **paused** with copy (Egyptian colloquial) saying Gold resumes on signing in again, the backend still records A as the seat holder, no move is spent, and no other phone can take Gold without a move under FR-GOLD-08. **Given** the user signs in again on A to the owning account, **then** Gold resumes and no move is counted. **Given** phone A holds Gold for a purchase **not** linked to any account, **when** the user signs out, **then** Gold continues unchanged. |
| FR-ACCT-04 | Delete account from inside the app removes account record and links on the backend (store purchases remain with the store account). **Exception (D-47):** support-lookup audit rows (FR-BE-11) — HMAC e-mail pseudonym + account ID, no plain e-mail — are kept until their own 1-year retention ends, then deleted (NFR-PRIV-07). The privacy notice states this. | M | — | Required by App Store guideline for apps with sign-in. After deletion, no backend table holds the plain e-mail or the account record; only audit rows younger than 1 year remain, and they are gone 1 year after their creation. |
| FR-ACCT-05 | **No self-service relinking after a phone change (D-54).** A purchase not yet linked to an account can be linked only from the install that bought it. If that phone is gone (reset, lost or sold without signing out), the app does not offer linking on the new phone; it points the owner to support, who can link or move it with an audited action (FR-BE-08, FR-GOLD-08). **Support linking (D-57):** support links a purchase to an account only after the store order-ID check and only when the buying phone is gone or has not been seen by the backend for **≥ 30 days**; otherwise support tells the owner to link from the buying phone. **Free reclaim (D-58, D-61b):** the first link from the buying phone returns a seat held outside the account to the buying phone even inside a running cooldown — at most once per purchase, even if the account is deleted and recreated. The reclaim **counts as the month's move and restarts the 30-day window**. **Support-link notice (v1.7):** if support linked the purchase to an account and the **buying phone later reappears** (contacts the backend again), that phone gets a **one-time notice**, in Egyptian colloquial copy: "your Gold was linked to an account by support", with the support contact. **Dispute freeze (D-64, D-65b):** after support corrects a link or move on the purchase, any further support link or move on it is refused for 30 days; further corrections stay possible, and each one restarts the 30 days; the freeze does not affect the owner's own self-service link from the buying phone or self-service moves (FR-BE-08). | M | — | **Given** support linked buying phone A's purchase to an account on 2026-11-06 because A was unseen since 2026-10-01, **when** A contacts the backend again on 2026-11-25, **then** A shows once that its Gold was linked to an account by support, with the support contact, and does not show it again on later refreshes. **Given** support detached a mistaken link on 2026-11-10 (correction), **when** support tries to link or move that purchase on 2026-11-20, **then** the action is refused and support sees the freeze ending 2026-12-10; a further correction on 2026-11-20 is allowed and moves the freeze end to 2026-12-20 (D-65b). **Given** Gold moved A → B (store-account restore, never linked) on 2026-11-06, **when** the user first signs in on buying phone A on 2026-11-12, **then** the purchase is linked, Gold returns to A at once despite the cooldown, B loses Gold, and the next move is possible from 2026-12-12 (D-61b). **Given** Gold bought on phone A and never linked, **when** the user signs in on new phone B and the purchase is restored there, **then** sign-in succeeds but the purchase is **not** linked to the account from B, and the user is told to sign in on the buying phone or contact support (B may still hold Gold through a same-store-account restore under FR-GOLD-03/08; only the account link is refused). **Given** the user signs in on phone A, **then** the purchase is linked. **Given** an already-linked purchase, **then** B signed in to the owning account can receive it under FR-GOLD-08 (one seat, 30-day move). **Given** phone A was last seen by the backend on 2026-10-01 and the owner contacts support on 2026-11-06 with a Google Play order ID in the synthetic format `GPA.0000-0000-0000-00000` that Google confirms live, **then** one support agent may link the purchase to the owner's account; the audit row records agent, purchase, account, time and "order check passed" — **not** the order ID. **Given** phone A was last seen on 2026-10-20 (less than 30 days), **then** support does not link and the owner is told to sign in on phone A. **Given** a support link was made in error, **then** support can detach and re-link through an audited correction. |

### 7.28 Catalog sync (SYNC)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-SYNC-01 | On app open (foreground), if the last successful catalog sync is older than 24 h, fetch updates in the background (D-15). Never more than one successful sync per 24 h. | M | F | Opening the app 10 times in a day produces at most 1 successful sync (+ retries after failures, BR-SYNC-02). |
| FR-SYNC-02 | Catalog = system categories & subcategories (names AR/EN, icons, colours, buckets), canonical merchants, merchant aliases/patterns, keyword heuristics. Delivered as versioned deltas since the app's current version. | M | F | — |
| FR-SYNC-03 | Updates are applied atomically into the local encrypted DB; a failed or partial download leaves the previous version intact. | M | F | Kill the app mid-download → previous catalog still works. |
| FR-SYNC-04 | Catalog payloads are signed by the backend and verified by the app before applying. | M | F | Tampered payload is rejected. |
| FR-SYNC-05 | After an update, re-categorize only transactions that were categorized by the seeded map or are in "needs classification" — never user-verified transactions or those matched by user rules (BR-CAT-01). | M | F | — |
| FR-SYNC-06 | Sync never blocks the UI and never shows errors to the user; status visible in Settings → About ("Merchant list updated: <date>"). | M | F | — |
| FR-SYNC-07 | The same daily call also refreshes feature flags and (Gold) prices and entitlement status, to minimize network use. | S | F | — |

### 7.29 Backend services (BE) — .NET + PostgreSQL (D-13)
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-BE-01 | Anonymous install registration: app generates a random install ID on first launch; backend stores it with platform, app version and first/last-seen dates only. | M | — | No device identifiers (IMEI, advertising ID, phone number). |
| FR-BE-02 | Purchase verification: receive purchase token (Android) / signed transaction (iOS) with install ID; verify with Google Play Developer API (`purchases.subscriptionsv2` / `products`) and App Store Server API; acknowledge Android purchases; return a signed entitlement (plan, expiry). | M | — | Follows store best practice: server-side verify & acknowledge; grant only on PURCHASED state; purchase token as unique key. |
| FR-BE-03 | Store server notifications: Google Real-time Developer Notifications (Pub/Sub) and App Store Server Notifications V2 update entitlements (renew, cancel, grace, refund, revoke). | M | — | Refund notification marks entitlement revoked within minutes. |
| FR-BE-04 | Price feed: periodically fetch gold (24K/21K/18K per gram) and FX rates for all supported ISO currencies from a licensed source (OQ-02), cache, and serve one shared response to all apps. | M | — | Apps never call the third-party price source directly. |
| FR-BE-05 | Feature flags: named flags (e.g. `zakah`, `smart_roi`) with on/off and optional minimum app version / platform / percentage rollout. | M | — | Flag change visible to apps within 24 h. |
| FR-BE-06 | Catalog service: versioned catalog with delta endpoint (FR-SYNC-02), signed payloads. | M | — | — |
| FR-BE-10 | "Request my bank" intake (FR-PAR-14): store institution name, country, channel type and count of distinct installs; operators see a ranked list. | S | — | No message content accepted. |
| FR-BE-07 | Contribution intake (D-16): accept anonymous merchant suggestions, aggregate by normalized name, require ≥ N distinct installs (A-48) before an operator reviews and promotes them into the catalog. | S | — | No single contribution goes live without operator approval. |
| FR-BE-08 | Operator tools (R-05): manage catalog, review contributions, set flags, look up entitlement by install ID / account for support. **Support move & link (D-52, D-56, D-57):** an operator with role **`support_agent`** can move a Gold seat to another install or link a purchase to an account. Before either action the agent enters the user-supplied store order ID (Google Play or Apple order ID), which the backend checks **live** with Google / Apple and **never stores**. One agent may act (no second approver). Linking is allowed only if the buying install is gone or not seen for ≥ 30 days (D-57d). A support move **restarts the 30-day window** (D-56). Every move and link can be **reversed through an audited correction** (move back; detach and re-link). The install that loses Gold through a support move is told so at its next refresh, with the support contact; a buying install that reappears after a support **link** gets a one-time "linked to an account by support" notice (FR-ACCT-05). **Dispute freeze (D-64, D-65b):** after a correction on a purchase, any further support **move or link** on it is refused for **30 days** from that correction; **corrections remain allowed** during the freeze, and **each new correction restarts the 30 days** (the freeze ends 30 days after the latest correction); the freeze blocks **support moves and links only** — the user's self-service move rules (FR-GOLD-08) are unchanged; every support move or link **refused by the freeze is audited** (FR-BE-11); the lookup view shows support whether a freeze is active and its end date. **Unfreeze and separation of duties (R6-1, v1.8):** an operator with role **`support_lead`** can **unfreeze** a purchase — only an operator **different from the one who made the correction** that started the freeze, after the live ownership check; the unfreeze is **audited** and **moves nothing** (seat, account and move window unchanged). The **same operator cannot both lift a freeze and redo the move or link the freeze was protecting**; the server enforces this. | M | — | **Given** a correction by operator X on 2026-11-10, **when** X calls unfreeze, **then** it is rejected; **when** support lead Y unfreezes after a passing ownership check, **then** the freeze ends, an audit row records it, and no seat or link changes; **when** Y then attempts the move the freeze was protecting, **then** the server rejects it, and a different `support_agent` Z can make it. **Given** a correction (move back) on a purchase on 2026-11-10, **when** a `support_agent` attempts a move or link on it before 2026-12-10, **then** it is rejected with the freeze end date shown, and an audit row records the refused attempt (D-65b); a correction in that period is accepted. **Given** a further correction on 2026-11-25, **then** the freeze end shown to support moves to 2026-12-25, and a support move attempted on 2026-12-15 is refused. **Given** the freeze is active, **when** the user makes a self-service move allowed by FR-GOLD-08, **then** the backend accepts it (the freeze does not apply). Operator access protected by strong auth (MFA). Form: admin web app **after the first release** (D-37); v1 uses scripts with the same MFA protection and the same `support_agent` role and checks. Every support lookup, move, link and correction is audited (FR-BE-11, D-47). A move or link without a passing live order check is rejected. An operator without `support_agent` cannot move or link. No table, log or audit row contains the order ID. |
| FR-BE-09 | Account linking for optional sign-in (FR-ACCT): verify Google / Apple ID tokens; link entitlements; delete on request. | M | — | — |
| FR-BE-11 | **Support audit (D-47, D-57).** Every operator lookup (FR-BE-08) writes an audit row with a **keyed HMAC pseudonym of the e-mail** (key held in the secrets manager, NFR-SEC-07) plus the account ID, and no plain e-mail. **Every support move, link and correction** (FR-BE-08) also writes an audit row: acting `support_agent`, action (move / link / move-back / detach / re-link), purchase, source and target install or account, time, and the fact that the live order-ID check **passed** — never the order ID itself. Corrections reference the row they reverse. *(v1.7, D-64:)* the freeze start and end date are derived from the **latest** correction row and shown to support (each new correction restarts the freeze, D-65b). *(D-65b:)* a support move or link **refused by the freeze** also writes an audit row: acting `support_agent`, attempted action, purchase, time, outcome "refused — dispute freeze" and the freeze end date (never the order ID). Rows are deleted **1 year** after creation, regardless of later account deletion (FR-ACCT-04). | M | — | Audit table contains no plain e-mail and no order ID. A support move writes exactly one row naming the agent; a correction row points to the original row. A support move or link refused by the dispute freeze writes exactly one row with outcome "refused — dispute freeze" and changes no seat or link (D-65b). A row older than 1 year is deleted by the retention job; a row for a deleted account is still deleted at 1 year, not earlier or later. |

### 7.30 Per-card breakdown (CARD) — D-25
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-CARD-01 | A **card/account filter** (single or multi-select, default "All") is available on the home screen, transaction list, budgets view, subscriptions view, chat answers and every chart. The filter persists while navigating until cleared. | M | F | Selecting "CIB Credit *1234" updates all totals, lists and charts to that card only. |
| FR-CARD-02 | **Card detail screen** for each card/account: spend by category (donut + list) for the selected period, top merchants, monthly trend, income/refunds, balance or available limit, and recent transactions. | M | F | Category totals on the card screen sum to the card's total spend for the period. |
| FR-CARD-03 | **Compare cards**: a table of categories × cards for the selected period and currency. | S | F | e.g. Dining: NBE 2,100 · CIB 1,750 · Wise USD 40. |
| FR-CARD-04 | A transaction's card is shown everywhere it appears (list, details, chat answers) with the card's label and last-4. | M | F | — |
| FR-CARD-05 | Cash, voice and manual entries belong to a selectable account (default: Cash) so they appear correctly in per-card views. | M | F | — |

### 7.31 Capture controls — ignore per card (CAP) — D-26
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-CAP-01 | For each card/account, the user can switch off capture **per channel**: SMS, app notifications (Android), Apple Pay / Wallet (iOS). Each channel is a separate toggle; turning all off = card fully ignored. | M | F | Ignoring SMS for NBE *4567 while notifications stay on still captures its notifications. |
| FR-CAP-02 | Ignored messages are **never stored** (BR-CAP-01): not in the DB, review queue, logs, backups or contributions. | M | F | After ignoring a card, a test SMS for it leaves no trace in the sandbox (inspection test). |
| FR-CAP-03 | Ignore can be set before a card is ever seen by entering institution + last-4 (e.g. a company card). | M | F | — |
| FR-CAP-04 | When ignoring a card, the user chooses what to do with its **existing** transactions: keep them (default) or delete them. | M | F | Delete removes them and updates all totals. |
| FR-CAP-05 | Ignoring is also available at institution level (e.g. "ignore all Revolut notifications"). | S | F | — |
| FR-CAP-06 | Settings → Capture shows a list of ignored cards/institutions and channels, with one-tap undo. | M | F | — |
| FR-CAP-07 | After un-ignoring on Android, offer to re-scan the SMS inbox for that card (BR-CAP-04). | S | F | Re-scan imports without duplicates. |
| FR-CAP-08 | Ignore rules are included in backups (FR-BAK-06). | M | G | — |

### 7.32 Multi-currency (CUR) — D-28, D-29
| ID | Requirement | Pri | Tier | Acceptance criteria |
|----|-------------|-----|------|---------------------|
| FR-CUR-01 | Support **any active ISO 4217 currency** for capture, manual entry, accounts, assets, budgets and exports, with correct decimals and symbol; featured currencies (EGP, USD, SAR, EUR, AED, QAR, KWD, BHD, + GBP, INR — A-59) listed first; ISO funds codes supported and listed last; non-currency X-codes excluded (FR-CUR-07, D-51). | M | F | A GBP Monzo payment, an INR HDFC payment and a JOD manual entry are each stored and shown in their own currency. |
| FR-CUR-02 | User sets a **primary currency** (default EGP) used to order views; it is never used to convert stored data. | M | F | — |
| FR-CUR-03 | Every screen with totals (home, budgets, charts, card detail, net worth, chat answers, share cards) shows **one figure per currency** and offers a currency switcher when more than one currency exists in the current filter. | M | F | No screen silently adds amounts of different currencies. |
| FR-CUR-04 | **Optional "≈ in EGP" view** (Settings toggle, off by default — A-54): adds an approximate combined total converted at the latest backend rate, always marked "≈" with the rate date. Applies to home, net worth and charts. | M | F | Turning it off removes every combined figure. Offline: uses last known rates, labelled stale after 24 h. |
| FR-CUR-05 | The ≈EGP target currency can be changed to any supported currency (e.g. ≈ in USD) (A-60). | C | F | — |
| FR-CUR-06 | Self-transfers between accounts in **different currencies** (e.g. Wise USD → NBE EGP) can be paired manually; auto-suggested when the amounts match within ±3% at the day's rate and timestamps are within 3 days (A-61). | S | F | Paired cross-currency transfers are excluded from spend and income in both currencies. |
| FR-CUR-07 | **Currency picker order and coverage (D-51).** Order: (1) featured currencies (A-59), (2) all other active ISO 4217 currencies, (3) ISO 4217 **funds codes** (e.g. BOV, CLF, CHE, CHW, COU, MXV, USN, UYI, UYW) at the end. ISO **non-currency X-codes** (precious metals XAU/XAG/XPT/XPD, XDR, XSU, XUA, bond-market units XBA…XBD, testing XTS, no-currency XXX, and the Arab Monetary Fund accounting unit XAD — D-67) are not offered. X-codes that are real circulating currencies (XOF, XAF, XCD, XPF) are regular currencies and are offered. | M | F | **Given** the picker is open, **then** the featured currencies appear first, BOV/CLF/UYW appear after every regular currency, and XAU, XDR, XTS are absent; searching "XOF" finds the West African CFA franc. A CLF manual entry is stored with CLF's ISO exponent (4) and shown in CLF (BR-MON-03). |

---

## 8. Business rules

### Money & currency
- **BR-MON-01** Amounts are stored exactly (integer minor units), never as floating point.
- **BR-MON-02** Every amount carries its currency. EGP is the reporting currency.
- **BR-MON-03** Minor units follow each currency's ISO 4217 exponent: most currencies 2 decimals; **KWD, BHD, OMR, JOD, TND, LYD, IQD = 3**; JPY, KRW and others = 0; funds codes CLF and UYW = 4 (D-51). Parsing, storage, display, CSV and backup must respect the exponent.
- **BR-FX-01** ~~Store an EGP equivalent per transaction.~~ Superseded (D-28): amounts are stored only in their original currency (plus billed amount/currency when the message states one). Conversion happens **only at display time** in the optional ≈ view, using the latest backend rate (A-62).
- **BR-FX-02** Totals, budgets, averages, charts and alerts are always computed **within one currency**. Mixing currencies is allowed only in the ≈ view and must be labelled approximate.
- **BR-FX-03** A transaction counts toward the card it was charged to in the **billed currency** (e.g. a USD purchase on an EGP card counts as EGP for that card and its EGP budgets; the original USD amount is kept for display).

### Capture & deduplication
- **BR-ING-01** Only messages from senders in the institution registry (or user-defined Gold templates) are processed.
- **BR-ING-02** Duplicates: same message body hash → ignore. Same institution + last-4 + amount + direction within 2 minutes from different channels (SMS vs notification) → treat as one (A-30).
- **BR-ING-03** OTP and promotional messages from bank senders are ignored and not stored.

### Capture controls
- **BR-CAP-01** Order of processing: receive message → identify institution, channel and card (in memory only) → if an ignore rule matches (card + channel, or institution + channel) → discard immediately; nothing is written anywhere. Only non-ignored messages continue to parsing, storage and dedupe.
- **BR-CAP-02** If the card can't be identified from the message (no last-4), only institution-level ignore rules apply; otherwise the message is processed normally.
- **BR-CAP-03** Ignore rules apply to automatic channels only (SMS, notifications, Apple Pay). Manual, voice, OCR and statement imports for that card are allowed; statement import asks whether to skip ignored cards (default: skip).
- **BR-CAP-04** Un-ignoring affects only future messages; past ignored messages are gone. Android may recover them by re-scanning the SMS inbox (FR-CAP-07); notifications and Apple Pay events can't be recovered.

### Transactions
- **BR-TXN-01** Spend = expenses − matched merchant refunds − assigned reimbursements (splits); internal transfers excluded.
- **BR-TXN-02** Income includes salary, transfer-in from others, interest, cashback; excludes internal transfers and incoming transfers assigned as reimbursements.
- **BR-TXN-03** Declined transactions are stored for reference but excluded from all totals.
- **BR-TXN-04** Credit card settlement payments are transfers (not new spend), to avoid double counting with the original card purchases (A-31).

### Self-transfers, refunds & splits
- **BR-XFR-01** An outgoing and incoming transaction are paired as internal when: both accounts belong to the user, amounts are equal (same currency), directions are opposite, and timestamps are within 5 minutes. Cross-currency pairs are only suggested, never auto-paired (FR-CUR-06).
- **BR-XFR-02** If more than one candidate matches, no auto-pair; ask the user.
- **BR-XFR-03** A refund is matched to the most recent expense at the same merchant with amount ≥ refund within 60 days (A-32); unmatched refunds count as income-type "refund".
- **BR-XFR-04** Net personal spend for a split = paid amount − linked repayments; cannot go below 0.
- **BR-XFR-05** A **reimbursement** is an incoming transfer the user assigns to an expense (D-20). It reduces that expense's net spend in its category and cycle, and is not counted as income.
- **BR-XFR-06** Total reimbursements for an expense cannot exceed the expense amount; any excess of an incoming transfer stays as normal income (or can be assigned to another expense).
- **BR-XFR-07** A reimbursement arriving in a later budget cycle reduces the **original expense's** cycle (restating that cycle's totals), not the current one (A-49).
- **BR-XFR-08** Reimbursements differ from merchant refunds (BR-XFR-03): refunds come from the merchant/bank; reimbursements come from people. Both reduce net spend; they are labelled differently.

### Categorization
- **BR-CAT-01** Precedence: user rule > merchant catalog (bundled seed + synced updates) > keyword heuristics > "needs classification". A catalog update never overrides a user rule or a user-verified transaction.
- **BR-CAT-02** Every category belongs to one bucket: Needs, Wants, Obligations, Savings, Income, Giving. For the 50/30/20 chart: Needs + Obligations → 50%; Wants + Giving → 30%; Savings → 20% (A-33).
- **BR-CAT-03** Transfers to a person (IPA / phone) with no rule go to "needs classification".

### Budget
- **BR-BUD-01** Payday day is 1–28. Cycle = payday … day before next payday.
- **BR-BUD-02** Alert thresholds default 80% and 100%; each fires once per category per cycle.
- **BR-BUD-03** Safe daily spend = max(0, total budget − cycle spend) ÷ days remaining including today.
- **BR-BUD-04** Ideal burn line on day *d* = total budget × *d* ÷ cycle length.

### Mascot triggers
- **BR-MAS-01** Shocked: a category passes 85% of its budget before day 20 of the cycle, or dining/delivery spend is > 30% above the user's 3-cycle average.
- **BR-MAS-02** Proud: user is under the ideal burn line, or meets a monthly goal.
- **BR-MAS-03** Detective: duplicate POS debit (same merchant, amount, card within 10 minutes (A-34)), subscription renewal detected, or self-transfer paired.

### Subscriptions & installments
- **BR-SUB-01** A subscription is suggested when the same merchant is charged a similar amount (±10%) at roughly monthly intervals (25–35 days) at least 2 times (A-35).
- **BR-SUB-02** Annualized cost = monthly cost × 12.
- **BR-SUB-03** Reminder default: 3 days before due date.

### Wealth
- **BR-WLT-01** Net worth = account balances + asset values − credit card balances − remaining installments − other liabilities (A-36), **computed separately per currency/unit**; combined only in the ≈ view (D-29).
- **BR-WLT-02** Gold value = grams × current price for that karat; CD value = principal (accrued interest not added until paid) (A-37).

### Zakah (flagged)
- **BR-ZAK-01** Nisab = value of 85 g of 24K gold.
- **BR-ZAK-02** Hawl = 354 days per asset lot.
- **BR-ZAK-03** Rate 2.5% per eligible item in its native unit; 21K gold counts as 87.5% purity toward nisab.
- **BR-ZAK-04** Short-term debts due now are deducted from cash before Zakah.
- **BR-ZAK-05** All Zakah rules subject to scholar review before the flag is turned on (D-07).

### Gold tier
- **BR-GOLD-01** Plans: monthly, yearly, lifetime. Prices TBD (D-12).
- **BR-GOLD-02** Free voice limit: 15 confirmed voice logs per calendar month.
- **BR-GOLD-03** The backend-signed entitlement is cached securely on device; the app honours it offline until token expiry + grace (A-38). Lifetime entitlements don't expire but are re-checked when online. *(D-60, supersedes the D-52 note "at most 14 days" and the earlier "7-day grace": the entitlement token lives **3 days** and the grace is **4 days**, so for every plan, including lifetime, a phone **that has lost Gold** keeps it without contacting the backend for **at most 7 days**; the **current holder** keeps at least 5 offline days (FR-GOLD-04) — how the holder's token is refreshed to guarantee this is the architect's design. Expiry and grace use trusted time; a detected clock rollback withholds Gold until reconnect (NFR-SEC-08). ADR-012's 30-day roll for lifetime tokens must be revised accordingly.)*
- **BR-GOLD-04** On downgrade, Gold-created data (custom categories, assets, rules) stays visible and usable for reading; creating new Gold items is blocked.
- **BR-GOLD-05** Gold is granted only after backend verification of a purchase in PURCHASED state; PENDING purchases (e.g. cash-payment methods) show "pending" and grant nothing until completed.
- **BR-GOLD-06** If the backend is unreachable at purchase time, the app keeps the purchase and retries verification; the store's own refund-on-no-acknowledgement window (3 days on Google Play) must not be missed — retries continue in the background.
- **BR-GOLD-07** *(D-52, D-55…D-65)* One live Gold seat per purchase, across platforms. A move to a different phone is allowed once per rolling 30 days; support moves are audited and **restart the window** (D-56); a same-phone restore is not a move — on iOS this includes a reinstall or "Delete everything" on the same iPhone, recognised through the seat keys (D-62), **up to 2 free recognitions per purchase per rolling 30 days; beyond that it counts as the monthly move (D-63)**; **on the iPhone that holds the seat an over-cap reinstall is never refused — Gold stays and the window restarts, even if the month's move is already used (D-65a)**; support moves and links are frozen for 30 days after the latest support correction on the purchase — each new correction restarts the freeze, refused support attempts are audited, and self-service move rules are unaffected (D-64, D-65b); on Android a reinstall or "Delete everything" is a new install (D-55). A plan change from a phone other than the holder **moves Gold and counts as the move**; the payment is never blocked (D-59); if the month's move is already used, Gold stays on the holder and the paying phone sees the next-move date (D-61a). The first account link from the buying phone reclaims the seat despite a running cooldown, **once per purchase** (D-58), and that reclaim counts as the move and restarts the window (D-61b). Signing out does not release the seat or spend a move; for an account-linked purchase it pauses Gold on that phone until sign-in (FR-ACCT-03, D-61c). A phone Gold moved away from loses Gold within **7 days** even offline (3-day token + 4-day grace, D-60) *(superseded v1.5 text: "token lifetime is at most 14 days … within 14 days")*; BR-GOLD-03's offline honouring applies only to the current seat holder.

### Sync & backend
- **BR-SYNC-01** Catalog, flags and prices are fetched at most once per 24 h after a successful sync, triggered on app open.
- **BR-SYNC-02** After a failed sync, retry on next app open with exponential back-off (max 1 attempt per hour).
- **BR-SYNC-03** The backend receives only: anonymous install ID, platform, app version, catalog version, purchase tokens/transactions, optional account ID token, **a device attestation token/assertion (Play Integrity on Android, App Attest on iOS) for purchase restore and, if ADR-012 Amendment (2026-11-05) requires it, purchase verification — carrying no other device data (D-45)**, ~~on iOS only, a derived non-reversible proof of the per-device Keychain install secret (ThisDeviceOnly) used to recognise a reinstall on the same iPhone — never the secret itself and carrying no other device data (D-55; exact form per the architect)~~ *(superseded by D-62)* **on iOS only, the field `seatKeys[] {publicKey, signature}`: element 0 is the current install's Secure Enclave public key and a signature made with it, sent on purchase verify, restore and sign-in (v1.8, R5-9); on restore and sign-in it is followed by up to 4 public keys and signatures from earlier Zaghlol installs on the same iPhone (at most 5 entries), used to recognise a reinstall on the same iPhone (D-55, D-62, D-63). Accepted linkability (D-62): in transit the backend can tell which installs came from the same iPhone; at rest it keeps only a keyed hash per purchase plus a per-install keyed hash of the install's own seat key (`installs.seat_key_hash`, keyed with the install ID so it cannot be joined across installs, deleted with the install — v1.8, R5-9), never the raw keys, and raw keys are never logged. Carries no other device data**, (if opted in) merchant contributions, and (if the user asks) bank-support requests (name, country, channel type). Never: messages, transactions, amounts, balances, budgets, assets, user rules, contacts, location.
  - *Classification (D-48)* — these fall under existing classes and are not new data: the server-issued cursors `flagsVersion`, `pricesAsOf`, `entitlementIssuedAt`, `registryVersion` → "catalog/app version"; the restore `productId` → "purchase tokens/transactions"; the raw sign-in `nonce` → "optional account ID token".
  - *Classification (D-55…D-60, v1.6)* — the iOS Keychain-derived install proof is a **new class** (amendment above, D-55), not a classification under an existing one; a **plan-change purchase token / transaction** (D-59) → "purchase tokens/transactions"; an app request for **trusted server time** (D-60) carries nothing beyond the existing classes; the **store order ID** used for support's ownership check (D-57) is **not sent by the app** — the user gives it to support, the backend checks it live with Google/Apple and never stores it; the "Gold moved by support" notice (D-57f) is server → app and adds no app-sent data. *(v1.6 "iOS Keychain-derived install proof" now reads "iOS `seatKeys[]`", D-62.)*
  - *Classification (D-62…D-64, v1.7)* — `seatKeys[] {publicKey, signature}` (iOS only) is the **new class** set by D-62 (replaces the D-55 proof); the **time nonce** — a fresh random value per request, generated by the app, with **no device data**, sent so that the backend-signed server time in the response is bound to that request (trusted time, NFR-SEC-08) → not new data, classified with the request it travels in (D-48 style); the "linked to an account by support" notice (FR-ACCT-05) and the dispute-freeze state (D-64) are server-side / server → app and add no app-sent data.
- **BR-SYNC-04** A merchant contribution = {normalized merchant string, institution code, chosen system category}. Excluded: person-to-person transfers, phone numbers, IPAs, anything matching a person-name pattern, user-defined category names. Contributions are batched and sent with the daily sync.

### Backup & export
- **BR-BAK-01** Backups are encrypted before leaving the device; the key is never uploaded.
- **BR-BAK-02** Free: one backup slot, manual only. Gold: automatic schedule and the last 5 versions (A-25). Both include all data, settings and customizations (FR-BAK-06).
- **BR-EXP-01** CSV is UTF-8 with BOM; dates ISO 8601; amounts with `.` decimal.

---

## 9. Non-functional requirements

### Privacy (PRIV)
- **NFR-PRIV-01** No analytics, advertising or third-party crash-reporting SDKs. The Zaghlol backend (D-13) receives only the data listed in BR-SYNC-03.
- **NFR-PRIV-02** Financial data leaves the device only (a) as an encrypted backup to the user's own Drive/iCloud, (b) as files the user explicitly exports or shares. Purchase data goes to the stores and the Zaghlol backend for verification.
- **NFR-PRIV-03** Price and flag requests carry no holdings or financial data.
- **NFR-PRIV-06** Backend data retention: install records deleted after 12 months of inactivity; request logs kept ≤ 30 days without full IP addresses (A-50).
- **NFR-PRIV-04** Non-financial SMS are never read into storage (Play spyware policy).
- **NFR-PRIV-05** Comply with Egypt's Personal Data Protection Law No. 151/2020 and store privacy disclosures (Play Data safety, Apple privacy labels) (A-39).
- **NFR-PRIV-07** Support-lookup audit (D-47, FR-BE-11): audit rows hold only a keyed HMAC pseudonym of the e-mail and the account ID; retention is exactly 1 year from creation, then deletion, including for accounts deleted earlier (FR-ACCT-04). The HMAC key is a backend secret (NFR-SEC-07) and never leaves the backend. Purpose (support accountability) and retention are stated in the privacy notice as required by PDPL 151/2020 (NFR-PRIV-05). Store disclosures (Play Data safety, Apple privacy labels) list device attestation (D-45) and, on iOS, ~~the Keychain-derived install proof (D-55)~~ the **seat keys** (D-62) where the stores require it. **Support actions (D-57):** move/link/correction audit rows (FR-BE-11) follow the same 1-year retention; the store order ID used for the ownership check is never stored, logged or audited — only "check passed". **iPhone seat keys (D-62, v1.7):** (a) the backend receives `seatKeys[] {publicKey, signature}` on iOS restore and sign-in (and element 0, the install's own key, also on purchase verify — v1.8, R5-9) and may link, in transit, the installs that came from the same iPhone — accepted by the PO; (b) **at rest only a keyed hash per purchase** is kept (key is a backend secret, NFR-SEC-07), plus a **per-install keyed hash of the install's own seat key** (`installs.seat_key_hash`), keyed with the install ID so it cannot be joined across installs and **deleted with the install** (v1.8, R5-9) — never the raw public keys; (c) raw keys and signatures are **never written to logs**, request logs (NFR-PRIV-06) or audit rows; (d) **store disclosures** — the Apple privacy label (and App Store review notes) must declare the seat keys as a device-scoped identifier collected for purchase anti-fraud / app functionality, not used for tracking; whether it is "linked to you" (it can be once the user signs in) and the exact label categories are confirmed before submission (A-39); Play Data safety is unaffected (iOS only); (e) **privacy notice** states the purpose (recognise a reinstall on the same iPhone so it does not spend the monthly move), that the backend can tell installs on the same iPhone apart from others, the at-rest keyed hash and its retention, and that **"Delete everything" on iOS keeps the seat keys on the phone and the keyed hash on the server** (FR-ONB-08). Retention of the keyed hash per purchase is set by the architect and stated in the notice.

### Security (SEC)
- **NFR-SEC-01** Database encrypted at rest with AES-256 (SQLCipher); key generated on device, protected by Android Keystore / iOS Keychain.
- **NFR-SEC-02** Backup files AES-256-GCM, authenticated.
- **NFR-SEC-03** No sensitive data (message bodies, balances, card digits, names, phone/IPA) in logs.
- **NFR-SEC-04** App switcher snapshot hidden when app lock is on.
- **NFR-SEC-05** Gold entitlement can't be unlocked by editing local files: the cached entitlement is signed by the backend and verified by the app.
- **NFR-SEC-06** All local data encrypted (FR-SEC-03); no plaintext copies outside the app sandbox except user-initiated exports.
- **NFR-SEC-07** Backend: TLS only; secrets (store API keys, signing keys) in a secrets manager; operator access with MFA; OWASP ASVS L2 as baseline (A-51).
- **NFR-SEC-08** *(D-60)* **Trusted time for Gold.** Entitlement expiry and grace are evaluated against trusted time (anchored to backend-signed time from the last successful contact; mechanism per the architect), not the raw device clock. If the device clock is detected as set back, Gold is withheld until the app reconnects and refreshes, with "connect to check Gold" copy; local data stays readable (BR-GOLD-04). Moving the clock forward never extends Gold. *(v1.7:)* To bind a signed server time to its own request, the app sends a **time nonce** — a fresh random value per request, with no device data (BR-SYNC-03 classification, D-48 style); the app accepts a signed server time only if it carries the nonce of that request, so a recorded old response cannot be replayed to anchor a false time.

### Backend operations (BE)
- **NFR-BE-01** The app must remain fully usable when the backend is down (only new purchases verification, cross-platform Gold, catalog/price/flag freshness are delayed).
- **NFR-BE-02** Availability target 99.5% monthly (A-52).
- **NFR-BE-03** Daily sync response for a client already on the latest catalog ≤ 2 KB; full catalog ≤ 1 MB compressed.
- **NFR-BE-04** Capacity: 500k registered installs, 100k daily syncs at launch +12 months (A-53).
- **NFR-BE-05** Stack: .NET (current LTS) Web API + PostgreSQL; hosting provider and region decided in Phase 3 (OQ-16).

### Performance (PERF) — proposed targets (A-40)
- **NFR-PERF-01** Parse one message < 10 ms (reference mid-range Android, e.g. 2023 Samsung A-series).
- **NFR-PERF-02** Cold start to home < 2 s.
- **NFR-PERF-03** Historical scan of 10,000 SMS < 60 s, with progress.
- **NFR-PERF-04** Charts render < 300 ms with 2 years of data; 60 fps scrolling.
- **NFR-PERF-05** Voice phrase → parsed items < 2 s after speech ends.
- **NFR-PERF-06** Background capture must not noticeably affect battery (< 1% per day attributable).

### Reliability (REL)
- **NFR-REL-01** No transaction loss when the app is killed during capture; capture is idempotent.
- **NFR-REL-02** Database migrations are tested and never lose data.
- **NFR-REL-03** All features except catalog/price/flag refresh, backup, purchases and sign-in work fully offline.

### Usability & accessibility (UX)
- **NFR-UX-01** Arabic-first RTL layouts, fully mirrored LTR for English.
- **NFR-UX-02** WCAG 2.1 AA contrast; touch targets ≥ 48 dp; supports text scaling to 130% without breaking layout; screen-reader labels in both languages.
- **NFR-UX-03** Material 3 conventions on Android, iOS conventions on iOS.
- **NFR-UX-04** Light and dark mode.

### Compatibility (COMP)
- **NFR-COMP-01** Minimum OS versions: TBD (OQ-03). Proposed Android 8.0+ (API 26), iOS 17+ (needed for silent message automations — to verify in Phase 3).
- **NFR-COMP-02** Phones only; tablets supported in portrait without dedicated layout (A-41).

### Maintainability (MAINT)
- **NFR-MAINT-01** Institution templates and merchant seeds are data, updatable per release.
- **NFR-MAINT-02** Domain logic (parsing, categorization, budgets, Zakah) unit-tested independently of UI.

### Compliance (COMP-L)
- **NFR-LEGAL-01** Google Play: SMS permission declaration form for "SMS-based money management"; app must remain functional without it (D-02).
- **NFR-LEGAL-02** App Store: in-app purchase for digital features; privacy nutrition label accurate.
- **NFR-LEGAL-03** Disclaimers: coaching and ROI are not financial advice; Zakah is an estimate.
- **NFR-LEGAL-04** Use of bank names/logos in UI requires a trademark review (OQ-09).

---

## 10. Edge cases

**Capture & parsing**
- EC-01 Same transaction arrives by SMS and app notification → one record (BR-ING-02).
- EC-02 Two genuinely identical purchases (same amount, merchant, minute) → must not be merged when bodies differ by reference/time; if bodies are identical, user can split duplicates manually.
- EC-03 Arabic-Indic digits, mixed digit systems, missing decimals, thousands separators in either script.
- EC-04 Message missing balance, merchant or last-4.
- EC-05 Foreign-currency purchase (USD at AMAZON) with or without EGP equivalent in message.
- EC-06 Declined / reversed / pending authorisation messages.
- EC-07 OTPs, promos and statement notices from bank senders → ignored.
- EC-08 Bank changes its SMS format → parse fails → message goes to review queue; not lost.
- EC-09 Multi-part (concatenated) SMS.
- EC-10 Phone clock wrong or timezone changes; message date vs receipt time disagree.
- EC-11 Dual-SIM devices.
- EC-12 Historical scan finds thousands of messages from years ago → only within configured depth.
- EC-13 SMS permission revoked later → app detects and switches to degraded mode with a banner.
- EC-14 iOS Shortcut automation disabled or asks for confirmation → app detects absence of captures and nudges.

**Transfers, refunds, splits**
- EC-15 Self-transfer where only one side is captured (other bank not sending SMS) → no pair; user can mark as internal.
- EC-16 Two transfers of the same amount within 5 minutes → ambiguous; ask user (BR-XFR-02).
- EC-17 Partial refunds; refund larger than original.
- EC-18 Split repayment arrives before the expense is marked as split.
- EC-19 Credit card bill payment via InstaPay (InstaPay sample 5) → transfer, not spend.

**Budget & dates**
- EC-20 Payday falls on Friday/holiday and salary arrives early — cycle stays on configured day (A-42).
- EC-21 User changes payday mid-cycle → current cycle ends early; new cycle starts next payday.
- EC-22 Months shorter than payday day (not possible since max 28).
- EC-23 First cycle after install has partial data → charts and averages state "not enough data".
- EC-24 Zero budget set → no percentage alerts; safe daily spend hidden.

**Gold tier & data**
- EC-25 Subscription expires while offline → grace period then downgrade.
- EC-26 Restore a backup made with a newer app version → refuse with update prompt.
- EC-27 Forgotten backup passphrase → backup unrecoverable; warned at setup.
- EC-28 Device storage full during backup/export.
- EC-29 Delete-all-data while backup is running.

**Voice & chat**
- EC-30 Voice phrase with no amount, or amount with no item.
- EC-31 Mixed Arabic-English speech ("دفعت 200 Uber").
- EC-32 Device lacks on-device Arabic recognition → clear message; manual entry offered.
- EC-33 Chat question about a period with no data → explicit "no data" answer.

**Wealth**
- EC-34 Price fetch fails / stale for > 24 h → show last price with date.
- EC-35 Asset recorded in a currency without a fetched rate.
- EC-36 KWD/BHD amounts with 3 decimals in SMS (`KWD 12.345`) — must not be truncated to 2.

**Multi-currency & online banks**
- EC-50 Same amount format ambiguity: `1.234` = one thousand two hundred thirty-four (EU grouping) or 1.234 KWD → resolved by the institution template's locale and the currency's exponent.
- EC-51 Indian grouping `₹1,23,456.78` (HDFC/Paytm).
- EC-52 Wise/Revolut in-app conversion USD→EGP → internal transfer, not spend (FR-PAR-12).
- EC-53 Foreign purchase on an Egyptian card: message shows USD 20.00 and EGP 1,010.00 → card total counts EGP 1,010.00; USD shown as original (BR-FX-03).
- EC-54 Revolut card payment notification followed later by a "payment settled" with a slightly different amount (FX settlement) → update the original, don't create a second transaction (A-63).
- EC-55 User has only one currency → no currency switcher or ≈ UI appears.
- EC-56 ≈ view on while a currency has no fetched rate → that currency is listed separately as "not included".
- EC-57 Notification text from an online bank is in a language other than English (app language set to German/Dutch) → unrecognized → review queue; setup tells user to set the bank app to English (A-57).

**Per-card & ignore rules**
- EC-58 Ignored card appears in a message together with a non-ignored card (e.g. transfer from ignored card to tracked account) → the transfer is captured from the tracked side's message only.
- EC-59 Two cards share the same last-4 at different institutions → ignore rules match institution + last-4, never last-4 alone.
- EC-60 Card is replaced (new last-4) → new card appears; user can merge (FR-ACC-04) and copy ignore settings.
- EC-61 Card filter selected and the user opens a chart with no data for that card → empty state names the card.
- EC-62 Historical scan runs while a card is ignored → its messages skipped.
- EC-63 User ignores a card while it has pending reimbursements or split links → links kept on existing transactions (unless user chose delete).

**Reimbursements**
- EC-37 Friends reimburse more than their share, or reimburse total > expense → excess stays income (BR-XFR-06).
- EC-38 Reimbursement arrives before the expense is captured (e.g. friend pays first) → can be assigned later.
- EC-39 Same friend's single transfer covers two different outings → split across expenses (FR-XFR-07).
- EC-40 Expense deleted or edited after reimbursements were assigned → reimbursements unassigned with a notice if they'd exceed the new amount.

**Backend, sync & accounts**
- EC-41 Backend unreachable for weeks → app runs on last catalog/prices/flags; prices marked stale.
- EC-42 Catalog update renames or merges a merchant used by a user rule → user rule still wins and keeps working.
- EC-43 Device clock wrong → 24 h sync throttle uses server time from the last response.
- EC-44 Purchase made with no network → verification retried; Gold shown as "pending verification".
- EC-45 User buys Gold on Android and iOS separately and then signs in on both → both entitlements linked; no double charge handling needed by app (store handles refunds).
- EC-46 User signs into a different account on the same phone → entitlements from previous account removed after confirmation.
- EC-47 Restoring a backup on a phone whose catalog is newer/older than the backup's → restored rules apply; catalog re-syncs.
- EC-48 Contribution opt-in turned off while a batch is queued → queued batch is deleted, not sent.
- EC-49 Feature flag turned off after a user has created Zakah data → data kept, feature hidden.
- EC-64 *(revised D-52, D-60)* A Gold purchase token is shared to a second phone → if no move in the last 30 days, Gold moves to that phone and the original holder loses it (at next refresh, or within **7 days** offline, D-60); otherwise refused with the next-move date and a support link. Never more than one live seat (FR-GOLD-08). *(Superseded v1.5 text: "within 14 days offline". Superseded v1.4 text: "shared to a 4th phone while 3 installs already hold Gold → never more than 3 at once".)*
- EC-65 Account-linked purchase restored on a phone that is signed out or signed in to another account → no Gold; user asked to sign in with the owning account (FR-GOLD-08). Signed in to the owning account on the new phone → subject to the 30-day move rule. A purchase **never linked** before the buying phone was reset or sold → cannot be linked from the new phone; user pointed to support (D-54, FR-ACCT-05). Support links only after a passing live order-ID check and only if the buying phone has not been seen for ≥ 30 days (D-57); if it was seen more recently, the owner is told to link from it. *(iOS: if the buying iPhone was only reinstalled, not reset, it is still recognised as the buying phone, D-55, via its seat keys, D-62; the D-63 cap limits only free recognitions, not recognition of the buying phone.)* *(v1.7:)* If support linked the purchase and the buying phone later reappears, it shows a one-time "your Gold was linked to an account by support" notice (FR-ACCT-05). After a support correction, further support links or moves on the purchase are frozen for 30 days (D-64); each new correction restarts the freeze and it does not block the owner's own link from the buying phone (D-65b).
- EC-66 Restore on a device where attestation fails or is unavailable (rooted phone, custom ROM, Play services missing, App Attest unsupported) → no Gold; help message (FR-GOLD-09, R-19). A refused restore is not counted as a move (D-52); a support move after the ownership check (D-57) is the fallback and restarts the 30-day window (D-56).
- EC-67 OEM transfer tool (e.g. Samsung Smart Switch) copies the encrypted DB to a new phone without its Keystore key → DB wiped, fresh Welcome with restore offer (FR-SEC-05, D-50). A Gold restore on the new phone is a new install and follows the 30-day move rule (D-55: the iOS Keychain install secret is ThisDeviceOnly and never travels to a new device; *v1.7, D-62:* the Secure Enclave seat keys likewise never leave the iPhone).
- EC-68 *(D-52, D-56, D-57)* Phone lost, stolen or broken **inside the 30-day cooldown** (e.g. Gold moved to phone B on 2026-11-06, B breaks on 2026-11-15, restore on phone C refused until 2026-12-06) → app shows the next-move date and a support link; the user gives support the Google Play / Apple order ID, support checks it live (order ID not stored) and one `support_agent` performs an audited manual move to C. The move **restarts the window**: next move from 2026-12-15 (D-56). If B comes back online it is told Gold was moved by support, with the support contact; a mistaken move can be reversed by an audited move-back (FR-GOLD-08, FR-BE-08/11, R-21). *(v1.7, D-64:)* after such a move-back (e.g. on 2026-11-17), support cannot move or link that purchase again until 2026-12-17 (dispute freeze, visible to support); a further correction is still possible and restarts the freeze (e.g. a second correction on 2026-11-25 → frozen until 2026-12-25); each support move or link refused by the freeze is audited (D-65b). The freeze covers support actions only: a user disputing the correction inside the freeze can still make a self-service move under the normal monthly-move rules (D-65b), otherwise must wait. *(Superseded v1.5 text: "support verifies ownership" — ownership check now defined by D-57.)*
- EC-69 *(D-55)* **Reinstall / "Delete everything" on the same phone.** iOS: the app is deleted and reinstalled on the same iPhone → ~~the Keychain install secret survives, the backend recognises the same device from its derived proof~~ *(D-62:)* the earlier installs' Secure Enclave seat keys survive, the new install sends `seatKeys[]` (its own key + up to 4 earlier keys), the backend matches one to the purchase's keyed hash, Restore returns Gold and no move is counted — **up to the D-63 cap**: the 1st and 2nd recognition per purchase in a rolling 30 days are free; a 3rd (e.g. reinstalls recognised on 2026-11-06 and 2026-11-10, a third on 2026-11-20) counts as the monthly move. *(D-65a:)* if this iPhone holds the seat, the over-cap restore is **never refused** — Gold stays and the window restarts (next move from 2026-12-20), even if the month's move was already used (e.g. Gold moved to this iPhone on 2026-11-01) — provided the owner can restore with an App Store purchase on this iPhone. *(D-66, accepted residual:)* if the Gold was bought on Android (Google Play) or under a different Apple ID, the iPhone has no App Store transaction and can only sign in, whose seat key is not trusted (no App Attest on sign-in); the over-cap sign-in is then an ordinary move and is refused until the next-move date (2026-12-01 in this example, at most 30 days); the app shows that date and the support path instead of Restore, and support can move the seat (support-lead unfreeze first if a dispute freeze is running, FR-BE-08); if this iPhone no longer holds the seat, the normal move rules apply (allowed and counted if no move in the last 30 days, otherwise refused with the next-move date). An iPhone with more than 4 earlier installs' keys still sends at most 4 of them (which 4: architect). Android: the user taps "Delete everything" while holding Gold → warning first ("restoring Gold afterwards counts as this month's move"); after confirming, or after an Android reinstall, a restore is a new install — counted as the move if none in the last 30 days, otherwise refused with the next-move date and a support link. OS factory reset on either platform → new device (Keychain ThisDeviceOnly items do not survive a full erase).
- EC-70 *(D-60)* **Clock rollback.** The user, offline, sets the phone's clock back (e.g. from 2026-11-20 to 2026-11-01) to stretch an expired or moved-away Gold token → rollback detected; Gold is withheld with "connect to check Gold" copy until a successful online refresh, which restores Gold if the phone is still the seat holder. Data created with Gold stays readable (BR-GOLD-04). Normal time-zone changes and DST shifts are not treated as a rollback (trusted-time design per the architect, NFR-SEC-08).
- EC-71 *(D-59, D-61a)* **Plan change from another phone.** Phone B holds monthly Gold; on phone A the user upgrades to yearly (or downgrades yearly → monthly at renewal) → the store payment always goes through; if no move in the last 30 days, Gold moves to A, the move is counted and B loses Gold at next refresh or within 7 days offline. Inside the cooldown (this month's move already used) the payment still goes through, Gold **stays on B**, and A shows the next-move date — no extra move (D-61a). A plan change made on the current holder is not a move.
- EC-72 *(D-58, D-61b)* **Delete the account and sign in again.** Buying phone A, never linked; phone B holds Gold through a store-account restore; user signs in on A → first link, Gold returns to A even inside a running cooldown (free reclaim); the reclaim counts as the month's move and restarts the 30-day window (e.g. reclaim on 2026-11-12 → next move from 2026-12-12). User later deletes the account (FR-ACCT-04) and signs in again on A (same Google/Apple identity or a new one) → the purchase can be linked again from A, but **no second free reclaim**: if B (or another phone) holds the seat by then, normal 30-day rule applies. Deleting the account does not reset the move window.
- EC-73 *(FR-ACCT-03, D-61c)* **Sign out and back in on the holder.** User signs out on the phone that holds Gold for an **account-linked** purchase → Gold is **paused** on that phone (data stays, copy says Gold resumes on signing in), seat stays reserved, no move spent; user signs in again (same account) → Gold resumes, no move counted. For a purchase **not linked** to an account, sign-out changes nothing. Signing in to a **different** account on that phone follows EC-46 and FR-GOLD-08(e).

## 11. External integrations

| ID | Integration | Platform | Purpose | Network? | Notes |
|----|-------------|----------|---------|----------|-------|
| INT-01 | SMS provider / BroadcastReceiver | Android | SMS capture | No | Play declaration required. |
| INT-02 | NotificationListenerService | Android | Bank/wallet notifications | No | Special access setting. |
| INT-03 | Share intent / clipboard | Both | Manual message import | No | — |
| INT-04 | Shortcuts + App Intents (Message & Transaction automations) | iOS | SMS & Apple Pay capture | No | Automation behaviour to verify per iOS version. |
| INT-05 | Message filter extension | iOS | SMS capture (D-09) | No | Feasibility risk R-02. |
| INT-06 | Vision OCR / ML Kit text recognition | Both | Screenshot & receipt OCR | No | Arabic OCR support to verify (R-06). |
| INT-07 | On-device speech recognition (ar-EG, en) | Both | Voice entry | No (on-device) | Availability varies (R-05). |
| INT-08 | Google Play Billing | Android | Gold purchases | Yes | — |
| INT-09 | StoreKit 2 | iOS | Gold purchases | Yes | — |
| INT-10 | Google Sign-In + Drive API v3 (`drive.appdata`) | Both | Encrypted backup | Yes | OAuth client IDs needed. |
| INT-11 | iCloud (Drive or CloudKit private DB) | iOS | Encrypted backup | Yes | — |
| INT-12 | Gold & FX price source | Backend | Asset valuation | Yes | Called by backend only; source TBD (OQ-02). |
| INT-17 | Zaghlol backend API (.NET) | Both | Sync, entitlements, prices, flags, contributions, accounts | Yes | D-13. |
| INT-18 | Google Play Developer API (purchases, voided purchases) | Backend | Verify & acknowledge purchases | Yes | Service account. |
| INT-19 | Google Cloud Pub/Sub — Real-time Developer Notifications | Backend | Subscription lifecycle events | Yes | — |
| INT-20 | App Store Server API + App Store Server Notifications V2 | Backend | Verify transactions, lifecycle events | Yes | Signed JWS. |
| INT-21 | Sign in with Google / Sign in with Apple | App + Backend | Optional account (FR-ACCT) | Yes | Apple requires Sign in with Apple if other social logins are offered on iOS. |
| INT-22 | Play Integrity API / App Attest (DeviceCheck) | App + Backend | Device attestation for Gold restore (and possibly verify) (D-45) | Yes | No other device data sent (BR-SYNC-03); design in ADR-012 Amendment (2026-11-05). |
| INT-13 | Local notifications | Both | Alerts & reminders | No | — |
| INT-14 | Biometrics (BiometricPrompt / LocalAuthentication) | Both | App lock | No | — |
| INT-15 | System share sheet | Both | Share cards & exports | No | — |
| INT-16 | Home-screen widgets (App Widgets / WidgetKit) | Both | Glanceable info | No | — |

## 12. Out of scope

| ID | Item | Reason |
|----|------|--------|
| OOS-01 | Storing or syncing any user financial data on the Zaghlol backend; mandatory accounts; cross-device data sync (only Gold entitlement syncs) | D-13, D-14 |
| OOS-02 | Sharing budgets across people/devices; multiple profiles on one device | D-04 |
| OOS-03 | Bank login / open-banking APIs / screen-scraping | Privacy promise |
| OOS-04 | Making payments, transfers or purchases of gold/funds from the app | Not in spec; regulatory |
| OOS-05 | Cloud or on-device LLM chat | D-06 |
| OOS-06 | Markets outside Egypt (UK, EU, India launches, local languages, local store listings/marketing). Foreign banks are supported only for Egyptians who hold them. | D-27 |
| OOS-07 | Web, desktop, tablet-optimized or wearable apps | A-41 |
| OOS-08 | Advertising | Spec Screen 1 ("no ads") |
| OOS-09 | Producing the 8 / 10 social-media marketing campaigns (spec §6, §13.3) — they are marketing assets, not app features | Separate marketing workstream |
| OOS-10 | Zakah and Smart ROI **visible** at launch | D-07, D-10 (built, flagged off) |
| OOS-11 | Tax filing, credit scoring, loan offers | Not in spec |
| OOS-12 | PDF statement import for banks other than CIB, NBE, QNB, Banque Misr | Spec §2 |
| OOS-13 | Distributing an APK outside Google Play | D-02 (not chosen) |
| OOS-14 | Email capture (Gmail / Outlook bank alerts) — later option | D-23; Gmail restricted scope needs annual security assessment |
| OOS-15 | Over-the-air SMS template updates from the backend — later option | D-17 |
| OOS-16 | Third-party subscription platforms (e.g. RevenueCat) — own backend chosen | D-13 |
| OOS-17 | Per-card budgets, default category per card, card groups/tags (Personal/Business) | Not selected in D-25 — later options |
| OOS-18 | Open-banking APIs of online banks (e.g. Wise/Revolut/Monzo APIs) | Privacy promise (OOS-03); capture stays message/notification/statement-based |
| OOS-19 | Crypto assets | Not requested |

## 13. Risks

| ID | Risk | Impact | Mitigation |
|----|------|--------|-----------|
| R-01 | Google Play refuses the SMS permission exception. | Android auto-capture limited to notifications. | D-02 fallbacks; prepare declaration and demo video; notification capture as first-class channel. |
| R-02 | iOS message filter extension cannot capture or persist bank SMS (it only sees unknown senders and has no shared storage). | Channel unusable. | Architect feasibility spike in Phase 3; Shortcuts remains primary iOS channel. |
| R-03 | Spec SMS samples are prototype-generated, not real bank formats. | Parsing fails on real messages. | Collect anonymized real samples per institution (OQ-04). |
| R-04 | Full-spec scope at launch on two platforms. | Long timeline, quality risk. | Phase 4 milestones deliver vertical slices; flags allow holding back unstable features. |
| R-05 | On-device Egyptian Arabic speech recognition unavailable or poor on many devices. | Voice entry degraded. | Detect support; offer online system recognizer only with user consent (OQ-06). |
| R-06 | Arabic OCR quality for screenshots. | OCR channel weak. | Spike in Phase 3; templates for InstaPay receipts. |
| R-07 | iOS Shortcuts automations may require user confirmation or break across iOS updates. | iOS capture friction. | Setup checker; in-app guidance; screenshot OCR backup. |
| R-08 | Religious accuracy of Zakah. | Reputation. | D-07 flag + scholar review. |
| R-09 | No analytics → hard to measure success metrics. | Blind product decisions. | OQ-01. |
| R-10 | Trademark use of bank names/logos. | Store rejection / legal. | OQ-09. |
| R-11 | Spec marketing ("we didn't build a server at all", Campaign #3) is no longer true. | Trust damage if claimed. | Reword to "your financial data never leaves your phone"; store privacy labels must declare backend data (install ID, purchases, optional account). |
| R-12 | Backend adds operating cost, on-call and security exposure. | Cost / outage / breach. | Minimal data held (BR-SYNC-03); app works when backend is down (NFR-BE-01). |
| R-13 | Contributed merchant names could contain personal names or data. | Privacy leak. | BR-SYNC-04 filters, k-anonymity threshold (A-48), operator review. |
| R-14 | ~~Free users lose all data when changing phones.~~ Mitigated by D-33 (one free cloud backup). | — | — |
| R-18 | Institution list (≈ 80 institutions incl. proposed) is large for a full-scope launch on two platforms. | Schedule; parse quality. | M/S priorities in `institutions.md`; S rows can ship in the first update; generic parser (FR-PAR-13) covers gaps. |
| R-15 | iOS can't read online-bank app notifications; Wise/Revolut/Monzo/bunq/N26 capture on iOS limited to Apple Pay, OCR and statements. | Weaker iOS experience for P-06. | Clear per-bank setup guidance; statement import; OCR templates for these apps' screens. |
| R-16 | Online banks change notification wording often and send them in the app's UI language. | Parse failures. | Review queue; templates per language; fixtures from real samples (OQ-04); prompt to use English in bank app. |
| R-17 | Per-currency reporting adds UI complexity for a mostly-EGP audience. | Confusing screens. | Currency UI appears only when a second currency exists (EC-55). |
| R-19 | Attestation required on restore (D-46) locks out legitimate buyers whose device can't attest (rooted, custom ROM, no Play services, App Attest unsupported) or when the attestation service is down; attestation quotas/cost. With one seat per purchase (D-52), a legitimate owner with two phones (e.g. Android + iPhone) can use Gold on only one, and a refused restore on a new phone leaves the owner without Gold until support acts. | Paying users lose Gold after a phone change; support load; store complaints and refund requests. | Clear help copy showing why and the next-move date; refused restores not counted as moves; operator support path with audited manual move (FR-BE-08); "sign in on the buying phone" guidance (D-54); ADR-012 Amendment to define retry and outage behaviour and quota sizing. *(v1.6, D-55…D-60:)* same-iPhone reinstalls no longer spend the move (D-55), but **Android reinstalls and "Delete everything" do** — mitigated by a warning before deletion; the shorter offline window (7 days for a phone that lost Gold, D-60) and clock-rollback withholding can briefly withhold Gold from a legitimate holder whose clock jumps or who stays offline long — mitigated by "connect to check Gold" copy and the ≥ 5-day holder guarantee (FR-GOLD-04); a plan change from another phone moves Gold (D-59), which may surprise users — mitigated by clear copy at purchase. *(v1.7, D-62/D-63:)* a user who reinstalls on the same iPhone more than twice in 30 days (e.g. while troubleshooting) spends the monthly move on the 3rd reinstall (D-63) — mitigated by help copy before reinstalling and a next-move date shown on refusal; *(D-65a)* the seat-holding iPhone is never locked out by the cap (Gold stays, only the window restarts), so the residual impact is a later next-move date, not loss of Gold — *(v1.8, D-66)* **except** when the Gold was bought on Android (Google Play) or under a different Apple ID: the iPhone has no App Store transaction to restore with, sign-in carries no App Attest (PO declined to add it), and the owner can be **refused on the holding iPhone for up to 30 days** after a 3rd reinstall within 30 days (accepted residual) — mitigated by showing the next-move date and the support path instead of Restore, a support move after the ownership check (support-lead unfreeze first if a dispute freeze is running), and help copy before reinstalling; iPhone seat keys make installs on the same iPhone **linkable by the backend in transit** (accepted by the PO, D-62) — mitigated by keyed-hash-only storage, no raw-key logging, and privacy-notice and store-label disclosure (NFR-PRIV-07); seat keys depend on Keychain/Secure Enclave items surviving app deletion — if a future iOS release clears them on delete, same-iPhone recognition falls back to Android-like behaviour (architect to verify, ADR-012 Amendment). |
| R-20 | OEM transfer tools (D-50) silently copy app data; user expects data to arrive and sees a fresh Welcome. | Perceived data loss. | Welcome offers restore from Zaghlol backup; backup reminders (FR-BAK-08); copy explains that only Zaghlol's own backup moves data. |
| R-21 | *(D-52, D-54)* Owners who change phones more than once a month (repairs, loaner phones, switching between Android and iPhone), lose a phone inside the cooldown, or reset/sell the buying phone before linking need a support move. | **Support load**; slow resolution frustrates paying users; manual moves are an abuse vector. | Support path and audited manual move (FR-BE-08); the operator admin app arrives after the first release (D-37), so an audited interim support procedure must exist at launch; clear in-app next-move date; prompt to sign in on the buying phone after purchase (FR-ACCT-01); monitor support volume after launch and revisit the 30-day window if needed. *(v1.6, D-56/D-57:)* ownership is proven by a **live store order-ID check** (order ID never stored), which lowers the abuse risk but means users must find their order ID (support copy must explain where: Google Play order history / Apple purchase history); **a single `support_agent` may act** without a second approver — accepted risk of insider error or abuse, mitigated by MFA, per-action audit rows (FR-BE-11), audited reversal, the 30-day "not seen" rule for support links, and notice to the phone that loses Gold; support moves **restart the window** (D-56), so a user who needs two support moves in a month will need support twice. The interim script-based procedure must enforce the same checks at launch. *(v1.7, D-64:)* a **30-day dispute freeze** after any support correction blocks further support moves and links on that purchase (corrections still allowed; freeze visible to support) — this limits "move-back ping-pong" between disputing parties and single-agent abuse, at the cost that a genuine owner whose correction was itself wrong may wait up to 30 days unless a further correction fixes it; the interim scripts must enforce the freeze too. *(D-65b:)* each new correction restarts the freeze, so repeated corrections can extend it — mitigated by auditing every correction and every refused support attempt (FR-BE-11), which makes ping-pong visible in review; the freeze never blocks the owner's self-service moves. |

## 14. Assumptions (to be confirmed at review)

| ID | Assumption |
|----|-----------|
| A-01 | Success-metric targets in §3.2 are proposals; the spec gives none. |
| A-02 | Personas derived from spec examples; no user research exists. |
| A-03 | ~~Egypt only; supported currencies EGP, USD, SAR, EUR.~~ Superseded by D-22. |
| A-04 | ~~Flags compile-time only.~~ Superseded: flags are remote via backend (FR-BE-05), default OFF. |
| A-05 | Saving "always apply" merchant rules is **Free** (spec Screen 5 shows it to everyone; spec §2 lists the "Always Apply Rule engine" as Gold). Recommended Free for growth and accuracy — **please confirm**. |
| A-06 | Free charts = Cash flow (1), Category donut (2), Top merchants top-5 (6), Budget progress bars (Screen 9). The spec's "Basic Budget Bar" is not one of the 12 charts. |
| A-07 | Ask Zaghlol chat and roast mode are Free (spec doesn't tier them). |
| A-08 | If biometrics unavailable, device passcode is used; no separate app PIN. |
| A-09 | §13's 16-screen set is canonical; §5's 14 screens' content maps into it. |
| A-10 | App lock re-prompts after 1 minute in background (configurable). |
| A-11 | Historical SMS scan depth default 6 months, user-selectable up to 24 months. |
| A-12 | Parse confidence threshold defined during Phase 3 from fixture results. |
| A-13 | New rules apply to future transactions and offer "apply to past N matching transactions" with a count. |
| A-14 | One voice log = one confirmed recording regardless of how many items it contains. |
| A-15 | Voice limit resets on the 1st of each calendar month, not on payday. |
| A-16 | Overall cycle budget defaults to sum of category limits; user may set a total instead. |
| A-17 | Gameya (جمعية) is entered manually (no SMS source). |
| A-18 | Roast-mode humour targets spending only; content reviewed in copy deck. |
| A-19 | Wealth asset list = spec §2/§11 types + car (spec §3 mentions car). |
| A-20 | Net-worth snapshot saved automatically at each cycle end and on demand. |
| A-21 | Smart ROI is a Gold feature (spec places it in "Smart Coach" tab without tier). |
| A-22 | Growth-first paywall frequency: max one unsolicited prompt per week. |
| A-23 | Backup encryption key derived from a user-chosen passphrase (needed for restore on a new device); Phase 3 decides KDF. |
| A-24 | Cross-platform restore supported via Google Drive (iCloud is iOS-only). |
| A-25 | Keep last 5 backups. |
| A-26 | Share cards hide amounts by default. |
| A-27 | Quiet hours 23:00–08:00 by default. |
| A-28 | Default language follows device; Arabic if device is Arabic. |
| A-29 | Arabic locale shows Arabic-Indic digits by default; user can switch to Western digits. |
| A-30 | Cross-channel duplicate window = 2 minutes. |
| A-31 | Credit card settlement is a transfer, not spend (purchases already counted). |
| A-32 | Refund matching window 60 days. |
| A-33 | 50/30/20 mapping in BR-CAT-02. |
| A-34 | Duplicate POS debit window 10 minutes. |
| A-35 | Subscription detection thresholds in BR-SUB-01. |
| A-36 | Liabilities in net worth include credit card balances and remaining BNPL installments. |
| A-37 | CD accrued interest is not added to value until paid out. |
| A-38 | ~~Offline Gold grace period 7 days.~~ *Superseded by D-60 (2026-11-06):* entitlement token 3 days + grace 4 days — a phone that lost Gold keeps it offline at most 7 days in total; the current holder keeps at least 5 offline days (FR-GOLD-04). |
| A-39 | Egyptian PDPL applies; legal review is outside this document. |
| A-40 | Performance targets in §9 are proposals. |
| A-41 | Phones only; no tablet-specific layouts. |
| A-42 | Budget cycle follows configured payday, not actual salary arrival date. |
| A-43 | Until the user sets a payday, the budget cycle is the calendar month (day 1). |
| A-44 | Catalog updates re-categorize only non-user-verified, catalog-categorized transactions (FR-SYNC-05). |
| A-45 | Reimbursement suggestion window: 7 days after the expense. |
| A-46 | Raw message text is included in backups (encrypted) so parsing can be re-run after app updates. |
| A-47 | For optional sign-in, the backend may store the email taken **only from the Apple/Google ID token's `email` claim** (Apple may give a relay address); used only for support lookup. For Sign in with Apple on Android, `scope=email` is requested and Apple's `user` field is never read (D-49). Lookups are audited with an HMAC pseudonym, kept 1 year (D-47). |
| A-48 | A contributed merchant needs ≥ 5 distinct installs before operator review. |
| A-49 | Late reimbursements restate the original expense's cycle. |
| A-50 | Backend retention: inactive installs deleted after 12 months; logs ≤ 30 days, IPs truncated. |
| A-51 | OWASP ASVS Level 2 as backend security baseline. |
| A-52 | Backend availability target 99.5%. |
| A-53 | Capacity sizing: 500k installs / 100k daily syncs in year 1. |
| A-54 | The "≈ in EGP" combined view is **off by default** (your instruction: no conversion), user can turn it on. |
| A-55 | Multi-currency tracking is Free (needed for correct capture); only foreign-asset tracking in Wealth stays Gold (§5.2). |
| A-56 | Wise, Revolut, Monzo, bunq and N26 notify payments via app push notifications, not SMS — to verify with real samples. |
| A-57 | Online-bank templates cover English notifications at launch (plus HDFC/Paytm SMS in English); other bank-app languages go to the review queue. |
| A-58 | Gold is priced per gram in EGP and USD; gold holdings are shown in grams and valued in the user's chosen gold-pricing currency (default EGP). |
| A-59 | Featured currencies: EGP, USD, SAR, EUR, AED, QAR, KWD, BHD, GBP, INR (GBP/INR added for Monzo/HDFC/Paytm). |
| A-60 | ≈ target currency selectable (default EGP). |
| A-61 | Cross-currency self-transfer suggestion: ±3% at day's rate, within 3 days. |
| A-62 | The ≈ view uses the **current** rate (not historical rates) for simplicity; labelled with rate date. |
| A-63 | Pending vs settled card notifications (e.g. Revolut) are merged into one transaction when merchant matches and amount differs by ≤ 5%. |
| A-64 | Rows marked *Proposed* in `institutions.md` (GCC banks beyond Al Rajhi/Emirates NBD, MNT-Halan, Khazna, Lucky, bank wallets) are in scope at **S** priority unless you strike them at approval. |
| A-65 | Free backup is first suggested after 7 days of data. |
| A-66 | "Always capture this sender" for generically parsed messages still sends each message to the review queue until the user has confirmed 3 parses from that sender. |
| A-67 | "One free backup" = one backup **slot** (the user can refresh it anytime), not a single lifetime backup. Reminder when older than 30 days. |

## 15. Open questions (non-blocking for approval unless marked)

| ID | Question | Owner | Needed by |
|----|----------|-------|-----------|
| OQ-01 | How will success metrics be measured without analytics? Options: store-console data only; anonymous aggregate counts on the backend (installs, daily syncs); in-app surveys. | Product owner | Phase 3 |
| OQ-02 | Which source for gold (24K/21K/18K EGP) and FX prices (7 currencies) will the backend use? Must be licensable for commercial redistribution. | Architect + product owner | Phase 3 |
| OQ-03 | Minimum Android and iOS versions. | Architect | Phase 3 |
| OQ-04 | **Can you provide anonymized real SMS / notification samples and PDF statements for each supported institution?** The spec's 53 samples look prototype-generated. | Product owner | Before Phase 5 parsing tasks |
| OQ-05 | Who compiles the full 600+ merchant seed list (spec lists ~150)? | Product owner / content | Phase 4 |
| OQ-06 | If offline Arabic speech isn't available on a device, may the app use the OS's online recognizer with explicit consent? | Product owner | Phase 3 |
| OQ-07 | What distinguishes "basic tips" (Free) from "deep coaching" (Gold) in chart explanations? | UX (Phase 2) | Phase 2 |
| OQ-08 | Should CSV import support other apps' formats (column mapping), or only Zaghlol's own? | Product owner | Phase 2 |
| OQ-09 | Are bank names/logos used in UI cleared for trademark use? | Product owner / legal | Before launch |
| OQ-10 | Who is the scholar / body to review Zakah rules, and the target date? | Product owner | Before enabling flag |
| OQ-11 | Final Gold prices. | Product owner | Before launch |
| OQ-12 | Operator tools: a small admin web app (recommended) or scripts/direct DB access? | Product owner | **Resolved (D-37)**: admin web app after the first release |
| OQ-13 | ~~Free backup?~~ **Resolved: D-33.** | — | — |
| OQ-14 | Later: on-device ML fallback for unrecognized message formats (competitors market "AI" parsing)? | Product owner | Post-launch |
| OQ-15 | Certificate pinning for the backend (stronger, but risky on certificate rotation)? | Architect | Phase 3 |
| OQ-16 | Backend hosting provider and region (Egyptian data-residency needs, if any, under PDPL). | Architect + product owner | Phase 3 |
| OQ-17 | ~~More online banks?~~ **Resolved: D-32**; confirm *Proposed* rows in `institutions.md` (A-64). | Product owner | At approval |
| OQ-18 | OQ-04 extended: anonymized real notification/SMS samples and statements for every institution in `institutions.md` (priority: M rows first). | Product owner | Before Phase 5 parsing tasks |
| OQ-19 | D-52 details for the architect: (a) how the backend recognises "the same phone" after an app reinstall or OS reset (a new install ID / new App Attest key), so that a same-phone restore is not counted as a move without adding any device identifier beyond BR-SYNC-03; (b) whether an audited support move restarts the 30-day window. Recommendation: (a) treat a reinstall as a new install unless the ADR finds a BR-SYNC-03-compliant signal, and say so in the help copy; (b) support move does **not** restart the window. NON-BLOCKING. | Architect + product owner | **Resolved 2026-11-06**: (a) **D-55** — iOS recognises a same-iPhone reinstall via a ThisDeviceOnly Keychain secret (derived proof only, BR-SYNC-03 amended); Android reinstall = new install, with a warning; (b) **D-56** — a support move **does** restart the window (recommendation not taken). Related: D-57…D-60. |
| OQ-20 | Gaps found while recording D-55…D-60: (a) **Plan change from another phone inside the 30-day cooldown** (D-59 says the payment is never blocked, but not where the seat goes when the monthly move is already used): does Gold still move (an extra move), or does it stay on the current holder with the next-move date shown? (b) Does the D-58 **free reclaim** count as the month's move (restart the 30-day window) or leave the window untouched? (c) **Signed-out holder of an account-linked purchase** (FR-ACCT-03 keeps the seat; FR-GOLD-08(e)/EC-65 require sign-in to receive it): does the signed-out holder keep *using* Gold, or keep the seat reserved but show Gold as paused until sign-in? Recommendation: (a) payment completes, Gold stays on the current holder, the app shows the next-move date and a support link — no extra move; (b) reclaim does not restart the window; (c) the holder keeps using Gold (sign-out never removes Gold from the phone that holds it). NON-BLOCKING (the architect can design for all options; copy depends on the answer). | Product owner | **Resolved 2026-11-06 (D-61)**: (a) as recommended — payment completes, Gold stays on the current phone, paying phone sees the next-move date; (b) **not as recommended** — the reclaim counts as the month's move and restarts the window (still bypasses a running cooldown); (c) **not as recommended** — Gold is paused on a signed-out holder of an account-linked purchase until sign-in; seat stays reserved, no move spent; unlinked purchases unaffected. |
| OQ-21 | Gaps found while recording D-62…D-64: (a) **Cap overflow when the month's move is already used (D-63).** A 3rd same-iPhone reinstall recognition "counts as the monthly move". If the move was already used (e.g. Gold moved to this iPhone 10 days ago), the literal reading is that the restore is **refused** — so the owner loses Gold on the very iPhone that holds the seat until the window ends or support acts. Is that intended, or does the seat holder keep Gold and only the window restart? (b) **Dispute-freeze scope (D-64):** does the freeze also block **self-service** moves (D-64 names only support moves/links)? Does a further correction inside the freeze **restart** the 30 days? Are support attempts refused by the freeze **audited**? Recommendation: (a) the iPhone that already holds the seat keeps Gold; the overflow restore restarts the 30-day window instead of being refused (avoids locking out the paying owner on their own phone); (b) freeze applies to support actions only, each correction restarts the freeze, refused attempts are audited (FR-BE-11). NON-BLOCKING (architect can build the counter, freeze and audit for either answer; copy and FR-GOLD-03 criteria depend on (a)). | Product owner | **Resolved 2026-11-06 (D-65)**, both as recommended: (a) the iPhone that holds the seat keeps Gold on an over-cap reinstall and the 30-day window restarts — never refused there, even if the month's move is used; an over-cap reinstall on an iPhone that does not hold the seat follows the normal move rules; (b) the freeze blocks support moves and links only (self-service rules unchanged), each new correction restarts it, refused support attempts are audited. |

## 16. Traceability to spec

| Spec section | Requirements |
|--------------|--------------|
| §1 Brand & mascot | FR-MAS, FR-L10N, NFR-UX |
| §2 Architecture & pay model | §5.2, FR-GOLD, FR-EXP, FR-BAK, NFR-PRIV |
| §3 Competitors & iOS | FR-ING-A, FR-ING-I, FR-VOI, FR-XFR, FR-WLT, FR-CHAT |
| §4 Categories | FR-CAT, BR-CAT |
| §5 Screens 1–14 | FR-ONB, ING, PAR, CAT, VOI, CHT, XFR, BUD, SUB, WLT, CHAT, GOLD, SHR |
| §6 Marketing campaigns | OOS-09 |
| §7 12 charts | FR-CHT, BR-BUD-04 |
| §8 SMS lab & regex | FR-PAR, BR-ING |
| §9 Stack & schema | Input to Phase 3 (not requirements); "zero backend" superseded by D-13 |
| v1.8 PO decision D-66, R5-9 wording, R6-1 | D-62 (R5-9 note), D-63/D-65 (marked by D-66), BR-SYNC-03 (element 0 on verify, `installs.seat_key_hash`), FR-GOLD-03/08, FR-BE-08 (unfreeze, separation of duties), NFR-PRIV-07, EC-69, R-19, glossary; ADR-012 Amendment R5-3 option (b) |
| v1.7 PO decisions (D-62…D-65) | D-48 (addendum), D-55 (marked), D-63/D-64 (marked by D-65), BR-SYNC-03 (`seatKeys[]`, time-nonce classification), BR-GOLD-07, FR-ONB-08, FR-GOLD-03/08, FR-ACCT-05 (support-link notice, freeze), FR-BE-08/11, NFR-PRIV-07, NFR-SEC-08, EC-65, EC-67…69, R-19, R-21, OQ-21 (opened, closed by D-65), glossary; ADR-012 Amendment to be revised |
| v1.6 PO decisions (D-55…D-61) | FR-GOLD-03/07/08, FR-ACCT-03/05, FR-BE-08/11, BR-GOLD-03/07, BR-SYNC-03 (+ D-48 addendum), NFR-PRIV-07, new NFR-SEC-08, A-38, EC-64…68, new EC-69…73, R-19, R-21, OQ-19 (closed), OQ-20 (opened and closed by D-61); ADR-012 Amendment to be revised |
| v1.5 PO decisions (D-52…D-54) | FR-GOLD-02/03/07/08/09, BR-GOLD-03/07, FR-ACCT-01/02/05, §5.1 R-04, EC-64…66, EC-68, R-19, R-21, OQ-19; ADR-012 Amendment to be revised |
| v1.4 PO decisions (D-45…D-51) | BR-SYNC-03, FR-GOLD-02/03/07/08/09, FR-SEC-05, FR-ACCT-02/04, FR-BE-11, FR-CUR-01/07, BR-MON-03, NFR-PRIV-07, A-47, EC-64…67, R-19/20, INT-22; ADR-012 Amendment (2026-11-05) |
| v0.4 review (D-32, D-33) | `institutions.md`, FR-PAR-01/13/14/15, FR-ING-A-07, FR-BE-10, FR-BAK-01…05/08/09, BR-BAK-02, BR-SYNC-03 |
| v0.3 review (D-25…D-31) | FR-CARD, FR-CAP, FR-CUR, FR-ING-A-07/08, FR-ING-I-08, FR-PAR-10…12, FR-ACC-06, FR-EXP-06/07, FR-CHT-05/06, FR-HOME-05, BR-CAP, BR-FX-02/03, P-06 |
| v0.2 review (D-13…D-24) | FR-ACCT, FR-SYNC, FR-BE, FR-SEC-03…08, FR-BAK-06…08, FR-XFR-06…09, FR-ONB-09…12, BR-MON-03, BR-XFR-05…08, BR-SYNC, BR-GOLD-05/06, NFR-BE |
| §10 Nav bar & animation | Input to Phase 2 |
| §11 Zakah | FR-ZAK, BR-ZAK |
| §12 Smart ROI | FR-ROI |
| §13 16 screens | A-09, Phase 2 |

## 17. Glossary

| Term | Meaning |
|------|---------|
| InstaPay (إنستاباي) | Egypt's instant payment network; addresses look like `name@instapay`. |
| IPA | Instant Payment Address (InstaPay handle). |
| BNPL | Buy now, pay later (valU, Sympl, Souhoola, Shahry, Aman, Forsa, Contact). |
| Gameya (جمعية) | Rotating savings circle among friends/family. |
| Shahada (شهادة) | Bank savings certificate (CD), e.g. 27% certificate. |
| 21K / 24K | Gold karat (purity 87.5% / 99.9%). |
| Nisab (نصاب) | Minimum wealth threshold for Zakah (85 g of 24K gold). |
| Hawl (حول) | One lunar year (354 days) an asset must be held before Zakah is due. |
| Payday cycle | Budget period from payday to the day before next payday. |
| Safe daily spend | Remaining budget ÷ remaining days in cycle. |
| Self-transfer | Money moved between two of the user's own accounts. |
| Roast mode (قصف الجبهة) | Humorous critique of spending. |
| Zaghlol Gold | Paid tier. |
| Reimbursement | Money a person sends back for their share of an expense the user paid (D-20). |
| Primary currency | The currency shown first in views (default EGP); never used to convert stored data. |
| ≈ view | Optional combined total converted to one currency at the latest rate, always labelled approximate. |
| Billed amount | The amount actually charged to a card in the card's currency, which may differ from the original purchase currency. |
| Ignore rule | A per-card (or per-institution) setting that discards SMS, notifications or Apple Pay events before anything is stored. |
| Online bank | App-first bank or money account (Wise, Revolut, Monzo, bunq, N26, Paytm, HDFC app) captured via notifications/statements. |
| Catalog | Shared, non-personal list of merchants, categories and keywords maintained by Zaghlol and synced daily. |
| Install ID | Random identifier generated by the app on first launch; not linked to the person or device hardware. |
| Entitlement | The backend-signed record that a user has Gold (plan + expiry). |
| RTDN | Google Play Real-time Developer Notifications. |
| ASSN V2 | App Store Server Notifications version 2. |
| Device attestation | A platform-signed statement that a request comes from a genuine, unmodified copy of Zaghlol on a real device: Play Integrity (Android) or App Attest (iOS) (D-45). |
| HMAC pseudonym | A keyed hash of a value (here the e-mail) that lets operators match records without storing the value itself (D-47). |
| Funds code | ISO 4217 code for a fund or accounting unit rather than circulating cash (e.g. BOV, CLF, UYW); shown last in the currency picker (D-51). |
| Seat key | On iOS, a Secure Enclave key pair created per Zaghlol install and kept on the iPhone across app deletion; sent as `{publicKey, signature}` (current + up to 4 earlier installs) on restore and sign-in so the backend can recognise a reinstall on the same iPhone (D-62); the current install's own key (element 0) is also sent on purchase verify. The server keeps only a keyed hash per purchase and a per-install keyed hash of the install's own key (`installs.seat_key_hash`, keyed with the install ID, deleted with the install) (v1.8, R5-9). A key registered through sign-in is not trusted as "same iPhone" (D-66). |
| Time nonce | A fresh random value the app sends with a request so the backend-signed server time in the reply is bound to that request (trusted time, NFR-SEC-08). Carries no device data. |
| Dispute freeze | 30 days after the latest support correction on a purchase during which further support moves or links on it are refused (and the refusals audited); corrections remain allowed and each restarts the 30 days; self-service moves are not affected (D-64, D-65b). A support lead other than the correcting operator can **unfreeze** (audited, moves nothing); that operator cannot then redo the protected move (FR-BE-08, R6-1). |

## 18. Approval

| Role | Name | Decision | Date |
|------|------|----------|------|
| Product owner | amr905 | ☑ Approved | 2026-11-01 |

On approval, Phase 2 (UI/UX design) may start.
