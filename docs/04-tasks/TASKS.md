# Task Board — Zaghlol implementation plan

| | |
|---|---|
| Version | 1.0 — **APPROVED 2026-11-03** |
| Phase | 4 — Task breakdown |
| Inputs | SRS v1.3, Phase 2 design (approved), Phase 3 technical spec v1.0 (approved) |
| Date | 2026-11-03 |


**177 tasks · 48 user stories · 21 epics · 8 milestones.** Complexity: Low 3 · Medium 75 · High 49 · High-critical 47 · external/human 3. Models: Haiku 3 · Opus 53 · Sonnet 118 · — (human) 3.


Status legend: TODO · IN_PROGRESS · IN_REVIEW · CHANGES_REQUESTED · DONE · BLOCKED


## How to read a task
Every task file has: ID, description, technical details, dependencies, affected components, complexity (Low/Medium/High), recommended model and agent, acceptance criteria, testing requirements, parallelization. Complexity maps to the routing classes in `docs/workflow/model-routing.md`: Low = C1, Medium = C2, High = C3, High (critical) = C4 (automatic for crypto, keys, permissions & native receivers, schema migrations, billing/entitlements, sign-in tokens, Zakah, money primitives, the backend data boundary).


## Milestones
| Milestone | Goal | Tasks |
|---|---|---|
| **M0 — Foundations & spikes** | Repo, CI, encrypted DB, money/l10n/theme/routing core, backend skeleton, risk spikes. | 28 |
| **M1 — Android capture → Home (vertical slice)** | A bank SMS on Android becomes a categorized transaction on the Home screen, offline, encrypted. | 29 |
| **M2 — iOS capture, transactions & categorization** | Shortcuts/Apple Pay/share capture on iOS; full transactions, review queue, accounts & cards, all institution templates. | 29 |
| **M3 — Money brain** | Transfers, refunds, splits, reimbursements, budgets & payday cycle, recurring, notifications, mascot. | 18 |
| **M4 — Insights, chat, voice & wealth** | 12 charts + explanations, Ask Zaghlol, voice logging, wealth & net worth, multi-currency ≈ view, share cards, widgets. | 17 |
| **M5 — Backend services & Zaghlol Gold** | Install/sync/catalog/flags/prices, purchases & entitlements, store notifications, optional sign-in, operator CLI. | 26 |
| **M6 — Backup, import/export, OCR, settings & security** | Encrypted Drive/iCloud backup & restore, CSV/XLSX/PDF/online statements, OCR, settings, app lock, delete everything. | 19 |
| **M7 — Flagged features, hardening & launch** | Zakah & ROI behind flags, privacy/perf/a11y/security verification, store release pipelines. | 11 |

