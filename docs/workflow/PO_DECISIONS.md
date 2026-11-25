# PO decisions

Compiled 2026-11-13. On 2026-11-13 the PO delegated every decision with a sound default or a clear engineering/privacy answer to the Lead, keeping money, legal, accounts, devices and religious sign-off. **Part 1 is decided** and binds builders: a task's builder applies the rows for its task. **Part 2 still needs Amr.** Full wording of each question is in the source file named in the ID.

## Part 1 — Decided by the Lead (2026-11-13, PO delegation)

### Blocking decisions

| ID | Decision | Why |
|---|---|---|
| MERGE (PO, 2026-11-21) | The Lead merges each batch PR into `main` (merge commit) once its review is APPROVED and its GitHub CI is green, **without asking the PO**. | PO: "merge any required branches and dont ask me again about merging branches". |
| FU-109 M-1 (T-048) | Phone-number senders the user adds: **live capture only**, and only messages that look financial (amount + currency or bank keywords); a consent line when the sender is added; a **separate opt-in "scan the last 3 months"**, never 25 months; their unparsed messages never go to the review queue. | Personal SMS must not be swept in by default (non-negotiable 1/6 spirit). |
| FU-112 Q1 (T-132) | T-132 **backfills** a seat for every purchase verified before it, bound to the install that bought it, with no event-row cooldown and the reclaim unused. | Otherwise early buyers burn their move window and reclaim for nothing. |
| FU-112 Q2 | A verify on a vacant seat with no new payment **leaves it vacant** (as built); the owner gets it back through restore. | Restore is the intended recovery path; no silent grants. |
| R6-1 (T-186) | Unfreeze is **enforced server-side**: a different operator than the one who froze, after a 24 h lock. If only one operator exists, the unfreeze needs the break-glass procedure in the runbook. | Server rule can't be bypassed by role mistakes. |
| DESIGN-0 (FR-ONB-03) | *(PO, 2026-11-14)* A fresh install opens in **Arabic** and the **light** theme, whatever the device language or theme; an explicit choice (including System) wins. | PO instruction; amends FR-ONB-03 ("device language until chosen"). |
| T-135 delete (batch-25a review) | The user's right to delete is **never blocked by Apple**. `DELETE /v1/accounts/me` always deletes the account and its links in the same request (204). If the Apple token revoke fails for any reason, only the re-sealed (encrypted) refresh token goes into `pending_apple_revocations` (no account, install or subject column) in that same transaction; a worker retries with exponential back-off (15 min, doubling, capped at 24 h) for **30 days**, then drops it. `invalid_grant` (already revoked) queues nothing. Nothing else about the account is kept. |

### Defaults confirmed as built

