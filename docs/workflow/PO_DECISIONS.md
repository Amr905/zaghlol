# PO decisions

Compiled 2026-11-13. On 2026-11-13 the PO delegated every decision with a sound default or a clear engineering/privacy answer to the Lead, keeping money, legal, accounts, devices and religious sign-off. **Part 1 is decided** and binds builders: a task's builder applies the rows for its task. **Part 2 still needs Amr.** Full wording of each question is in the source file named in the ID.

## Part 1 — Decided by the Lead (2026-11-13, PO delegation)

### Blocking decisions

| ID | Decision | Why |
|---|---|---|
| FU-109 M-1 (T-048) | Phone-number senders the user adds: **live capture only**, and only messages that look financial (amount + currency or bank keywords); a consent line when the sender is added; a **separate opt-in "scan the last 3 months"**, never 25 months; their unparsed messages never go to the review queue. | Personal SMS must not be swept in by default (non-negotiable 1/6 spirit). |
| FU-112 Q1 (T-132) | T-132 **backfills** a seat for every purchase verified before it, bound to the install that bought it, with no event-row cooldown and the reclaim unused. | Otherwise early buyers burn their move window and reclaim for nothing. |
| FU-112 Q2 | A verify on a vacant seat with no new payment **leaves it vacant** (as built); the owner gets it back through restore. | Restore is the intended recovery path; no silent grants. |
| R6-1 (T-186) | Unfreeze is **enforced server-side**: a different operator than the one who froze, after a 24 h lock. If only one operator exists, the unfreeze needs the break-glass procedure in the runbook. | Server rule can't be bypassed by role mistakes. |

### Defaults confirmed as built