## M0 — Foundations & spikes

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-001](tasks/T-001.md) | Create mono-repo scaffold with pub workspace, app flavors and pure-Dart packages | US-01-1 | Medium | Sonnet | flutter-core-engineer | — | A | 1 | TODO |
| [T-002](tasks/T-002.md) | Add custom lint rules (no double in money, no UI string literals, no print) | US-01-1 | Medium | Sonnet | flutter-core-engineer | T-001 | A | 2 | TODO |
| [T-003](tasks/T-003.md) | App CI pipeline (format, analyze, unit, golden, native unit) | US-01-1 | Medium | Sonnet | flutter-core-engineer | T-001 | A | 2 | TODO |
| [T-004](tasks/T-004.md) | Pigeon setup and stale-generation check | US-01-1 | Medium | Sonnet | flutter-core-engineer | T-001 | A | 2 | TODO |
| [T-005](tasks/T-005.md) | Backend solution scaffold, Docker Compose and CI | US-01-1 | Medium | Sonnet | backend-engineer | — | B | 1 | TODO |
| [T-006](tasks/T-006.md) | OpenAPI v1 spec and contract-test harness | US-13-1 | Medium | Sonnet | backend-engineer | T-005 | B | 2 | TODO |
| [T-007](tasks/T-007.md) | SPK-05: encrypted SQLite (SQLite3MultipleCiphers) + FTS5 trigram on both platforms | US-01-2 | High* | Opus | flutter-core-engineer | T-001 | A | 2 | TODO |
| [T-008](tasks/T-008.md) | SPK-01: Android receiver → spool → WorkManager → headless engine latency | US-01-2 | High* | Opus | native-platform-engineer | T-001, T-004 | D | 3 | TODO |
| [T-009](tasks/T-009.md) | SPK-03: can an iOS App Intent process immediately with a headless Flutter engine? | US-01-2 | High* | Opus | native-platform-engineer | T-001, T-004 | E | 3 | TODO |
| [T-010](tasks/T-010.md) | SPK-02: OCR accuracy on synthetic InstaPay/wallet receipts | US-01-2 | High | Sonnet | native-platform-engineer | T-001 | D | 2 | TODO |
| [T-011](tasks/T-011.md) | SPK-04: on-device ar-EG speech availability across the device matrix | US-01-2 | Medium | Sonnet | native-platform-engineer | T-001 | D | 2 | TODO |
| [T-012](tasks/T-012.md) | Money and Currency value types with ISO 4217 table | US-02-2 | High* | Opus | flutter-core-engineer | T-001 | A | 2 | TODO |
| [T-013](tasks/T-013.md) | Text & amount normalization utilities (digits, separators, groupings) | US-05-1 | High | Sonnet | parsing-engine-engineer | T-012 | F | 3 | TODO |
| [T-014](tasks/T-014.md) | Result/Failure types, SafeException and domain event bus | US-02-1 | Medium | Sonnet | flutter-core-engineer | T-001 | A | 2 | TODO |
| [T-015](tasks/T-015.md) | Secure key bootstrap for the database key | US-02-1 | High* | Opus | flutter-core-engineer | T-007 | A | 3 | TODO |
| [T-016](tasks/T-016.md) | AppDatabase v1 skeleton: encrypted open, isolate, migration harness | US-02-1 | High* | Opus | flutter-core-engineer | T-015 | A | 4 | TODO |
| [T-017](tasks/T-017.md) | Schema batch A: accounts, balances, raw messages, transactions (+FTS), transfers, offsets, splits | US-06-1 | High* | Opus | flutter-core-engineer | T-016 | A | 5 | TODO |
| [T-018](tasks/T-018.md) | Schema batch B: categories, catalog, rules, budgets, alerts, summaries, recurring | US-07-1 | High* | Opus | flutter-core-engineer | T-016 | A | 5 | TODO |
| [T-019](tasks/T-019.md) | Schema batch C: wealth, prices, Zakah, capture controls, review, settings, outbox, misc | US-02-1 | High* | Opus | flutter-core-engineer | T-016 | A | 5 | TODO |
| [T-020](tasks/T-020.md) | Settings repository with typed accessors and defaults | US-18-1 | Medium | Sonnet | flutter-core-engineer | T-019 | A | 6 | TODO |
| [T-021](tasks/T-021.md) | Redacting local diagnostic log | US-21-1 | High | Sonnet | flutter-core-engineer | T-019, T-014 | A | 6 | TODO |
| [T-022](tasks/T-022.md) | Design tokens, Mint Fresh/Jade Night themes and base components | US-02-3 | Medium | Sonnet | flutter-ui-engineer | T-001 | G | 2 | TODO |
| [T-023](tasks/T-023.md) | Localization scaffold, digits mode and money/date formatting | US-02-2 | Medium | Sonnet | flutter-core-engineer | T-012, T-020 | A | 7 | TODO |
| [T-024](tasks/T-024.md) | App shell: routing, platform tab bars, Add button, deep links | US-02-3 | Medium | Sonnet | flutter-ui-engineer | T-022, T-023 | G | 8 | TODO |
| [T-025](tasks/T-025.md) | Feature flags service (default OFF) | US-13-1 | Medium | Sonnet | flutter-core-engineer | T-019 | A | 6 | TODO |
| [T-026](tasks/T-026.md) | Copy deck part 1: onboarding, capture, Home, transactions, review, accounts | US-20-1 | High | Opus | ux-designer | — | C | 1 | TODO |
| [T-027](tasks/T-027.md) | Copy deck part 2: insights, budget, bills, money, chat, voice, roast, explanations | US-20-1 | High | Opus | ux-designer | — | C | 1 | TODO |
| [T-028](tasks/T-028.md) | Copy deck part 3: settings, Gold, backup, import/export, notifications, errors, legal | US-20-1 | High | Opus | ux-designer | — | C | 1 | TODO |