T-035 Q1–Q6 (keep with bundled rules; drop OTP+transaction messages, as the real debit SMS follows; 20 per sender per minute; keep capturing custom-template senders after Gold lapses, as review items; iOS per-card SMS toggle also governs Shortcuts; promo drop per bank only) · T-039 Q1 / T-040 Q1 (unknown senders 50 % and 10/min; SMS 80 % of the spool) · T-043 Q2 / T-047 Q3 (user-added notification apps allowed, with the messaging-app deny list, a confirmation, cap 10) · T-043 Q3 (missed notifications while the listener is down are accepted, not re-read) · T-041 Q1 (unstorable held messages: diagnostics count only) · T-047 Q1 (no home banner on a Play build without the SMS exception; degraded mode only) · T-046 Q1–Q3 (merge card-less notification into same-bank SMS within 2 min; identical message from the same sender stored once, the second marked `low_confidence` "possible duplicate"; one account per always-capture sender) · T-051 Q1–Q5 (first payday re-buckets the past; unpaired transfer out = spend, transfer in / unmatched refund = income, fee = spend; safe-to-spend in whole pounds rounded down; hidden when there is no budget; budget kept full after a mid-cycle payday change) · T-075 PO-1–PO-3 (contributed-alias tier off; `person` counterparties skip the catalog; fuzzy only for keys of 6+ chars, margin 0.02) · T-019 Q1–Q4 (payout list monthly/quarterly/semi_annual/annual/at_maturity with `rate_bp` cap 100 000; Gregorian `due_on`, Hijri `lot_start_hijri`; OCR/share/paste can't be always-captured; `per_unit` stays a validated slug) · T-020 (all 29 setting defaults) · T-025 (flags read OFF after 14 days without sync) · T-112 (no manual FX override) · T-131 R5-3 (b: iOS sign-in carries no App Attest assertion) · T-133 Q3–Q4 and T-134 Q3–Q4 (refund without revoke keeps Gold until the store ends it; lifetime refund removes Gold; Gold returns on reversal; never answer refund-review / consumption requests, so no usage data leaves) · T-148 Q1 and Q3 (old backups deleted after a passphrase change, only after the user confirms; Arabic-Indic digits folded in the passphrase) · T-182 Q1 (rotate K_seat on compromise, as an incident procedure) · OQ-08 (Zaghlol CSV import only at launch) · OQ-14 (on-device ML fallback post-launch) · OQ-17 (institutions.md "Proposed" rows confirmed; corrections later go through catalog sync) · T-130 Q4 / T-133 Q6 (Play API quota 200 K/day, `WorkerShare 0.2`).

### Changed or newly set by the Lead

| ID | Decision |
|---|---|
| PHONE-FEEDBACK-2 answers (PO, 2026-11-26 01:13) | Multi-currency: option C, hybrid (D-86); exchanged salary grows the EGP budget by the EGP received. The 1,558 receipt scan was on the latest main at the time: needs the dev "what I read" text from a build with PR #125. Mascot: the cut hand is seen in the app itself; the animation must appear in the app, not only in About (D-87) — Lead to propose places. |
| PHONE-FEEDBACK-2 (PO, 2026-11-25 evening) | Eleven stories in `docs/01-requirements/user-stories-2026-11-25.md` (US-P01…US-P11, tasks T-262…T-271): شهر instead of دورة (D-84); share image; camera capture; InstaPay title + person; card linked to account; receipt total cross-checks; mascot hand; statement import UI; backup export; foreign-currency salary is salary income (D-85). Multi-currency design waits for the PO's choice (`docs/02-design/multi-currency-options.md`). |
| SMS-V2 (PO, 2026-11-25) | Parsing v2 per `docs/03-technical/sms-parsing-v2-plan.md`. PO: Arab Bank threads `ArabBank` and `Arab Bank`; cases 1 and 5 of the PO suite are Arab Bank; due and statement SMS are kept as dues (D-83); a known bank's message that misses its templates may auto-save when the SMS-AUTO rule holds; the 12 cases go in the repo as synthetic copies. Lead assumptions A1–A3 in plan §8. |
| PAYDAY-AUTO (PO, 2026-11-25) | Payday follows the salary (D-81) and a cycle starting after day 20 belongs to the next month (D-82). Lead assumptions A4–A10 in `sms-parsing-v2-plan.md` §8 (±2 days, earliest wins; typed payday changed only when 3 months disagree; 29–31 → 28; primary currency only). |
| MASCOT-RIV-CODE (PO, 2026-11-23) | The PO has no paid Rive plan; the mascot file `zaghlol.riv` is generated from code (T-212) instead of in the Rive editor; simple motion is accepted; a human animator may polish the same file later (T-088 stays open for that). Rive runtime stays in the app (ADR-024 option F not taken). |
| CHARTS-V2 (PO, 2026-11-22) | *(PO approved the Charts v2 proposal, design canvas page "charts2"; mockups in `docs/02-design/mockups/charts-v2/`.)* Insights opens on three tabs: Overview / Categories / Trends. The T-189 charts screen stays, reached from "All charts (12)". Lead defaults: the hero pace card and "Coming up" are **free**; every other v2 card inherits the free/Gold gate of the existing chart it is built from (`chart_gate.dart`); a Gold-only card shows the existing locked-card treatment. Hero and pace line use the **primary currency**; other currencies with spending in the period are listed under the hero, each in its own currency, never summed (D-28). Period wording «شهر»; the period picker applies to all tabs. |
| CAT-INSTAPAY (PO, 2026-11-17) | InstaPay transfers (SMS, notification, manual; in and out) get a seeded "InstaPay" category (ar "إنستاباي", en "InstaPay") until the user changes it. A user-chosen category always wins and is never overwritten by re-parse or re-categorize. |
| CAT-CASH (PO, 2026-11-17) | ATM withdrawals get a seeded "Cash" category (ar "كاش", en "Cash"). Manual payments entered as paid in cash are part of cash already withdrawn, not extra spending: spending is counted when cash is withdrawn (Cash category); a later cash payment moves its amount from Cash into its own category (breakdowns, per-category budgets) without changing total spending while the user's unspent withdrawn cash (per currency, running pool across periods) covers it; any part beyond the pool is new spending. Delete/edit of a payment or withdrawal recomputes. Never mix currencies; integer minor units; no double counting (Home, Insights, budgets, cycle "left to spend"; exports keep raw rows). Implemented as a computed pool at the analytics/budget layer, no migration (docs/04-tasks/tasks/CAT-cash.md). |
| SMS-NODIGIT (PO, 2026-11-16) | A message that contains **no digit at all** (Western `0-9` or Arabic-Indic `٠-٩` / `۰-۹`, after the Guard's fold) is dropped by the Guard as `no_digit`, on every channel, before any sender or pattern check. It can't hold an amount, a card or a date. Applied the same in the Dart, Kotlin and Swift Guards (`packages/zaghlol_parsing/test/fixtures/guard/golden.json`, cases `nodigit.*`). |
| SMS-AUTO (PO, 2026-11-16) | Bank SMS are read and **saved automatically**; this replaces the old rule that generic (no-template) results never auto-save. A result auto-saves when the sender resolves to a registry bank, the amount and currency are read with no competing reading, the direction or event is clear (including a credit-card settlement, which is a transfer into the card account, never an expense or income) and a card last-4 or a merchant is present. Anything with currency or amount ambiguity (D-28), a missing or conflicting direction, an unknown sender or a promo/OTP cue goes to review. The review card shows the original message text (collapsible, on screen only, never logged). Stored review rows are re-evaluated once under the new rules after the registry version bump (re-parse job; never duplicates a saved transaction). |
| BANK-ACRONYM (PO, 2026-11-16) | When a bank's name does not fit its slot, the UI shows its English acronym (NBE, CIB, QNB, HSBC, BM...) from `acronym` in `assets/brand/institutions_brand.json`; the full name stays in the tooltip and semantics label. Money-tab account rows use `ZInstitutionAvatar` (FU-250). |
| CARD-DIGITS (PO, 2026-11-16) | Card and account numbers (last-4, masked) always show in Western digits, left to right ("•••• 5075"), even in Arabic, like the physical card (`core/l10n/card_number.dart`). Amounts and dates keep following the locale. |
| REVIEW-KEEP (PO, 2026-11-16) | Doubtful SMS review cards get "Keep" (احفظها): saves the transaction as parsed in one tap with haptics. Needs an amount, a known bank, a kind and a channel; otherwise it is disabled with a short reason. Edit and Ignore stay. Show/hide original message have their own keys. |
| CHARTS-FREE (PO, 2026-11-16) | All 12 charts are open in Free for now, through one switch `GoldGate.chartsOpenToFree` in `gating.dart`; set it to `false` to restore the Gold gate. Paywall copy no longer says charts are Gold-only. |
| T-047 Q4 | One banner at a time, by priority: data at risk (backup/key problems) > capture off > notifications missed > info. The others wait in capture settings. |
| T-130 Q3 / T-131 Q4 | Sandbox and license-tester purchases in production grant Gold, recorded as sandbox (as built). **No public TestFlight link**: invite-only testers. |
| T-131 Q5 | Family Sharing **off** for Gold products. Apple doesn't let you turn it off again once on, so off is the reversible choice. |
| T-131 Q7 | No offer codes or promoted purchases at launch. |
| T-134 Q1 | Apple's Sandbox Server URL points to the **staging** backend; T-140 scripts it. |
| T-133 Q1–Q2 | T-140 (infrastructure as code) creates the Pub/Sub topic, push subscription and `zaghlol-rtdn-push` service account in the backend's own project; Amr only pastes the topic name into Play Console (Part 2). |
| T-148 Q2 (budget) | Key-derivation budget p50 4 s, p95 8 s on the reference phone is accepted. (The phone itself is in Part 2.) |
| T-059 / OQ-05 | An agent drafts the 600+ merchant list from public sources; an Egyptian reader (T-058) reviews names and aliases including El Ezaby. |
| Q-17 | Split confirmed: «التنبيهات» for Zaghlol's own alerts, «الإشعارات» for captured apps' notifications. |
| FAB-MOCKUP (2026-11-17, PO) | The Android Add button is the floating apricot FAB of mockups 03/20 (bottom-end above the bar, 56 dp rounded square, apricot gradient, shadow, plus icon), not docked in the bar. Supersedes the batch-29 docked-FAB deviation (FU-246). Content clears it with `ZSpacing.fabClearance` on every tab. | The PO wants the agreed design; clearance solves the hidden-content problem. |
| Q-20 | No "not financial advice" line under chart tips (they describe the user's own data). |
| Q-24 | Idle-cash rule 4 makes no "halal" claim; general wording. Example rates come from the catalog. |
| Q-25 | Essential categories never roasted: rent, bills, groceries, health, education, fees, debt, work transport (as proposed). |
| Q-33 | Budget alerts keep the category name, but follow the user's lock-screen redaction setting like every notification. |
| T-132 Q1–Q3 | No earlier-holder history table: a former non-buying holder sees `none`, not `moved`, and still loses Gold within 7 days. An invalid/expired account token counts as absent (Gold shows `paused`) until T-135 adds `ACCOUNT_TOKEN_EXPIRED`. `plan:"none"` and whole-hour ISO `nextMoveAt` stand; T-144 confirms. |
| T-141 | The in-repo DTO generator (pinned, regenerated-file check in CI) replaces `openapi-generator-cli`. Production response-signing public keys come from T-140's key service (Lead), no PO action. |
| T-023 | Negative amounts use ASCII `-`. Non-EGP currencies show their ISO code in Arabic until UX defines symbols. |
| T-181 Q2 | Play Integrity calls have no separate budget counter: restore's 5/hour and 10/day limits cap them; T-140 adds a Google-quota alert. |
| T-052 | Safe-to-spend always uses all cards (budgets aren't per card); the card filter changes only spend figures and the feed. |
| T-185 Q1–Q3 | `movedFromOtherPhone` only when the seat came from another install; the per-purchase daily limit stays in memory while the API runs as one instance (T-140 go-live check); Android `attestation.seatKeys` → `VALIDATION_FAILED`. |
| T-089 | A manual unlink is remembered through resolved review items; losing it after the review-history purge is accepted for now. |
| T-094 / T-103 | Turning app lock on also turns on "hide amounts in notifications" (the user can turn it off). No alert type bypasses quiet hours yet. |
| T-103 | With app lock on and the phone's screen lock removed, the app stays locked and asks the user to set a screen lock (no bypass). |
| T-115 | The ≈ view rounds each converted currency once (half-even), then sums exactly; it is labelled ≈ whenever anything was converted or excluded. |
| T-154 | The Free export preview shows up to 20 rows. |
| T-103 | `local_auth` is dropped (it hung iOS app launch); the lock prompt is native: iOS `LAContext(.deviceOwnerAuthentication)`, Android `BiometricPrompt` (STRONG or DEVICE_CREDENTIAL on API 30+, WEAK or DEVICE_CREDENTIAL on 26–29). |
| T-076 | A re-parse never changes an existing transaction's amount or status and never writes a user-verified one; it only fills empty fields or promotes the raw row. |
| T-149 | A restore copies the backup under this phone's own database key (a key swap can't be atomic); the other phone's key never travels. |
| T-144 | A wall clock still wrong after a fresh server check stays "tampered" (fails closed); the copy tells the user to set the clock to automatic. |
| T-150 | Free/Gold count-based cleanup may remove a backup made under an old passphrase, but only once a newer verified backup exists. |
| T-090 | A refund larger than the matched expense counts the leftover as income; ambiguous refunds go to review as `reimbursement_suggestion` with `type: refund_ambiguous` (no migration). |
| T-096 | A card due is paid only by money coming into the card account; other recurring items keep their matching rules. |
| T-109 | `دينار` keeps the default currency with `ambiguousCurrency`; the voice UI asks. Missing spoken keywords go into the T-059 catalog seed. |
| Q-44, T-047 Q2, T-047 Q5 | `ux-designer` writes the copy in the voice guide; reviewed in T-058. Placement: Q-44 one-time Welcome line with a "restore" action; missed notifications as a dismissible card in capture settings (and the lowest-priority home banner); rule saved but not yet active as "اتحفظت — هتشتغل خلال ثواني" / "Saved — active in a few seconds". |
| T-076 | A re-parse never changes a stored amount; it may only fill missing fields or send the row to review. |
| T-115 | The ≈ view rounds each currency's converted figure before adding; any excluded currency keeps the figure labelled ≈ with a "not included" note. |
| T-110 | Safe-to-spend uses all cards; a credit/BNPL "balance" means the amount owed; a balance answer lists named accounts one by one and never adds assets and liabilities. |
| T-155 | CSV import skips duplicates and marks rows with unknown accounts invalid (never creates accounts). |
| T-147 | After an offline sign-out, account-linked Gold shows "paused" (not "free") until a fresh signed entitlement; S-69 shows a plain "Signed in" line, no e-mail. |
| T-152 | While the entitlement is still being verified, backup cleanup keeps up to 5 and the scheduled job is skipped, not cancelled. |
| T-080 | In the amount field a comma is accepted only as thousands grouping; `12,5` is rejected, never read as 125. |
| T-064 | The Wallet (Apple Pay) automation is flagged as silent only for users who have captured an Apple Pay payment at least once; the message automation is always checked. |
| T-082 | The quick-add sheet already existed (T-024); T-082 closes with the Gold badge on Asset (WIRE-3). The "voice logs left" line waits for the voice logger (T-120, deferred). |
| T-166 | Offline, the server install delete is not queued (a queue would keep the install token after the wipe); the server copy expires on its own, as the dialog says. A wipe resume deletes only unfinished parts, never data newer than the marker, and stops after 3 tries. |
| T-092 / WIRE-2 | A reimbursement or cross-currency suggestion links only the candidate the user taps; the card shows each candidate; no swipe-accept for pair suggestions. |
| NOTIF-GW | Local notifications use a small native host (no plugin, no remote push). Permission is asked after onboarding and on first enabling an alert type. A quiet-hours alert scheduled on Android is lost at reboot (keeps alert text off unencrypted storage). |
| T-173 | Timing tests run only in the serial `perf` CI job (one retry); budgets get tightened to about 1.3× the first CI numbers. |
| WEEKLY-FRIDAY (FU-204c) | *(PO, 2026-11-18)* The weekly summary is delivered on **Friday** (local time; quiet hours apply as for other alerts), once per Friday, covering the **seven days ending Thursday** (the design specs name no other window). | PO instruction. |
| OVERDUE-REMINDERS (FU-143) | *(PO, 2026-11-18)* An unpaid subscription or bill past its due date gets at most **two** reminders: **day+1 and day+3** (from 10:00 local); never more than one per item per day; none once paid, skipped or deleted, and none for card dues. Quiet hours and hide-amounts apply (redacted variant without the amount). Copy: `notifications_alert_overdue*` in the copy deck; the "Mark as paid" action goes through `markPaidManual`. | PO instruction. |

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
| FU-195-legal | **Draft ready — PO/legal review** (batch 54). `site/` holds Privacy (`/privacy/`), Terms (`/terms/`), Support (`/support/`), Manage subscription (`/subscription/`), Get (`/get/`) and a landing page, ar + en, with a removable "Draft" banner. Needed: legal review (PDPL 151/2020, Consumer Protection 181/2018), fill the `{{…}}` placeholders listed in `site/README.md` (company, address, registry, contact/support e-mail, DPO, hosting location, retention periods for purchases, bank requests and support tickets, helpdesk vendor, minimum age, prevailing language, courts, prices), then run `.github/workflows/site-pages.yml` (manual only) or serve from Caddy (`site/README.md`) and point DNS. **The 10 contradictions are resolved in the docs** (batch 54, table in [`docs/06-release/privacy-consistency.md`](../06-release/privacy-consistency.md)): (1) contributions carry the institution code; (2) e-mail from Google **and** Apple sign-in; (3) no certificate pinning (ADR-018); (4) consented OS online speech disclosed; (5) the server **stores** `accounts.email` until account deletion; (6) order ID kept only in helpdesk tickets; (7) BG-02 rewritten; (8) CLAUDE.md §1 wording **proposed, not applied** (Lead/PO to apply) and the paywall still lists `goldPaywallBenefitCharts` (follow-up); (9) `AppLinks.support` added; (10) retention table in the Data safety draft. **Still yours, with legal:** the "(confirm)" form classifications (audio via the OS recognizer, provider subject ID as User IDs, contributions as user content), retention for purchases, bank requests and tickets, and whether voice entry is in the launch build (C2). | Play Data safety, App Store, launch |
| T-181 / 181-1 | Before launch: confirm the Apple App Attestation root fingerprint. On your PC, download https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem and run `certutil -dump Apple_App_Attestation_Root_CA.pem`; the "Cert Hash(sha256)" must be `1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932`. | launch (iOS restore) |

### Accounts and store setup

| ID | What's needed | Blocks |
|---|---|---|
| T-130 Q1–Q2 | Play Console: service account with two permissions (Workload Identity preferred over a JSON key); confirm the package name and the product setup (monthly and yearly subscriptions, one-time lifetime). | T-130 go-live |
| T-130 Q5 | A license-tester account and one test order for the smoke test. | T-130 AC5 |
| T-131 Q1–Q3, Q6 | App Store Connect: In-App Purchase key; bundle ID and Team ID; confirm one subscription group, a lifetime non-consumable and the Billing Grace Period length; sandbox testers and one real order ID. | T-131 go-live |
| T-150 | Google Cloud: create the Android (package + signing SHA-1), iOS and web/server OAuth clients **in one project**, enable the Drive API, and list the `drive.appdata` scope on the consent screen. Send the iOS and server client IDs (not secrets). | Drive backup, T-147 sign-in |
| T-133 Q1 (your part) | Paste the Pub/Sub topic into Play Console once T-140 creates it. | T-133 go-live |
| T-133 Q5, T-134 Q2 | Send one test notification from Play Console and one from App Store Connect, to record the test vectors. | test vectors |

### Store release (T-176, T-177): accounts and secrets

Everything else is prepared (`docs/06-release/README.md`). Create the GitHub environments `android-release` and `ios-release` (Settings > Environments; required reviewer = you; deployment branches = `main` and `v*` tags) and put the secrets **in the environment**, not at repo level. The workflows build unsigned without them.

| ID | What's needed | Blocks |
|---|---|---|
| T-176 A1 | Google Play Console developer account (identity-verified) and the app `app.zaghlol` created; enrol in Play App Signing. | T-176 |
| T-176 A2 | Generate the **upload key** (keytool, RSA 2048+, keep an offline copy). Secrets `ANDROID_UPLOAD_KEYSTORE_BASE64` (base64 of the .jks), `ANDROID_UPLOAD_STORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`. | signed AAB |
| T-176 A3 | Play API service account JSON with release permission on the app (Workload Identity is not wired into the workflow; JSON key as secret `PLAY_SERVICE_ACCOUNT_JSON`). Can be the same service account as T-130. | Play upload |
| T-176 A4 | Variable (not secret) `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`: the Google Cloud project linked to Play Integrity (T-178). Without it attestation fails closed. | restore on Android |
| T-176 A5 | Play Console forms: Data safety (`docs/06-release/play-data-safety.md`), **SMS declaration** and the demo video (`play-sms-declaration.md`; you record or approve it), content rating, target audience, financial-features declaration. Decide the two (confirm) classifications in the Data safety draft with legal. | Play review |
| T-176 A6 | Real Terms, Privacy and support URLs (FU-195); the Data safety form cannot be completed without a privacy policy URL. | Play and App Store |
| T-177 B1 | Apple Developer Program membership, App Store Connect record for `app.zaghlol`, Team ID (secret `APPLE_TEAM_ID`). | T-177 |
| T-177 B2 | Register App IDs `app.zaghlol`, `app.zaghlol.ShareExtension`, `app.zaghlol.widget` with App Groups, Keychain sharing, iCloud (CloudDocuments), and Sign in with Apple (the entitlement is missing in `Runner.entitlements`: iOS engineer to add). Create three App Store distribution provisioning profiles. Secrets `IOS_PROFILE_APP_BASE64`, `IOS_PROFILE_SHARE_BASE64`, `IOS_PROFILE_WIDGET_BASE64`. | signed IPA |
| T-177 B3 | An Apple Distribution certificate exported as .p12: secrets `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`. (Needs a Mac once to export, or create it through Xcode cloud signing; say if you prefer `fastlane match` and a private certs repo instead.) | signed IPA |
| T-177 B4 | App Store Connect API key (role App Manager): secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`. | TestFlight upload |
| T-177 B5 | App Store Connect: App Privacy answers (`docs/06-release/app-store-privacy.md`), review notes, demo Apple ID for the reviewer, export-compliance answer, age rating, internal TestFlight testers. | App Review |
| T-176/177 C1 | Optional secret `SYMBOLS_PASSPHRASE` (a long random string) so the encrypted Dart symbols, R8 mapping and dSYMs are kept 14 days as workflow artifacts. The repo is public, so without it nothing is kept outside Play / App Store Connect. | crash deobfuscation |
| T-176/177 C2 | **Draft ready — PO review** (batch 54): `store-listing.md` now has the Play and App Store copy in ar and en (limits counted), the other listing fields and the screenshot shot list. Confirm the copy (native Egyptian review), `InstaPay` in keywords (OQ-09), and that voice entry stays out until T-120 ships. | store review |

### Files and devices

| ID | What's needed | Blocks |
|---|---|---|
| OQ-04 / OQ-18 | **PARTIAL** (round 1 received 2026-11-14: 38 banks/InstaPay/wallets/BNPL purchase shapes). Still needed: real ATM/salary/declined/FX wording, Shahry/Aman/Forsa/Contact, BNPL due/paid, statement PDFs/CSVs, notification formats. | T-031, bank templates, T-156, T-157 |
| T-159 | `tesseract4android-4.9.0.aar` in `C:\Projects\Zaghlol\`. | T-159 |
| FU-044 | **DONE**: fonts bundled by the Lead (OFL). | T-024 |
| T-088 | `zaghlol.riv` mascot file. | T-099 |
| T-148 Q2, T-007, T-008 Q1 | Name a reference low-end Android phone (and an iPhone 12), plus a Samsung A-series and a Xiaomi/Redmi with a second SIM for SPK-01. | release timings, SPK-01 |
| T-180 | Run the trusted-clock device checks in `docs/05-reviews/T-180-device.md` (sleep, Doze, reboot) on one Android phone and one iPhone, before T-144 ships. | T-144 |
| T-103 | Try the app lock on one Android phone and one iPhone: Face ID / fingerprint, then the passcode fallback. | T-103 sign-off |
| T-165, T-015, T-060 | Run the device checklists (backup exclusion; StrongBox phone; iPhone reboot and read before unlock; FU-067 steps). | closing those tasks |
| FU-223 | Confirm the guessed SMS sender IDs per bank. | bank templates |
| FU-195 | The real Terms, Privacy and support URLs (placeholders in `app/lib/app/app_config.dart`). **Draft ready — PO/legal review**: pages in `site/`, see FU-195-legal. | launch |
| FU-212 | The Shortcut file and the guide images. | iOS setup guide |
| Apple portal | Register the App Group and shared Keychain group for the app and its Share/Widget extensions. | iOS extensions |
| iOS builds | A Mac or a TestFlight path for iOS builds. | iOS release |

### Housekeeping

| ID | What's needed |
|---|---|
| PC runner | Start Docker Desktop and `START-LOCAL-CI.cmd` (silent since 2026-11-11 22:29). Optional now: builders don't wait for it. |
| Branches | Delete leftover branches: `ci/*` (T-040, T-184, FU-030, T-016/17/18, T-008, T-131, T-134, T-148, T-038, T-039, T-133, T-133-neg), `task/T-040-negproof-a..d`, `task/T-130-negproof`, `task/T-003-throwaway-red`, `task/T-165-proof`, `task/T-004-scratch`, `task/T-004-negctl`, `task/T-007-proof*`, `task/T-015-proof-*`, `review/batch-9*`, `scratch/*`. |