T-035 Q1–Q6 (keep with bundled rules; drop OTP+transaction messages, as the real debit SMS follows; 20 per sender per minute; keep capturing custom-template senders after Gold lapses, as review items; iOS per-card SMS toggle also governs Shortcuts; promo drop per bank only) · T-039 Q1 / T-040 Q1 (unknown senders 50 % and 10/min; SMS 80 % of the spool) · T-043 Q2 / T-047 Q3 (user-added notification apps allowed, with the messaging-app deny list, a confirmation, cap 10) · T-043 Q3 (missed notifications while the listener is down are accepted, not re-read) · T-041 Q1 (unstorable held messages: diagnostics count only) · T-047 Q1 (no home banner on a Play build without the SMS exception; degraded mode only) · T-046 Q1–Q3 (merge card-less notification into same-bank SMS within 2 min; identical message from the same sender stored once, the second marked `low_confidence` "possible duplicate"; one account per always-capture sender) · T-051 Q1–Q5 (first payday re-buckets the past; unpaired transfer out = spend, transfer in / unmatched refund = income, fee = spend; safe-to-spend in whole pounds rounded down; hidden when there is no budget; budget kept full after a mid-cycle payday change) · T-075 PO-1–PO-3 (contributed-alias tier off; `person` counterparties skip the catalog; fuzzy only for keys of 6+ chars, margin 0.02) · T-019 Q1–Q4 (payout list monthly/quarterly/semi_annual/annual/at_maturity with `rate_bp` cap 100 000; Gregorian `due_on`, Hijri `lot_start_hijri`; OCR/share/paste can't be always-captured; `per_unit` stays a validated slug) · T-020 (all 29 setting defaults) · T-025 (flags read OFF after 14 days without sync) · T-112 (no manual FX override) · T-131 R5-3 (b: iOS sign-in carries no App Attest assertion) · T-133 Q3–Q4 and T-134 Q3–Q4 (refund without revoke keeps Gold until the store ends it; lifetime refund removes Gold; Gold returns on reversal; never answer refund-review / consumption requests, so no usage data leaves) · T-148 Q1 and Q3 (old backups deleted after a passphrase change, only after the user confirms; Arabic-Indic digits folded in the passphrase) · T-182 Q1 (rotate K_seat on compromise, as an incident procedure) · OQ-08 (Zaghlol CSV import only at launch) · OQ-14 (on-device ML fallback post-launch) · OQ-17 (institutions.md "Proposed" rows confirmed; corrections later go through catalog sync) · T-130 Q4 / T-133 Q6 (Play API quota 200 K/day, `WorkerShare 0.2`).

### Changed or newly set by the Lead

| ID | Decision |
|---|---|
| T-047 Q4 | One banner at a time, by priority: data at risk (backup/key problems) > capture off > notifications missed > info. The others wait in capture settings. |
| T-130 Q3 / T-131 Q4 | Sandbox and license-tester purchases in production grant Gold, recorded as sandbox (as built). **No public TestFlight link**: invite-only testers. |
| T-131 Q5 | Family Sharing **off** for Gold products. Apple doesn't let you turn it off again once on, so off is the reversible choice. |
| T-131 Q7 | No offer codes or promoted purchases at launch. |
| T-134 Q1 | Apple's Sandbox Server URL points to the **staging** backend; T-140 scripts it. |
| T-133 Q1–Q2 | T-140 (infrastructure as code) creates the Pub/Sub topic, push subscription and `zaghlol-rtdn-push` service account in the backend's own project; Amr only pastes the topic name into Play Console (Part 2). |
| T-148 Q2 (budget) | Key-derivation budget p50 4 s, p95 8 s on the reference phone is accepted. (The phone itself is in Part 2.) |
| T-059 / OQ-05 | An agent drafts the 600+ merchant list from public sources; an Egyptian reader (T-058) reviews names and aliases including El Ezaby. |
| Q-17 | Split confirmed: «التنبيهات» for Zaghlol's own alerts, «الإشعارات» for captured apps' notifications. |
| Q-20 | No "not financial advice" line under chart tips (they describe the user's own data). |
| Q-24 | Idle-cash rule 4 makes no "halal" claim; general wording. Example rates come from the catalog. |
| Q-25 | Essential categories never roasted: rent, bills, groceries, health, education, fees, debt, work transport (as proposed). |
| Q-33 | Budget alerts keep the category name, but follow the user's lock-screen redaction setting like every notification. |
| Q-44, T-047 Q2, T-047 Q5 | `ux-designer` writes the copy in the voice guide; reviewed in T-058. Placement: Q-44 one-time Welcome line with a "restore" action; missed notifications as a dismissible card in capture settings (and the lowest-priority home banner); rule saved but not yet active as "اتحفظت — هتشتغل خلال ثواني" / "Saved — active in a few seconds". |

## Part 2 — Still needs Amr

### Business and legal

| ID | What's needed | Blocks |
|---|---|---|
| T-136 Q1 | Support staff sign-in: Microsoft Entra ID (fits the design; needs a ≤ 60-min token policy) or Google Workspace (needs a design change). Pick the one your company already uses. | T-136 close, T-186 go-live |
| T-136 Q2 | The tenant that owns the sign-in app registrations, and how many support staff (fewer than 2 means unfreeze uses break-glass, R6-1). | T-136, T-186 |
| D-41 | Local gold-price provider and FX data licence (a contract). The fake provider covers development. | T-127 go-live |
| OQ-11 | Final Gold prices (seed: 49 / 399 / 899 EGP monthly / yearly / lifetime). | launch |
| OQ-16 / BLK-04 | Hosting provider and region, and the PDPL licence decision (needs legal advice). | T-140 |
| OQ-09 | Trademark clearance for bank names and logos; until cleared, logos stay out. | launch |
| Q-36 | Legal sign-off on the subscription-renewal wording and placement (draft `gold_paywall_renewal`). | S-68 |
| OQ-10, Q-23 | Zakah scholar or body, target date, and sign-off on the Zakah and Smart ROI disclaimers. Both features are flagged off at launch, so this doesn't block launch. | `zakah`, `smart_roi` flags |

### Accounts and store setup

| ID | What's needed | Blocks |
|---|---|---|
| T-130 Q1–Q2 | Play Console: service account with two permissions (Workload Identity preferred over a JSON key); confirm the package name and the product setup (monthly and yearly subscriptions, one-time lifetime). | T-130 go-live |
| T-130 Q5 | A license-tester account and one test order for the smoke test. | T-130 AC5 |
| T-131 Q1–Q3, Q6 | App Store Connect: In-App Purchase key; bundle ID and Team ID; confirm one subscription group, a lifetime non-consumable and the Billing Grace Period length; sandbox testers and one real order ID. | T-131 go-live |
| T-133 Q1 (your part) | Paste the Pub/Sub topic into Play Console once T-140 creates it. | T-133 go-live |
| T-133 Q5, T-134 Q2 | Send one test notification from Play Console and one from App Store Connect, to record the test vectors. | test vectors |

### Files and devices

| ID | What's needed | Blocks |
|---|---|---|
| OQ-04 / OQ-18 | SMS, notification and PDF samples per bank, with real numbers changed (we only need the shape). | T-031, bank templates, T-156, T-157 |
| T-159 | `tesseract4android-4.9.0.aar` in `C:\Projects\Zaghlol\`. | T-159 |
| FU-044 | The four IBM Plex Sans Arabic TTF files. | T-024 |
| T-088 | `zaghlol.riv` mascot file. | T-099 |
| T-148 Q2, T-007, T-008 Q1 | Name a reference low-end Android phone (and an iPhone 12), plus a Samsung A-series and a Xiaomi/Redmi with a second SIM for SPK-01. | release timings, SPK-01 |
| T-165, T-015, T-060 | Run the device checklists (backup exclusion; StrongBox phone; iPhone reboot and read before unlock; FU-067 steps). | closing those tasks |

### Housekeeping

| ID | What's needed |
|---|---|
| PC runner | Start Docker Desktop and `START-LOCAL-CI.cmd` (silent since 2026-11-11 22:29). Optional now: builders don't wait for it. |
| Branches | Delete leftover branches: `ci/*` (T-040, T-184, FU-030, T-016/17/18, T-008, T-131, T-134, T-148, T-038, T-039, T-133, T-133-neg), `task/T-040-negproof-a..d`, `task/T-130-negproof`, `task/T-003-throwaway-red`, `task/T-165-proof`, `task/T-004-scratch`, `task/T-004-negctl`, `task/T-007-proof*`, `task/T-015-proof-*`, `review/batch-9*`, `scratch/*`. |