## M1 — Android capture → Home (vertical slice)

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-029](tasks/T-029.md) | Generate ARB files from copy deck (part 1) | US-02-2 | Low | Haiku | boilerplate-engineer | T-023, T-026 | C | 8 | TODO |
| [T-030](tasks/T-030.md) | Catalog seed pipeline and 14 system categories | US-07-1 | Medium | Sonnet | flutter-core-engineer | T-018 | A | 6 | TODO |
| [T-031](tasks/T-031.md) | Convert real SMS/notification/statement samples into synthetic fixtures (OQ-04/18) | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-013 | F | 4 | BLOCKED |
| [T-032](tasks/T-032.md) | Template registry format, loader and registry_lint CLI | US-05-1 | High | Sonnet | parsing-engine-engineer | T-013 | F | 4 | TODO |
| [T-033](tasks/T-033.md) | Parsing pipeline stages 1–7 and ParseResult | US-05-1 | High | Sonnet | parsing-engine-engineer | T-032, T-012 | F | 5 | TODO |
| [T-034](tasks/T-034.md) | Merchant cleaning and normalized merchant key | US-07-1 | Medium | Sonnet | parsing-engine-engineer | T-013 | F | 4 | TODO |
| [T-035](tasks/T-035.md) | Capture Guard rules in Dart, shared golden cases and config generator | US-03-1 | High* | Opus | parsing-engine-engineer | T-032 | F | 5 | TODO |
| [T-036](tasks/T-036.md) | Templates + fixtures: NBE, CIB, Banque Misr, QNB | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-037](tasks/T-037.md) | Templates + fixtures: InstaPay scenarios and mobile wallets | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-038](tasks/T-038.md) | Android Capture Guard (Kotlin) with config reader | US-03-1 | High* | Opus | native-platform-engineer | T-035, T-008 | D | 6 | TODO |
| [T-039](tasks/T-039.md) | Android encrypted spool + spool host API | US-03-1 | High* | Opus | native-platform-engineer | T-004, T-008 | D | 4 | TODO |
| [T-040](tasks/T-040.md) | SMS receiver (multipart, Guard, spool, enqueue) in prodSms flavor | US-03-1 | High* | Opus | native-platform-engineer | T-038, T-039 | D | 7 | TODO |
| [T-041](tasks/T-041.md) | IngestionWorker with headless Flutter engine and foreground events | US-03-1 | High* | Opus | native-platform-engineer | T-039, T-008 | D | 5 | TODO |
| [T-042](tasks/T-042.md) | Inbox reader for historical scan (sender-filtered, paged) | US-03-2 | High* | Opus | native-platform-engineer | T-004, T-038 | D | 7 | TODO |
| [T-043](tasks/T-043.md) | Bank notification listener service | US-03-3 | High* | Opus | native-platform-engineer | T-038, T-039 | D | 7 | TODO |
| [T-044](tasks/T-044.md) | Android capabilities and permission flows host API | US-03-4 | High* | Opus | native-platform-engineer | T-040, T-043 | D | 8 | TODO |
| [T-045](tasks/T-045.md) | Accounts repository: auto-create, default cash, per-currency balances | US-06-1 | High | Sonnet | flutter-core-engineer | T-017 | A | 6 | TODO |
| [T-046](tasks/T-046.md) | IngestRawMessages use case (dedupe, merge, persist, ack, events) | US-06-1 | High* | Opus | flutter-core-engineer | T-033, T-045, T-014, T-035 | A | 7 | TODO |
| [T-047](tasks/T-047.md) | Capture module (app side): guard config writer, spool orchestrator, degraded mode | US-03-1 | High | Sonnet | flutter-core-engineer | T-046, T-039, T-035 | A | 8 | TODO |
| [T-048](tasks/T-048.md) | Historical inbox scan with progress (Android) | US-03-2 | High | Sonnet | flutter-core-engineer | T-047, T-042 | A | 9 | TODO |
| [T-049](tasks/T-049.md) | Review queue domain and repository | US-06-2 | Medium | Sonnet | flutter-core-engineer | T-019, T-046 | A | 8 | TODO |
| [T-050](tasks/T-050.md) | Transactions repository: query, search, CRUD, soft delete | US-06-3 | Medium | Sonnet | flutter-core-engineer | T-017 | A | 6 | TODO |
| [T-051](tasks/T-051.md) | Payday cycle engine, safe-to-spend, burn line and cycle summaries | US-09-1 | High | Sonnet | flutter-core-engineer | T-012, T-018, T-050 | A | 7 | TODO |
| [T-052](tasks/T-052.md) | Home read model and persistent card filter | US-10-2 | Medium | Sonnet | flutter-core-engineer | T-051, T-050, T-045, T-049 | A | 9 | TODO |
| [T-053](tasks/T-053.md) | ZaghlolAvatar widget with static fallback and reduce-motion | US-10-3 | Medium | Sonnet | flutter-ui-engineer | T-022 | G | 3 | TODO |
| [T-054](tasks/T-054.md) | Home screen S-10 (iOS and Android variants) | US-10-2 | Medium | Sonnet | flutter-ui-engineer | T-052, T-024, T-029, T-053 | G | 10 | TODO |
| [T-055](tasks/T-055.md) | Welcome screen S-01 with language toggle and restore entry | US-10-1 | Medium | Sonnet | flutter-ui-engineer | T-024, T-029, T-053 | G | 9 | TODO |
| [T-056](tasks/T-056.md) | Android capture setup S-02 with live scan and degraded variant | US-10-1 | Medium | Sonnet | flutter-ui-engineer | T-055, T-044, T-048 | G | 10 | TODO |
| [T-057](tasks/T-057.md) | Scan results screen S-06 «دي كروتك؟» | US-10-1 | Medium | Sonnet | flutter-ui-engineer | T-056, T-045 | G | 11 | TODO |

