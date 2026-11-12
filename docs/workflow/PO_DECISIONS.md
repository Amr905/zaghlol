# PO decisions waiting on Amr

All open questions for the product owner, compiled 2026-11-13 from `LEAD_HANDOFF.md` ("Waiting on the PO"), the task files, `implementation-status.md` (FU-109, FU-112), SRS §15, `open-questions.md` and `copy-deck.md`. Answered questions are left out.
Groups run from most to least blocking. Where a default is listed, it is already in code or in the source note; replying "confirm" is enough. Source files hold the full wording.
Note: the seed rows OQ-01…OQ-12 in `docs/01-requirements/open-questions.md` are still marked OPEN but are superseded by SRS §15 and the D-decisions; only their still-open parts appear below.

| Group | Count |
|-------|-------|
| A. Blocks a task ready to build now | 7 |
| B. Provisional default in code, confirm or change | 45 |
| C. Inputs, accounts and devices only the PO can supply | 26 |
| D. Copy and brand wording | 11 |
| E. Housekeeping | 2 |
| **Total** | **91** |

## A. Blocks a task that is ready to build now (7)

| ID | Question | Options | Default / recommendation | Blocks |
|----|----------|---------|--------------------------|--------|
| FU-109 M-1 | Should SMS from phone-number senders the user adds be scanned for history (up to 25 months)? | Live only / live + opt-in 3-month scan / full history | Lead: live capture with financial-looking filter, consent text, separate opt-in 3-month scan, never put their unparsed messages in review | T-048 |
| FU-112 Q1 | Purchases verified before T-132 have no seat row: backfill them in T-132? | Backfill in T-132 / leave unseated | None given | T-132 |
| FU-112 Q2 | Verify on a vacant seat with no new payment: seat stays vacant? | Stays vacant / claims seat | Stays vacant (as built) | T-184, T-185 |
| T-136 Q1 | Which operator sign-in provider? | Entra ID (needs token lifetime <= 60 min) / Google Workspace (needs a design change) | "Decide later" | T-136 close, T-186 go-live (FU-060 S-4) |
| T-136 Q2 | Which tenant owns the `zaghlol-ops` and admin-app client registrations (and staff count)? | Name the tenant | None | T-136 AC4 (R3-9), T-186 |
| R6-1 (T-186) | Unfreeze rule: enforce server-side (different operator, 24 h lock) or use disjoint role assignments? | Server-side R6-1 / disjoint roles | Server-side R6-1 | T-186 |
| D-41 | Which local Egyptian gold-price provider (and FX licence)? | Provider contract | TBD; fake provider only for now | T-127 go-live |

## B. Provisional default already in code (45)

