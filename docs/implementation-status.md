# Implementation Status

| | |
|---|---|
| Phase | 5 — Implementation (started 2026-11-03) |
| Source of truth for task specs | `docs/04-tasks/tasks/T-###.md` |
| Rule | A task is DONE only with verification evidence (CI run / test output / review report). Dependencies must be DONE before start. One agent per file set at a time. |

## Blockers
| ID | Blocker | Impact | Owner |
|---|---|---|---|
| ~~BLK-01~~ | **Resolved 2026-11-03**: builds & tests run on GitHub Actions (repo Amr905/zaghlol). Was: no build toolchain reachable**: the cloud workspace and the linked VM cannot download Flutter/Dart, pub.dev packages, Android SDK/Gradle/Maven, .NET SDK or NuGet (network allowlist); no GitHub account linked for CI; iOS needs macOS. | All code tasks can't be built or tested → can't be verified. | Product owner |
| BLK-02 | Real SMS/notification/statement samples (OQ-04/18) | T-031, T-156, T-157 | Product owner |
| BLK-03 | Gold-feed provider contract (D-41) | T-127 go-live only | Product owner |
| BLK-04 | Hosting region + PDPL licence (CR-03/OQ-16) | T-140 | Product owner + legal |

## Summary
| Milestone | Total | DONE | IN_PROGRESS | BLOCKED |
|---|---|---|---|---|
| M0 | 28 | 1 | 1 | 0 |
| M1 | 29 | 0 | 0 | 0 |
| M2 | 29 | 0 | 0 | 0 |
| M3 | 18 | 0 | 0 | 0 |
| M4 | 17 | 0 | 0 | 0 |
| M5 | 26 | 0 | 0 | 0 |
| M6 | 19 | 0 | 0 | 0 |
| M7 | 11 | 0 | 0 | 0 |