## M2 — iOS capture, transactions & categorization

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-058](tasks/T-058.md) | Native Egyptian-speaker review of the copy deck | US-20-1 | Medium | — (human) | external | T-026, T-027, T-028 | C | 2 | TODO |
| [T-059](tasks/T-059.md) | Compile the 600+ Egyptian merchant seed list (OQ-05) | US-20-1 | Medium | — (human) | external | T-030 | C | 7 | TODO |
| [T-060](tasks/T-060.md) | Android share/paste intake (text, image, PDF, CSV) | US-03-4 | High | Sonnet | native-platform-engineer | T-004 | D | 3 | TODO |
| [T-061](tasks/T-061.md) | iOS Capture Guard (Swift) with config reader | US-04-1 | High* | Opus | native-platform-engineer | T-035, T-009 | E | 6 | TODO |
| [T-062](tasks/T-062.md) | iOS encrypted spool, host API and background refresh | US-04-1 | High* | Opus | native-platform-engineer | T-004, T-009 | E | 4 | TODO |
| [T-063](tasks/T-063.md) | App Intents for Message and Wallet automations | US-04-1 | High* | Opus | native-platform-engineer | T-061, T-062 | E | 7 | TODO |
| [T-064](tasks/T-064.md) | Shortcut package, iCloud link and setup checker | US-04-1 | High | Sonnet | native-platform-engineer | T-063 | E | 8 | TODO |
| [T-065](tasks/T-065.md) | iOS Share Extension (text, image, PDF) | US-04-2 | High* | Opus | native-platform-engineer | T-062 | E | 5 | TODO |
| [T-066](tasks/T-066.md) | Capture module iOS integration (drain, BG refresh, checker state) | US-04-1 | High | Sonnet | flutter-core-engineer | T-047, T-062, T-064 | A | 9 | TODO |
| [T-067](tasks/T-067.md) | iOS capture setup S-03 (add Shortcut, check setup, first expense) | US-10-1 | Medium | Sonnet | flutter-ui-engineer | T-055, T-066 | G | 10 | TODO |
| [T-068](tasks/T-068.md) | Templates + fixtures: Egyptian banks batch 1 | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-069](tasks/T-069.md) | Templates + fixtures: Egyptian banks batch 2 | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-070](tasks/T-070.md) | Templates + fixtures: BNPL (valU, Sympl, Souhoola, Shahry, Aman, Forsa, Contact) | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-071](tasks/T-071.md) | Templates + fixtures: Wise, Revolut, Monzo, bunq, N26, Payoneer | US-05-1 | High | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-072](tasks/T-072.md) | Templates + fixtures: HDFC, Paytm, Al Rajhi, Emirates NBD/Liv, GCC (S rows) | US-05-1 | Medium | Sonnet | parsing-engine-engineer | T-033 | F | 6 | TODO |
| [T-073](tasks/T-073.md) | Generic parser for unknown financial senders | US-05-2 | High | Sonnet | parsing-engine-engineer | T-033, T-034 | F | 6 | TODO |
| [T-074](tasks/T-074.md) | Merchant rules repository and apply-to-past | US-07-1 | Medium | Sonnet | flutter-core-engineer | T-018, T-050 | A | 7 | TODO |
| [T-075](tasks/T-075.md) | Categorizer with fuzzy merchant matching | US-07-1 | High | Sonnet | parsing-engine-engineer | T-034, T-018, T-074, T-030 | F | 8 | TODO |
| [T-076](tasks/T-076.md) | Re-parse job after registry version bump | US-06-2 | High | Sonnet | flutter-core-engineer | T-046, T-032 | A | 8 | TODO |
| [T-077](tasks/T-077.md) | Bulk edit and undo use case | US-06-3 | High | Sonnet | flutter-core-engineer | T-050, T-074 | A | 8 | TODO |
| [T-078](tasks/T-078.md) | Ignore rules domain: per card/channel, before-seen, keep/delete, re-scan | US-06-4 | High | Sonnet | flutter-core-engineer | T-047, T-050 | A | 9 | TODO |
| [T-079](tasks/T-079.md) | Transactions list S-11 with filters, search and selection mode | US-06-3 | Medium | Sonnet | flutter-ui-engineer | T-050, T-077, T-024, T-029 | G | 9 | TODO |
| [T-080](tasks/T-080.md) | Transaction detail S-12 and add/edit sheet S-13 | US-06-3 | Medium | Sonnet | flutter-ui-engineer | T-050, T-075, T-045, T-029 | G | 9 | TODO |
| [T-081](tasks/T-081.md) | Review queue S-14 | US-06-2 | Medium | Sonnet | flutter-ui-engineer | T-049, T-074, T-029 | G | 9 | TODO |
| [T-082](tasks/T-082.md) | Quick add sheet S-30 | US-06-3 | Low | Haiku | boilerplate-engineer | T-024, T-029 | G | 9 | TODO |
| [T-083](tasks/T-083.md) | Money tab S-40 (accounts per currency) | US-06-5 | Medium | Sonnet | flutter-ui-engineer | T-045, T-052, T-029 | G | 10 | TODO |
| [T-084](tasks/T-084.md) | Card detail S-41, compare cards S-42 | US-06-5 | Medium | Sonnet | flutter-ui-engineer | T-083, T-051 | G | 11 | TODO |
| [T-085](tasks/T-085.md) | Add/edit card S-43 (type → bank → details), merge and hide | US-06-5 | Medium | Sonnet | flutter-ui-engineer | T-083, T-078 | G | 11 | TODO |
| [T-086](tasks/T-086.md) | Capture settings S-61 and card capture sheet S-62 | US-06-4 | Medium | Sonnet | flutter-ui-engineer | T-078, T-029 | G | 10 | TODO |