| ID | Question | Options | Default | Blocks |
|----|----------|---------|---------|--------|
| T-035 Q1 | Unreadable user capture rules: keep bank messages with bundled rules or drop all? | Keep with bundled / drop all | Keep with bundled (`keepWithBase`) | none |
| T-035 Q2 | Message with an OTP and a transaction is dropped? | Drop / keep | Drop | none |
| T-035 Q3 | Rate limit of kept messages per sender per minute; lost notifications unrecoverable? | 20 / other | 20 | none |
| T-035 Q4 | After Gold lapses, still capture senders of custom templates? | Capture as review / drop | Capture | none |
| T-035 Q5 | iOS per-card "SMS" toggle also governs Shortcuts messages? | Yes / separate toggle | Yes | none |
| T-035 Q6 | Drop bank promos only where the bank has promo patterns? | Per-bank only / global list | Per-bank only | none |
| T-039 Q1 / T-040 Q1 | Share of the waiting-messages store for unknown senders and bank SMS | 50 % unknown, 10/min; SMS 80 % / other | 50 %, 10 per min, SMS 80 % | none |
| T-043 Q2 / T-047 Q3 | Read notifications from apps the user adds (not only registry apps)? | Allow with deny list, confirm, cap 10 / registry only | Allow, cap 10 | none |
| T-043 Q3 | Notifications missed while the listener is down: accept or re-read the shade on reconnect? | Accept / re-read | Accept | none |
| T-041 Q1 | Show the user messages held in the spool but not storable? | Show in capture settings / diagnostics only | Diagnostics count only, no UI | none |
| T-047 Q1 | Home banner on a Play build without the SMS exception? | `home_banner_smsOff` / other banner / degraded card only | Mode only, no banner | T-047 |
| T-047 Q4 | Banner stacking when several issues are active (see T-047)? | One at a time with priority / stack | None | T-047 |
| T-046 Q1 | Merge a bank notification without a card number into the same-bank SMS within 2 minutes? | Yes / no | Yes | none |
| T-046 Q2 | Identical message from same sender stored once (two equal rides become one)? | Keep rule / count later copies as new | Keep rule | none |
| T-046 Q3 | Account for an "always capture" unknown sender? | New account per sender / default cash / ask | Account per sender | none |
| T-051 Q1 | First explicit payday re-buckets all past data? | Re-bucket / treat as mid-cycle change | Re-bucket | none |
| T-051 Q2 | Un-paired transfer out counts as spend, transfer in and unmatched refund as income, fee as spend? | Yes / no | Yes | none |
| T-051 Q3 | Safe-to-spend shown as whole pounds or with piastres? | Whole (314) / 314.28 | Whole, rounded down | none |
| T-051 Q4 | With no budget, fall back to income target for safe-to-spend? | Fall back / hide | Hide | none |
| T-051 Q5 | Budget after a mid-cycle payday change (10 or 40 days): keep full or prorate? | Full / prorate | Full | none |
| T-075 PO-1 | What is a "contributed alias" for the 0.88 fuzzy tier? | Backend flag / institution / none | Off | none |
| T-075 PO-2 | Treat counterparty kind `person` as person-to-person (no catalog)? | Yes / no | Yes | none |
| T-075 PO-3 | Fuzzy match only for keys of 6+ characters, ambiguity margin 0.02? | Confirm / change | As written | none |
| T-019 Q1 | Allowed `assets.payout` values and `rate_bp` cap 100 000 (see T-019)? | Confirm against Egyptian certificates | monthly/quarterly/semi_annual/annual/at_maturity | wealth task |
| T-019 Q2 | `zakah_ledger.due_on` Gregorian and `lot_start_hijri` Hijri format OK (see T-019)? | Confirm | As built | Zakah engine |
| T-019 Q3 | Can OCR/share/paste senders be "always captured" (see T-019)? | Yes / no | Only sms, notification, shortcut_message | none |
| T-019 Q4 | Vocabulary for `price_quotes.per_unit` (see T-019)? | Fix list | Free slug (`g`) | price sync task |
| T-020 | Confirm the default value of each settings key (see T-020, A-10/27/29/43/54) | Confirm / change | As built (29 keys) | none |
| T-025 | Feature flags read OFF after 14 days without sync (5-minute clock tolerance)? | 14 d / other | 14 days | none |
| T-112 | Allow a manual FX-rate override (needs a schema change and new task)? | Price-only / add FX override | Price-only | none |
| T-130 Q3 / T-131 Q4 | Sandbox and license-tester purchases in production grant Gold? Public TestFlight link? | Grant, recorded as sandbox / refuse | Grant (`AllowSandbox = true`) | go-live |
| T-131 Q5 | Family Sharing off for Gold products? | Off / on | Off (`PURCHASE_NOT_OWNED`) | go-live |
| T-131 Q7 | Offer codes or promoted purchases at launch (buyers go through restore)? | Yes / no | None | go-live |
| T-131 R5-3 | Does iOS sign-in carry an App Attest assertion? | (a) yes, in T-181 / (b) no | (b) | T-131, T-181 |
| T-133 Q3 | Voided purchases: refund without revoke keeps Gold until Play ends it; lifetime refund removes Gold; Gold returns if Play reverses? | Keep / remove at once | Keep until ended (warn after 40 min); yes; yes | go-live |
| T-133 Q4 | Never answer `pendingRefundReviewNotification` (no usage data sent)? | Never answer / answer | Never answer | go-live |
| T-134 Q3 | Ignore Apple `CONSUMPTION_REQUEST` (no usage data sent)? | Ignore / answer | Ignore | go-live |
| T-134 Q4 | Gold returns automatically on `REFUND_REVERSED`? | Yes / no | Yes | go-live |
| T-148 Q1 | After a passphrase change, keep old backup versions (labelled) or delete after confirmation? | Keep / delete | Delete after confirmation | release |
| T-148 Q3 | Fold Arabic-Indic digits so the passphrase opens the same backup? | Yes / no | Yes | release |
| T-182 Q1 | If `K_seat` is compromised, rotate (clears seat-key hashes; iPhones lose same-device recognition once) or keep the old key? | Rotate / keep | Rotate as incident procedure | none |
| OQ-08 | Support CSV import from other apps (column mapping) or only Zaghlol CSV? | Zaghlol only / add mapping | Zaghlol CSV only (FR-EXP-03) | none |
| OQ-11 | Final Gold prices | Price list | 49 / 399 / 899 EGP (seed) | launch |
| OQ-14 | Later: on-device ML fallback for unrecognized messages? | Post-launch / never | Post-launch | none |
| OQ-17 | Confirm the "Proposed" rows in `institutions.md` (A-64) | Confirm / edit | As proposed | approval |

