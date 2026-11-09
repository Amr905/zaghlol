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
| ~~BLK-05~~ | **Resolved 2026-11-06: the repo was made public, so Actions is free.** Was: GitHub Actions blocked by account billing (2026-11-06): "recent account payments have failed or your spending limit needs to be increased". No job starts. | All CI verification (T-003, FU-api-decisions, every later task) | Product owner: fix the payment method or raise the spending limit, or make the repo public (free Actions minutes) |

## Summary
| Milestone | Total | DONE | IN_PROGRESS | BLOCKED |
|---|---|---|---|---|
| M0 | 28 | 14 | 0 | 0 |
| M1 | 29 | 0 | 0 | 1 |
| M2 | 29 | 0 | 0 | 0 |
| M3 | 18 | 0 | 0 | 0 |
| M4 | 17 | 0 | 0 | 0 |
| M5 | 35 | 4 | 0 | 2 |
| M6 | 19 | 0 | 1 | 2 |
| M7 | 11 | 0 | 0 | 0 |

## Tasks
| ID | Title | MS | Class | Model | Agent | Depends on | Status | Verification evidence | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T-001 | Create mono-repo scaffold with pub workspace, app flavors and pure-Dart packages | M0 | C2 | Sonnet | flutter-core-engineer | — | DONE | CI run 42103098253 (10/10 green) @ ec6214e; review [T-001](05-reviews/T-001.md) APPROVED (round 2) | Squash-merged; deferred findings appended to T-002/003/022/023/141/165/176 |
| T-002 | Add custom lint rules (no double in money, no UI string literals, no print) | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | DONE | app-ci 42484193276 (13/13) @ 4c13193; PR #4 squash-merged; review [T-002](05-reviews/T-002.md) APPROVED | Standalone AST checker in tools/lints (custom_lint does not analyze on Dart 3.13). FU-029…FU-033 |
| T-003 | App CI pipeline (format, analyze, unit, golden, native unit) | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | DONE | app-ci run 42213382460 (13/13 green) @ b186d1d; red/no-test proofs 42211250792, 42212487800; symlink proofs 42209342928, 42209963798; regen runs 42213382374, 42207136110; review [T-003](05-reviews/T-003.md) APPROVED (round 2) | Squash-merged; nits deferred to T-007/T-008/T-022/T-023 |
| T-004 | Pigeon setup and stale-generation check | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | DONE | app-ci 42488720352 (13/13); negative control 42488874829; PR #7 squash-merged; review [T-004](05-reviews/T-004.md) APPROVED | FU-042, FU-043 |
| T-005 | Backend solution scaffold, Docker Compose and CI | M0 | C2 | Sonnet | backend-engineer | — | DONE | CI run 41720361381 (4/4 green) @ d98b37d; review [T-005](05-reviews/T-005.md) APPROVED | Squash-merged; follow-ups FU-001…005 |
| T-006 | OpenAPI v1 spec and contract-test harness | M0 | C2 | Sonnet | backend-engineer | T-005 | DONE | CI run 42102066749 (5/5 green) @ 8d60381; review [T-006](05-reviews/T-006.md) APPROVED (round 2) | Squash-merged; osMajor dropped per BR-SYNC-03 |
| T-007 | SPK-05: encrypted SQLite (SQLite3MultipleCiphers) + FTS5 trigram on both platforms | M0 | C4 | Opus | flutter-core-engineer | T-001 | DONE | app-ci 42525620560, db-platform 42525620566 (4 legs); negative proofs 42525638895 (upstream SQLite) and 42525641481 (key removed) red as intended; reviews [T-007](05-reviews/T-007.md) + [security](05-reviews/T-007-security.md) APPROVED | PR #13 squash-merged. Device timing rows in ADR-002 pending PO decisions (iPhone 12 run, reference Android phone) |
| T-008 | SPK-01: Android receiver → spool → WorkManager → headless engine latency | M0 | C4 | Opus | native-platform-engineer | T-001, T-004 | TODO | — |  |
| T-009 | SPK-03: can an iOS App Intent process immediately with a headless Flutter engine? | M0 | C4 | Opus | native-platform-engineer | T-001, T-004 | TODO | — |  |
| T-010 | SPK-02: OCR accuracy on synthetic InstaPay/wallet receipts | M0 | C3 | Sonnet | native-platform-engineer | T-001 | TODO | — |  |
| T-011 | SPK-04: on-device ar-EG speech availability across the device matrix | M0 | C2 | Sonnet | native-platform-engineer | T-001 | TODO | — |  |
| T-012 | Money and Currency value types with ISO 4217 table | M0 | C4 | Opus | flutter-core-engineer | T-001 | DONE | app-ci 42407200685 (13/13) @ cb1859c; merged to main | All three reviews APPROVED (round 3). Review: docs/05-reviews/T-012.md. Follow-ups: FU-014; optional F11 dart:math check, R3 nits |
| T-013 | Text & amount normalization utilities (digits, separators, groupings) | M0 | C3 | Sonnet | parsing-engine-engineer | T-012 | DONE | app-ci 42689001237 + PR head green; review [T-013](05-reviews/T-013.md) APPROVED | PR #14 squash-merged. Adds ParseFailureReason.excessPrecision |
| T-014 | Result/Failure types, SafeException and domain event bus | M0 | C2 | Sonnet | flutter-core-engineer | T-001 | DONE | app-ci 42487468428 (green, on main-merged head 160f2f6); PR #3 squash-merged; review [T-014](05-reviews/T-014.md) APPROVED | FU-034…FU-038 |
| T-015 | Secure key bootstrap for the database key | M0 | C4 | Opus | flutter-core-engineer | T-007 | TODO | — |  |
| T-016 | AppDatabase v1 skeleton: encrypted open, isolate, migration harness | M0 | C4 | Opus | flutter-core-engineer | T-015 | TODO | — |  |
| T-017 | Schema batch A: accounts, balances, raw messages, transactions (+FTS), transfers, offsets, splits | M0 | C4 | Opus | flutter-core-engineer | T-016 | TODO | — |  |
| T-018 | Schema batch B: categories, catalog, rules, budgets, alerts, summaries, recurring | M0 | C4 | Opus | flutter-core-engineer | T-016 | TODO | — |  |
| T-019 | Schema batch C: wealth, prices, Zakah, capture controls, review, settings, outbox, misc | M0 | C4 | Opus | flutter-core-engineer | T-016 | TODO | — |  |
| T-020 | Settings repository with typed accessors and defaults | M0 | C2 | Sonnet | flutter-core-engineer | T-019 | TODO | — |  |
| T-021 | Redacting local diagnostic log | M0 | C3 | Sonnet | flutter-core-engineer | T-019, T-014 | TODO | — |  |
| T-022 | Design tokens, Mint Fresh/Jade Night themes and base components | M0 | C2 | Sonnet | flutter-ui-engineer | T-001 | DONE | app-ci 42506573523 (13/13); PR #9 squash-merged; review [T-022](05-reviews/T-022.md) APPROVED | Goldens use Ahem until IBM Plex Sans Arabic is bundled. FU-044…FU-047 |
| T-023 | Localization scaffold, digits mode and money/date formatting | M0 | C2 | Sonnet | flutter-core-engineer | T-012, T-020 | TODO | — |  |
| T-024 | App shell: routing, platform tab bars, Add button, deep links | M0 | C2 | Sonnet | flutter-ui-engineer | T-022, T-023 | TODO | — |  |
| T-025 | Feature flags service (default OFF) | M0 | C2 | Sonnet | flutter-core-engineer | T-019 | TODO | — |  |
| T-026 | Copy deck part 1: onboarding, capture, Home, transactions, review, accounts | M0 | C3 | Opus | ux-designer | — | DONE | task/T-026-copy-deck-1 @ fc404b7; merged to main | Code APPROVED, tests SUFFICIENT (round 2). Minors carried to T-029; R2-4 to UX (S-40 hidden-accounts row) |
| T-027 | Copy deck part 2: insights, budget, bills, money, chat, voice, roast, explanations | M0 | C3 | Sonnet | ux-designer | — | DONE | task/T-027-copy-deck-2 @ 3305da5; copy_deck_check.py 0 errors (1,188 keys); review [T-027](05-reviews/T-027.md) APPROVED | Docs-only review (one Sonnet reviewer). Open copy questions Q-19…Q-29; FU-027, FU-028 |
| T-028 | Copy deck part 3: settings, Gold, backup, import/export, notifications, errors, legal | M0 | C3 | Sonnet | ux-designer | — | DONE | copy_deck_check.py 0 errors (1,651 ARB + 19 native); PR #5 squash-merged; review [T-028](05-reviews/T-028.md) APPROVED (round 2) | Round 1 major (BR-SYNC-03 under-disclosure) fixed. Open copy questions Q-30…Q-43; FU-039…FU-041 |
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
| T-122 | EF Core model and initial migration for all backend tables + DB roles | M5 | C4 | Opus | backend-engineer | T-005 | DONE | backend-ci 42407789072 (5/5, 391 tests) @ d5943be; PR #2 squash-merged | All three C4 reviews APPROVED (round 2). Follow-ups FU-015 to FU-026; FU-020 before T-184 |
| T-123 | Signing service (ES256 via KMS abstraction) and response-signature middleware | M5 | C4 | Opus | backend-engineer | T-005 | DONE | backend-ci 42502737300 (5/5) @ 1a8d165; PR #8 squash-merged; [T-123](05-reviews/T-123.md) APPROVED (code r2, security, tests) | Closes FU-019, 022, 023, 026, FU-025 code part. FU-048 |
| T-124 | Install registration, install-token auth, rate limits, idempotency, strict DTOs | M5 | C4 | Opus | backend-engineer | T-122, T-123, T-006 | DONE | backend-ci 42691437478 + PR head green (Android NDK download flake re-run); reviews [T-124](05-reviews/T-124.md) APPROVED, [security](05-reviews/T-124-security.md) APPROVED after S-1 fix (delta re-review) | PR #15 squash-merged. Non-dev deploys must set ForwardedHeaders proxies or NoProxy=true |
| T-125 | Catalog versions, deltas, signed full snapshots and admin draft/publish | M5 | C3 | Opus | backend-engineer | T-122, T-123 | TODO | — |  |
| T-126 | Feature flags with targeting rules and admin endpoints | M5 | C2 | Sonnet | backend-engineer | T-122 | TODO | — |  |
| T-127 | Price service: local Egyptian gold-market adapter, FX adapter, worker, override | M5 | C3 | Sonnet | backend-engineer | T-122 | BLOCKED | — | Provider contract for local gold feed (D-41) needed before go-live; build continues with fakes |
| T-128 | Daily POST /v1/sync with throttle, contributions and bank-request intake | M5 | C4 | Opus | backend-engineer | T-124, T-125, T-126, T-127, T-123 | TODO | — |  |
| T-129 | Contribution aggregation, review list and promote/reject | M5 | C2 | Sonnet | backend-engineer | T-128, T-125 | TODO | — |  |
| T-130 | Google Play purchase verification, acknowledgement and sweeper | M5 | C4 | Opus | backend-engineer | T-124, T-123 | TODO | — |  |
| T-131 | App Store verification (JWS chain, Server API status, appAccountToken) | M5 | C4 | Opus | backend-engineer | T-124, T-123 | TODO | — |  |
| T-132 | Entitlement tokens, GET /v1/entitlement, seat at verify and sync entitlement block | M5 | C4 | Opus | backend-engineer | T-128, T-130, T-131, T-184 | TODO | — | Plan v1.1: split; seat service → T-184, restore → T-185 |
| T-133 | Google RTDN push endpoint, processing worker and voided reconciliation | M5 | C4 | Opus | backend-engineer | T-130 | TODO | — |  |
| T-134 | App Store Server Notifications V2 endpoint and reconciliation | M5 | C4 | Opus | backend-engineer | T-131 | TODO | — |  |
| T-135 | Accounts: Google/Apple ID token sign-in, linking, sign-out, delete, Android Apple callback | M5 | C4 | Opus | backend-engineer | T-132, T-182, T-184 | TODO | — | Plan v1.1: R5-3(a) note |
| T-136 | Operator auth (OIDC + MFA), roles, audit log and support lookup | M5 | C4 | Opus | backend-engineer | T-122 | TODO | — | Plan v1.1: support write endpoints → T-186 |
| T-137 | zaghlol-ops CLI for catalog, flags, prices, contributions and support, plus support runbook | M5 | C3 | Sonnet | backend-engineer | T-136, T-186, T-125, T-126, T-127, T-129 | TODO | — | Plan v1.1: C2→C3 (order IDs, operator login) |
| T-138 | Backend observability: OpenTelemetry, metrics, dashboards, alert rules | M5 | C3 | Sonnet | backend-engineer | T-005 | DONE | backend-ci 42528633775 (6/6) @ 4020b9e; mutation runs 42528095105, 42528424746; PR #11 squash-merged; [T-138](05-reviews/T-138.md) APPROVED (r3) | Closes FU-002, FU-008. FU-049 |
| T-139 | Retention purger and log privacy settings | M5 | C2 | Sonnet | backend-engineer | T-122, T-138 | TODO | — |  |
| T-140 | Infrastructure as code and deployment pipeline (staging, prod) | M5 | C4 | Opus | backend-engineer | T-138 | BLOCKED | — | CR-03 / OQ-16: hosting provider & region + PDPL licence decision. Plan v1.1: C3→C4 (KMS keys) |
| T-141 | App BackendClient: generated DTOs, ES256 verification, lazy install registration | M5 | C4 | Opus | flutter-core-engineer | T-006, T-019 | TODO | — |  |
| T-142 | Merchant contribution opt-in and outbox with on-device filters | M5 | C4 | Opus | flutter-core-engineer | T-075, T-019 | TODO | — |  |
| T-143 | Daily sync orchestrator: throttle, back-off, atomic apply, re-categorize | M5 | C3 | Opus | flutter-core-engineer | T-141, T-075, T-142, T-112, T-025, T-144 | TODO | — |  |
| T-144 | Entitlement token verification, trusted time, offline cache and grace | M5 | C4 | Opus | flutter-core-engineer | T-119, T-141, T-180 | TODO | — | Plan v1.1: R5-1 tests are owner-task criteria |
| T-145 | In-app purchase flow, backend verify, background retry and restore | M5 | C4 | Opus | flutter-core-engineer | T-144, T-141, T-178, T-179, T-183 | TODO | — |  |
| T-146 | Paywall S-68, locked previews, upgrade prompt cap and Gold status messages | M5 | C2 | Sonnet | flutter-ui-engineer | T-145, T-144, T-087 | TODO | — |  |
| T-147 | Optional sign-in, account screen S-69, sign-out and delete account | M5 | C4 | Opus | flutter-core-engineer | T-141, T-144, T-145, T-179, T-183 | TODO | — | Plan v1.1: R5-3(a) note |
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
| T-165 | Exclude app data from OS backups and device transfer | M6 | C4 | Opus | native-platform-engineer | T-001 | IN_REVIEW | app-ci 42352212541 (13/13 green) @ eebeaa0, merged as 189acf7; negative proofs 42316160887, 42352248954 | MERGED, device run pending. Code APPROVED, tests SUFFICIENT, security APPROVED (r2). Done only when docs/05-reviews/T-165-device.md passes on a release candidate (F3); F9: add iOS canaries and finish onboarding before steps 5a/5c |
| T-166 | Delete everything (local wipe + backend install delete) | M6 | C4 | Opus | flutter-core-engineer | T-015, T-141, T-152, T-145, T-179 | TODO | — |  |
| T-167 | Zakah engine (hawl, nisab, native-unit dues) | M7 | C4 | Opus | flutter-core-engineer | T-113 | TODO | — |  |
| T-168 | Zakah screen S-46 behind flag with disclaimer | M7 | C2 | Sonnet | flutter-ui-engineer | T-167, T-025, T-087 | TODO | — |  |
| T-169 | Smart ROI general-advice rules with no-names check | M7 | C3 | Sonnet | flutter-core-engineer | T-105 | TODO | — |  |
| T-170 | Smart ROI screen S-51 behind flag | M7 | C2 | Sonnet | flutter-ui-engineer | T-169, T-025, T-087 | TODO | — |  |
| T-171 | Privacy verification suite (sandbox scan, data-boundary proxy, ignore no-trace) | M7 | C4 | Opus | test-engineer | T-166, T-143, T-078, T-149, T-165 | TODO | — |  |
| T-172 | Device end-to-end suites (Android killed-app capture, iOS intents, backup, purchases) | M7 | C3 | Sonnet | test-engineer | T-056, T-067, T-153, T-145, T-147 | TODO | — |  |
| T-173 | Performance benchmarks and CI budgets | M7 | C2 | Sonnet | test-engineer | T-033, T-050, T-105, T-048 | TODO | — |  |
| T-174 | Accessibility and golden coverage pass (130% text, both themes, screen readers) | M7 | C2 | Sonnet | test-engineer | T-054, T-079, T-162, T-107 | TODO | — |  |
| T-175 | Security assessment: MobSF, ZAP, dependency scans, pen test | M7 | C4 | Opus | security-privacy-reviewer | T-171, T-140 | TODO | — |  |
| T-176 | Android release pipeline, Play listings, Data safety and SMS declaration package | M7 | C3 | Sonnet | flutter-core-engineer | T-172, T-171 | TODO | — |  |
| T-177 | iOS release pipeline, privacy labels and App Review notes | M7 | C3 | Sonnet | flutter-core-engineer | T-172, T-171 | TODO | — |  |
| T-178 | AttestationHostApi (Play Integrity standard request, App Attest) and release network security config | M5 | C4 | Opus | native-platform-engineer | T-004 | TODO | — | Plan v1.1 (new) |
| T-179 | SeatKeyHostApi (iOS Secure Enclave seat keys) and Dart seat-key service | M5 | C4 | Opus | native-platform-engineer | T-004, T-141 | TODO | — | Plan v1.1 (new); R-19 device test |
| T-180 | TrustedClockHostApi (monotonic clock with sleep, boot reference) on both platforms | M5 | C4 | Opus | native-platform-engineer | T-004 | TODO | — | Plan v1.1 (new) |
| T-181 | Backend attestation verifiers: Play Integrity decode and App Attest attestation/assertion, with fakes | M5 | C4 | Opus | backend-engineer | T-122 | TODO | — | Plan v1.1 (new) |
| T-182 | Backend seat-key proof verifier and keyed hashes (K_seat), with fakes | M5 | C4 | Opus | backend-engineer | T-122, T-123 | TODO | — | Plan v1.1 (new) |
| T-183 | Dart request-binding library: JCS, strict JSON parser, restore and seat-key hashes over shared vectors | M5 | C4 | Opus | flutter-core-engineer | T-001, T-014 | TODO | — | Plan v1.1 (new) |
| T-184 | Seat service: bind, move, same-iPhone rebind with cap, claimants, reclaim and support-move primitive | M5 | C4 | Opus | backend-engineer | T-122, T-182 | TODO | — | Plan v1.1 (new, from T-132) |
| T-185 | POST /v1/purchases/restore: strict parse, install binding, attestation, seat outcomes and limits | M5 | C4 | Opus | backend-engineer | T-132, T-181, T-182, T-184 | TODO | — | Plan v1.1 (new, from T-132) |
| T-186 | Support seat:move, purchase:detach and purchase:unfreeze endpoints with dispute freeze | M5 | C4 | Opus | backend-engineer | T-136, T-184, T-130, T-131, T-132 | TODO | — | Plan v1.1 (new, from T-136); R6-1 |