## M3 — Money brain

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-087](tasks/T-087.md) | Generate ARB files from copy deck (parts 2–3) | US-02-2 | Low | Haiku | boilerplate-engineer | T-029, T-027, T-028 | C | 9 | TODO |
| [T-088](tasks/T-088.md) | Produce zaghlol.riv from the vector rig (illustrator) | US-10-3 | Medium | — (human) | external | — | C | 1 | TODO |
| [T-089](tasks/T-089.md) | Self-transfer pairing, FX conversions and card settlements | US-08-1 | High | Sonnet | flutter-core-engineer | T-046, T-050 | A | 8 | TODO |
| [T-090](tasks/T-090.md) | Refund matching and offset links | US-08-2 | High | Sonnet | flutter-core-engineer | T-089 | A | 9 | TODO |
| [T-091](tasks/T-091.md) | Splits and reimbursements with allocation and unassign | US-08-2 | High | Sonnet | flutter-core-engineer | T-090 | A | 10 | TODO |
| [T-092](tasks/T-092.md) | Reimbursement and cross-currency pair suggestions | US-08-2 | Medium | Sonnet | flutter-core-engineer | T-091, T-049 | A | 11 | TODO |
| [T-093](tasks/T-093.md) | Split/reimbursement sheet S-15 and link-transfer sheet S-16 | US-08-2 | Medium | Sonnet | flutter-ui-engineer | T-091, T-089, T-080 | G | 11 | TODO |
| [T-094](tasks/T-094.md) | Local notifications service (types, quiet hours, redaction) | US-10-4 | Medium | Sonnet | flutter-core-engineer | T-020 | A | 7 | TODO |
| [T-095](tasks/T-095.md) | Budgets per category and currency with threshold alerts | US-09-1 | Medium | Sonnet | flutter-core-engineer | T-051, T-094 | A | 8 | TODO |
| [T-096](tasks/T-096.md) | Subscriptions detection, installments, gameya, card dues and reminders | US-09-2 | High | Sonnet | flutter-core-engineer | T-050, T-094 | A | 8 | TODO |
| [T-097](tasks/T-097.md) | Contextual setup suggestions (payday, budgets, backup) | US-10-1 | Medium | Sonnet | flutter-core-engineer | T-051, T-049 | A | 9 | TODO |
| [T-098](tasks/T-098.md) | Mascot trigger policy (shocked, detective, proud, tour guide) | US-10-3 | Medium | Sonnet | flutter-core-engineer | T-051, T-089, T-095 | A | 9 | TODO |
| [T-099](tasks/T-099.md) | Wire motion-only mascot moments to UI events | US-10-3 | Medium | Sonnet | flutter-ui-engineer | T-053, T-088 | G | 4 | TODO |
| [T-100](tasks/T-100.md) | Duplicate-charge and weekly-summary notifications | US-10-4 | Medium | Sonnet | flutter-core-engineer | T-094, T-046, T-051 | A | 8 | TODO |
| [T-101](tasks/T-101.md) | Insights shell and Budget S-22 (+ edit budgets) | US-09-1 | Medium | Sonnet | flutter-ui-engineer | T-095, T-087, T-024 | G | 10 | TODO |
| [T-102](tasks/T-102.md) | Bills & installments S-24 and add/edit recurring item | US-09-2 | Medium | Sonnet | flutter-ui-engineer | T-096, T-087 | G | 10 | TODO |
| [T-103](tasks/T-103.md) | App lock, privacy overlay and screenshot hiding | US-18-2 | High | Sonnet | native-platform-engineer | T-004, T-020 | D | 7 | TODO |
| [T-104](tasks/T-104.md) | Home contextual cards and Settings 'finish setup' | US-10-1 | Medium | Sonnet | flutter-ui-engineer | T-054, T-097, T-103 | G | 11 | TODO |

## M4 — Insights, chat, voice & wealth

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-105](tasks/T-105.md) | Chart query layer for all 12 charts | US-11-1 | High | Sonnet | flutter-core-engineer | T-051, T-096, T-091 | A | 11 | TODO |
| [T-106](tasks/T-106.md) | Explanation template engine (basic vs deep coaching) | US-11-1 | High | Sonnet | flutter-core-engineer | T-105, T-027 | A | 12 | TODO |
| [T-107](tasks/T-107.md) | Charts S-20: four Free charts and Gold-locked previews | US-11-1 | Medium | Sonnet | flutter-ui-engineer | T-105, T-101 | G | 12 | TODO |
| [T-108](tasks/T-108.md) | Chart detail with explanation S-21 | US-11-1 | Medium | Sonnet | flutter-ui-engineer | T-106, T-107 | G | 13 | TODO |
| [T-109](tasks/T-109.md) | Egyptian Arabic voice-phrase parser and 200-phrase fixtures | US-11-3 | High | Sonnet | parsing-engine-engineer | T-013, T-075 | F | 9 | TODO |
| [T-110](tasks/T-110.md) | Ask Zaghlol intent engine (grammar, slots, query plans, answers, roast) | US-11-2 | High | Sonnet | parsing-engine-engineer | T-105, T-027 | F | 12 | TODO |
| [T-111](tasks/T-111.md) | Ask Zaghlol screen S-50 | US-11-2 | Medium | Sonnet | flutter-ui-engineer | T-110 | G | 13 | TODO |
| [T-112](tasks/T-112.md) | Prices and FX store in app (sync-fed, manual override, stale) | US-12-1 | Medium | Sonnet | flutter-core-engineer | T-019 | A | 6 | TODO |
| [T-113](tasks/T-113.md) | Assets, liabilities, net worth per unit and snapshots | US-12-1 | High | Sonnet | flutter-core-engineer | T-112, T-045, T-096 | A | 9 | TODO |
| [T-114](tasks/T-114.md) | Charts: remaining eight (Gold) | US-11-1 | Medium | Sonnet | flutter-ui-engineer | T-107, T-113 | G | 13 | TODO |
| [T-115](tasks/T-115.md) | ≈ combined view service (target currency, rate date, exclusions) | US-12-2 | High | Sonnet | flutter-core-engineer | T-012, T-112 | A | 7 | TODO |
| [T-116](tasks/T-116.md) | Shared per-currency figures and currency switcher component | US-12-2 | Medium | Sonnet | flutter-ui-engineer | T-115, T-054 | G | 11 | TODO |
| [T-117](tasks/T-117.md) | Achievement share cards with hidden amounts by default | US-11-4 | Medium | Sonnet | flutter-ui-engineer | T-105, T-022 | G | 12 | TODO |
| [T-118](tasks/T-118.md) | Home-screen widgets (Android Glance, iOS WidgetKit) | US-11-4 | High | Sonnet | native-platform-engineer | T-051, T-004 | E | 8 | TODO |
| [T-119](tasks/T-119.md) | Gold gate matrix and entitlement state (local) | US-14-1 | Medium | Sonnet | flutter-core-engineer | T-025, T-020 | A | 7 | TODO |
| [T-120](tasks/T-120.md) | Voice logger S-31 with on-device-first recognition and monthly limit | US-11-3 | High | Sonnet | flutter-ui-engineer | T-109, T-119, T-011 | G | 10 | TODO |
| [T-121](tasks/T-121.md) | Money tab assets, Add asset S-44 and Prices S-45 | US-12-1 | Medium | Sonnet | flutter-ui-engineer | T-113, T-083, T-119 | G | 11 | TODO |