## C. Inputs, accounts and devices only the PO can supply (26)

| ID | Question | Options | Default / note | Blocks |
|----|----------|---------|----------------|--------|
| T-130 Q1 | Create the Play Console service account (two permissions); workload identity or JSON key? | WIF / JSON key | None | T-130 go-live |
| T-130 Q2 | Confirm package name; monthly and yearly are separate subscriptions, lifetime is one-time | Confirm | As assumed | T-130 go-live |
| T-130 Q4 / T-133 Q6 | Confirm Play API daily quota (and `WorkerShare 0.2`) | Number | 200 K/day | T-130, T-133 |
| T-130 Q5 | Who provides a license-tester account and test order, runs the `orders.get` smoke test? | Name and date | None | T-130 AC5 |
| T-131 Q1 | Create the App Store Connect In-App Purchase key; who and when? | Name and date | None | T-131 go-live |
| T-131 Q2 | iOS bundle ID and Apple Team ID | Values | None | T-131 go-live |
| T-131 Q3 | Confirm one subscription group, lifetime non-consumable, Billing Grace Period length | Confirm | None | T-131 go-live |
| T-131 Q6 | Sandbox testers and one real production order ID | Names | None | T-131 smoke test |
| T-133 Q1 | Who creates the Pub/Sub topic and push subscription, and sets it in Play Console? | Owner | T-140 IaC owner | T-133 go-live |
| T-133 Q2 | Which project hosts the push service account; who holds `actAs`? | Project, person | `zaghlol-rtdn-push` as proposed | T-133 go-live |
| T-133 Q5 | Who sends a Play test notification to staging for the recorded vector? | Name | Test skipped | T-133 vector |
| T-134 Q1 | Apple Sandbox Server URL: production or staging backend; who configures? | Production / staging | None | T-134 go-live |
| T-134 Q2 | Who runs `Request a Test Notification` once for the recorded vector? | Name | Test skipped | T-134 vector |
| T-148 Q2 | Reference low-end Android phone for the key-derivation budget; is 4 s typical, 8 s worst acceptable? | Model | p50 4 s, p95 8 s | release, T-171 |
| T-008 Q1 | Which Samsung A-series and Xiaomi/Redmi phones, and a second SIM, for SPK-01? | Models | None | SPK-01 |
| T-159 | Place `tesseract4android-4.9.0.aar` in `C:\Projects\Zaghlol\` | File | None | T-159 |
| FU-044 | Supply the four IBM Plex Sans Arabic TTFs | Files | Goldens use Ahem | T-024 |
| OQ-04 / OQ-18 | Anonymized real SMS, notification and PDF samples per institution (synthetic-able; see T-031) | Samples | None | T-031, T-156, T-157 |
| T-088 | Produce `zaghlol.riv` from the vector rig | File | None | T-099 |
| T-059 (OQ-05, T-075 PO-4) | Compile the 600+ merchant list; Egyptian reader reviews the El Ezaby aliases | Owner | None | T-059 |
| OQ-16 / BLK-04 | Hosting provider and region, and PDPL licence decision | Provider, region | None | T-140 |
| OQ-10 | Who is the Zakah scholar or body, and the target date? | Name, date | None | zakah flag |
| T-165 | Run the device check for backup exclusion | Run | None | T-165 close |
| T-015 | Device checklist: StrongBox phone, iPhone reboot and background read before unlock | Run | None | T-015 close |
| T-060 | Manual steps (FU-067) | Run | None | T-060 close |
| T-007 | Timings on a reference Android phone and an iPhone 12 | Run | None | T-007 close |

## D. Copy and brand wording (11)

| ID | Question | Options | Default | Blocks |
|----|----------|---------|---------|--------|
| Q-17 | Use «التنبيهات» for Zaghlol's own alerts and «الإشعارات» for captured apps' notifications? | Confirm split / one word | Proposed split | glossary |
| Q-20 | Add a short "not financial advice" line under chart tips (S-21)? | Yes / no | No disclaimer | S-21 |
| Q-23 | Approve Zakah and Smart ROI disclaimers; scholar sign-off on Zakah text | Wording | Drafts in copy deck | `zakah`, `smart_roi` flags |
| Q-24 | Mention "halal" in idle-cash rule 4? Who owns the example-rate table? | Mention / no | General wording, no halal claim | S-51 |
| Q-25 | Approve the "essential" categories never roasted and `chat_roast_gentle` conditions | List | Rent, bills, groceries, health, education, fees, debt, work transport | S-50 |
| Q-33 | Notification redaction scope: also hide category name on budget alerts? | Keep / hide | Keep category | notifications |
| Q-36 | Confirm the subscription renewal line wording and where it must appear | Legal wording | Draft `gold_paywall_renewal` | S-68 |
| Q-44 | Wording for the one-time "old data couldn't be opened" Welcome line (AR, EN, restore action) | Copy | None | S-01 |
| OQ-09 | Are bank names and logos cleared for trademark use? | Cleared / remove logos | Not cleared | launch |
| T-047 Q2 / T-039 Q2 | Copy and placement for "some notifications were missed (N)"; dismissible? | Copy | Silent catch-up for SMS | T-047 |
| T-047 Q5 | What rule screens say when a rule is saved but the native filter is not yet updated | Copy | TBD | T-047 |

## E. Housekeeping (2)

| ID | Question | Options | Default | Blocks |
|----|----------|---------|---------|--------|
| Branches | Delete leftover branches: `ci/*` (T-040, T-184, FU-030, T-016/17/18, T-008, T-131, T-134, T-148, T-038, T-039, T-133, T-133-neg), `task/T-040-negproof-a..d`, `task/T-130-negproof`, `task/T-003-throwaway-red`, `task/T-165-proof`, `task/T-004-scratch`, `task/T-004-negctl`, `task/T-007-proof*`, `task/T-015-proof-*`, `review/batch-9*`, `scratch/*` | Delete | Agents cannot delete through the proxy | none |
| PC runner | Keep Docker Desktop (Linux containers, 10 GB `.wslconfig`) and `START-LOCAL-CI.cmd` running; restart the runner after a new `runner.ps1` | Keep running | None | local CI |
