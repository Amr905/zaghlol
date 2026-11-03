# Parallelization Plan

Tasks in the same **wave** have all their dependencies done at the same point and can run in parallel, one sub-agent each (CLAUDE.md §6.3: independent tasks may run in parallel; tasks touching the same files may not). Lanes show who works where.


## Lanes
| Lane | Owner | Tasks |
|---|---|---|
| A | App core/data (flutter-core) | 67 |
| B | Backend (.NET) | 21 |
| C | Content & assets | 8 |
| D | Native Android | 14 |
| E | Native iOS | 9 |
| F | Parsing & NLP (pure Dart) | 21 |
| G | UI (flutter-ui) | 37 |

## Big picture
- **Backend lane (B) is independent of the app** after M0 and can run from week 1 alongside M1–M4; only the app's `T-*` sync/Gold tasks in M5 need it.
- **Parsing lane (F)** is pure Dart and can run ahead of native capture: templates batches are fully parallel with each other.
- **Native Android (D) and iOS (E)** run in parallel; iOS starts after its spike.
- **Content (C)**: copy deck and merchant list start immediately; the Rive mascot is an external illustrator task feeding M3.
- External/blocked items: real SMS samples (OQ-04/18) gate fixture quality and PDF import; the gold-feed contract gates price go-live; **CR-03/OQ-16 gates cloud deployment only**.