## M5 — Backend services & Zaghlol Gold

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-122](tasks/T-122.md) | EF Core model and initial migration for all backend tables + DB roles | US-13-1 | High* | Opus | backend-engineer | T-005 | B | 2 | TODO |
| [T-123](tasks/T-123.md) | Signing service (ES256 via KMS abstraction) and response-signature middleware | US-13-1 | High* | Opus | backend-engineer | T-005 | B | 2 | TODO |
| [T-124](tasks/T-124.md) | Install registration, install-token auth, rate limits, idempotency, strict DTOs | US-13-1 | High* | Opus | backend-engineer | T-122, T-006 | B | 3 | TODO |
| [T-125](tasks/T-125.md) | Catalog versions, deltas, signed full snapshots and admin draft/publish | US-13-1 | High | Opus | backend-engineer | T-122, T-123 | B | 3 | TODO |
| [T-126](tasks/T-126.md) | Feature flags with targeting rules and admin endpoints | US-13-1 | Medium | Sonnet | backend-engineer | T-122 | B | 3 | TODO |
| [T-127](tasks/T-127.md) | Price service: local Egyptian gold-market adapter, FX adapter, worker, override | US-12-1 | High | Sonnet | backend-engineer | T-122 | B | 3 | BLOCKED |
| [T-128](tasks/T-128.md) | Daily POST /v1/sync with throttle, contributions and bank-request intake | US-13-1 | High* | Opus | backend-engineer | T-124, T-125, T-126, T-127, T-123 | B | 4 | TODO |
| [T-129](tasks/T-129.md) | Contribution aggregation, review list and promote/reject | US-13-2 | Medium | Sonnet | backend-engineer | T-128, T-125 | B | 5 | TODO |
| [T-130](tasks/T-130.md) | Google Play purchase verification, acknowledgement and sweeper | US-14-1 | High* | Opus | backend-engineer | T-124, T-123 | B | 4 | TODO |
| [T-131](tasks/T-131.md) | App Store verification (JWS chain, Server API status, appAccountToken) | US-14-1 | High* | Opus | backend-engineer | T-124, T-123 | B | 4 | TODO |
| [T-132](tasks/T-132.md) | Entitlement computation, signed tokens, GET /v1/entitlement and restore | US-14-1 | High* | Opus | backend-engineer | T-130, T-131 | B | 5 | TODO |
| [T-133](tasks/T-133.md) | Google RTDN push endpoint, processing worker and voided reconciliation | US-14-1 | High* | Opus | backend-engineer | T-130 | B | 5 | TODO |
| [T-134](tasks/T-134.md) | App Store Server Notifications V2 endpoint and reconciliation | US-14-1 | High* | Opus | backend-engineer | T-131 | B | 5 | TODO |
| [T-135](tasks/T-135.md) | Accounts: Google/Apple ID token sign-in, linking, sign-out, delete, Android Apple callback | US-15-1 | High* | Opus | backend-engineer | T-132 | B | 6 | TODO |
| [T-136](tasks/T-136.md) | Operator auth (OIDC + MFA), roles, audit log and support lookup | US-13-2 | High* | Opus | backend-engineer | T-122 | B | 3 | TODO |
| [T-137](tasks/T-137.md) | zaghlol-ops CLI for catalog, flags, prices, contributions and support | US-13-2 | Medium | Sonnet | backend-engineer | T-136, T-125, T-126, T-127, T-129 | B | 6 | TODO |
| [T-138](tasks/T-138.md) | Backend observability: OpenTelemetry, metrics, dashboards, alert rules | US-21-1 | Medium | Sonnet | backend-engineer | T-005 | B | 2 | TODO |
| [T-139](tasks/T-139.md) | Retention purger and log privacy settings | US-13-1 | Medium | Sonnet | backend-engineer | T-122, T-138 | B | 3 | TODO |
| [T-140](tasks/T-140.md) | Infrastructure as code and deployment pipeline (staging, prod) | US-13-1 | High | Opus | backend-engineer | T-138 | B | 3 | BLOCKED |
| [T-141](tasks/T-141.md) | App BackendClient: generated DTOs, ES256 verification, lazy install registration | US-13-1 | High* | Opus | flutter-core-engineer | T-006, T-019 | A | 6 | TODO |
| [T-142](tasks/T-142.md) | Merchant contribution opt-in and outbox with on-device filters | US-07-2 | High* | Opus | flutter-core-engineer | T-075, T-019 | A | 9 | TODO |
| [T-143](tasks/T-143.md) | Daily sync orchestrator: throttle, back-off, atomic apply, re-categorize | US-13-1 | High | Opus | flutter-core-engineer | T-141, T-075, T-142, T-112, T-025 | A | 10 | TODO |
| [T-144](tasks/T-144.md) | Entitlement token verification, offline cache and grace | US-14-1 | High* | Opus | flutter-core-engineer | T-119, T-141 | A | 8 | TODO |
| [T-145](tasks/T-145.md) | In-app purchase flow, backend verify, background retry and restore | US-14-1 | High* | Opus | flutter-core-engineer | T-144, T-141 | A | 9 | TODO |
| [T-146](tasks/T-146.md) | Paywall S-68, locked previews and upgrade prompt cap | US-14-1 | Medium | Sonnet | flutter-ui-engineer | T-145, T-087 | G | 10 | TODO |
| [T-147](tasks/T-147.md) | Optional sign-in, account screen S-69, sign-out and delete account | US-15-1 | High* | Opus | flutter-core-engineer | T-141, T-144 | A | 9 | TODO |