## Tasks
| ID | Title | MS | Class | Model | Agent | Depends on | Status | Verification evidence | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T-001 | Create mono-repo scaffold with pub workspace, app flavors and pure-Dart packages | M0 | C2 | Sonnet | flutter-core-engineer | — | IN_PROGRESS | — |  |
| T-002 | Add custom lint rules (no double in money, no UI string literals, no print) | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | TODO | — |  |
| T-003 | App CI pipeline (format, analyze, unit, golden, native unit) | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | TODO | — |  |
| T-004 | Pigeon setup and stale-generation check | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | TODO | — |  |
| T-005 | Backend solution scaffold, Docker Compose and CI | M0 | C2 | Sonnet | backend-engineer | — | DONE | CI run 41720361381 (4/4 green) @ d98b37d; review [T-005](05-reviews/T-005.md) APPROVED | Squash-merged; follow-ups FU-001…005 |
| T-006 | OpenAPI v1 spec and contract-test harness | M0 | C2 | Sonnet | backend-engineer | T-005 | TODO | — |  |
| T-007 | SPK-05: encrypted SQLite (SQLite3MultipleCiphers) + FTS5 trigram on both platforms | M0 | C4 | Opus | flutter-core-engineer | T-001 | TODO | — |  |
| T-008 | SPK-01: Android receiver → spool → WorkManager → headless engine latency | M0 | C4 | Opus | native-platform-engineer | T-001, T-004 | TODO | — |  |
| T-009 | SPK-03: can an iOS App Intent process immediately with a headless Flutter engine? | M0 | C4 | Opus | native-platform-engineer | T-001, T-004 | TODO | — |  |
| T-010 | SPK-02: OCR accuracy on synthetic InstaPay/wallet receipts | M0 | C3 | Sonnet | native-platform-engineer | T-001 | TODO | — |  |
| T-011 | SPK-04: on-device ar-EG speech availability across the device matrix | M0 | C2 | Sonnet | native-platform-engineer | T-001 | TODO | — |  |
| T-012 | Money and Currency value types with ISO 4217 table | M0 | C4 | Opus | flutter-core-engineer | T-001 | TODO | — |  |
| T-013 | Text & amount normalization utilities (digits, separators, groupings) | M0 | C3 | Sonnet | parsing-engine-engineer | T-012 | TODO | — |  |
| T-014 | Result/Failure types, SafeException and domain event bus | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | TODO | — |  |
| T-015 | Secure key bootstrap for the database key | M0 | C4 | Opus | flutter-core-engineer | T-007 | TODO | — |  |
| T-016 | AppDatabase v1 skeleton: encrypted open, isolate, migration harness | M0 | C4 | Opus | flutter-core-engineer | T-015 | TODO | — |  |
| T-017 | Schema batch A: accounts, balances, raw messages, transactions (+FTS), transfers, offsets, splits | M0 | C4 | Opus | flutter-core-engineer | T-016 | TODO | — |  |
| T-018 | Schema batch B: categories, catalog, rules, budgets, alerts, summaries, recurring | M0 | C4 | Opus | flutter-core-engineer | T-016 | TODO | — |  |
| T-019 | Schema batch C: wealth, prices, Zakah, capture controls, review, settings, outbox, misc | M0 | C4 | Opus | flutter-core-engineer | T-016 | TODO | — |  |
| T-020 | Settings repository with typed accessors and defaults | M0 | C2 | Sonnet | flutter-core-engineer | T-019 | TODO | — |  |
| T-021 | Redacting local diagnostic log | M0 | C3 | Sonnet | flutter-core-engineer | T-019, T-014 | TODO | — |  |
| T-022 | Design tokens, Mint Fresh/Jade Night themes and base components | M0 | C2 | Sonnet | flutter-ui-engineer | T-001 | TODO | — |  |
| T-023 | Localization scaffold, digits mode and money/date formatting | M0 | C2 | Sonnet | flutter-core-engineer | T-012, T-020 | TODO | — |  |
| T-024 | App shell: routing, platform tab bars, Add button, deep links | M0 | C2 | Sonnet | flutter-ui-engineer | T-022, T-023 | TODO | — |  |
| T-025 | Feature flags service (default OFF) | M0 | C2 | Sonnet | flutter-core-engineer | T-019 | TODO | — |  |
| T-026 | Copy deck part 1: onboarding, capture, Home, transactions, review, accounts | M0 | C3 | Opus | ux-designer | — | TODO | — |  |
| T-027 | Copy deck part 2: insights, budget, bills, money, chat, voice, roast, explanations | M0 | C3 | Opus | ux-designer | — | TODO | — |  |
| T-028 | Copy deck part 3: settings, Gold, backup, import/export, notifications, errors, legal | M0 | C3 | Opus | ux-designer | — | TODO | — |  |
| T-029 | Generate ARB files from copy deck (part 1) | M1 | C1 | Haiku | boilerplate-engineer | T-023, T-026 | TODO | — |  |
| T-030 | Catalog seed pipeline and 14 system categories | M1 | C2 | Sonnet | flutter-core-engineer | T-018 | TODO | — |  |
| T-031 | Convert real SMS/notification/statement samples into synthetic fixtures (OQ-04/18) | M1 | C2 | Sonnet | parsing-engine-engineer | T-013 | BLOCKED | — | Waiting for samples from product owner (OQ-04/OQ-18) |
| T-032 | Template registry format, loader and registry_lint CLI | M1 | C3 | Sonnet | parsing-engine-engineer | T-013 | TODO | — |  |
| T-033 | Parsing pipeline stages 1–7 and ParseResult | M1 | C3 | Sonnet | parsing-engine-engineer | T-032, T-012 | TODO | — |  |
| T-034 | Merchant cleaning and normalized merchant key | M1 | C2 | Sonnet | parsing-engine-engineer | T-013 | TODO | — |  |
| T-035 | Capture Guard rules in Dart, shared golden cases and config generator | M1 | C4 | Opus | parsing-engine-engineer | T-032 | TODO | — |  |
| T-036 | Templates + fixtures: NBE, CIB, Banque Misr, QNB | M1 | C2 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-037 | Templates + fixtures: InstaPay scenarios and mobile wallets | M1 | C2 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-038 | Android Capture Guard (Kotlin) with config reader | M1 | C4 | Opus | native-platform-engineer | T-035, T-008 | TODO | — |  |
| T-039 | Android encrypted spool + spool host API | M1 | C4 | Opus | native-platform-engineer | T-004, T-008 | TODO | — |  |
| T-040 | SMS receiver (multipart, Guard, spool, enqueue) in prodSms flavor | M1 | C4 | Opus | native-platform-engineer | T-038, T-039 | TODO | — |  |
| T-041 | IngestionWorker with headless Flutter engine and foreground events | M1 | C4 | Opus | native-platform-engineer | T-039, T-008 | TODO | — |  |
| T-042 | Inbox reader for historical scan (sender-filtered, paged) | M1 | C4 | Opus | native-platform-engineer | T-004, T-038 | TODO | — |  |
| T-043 | Bank notification listener service | M1 | C4 | Opus | native-platform-engineer | T-038, T-039 | TODO | — |  |
| T-044 | Android capabilities and permission flows host API | M1 | C4 | Opus | native-platform-engineer | T-040, T-043 | TODO | — |  |
| T-045 | Accounts repository: auto-create, default cash, per-currency balances | M1 | C3 | Sonnet | flutter-core-engineer | T-017 | TODO | — |  |
| T-046 | IngestRawMessages use case (dedupe, merge, persist, ack, events) | M1 | C4 | Opus | flutter-core-engineer | T-033, T-045, T-014, T-035 | TODO | — |  |
| T-047 | Capture module (app side): guard config writer, spool orchestrator, degraded mode | M1 | C3 | Sonnet | flutter-core-engineer | T-046, T-039, T-035 | TODO | — |  |
| T-048 | Historical inbox scan with progress (Android) | M1 | C3 | Sonnet | flutter-core-engineer | T-047, T-042 | TODO | — |  |
| T-049 | Review queue domain and repository | M1 | C2 | Sonnet | flutter-core-engineer | T-019, T-046 | TODO | — |  |
| T-050 | Transactions repository: query, search, CRUD, soft delete | M1 | C2 | Sonnet | flutter-core-engineer | T-017 | TODO | — |  |
| T-051 | Payday cycle engine, safe-to-spend, burn line and cycle summaries | M1 | C3 | Sonnet | flutter-core-engineer | T-012, T-018, T-050 | TODO | — |  |
| T-052 | Home read model and persistent card filter | M1 | C2 | Sonnet | flutter-core-engineer | T-051, T-050, T-045, T-049 | TODO | — |  |
| T-053 | ZaghlolAvatar widget with static fallback and reduce-motion | M1 | C2 | Sonnet | flutter-ui-engineer | T-022 | TODO | — |  |
| T-054 | Home screen S-10 (iOS and Android variants) | M1 | C2 | Sonnet | flutter-ui-engineer | T-052, T-024, T-029, T-053 | TODO | — |  |
| T-055 | Welcome screen S-01 with language toggle and restore entry | M1 | C2 | Sonnet | flutter-ui-engineer | T-024, T-029, T-053 | TODO | — |  |
| T-056 | Android capture setup S-02 with live scan and degraded variant | M1 | C2 | Sonnet | flutter-ui-engineer | T-055, T-044, T-048 | TODO | — |  |
| T-057 | Scan results screen S-06 «دي كروتك؟» | M1 | C2 | Sonnet | flutter-ui-engineer | T-056, T-045 | TODO | — |  |
| T-058 | Native Egyptian-speaker review of the copy deck | M2 | C2 | human | external | T-026, T-027, T-028 | TODO | — |  |
| T-059 | Compile the 600+ Egyptian merchant seed list (OQ-05) | M2 | C2 | human | external | T-030 | TODO | — |  |
| T-060 | Android share/paste intake (text, image, PDF, CSV) | M2 | C3 | Sonnet | native-platform-engineer | T-004 | TODO | — |  |
| T-061 | iOS Capture Guard (Swift) with config reader | M2 | C4 | Opus | native-platform-engineer | T-035, T-009 | TODO | — |  |
| T-062 | iOS encrypted spool, host API and background refresh | M2 | C4 | Opus | native-platform-engineer | T-004, T-009 | TODO | — |  |
| T-063 | App Intents for Message and Wallet automations | M2 | C4 | Opus | native-platform-engineer | T-061, T-062 | TODO | — |  |
| T-064 | Shortcut package, iCloud link and setup checker | M2 | C3 | Sonnet | native-platform-engineer | T-063 | TODO | — |  |
| T-065 | iOS Share Extension (text, image, PDF) | M2 | C4 | Opus | native-platform-engineer | T-062 | TODO | — |  |
| T-066 | Capture module iOS integration (drain, BG refresh, checker state) | M2 | C3 | Sonnet | flutter-core-engineer | T-047, T-062, T-064 | TODO | — |  |
| T-067 | iOS capture setup S-03 (add Shortcut, check setup, first expense) | M2 | C2 | Sonnet | flutter-ui-engineer | T-055, T-066 | TODO | — |  |
| T-068 | Templates + fixtures: Egyptian banks batch 1 | M2 | C2 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-069 | Templates + fixtures: Egyptian banks batch 2 | M2 | C2 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-070 | Templates + fixtures: BNPL (valU, Sympl, Souhoola, Shahry, Aman, Forsa, Contact) | M2 | C2 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-071 | Templates + fixtures: Wise, Revolut, Monzo, bunq, N26, Payoneer | M2 | C3 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-072 | Templates + fixtures: HDFC, Paytm, Al Rajhi, Emirates NBD/Liv, GCC (S rows) | M2 | C2 | Sonnet | parsing-engine-engineer | T-033 | TODO | — |  |
| T-073 | Generic parser for unknown financial senders | M2 | C3 | Sonnet | parsing-engine-engineer | T-033, T-034 | TODO | — |  |
| T-074 | Merchant rules repository and apply-to-past | M2 | C2 | Sonnet | flutter-core-engineer | T-018, T-050 | TODO | — |  |
| T-075 | Categorizer with fuzzy merchant matching | M2 | C3 | Sonnet | parsing-engine-engineer | T-034, T-018, T-074, T-030 | TODO | — |  |
| T-076 | Re-parse job after registry version bump | M2 | C3 | Sonnet | flutter-core-engineer | T-046, T-032 | TODO | — |  |
| T-077 | Bulk edit and undo use case | M2 | C3 | Sonnet | flutter-core-engineer | T-050, T-074 | TODO | — |  |
| T-078 | Ignore rules domain: per card/channel, before-seen, keep/delete, re-scan | M2 | C3 | Sonnet | flutter-core-engineer | T-047, T-050 | TODO | — |  |
| T-079 | Transactions list S-11 with filters, search and selection mode | M2 | C2 | Sonnet | flutter-ui-engineer | T-050, T-077, T-024, T-029 | TODO | — |  |
| T-080 | Transaction detail S-12 and add/edit sheet S-13 | M2 | C2 | Sonnet | flutter-ui-engineer | T-050, T-075, T-045, T-029 | TODO | — |  |
| T-081 | Review queue S-14 | M2 | C2 | Sonnet | flutter-ui-engineer | T-049, T-074, T-029 | TODO | — |  |
| T-082 | Quick add sheet S-30 | M2 | C1 | Haiku | boilerplate-engineer | T-024, T-029 | TODO | — |  |
| T-083 | Money tab S-40 (accounts per currency) | M2 | C2 | Sonnet | flutter-ui-engineer | T-045, T-052, T-029 | TODO | — |  |
| T-084 | Card detail S-41, compare cards S-42 | M2 | C2 | Sonnet | flutter-ui-engineer | T-083, T-051 | TODO | — |  |
| T-085 | Add/edit card S-43 (type → bank → details), merge and hide | M2 | C2 | Sonnet | flutter-ui-engineer | T-083, T-078 | TODO | — |  |
| T-086 | Capture settings S-61 and card capture sheet S-62 | M2 | C2 | Sonnet | flutter-ui-engineer | T-078, T-029 | TODO | — |  |
| T-087 | Generate ARB files from copy deck (parts 2–3) | M3 | C1 | Haiku | boilerplate-engineer | T-029, T-027, T-028 | TODO | — |  |
| T-088 | Produce zaghlol.riv from the vector rig (illustrator) | M3 | C2 | human | external | — | TODO | — |  |
| T-089 | Self-transfer pairing, FX conversions and card settlements | M3 | C3 | Sonnet | flutter-core-engineer | T-046, T-050 | TODO | — |  |
| T-090 | Refund matching and offset links | M3 | C3 | Sonnet | flutter-core-engineer | T-089 | TODO | — |  |
| T-091 | Splits and reimbursements with allocation and unassign | M3 | C3 | Sonnet | flutter-core-engineer | T-090 | TODO | — |  |
| T-092 | Reimbursement and cross-currency pair suggestions | M3 | C2 | Sonnet | flutter-core-engineer | T-091, T-049 | TODO | — |  |
| T-093 | Split/reimbursement sheet S-15 and link-transfer sheet S-16 | M3 | C2 | Sonnet | flutter-ui-engineer | T-091, T-089, T-080 | TODO | — |  |
| T-094 | Local notifications service (types, quiet hours, redaction) | M3 | C2 | Sonnet | flutter-core-engineer | T-020 | TODO | — |  |
| T-095 | Budgets per category and currency with threshold alerts | M3 | C2 | Sonnet | flutter-core-engineer | T-051, T-094 | TODO | — |  |
| T-096 | Subscriptions detection, installments, gameya, card dues and reminders | M3 | C3 | Sonnet | flutter-core-engineer | T-050, T-094 | TODO | — |  |
| T-097 | Contextual setup suggestions (payday, budgets, backup) | M3 | C2 | Sonnet | flutter-core-engineer | T-051, T-049 | TODO | — |  |
| T-098 | Mascot trigger policy (shocked, detective, proud, tour guide) | M3 | C2 | Sonnet | flutter-core-engineer | T-051, T-089, T-095 | TODO | — |  |
| T-099 | Wire motion-only mascot moments to UI events | M3 | C2 | Sonnet | flutter-ui-engineer | T-053, T-088 | TODO | — |  |
| T-100 | Duplicate-charge and weekly-summary notifications | M3 | C2 | Sonnet | flutter-core-engineer | T-094, T-046, T-051 | TODO | — |  |
| T-101 | Insights shell and Budget S-22 (+ edit budgets) | M3 | C2 | Sonnet | flutter-ui-engineer | T-095, T-087, T-024 | TODO | — |  |
| T-102 | Bills & installments S-24 and add/edit recurring item | M3 | C2 | Sonnet | flutter-ui-engineer | T-096, T-087 | TODO | — |  |
| T-103 | App lock, privacy overlay and screenshot hiding | M3 | C3 | Sonnet | native-platform-engineer | T-004, T-020 | TODO | — |  |
| T-104 | Home contextual cards and Settings 'finish setup' | M3 | C2 | Sonnet | flutter-ui-engineer | T-054, T-097, T-103 | TODO | — |  |
| T-105 | Chart query layer for all 12 charts | M4 | C3 | Sonnet | flutter-core-engineer | T-051, T-096, T-091 | TODO | — |  |
| T-106 | Explanation template engine (basic vs deep coaching) | M4 | C3 | Sonnet | flutter-core-engineer | T-105, T-027 | TODO | — |  |
| T-107 | Charts S-20: four Free charts and Gold-locked previews | M4 | C2 | Sonnet | flutter-ui-engineer | T-105, T-101 | TODO | — |  |
| T-108 | Chart detail with explanation S-21 | M4 | C2 | Sonnet | flutter-ui-engineer | T-106, T-107 | TODO | — |  |
| T-109 | Egyptian Arabic voice-phrase parser and 200-phrase fixtures | M4 | C3 | Sonnet | parsing-engine-engineer | T-013, T-075 | TODO | — |  |
| T-110 | Ask Zaghlol intent engine (grammar, slots, query plans, answers, roast) | M4 | C3 | Sonnet | parsing-engine-engineer | T-105, T-027 | TODO | — |  |
| T-111 | Ask Zaghlol screen S-50 | M4 | C2 | Sonnet | flutter-ui-engineer | T-110 | TODO | — |  |
| T-112 | Prices and FX store in app (sync-fed, manual override, stale) | M4 | C2 | Sonnet | flutter-core-engineer | T-019 | TODO | — |  |
| T-113 | Assets, liabilities, net worth per unit and snapshots | M4 | C3 | Sonnet | flutter-core-engineer | T-112, T-045, T-096 | TODO | — |  |
| T-114 | Charts: remaining eight (Gold) | M4 | C2 | Sonnet | flutter-ui-engineer | T-107, T-113 | TODO | — |  |
| T-115 | ≈ combined view service (target currency, rate date, exclusions) | M4 | C3 | Sonnet | flutter-core-engineer | T-012, T-112 | TODO | — |  |
| T-116 | Shared per-currency figures and currency switcher component | M4 | C2 | Sonnet | flutter-ui-engineer | T-115, T-054 | TODO | — |  |
| T-117 | Achievement share cards with hidden amounts by default | M4 | C2 | Sonnet | flutter-ui-engineer | T-105, T-022 | TODO | — |  |
| T-118 | Home-screen widgets (Android Glance, iOS WidgetKit) | M4 | C3 | Sonnet | native-platform-engineer | T-051, T-004 | TODO | — |  |
| T-119 | Gold gate matrix and entitlement state (local) | M4 | C2 | Sonnet | flutter-core-engineer | T-025, T-020 | TODO | — |  |
| T-120 | Voice logger S-31 with on-device-first recognition and monthly limit | M4 | C3 | Sonnet | flutter-ui-engineer | T-109, T-119, T-011 | TODO | — |  |
| T-121 | Money tab assets, Add asset S-44 and Prices S-45 | M4 | C2 | Sonnet | flutter-ui-engineer | T-113, T-083, T-119 | TODO | — |  |
| T-122 | EF Core model and initial migration for all backend tables + DB roles | M5 | C4 | Opus | backend-engineer | T-005 | TODO | — |  |
| T-123 | Signing service (ES256 via KMS abstraction) and response-signature middleware | M5 | C4 | Opus | backend-engineer | T-005 | TODO | — |  |
| T-124 | Install registration, install-token auth, rate limits, idempotency, strict DTOs | M5 | C4 | Opus | backend-engineer | T-122, T-006 | TODO | — |  |
| T-125 | Catalog versions, deltas, signed full snapshots and admin draft/publish | M5 | C3 | Opus | backend-engineer | T-122, T-123 | TODO | — |  |
| T-126 | Feature flags with targeting rules and admin endpoints | M5 | C2 | Sonnet | backend-engineer | T-122 | TODO | — |  |
| T-127 | Price service: local Egyptian gold-market adapter, FX adapter, worker, override | M5 | C3 | Sonnet | backend-engineer | T-122 | BLOCKED | — | Provider contract for local gold feed (D-41) needed before go-live; build continues with fakes |
| T-128 | Daily POST /v1/sync with throttle, contributions and bank-request intake | M5 | C4 | Opus | backend-engineer | T-124, T-125, T-126, T-127, T-123 | TODO | — |  |
| T-129 | Contribution aggregation, review list and promote/reject | M5 | C2 | Sonnet | backend-engineer | T-128, T-125 | TODO | — |  |
| T-130 | Google Play purchase verification, acknowledgement and sweeper | M5 | C4 | Opus | backend-engineer | T-124, T-123 | TODO | — |  |
| T-131 | App Store verification (JWS chain, Server API status, appAccountToken) | M5 | C4 | Opus | backend-engineer | T-124, T-123 | TODO | — |  |
| T-132 | Entitlement computation, signed tokens, GET /v1/entitlement and restore | M5 | C4 | Opus | backend-engineer | T-130, T-131 | TODO | — |  |
| T-133 | Google RTDN push endpoint, processing worker and voided reconciliation | M5 | C4 | Opus | backend-engineer | T-130 | TODO | — |  |
| T-134 | App Store Server Notifications V2 endpoint and reconciliation | M5 | C4 | Opus | backend-engineer | T-131 | TODO | — |  |
| T-135 | Accounts: Google/Apple ID token sign-in, linking, sign-out, delete, Android Apple callback | M5 | C4 | Opus | backend-engineer | T-132 | TODO | — |  |
| T-136 | Operator auth (OIDC + MFA), roles, audit log and support lookup | M5 | C4 | Opus | backend-engineer | T-122 | TODO | — |  |
| T-137 | zaghlol-ops CLI for catalog, flags, prices, contributions and support | M5 | C2 | Sonnet | backend-engineer | T-136, T-125, T-126, T-127, T-129 | TODO | — |  |
| T-138 | Backend observability: OpenTelemetry, metrics, dashboards, alert rules | M5 | C2 | Sonnet | backend-engineer | T-005 | TODO | — |  |
| T-139 | Retention purger and log privacy settings | M5 | C2 | Sonnet | backend-engineer | T-122, T-138 | TODO | — |  |
| T-140 | Infrastructure as code and deployment pipeline (staging, prod) | M5 | C3 | Opus | backend-engineer | T-138 | BLOCKED | — | CR-03 / OQ-16: hosting provider & region + PDPL licence decision |
| T-141 | App BackendClient: generated DTOs, ES256 verification, lazy install registration | M5 | C4 | Opus | flutter-core-engineer | T-006, T-019 | TODO | — |  |
| T-142 | Merchant contribution opt-in and outbox with on-device filters | M5 | C4 | Opus | flutter-core-engineer | T-075, T-019 | TODO | — |  |
| T-143 | Daily sync orchestrator: throttle, back-off, atomic apply, re-categorize | M5 | C3 | Opus | flutter-core-engineer | T-141, T-075, T-142, T-112, T-025 | TODO | — |  |
| T-144 | Entitlement token verification, offline cache and grace | M5 | C4 | Opus | flutter-core-engineer | T-119, T-141 | TODO | — |  |
| T-145 | In-app purchase flow, backend verify, background retry and restore | M5 | C4 | Opus | flutter-core-engineer | T-144, T-141 | TODO | — |  |
| T-146 | Paywall S-68, locked previews and upgrade prompt cap | M5 | C2 | Sonnet | flutter-ui-engineer | T-145, T-087 | TODO | — |  |
| T-147 | Optional sign-in, account screen S-69, sign-out and delete account | M5 | C4 | Opus | flutter-core-engineer | T-141, T-144 | TODO | — |  |
| T-148 | Backup file format: Argon2id-wrapped key and chunked AES-256-GCM | M6 | C4 | Opus | flutter-core-engineer | T-015 | TODO | — |  |
| T-149 | Backup snapshot and restore swap with schema checks | M6 | C4 | Opus | flutter-core-engineer | T-148, T-017, T-018, T-019, T-020 | TODO | — |  |
| T-150 | Google Drive appDataFolder backend | M6 | C4 | Opus | flutter-core-engineer | T-149 | TODO | — |  |
| T-151 | iCloud backup host (native) and Dart adapter | M6 | C4 | Opus | native-platform-engineer | T-149, T-004 | TODO | — |  |
| T-152 | Backup schedules, slots and reminders (Free 1 slot, Gold 5 versions) | M6 | C3 | Sonnet | flutter-core-engineer | T-150, T-151, T-119, T-094 | TODO | — |  |
| T-153 | Backup & restore screens S-66 and S-04 | M6 | C2 | Sonnet | flutter-ui-engineer | T-152, T-087 | TODO | — |  |
| T-154 | CSV and Excel export with preview for Free | M6 | C2 | Sonnet | flutter-core-engineer | T-050, T-119 | TODO | — |  |
| T-155 | Zaghlol CSV import with duplicate detection | M6 | C3 | Sonnet | flutter-core-engineer | T-046, T-154 | TODO | — |  |
| T-156 | Bank PDF statement import (CIB, NBE, QNB, Banque Misr) | M6 | C3 | Sonnet | parsing-engine-engineer | T-033, T-031 | BLOCKED | — | Needs sample statements (OQ-04) |
| T-157 | Online-bank statement import (Wise, Revolut, Monzo, bunq, N26) | M6 | C3 | Sonnet | parsing-engine-engineer | T-155, T-071 | BLOCKED | — | Needs sample statements (OQ-04) |
| T-158 | Import flow S-67 (source, summary, done) | M6 | C2 | Sonnet | flutter-ui-engineer | T-156, T-157, T-155, T-119 | TODO | — |  |
| T-159 | Android OCR host (ML Kit Latin + Tesseract Arabic) | M6 | C3 | Sonnet | native-platform-engineer | T-010, T-004 | TODO | — |  |
| T-160 | iOS OCR host (Vision) | M6 | C3 | Sonnet | native-platform-engineer | T-010, T-004 | TODO | — |  |
| T-161 | Receipt/screen OCR templates and confirmation screen S-32 | M6 | C2 | Sonnet | parsing-engine-engineer | T-159, T-160, T-033 | TODO | — |  |
| T-162 | Settings S-60 incl. privacy info and About | M6 | C2 | Sonnet | flutter-ui-engineer | T-020, T-087, T-115 | TODO | — |  |
| T-163 | Categories & rules S-63/S-64 incl. custom categories (Gold) | M6 | C2 | Sonnet | flutter-ui-engineer | T-074, T-119 | TODO | — |  |
| T-164 | Custom message template builder engine and screen S-65 (Gold) | M6 | C3 | Sonnet | parsing-engine-engineer | T-033, T-119 | TODO | — |  |
| T-165 | Exclude app data from OS backups and device transfer | M6 | C4 | Opus | native-platform-engineer | T-001 | TODO | — |  |
| T-166 | Delete everything (local wipe + backend install delete) | M6 | C4 | Opus | flutter-core-engineer | T-015, T-141, T-152 | TODO | — |  |
| T-167 | Zakah engine (hawl, nisab, native-unit dues) | M7 | C4 | Opus | flutter-core-engineer | T-113 | TODO | — |  |
| T-168 | Zakah screen S-46 behind flag with disclaimer | M7 | C2 | Sonnet | flutter-ui-engineer | T-167, T-025, T-087 | TODO | — |  |
| T-169 | Smart ROI general-advice rules with no-names check | M7 | C3 | Sonnet | flutter-core-engineer | T-105 | TODO | — |  |
| T-170 | Smart ROI screen S-51 behind flag | M7 | C2 | Sonnet | flutter-ui-engineer | T-169, T-025, T-087 | TODO | — |  |
| T-171 | Privacy verification suite (sandbox scan, data-boundary proxy, ignore no-trace) | M7 | C4 | Opus | test-engineer | T-166, T-143, T-078, T-149, T-165 | TODO | — |  |
| T-172 | Device end-to-end suites (Android killed-app capture, iOS intents, backup, purchases) | M7 | C3 | Sonnet | test-engineer | T-056, T-067, T-153, T-145 | TODO | — |  |
| T-173 | Performance benchmarks and CI budgets | M7 | C2 | Sonnet | test-engineer | T-033, T-050, T-105, T-048 | TODO | — |  |
| T-174 | Accessibility and golden coverage pass (130% text, both themes, screen readers) | M7 | C2 | Sonnet | test-engineer | T-054, T-079, T-162, T-107 | TODO | — |  |
| T-175 | Security assessment: MobSF, ZAP, dependency scans, pen test | M7 | C4 | Opus | security-privacy-reviewer | T-171, T-140 | TODO | — |  |
| T-176 | Android release pipeline, Play listings, Data safety and SMS declaration package | M7 | C3 | Sonnet | flutter-core-engineer | T-172, T-171 | TODO | — |  |
| T-177 | iOS release pipeline, privacy labels and App Review notes | M7 | C3 | Sonnet | flutter-core-engineer | T-172, T-171 | TODO | — |  |