## Follow-ups (from reviews)
| ID | From | Item | Owner / target | Status |
|---|---|---|---|---|
| FU-001 | T-005 #1, #8 (partly done on T-006 branch; Dockerfile line + architect sign-off of §4.8/§6 remain) | Add NOT_FOUND, METHOD_NOT_ALLOWED, UNAUTHORIZED (fallback only), PAYLOAD_TOO_LARGE, UNSUPPORTED_MEDIA_TYPE to `backend-api.md` §6; Dockerfile location in `project-structure.md` | solution-architect (docs) | OPEN |
| FU-002 | T-005 #2 | Align log field names with observability §3.2 (or update the doc) before any alerting | T-138 | OPEN |
| FU-003 | T-005 #3 | DB readiness check on health/readiness probe, tested against Testcontainers | T-122 | OPEN |
| FU-004 | T-005 #4–7, #9–10, #12–13 | Backend hardening: real body-not-logged test, SHA-pinned actions, Trivy by digest, 4xx mapping + test, single trace id, Production env in tests, stale-heartbeat test, compose loopback | backend-engineer (small C2 pass, before M5) | OPEN |
| FU-005 | T-005 #11 | `serverTime` as UTC `Z` and fixed in OpenAPI | T-006 (done); global converter tracked in FU-013 | CLOSED |
- **FU-014** (from T-012 security R3-2, low): BGN and CUC are not in the current ISO table, so pre-2026 Bulgarian lev amounts from imports or SMS go to review. Decide whether a later table refresh re-adds withdrawn codes as historic (D-28). Owner: requirements-analyst.
- **FU-015** (T-122 code #6): EF `SetNull` on tracked dependents breaks the `account_linked_by` pairing. Account and install deletes must go through `ExecuteDeleteAsync`/SQL, never tracked graphs. Owner: T-135, T-139.
- **FU-016** (T-122 code #7, #24; Npgsql note): `bootstrap-roles.sql` attribute clauses may need superuser on managed PG; grant CONNECT to the provider's monitoring role if needed; deployed connection strings must use `Maximum Pool Size`. Owner: T-140.
- **FU-017** (T-122 code #8, security F14): `--healthcheck` and the container HEALTHCHECK probe readiness. Liveness must be a process-only check. Owner: T-140.
- **FU-018** (T-122 security R2-3): the digit-run backstop allows only one separator character. Widen it to `[[:space:] .,/_،-]{0,3}` with cases for double spaces, `/`, `_` and the Arabic comma, and fold digits in the API filter first. Owner: T-127 (new migration).
- **FU-019** (T-122 security R2-2): `DatabaseRoleGuard` checks only `current_user`. Also require `session_user = current_user` and run the flag, owner and group checks on `session_user`; add a test with a superuser login and `role=zaghlol_api`. Owner: T-123.
- **FU-020** (T-122 tests N1, security R2-1, code #22; **must land before T-184**): the `installs_before_update` tombstone exemption lets `seat_key_hash` change to any value, and `deleted_at` can be reset. Require `NEW.seat_key_hash IS NULL` in the tombstone branch, make `deleted_at` one-way, and add negative tests. Needs a new migration, because InitialCreate is frozen. Also from code #11/#12: done in round 2. Owner: T-182 or T-184.
- **FU-021** (T-122 code #13): `CreateDbContext(DatabaseRole)` lets any `/v1` handler ask for Admin. Bind the role per endpoint group and test that `/v1` can't get Admin. Owner: T-124, T-136.
- **FU-022** (T-122 code #18): the one-connection readiness pool can stay blocked for Npgsql's connect timeout (15 s). Set `Timeout=2` on the probe string, and add a recovery test against BlackHoleServer. Owner: T-123 or T-140.
- **FU-023** (T-122 code #19, #20; tests N2, N8): the login guard should check full transitive membership (e.g. `pg_write_all_data`, provider admin groups) and exit with a non-zero code on rejection. Owner: T-123 or T-140.
- **FU-024** (T-122 code #21): no runtime role can write `operators`, so audit rows can't be written until operator provisioning adds a grant in its own migration. Owner: T-136.
- **FU-025** (T-122 security F7, F13): an `Include Error Detail` startup guard and server log verbosity for CHECK failures (T-123/T-140); doc fix for account hard delete vs tombstone (architect).
- **FU-026** (T-122 tests N3, N6, N7, N9): sequence privileges, the future-dated audit insert boundary, enforcement of `ApiHostGroup` membership, readiness caching and cancellation tests. Owner: backend test follow-up with T-123.
| FU-006 | T-006 #2 | Android restore: `{productId, purchaseToken}` items or commit to `productsv2` | solution-architect → T-130/T-132 | OPEN (architect decision) |
| FU-007 | T-006 #3 | Open (ignore-unknown) schemas for server-to-server envelopes (Pub/Sub RTDN, ASSN V2) | solution-architect → T-133/T-134 | OPEN (architect decision) |
| FU-008 | T-006 #4, #5 | Apple Android callback transport (query vs form_post); support lookup e-mail out of query string; never log query strings | solution-architect → T-135/T-136/T-138 | OPEN (architect decision) |
| FU-009 | T-006 #8 | Admin draft DELETE + per-entity key format (keywords: keyword+lang) | T-125 | OPEN |
| FU-010 | T-006 #9, #11, #12 | Spectral via package.json + lockfile + pinned Node; YAML float scalars as numbers; Spectral `type[*]` rule | FU-004 hardening pass | OPEN |
| FU-011 | T-006 #14 | Each endpoint task adds a live response-vs-spec test incl. `400 UNKNOWN_FIELD` | T-124, T-128, T-130…T-136 | OPEN |
| FU-013 | T-006 #6, #13, #15, #16 | Remove `installs.os_major` from backend-schema.md (**before T-122**); global UTC-`Z` JSON converter + InstallId UUID v4 pattern (T-124); pin openapi-generator version (T-141) | solution-architect / T-124 / T-141 | OPEN |
| FU-012 | T-006 decision 2 (PO APPROVED 2026-11-05; recording in SRS v1.4) | Record that server-issued version cursors (flagsVersion, pricesAsOf, entitlementIssuedAt, registryVersion) fall under BR-SYNC-03 "catalog/app version" | product owner | OPEN (PO confirm) |

- **FU-027** (T-027 review #2): `insights_explainCashFlow_tip` short branch ("you'll finish in the black") reads as a guarantee; soften it. Owner: T-058.
- **FU-028** (T-027 review #3): roast lines carry emoji in chat; confirm chat bubbles count as mascot lines (voice doc §4). Owner: T-058. Note: Q-23 (disclaimer + Zakah scholar sign-off) must close before the `zakah` and `smart_roi` flags go on.
- **FU-029** (T-002 review #1): `riverpod_lint` not added (custom_lint unusable on Dart 3.13; riverpod_lint 3.x analyzer plugin unverified). Owner: T-024, together with `flutter_riverpod`; verify it reports in CI.
- **FU-030** (T-002 review #2, #6; **before parsing work, T-032/T-033**): `no_double_money` misses `double.parse`/`tryParse`/`num.parse`/`.toDouble()`, inferred doubles and double literals in `zaghlol_parsing`; zero scanned files exits 0. Owner: a small lint-hardening task (task-planner to add) or T-013.
- **FU-031** (T-002 review #3; **before T-024 screens**): `no_ui_string_literals` checks only methods named `build`, and the ancestor allow-list is too broad. Owner: T-022 (if not done there) else T-024.
- **FU-032** (T-002 review #4): `no_print_outside_debug` misses `core.print`, `stdout.write`, `developer.log` and tear-offs. Owner: T-021.
- **FU-033** (T-002 review #5, T-014 review #2): `safe_exception_required` checks only class declarations; direct `throw FormatException(..)` in parsing/db, enum/mixin exceptions and non-literal `SafeException(...)` codes pass, and the code-shape check is an `assert` only. Owner: T-021.
- **FU-034** (T-014 review #1): validate `PlatformFailure.platformCode` as UPPER_SNAKE like `SafeException`. Owner: T-021 or the first platform-error task (T-008).
- **FU-035** (T-014 review #3; before its first publisher): add `cycleKey` to `BudgetThresholdCrossed` for `fired_alerts` dedupe. Owner: T-095.
- **FU-036** (T-014 review #4): `MascotTrigger` `pose`/`reason` should be enums or documented constants. Owner: T-098.
- **FU-037** (T-014 review #5): make `TransactionsChanged` sets unmodifiable; align names with docs (`accounts`, `cycles`). Owner: T-046.
- **FU-038** (T-014 review #6): `Failure.toString` uses `runtimeType` (obfuscated in release). Owner: T-021.
- **FU-039** (T-028 review #2, #6): `privacy_delete_body` says "security keys" are deleted but iPhone seat keys stay; reword. Owner: T-058.
- **FU-040** (T-028 review #3): delete-everything dialog should say Drive/iCloud backups, the store purchase and the account are untouched (check FR-ONB-08). Owner: T-087.
- **FU-041** (T-028 review #4, #5): PO/security decide whether redacted budget alerts keep the category name (Q-33); UX picks «احذف» vs «امسح» for the delete confirmation word (Q-39). Owner: PO / UX.
- **FU-042** (T-004 #1): the Pigeon stale check watches three fixed output dirs; fail if an output path falls outside them. Owner: T-008.
- **FU-043** (T-004 #2): add the generated `.g.swift` files to the Runner target and confirm it builds. Owner: first iOS native task (T-009/T-062).
- **FU-044** (T-022 #1, deviation): bundle IBM Plex Sans Arabic (4 TTFs + `fonts:` block) and regenerate goldens; until then goldens use Ahem. Owner: PO supplies the files; T-024 wires them.
- **FU-045** (T-022 #2): `ZMoneyText` with `masked: true` and no `maskedText` shows the real amount; make it required. Owner: T-117.
- **FU-046** (T-022 #3, #5): require semantics labels when clear/dismiss callbacks are set; real `ZColors.lerp`/`copyWith`. Owner: T-024.
- **FU-047** (T-022 #4, UX): 1.3x goldens for chips, pills, segmented, money text and sheet (T-053). UX to confirm the dark tokens §0 leaves undefined (warning, danger, zaghlolBg, incomeBg) before T-053.
- **FU-048** (T-123 code #2, #4–#7, #9–#10; security L-1, L-3, L-4, I-1…I-5; tests G1, G2, G4–G7): see `docs/05-reviews/T-123.md` and its three reports for each item and owner (T-124, T-125, T-128, T-132, T-138, T-140, T-141, backend tooling).
- **FU-049** (T-138 code #2, #5–#6, the 499 test; tests m1–m8; security F1–F9): see `docs/05-reviews/T-138.md` and its three reports for each item and owner (T-124, T-125, T-135, T-136, T-140, T-138 follow-up). **Before T-140:** strip Npgsql exception span events. **Before T-125:** use fixed value sets for metric tags.
- **FU-050** (T-007 code #1–#7; security L-1…L-3, I-1…I-5): attestation check only covers the Linux host binary and isn't pinned to the upstream release workflow/tag; APK regex also matches upstream `libsqlite3.so`; CI key file not removed on failure; ADR-002 cites bf2419e runs. See `docs/05-reviews/T-007*.md`. Owners: T-015 (key-handling rules, error codes), T-171 release checklist (mobile binary attestation), CI tooling.
- **FU-051** (T-013 minors #1–#5, nits): `$` with a non-candidate fallback fails (policy decision for templates); trailing `.`/`,` after a number fails (template captures must exclude it); `0,123` accepted; U+2060/U+00AD not stripped; no-echo fuzz check is vacuous. See `docs/05-reviews/T-013.md`. Owner: T-032.
- **FU-052** (T-124 code minors/nits; security S-2…S-7): **Before T-130/T-135 use `WithIdempotency`:** S-2, the idempotency session holds a DB connection/transaction while the handler opens another (pool exhaustion) — needs a design note in T-130. Also S-3 (no guard against storing `rotateInstallToken`), S-4 (DELETE race leaves a row ≤24 h), S-6 (key not in encryption context), replay drops handler headers, no rotated-kid re-sign test. See `docs/05-reviews/T-124*.md`. Owners: T-130, T-135, T-140.
- **FU-053** (PC runner): fails for local reasons — Docker not running, `KeyRingTests.AnOffCurvePointIsRejected` throws PlatformNotSupportedException on Windows, CRLF vs LF in `iso4217_table_test`, and once Application Control blocked it. Owner: PO (Docker) + backend/app tooling.
- **FU-054** (local-ci container review minors): no timeout/container name on `docker run` (a hung step blocks the loop); NTFS bind mount is slow; Windows-containers mode not detected; no Gradle cache volume for APK steps; bare `\r` progress lines in logs. See `docs/05-reviews/local-ci-container.md`. Owner: CI tooling.
- **FU-055** (PC runner, first Linux-container run 2026-11-10): `SeededSeriesTests.EverySeriesIsExportedAtZeroBeforeAnyEvent` failed once (series `zaghlol.audit_alert.fired rule=support_moves_per_purchase_90d` missing) while it passes in GitHub CI — likely a timing/ordering race in the MeterListener collection. Owner: T-138 follow-up.

## Log
| Date | Event |
|---|---|
| 2026-11-03 | Phase 4 plan approved; Phase 5 opened. Toolchain check: blocked (BLK-01). |
| 2026-11-03 | BLK-01 resolved via GitHub Actions. T-001 and T-005 started in parallel (separate worktrees, lanes A/B). |
| 2026-11-03 | T-005 DONE: code-reviewer APPROVED (14 minor/nit findings → FU-001…005), CI green, squash-merged to main. T-006 unblocked. |
| 2026-11-03 | T-006 started (backend-engineer, Sonnet), scoped to backend/** + backend-api.md §6 to avoid conflict with T-001. |
| 2026-11-03 | T-001 implementation finished; Lead verified CI (5/5 green) and diff; code review started. |
| 2026-11-03 | T-001 review round 1: CHANGES_REQUESTED (F1–F3 majors; F4/F6/F8/F12/F15 cheap fixes added; others deferred to T-002/T-003/T-023/T-141/T-165/T-176). T-006 implemented, CI green, in review. |
| 2026-11-05 | Both agents paused by a usage limit; resumed. |
| 2026-11-05 | T-006 review round 1: CHANGES_REQUESTED (1 major: `osMajor` not in BR-SYNC-03 → dropped per SRS precedence). Follow-ups FU-006…012 logged. |
| 2026-11-05 | T-006 DONE: re-review APPROVED (round 2), CI green, squash-merged to main. Unblocks T-124, T-141 (with other deps). FU-013 logged. |
| 2026-11-05 | T-001 DONE: re-review APPROVED (round 2), CI 10/10 green, squash-merged. Deferred findings appended to the owning task files. T-165 to run before T-015/T-016. |
| 2026-11-05 | Wave 2 started: T-003 (app CI + regen workflow). Design notes for T-012, T-165 in progress. Held: T-002/T-004/T-022 (need T-003 lockfile/golden regen; T-002 and T-004 both change pubspec.lock → serialize), T-014 (same package as T-012), T-122 (needs FU-013), T-123/T-138 (after architect API decisions). |
| 2026-11-05 | Design notes for T-012 and T-165 merged. Their follow-ups were added to T-015/T-016 (orphaned-DB wipe) and T-017/T-019 (money CHECK constraints). The FU-api-decisions branch (CI green) is in security-privacy review. |
| 2026-11-05 | FU-api-decisions security review: CHANGES_REQUESTED (2 blockers: restore token sharing, Apple nonce; 4 majors). Findings 2–8, 10–12 fixed at 8fe1251 (CI green). |
| 2026-11-05 | PO decisions: D1 Gold restore = 3-seat limit + device attestation (Play Integrity / App Attest; BR-SYNC-03 amended); D2 support-lookup audit rows kept 1 year; D3/FU-012/A-47/Smart-Switch outcome approved; funds currency codes shown at end of picker. Architect applying D1/D2; requirements-analyst recording SRS v1.4. |
| 2026-11-05 | T-003 implemented (app-ci + two-job app-regen), CI green; in review. FU-api-decisions round 2 (D-45/46/47 design) in security re-review. Throwaway branch task/T-003-throwaway-red can't be deleted through the agent proxy; left for the owner. |
| 2026-11-05 | FU-api-decisions security re-review (round 2): CHANGES_REQUESTED. 1 blocker (R2-1: attestation not bound to install), 3 majors. Round-1 findings 2–12 confirmed resolved. |
| 2026-11-06 | PO decisions: D-52 Gold on ONE phone, movable once per 30 days (replaces 3 seats); D-53 FR-GOLD-09 "expired" = Play only; D-54 no self-service relink after phone change (support only). Container restart lost the architect's round-2 work and the T-003 review; both restarted. requirements-analyst recording SRS v1.5. |
| 2026-11-06 | SRS v1.5 merged (D-52…D-54; OQ-19 opened). T-003 review round 1: CHANGES_REQUESTED (F1 major: regen commit job could be made to run repo code through a symlinked destination); fixes in progress. |
| 2026-11-06 | BLK-05: all GitHub Actions jobs are refused because of an account billing block (Lead verified the annotation on run 42164778967). Verification is paused for T-003 and FU-api-decisions. |
| 2026-11-06 | FU-api-decisions security round 3 (@ e00fd92): CHANGES_REQUESTED. All R2 findings resolved; 2 majors: R3-1 device-clock rollback defeats the offline bound, R3-2 weak support-move ownership proof. Report saved in docs/05-reviews/in-progress/. |
| 2026-11-06 | PO decisions: D-55 recognise iPhone reinstall via Keychain secret (Android reinstall = move); D-56 support move restarts the 30-day window; D-57 support requires a live-checked store order ID, one agent, audited undo; D-58 free reclaim once per purchase; D-59 plan change from another phone = move; D-60 offline window 7 days (3 d token + 4 d grace). Architect on round 4; analyst writing SRS v1.6. |
| 2026-11-06 | SRS v1.6 + D-61 merged (bdb4091). FU-api-decisions round 4 pushed at 9ae53aa: iOS Secure Enclave seat key (D-55), trusted time (R3-1), support order-ID check + correction/detach (D-57), 3+4-day tokens (D-60). Not CI-verified. Security round 4 review running. Task impacts saved in docs/05-reviews/in-progress/. |
| 2026-11-06 | FU-api security round 4 (@ 9ae53aa): CHANGES_REQUESTED. Majors: R4-1, the iPhone seat-key proof can be relayed from a jailbroken phone; R4-2, a replayed signed server time defeats trusted time. PO: D-62 keep multi-key seatKeys, linkability accepted; D-63 at most 2 same-iPhone rebinds per 30 days; D-64 30-day dispute freeze after a support correction. Architect round 5 and SRS v1.7 in progress. |
| 2026-11-06 | FU-api round 5 pushed at d296a7f (R4-1 element-0 binding + rebind cap + keys in clientDataHash; R4-2 time nonce; R4-3 lb state; D-62…D-65). Architect deviation: a sign-in over-cap rebind is never refused only for a trusted seat key (PO to confirm). Security round 5 running. BLK-05 still open (rechecked 06:19Z). |
| 2026-11-06 | PO: stop using GitHub Actions; iOS verification deferred. New build environment: a local CI runner on the PO's Windows PC (C:\Projects\Zaghlol\.zaghlol-local-ci). It runs a fixed app+backend pipeline on a separate clone, the Lead queues jobs, and results come back as logs. Waiting for the PO to start it once. |
| 2026-11-06 | PO made the repo public: GitHub Actions runs again for free, including macOS/iOS (BLK-05 resolved). The local Windows runner stays as a fallback. FU-api security round 5: one blocker (R5-1: the app doesn't check that the token's `sub` is its own install). Architect fixing R5-1/R5-2 and adding the support-lead unfreeze (R5-5, PO no preference, so the recommended option was taken). The R5-3 decision on iOS sign-in attestation is still open. T-003 CI re-run started. |
| 2026-11-06 | FU-api-decisions MERGED (be7dcd1): security-privacy review APPROVED after 5 rounds plus a delta check; backend-ci green (42207189180, 34/34 contract tests). Residuals listed in docs/05-reviews/FU-api-decisions.md. Open: R5-3 PO choice (iOS sign-in attestation), R6-1 (T-136). Next: task-planner applies the task impacts and adds the 2 new C4 tasks. |
| 2026-11-06 | Task plan v1.1 (task-planner): FU-api round 4–6 impacts and the final review's owner-task criteria applied to T-122…T-147 plus T-004/T-014/T-028/T-162/T-166/T-171/T-172/T-176/T-177. New M5 tasks T-178…T-186 (all C4/Opus): native attestation, seat keys, trusted clock; backend attestation and seat-key verifiers; Dart binding library; seat service and restore (split from T-132); support write endpoints (split from T-136). Class changes: T-137 C2→C3, T-138 C2→C3, T-140 C3→C4. 186 tasks. Awaiting PO approval of v1.1; R5-3 and R6-1 PO choices still open. |
| 2026-11-06 | PO APPROVED task plan v1.1. T-003 round 2 in review. |
| 2026-11-06 | Design notes started for backend lane B: T-122 (C4), T-123 (C4), T-138 (C3). They run alongside the T-003 review; no file overlap. |
| 2026-11-06 | T-003 DONE: review APPROVED in round 2; CI 13/13 green, including iOS dev/staging/prod; squash-merged. Unblocks T-002, T-004, T-012, T-022, T-165. After merge: dispatch app-regen once (workflow_dispatch) and enable branch protection on main (PO). |
| 2026-11-06 | T-012 and T-165 started in parallel (no shared files). Held: T-002 and T-004 (both change pubspec.lock; run after T-012), T-022 (after T-002 lints). |
| 2026-11-07 | Design notes for T-122/T-123/T-138 merged (1c68de5). Lead decisions: IEnvelopeCipher goes in T-123 (T-124 now depends on T-123); the cloud KMS adapter goes in T-140; the signing-key ring is configuration, not a `signing_keys` table; accounts are hard-deleted (T-135 to fix the retention wording); operator UUIDs are allowed in operator alerts. |
| 2026-11-07 | T-012 implemented (CI green), in C4 review. Blocker: the ISO 4217 snapshot was rebuilt from memory because the build environment can't reach six-group.com; PO asked to download it. |
| 2026-11-07 | T-012 round 1 reviews done: code and security CHANGES_REQUESTED, tests SUFFICIENT. All fixes sent to the implementer in one round. Follow-ups routed to T-021, T-046, T-149, T-155. |
| 2026-11-07 | T-165 implemented. Lead verified CI: green run, and the negative proof is red in 7 jobs as intended. C4 reviews started. |
| 2026-11-07 | T-165 round 1: code APPROVED, tests SUFFICIENT, security CHANGES_REQUESTED. Fixes sent. Follow-ups routed to T-008/015/016/021/062/063/065/149/150/166/171/176. |
| 2026-11-07 | T-122 implemented: 25 tables, 39 CHECKs (each with a negative test), grants matrix, readiness 503, push-triggered migration workflow. CI green; C4 reviews started. |
| 2026-11-07 | T-122 round 1: code + security CHANGES_REQUESTED, tests SUFFICIENT. Fixes folded into a regenerated InitialCreate (unshipped). Lead approved the push-mode migration workflow. PO asked to add a ruleset on main. |
| 2026-11-07 | T-165 merged (189acf7) after all three approvals; stays IN_REVIEW until the device run. T-012 round-2 code review APPROVED pending the SIX snapshot. |
| 2026-11-07 | PO supplied the genuine SIX list-one.xml; T-012 round 3 (snapshot swap + R2-1/R2-2) started. T-002 and T-026 started. PO created ruleset 'main requirs PR' (PR required, no force-push/deletion, no bypass), enforcement still disabled; once active the Lead merges via PRs. |
| 2026-11-07 | Container restart stopped the T-122, T-002 and T-026 agents. Lead saved the uncommitted worktree changes as WIP commits (T-122 4021a31, T-026 5c7b38a) and resumed all three. T-012 round 3: the genuine snapshot added XAD as a funds code; PO decided to hide it (D-67); the exclusion fix is in progress. |
| 2026-11-07 | T-012 r3 green (cb1859c) and T-122 r2 green (d5943be); delta re-reviews sent. T-026 code review CHANGES_REQUESTED (F-1 to F-3), tests SUFFICIENT; round 2 in progress. PO decisions D-68 (late-month salary suggests the 1st) and D-69 (hidden accounts still count). |
| 2026-11-07 | T-012 DONE: merged after round 3 (all three reviews APPROVED). |
| 2026-11-08 | New Lead session. T-027 DONE (docs-only review APPROVED, no blockers/majors); copy-deck check script added as docs/workflow/tools/copy_deck_check.py. T-002 resumed and T-014 started (both Sonnet). Main ruleset now Active: merges go through PRs. |
| 2026-11-08 | Lead merged PRs #1 (T-027), #2 (T-122), #4 (T-002), #3 (T-014, after re-running CI on a main-merged head) and #5 (T-028, round 2 after one major). PO authorised the Lead to merge approved PRs. Started T-004, T-022 (Sonnet) and T-123 (Opus). FU-029…FU-041 logged. |
| 2026-11-09 | Merged #7 (T-004), #8 (T-123), #9 (T-022), #10 (Balanced rules, 2 tasks at a time, runner LF fix), #11 (T-138). 15/186 done. T-007 (Opus) and T-124 (design note, Sonnet) in progress. |
| 2026-11-09 | New Lead session (PO linked GitHub, upgraded Flutter). Merged #13 (T-007), #14 (T-013), #15 (T-124, one security fix round). 18/186 done. FU-050…FU-053 logged. |
| 2026-11-10 | PC runner moved to Linux Docker containers (#17) with a locally built Flutter 3.47.9 image; first runs: app checks all PASS, backend build/format PASS, Testcontainers work. FU-054, FU-055 logged. |