## Critical path
T-001 (Create mono-repo scaffold with pub wor…) → T-007 (SPK-05: encrypted SQLite (SQLite3Multi…) → T-015 (Secure key bootstrap for the database …) → T-016 (AppDatabase v1 skeleton: encrypted ope…) → T-017 (Schema batch A: accounts, balances, ra…) → T-045 (Accounts repository: auto-create, defa…) → T-046 (IngestRawMessages use case (dedupe, me…) → T-089 (Self-transfer pairing, FX conversions …) → T-090 (Refund matching and offset links) → T-091 (Splits and reimbursements with allocat…) → T-105 (Chart query layer for all 12 charts) → T-106 (Explanation template engine (basic vs …) → T-108 (Chart detail with explanation S-21)

Length: 13 sequential tasks.


## Waves

### Wave 1 — 6 task(s)
- **A** (App core/data (flutter-core)): T-001 Create mono-repo scaffold with pub workspace, app flavors and pure-Dart packages
- **B** (Backend (.NET)): T-005 Backend solution scaffold, Docker Compose and CI
- **C** (Content & assets): T-026 Copy deck part 1: onboarding, capture, Home, transactions, review, accounts; T-027 Copy deck part 2: insights, budget, bills, money, chat, voice, roast, explanations; T-028 Copy deck part 3: settings, Gold, backup, import/export, notifications, errors, legal; T-088 Produce zaghlol.riv from the vector rig (illustrator)

### Wave 2 — 15 task(s)
- **A** (App core/data (flutter-core)): T-002 Add custom lint rules (no double in money, no UI string literals, no print); T-003 App CI pipeline (format, analyze, unit, golden, native unit); T-004 Pigeon setup and stale-generation check; T-007 SPK-05: encrypted SQLite (SQLite3MultipleCiphers) + FTS5 trigram on both platforms; T-012 Money and Currency value types with ISO 4217 table; T-014 Result/Failure types, SafeException and domain event bus
- **B** (Backend (.NET)): T-006 OpenAPI v1 spec and contract-test harness; T-122 EF Core model and initial migration for all backend tables + DB roles; T-123 Signing service (ES256 via KMS abstraction) and response-signature middleware; T-138 Backend observability: OpenTelemetry, metrics, dashboards, alert rules
- **C** (Content & assets): T-058 Native Egyptian-speaker review of the copy deck
- **D** (Native Android): T-010 SPK-02: OCR accuracy on synthetic InstaPay/wallet receipts; T-011 SPK-04: on-device ar-EG speech availability across the device matrix; T-165 Exclude app data from OS backups and device transfer
- **G** (UI (flutter-ui)): T-022 Design tokens, Mint Fresh/Jade Night themes and base components

### Wave 3 — 15 task(s)
- **A** (App core/data (flutter-core)): T-015 Secure key bootstrap for the database key
- **B** (Backend (.NET)): T-124 Install registration, install-token auth, rate limits, idempotency, strict DTOs; T-125 Catalog versions, deltas, signed full snapshots and admin draft/publish; T-126 Feature flags with targeting rules and admin endpoints; T-127 Price service: local Egyptian gold-market adapter, FX adapter, worker, override; T-136 Operator auth (OIDC + MFA), roles, audit log and support lookup; T-139 Retention purger and log privacy settings; T-140 Infrastructure as code and deployment pipeline (staging, prod)
- **D** (Native Android): T-008 SPK-01: Android receiver → spool → WorkManager → headless engine latency; T-060 Android share/paste intake (text, image, PDF, CSV); T-159 Android OCR host (ML Kit Latin + Tesseract Arabic)
- **E** (Native iOS): T-009 SPK-03: can an iOS App Intent process immediately with a headless Flutter engine?; T-160 iOS OCR host (Vision)
- **F** (Parsing & NLP (pure Dart)): T-013 Text & amount normalization utilities (digits, separators, groupings)
- **G** (UI (flutter-ui)): T-053 ZaghlolAvatar widget with static fallback and reduce-motion

### Wave 4 — 11 task(s)
- **A** (App core/data (flutter-core)): T-016 AppDatabase v1 skeleton: encrypted open, isolate, migration harness; T-148 Backup file format: Argon2id-wrapped key and chunked AES-256-GCM
- **B** (Backend (.NET)): T-128 Daily POST /v1/sync with throttle, contributions and bank-request intake; T-130 Google Play purchase verification, acknowledgement and sweeper; T-131 App Store verification (JWS chain, Server API status, appAccountToken)
- **D** (Native Android): T-039 Android encrypted spool + spool host API
- **E** (Native iOS): T-062 iOS encrypted spool, host API and background refresh
- **F** (Parsing & NLP (pure Dart)): T-031 Convert real SMS/notification/statement samples into synthetic fixtures (OQ-04/18); T-032 Template registry format, loader and registry_lint CLI; T-034 Merchant cleaning and normalized merchant key
- **G** (UI (flutter-ui)): T-099 Wire motion-only mascot moments to UI events

### Wave 5 — 11 task(s)
- **A** (App core/data (flutter-core)): T-017 Schema batch A: accounts, balances, raw messages, transactions (+FTS), transfers, offsets, splits; T-018 Schema batch B: categories, catalog, rules, budgets, alerts, summaries, recurring; T-019 Schema batch C: wealth, prices, Zakah, capture controls, review, settings, outbox, misc
- **B** (Backend (.NET)): T-129 Contribution aggregation, review list and promote/reject; T-132 Entitlement computation, signed tokens, GET /v1/entitlement and restore; T-133 Google RTDN push endpoint, processing worker and voided reconciliation; T-134 App Store Server Notifications V2 endpoint and reconciliation
- **D** (Native Android): T-041 IngestionWorker with headless Flutter engine and foreground events
- **E** (Native iOS): T-065 iOS Share Extension (text, image, PDF)
- **F** (Parsing & NLP (pure Dart)): T-033 Parsing pipeline stages 1–7 and ParseResult; T-035 Capture Guard rules in Dart, shared golden cases and config generator

### Wave 6 — 22 task(s)
- **A** (App core/data (flutter-core)): T-020 Settings repository with typed accessors and defaults; T-021 Redacting local diagnostic log; T-025 Feature flags service (default OFF); T-030 Catalog seed pipeline and 14 system categories; T-045 Accounts repository: auto-create, default cash, per-currency balances; T-050 Transactions repository: query, search, CRUD, soft delete; T-112 Prices and FX store in app (sync-fed, manual override, stale); T-141 App BackendClient: generated DTOs, ES256 verification, lazy install registration
- **B** (Backend (.NET)): T-135 Accounts: Google/Apple ID token sign-in, linking, sign-out, delete, Android Apple callback; T-137 zaghlol-ops CLI for catalog, flags, prices, contributions and support
- **D** (Native Android): T-038 Android Capture Guard (Kotlin) with config reader
- **E** (Native iOS): T-061 iOS Capture Guard (Swift) with config reader
- **F** (Parsing & NLP (pure Dart)): T-036 Templates + fixtures: NBE, CIB, Banque Misr, QNB; T-037 Templates + fixtures: InstaPay scenarios and mobile wallets; T-068 Templates + fixtures: Egyptian banks batch 1; T-069 Templates + fixtures: Egyptian banks batch 2; T-070 Templates + fixtures: BNPL (valU, Sympl, Souhoola, Shahry, Aman, Forsa, Contact); T-071 Templates + fixtures: Wise, Revolut, Monzo, bunq, N26, Payoneer; T-072 Templates + fixtures: HDFC, Paytm, Al Rajhi, Emirates NBD/Liv, GCC (S rows); T-073 Generic parser for unknown financial senders; T-156 Bank PDF statement import (CIB, NBE, QNB, Banque Misr); T-161 Receipt/screen OCR templates and confirmation screen S-32

### Wave 7 — 14 task(s)
- **A** (App core/data (flutter-core)): T-023 Localization scaffold, digits mode and money/date formatting; T-046 IngestRawMessages use case (dedupe, merge, persist, ack, events); T-051 Payday cycle engine, safe-to-spend, burn line and cycle summaries; T-074 Merchant rules repository and apply-to-past; T-094 Local notifications service (types, quiet hours, redaction); T-115 ≈ combined view service (target currency, rate date, exclusions); T-119 Gold gate matrix and entitlement state (local); T-149 Backup snapshot and restore swap with schema checks
- **C** (Content & assets): T-059 Compile the 600+ Egyptian merchant seed list (OQ-05)
- **D** (Native Android): T-040 SMS receiver (multipart, Guard, spool, enqueue) in prodSms flavor; T-042 Inbox reader for historical scan (sender-filtered, paged); T-043 Bank notification listener service; T-103 App lock, privacy overlay and screenshot hiding
- **E** (Native iOS): T-063 App Intents for Message and Wallet automations

### Wave 8 — 20 task(s)
- **A** (App core/data (flutter-core)): T-047 Capture module (app side): guard config writer, spool orchestrator, degraded mode; T-049 Review queue domain and repository; T-076 Re-parse job after registry version bump; T-077 Bulk edit and undo use case; T-089 Self-transfer pairing, FX conversions and card settlements; T-095 Budgets per category and currency with threshold alerts; T-096 Subscriptions detection, installments, gameya, card dues and reminders; T-100 Duplicate-charge and weekly-summary notifications; T-144 Entitlement token verification, offline cache and grace; T-150 Google Drive appDataFolder backend; T-154 CSV and Excel export with preview for Free
- **C** (Content & assets): T-029 Generate ARB files from copy deck (part 1)
- **D** (Native Android): T-044 Android capabilities and permission flows host API
- **E** (Native iOS): T-064 Shortcut package, iCloud link and setup checker; T-118 Home-screen widgets (Android Glance, iOS WidgetKit); T-151 iCloud backup host (native) and Dart adapter
- **F** (Parsing & NLP (pure Dart)): T-075 Categorizer with fuzzy merchant matching; T-164 Custom message template builder engine and screen S-65 (Gold)
- **G** (UI (flutter-ui)): T-024 App shell: routing, platform tab bars, Add button, deep links; T-163 Categories & rules S-63/S-64 incl. custom categories (Gold)

### Wave 9 — 20 task(s)
- **A** (App core/data (flutter-core)): T-048 Historical inbox scan with progress (Android); T-052 Home read model and persistent card filter; T-066 Capture module iOS integration (drain, BG refresh, checker state); T-078 Ignore rules domain: per card/channel, before-seen, keep/delete, re-scan; T-090 Refund matching and offset links; T-097 Contextual setup suggestions (payday, budgets, backup); T-098 Mascot trigger policy (shocked, detective, proud, tour guide); T-113 Assets, liabilities, net worth per unit and snapshots; T-142 Merchant contribution opt-in and outbox with on-device filters; T-145 In-app purchase flow, backend verify, background retry and restore; T-147 Optional sign-in, account screen S-69, sign-out and delete account; T-152 Backup schedules, slots and reminders (Free 1 slot, Gold 5 versions); T-155 Zaghlol CSV import with duplicate detection
- **C** (Content & assets): T-087 Generate ARB files from copy deck (parts 2–3)
- **F** (Parsing & NLP (pure Dart)): T-109 Egyptian Arabic voice-phrase parser and 200-phrase fixtures
- **G** (UI (flutter-ui)): T-055 Welcome screen S-01 with language toggle and restore entry; T-079 Transactions list S-11 with filters, search and selection mode; T-080 Transaction detail S-12 and add/edit sheet S-13; T-081 Review queue S-14; T-082 Quick add sheet S-30

### Wave 10 — 16 task(s)
- **A** (App core/data (flutter-core)): T-091 Splits and reimbursements with allocation and unassign; T-143 Daily sync orchestrator: throttle, back-off, atomic apply, re-categorize; T-166 Delete everything (local wipe + backend install delete); T-167 Zakah engine (hawl, nisab, native-unit dues)
- **F** (Parsing & NLP (pure Dart)): T-157 Online-bank statement import (Wise, Revolut, Monzo, bunq, N26)
- **G** (UI (flutter-ui)): T-054 Home screen S-10 (iOS and Android variants); T-056 Android capture setup S-02 with live scan and degraded variant; T-067 iOS capture setup S-03 (add Shortcut, check setup, first expense); T-083 Money tab S-40 (accounts per currency); T-086 Capture settings S-61 and card capture sheet S-62; T-101 Insights shell and Budget S-22 (+ edit budgets); T-102 Bills & installments S-24 and add/edit recurring item; T-120 Voice logger S-31 with on-device-first recognition and monthly limit; T-146 Paywall S-68, locked previews and upgrade prompt cap; T-153 Backup & restore screens S-66 and S-04; T-162 Settings S-60 incl. privacy info and About

### Wave 11 — 13 task(s)
- **A** (App core/data (flutter-core)): T-092 Reimbursement and cross-currency pair suggestions; T-105 Chart query layer for all 12 charts; T-171 Privacy verification suite (sandbox scan, data-boundary proxy, ignore no-trace); T-172 Device end-to-end suites (Android killed-app capture, iOS intents, backup, purchases)
- **G** (UI (flutter-ui)): T-057 Scan results screen S-06 «دي كروتك؟»; T-084 Card detail S-41, compare cards S-42; T-085 Add/edit card S-43 (type → bank → details), merge and hide; T-093 Split/reimbursement sheet S-15 and link-transfer sheet S-16; T-104 Home contextual cards and Settings 'finish setup'; T-116 Shared per-currency figures and currency switcher component; T-121 Money tab assets, Add asset S-44 and Prices S-45; T-158 Import flow S-67 (source, summary, done); T-168 Zakah screen S-46 behind flag with disclaimer

### Wave 12 — 9 task(s)
- **A** (App core/data (flutter-core)): T-106 Explanation template engine (basic vs deep coaching); T-169 Smart ROI general-advice rules with no-names check; T-173 Performance benchmarks and CI budgets; T-175 Security assessment: MobSF, ZAP, dependency scans, pen test; T-176 Android release pipeline, Play listings, Data safety and SMS declaration package; T-177 iOS release pipeline, privacy labels and App Review notes
- **F** (Parsing & NLP (pure Dart)): T-110 Ask Zaghlol intent engine (grammar, slots, query plans, answers, roast)
- **G** (UI (flutter-ui)): T-107 Charts S-20: four Free charts and Gold-locked previews; T-117 Achievement share cards with hidden amounts by default

### Wave 13 — 5 task(s)
- **G** (UI (flutter-ui)): T-108 Chart detail with explanation S-21; T-111 Ask Zaghlol screen S-50; T-114 Charts: remaining eight (Gold); T-170 Smart ROI screen S-51 behind flag; T-174 Accessibility and golden coverage pass (130% text, both themes, screen readers)


## Conflict rules (do not run together)
- T-017, T-018, T-019: share the Drift database definition file — run one at a time
- T-026, T-027, T-028: edit copy-deck.md — run one at a time or in separate files merged by the Lead
- T-036, T-037, T-068, T-069, T-070, T-071, T-072: separate institution files — parallel OK; registry_manifest.json version bump merged by the Lead
- T-130, T-131: both touch Application/Purchases — coordinate the shared Purchase aggregate; parallel OK after be_installs