## M6 — Backup, import/export, OCR, settings & security

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-148](tasks/T-148.md) | Backup file format: Argon2id-wrapped key and chunked AES-256-GCM | US-16-1 | High* | Opus | flutter-core-engineer | T-015 | A | 4 | TODO |
| [T-149](tasks/T-149.md) | Backup snapshot and restore swap with schema checks | US-16-1 | High* | Opus | flutter-core-engineer | T-148, T-017, T-018, T-019, T-020 | A | 7 | TODO |
| [T-150](tasks/T-150.md) | Google Drive appDataFolder backend | US-16-1 | High* | Opus | flutter-core-engineer | T-149 | A | 8 | TODO |
| [T-151](tasks/T-151.md) | iCloud backup host (native) and Dart adapter | US-16-1 | High* | Opus | native-platform-engineer | T-149, T-004 | E | 8 | TODO |
| [T-152](tasks/T-152.md) | Backup schedules, slots and reminders (Free 1 slot, Gold 5 versions) | US-16-1 | High | Sonnet | flutter-core-engineer | T-150, T-151, T-119, T-094 | A | 9 | TODO |
| [T-153](tasks/T-153.md) | Backup & restore screens S-66 and S-04 | US-16-1 | Medium | Sonnet | flutter-ui-engineer | T-152, T-087 | G | 10 | TODO |
| [T-154](tasks/T-154.md) | CSV and Excel export with preview for Free | US-17-1 | Medium | Sonnet | flutter-core-engineer | T-050, T-119 | A | 8 | TODO |
| [T-155](tasks/T-155.md) | Zaghlol CSV import with duplicate detection | US-17-1 | High | Sonnet | flutter-core-engineer | T-046, T-154 | A | 9 | TODO |
| [T-156](tasks/T-156.md) | Bank PDF statement import (CIB, NBE, QNB, Banque Misr) | US-17-1 | High | Sonnet | parsing-engine-engineer | T-033, T-031 | F | 6 | BLOCKED |
| [T-157](tasks/T-157.md) | Online-bank statement import (Wise, Revolut, Monzo, bunq, N26) | US-17-1 | High | Sonnet | parsing-engine-engineer | T-155, T-071 | F | 10 | BLOCKED |
| [T-158](tasks/T-158.md) | Import flow S-67 (source, summary, done) | US-17-1 | Medium | Sonnet | flutter-ui-engineer | T-156, T-157, T-155, T-119 | G | 11 | TODO |
| [T-159](tasks/T-159.md) | Android OCR host (ML Kit Latin + Tesseract Arabic) | US-17-2 | High | Sonnet | native-platform-engineer | T-010, T-004 | D | 3 | TODO |
| [T-160](tasks/T-160.md) | iOS OCR host (Vision) | US-17-2 | High | Sonnet | native-platform-engineer | T-010, T-004 | E | 3 | TODO |
| [T-161](tasks/T-161.md) | Receipt/screen OCR templates and confirmation screen S-32 | US-17-2 | Medium | Sonnet | parsing-engine-engineer | T-159, T-160, T-033 | F | 6 | TODO |
| [T-162](tasks/T-162.md) | Settings S-60 incl. privacy info and About | US-18-1 | Medium | Sonnet | flutter-ui-engineer | T-020, T-087, T-115 | G | 10 | TODO |
| [T-163](tasks/T-163.md) | Categories & rules S-63/S-64 incl. custom categories (Gold) | US-18-1 | Medium | Sonnet | flutter-ui-engineer | T-074, T-119 | G | 8 | TODO |
| [T-164](tasks/T-164.md) | Custom message template builder engine and screen S-65 (Gold) | US-05-3 | High | Sonnet | parsing-engine-engineer | T-033, T-119 | F | 8 | TODO |
| [T-165](tasks/T-165.md) | Exclude app data from OS backups and device transfer | US-18-2 | High* | Opus | native-platform-engineer | T-001 | D | 2 | TODO |
| [T-166](tasks/T-166.md) | Delete everything (local wipe + backend install delete) | US-18-2 | High* | Opus | flutter-core-engineer | T-015, T-141, T-152 | A | 10 | TODO |