## Follow-ups (from reviews)
| ID | From | Item | Owner / target | Status |
|---|---|---|---|---|
| FU-001 | T-005 #1, #8 | Add NOT_FOUND, METHOD_NOT_ALLOWED, UNAUTHORIZED (fallback only), PAYLOAD_TOO_LARGE, UNSUPPORTED_MEDIA_TYPE to `backend-api.md` §6; Dockerfile location in `project-structure.md` | solution-architect (docs) | OPEN |
| FU-002 | T-005 #2 | Align log field names with observability §3.2 (or update the doc) before any alerting | T-138 | OPEN |
| FU-003 | T-005 #3 | DB readiness check on health/readiness probe, tested against Testcontainers | T-122 | OPEN |
| FU-004 | T-005 #4–7, #9–10, #12–13 | Backend hardening: real body-not-logged test, SHA-pinned actions, Trivy by digest, 4xx mapping + test, single trace id, Production env in tests, stale-heartbeat test, compose loopback | backend-engineer (small C2 pass, before M5) | OPEN |
| FU-005 | T-005 #11 | `serverTime` as UTC `Z` and fixed in OpenAPI | T-006 | OPEN |

## Log
| Date | Event |
|---|---|
| 2026-11-03 | Phase 4 plan approved; Phase 5 opened. Toolchain check: blocked (BLK-01). |
| 2026-11-03 | BLK-01 resolved via GitHub Actions. T-001 and T-005 started in parallel (separate worktrees, lanes A/B). |
| 2026-11-03 | T-005 DONE: code-reviewer APPROVED (14 minor/nit findings → FU-001…005), CI green, squash-merged to main. T-006 unblocked. |