## M7 — Flagged features, hardening & launch

| ID | Title | Story | Cx | Model | Agent | Depends on | Lane | Wave | Status |
|---|---|---|---|---|---|---|---|---|---|
| [T-167](tasks/T-167.md) | Zakah engine (hawl, nisab, native-unit dues) | US-19-1 | High* | Opus | flutter-core-engineer | T-113 | A | 10 | TODO |
| [T-168](tasks/T-168.md) | Zakah screen S-46 behind flag with disclaimer | US-19-1 | Medium | Sonnet | flutter-ui-engineer | T-167, T-025, T-087 | G | 11 | TODO |
| [T-169](tasks/T-169.md) | Smart ROI general-advice rules with no-names check | US-19-2 | High | Sonnet | flutter-core-engineer | T-105 | A | 12 | TODO |
| [T-170](tasks/T-170.md) | Smart ROI screen S-51 behind flag | US-19-2 | Medium | Sonnet | flutter-ui-engineer | T-169, T-025, T-087 | G | 13 | TODO |
| [T-171](tasks/T-171.md) | Privacy verification suite (sandbox scan, data-boundary proxy, ignore no-trace) | US-21-1 | High* | Opus | test-engineer | T-166, T-143, T-078, T-149, T-165 | A | 11 | TODO |
| [T-172](tasks/T-172.md) | Device end-to-end suites (Android killed-app capture, iOS intents, backup, purchases) | US-21-1 | High | Sonnet | test-engineer | T-056, T-067, T-153, T-145 | A | 11 | TODO |
| [T-173](tasks/T-173.md) | Performance benchmarks and CI budgets | US-21-1 | Medium | Sonnet | test-engineer | T-033, T-050, T-105, T-048 | A | 12 | TODO |
| [T-174](tasks/T-174.md) | Accessibility and golden coverage pass (130% text, both themes, screen readers) | US-21-1 | Medium | Sonnet | test-engineer | T-054, T-079, T-162, T-107 | G | 13 | TODO |
| [T-175](tasks/T-175.md) | Security assessment: MobSF, ZAP, dependency scans, pen test | US-21-1 | High* | Opus | security-privacy-reviewer | T-171, T-140 | A | 12 | TODO |
| [T-176](tasks/T-176.md) | Android release pipeline, Play listings, Data safety and SMS declaration package | US-21-1 | High | Sonnet | flutter-core-engineer | T-172, T-171 | A | 12 | TODO |
| [T-177](tasks/T-177.md) | iOS release pipeline, privacy labels and App Review notes | US-21-1 | High | Sonnet | flutter-core-engineer | T-172, T-171 | A | 12 | TODO |

\* = critical (C4): Opus + security-privacy-reviewer.


## Blocked or external items
| ID | Task | Waiting for |
|---|---|---|
| [T-031](tasks/T-031.md) | Convert real SMS/notification/statement samples into synthetic fixtures (OQ-04/18) | Waiting for samples from product owner (OQ-04/OQ-18) |
| [T-127](tasks/T-127.md) | Price service: local Egyptian gold-market adapter, FX adapter, worker, override | Provider contract for local gold feed (D-41) needed before go-live; build continues with fakes |
| [T-140](tasks/T-140.md) | Infrastructure as code and deployment pipeline (staging, prod) | CR-03 / OQ-16: hosting provider & region + PDPL licence decision |
| [T-156](tasks/T-156.md) | Bank PDF statement import (CIB, NBE, QNB, Banque Misr) | Needs sample statements (OQ-04) |
| [T-157](tasks/T-157.md) | Online-bank statement import (Wise, Revolut, Monzo, bunq, N26) | Needs sample statements (OQ-04) |
| [T-058](tasks/T-058.md) | Native Egyptian-speaker review of the copy deck | External/human: product owner + native Egyptian reviewer |
| [T-059](tasks/T-059.md) | Compile the 600+ Egyptian merchant seed list (OQ-05) | External/human: product owner / content team (OQ-05) |
| [T-088](tasks/T-088.md) | Produce zaghlol.riv from the vector rig (illustrator) | External/human: illustrator (Rive) |

## Execution rules (Phase 5)
1. One task per sub-agent call; pass the task file path (CLAUDE.md §6).
2. C3/C4 tasks get their design note from `solution-architect` (Opus) before implementation starts.
3. Tasks in the same wave on different lanes run in parallel (see `parallelization.md`); conflict groups run one at a time.
4. Reviews per class: C1 Lead spot-check · C2 code-reviewer · C3 + test-engineer · C4 + security-privacy-reviewer.
5. Two failed reviews → bump one class and re-delegate.
6. Milestone exit: all tasks DONE + `docs/05-reviews/M#-release-check.md` on Android and iOS.

## Approval
| Role | Name | Decision | Date |
|---|---|---|---|
| Product owner | amr905 | ☑ Approved | 2026-11-03 |

On approval, Phase 5 (implementation) starts with M0 wave 1.
