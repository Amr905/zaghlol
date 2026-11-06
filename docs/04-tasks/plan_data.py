# Zaghlol Phase 4 plan data. Keys are symbolic; generator assigns T-### in order.
# FROZEN AT PLAN v1.0 (2026-11-03). Since v1.1 (2026-11-06) the task markdown in docs/04-tasks/ is edited by hand
# (T-178…T-186 added, T-132/T-136 split, review follow-ups appended by the Lead). Do NOT regenerate from this file.

MILESTONES = {
 "M0": ("Foundations & spikes", "Repo, CI, encrypted DB, money/l10n/theme/routing core, backend skeleton, risk spikes."),
 "M1": ("Android capture → Home (vertical slice)", "A bank SMS on Android becomes a categorized transaction on the Home screen, offline, encrypted."),
 "M2": ("iOS capture, transactions & categorization", "Shortcuts/Apple Pay/share capture on iOS; full transactions, review queue, accounts & cards, all institution templates."),
 "M3": ("Money brain", "Transfers, refunds, splits, reimbursements, budgets & payday cycle, recurring, notifications, mascot."),
 "M4": ("Insights, chat, voice & wealth", "12 charts + explanations, Ask Zaghlol, voice logging, wealth & net worth, multi-currency ≈ view, share cards, widgets."),
 "M5": ("Backend services & Zaghlol Gold", "Install/sync/catalog/flags/prices, purchases & entitlements, store notifications, optional sign-in, operator CLI."),
 "M6": ("Backup, import/export, OCR, settings & security", "Encrypted Drive/iCloud backup & restore, CSV/XLSX/PDF/online statements, OCR, settings, app lock, delete everything."),
 "M7": ("Flagged features, hardening & launch", "Zakah & ROI behind flags, privacy/perf/a11y/security verification, store release pipelines."),
}

EPICS = {
 "E01": "Foundations & tooling",
 "E02": "Core platform (DB, money, l10n, theme, navigation)",
 "E03": "Android capture",
 "E04": "iOS capture",
 "E05": "Parsing engine & institution templates",
 "E06": "Ingestion, accounts & transactions",
 "E07": "Categorization & merchant catalog",
 "E08": "Transfers, refunds, splits & reimbursements",
 "E09": "Budget, payday cycle & recurring payments",
 "E10": "Home, onboarding, mascot & notifications",
 "E11": "Insights, Ask Zaghlol & voice",
 "E12": "Wealth, prices & multi-currency",
 "E13": "Backend platform & daily sync",
 "E14": "Zaghlol Gold — purchases & entitlements",
 "E15": "Optional account (sign-in)",
 "E16": "Encrypted backup & restore",
 "E17": "Import, export & OCR",
 "E18": "Settings, security & privacy",
 "E19": "Flagged features (Zakah, Smart ROI)",
 "E20": "Content & assets",
 "E21": "Quality, compliance & release",
}

# (id, epic, "As a … I want … so that …", traces)
STORIES = [
 ("US-01-1","E01","As the dev team, we can build, lint and test the app and backend in CI from day one, so every task is verified the same way.","CLAUDE.md §7"),
 ("US-01-2","E01","As the Lead, the riskiest platform assumptions are proven by spikes before features depend on them.","architecture §9, README spikes"),
 ("US-02-1","E02","As a user, everything Zaghlol stores on my phone is encrypted from the first write.","FR-SEC-01/03/04, NFR-SEC-01/06"),
 ("US-02-2","E02","As a user, money is always exact and shown in my language, digits and direction.","BR-MON-*, FR-L10N-*, FR-CUR-01"),
 ("US-02-3","E02","As a user, the app looks and navigates the same as the approved design on iPhone and Android.","Design 02–05, NFR-UX-*"),
 ("US-03-1","E03","As an Android user, bank SMS are captured automatically even when the app is closed, and personal SMS are never read into storage.","FR-ING-A-01/02, BR-ING-*, NFR-PRIV-04"),
 ("US-03-2","E03","As an Android user, my past bank SMS are scanned on first setup so I see my history immediately.","FR-ONB-06, NFR-PERF-03"),
 ("US-03-3","E03","As an Android user of online banks, bank-app notifications are captured too.","FR-ING-A-03/07"),
 ("US-03-4","E03","As an Android user, I can share or paste a message when automatic capture misses it, and the app still works without SMS permission.","FR-ING-A-04/05, D-02"),
 ("US-04-1","E04","As an iPhone user, my bank SMS and Apple Pay payments are logged through Shortcuts automations without opening the app (FinArt/Say approach).","FR-ING-I-01/02/06/07, D-39"),
 ("US-04-2","E04","As an iPhone user, I can share a message, screenshot or statement to Zaghlol.","FR-ING-I-04/05/08"),
 ("US-05-1","E05","As a user, messages from every supported institution are understood correctly in Arabic and English.","FR-PAR-01…06/10/11/15, institutions.md"),
 ("US-05-2","E05","As a user with an unlisted bank, Zaghlol still suggests what it read and lets me request support.","FR-PAR-13/14"),
 ("US-05-3","E05","As a Gold user, I can teach Zaghlol a new message format.","FR-PAR-07"),
 ("US-06-1","E06","As a user, every captured message becomes exactly one transaction on the right card, without duplicates.","FR-ACC-01/02/03/06, BR-ING-02, NFR-REL-01"),
 ("US-06-2","E06","As a user, anything Zaghlol isn't sure about waits for me in a review queue instead of being lost.","FR-ING-A-06, FR-PAR-06, EC-08"),
 ("US-06-3","E06","As a user, I can find, add, edit, delete and bulk-edit transactions.","FR-TXN-01…06, D-36"),
 ("US-06-4","E06","As a user, I can stop Zaghlol reading specific cards or channels, and ignored messages are never stored.","FR-CAP-*, BR-CAP-*"),
 ("US-06-5","E06","As a user, I can see and manage each card and account separately.","FR-CARD-*, FR-ACC-04/05"),
 ("US-07-1","E07","As a user, transactions are categorized automatically using my rules first, then the Egyptian merchant catalog.","FR-CAT-01…06/08, BR-CAT-*"),
 ("US-07-2","E07","As a user, I can opt in to share unknown merchant names anonymously to improve the catalog.","FR-CAT-09, BR-SYNC-04, D-16"),
 ("US-08-1","E08","As a user, moving money between my own accounts and card bill payments is never counted as spending.","FR-XFR-01/02, FR-PAR-12, BR-TXN-04, FR-CUR-06"),
 ("US-08-2","E08","As a user, refunds, shared bills and friends' reimbursements reduce my real spending.","FR-XFR-03…09, BR-XFR-*"),
 ("US-09-1","E09","As a user, I see my payday cycle, budgets per category and currency, and a safe amount to spend per day.","FR-BUD-*, BR-BUD-*"),
 ("US-09-2","E09","As a user, subscriptions, installments, card dues and gameya are tracked and I'm reminded before they're due.","FR-SUB-*, BR-SUB-*"),
 ("US-10-1","E10","As a new user, I reach my own transactions within 60 seconds with the fewest possible questions.","FR-ONB-*, D-21, flows 07"),
 ("US-10-2","E10","As a user, Home shows my money at a glance per currency with a card filter.","FR-HOME-*, FR-CARD-01, FR-CUR-03"),
 ("US-10-3","E10","As a user, Captain Zaghlol reacts to what's happening with fun, respectful animations.","FR-MAS-*, BR-MAS-*, D-35"),
 ("US-10-4","E10","As a user, I get useful local notifications I control, with amounts hidden on the lock screen if I want.","FR-NTF-*"),
 ("US-11-1","E11","As a user, I see 12 charts (4 free) with a Zaghlol explanation and a tip.","FR-CHT-*"),
 ("US-11-2","E11","As a user, I can ask Zaghlol questions about my money in Egyptian Arabic or English, offline.","FR-CHAT-*, D-06"),
 ("US-11-3","E11","As a user, I can log cash spending by voice in Egyptian Arabic.","FR-VOI-*, D-42"),
 ("US-11-4","E11","As a user, I can share fun achievement cards and see a home-screen widget.","FR-SHR-*, FR-WID-*"),
 ("US-12-1","E12","As a Gold user, I track gold, certificates and other assets and see net worth per currency/unit over time.","FR-WLT-*, BR-WLT-*"),
 ("US-12-2","E12","As a user with several currencies, every total stays in its own currency, with an optional labelled ≈ view.","FR-CUR-*, BR-FX-*"),
 ("US-13-1","E13","As the app, I get catalog, flags and prices in one small signed daily call, and keep working offline.","FR-SYNC-*, FR-BE-01/04/05/06, NFR-BE-*"),
 ("US-13-2","E13","As an operator, I can manage the catalog, flags, prices and contributions securely.","FR-BE-07/08/10, D-37"),
 ("US-14-1","E14","As a user, I can buy, restore and keep Gold (even offline for days), verified by the backend.","FR-GOLD-*, BR-GOLD-*"),
 ("US-15-1","E15","As a user, I can optionally sign in with Google or Apple to carry Gold across Android and iPhone, and delete that account.","FR-ACCT-*, D-14, D-44"),
 ("US-16-1","E16","As a user, I can back up everything encrypted to my Google Drive or iCloud and restore it on a new phone (any platform).","FR-BAK-*, BR-BAK-*, D-33"),
 ("US-17-1","E17","As a Gold user, I can export to CSV/Excel and import CSV, bank PDF and online-bank statements.","FR-EXP-*, FR-ING-I-05"),
 ("US-17-2","E17","As a user, I can capture a receipt or InstaPay screenshot with on-device OCR.","FR-ING-I-04, D-40"),
 ("US-18-1","E18","As a user, I control every preference from Settings, including categories, rules and what Zaghlol reads.","FR-ONB-07, FR-CAT-07/08"),
 ("US-18-2","E18","As a user, the app is locked with biometrics, hidden in the app switcher, excluded from OS backups, and I can delete everything.","FR-SEC-*, FR-ONB-08"),
 ("US-19-1","E19","As a user (when enabled by Zaghlol), I can estimate Zakah per asset in its native unit.","FR-ZAK-*, BR-ZAK-*, D-07"),
 ("US-19-2","E19","As a user (when enabled), I get general investment-of-savings tips without product names.","FR-ROI-*, D-10, D-38"),
 ("US-20-1","E20","As the team, all copy, merchant data, mascot animation and fixtures exist before the screens and parsers that need them.","Phase 2 copy deck, OQ-04/05, D-35"),
 ("US-21-1","E21","As the product owner, every release is proven private, fast, accessible and store-compliant before it ships.","NFR-*, testing-strategy"),
]

TASKS = []
def T(key, ms, story, title, cls, agent, deps, comps, desc, tech, ac, tests, lane, traces="", model=None, ext=False, blocked=None):
    TASKS.append(dict(key=key, ms=ms, story=story, title=title, cls=cls, agent=agent, deps=deps, comps=comps,
                      desc=desc, tech=tech, ac=ac, tests=tests, lane=lane, traces=traces, model=model, ext=ext, blocked=blocked))

# ───────────────────────── M0 Foundations ─────────────────────────
T("repo","M0","US-01-1","Create mono-repo scaffold with pub workspace, app flavors and pure-Dart packages","C2","flutter-core-engineer",[],
  "repo root, app/, packages/zaghlol_domain, packages/zaghlol_parsing",
  "Set up the repository layout from project-structure.md so every later task has a home.",
  "Pub workspace root pubspec; `flutter create` app with flavors dev/staging/prod; Android product flavors prodSms/prodNoSms (same applicationId, SMS permissions only in prodSms manifest); empty pure-Dart packages; analysis_options with strict lints + riverpod_lint; .gitignore; README dev setup.",
  ["`flutter build apk --flavor prodNoSms` and `flutter build ios --flavor dev --no-codesign` succeed","`dart test` runs in both packages (one placeholder test each)","prodNoSms merged manifest contains no READ_SMS/RECEIVE_SMS"],
  ["CI smoke build for every flavor","Manifest assertion test for prodNoSms"],"A","project-structure.md, ADR-004/007, NFR-COMP-01/02, NFR-MAINT-02")
T("lints","M0","US-01-1","Add custom lint rules (no double in money, no UI string literals, no print)","C2","flutter-core-engineer",["repo"],
  "tools/lints (custom_lint plugin)",
  "Enforce CLAUDE.md non-negotiables automatically.",
  "custom_lint plugin: (1) `double`/`num` forbidden in files under money/ and in any field named *amount*/*minor*; (2) string literals in widget build methods (allow-list for keys/asset paths); (3) print/debugPrint outside debug-only files; (4) exceptions in parsing/db layers must extend SafeException.",
  ["Each rule fires on a fixture file and is silent on compliant code","Rules run in CI analyze step"],["Lint fixture tests"],"A","CLAUDE.md §2, §7")
T("ci_app","M0","US-01-1","App CI pipeline (format, analyze, unit, golden, native unit)","C2","flutter-core-engineer",["repo"],
  ".github/workflows/app-ci.yml",
  "Every PR runs the same checks the DoD requires.",
  "GitHub Actions: Flutter pinned version cache; dart format check; flutter analyze + custom_lint; unit tests for packages; widget+golden tests; Kotlin unit (Gradle) and Swift unit (macOS runner, xcodebuild test) jobs; artifact upload of golden diffs.",
  ["A PR with a format error or failing test is red","Golden diffs downloadable as artifacts"],["Workflow dry run on a sample PR"],"A","deployment §2")
T("pigeon","M0","US-01-1","Pigeon setup and stale-generation check","C2","flutter-core-engineer",["repo"],
  "app/pigeons/, generated Dart/Kotlin/Swift",
  "Type-safe platform channel generation used by all native tasks.",
  "Add pigeon dev dependency; `app/pigeons/*.dart` with empty API stubs from platform-channels.md (names only); generation script; CI step fails if generated files differ.",
  ["`dart run pigeon` regenerates identical files","CI fails when a pigeon file is edited without regenerating"],["CI check"],"A","ADR-007, platform-channels.md")
T("be_scaffold","M0","US-01-1","Backend solution scaffold, Docker Compose and CI","C2","backend-engineer",[],
  "backend/ (Zaghlol.Api/Application/Domain/Infrastructure/Workers/Ops, tests)",
  "Runnable .NET 10 backend skeleton with health endpoint, local Postgres and CI.",
  ".NET 10 solution per project-structure; Minimal API with /v1/health; Problem Details; Serilog JSON console; Dockerfile (distroless, non-root); docker-compose (api, worker, postgres 17); backend-ci.yml (build -warnaserror, format, xUnit, Testcontainers, SCA, image scan).",
  ["`docker compose up` serves /v1/health 200","CI green on a clean PR","Container runs as non-root"],["Integration test hits /v1/health with Testcontainers"],"B","ADR-022, deployment §3")
T("openapi","M0","US-13-1","OpenAPI v1 spec and contract-test harness","C2","backend-engineer",["be_scaffold"],
  "backend/openapi/zaghlol-v1.yaml, contract tests (server), app DTO generation config",
  "Single source of truth for the API used by both sides.",
  "Write zaghlol-v1.yaml from backend-api.md §2–6 (all endpoints, schemas with additionalProperties:false, problem+json, headers); server contract tests validate responses; Dart DTO generation config (openapi_generator or hand-maintained with schema test).",
  ["Spec validates with an OpenAPI linter","Every endpoint in backend-api.md is present","Request schemas reject unknown fields"],["Spectral lint in CI","Schema conformance tests"],"B","backend-api.md")
T("spk_db","M0","US-01-2","SPK-05: encrypted SQLite (SQLite3MultipleCiphers) + FTS5 trigram on both platforms","C4","flutter-core-engineer",["repo"],
  "spike branch only; findings → ADR-002",
  "Prove the DB encryption path before the schema is built.",
  "sqlite3 build hook `source: sqlite3mc`; open with PRAGMA cipher='sqlcipher', legacy=4, key; verify `PRAGMA cipher` and that the file is unreadable without the key; FTS5 trigram tokenizer availability; measure open time and 50k-row FTS query on a mid-range Android and an iPhone 12.",
  ["Written result in ADR-002 (Consequences/Spike section) with timings","Recommendation confirmed or alternative proposed"],["Throwaway benchmark app"],"A","ADR-002")
T("spk_android","M0","US-01-2","SPK-01: Android receiver → spool → WorkManager → headless engine latency","C4","native-platform-engineer",["repo","pigeon"],
  "spike branch; findings → ADR-005",
  "Measure whether a killed app processes an SMS within 10 s.",
  "Minimal SmsReceiver + encrypted spool + expedited WorkManager starting a headless FlutterEngine (entrypoint ingestionMain) that logs completion; test on Samsung A-series and Xiaomi with battery optimisation on/off; measure p50/p95.",
  ["Latency table per device in ADR-005","Documented need (or not) for battery-optimisation prompt"],["Manual device runs with `adb emu sms send` / real SMS"],"D","ADR-005, FR-ING-A-01")
T("spk_ios","M0","US-01-2","SPK-03: can an iOS App Intent process immediately with a headless Flutter engine?","C4","native-platform-engineer",["repo","pigeon"],
  "spike branch; findings → ADR-005/006",
  "Decide whether iOS captures are processed instantly or on next open.",
  "App Intent (openAppWhenRun=false) writing a spool entry, then attempting FlutterEngine run with a Dart entrypoint inside perform(); measure time and memory limits on iOS 17 and 26; check behaviour while locked (after first unlock).",
  ["Go/no-go recorded in ADR-006 with measurements","Fallback (process on foreground/BGAppRefresh) confirmed"],["Manual device runs via Shortcuts"],"E","ADR-006")
T("spk_ocr","M0","US-01-2","SPK-02: OCR accuracy on synthetic InstaPay/wallet receipts","C3","native-platform-engineer",["repo"],
  "spike branch; findings → ADR-009",
  "Confirm OCR approach per platform before building it.",
  "Create 50 synthetic receipt screenshots (AR/EN); run iOS Vision (runtime-supported languages) and Android ML Kit Latin + Tesseract `ara` fast; score amount/IPA/reference/date extraction.",
  ["Accuracy table per field and platform in ADR-009","Tesseract model size and timing recorded"],["Scripted batch run"],"D","ADR-009, D-40")
T("spk_speech","M0","US-01-2","SPK-04: on-device ar-EG speech availability across the device matrix","C2","native-platform-engineer",["repo"],
  "spike branch; findings → ADR-010",
  "Know which devices need the consented online fallback.",
  "speech_to_text probe app: list locales, onDevice support for ar-EG/ar-SA/en on device matrix (Android 12–16, iOS 17/18/26); record word accuracy on 30 test phrases.",
  ["Availability matrix in ADR-010","Fallback UX trigger condition defined"],["Manual device runs"],"D","ADR-010, D-42", model="sonnet")

T("money","M0","US-02-2","Money and Currency value types with ISO 4217 table","C4","flutter-core-engineer",["repo"],
  "packages/zaghlol_domain/lib/money/",
  "One exact money type used everywhere.",
  "Money{minor:int, currency}; Currency from bundled currencies.json (active ISO codes, exponents incl. 3-decimal KWD/BHD/OMR/JOD/TND/LYD/IQD, 0-decimal JPY/KRW); +,−, compare with CurrencyMismatch; allocate(weights) with remainder distribution; MultiCurrencyTotal; no double anywhere.",
  ["KWD 1.250, BHD 0.375, JPY 1500 round-trip exactly","Adding EGP to USD throws CurrencyMismatch","allocate never loses or creates a minor unit"],["Unit + property tests (glados) for arithmetic and allocate"],"A","domain-algorithms §1, BR-MON-*")
T("normalize","M0","US-05-1","Text & amount normalization utilities (digits, separators, groupings)","C3","parsing-engine-engineer",["money"],
  "packages/zaghlol_parsing/lib/normalize/",
  "Shared normalizer for parsing, voice, OCR and search.",
  "Arabic-Indic/extended digits → ASCII; ٫/٬ separators; invisible marks; tatweel/diacritics (matching only); Arabic letter folding for keys; amount parser for 1,234.56 / 1.234,56 (eu locale flag) / 1,23,456.78 with currency exponent validation (no silent rounding).",
  ["`١٬٢٥٠٫٠٠` → 1250.00 EGP","`KWD 12.345` → 12345 minor","Too many decimals for a currency → failure, not rounding"],["Table-driven tests for every FR-PAR-04/11 format","Property test: format→parse round-trip"],"F","parsing-engine §2")
T("result_bus","M0","US-02-1","Result/Failure types, SafeException and domain event bus","C2","flutter-core-engineer",["repo"],
  "packages/zaghlol_domain/lib/core/, app/lib/core/result",
  "Common error and event primitives.",
  "Sealed Result<T,Failure>; Failure hierarchy (Parse, Db, Network, Platform, Crypto, Currency); SafeException that never carries message text; DomainEventBus stream with typed events (TransactionsChanged, BudgetThresholdCrossed, MascotTrigger, CatalogUpdated…).",
  ["All failures are exhaustively switchable","SafeException.toString() contains only a code"],["Unit tests"],"A","error-handling §1")
T("keys","M0","US-02-1","Secure key bootstrap for the database key","C4","flutter-core-engineer",["spk_db"],
  "app/lib/core/db/key_bootstrap.dart, secure storage config",
  "Generate and protect K_db on first launch.",
  "32 random bytes via Random.secure; flutter_secure_storage (Android Keystore-wrapped AES; iOS Keychain first_unlock_this_device, not synchronizable); detect missing/invalidated key vs first run (never silently create a new DB over an existing file); key never logged or persisted elsewhere.",
  ["First run creates key; second run reads same key","Existing DB + missing key → KeyInvalidated failure (not a new key)","Key absent from logs, prefs and files (scan)"],["Unit tests with fake storage","Device test on Android + iOS"],"A","security-model §3, FR-SEC-04")
T("db_core","M0","US-02-1","AppDatabase v1 skeleton: encrypted open, isolate, migration harness","C4","flutter-core-engineer",["keys"],
  "app/lib/core/db/",
  "Encrypted Drift database that every repository builds on.",
  "NativeDatabase.createInBackground with sqlite3mc; setup: PRAGMA cipher/legacy/key, verify cipher active else refuse; WAL, foreign_keys; schemaVersion 1; drift_dev schema dump folder; generated migration tests; pre-migration encrypted copy and restore-on-failure; DB file in no-backup dir.",
  ["Opening with wrong key fails cleanly","File header is not 'SQLite format 3'","Migration failure restores the copy"],["Encrypted-file test","Migration harness self-test"],"A","database-schema §0/§4, ADR-002, NFR-REL-02")
T("db_a","M0","US-06-1","Schema batch A: accounts, balances, raw messages, transactions (+FTS), transfers, offsets, splits","C4","flutter-core-engineer",["db_core"],
  "app/lib/core/db/tables/*, daos/",
  "Core financial tables with indexes, FTS and invariant triggers.",
  "Tables per database-schema §2.1–2.3 incl. partial unique indexes, transactions_fts (trigram, triggers incl. amount_text in both digit systems), offset sum invariant triggers, Money type converters; schema dump v1.",
  ["All CHECK/unique constraints enforced","Offset over-allocation aborts","FTS finds merchant by partial Arabic/English text"],["DAO tests on encrypted in-memory DB","Trigger tests"],"A","database-schema §2.1–2.3")
T("db_b","M0","US-07-1","Schema batch B: categories, catalog, rules, budgets, alerts, summaries, recurring","C4","flutter-core-engineer",["db_core"],
  "app/lib/core/db/tables/*",
  "Categorization, budgeting and recurring tables.",
  "Tables per database-schema §2.4–2.5 incl. catalog_alias_fts trigram; schema dump.",
  ["Constraints enforced","catalog_alias_fts returns trigram candidates"],["DAO tests"],"A","database-schema §2.4–2.5")
T("db_c","M0","US-02-1","Schema batch C: wealth, prices, Zakah, capture controls, review, settings, outbox, misc","C4","flutter-core-engineer",["db_core"],
  "app/lib/core/db/tables/*",
  "Remaining tables so the v1 schema is complete before features start.",
  "Tables per database-schema §2.6–2.8; secure_state BLOB store; typed DAOs; schema dump v1 final.",
  ["v1 schema dump matches database-schema.md","All tables have DAO coverage"],["DAO tests","Schema snapshot test"],"A","database-schema §2.6–2.8")
T("settings_repo","M0","US-18-1","Settings repository with typed accessors and defaults","C2","flutter-core-engineer",["db_c"],
  "app/lib/core/settings/",
  "All preferences stored in the encrypted DB with typed access.",
  "Typed keys for every FR-ONB-07/FR-BAK-06 setting with defaults (A-10/27/29/43/54); reactive providers; no SharedPreferences/UserDefaults usage anywhere (lint/grep check).",
  ["Every setting has a default and round-trips","No plain prefs used in app (CI grep)"],["Unit tests"],"A","FR-ONB-07, FR-SEC-03")
T("diaglog","M0","US-21-1","Redacting local diagnostic log","C3","flutter-core-engineer",["db_c","result_bus"],
  "app/lib/core/logging/",
  "Local, privacy-safe diagnostics that can be shared by the user.",
  "DiagEvent API with allow-listed field types (codes, counts, durations, versions, institution codes); ring buffer 7 days/2000 rows; global error handlers write codes only; export as text.",
  ["Free-text fields rejected at compile time","Ring buffer trims correctly"],["Unit tests incl. attempt to log a message body (must not compile/pass)"],"A","error-handling §3.1")
T("theme","M0","US-02-3","Design tokens, Mint Fresh/Jade Night themes and base components","C2","flutter-ui-engineer",["repo"],
  "app/lib/core/theme/",
  "Reusable themed components matching the approved design system.",
  "Tokens from 05-theme-2026 §0 + 04-design-system (type scale, spacing, radius, motion); IBM Plex Sans Arabic + Latin fallback; components C-01…C-36 base set: buttons, chips, cards, list rows, category tiles, amount text (ink spend / green income), pills, banners, sheets, segmented control; light/dark.",
  ["Golden tests for each component in ar/en × light/dark","All text tokens meet WCAG AA"],["Golden tests","Contrast unit test"],"G","design 04, 05 §0")
T("l10n","M0","US-02-2","Localization scaffold, digits mode and money/date formatting","C2","flutter-core-engineer",["money","settings_repo"],
  "app/lib/core/l10n/",
  "Arabic-first localization with correct digits and directions.",
  "gen-l10n with app_ar.arb template + app_en.arb; DigitsMode (Arabic-Indic default in ar, A-29); MoneyFormat (ج.م/EGP, exponent-correct, bidi isolation); date formats; Directionality from locale.",
  ["Amounts render with correct digits and decimals per currency","Switching language flips direction without restart"],["Unit + widget tests"],"A","ADR-017, FR-L10N-01/03")
T("shell","M0","US-02-3","App shell: routing, platform tab bars, Add button, deep links","C2","flutter-ui-engineer",["theme","l10n"],
  "app/lib/core/routing/, app shell widgets",
  "Navigation skeleton per 03-navigation.md.",
  "go_router shell with 4 tabs (الرئيسية/الحسبة/فلوسي/زغلول); iOS 26 floating glass tab bar + detached Add button; Android M3 NavigationBar + FAB bottom-end; modal Add sheet route; deep links zaghlol://add, review, widget tap.",
  ["Tabs preserve state","Correct platform variant on each OS","Deep links open the right screen"],["Widget + golden tests both platforms/locales"],"G","design 03-navigation")
T("flags","M0","US-13-1","Feature flags service (default OFF)","C2","flutter-core-engineer",["db_c"],
  "app/lib/core/flags/",
  "Remote-controlled flags with safe defaults.",
  "Flag registry (zakah, smart_roi, roi_named_products); snapshot in secure_state; default OFF when never fetched; reactive provider; data kept when a flag turns off (EC-49).",
  ["Never-synced app has all flags OFF","Flag change from sync updates UI without restart"],["Unit tests"],"A","FR-BE-05, FR-ZAK-06")

# ───────────────────────── Content (lane C) ─────────────────────────
T("copy1","M0","US-20-1","Copy deck part 1: onboarding, capture, Home, transactions, review, accounts","C3","ux-designer",[],
  "docs/02-design/copy-deck.md",
  "Egyptian Arabic + English strings for the first milestones.",
  "Keyed strings (feature_screen_element) following 06-voice-and-tone; states (empty/loading/error); plurals/ICU; mascot lines for these screens; no jokes on errors/permissions/payments.",
  ["Every string on S-01…S-16, S-06, S-40…S-43, S-61/62 has AR+EN","Keys follow naming convention"],["Copy checklist review by Lead"],"C","Phase 2 part 2", model="opus")
T("copy2","M0","US-20-1","Copy deck part 2: insights, budget, bills, money, chat, voice, roast, explanations","C3","ux-designer",[],
  "docs/02-design/copy-deck.md",
  "Strings and explanation/roast templates for M3–M4.",
  "Keyed strings for S-20…S-24, S-30…S-32, S-44…S-46, S-50/51; chart explanation templates (basic vs deep, OQ-07 definition); roast templates (A-18 rules); chat answer templates and suggested chips.",
  ["All templates have value placeholders and AR/EN","Roast lines pass A-18 checklist"],["Copy review"],"C","FR-CHT-03, FR-CHAT-04", model="opus")
T("copy3","M0","US-20-1","Copy deck part 3: settings, Gold, backup, import/export, notifications, errors, legal","C3","ux-designer",[],
  "docs/02-design/copy-deck.md",
  "Remaining strings incl. legal/disclaimers in simple standard Arabic.",
  "S-60…S-74, paywall, consent texts (online speech, contribution opt-in), 'what the server knows', notifications (redacted variants), error catalogue mapped to failure codes, Zakah/ROI/coaching disclaimers.",
  ["Every Failure code has user copy","Legal texts have an Egyptian one-line summary"],["Copy review"],"C","FR-L10N-02/04, NFR-LEGAL-03", model="opus")
T("copy_review","M2","US-20-1","Native Egyptian-speaker review of the copy deck","C2","external",["copy1","copy2","copy3"],
  "docs/02-design/copy-deck.md",
  "Human review required by FR-L10N-02 acceptance.",
  "Product owner arranges a native Egyptian reviewer; Lead applies edits via ARB task.",
  ["Reviewer sign-off recorded in copy-deck.md"],["—"],"C","FR-L10N-02", ext=True)
T("arb1","M1","US-02-2","Generate ARB files from copy deck (part 1)","C1","boilerplate-engineer",["l10n","copy1"],
  "app/lib/core/l10n/app_ar.arb, app_en.arb",
  "Strings available to M1/M2 screens.",
  "Transcribe copy deck part 1 keys into ARB with ICU plurals; run gen-l10n.",
  ["gen-l10n succeeds; no missing keys between ar/en"],["ARB parity test"],"C","ADR-017")
T("arb2","M3","US-02-2","Generate ARB files from copy deck (parts 2–3)","C1","boilerplate-engineer",["arb1","copy2","copy3"],
  "app/lib/core/l10n/*.arb",
  "Strings for M3–M7 screens.",
  "Transcribe parts 2–3; templates kept as ICU with placeholders.",
  ["ARB parity test passes"],["ARB parity test"],"C","ADR-017")
T("catalog_seed","M1","US-07-1","Catalog seed pipeline and 14 system categories","C2","flutter-core-engineer",["db_b"],
  "tools/catalog_build/, app/assets/catalog/",
  "Bundled, signed merchant/category catalog that works on first launch offline.",
  "CLI converting curated CSV (categories from spec §4 with subcategories/buckets/colours; merchants, aliases, keywords) to catalog_seed.json.gz + dev signature; first-launch loader into catalog tables; merchant list content from OQ-05 (initial ~150 spec examples until the 600+ list arrives).",
  ["14 system categories in AR/EN exactly as spec","Seed loads in < 1 s on reference device","Tampered seed rejected"],["Loader tests","Signature tests"],"A","FR-CAT-01/02, OQ-05")
T("merchant_list","M2","US-20-1","Compile the 600+ Egyptian merchant seed list (OQ-05)","C2","external",["catalog_seed"],
  "tools/catalog_build/merchants.csv",
  "Content needed for SM-04 categorization targets.",
  "Product owner/content compiles merchants with category, Arabic/English names and aliases; boilerplate-engineer converts.",
  ["≥ 600 merchants with category and ≥ 1 alias each"],["Catalog lint"],"C","FR-CAT-02, OQ-05", ext=True)
T("rive_asset","M3","US-10-3","Produce zaghlol.riv from the vector rig (illustrator)","C2","external",[],
  "app/assets/rive/zaghlol.riv",
  "Production mascot animation per D-35.",
  "Illustrator rebuilds brand/zaghlol-mascot-rig.svg in Rive: state machine ZaghlolAvatar, inputs state(enum of 15 moments)/talk/reduceMotion; timing per 08-mascot-motion; hidden parts (head turn, coin wing).",
  ["All 15 moments present and ≤ 3 s one-offs","File ≤ 500 KB"],["Visual review against Motion Lab"],"C","ADR-020, D-35", ext=True)
T("samples","M1","US-05-1","Convert real SMS/notification/statement samples into synthetic fixtures (OQ-04/18)","C2","parsing-engine-engineer",["normalize"],
  "packages/zaghlol_parsing/fixtures/",
  "Realistic fixtures without real customer data.",
  "Product owner provides anonymized samples per institution (M rows first); engineer rewrites names, digits, references and IPAs into synthetic fixtures; originals never committed.",
  ["≥ 4 fixtures per event type for M-priority institutions","No real names/digits (review checklist)"],["Fixture lint"],"F","OQ-04/18, testing-strategy §2", blocked="Waiting for samples from product owner (OQ-04/OQ-18)")

# ───────────────────────── M1 Parsing core ─────────────────────────
T("registry","M1","US-05-1","Template registry format, loader and registry_lint CLI","C3","parsing-engine-engineer",["normalize"],
  "packages/zaghlol_parsing/lib/registry/, tools/registry_lint/",
  "Banks become data: schema, loader and a linter that runs every fixture.",
  "JSON schema per parsing-engine §3; loader with precompiled regex cache per isolate; registry_manifest with registryVersion; lint: schema, regex compile, catastrophic-backtracking heuristic, fixture runner, cross-match detection, Guard-config subset export.",
  ["Lint fails on invalid regex or a fixture regression","Registry loads 80 institutions in < 150 ms"],["Lint self-tests","Load benchmark"],"F","ADR-003, parsing-engine §3, FR-PAR-08, NFR-MAINT-01")
T("pipeline","M1","US-05-1","Parsing pipeline stages 1–7 and ParseResult","C3","parsing-engine-engineer",["registry","money"],
  "packages/zaghlol_parsing/lib/pipeline/",
  "Turn a raw message into typed fields with direction and confidence.",
  "Institution resolve; language detection; ordered template match; typed extraction (Money incl. original/billed amount, last4, merchant, counterparty kind, balance/available, ref, date/time with nearest-past year policy); direction from event; sanity penalties; confidence threshold constant (A-12).",
  ["Spec NBE example parses to expected fields","Missing optional fields are null, never guessed","Parse < 2 ms mean on CI host"],["Fixture runner","Benchmark"],"F","parsing-engine §1–4, FR-PAR-02/03/06/09")
T("merchant_clean","M1","US-07-1","Merchant cleaning and normalized merchant key","C2","parsing-engine-engineer",["normalize"],
  "packages/zaghlol_parsing/lib/merchant/",
  "Clean display names and stable keys for matching.",
  "Strip POS/terminal codes, country/city tokens (list in registry), legal suffixes; title-case display; merchant_norm with Arabic→Latin transliteration and el/al unification.",
  ["`CARREFOUR MAADI EG 041` → Carrefour","`ELEZABY`, `EL EZABY` share a key"],["Table-driven tests"],"F","FR-PAR-05, parsing-engine §5")
T("guard_dart","M1","US-03-1","Capture Guard rules in Dart, shared golden cases and config generator","C4","parsing-engine-engineer",["registry"],
  "packages/zaghlol_parsing/lib/guard/, guard golden cases JSON",
  "One definition of what may be stored, reused by Kotlin and Swift.",
  "Guard algorithm per platform-channels §1.2; config JSON generator from registry + DB state (ignore rules, capture senders, custom templates); shared golden case file (≥ 60 cases: non-financial drop, OTP drop, institution ignore, card ignore, generic keep) consumed by Dart/Kotlin/Swift tests.",
  ["Golden cases pass in Dart","Ignore matches institution+last4, never last4 alone (EC-59)"],["Golden case tests"],"F","BR-CAP-01/02, BR-ING-01/03", model="opus")
T("tpl_top","M1","US-05-1","Templates + fixtures: NBE, CIB, Banque Misr, QNB","C2","parsing-engine-engineer",["pipeline"],
  "app/assets/registry/institutions/{nbe,cib,banque_misr,qnb}.json, fixtures",
  "The four largest Egyptian banks parse correctly.",
  "Card purchase, foreign card purchase, ATM, transfers in/out, salary, refund/reversal, declined, cc payment, OTP/promo drop patterns; AR+EN; Guard sender/last4 data.",
  ["≥ 4 fixtures per template pass","No cross-matches"],["registry_lint fixtures"],"F","FR-PAR-01")
T("tpl_instapay","M1","US-05-1","Templates + fixtures: InstaPay scenarios and mobile wallets","C2","parsing-engine-engineer",["pipeline"],
  "institutions/{instapay,vodafone_cash,etisalat_cash,orange_cash,we_pay,…}.json",
  "InstaPay and wallets (spec's 6 scenarios + 6 wallets/cards).",
  "IPA/phone counterparties (never uploaded), cc payment via InstaPay (EC-19 → transfer), wallet top-up; AR+EN.",
  ["All spec InstaPay scenarios parse","Counterparty kind correct (ipa/phone)"],["registry_lint fixtures"],"F","FR-PAR-01, EC-19")

# ───────────────────────── M1 Android capture ─────────────────────────
T("and_guard","M1","US-03-1","Android Capture Guard (Kotlin) with config reader","C4","native-platform-engineer",["guard_dart","spk_android"],
  "android/.../guard/",
  "Kotlin Guard identical to Dart rules.",
  "GuardConfig decrypt/parse; compiled-in fallback sender list; algorithm per §1.2; consumes shared golden cases in JUnit.",
  ["All shared golden cases pass in Kotlin","Malformed config → fallback senders still kept"],["JUnit golden tests"],"D","platform-channels §1")
T("and_spool","M1","US-03-1","Android encrypted spool + spool host API","C4","native-platform-engineer",["pigeon","spk_android"],
  "android/.../spool/, AndroidCaptureHostApi (drain/ack/writeGuardConfig/scheduleIngestionNow)",
  "Loss-free, encrypted hand-off from native to Dart.",
  "Keystore AES-256-GCM key (StrongBox if available, no user auth); CBOR entries in noBackupFilesDir/spool, atomic write; drain returns decrypted entries; ack deletes; KEY_INVALIDATED handling; quarantine after 3 decrypt failures.",
  ["Entries survive process kill","Files unreadable without key","Ack deletes only listed ids"],["Robolectric + instrumented tests"],"D","ADR-005")
T("and_sms","M1","US-03-1","SMS receiver (multipart, Guard, spool, enqueue) in prodSms flavor","C4","native-platform-engineer",["and_guard","and_spool"],
  "android/.../capture/SmsReceiver.kt, prodSms manifest",
  "Live SMS capture with personal SMS never stored.",
  "SMS_RECEIVED receiver; assemble multipart PDUs (EC-09); sim slot (EC-11); Guard; spool; goAsync ≤ 5 s; enqueue expedited IngestionWorker; notify engine if attached; nothing logged.",
  ["Personal SMS leaves no file","Bank SMS creates one spool entry","Multipart message assembled once"],["Instrumented tests with emulator SMS","privacy check of files dir"],"D","FR-ING-A-01/02")
T("and_worker","M1","US-03-1","IngestionWorker with headless Flutter engine and foreground events","C4","native-platform-engineer",["and_spool","spk_android"],
  "android/.../spool/IngestionWorker.kt, app/lib/ingestion_main.dart (entrypoint shell), CaptureEventsApi",
  "Background processing of the spool within 10 s.",
  "Expedited work; reuse cached engine if app alive else start headless engine at ingestionMain; wait for Dart completion (≤ 60 s); re-enqueue with back-off if spool non-empty; EventChannel onSpoolChanged for foreground.",
  ["App killed: SMS → spool drained by worker","Foreground: drained within 2 s"],["Instrumented tests"],"D","architecture §4.3")
T("and_inbox","M1","US-03-2","Inbox reader for historical scan (sender-filtered, paged)","C4","native-platform-engineer",["pigeon","and_guard"],
  "android/.../capture/InboxReader.kt, queryInbox host API",
  "Read only allowlisted senders' past SMS.",
  "ContentResolver query with address IN (…) AND date > since, paged by _id, page ≤ 500; returns in-memory pages; never touches other senders.",
  ["Query never returns non-allowlisted senders","10k messages paged without OOM"],["Instrumented test with seeded inbox"],"D","FR-ONB-06, NFR-PRIV-04")
T("and_notif","M1","US-03-3","Bank notification listener service","C4","native-platform-engineer",["and_guard","and_spool"],
  "android/.../capture/BankNotificationListener.kt",
  "Capture bank/wallet/online-bank app notifications.",
  "NotificationListenerService filtering packages from config; read title/text/bigText; skip ongoing & group summaries; Guard; spool; enqueue worker.",
  ["Registered package notification → spool entry","Other apps ignored and not read into storage"],["Instrumented test posting fake notifications"],"D","FR-ING-A-03/07")
T("and_perm","M1","US-03-4","Android capabilities and permission flows host API","C4","native-platform-engineer",["and_sms","and_notif"],
  "AndroidCaptureHostApi (getCapabilities, requestSmsPermission, openNotificationAccessSettings, battery optimisation)",
  "Everything the onboarding and degraded mode need from Android.",
  "Capabilities incl. smsFlavor; runtime permission request; settings intents; permission change callbacks (EC-13); POST_NOTIFICATIONS on 13+.",
  ["prodNoSms reports smsFlavor=false and never requests SMS","Revoking SMS triggers onPermissionChanged"],["Instrumented tests"],"D","FR-ONB-05, FR-ING-A-05")
T("and_share","M2","US-03-4","Android share/paste intake (text, image, PDF, CSV)","C3","native-platform-engineer",["pigeon"],
  "android manifest intent filters, ShareActivity, host API",
  "Users can send messages/files to Zaghlol.",
  "Intent filters text/plain, image/*, application/pdf, text/csv; images/PDFs copied encrypted with spool key; in-app confirmation route; paste is user-initiated only.",
  ["Shared text opens confirmation with parsed fields","Shared image goes to OCR flow"],["Instrumented tests"],"D","FR-ING-A-04")

# ───────────────────────── M1 Ingestion/accounts/home ─────────────────────────
T("accounts_repo","M1","US-06-1","Accounts repository: auto-create, default cash, per-currency balances","C3","flutter-core-engineer",["db_a"],
  "app/lib/features/accounts/data/",
  "Cards and accounts appear automatically and track balances.",
  "Find-or-create by (institution, last4); kind inference from template event/hints; exactly one default cash; balances upsert when message newer than as_of; merge (re-link transactions) and hide.",
  ["Same inst+last4 never creates two accounts","Older message doesn't overwrite newer balance","Merge moves all transactions"],["Repository tests"],"A","FR-ACC-01…06")
T("ingest","M1","US-06-1","IngestRawMessages use case (dedupe, merge, persist, ack, events)","C4","flutter-core-engineer",["pipeline","accounts_repo","result_bus","guard_dart"],
  "app/lib/features/ingestion/application/",
  "The single path from raw message to stored transaction.",
  "Guard re-check; parse; body-hash dedupe; cross-channel ±2 min dedupe; pending/settled merge (A-63); account resolve; categorize hook (interface, rule/none until categorizer lands); persist txn + raw message in one transaction; return ids to ack; review items for low confidence/unrecognized; emit events. Idempotent.",
  ["Same SMS twice → one transaction","SMS + notification of same payment → one transaction","Crash before commit → re-processing creates no duplicate"],["Use-case tests with fakes","Property test: random re-delivery order"],"A","parsing-engine §6, BR-ING-02, NFR-REL-01")
T("capture_app","M1","US-03-1","Capture module (app side): guard config writer, spool orchestrator, degraded mode","C3","flutter-core-engineer",["ingest","and_spool","guard_dart"],
  "app/lib/features/capture/",
  "Dart side of capture on Android (iOS hooks added in M2).",
  "Write encrypted guard config on changes/app update; drain spool on foreground event, app start and from ingestionMain; capability/degraded state provider; setup progress state (FR-ONB-11).",
  ["Changing an ignore rule rewrites config before next capture","Degraded mode lists active channels"],["Unit tests with fake host API","Integration test on emulator"],"A","FR-ING-A-05, FR-ONB-11, FR-ING-A-08")
T("scan","M1","US-03-2","Historical inbox scan with progress (Android)","C3","flutter-core-engineer",["capture_app","and_inbox"],
  "app/lib/features/capture/application/scan.dart",
  "First-run scan that fills Home progressively.",
  "Scan depth setting (default 6 months, A-11); page through queryInbox; Guard in Dart; ingest in batches in an isolate; progress stream (count, institutions found); ignored cards skipped (EC-62); re-scan for one card (FR-CAP-07).",
  ["First parsed transactions visible < 10 s after permission","10k SMS < 60 s on reference device"],["Integration test with seeded inbox","Benchmark"],"A","FR-ONB-06, NFR-PERF-03")
T("review_repo","M1","US-06-2","Review queue domain and repository","C2","flutter-core-engineer",["db_c","ingest"],
  "app/lib/features/ingestion/data/review_repository.dart",
  "Nothing uncertain is lost; everything waits for the user.",
  "Review item kinds per schema; resolve actions (dismiss, manual fields → create txn, accept suggestion, request my bank → outbox); counts provider for Home pill.",
  ["Dismissed raw message status updates","Manual entry from unrecognized message creates a verified transaction"],["Repository tests"],"A","FR-ING-A-06")
T("txn_repo","M1","US-06-3","Transactions repository: query, search, CRUD, soft delete","C2","flutter-core-engineer",["db_a"],
  "app/lib/features/transactions/data/",
  "Typed access to transactions for every screen.",
  "Filters (period, accounts, categories, type, source, currency); FTS search incl. amount text; add/edit marks user-verified; soft delete with 30-day purge job.",
  ["Search < 200 ms on 50k rows","Edit of auto-captured sets is_user_verified"],["Repository tests","Search benchmark"],"A","FR-TXN-01…05")
T("cycle","M1","US-09-1","Payday cycle engine, safe-to-spend, burn line and cycle summaries","C3","flutter-core-engineer",["money","db_b","txn_repo"],
  "packages/zaghlol_domain/lib/budget/, app cycle_summaries maintenance",
  "Correct cycle totals per currency for Home and budgets.",
  "cycleFor(payday 1–28, A-43 default day 1), mid-cycle payday change (EC-21), spend/income per currency excluding internal/declined, offsets by expense cycle (BR-XFR-07), safeToSpend/idealBurn, cycle_summaries cache invalidated by events.",
  ["Spec example: 2,200 left, 7 days → 314/day","Payday 25 → 25 Oct–24 Nov","Every payday 1–28 × every month boundary correct"],["Unit + property tests"],"A","domain-algorithms §2, BR-BUD-01/03/04, BR-TXN-02/03")
T("home_model","M1","US-10-2","Home read model and persistent card filter","C2","flutter-core-engineer",["cycle","txn_repo","accounts_repo","review_repo"],
  "app/lib/features/home/application/",
  "Data for Home in one reactive provider.",
  "Per-currency hero (primary first), KPIs, recent feed with internal transfers labelled excluded, review count, scan-in-progress state; global card filter provider (single/multi, persists while navigating, FR-CARD-01).",
  ["User with only EGP sees no currency UI data (EC-55)","Card filter changes all Home figures"],["Provider tests"],"A","FR-HOME-01/03/05, FR-CARD-01")
T("mascot_widget","M1","US-10-3","ZaghlolAvatar widget with static fallback and reduce-motion","C2","flutter-ui-engineer",["theme"],
  "app/lib/features/mascot/presentation/",
  "One mascot widget for every screen, ready for the Rive file.",
  "Widget API state enum (15 moments) + talk; Rive runtime when zaghlol.riv present, else SVG-rig static poses from brand assets; respects OS reduce-motion and in-app toggle; one instance per screen.",
  ["Reduce motion shows a still pose with no animation","Swapping in the .riv file needs no API change"],["Widget/golden tests"],"G","ADR-020, FR-MAS-01/03")
T("home_ui","M1","US-10-2","Home screen S-10 (iOS and Android variants)","C2","flutter-ui-engineer",["home_model","shell","arb1","mascot_widget"],
  "app/lib/features/home/presentation/",
  "The approved Home design, live.",
  "Hero (safe to spend / this month until payday set), KPIs, mascot banner slot, review pill, recent list, scan banner, currency swipe cards when >1 currency, card filter chip; empty/loading/error states; Android M3 variant.",
  ["Matches mockups 03/20/21/22 within golden tolerance","Empty state names the active card filter (EC-61)"],["Golden tests ar/en × light/dark × iOS/Android"],"G","S-10, mockups 03/20–22")
T("onb_welcome","M1","US-10-1","Welcome screen S-01 with language toggle and restore entry","C2","flutter-ui-engineer",["shell","arb1","mascot_widget"],
  "app/lib/features/onboarding/presentation/welcome.dart",
  "First screen per FR-ONB-01.",
  "Single primary button; language toggle switches app immediately; 'I already use Zaghlol' → restore route (placeholder until M6); privacy copy without 'no server' claim.",
  ["One primary action only","Language switch flips direction instantly"],["Golden tests"],"G","S-01, FR-ONB-01/12")
T("onb_android","M1","US-10-1","Android capture setup S-02 with live scan and degraded variant","C2","flutter-ui-engineer",["onb_welcome","and_perm","scan"],
  "app/lib/features/onboarding/presentation/android_setup.dart",
  "≤ 3 taps from welcome to SMS permission; scan starts immediately.",
  "Step 1 SMS explanation → system permission; Step 2 notification access while scan runs (mockup 23); degraded variant when denied/prodNoSms; skip → Home with finish-setup state.",
  ["≤ 3 user actions from welcome to permission granted","prodNoSms shows notification-first variant"],["Integration test on emulator","Golden tests"],"G","S-02, mockups 19/23")
T("onb_cards","M1","US-10-1","Scan results screen S-06 «دي كروتك؟»","C2","flutter-ui-engineer",["onb_android","accounts_repo"],
  "app/lib/features/onboarding/presentation/scan_results.dart",
  "Show what the scan found and let the user fix card types.",
  "Stats (categorized, needs review, cards), cards list with guessed type, credit-card prompt → S-43 credit fields, ignore entry → S-62, 'show my money'; skipped when 0 found; shown as sheet if scan finishes after user left.",
  ["Matches mockup 24","0 messages → straight to Home empty state"],["Golden + widget tests"],"G","S-06, mockup 24, 07-flows §C")

# ───────────────────────── M2 iOS capture ─────────────────────────
T("ios_guard","M2","US-04-1","iOS Capture Guard (Swift) with config reader","C4","native-platform-engineer",["guard_dart","spk_ios"],
  "ios/Runner/Guard/",
  "Swift Guard identical to Dart rules.",
  "GuardConfig decrypt/parse (Keychain spool key); compiled-in fallback senders; walletCardNames mapping for Apple Pay; shared golden cases in XCTest.",
  ["All shared golden cases pass in Swift"],["XCTest golden tests"],"E","platform-channels §1")
T("ios_spool","M2","US-04-1","iOS encrypted spool, host API and background refresh","C4","native-platform-engineer",["pigeon","spk_ios"],
  "ios/Runner/Spool/, IosCaptureHostApi",
  "Encrypted spool shared with the Share Extension.",
  "Keychain key (AfterFirstUnlockThisDeviceOnly, shared access group); App Group container excluded from backup; atomic writes; drain/ack; BGAppRefreshTask 'app.zaghlol.ingest'.",
  ["Entries readable by app after extension writes","Container excluded from iCloud device backup"],["XCTest"],"E","ADR-005/006")
T("ios_intents","M2","US-04-1","App Intents for Message and Wallet automations","C4","native-platform-engineer",["ios_guard","ios_spool"],
  "ios/Runner/Capture/",
  "Shortcuts can hand bank SMS and Apple Pay payments to Zaghlol (FinArt/Say approach).",
  "LogBankMessageIntent(message, sender?), LogWalletTransactionIntent(amount, merchant, card); Guard → spool; amount-free dialog «زغلول سجلها ✓»; per-intent last-run timestamps; AppShortcutsProvider; immediate processing if SPK-03 says go.",
  ["Intent run while app is closed creates a spool entry","Dialog never contains amounts"],["XCTest of perform()","Manual Shortcuts run on iOS 17 and 26"],"E","FR-ING-I-01/02, D-39")
T("ios_shortcut","M2","US-04-1","Shortcut package, iCloud link and setup checker","C3","native-platform-engineer",["ios_intents"],
  "app/assets/shortcuts/, getShortcutSetupStatus",
  "One-tap install of all keyword automations + Wallet automation, with a checker.",
  "Author Zaghlol.shortcut (Arabic/English keyword Message automations + Transaction automation) on macOS, sign/share iCloud link; checker reports missing automations from intent timestamps and 7-day silence (FR-ING-I-07); install guide images.",
  ["Fresh iPhone reaches a working automation in ≤ 3 steps","Checker flags a disabled automation"],["Manual test script on iOS 17/26"],"E","FR-ING-I-06/07, R-07")
T("ios_share","M2","US-04-2","iOS Share Extension (text, image, PDF)","C4","native-platform-engineer",["ios_spool"],
  "ios/ShareExtension/",
  "Share a message, screenshot or statement to Zaghlol.",
  "Accept text/images/PDF; Guard for text; encrypted copies to spool/files for images/PDF; never parses or shows amounts; Back Tap guide.",
  ["Shared screenshot appears in app OCR confirmation","No plaintext file left in container"],["XCTest","Manual"],"E","FR-ING-I-04")
T("capture_ios_app","M2","US-04-1","Capture module iOS integration (drain, BG refresh, checker state)","C3","flutter-core-engineer",["capture_app","ios_spool","ios_shortcut"],
  "app/lib/features/capture/ (iOS adapters)",
  "Dart side of iOS capture.",
  "Drain spool on foreground/BG refresh; guard config writes via iOS host; checker state for Home/Settings nudges (EC-14).",
  ["Captures from Shortcuts appear on next open","Checker nudge appears after 7 days of silence"],["Unit tests with fake host","Manual device test"],"A","FR-ING-I-07")
T("onb_ios","M2","US-10-1","iOS capture setup S-03 (add Shortcut, check setup, first expense)","C2","flutter-ui-engineer",["onb_welcome","capture_ios_app"],
  "app/lib/features/onboarding/presentation/ios_setup.dart",
  "iPhone users reach first value in ≤ 60 s.",
  "Step 1 add shortcut; step 2 checker with fix instructions (mockup 26); step 3 first expense by voice/typing (mockup 27) with online-bank guidance link.",
  ["Matches mockups 02/26/27","Skip at any step → Home with finish-setup card"],["Golden tests","Usability check script"],"G","S-03, FR-ONB-09")

# ───────────────────────── M2 Templates (parallel batch) ─────────────────────────
T("tpl_eg1","M2","US-05-1","Templates + fixtures: Egyptian banks batch 1","C2","parsing-engine-engineer",["pipeline"],
  "institutions/*.json (batch 1 per institutions.md M rows)",
  "Half of the remaining Egyptian banks.",
  "Same event coverage as top banks; AR+EN.",
  ["≥ 4 fixtures per template pass; no cross-matches"],["registry_lint"],"F","FR-PAR-01")
T("tpl_eg2","M2","US-05-1","Templates + fixtures: Egyptian banks batch 2","C2","parsing-engine-engineer",["pipeline"],
  "institutions/*.json (batch 2)",
  "Remaining Egyptian banks.",
  "Same as batch 1.",
  ["≥ 4 fixtures per template pass; no cross-matches"],["registry_lint"],"F","FR-PAR-01")
T("tpl_bnpl","M2","US-05-1","Templates + fixtures: BNPL (valU, Sympl, Souhoola, Shahry, Aman, Forsa, Contact)","C2","parsing-engine-engineer",["pipeline"],
  "institutions/{valu,sympl,…}.json",
  "Installment providers parse and feed recurring tracking.",
  "Purchase, installment due/paid events; bnpl account kind.",
  ["Fixtures pass; installment events tagged for SUB matching"],["registry_lint"],"F","FR-PAR-01, FR-SUB-03")
T("tpl_online","M2","US-05-1","Templates + fixtures: Wise, Revolut, Monzo, bunq, N26, Payoneer","C3","parsing-engine-engineer",["pipeline"],
  "institutions/{wise,revolut,monzo,bunq,n26,payoneer}.json",
  "Online banks incl. FX conversions and pending/settled.",
  "English notification templates; card payments, transfers, top-ups, refunds, declines, in-app conversions (fx_conversion event), pending_auth/settled; multi-currency account kind.",
  ["Wise USD→EGP conversion yields fx_conversion with two legs","Pending then settled merges (EC-54)"],["registry_lint","Pipeline tests for FX/pending"],"F","FR-PAR-10/12, D-27/32")
T("tpl_intl","M2","US-05-1","Templates + fixtures: HDFC, Paytm, Al Rajhi, Emirates NBD/Liv, GCC (S rows)","C2","parsing-engine-engineer",["pipeline"],
  "institutions/{hdfc,paytm,alrajhi,enbd,…}.json",
  "International and GCC institutions.",
  "Indian grouping, INR; Al Rajhi/ENBD AR+EN; SAR/AED/KWD 3-decimal cases.",
  ["`₹1,23,456.78` parses (EC-51)","`KWD 12.345` not truncated (EC-36)"],["registry_lint"],"F","FR-PAR-10/11/15")
T("generic","M2","US-05-2","Generic parser for unknown financial senders","C3","parsing-engine-engineer",["pipeline","merchant_clean"],
  "packages/zaghlol_parsing/lib/generic/",
  "Unlisted banks still produce suggestions in the review queue.",
  "Amount/currency adjacency, direction keyword dictionaries AR/EN, last-4, merchant span heuristic; always review; 'always capture' after 3 confirmations (A-66); unseen-format test set.",
  ["≥ 80% correct amount+currency on unseen set","Never auto-saves before 3 confirmations"],["Test set accuracy report"],"F","FR-PAR-13")

# ───────────────────────── M2 Categorization ─────────────────────────
T("rules_repo","M2","US-07-1","Merchant rules repository and apply-to-past","C2","flutter-core-engineer",["db_b","txn_repo"],
  "app/lib/features/categorization/data/rules_repository.dart",
  "User rules that always win.",
  "Rules by catalog merchant / merchant_norm / counterparty; 'apply to past N' with count (A-13); list/edit/delete; never uploaded.",
  ["New rule recategorizes the chosen past transactions only","Rule beats catalog"],["Repository tests"],"A","FR-CAT-05/08")
T("categorizer","M2","US-07-1","Categorizer with fuzzy merchant matching","C3","parsing-engine-engineer",["merchant_clean","db_b","rules_repo","catalog_seed"],
  "packages/zaghlol_parsing/lib/categorize/ + app adapter",
  "Automatic categorization at ≥ 80% (SM-04).",
  "Precedence rule > catalog exact > prefix/token > fuzzy (FTS5 trigram top-10 + Jaro-Winkler ≥ 0.92 / 0.88 contributed) > keywords (score ≥ 60, margin 20) > needs classification; P2P straight to rules/needs (BR-CAT-03); hooks into ingest.",
  ["ELEZABY / EL EZABY / صيدليات العزبي → El Ezaby","P2P transfer without rule → needs classification"],["Fixture-based categorization accuracy report","Unit tests"],"F","FR-CAT-03/04/06, BR-CAT-01/03")
T("reparse","M2","US-06-2","Re-parse job after registry version bump","C3","flutter-core-engineer",["ingest","registry"],
  "app/lib/features/ingestion/application/reparse.dart",
  "App updates fix past unrecognized messages automatically.",
  "On start, compare registryVersion; re-parse review messages and messages parsed by changed templates in an isolate; never touch user-verified transactions.",
  ["Updated template turns a review item into a transaction","User-verified rows unchanged"],["Use-case tests"],"A","A-46, parsing-engine §6")

# ───────────────────────── M2 Transactions & accounts UI ─────────────────────────
T("bulk","M2","US-06-3","Bulk edit and undo use case","C3","flutter-core-engineer",["txn_repo","rules_repo"],
  "app/lib/features/transactions/application/bulk_edit.dart",
  "Change many transactions at once with one Undo (D-36).",
  "Single DB transaction; before-image to undo_batches; category/account/delete; optional 'always use for these merchants' rules; undo restores and removes created rules; 24 h expiry.",
  ["10 selected → all updated and every total changes","One Undo restores all 10"],["Use-case tests"],"A","FR-TXN-06, domain §14")
T("ignore_domain","M2","US-06-4","Ignore rules domain: per card/channel, before-seen, keep/delete, re-scan","C3","flutter-core-engineer",["capture_app","txn_repo"],
  "app/lib/features/capture/application/ignore_rules.dart",
  "Users stop tracking specific cards and channels.",
  "Add/remove rules per channel and institution level; before-seen card (inst+last4); keep (default) or delete existing transactions; rewrite guard config immediately; re-scan offer on un-ignore (Android); links kept (EC-63).",
  ["Ignoring SMS for NBE *4567 still captures its notifications","Ignored SMS after rule leaves no trace"],["Use-case tests","Privacy integration check"],"A","FR-CAP-01…07, BR-CAP-*")
T("txn_list_ui","M2","US-06-3","Transactions list S-11 with filters, search and selection mode","C2","flutter-ui-engineer",["txn_repo","bulk","shell","arb1"],
  "app/lib/features/transactions/presentation/list/",
  "Find and bulk-edit transactions.",
  "Search-as-you-type (250 ms debounce), filter chips & sheets, day headers per currency, selection mode («اختار» / long-press), action bar, undo snackbar, bulk delete confirmation.",
  ["Select 10 → change category → undo works","No-results state names the search"],["Widget + golden tests"],"G","S-11")
T("txn_detail_ui","M2","US-06-3","Transaction detail S-12 and add/edit sheet S-13","C2","flutter-ui-engineer",["txn_repo","categorizer","accounts_repo","arb1"],
  "app/lib/features/transactions/presentation/detail/, edit/",
  "See and fix one transaction.",
  "Detail with category chip, card row, source badge, 'how Zaghlol read this' collapsible raw message and badges; add/edit sheet with account (default Cash), currency, date, note; 'always apply?' prompt after recategorize.",
  ["Matches mockup 04","Recategorize asks to save a rule"],["Golden + widget tests"],"G","S-12, S-13")
T("review_ui","M2","US-06-2","Review queue S-14","C2","flutter-ui-engineer",["review_repo","rules_repo","arb1"],
  "app/lib/features/ingestion/presentation/review/",
  "Resolve everything Zaghlol wasn't sure about.",
  "Filters by kind, category chips, new-bank card with accept/edit/dismiss, request my bank, transfer ambiguity, suggestions cards (reimbursement/subscription/payday as they land).",
  ["Matches mockup 05","Resolving updates Home pill count"],["Golden + widget tests"],"G","S-14")
T("quick_add_ui","M2","US-06-3","Quick add sheet S-30","C1","boilerplate-engineer",["shell","arb1"],
  "app/lib/features/home/presentation/quick_add_sheet.dart",
  "Add button opens the four options.",
  "Grid of say/type/scan/asset with Gold badge on asset; routes to existing/placeholder screens; voice quota line.",
  ["Matches mockup 11"],["Golden test"],"G","S-30")
T("money_ui","M2","US-06-5","Money tab S-40 (accounts per currency)","C2","flutter-ui-engineer",["accounts_repo","home_model","arb1"],
  "app/lib/features/accounts/presentation/money_tab.dart",
  "All cards and accounts with balances per currency.",
  "Net-worth hero per currency (accounts only until wealth lands), account list with 'as of', hidden/untracked rows, add button → S-43; assets section placeholder gated.",
  ["Matches mockup 13 (accounts part)"],["Golden tests"],"G","S-40")
T("card_detail_ui","M2","US-06-5","Card detail S-41, compare cards S-42","C2","flutter-ui-engineer",["money_ui","cycle"],
  "app/lib/features/accounts/presentation/card_detail.dart, compare.dart",
  "Per-card breakdown and comparison.",
  "Limit/balance card, donut by category, top merchants, trend, recent; empty state (mockup 31); compare table categories × cards per currency.",
  ["Category totals sum to card spend (FR-CARD-02)","Matches mockups 14/31"],["Widget + golden tests"],"G","S-41, S-42")
T("card_edit_ui","M2","US-06-5","Add/edit card S-43 (type → bank → details), merge and hide","C2","flutter-ui-engineer",["money_ui","ignore_domain"],
  "app/lib/features/accounts/presentation/edit_card/",
  "Manual card creation and editing per flows 07 §B.",
  "Type sheet (mockup 28), bank picker with search (mockup 29, monogram fallback), details form with validation and capture toggles (mockup 30), merge picker with confirm, hide toggle.",
  ["Validation rules from 07-flows §B enforced","Duplicate inst+last4 offers to open the existing card"],["Widget + golden tests"],"G","S-43, mockups 28–31, NFR-LEGAL-04 (bank logos gated by OQ-09)")
T("capture_settings_ui","M2","US-06-4","Capture settings S-61 and card capture sheet S-62","C2","flutter-ui-engineer",["ignore_domain","arb1"],
  "app/lib/features/capture/presentation/",
  "See and undo what Zaghlol ignores.",
  "Per-card channel toggles (mockup 17), keep/delete prompt, ignored list with one-tap undo, re-scan offer, iOS per-bank channel help (FR-ING-I-08).",
  ["Toggling a channel updates guard config immediately","Undo restores capture"],["Widget + golden tests"],"G","S-61, S-62")

# ───────────────────────── M3 Money brain ─────────────────────────
T("transfers","M3","US-08-1","Self-transfer pairing, FX conversions and card settlements","C3","flutter-core-engineer",["ingest","txn_repo"],
  "packages/zaghlol_domain/lib/transfers/, app application",
  "Own-account movements never count as spending.",
  "Pair opposite same-currency equal amounts within 5 min across user accounts; ambiguity → review (EC-16); late-arrival re-check; one-sided internal (EC-15); fx_conversion and cc_payment pairs; cross-currency suggestion (±3%, 3 days); manual link/unlink.",
  ["Spec example −1,000 NBE / +1,000 CIB within 2 min → 0 spend","Two candidates → no auto-pair"],["Unit tests with spec cases"],"A","domain §4, BR-XFR-01/02, FR-CUR-06")
T("offsets","M3","US-08-2","Refund matching and offset links","C3","flutter-core-engineer",["transfers"],
  "packages/zaghlol_domain/lib/transfers/offsets.dart",
  "Refunds reduce the original expense.",
  "Match refund to most recent same-merchant expense ≥ refund within 60 days; partial/oversized refunds (EC-17); unmatched → refund income; invariants enforced.",
  ["Partial refund reduces net spend correctly","Refund larger than expense → remainder is income"],["Unit tests"],"A","BR-XFR-03, BR-TXN-01")
T("splits","M3","US-08-2","Splits and reimbursements with allocation and unassign","C3","flutter-core-engineer",["offsets"],
  "packages/zaghlol_domain/lib/transfers/splits.dart",
  "Shared bills and friends' money back reduce real spending.",
  "Participants & shares; assign incoming to one/many expenses; one incoming across several expenses; caps (BR-XFR-06); later-cycle restatement (BR-XFR-07); unassign; expense edit/delete repair (EC-40).",
  ["1,200 bill + 400 + 400 → net 400","Reimbursement excluded from income"],["Unit tests with spec cases"],"A","FR-XFR-04…09, BR-XFR-04…08")
T("xfr_suggest","M3","US-08-2","Reimbursement and cross-currency pair suggestions","C2","flutter-core-engineer",["splits","review_repo"],
  "app/lib/features/transfers/application/suggestions.dart",
  "One-tap suggestions that never auto-apply.",
  "Incoming P2P within 7 days after Dining/Entertainment/Travel or shared expense with enough remaining → review suggestion; cross-currency suggestions; dismiss memory.",
  ["Suggestion appears and applies only on tap"],["Use-case tests"],"A","FR-XFR-08, FR-CUR-06")
T("xfr_ui","M3","US-08-2","Split/reimbursement sheet S-15 and link-transfer sheet S-16","C2","flutter-ui-engineer",["splits","transfers","txn_detail_ui"],
  "app/lib/features/transfers/presentation/",
  "UI for splitting and linking.",
  "Mockup 06 sheet: participants, status badges, suggested link pill, net paid; link-as-my-transfer sheet incl. cross-currency.",
  ["Matches mockup 06","Net figure updates live"],["Golden + widget tests"],"G","S-15, S-16")
T("notif","M3","US-10-4","Local notifications service (types, quiet hours, redaction)","C2","flutter-core-engineer",["settings_repo"],
  "app/lib/features/notifications/",
  "All alerts flow through one service.",
  "flutter_local_notifications + timezone; types per FR-NTF-01 with per-type toggles; quiet hours default 23–08; lock-screen redaction option (default on when app lock on); scheduling API; fired_alerts dedupe.",
  ["Quiet hours delay non-urgent alerts","Redacted variant shows no amounts"],["Unit tests","Device check"],"A","FR-NTF-*")
T("budgets","M3","US-09-1","Budgets per category and currency with threshold alerts","C2","flutter-core-engineer",["cycle","notif"],
  "app/lib/features/budget/",
  "Budgets that alert once per threshold per cycle.",
  "CRUD budgets (category or overall, one currency, cycle/annual, rollover option); progress per cycle; thresholds 80/100 default; one alert per threshold per cycle (BR-BUD-02); zero budget behaviour (EC-24).",
  ["EGP budget ignores GBP spend","Crossing 80% twice in a cycle alerts once"],["Unit tests"],"A","FR-BUD-01…06")
T("recurring","M3","US-09-2","Subscriptions detection, installments, gameya, card dues and reminders","C3","flutter-core-engineer",["txn_repo","notif"],
  "app/lib/features/recurring/",
  "Recurring money is tracked and reminded.",
  "Detection (≥ 2 charges, 25–35 days, ±10%); confirm/dismiss; annual ×12; installments with counts; gameya manual; card due from S-43 due day; auto-mark paid (±2%, ±5 days); reminders 3 days before.",
  ["Netflix-like history yields one suggestion","Matching payment marks installment paid"],["Unit tests"],"A","FR-SUB-*, BR-SUB-*")
T("ctx_suggest","M3","US-10-1","Contextual setup suggestions (payday, budgets, backup)","C2","flutter-core-engineer",["cycle","review_repo"],
  "app/lib/features/onboarding/application/contextual.dart",
  "Ask later, in context (D-21).",
  "Salary-like credit → payday suggestion; after first full cycle → budget suggestion; after 7 days → free backup suggestion (A-65); each shown once, dismissible forever.",
  ["Salary on day 25 → «ده ميعاد قبضك؟» once"],["Unit tests"],"A","FR-ONB-10")
T("mascot_policy","M3","US-10-3","Mascot trigger policy (shocked, detective, proud, tour guide)","C2","flutter-core-engineer",["cycle","transfers","budgets"],
  "packages/zaghlol_domain/lib/mascot_rules/",
  "Mascot banners fire on the right facts, in priority order.",
  "BR-MAS-01/02/03 rules; duplicate POS within 10 min (A-34); priority shocked > detective > proud > tourGuide; message ids with per-cycle once & dismissal memory.",
  ["Dining > 85% before day 20 → shocked banner","Only one banner at a time"],["Unit tests"],"A","domain §7")
T("mascot_motion","M3","US-10-3","Wire motion-only mascot moments to UI events","C2","flutter-ui-engineer",["mascot_widget","rive_asset"],
  "app/lib/features/mascot/presentation/",
  "Thinking, scanning, counting, saved, payday, oops, sleep, pull, tap moments (D-35).",
  "Event → state mapping; loops only during real work; ≤ 3 s one-offs; tap easter egg with copy-deck lines; pull-to-refresh on Home/Transactions.",
  ["Loops stop when work ends","Reduce motion shows still poses"],["Widget tests"],"G","08-mascot-motion")
T("dup_weekly","M3","US-10-4","Duplicate-charge and weekly-summary notifications","C2","flutter-core-engineer",["notif","ingest","cycle"],
  "app/lib/features/notifications/application/",
  "Two FR-NTF-01 types not covered elsewhere.",
  "Duplicate POS detection notification; weekly summary scheduled locally with redaction rules.",
  ["Two identical POS debits within 10 min → one alert"],["Unit tests"],"A","FR-NTF-01")
T("budget_ui","M3","US-09-1","Insights shell and Budget S-22 (+ edit budgets)","C2","flutter-ui-engineer",["budgets","arb2","shell"],
  "app/lib/features/budget/presentation/",
  "Budget screen per mockup 09.",
  "Segmented Insights header with card filter; cycle card; mascot banner; category bars with colour rules (terracotta only ≥ 85%); edit budgets screen per currency.",
  ["Matches mockup 09"],["Golden tests"],"G","S-20, S-22, S-23")
T("bills_ui","M3","US-09-2","Bills & installments S-24 and add/edit recurring item","C2","flutter-ui-engineer",["recurring","arb2"],
  "app/lib/features/recurring/presentation/",
  "Upcoming dues timeline.",
  "KPI cards, detective suggestion card, timeline with mark-paid, add/edit sheet for installment/gameya/bill.",
  ["Matches mockup 10"],["Golden tests"],"G","S-24")
T("finish_setup_ui","M3","US-10-1","Home contextual cards and Settings 'finish setup'","C2","flutter-ui-engineer",["home_ui","ctx_suggest","applock"],
  "app/lib/features/home/presentation/cards/, settings entry",
  "Payday card, app-lock offer after first transactions, finish setup list.",
  "Mockup 25 cards; app lock toggle offered once (FR-ONB-04); finish-setup list resumes skipped steps (FR-ONB-11).",
  ["Matches mockup 25","App lock offer appears only after transactions exist"],["Golden tests"],"G","FR-ONB-04/10/11")

# ───────────────────────── M4 Insights/chat/voice/wealth ─────────────────────────
T("chart_q","M4","US-11-1","Chart query layer for all 12 charts","C3","flutter-core-engineer",["cycle","recurring","splits"],
  "app/lib/features/insights/data/",
  "Fast, correct aggregates per currency, card and period.",
  "SQL aggregations for charts 1–12 (cash flow, donut, burn curve, 50/30/20 via buckets, day/hour pattern, top merchants, month vs 3-month avg, installment timeline, subscriptions ×12, cards split per currency, net worth (from snapshots), personal inflation); memoization keyed by (chart, period, filter, currency); 'not enough data' states (EC-23).",
  ["Each chart query < 100 ms on CI host with 2 years of data","Never mixes currencies unless ≈ view"],["Unit + benchmark tests"],"A","FR-CHT-01/04/05/06")
T("explain","M4","US-11-1","Explanation template engine (basic vs deep coaching)","C3","flutter-core-engineer",["chart_q","copy2"],
  "packages/zaghlol_domain/lib/insights/explanations.dart",
  "Zaghlol explains every chart with real numbers and one tip.",
  "Rules choose salient fact + tip per chart; Gold adds previous-cycle comparison, projection and drivers; values always computed.",
  ["Explanation numbers equal query results","Free shows basic only"],["Unit tests"],"A","FR-CHT-03, OQ-07")
T("charts_free","M4","US-11-1","Charts S-20: four Free charts and Gold-locked previews","C2","flutter-ui-engineer",["chart_q","budget_ui"],
  "app/lib/features/insights/presentation/charts/",
  "Cash flow, category donut, top merchants, budget bars; others locked.",
  "fl_chart, RTL time direction, legends, empty states naming filters; locked preview overlay with Gold CTA (FR-GOLD-05 cap).",
  ["Matches mockup 07","Charts render < 300 ms on reference device"],["Golden tests","Perf check"],"G","S-20, FR-CHT-02")
T("charts_gold","M4","US-11-1","Charts: remaining eight (Gold)","C2","flutter-ui-engineer",["charts_free","wealth_domain"],
  "app/lib/features/insights/presentation/charts/",
  "All 12 charts available to Gold.",
  "Burn curve, 50/30/20, day/hour, 3-month avg, installment timeline, subscriptions ×12, cards per currency (tap → S-41), net worth growth, personal inflation.",
  ["Each chart has empty state and works RTL/LTR"],["Golden tests"],"G","FR-CHT-01/06")
T("chart_detail_ui","M4","US-11-1","Chart detail with explanation S-21","C2","flutter-ui-engineer",["explain","charts_free"],
  "app/lib/features/insights/presentation/chart_detail.dart",
  "«اشرحلي يا زغلول» screen.",
  "Large chart, list, professor mascot bubble with tip, typing dots ≤ 600 ms.",
  ["Matches mockup 08"],["Golden tests"],"G","S-21")
T("voice_parser","M4","US-11-3","Egyptian Arabic voice-phrase parser and 200-phrase fixtures","C3","parsing-engine-engineer",["normalize","categorizer"],
  "packages/zaghlol_parsing/lib/voice/",
  "One phrase becomes several categorized items.",
  "Number words (ميت وخمسين, نص, ربع, ألفين…), currency words, item splitting, verb stripping, categorization, missing-amount flag (EC-30), mixed language (EC-31).",
  ["Spec phrase → 150 Groceries, 45 Dining, 30 Transport","≥ 95% item accuracy on fixture set"],["Phrase fixture tests"],"F","FR-VOI-02/05")
T("voice_ui","M4","US-11-3","Voice logger S-31 with on-device-first recognition and monthly limit","C3","flutter-ui-engineer",["voice_parser","gating","spk_speech"],
  "app/lib/features/voice/",
  "Speak, review, save.",
  "speech_to_text onDevice; consent sheet for online recognizer (D-42); listening mascot; parsed items list editable; account/date chips; save increments voice_usage on confirm; Free limit 15/month (A-14/15) with upsell.",
  ["Nothing saved without confirmation","16th Free log blocked with upsell"],["Widget tests","Device test"],"G","S-31, FR-VOI-01/03/04")
T("chat_engine","M4","US-11-2","Ask Zaghlol intent engine (grammar, slots, query plans, answers, roast)","C3","parsing-engine-engineer",["chart_q","copy2"],
  "packages/zaghlol_parsing/lib/chat/",
  "Offline answers to the FR-CHAT-01 intents.",
  "Weighted grammar data AR/EN incl. Egyptian forms; slots: category/merchant (fuzzy), card, period grammar, currency; query plans; one figure per currency; 'no data' answers; fallback chips; roast fact picker.",
  ["«صرفت كام بكارت CIB الشهر ده؟» answers per currency","Unknown question → fallback, never a number"],["Intent test set (≥ 300 utterances)"],"F","FR-CHAT-01/03/04/05")
T("chat_ui","M4","US-11-2","Ask Zaghlol screen S-50","C2","flutter-ui-engineer",["chat_engine"],
  "app/lib/features/chat/presentation/",
  "Chat UI with chips, mini charts and roast mode.",
  "Bubbles, inline mini bar chart, suggested chips, roast toggle, card filter chip, thinking moment.",
  ["Matches mockup 15"],["Golden tests"],"G","S-50")
T("prices_app","M4","US-12-1","Prices and FX store in app (sync-fed, manual override, stale)","C2","flutter-core-engineer",["db_c"],
  "app/lib/features/wealth/data/prices_repository.dart",
  "Local prices for valuation and ≈ view.",
  "Apply price/fx blocks; manual overrides; stale > 24 h labels (EC-34); missing rate handling (EC-35).",
  ["Override beats backend price","Stale label after 24 h"],["Unit tests"],"A","FR-WLT-03")
T("wealth_domain","M4","US-12-1","Assets, liabilities, net worth per unit and snapshots","C3","flutter-core-engineer",["prices_app","accounts_repo","recurring"],
  "packages/zaghlol_domain/lib/wealth/, app repository",
  "Net worth per currency/unit over time.",
  "Asset CRUD (gold by karat/grams, coins, certificates, cash, stocks, property, car); valuation; liabilities (cc balances, remaining installments); per-unit net worth; snapshots at cycle end + on demand; CD payout schedule.",
  ["Gold 24 g 21K valued at current 21K price","Net worth never sums across currencies"],["Unit tests"],"A","FR-WLT-01/02/04/05, BR-WLT-*")
T("approx","M4","US-12-2","≈ combined view service (target currency, rate date, exclusions)","C3","flutter-core-engineer",["money","prices_app"],
  "packages/zaghlol_domain/lib/money/approx.dart, settings",
  "Optional, clearly labelled combined totals.",
  "Integer conversion with rate_e9, banker's rounding at end; target currency selectable; returns rate date & excluded currencies; off by default.",
  ["Turning off removes every combined figure","Currency without rate listed as not included"],["Unit + property tests"],"A","FR-CUR-04/05, A-54/60/62")
T("currency_ui","M4","US-12-2","Shared per-currency figures and currency switcher component","C2","flutter-ui-engineer",["approx","home_ui"],
  "app/lib/core/theme/components/currency_switcher.dart + usages",
  "No screen silently mixes currencies.",
  "Switcher appears only with ≥ 2 currencies in filter; ≈ row with rate date; applied to Home, budgets, charts, card detail, net worth, chat, share cards.",
  ["Single-currency user sees no switcher (EC-55)"],["Widget tests"],"G","FR-CUR-03")
T("wealth_ui","M4","US-12-1","Money tab assets, Add asset S-44 and Prices S-45","C2","flutter-ui-engineer",["wealth_domain","money_ui","gating"],
  "app/lib/features/wealth/presentation/",
  "Gold and assets screens.",
  "Assets section with Gold badge, asset form per type with validation, prices screen with stale labels and manual override; Free locked preview.",
  ["Matches mockup 13 assets section","Free user opening Add asset sees paywall"],["Golden + widget tests"],"G","S-40/44/45")
T("share_cards","M4","US-11-4","Achievement share cards with hidden amounts by default","C2","flutter-ui-engineer",["chart_q","theme"],
  "app/lib/features/share_cards/",
  "Shareable PNGs with branding and hashtag.",
  "Templates (savings %, delivery cut…); hide amounts default (percentages); render offscreen to PNG; encrypted staging; system share sheet; unencrypted warning.",
  ["Hidden mode shows no amounts","Staging file deleted after share"],["Golden tests"],"G","FR-SHR-*, S-73")
T("widgets","M4","US-11-4","Home-screen widgets (Android Glance, iOS WidgetKit)","C3","native-platform-engineer",["cycle","pigeon"],
  "android widget/, ios ZaghlolWidget/, WidgetBridgeHostApi, app widgets_bridge",
  "Safe-to-spend and days to payday at a glance.",
  "Redacted snapshot strings written by app on TransactionsChanged; hide-amounts respected; tap deep link; quick-add voice widget (C).",
  ["Hide amounts shows •••","Widget updates within a minute of a new transaction"],["Manual device test","Snapshot unit tests"],"E","FR-WID-*", model="sonnet")

# ───────────────────────── M5 Backend (lane B, can start after M0) ─────────────────────────
T("be_db","M5","US-13-1","EF Core model and initial migration for all backend tables + DB roles","C4","backend-engineer",["be_scaffold"],
  "Zaghlol.Infrastructure/Persistence, Migrations",
  "Backend schema per backend-schema.md.",
  "Entities & configuration; initial migration; CHECK constraints; roles app_rw/worker_rw/migrator; migration job; expand/contract guideline doc comment.",
  ["Migration applies on empty PG 17","Privacy CHECKs present"],["Testcontainers migration test"],"B","backend-schema.md")
T("be_signing","M5","US-13-1","Signing service (ES256 via KMS abstraction) and response-signature middleware","C4","backend-engineer",["be_scaffold"],
  "Zaghlol.Infrastructure/Kms, Api middleware",
  "Every security-relevant response is signed.",
  "ISigner with KMS provider + local dev key; kid rotation (next/active/retired); Zaghlol-Signature header over exact body bytes; JWS compact builder for entitlement tokens; public JWK export for app embedding.",
  ["Signature verifies with exported public key","Rotation keeps old kid verifiable until retired"],["Unit tests with test vectors"],"B","ADR-012/013/018")
T("be_installs","M5","US-13-1","Install registration, install-token auth, rate limits, idempotency, strict DTOs","C4","backend-engineer",["be_db","openapi"],
  "Api/Endpoints/Installs, auth handler, middleware",
  "Anonymous installs with the accepted-fields boundary enforced.",
  "POST/DELETE /v1/installs; token SHA-256 storage; bearer auth handler; rate limiting per token & /24; Idempotency-Key store; unknown-field rejection; problem codes.",
  ["Unknown field → 400 UNKNOWN_FIELD","Deleted install token stops working immediately"],["Integration tests"],"B","FR-BE-01, BR-SYNC-03")
T("be_catalog","M5","US-13-1","Catalog versions, deltas, signed full snapshots and admin draft/publish","C3","backend-engineer",["be_db","be_signing"],
  "Application/Catalog, Api admin endpoints",
  "Versioned catalog with tiny deltas.",
  "Draft workspace; publish → immutable version with change log; delta (a,b] incl. tombstones; full snapshot gz + .sig to object storage/CDN; seed import from tools/catalog_build CSV.",
  ["Delta for an up-to-date client is empty","Snapshot signature verifies in app test"],["Integration tests"],"B","FR-BE-06, ADR-013", model="opus")
T("be_flags","M5","US-13-1","Feature flags with targeting rules and admin endpoints","C2","backend-engineer",["be_db"],
  "Application/Flags",
  "Remote flags (zakah, smart_roi, roi_named_products).",
  "Flag rules: platforms, min app version, rollout % (stable hash of install id); versioning; admin get/put with audit.",
  ["Rollout % stable per install","Default OFF"],["Unit + integration tests"],"B","FR-BE-05")
T("be_prices","M5","US-12-1","Price service: local Egyptian gold-market adapter, FX adapter, worker, override","C3","backend-engineer",["be_db"],
  "Infrastructure/Prices, Workers/PriceFetcher",
  "Gold per karat per gram (EGP, USD) and FX, served from cache.",
  "IPriceProvider; adapter for the contracted local gold-market feed (D-41; contract pending — build against interface + fake until credentials exist); FX adapter (licensed source); hourly worker; karat derivation where feed lacks a karat; stale flag; operator override.",
  ["Feed outage serves last value with stale after 24 h","Override wins until cleared"],["Unit tests with fake providers"],"B","FR-BE-04, ADR-014", blocked="Provider contract for local gold feed (D-41) needed before go-live; build continues with fakes")
T("be_sync","M5","US-13-1","Daily POST /v1/sync with throttle, contributions and bank-request intake","C4","backend-engineer",["be_installs","be_catalog","be_flags","be_prices","be_signing"],
  "Api/Endpoints/Sync, Application/Sync, Contributions, BankRequests, Metrics",
  "One small signed daily call.",
  "Compose blocks only when changed; server-side 24 h throttle; BR-SYNC-04 filters (person names, digits, phones, IPAs, custom categories); install_hash HMAC; daily_active_counts upsert; ≤ 2 KB when up to date.",
  ["Up-to-date response ≤ 2 KB","Contribution with a phone number is dropped","Second call within 24 h returns only serverTime/nextSyncNotBefore"],["Integration + contract tests"],"B","FR-SYNC-*, FR-BE-07/10, BR-SYNC-03/04")
T("be_contrib","M5","US-13-2","Contribution aggregation, review list and promote/reject","C2","backend-engineer",["be_sync","be_catalog"],
  "Workers/ContributionAggregator, admin endpoints",
  "Crowd-sourced merchants reach the catalog only via operator review.",
  "Aggregate by merchant_norm+institution; ready at ≥ 5 distinct installs (A-48); promote into draft; reject; raw rows purged per retention.",
  ["Nothing goes live without promote"],["Integration tests"],"B","FR-BE-07")
T("be_google","M5","US-14-1","Google Play purchase verification, acknowledgement and sweeper","C4","backend-engineer",["be_installs","be_signing"],
  "Infrastructure/GooglePlay, Application/Purchases",
  "Server-side verify & acknowledge Android purchases.",
  "subscriptionsv2.get / products.get; PURCHASED/ACTIVE only (pending → no Gold); obfuscatedExternalAccountId == HMAC(installId); upsert by token; acknowledge; 15-min sweeper; alert at 48 h unacked; Polly resilience.",
  ["Forged/replayed token rejected","Pending purchase grants nothing","Unacked purchase acked by sweeper"],["Integration tests with WireMock Play API"],"B","FR-BE-02, BR-GOLD-05/06")
T("be_apple","M5","US-14-1","App Store verification (JWS chain, Server API status, appAccountToken)","C4","backend-engineer",["be_installs","be_signing"],
  "Infrastructure/AppStore, Application/Purchases",
  "Server-side verify iOS purchases.",
  "Decide library (Enjna.AppStoreServerLibrary review vs in-house x5c→Apple Root CA G3 + ES256); bundleId/environment/appAccountToken checks; Get Transaction Info + subscription statuses; upsert by originalTransactionId.",
  ["Tampered JWS rejected","Sandbox and production handled"],["Unit tests with Apple test vectors","WireMock integration tests"],"B","FR-BE-02, ADR-012")
T("be_entitlement","M5","US-14-1","Entitlement computation, signed tokens, GET /v1/entitlement and restore","C4","backend-engineer",["be_google","be_apple"],
  "Application/Entitlements, Api endpoints",
  "Effective Gold per install/account as a signed token.",
  "Merge install + account purchases; token claims {sub, acct, plan, status, exp, graceUntil}; lifetime rolling 30-day exp; restore with re-binding & purchase_events; refresh in sync.",
  ["Restore on new install re-binds and grants Gold","Refunded purchase → status refunded in next token"],["Integration tests"],"B","FR-GOLD-03/04, BR-GOLD-03")
T("be_rtdn","M5","US-14-1","Google RTDN push endpoint, processing worker and voided reconciliation","C4","backend-engineer",["be_google"],
  "Api/Endpoints/Notifications/Google, Workers/NotificationProcessor",
  "Renewals, cancels, refunds update Gold within minutes.",
  "Pub/Sub push OIDC verification (audience + SA email); store & 204; worker re-reads Play state; dedupe by messageId; retries + dead-letter; daily voidedpurchases.list.",
  ["Refund notification revokes within minutes","Duplicate messages processed once"],["Integration tests incl. out-of-order"],"B","FR-BE-03")
T("be_assn","M5","US-14-1","App Store Server Notifications V2 endpoint and reconciliation","C4","backend-engineer",["be_apple"],
  "Api/Endpoints/Notifications/Apple, worker handlers",
  "Apple lifecycle events update Gold.",
  "Verify signedPayload chain; dedupe notificationUUID; handle SUBSCRIBED, DID_RENEW, DID_FAIL_TO_RENEW, EXPIRED, GRACE_PERIOD_EXPIRED, REFUND, REVOKE, DID_CHANGE_RENEWAL_STATUS; Get Notification History reconciliation.",
  ["REFUND marks purchase refunded","Invalid signature → 401, not stored"],["Integration tests"],"B","FR-BE-03")
T("be_accounts","M5","US-15-1","Accounts: Google/Apple ID token sign-in, linking, sign-out, delete, Android Apple callback","C4","backend-engineer",["be_entitlement"],
  "Application/Accounts, Api endpoints",
  "Optional account that only carries Gold.",
  "Verify Google (aud, iss, exp, JWKS) and Apple (aud, iss, nonce) tokens; Apple code exchange → encrypted refresh token for revocation; link install & purchases; 409 INSTALL_LINKED_TO_OTHER_ACCOUNT with replaceLink; account JWT 30 d; sign-out unlink; delete + Apple revoke; Android web-flow callback (D-44).",
  ["Buy on Android, sign in on iPhone → Gold (FR-GOLD-07)","Delete removes account and links"],["Integration tests with JWKS fakes"],"B","FR-BE-09, FR-ACCT-*")
T("be_admin","M5","US-13-2","Operator auth (OIDC + MFA), roles, audit log and support lookup","C4","backend-engineer",["be_db"],
  "Api/Admin, auth policies",
  "Secure operator access.",
  "OIDC JWT validation (company IdP, MFA claim required); roles; audit_log on every write; support lookup by exact install id or email returning status only; no bulk export.",
  ["Token without MFA claim rejected","Every write audited"],["Integration tests"],"B","FR-BE-08, NFR-SEC-07")
T("be_ops_cli","M5","US-13-2","zaghlol-ops CLI for catalog, flags, prices, contributions and support","C2","backend-engineer",["be_admin","be_catalog","be_flags","be_prices","be_contrib"],
  "Zaghlol.Ops",
  "v1 operator tooling (D-37).",
  "Device-code login; commands catalog draft/import/publish, flags get/set, prices override, contributions review/promote/reject, support lookup, bank-requests list.",
  ["All admin endpoints reachable from CLI with audit"],["CLI integration tests against Testcontainers"],"B","D-37")
T("be_retention","M5","US-13-1","Retention purger and log privacy settings","C2","backend-engineer",["be_db","be_observability"],
  "Workers/RetentionPurger, logging config",
  "Data kept only as long as allowed (NFR-PRIV-06).",
  "Daily purge per backend-schema §4; IP truncation; no body logging; token hashing in logs.",
  ["Inactive install > 12 months deleted","Logs contain no full IPs"],["Integration tests","Log assertion tests"],"B","NFR-PRIV-06")
T("be_observability","M5","US-21-1","Backend observability: OpenTelemetry, metrics, dashboards, alert rules","C2","backend-engineer",["be_scaffold"],
  "Api/Workers telemetry, deploy/observability",
  "Monitoring per error-handling §4.",
  "OTel traces/metrics; custom metrics (verify outcomes, unacked count, notification lag, price age, sync size); dashboards & alert rules as code; synthetic check definitions.",
  ["Metrics visible in local collector","Alert rules reviewed"],["Smoke test"],"B","error-handling §4")
T("be_infra","M5","US-13-1","Infrastructure as code and deployment pipeline (staging, prod)","C3","backend-engineer",["be_observability"],
  "backend/deploy/ (OpenTofu), .github/workflows/backend-deploy.yml",
  "Provider-neutral cloud setup.",
  "Modules: container service ×2, worker, managed PG 17 HA + PITR 14 d, KMS keys, object storage + CDN, secrets, WAF, Pub/Sub topic+push, DNS/TLS; OIDC-federated deploys; migration job; rollback.",
  ["Staging deploy from main is automatic","Prod promotes same image digest"],["Deploy smoke tests"],"B","deployment §3, ADR-015", model="opus", blocked="CR-03 / OQ-16: hosting provider & region + PDPL licence decision")

# app-side backend
T("be_client","M5","US-13-1","App BackendClient: generated DTOs, ES256 verification, lazy install registration","C4","flutter-core-engineer",["openapi","db_c"],
  "app/lib/core/backend/",
  "The only way the app talks to the backend, with the data boundary built in.",
  "DTOs from OpenAPI (no free-form maps); embedded public keys (current+next); verify Zaghlol-Signature over body bytes; error mapping to Failures; lazy POST /v1/installs; tokens in secure_state; recording client hook for privacy tests (debug only).",
  ["Unsigned or tampered response rejected","Only allow-listed fields can be serialized"],["Unit tests with signature vectors","Contract tests"],"A","backend-api §1, security-model §2")
T("contrib_outbox","M5","US-07-2","Merchant contribution opt-in and outbox with on-device filters","C4","flutter-core-engineer",["categorizer","db_c"],
  "app/lib/features/categorization/application/contributions.dart",
  "Opt-in anonymous contributions that can't leak personal data.",
  "Off by default; queue {merchantNorm, institutionCode, categoryCode} when user categorizes an unknown merchant; BR-SYNC-04 filters on device; opt-out deletes queue (EC-48).",
  ["Payload contains no amount/date/card/phone/IPA/person name","Opt-out deletes queued rows"],["Unit tests","Privacy contract test"],"A","FR-CAT-09, BR-SYNC-04")
T("app_sync","M5","US-13-1","Daily sync orchestrator: throttle, back-off, atomic apply, re-categorize","C3","flutter-core-engineer",["be_client","categorizer","contrib_outbox","prices_app","flags"],
  "app/lib/features/catalog_sync/",
  "Catalog, flags, prices and entitlement stay fresh without blocking the UI.",
  "On foreground: server-time 24 h throttle (EC-43); back-off ≤ 1/h after failure; verify; apply catalog ops/flags/prices/entitlement in one DB transaction; full snapshot download path; outbox upload; re-categorize only catalog/none-sourced non-verified rows (FR-SYNC-05); About status line.",
  ["10 opens/day → ≤ 1 successful sync","Kill mid-apply → previous catalog intact","User rule never overridden"],["Use-case tests","Integration test against local backend"],"A","FR-SYNC-*, ADR-013, BR-SYNC-01/02, NFR-REL-03", model="opus")

# ───────────────────────── M5 Gold app ─────────────────────────
T("gating","M4","US-14-1","Gold gate matrix and entitlement state (local)","C2","flutter-core-engineer",["flags","settings_repo"],
  "app/lib/features/gold/application/gating.dart",
  "One place that decides what Free and Gold can do.",
  "Gate matrix from SRS §5.2 (charts, voice limit, assets, custom categories/templates, export/import, backup history); EntitlementState provider (Free by default; debug override for dev builds only); downgrade read-only rules (BR-GOLD-04); paywall trigger hook.",
  ["Every Gold-only capability is checked through the matrix","Downgrade keeps Gold-created data readable but not creatable"],["Unit tests"],"A","§5.2, BR-GOLD-04")
T("entitlement","M5","US-14-1","Entitlement token verification, offline cache and grace","C4","flutter-core-engineer",["gating","be_client"],
  "app/lib/features/gold/application/entitlement.dart",
  "Gold works offline and can't be faked by editing files.",
  "Verify ES256 entitlement token with embedded keys; cache in secure_state; grant while now < graceUntil (A-38 7 d); lifetime rolling refresh; 'pending verification' state; feeds EntitlementState.",
  ["Airplane mode for 5 days keeps Gold","An edited token falls back to Free"],["Unit tests with signed vectors"],"A","FR-GOLD-04, NFR-SEC-05")
T("iap","M5","US-14-1","In-app purchase flow, backend verify, background retry and restore","C4","flutter-core-engineer",["entitlement","be_client"],
  "app/lib/features/gold/application/purchase.dart",
  "Buy and restore Gold safely on both stores.",
  "in_app_purchase 3.3+ (PBL 8, pending purchases enabled); obfuscatedAccountId/appAccountToken = HMAC(installId); verify call; outbox + WorkManager/BGTask retries until verified (BR-GOLD-06); restore → /v1/purchases/restore; complete purchases only after verify.",
  ["Backend down at purchase → Gold after it returns, within Google's 3-day window","Pending (cash) purchase shows pending, no Gold"],["Store sandbox tests","Unit tests with fake store"],"A","FR-GOLD-02/03, BR-GOLD-05/06")
T("paywall_ui","M5","US-14-1","Paywall S-68, locked previews and upgrade prompt cap","C2","flutter-ui-engineer",["iap","arb2"],
  "app/lib/features/gold/presentation/",
  "Explain and sell Gold without nagging.",
  "Mockup 18 with store-localized prices; restore; terms/privacy; max one unsolicited prompt per week (A-22); pending state.",
  ["Matches mockup 18","Prices come from the store"],["Golden tests"],"G","S-68, FR-GOLD-01/05")
T("account_ui","M5","US-15-1","Optional sign-in, account screen S-69, sign-out and delete account","C4","flutter-core-engineer",["be_client","entitlement"],
  "app/lib/features/account/",
  "Carry Gold across platforms, then leave cleanly.",
  "google_sign_in; sign_in_with_apple (iOS native, Android web flow with backend callback); nonce; /v1/accounts/signin; 409 confirm (EC-46); sign-out keeps local data; delete account; S-69 UI.",
  ["Sign-in never required for any non-Gold feature","Delete account removes backend links"],["Integration tests with backend","Widget tests"],"A","FR-ACCT-*, D-44")

# ───────────────────────── M6 Backup ─────────────────────────
T("bk_crypto","M6","US-16-1","Backup file format: Argon2id-wrapped key and chunked AES-256-GCM","C4","flutter-core-engineer",["keys"],
  "app/lib/features/backup/crypto/",
  "Tamper-evident encrypted backup stream.",
  "Header CBOR (magic, versions, kdf params, wrapped K_bk); Argon2id m=64MiB t=3 p=1; chunk nonces with counter; AAD = header ‖ index ‖ isLast; streaming encrypt/decrypt; passphrase change re-wraps.",
  ["Truncated/reordered/swapped chunks fail","Wrong passphrase fails at unwrap with clear error"],["Test vectors","Fuzz tests"],"A","ADR-011, security-model §5")
T("bk_snapshot","M6","US-16-1","Backup snapshot and restore swap with schema checks","C4","flutter-core-engineer",["bk_crypto","db_a","db_b","db_c","settings_repo"],
  "app/lib/features/backup/application/",
  "Everything in FR-BAK-06, nothing in FR-BAK-07.",
  "SQLite backup API into temp DB keyed with K_snap; settings manifest; restore: verify, decrypt, open, copy into new DB under fresh K_db, atomic swap; refuse newer schema (EC-26); migrate older; re-grant capture prompt; catalog re-sync.",
  ["Checklist test: every FR-BAK-06 item identical after restore","No unencrypted temp file at any point"],["Integration test backup→restore","Privacy scan during backup"],"A","FR-BAK-03/06/07")
T("bk_drive","M6","US-16-1","Google Drive appDataFolder backend","C4","flutter-core-engineer",["bk_snapshot"],
  "app/lib/features/backup/data/drive_store.dart",
  "Backups in the user's hidden Drive folder.",
  "google_sign_in drive.appdata scope; upload to temp name then rename; list/download/delete; quota/network errors; cross-platform restore.",
  ["Android backup restores on iPhone via Drive","Partial upload never replaces the previous backup"],["Integration tests (test account)"],"A","FR-BAK-01/03, D-11")
T("bk_icloud","M6","US-16-1","iCloud backup host (native) and Dart adapter","C4","native-platform-engineer",["bk_snapshot","pigeon"],
  "ios/Runner/ICloud/, ICloudBackupHostApi, Dart adapter",
  "Backups in the user's iCloud container.",
  "Ubiquity container Documents/Backups; availability check; upload/list/download/delete with coordination; error codes.",
  ["iCloud off → clear error and Drive offer"],["XCTest + device test"],"E","FR-BAK-01")
T("bk_schedule","M6","US-16-1","Backup schedules, slots and reminders (Free 1 slot, Gold 5 versions)","C3","flutter-core-engineer",["bk_drive","bk_icloud","gating","notif"],
  "app/lib/features/backup/application/schedule.dart",
  "Automatic backups for Gold; one manual slot for Free.",
  "WorkManager/BGProcessingTask schedules daily/weekly/monthly; Free overwrite single slot; Gold keep 5; upgrade keeps free backup as first version, downgrade keeps newest (FR-BAK-09); 30-day reminder (A-67); failure notification; cancel on delete-everything (EC-29).",
  ["Free backup twice → one file","Gold keeps last 5"],["Use-case tests"],"A","FR-BAK-02/04/05/08/09")
T("bk_ui","M6","US-16-1","Backup & restore screens S-66 and S-04","C2","flutter-ui-engineer",["bk_schedule","arb2"],
  "app/lib/features/backup/presentation/",
  "Set up, run and restore backups.",
  "Passphrase setup with strength and unrecoverable warning (EC-27); provider choice; last backup status; restore flow from welcome with all error states (newer version, wrong passphrase, corrupt, none found); counting mascot.",
  ["All S-04 states implemented"],["Golden + widget tests"],"G","S-04, S-66")

# ───────────────────────── M6 Import/export/OCR ─────────────────────────
T("export","M6","US-17-1","CSV and Excel export with preview for Free","C2","flutter-core-engineer",["txn_repo","gating"],
  "app/lib/features/export_import/application/export.dart",
  "Exports that open correctly in Excel.",
  "CSV UTF-8 BOM, ISO 8601, '.' decimals, currency per row; XLSX; date/category/card filters; Free preview table only; unencrypted warning; user-chosen location.",
  ["Arabic opens correctly in Excel on Windows","Amounts never converted"],["Unit tests","Manual Excel check"],"A","FR-EXP-01/02/05/07, BR-EXP-01")
T("import_csv","M6","US-17-1","Zaghlol CSV import with duplicate detection","C3","flutter-core-engineer",["ingest","export"],
  "app/lib/features/export_import/application/import_csv.dart",
  "Re-import or restore from Zaghlol CSV.",
  "Parse own format; map to transactions via ingest-like path; dedupe with existing; summary counts.",
  ["Re-importing an export creates no duplicates"],["Use-case tests"],"A","FR-EXP-03")
T("import_pdf","M6","US-17-1","Bank PDF statement import (CIB, NBE, QNB, Banque Misr)","C3","parsing-engine-engineer",["pipeline","samples"],
  "packages/zaghlol_parsing/lib/statements/pdf/, pdfrx adapter",
  "Gold users import past months from PDF.",
  "pdfrx text extraction; per-bank statement row templates; password-protected PDFs (local only); card mapping; ignored-card skip default (BR-CAP-03).",
  ["Sample statements parse to expected rows","Password prompt works"],["Fixture tests from synthetic statements"],"F","FR-EXP-04, OOS-12", blocked="Needs sample statements (OQ-04)")
T("import_online","M6","US-17-1","Online-bank statement import (Wise, Revolut, Monzo, bunq, N26)","C3","parsing-engine-engineer",["import_csv","tpl_online"],
  "packages/zaghlol_parsing/lib/statements/online/",
  "Multi-currency CSV (and PDF where no CSV) imports.",
  "Per-bank CSV column mappings; multi-currency rows kept native; dedupe against captured notifications (BR-ING-02); conversions as internal transfers.",
  ["Wise multi-currency CSV imports with per-currency counts","Already-captured payments skipped"],["Fixture tests"],"F","FR-EXP-06", blocked="Needs sample statements (OQ-04)")
T("import_ui","M6","US-17-1","Import flow S-67 (source, summary, done)","C2","flutter-ui-engineer",["import_pdf","import_online","import_csv","gating"],
  "app/lib/features/export_import/presentation/",
  "Import flow per flows 07 §D.",
  "Source list (mockup 32) with how-to links; summary sheet (mockup 33) with skipped counts and target card; done screen (mockup 34) with review link; Free → paywall; export screen.",
  ["Matches mockups 32–34"],["Golden tests"],"G","S-67")
T("ocr_android","M6","US-17-2","Android OCR host (ML Kit Latin + Tesseract Arabic)","C3","native-platform-engineer",["spk_ocr","pigeon"],
  "android/.../ocr/",
  "On-device OCR for Arabic and English.",
  "OcrHostApi; bundled ara fast model; merge lines by bounding box; decrypt image in memory; delete temp in finally.",
  ["SPK-02 accuracy reproduced","No image persisted"],["Instrumented tests"],"D","ADR-009, D-40")
T("ocr_ios","M6","US-17-2","iOS OCR host (Vision)","C3","native-platform-engineer",["spk_ocr","pigeon"],
  "ios/Runner/OCR/",
  "On-device OCR on iPhone.",
  "VNRecognizeTextRequest accurate; runtime language support; same result shape.",
  ["Arabic used only when supported"],["XCTest"],"E","ADR-009")
T("ocr_flow","M6","US-17-2","Receipt/screen OCR templates and confirmation screen S-32","C2","parsing-engine-engineer",["ocr_android","ocr_ios","pipeline"],
  "packages/zaghlol_parsing institutions screen templates, app S-32",
  "Screenshot → parsed transaction with confirmation.",
  "OCR-channel templates (InstaPay receipt, wallet receipts, online-bank app screens); confirmation UI with editable fields; ocr source.",
  ["InstaPay receipt yields amount/IPA/reference/date"],["Fixture tests on OCR text","Widget test"],"F","FR-ING-I-04/08, S-32")

# ───────────────────────── M6 Settings & security ─────────────────────────
T("settings_ui","M6","US-18-1","Settings S-60 incl. privacy info and About","C2","flutter-ui-engineer",["settings_repo","arb2","approx"],
  "app/lib/features/settings/presentation/",
  "Every preference within 2 taps.",
  "Mockup 16 structure; language/digits/payday/income/primary currency/≈ toggle & target; notifications & quiet hours; contribution opt-in; 'what Zaghlol's server knows' generated from allow-list; About (versions, sync status, diag share); delete everything entry.",
  ["All FR-ONB-07 items reachable in ≤ 2 taps"],["Widget + golden tests"],"G","S-60, FR-ONB-07, S-70, S-71, S-72")
T("categories_ui","M6","US-18-1","Categories & rules S-63/S-64 incl. custom categories (Gold)","C2","flutter-ui-engineer",["rules_repo","gating"],
  "app/lib/features/categorization/presentation/",
  "Manage rules and custom categories.",
  "Rules list edit/delete; custom categories/subcategories CRUD (Gold) with replacement on delete; downgrade read-only.",
  ["Deleting a category requires a replacement"],["Widget tests"],"G","S-63, S-64, FR-CAT-07/08")
T("custom_tpl","M6","US-05-3","Custom message template builder engine and screen S-65 (Gold)","C3","parsing-engine-engineer",["pipeline","gating"],
  "packages/zaghlol_parsing/lib/custom/, app S-65",
  "Gold users teach Zaghlol a format.",
  "Highlight amount/merchant/last4/date; generate template; test on sample + sender history with match counts; save to custom_templates; guard config update.",
  ["Generated template parses the sample and similar messages"],["Unit tests","Widget test"],"F","FR-PAR-07")
T("applock","M3","US-18-2","App lock, privacy overlay and screenshot hiding","C3","native-platform-engineer",["pigeon","settings_repo"],
  "DeviceSecurityHostApi, app/lib/features/security/",
  "Biometric/passcode lock and hidden app switcher.",
  "local_auth; timeout 60 s (A-10); FLAG_SECURE + setRecentsScreenshotEnabled(false) when on; iOS overlay on resign active; root/jailbreak heuristic warning (FR-SEC-07).",
  ["App switcher shows blank when lock on","Biometric fail falls back to device passcode"],["Device tests"],"D","FR-SEC-02/07, S-05")
T("os_backup_excl","M6","US-18-2","Exclude app data from OS backups and device transfer","C4","native-platform-engineer",["repo"],
  "Android manifest + data_extraction_rules.xml, iOS file attributes",
  "Only Zaghlol's own encrypted backup moves data between phones.",
  "allowBackup=false, dataExtractionRules exclude all (cloud + device transfer); iOS isExcludedFromBackup on DB/spool/temp dirs; verification script.",
  ["adb backup / device transfer yields no app data","iCloud device backup excludes DB"],["Device verification test"],"D","FR-SEC-05")
T("delete_all","M6","US-18-2","Delete everything (local wipe + backend install delete)","C4","flutter-core-engineer",["keys","be_client","bk_schedule"],
  "app/lib/features/security/application/delete_everything.dart",
  "Return to first-launch state with nothing left behind.",
  "Confirm; cancel jobs; close DB; delete DB, spool, temp, widget snapshot; delete Keystore/Keychain items; DELETE /v1/installs/me best effort; restart.",
  ["Sandbox scan after wipe finds no app data","Works offline"],["Integration test + privacy scan"],"A","FR-ONB-08, EC-29")

# ───────────────────────── M7 Flagged features ─────────────────────────
T("zakah_engine","M7","US-19-1","Zakah engine (hawl, nisab, native-unit dues)","C4","flutter-core-engineer",["wealth_domain"],
  "packages/zaghlol_domain/lib/zakah/",
  "Correct Zakah estimates per asset lot.",
  "Umm al-Qura Hijri table; lots from acquisition; nisab 85 g 24K; 21K 87.5% purity; 2.5% per eligible lot in native unit + EGP cost; short-term debts; ledger statuses.",
  ["Spec §11 table reproduced exactly"],["Unit tests with spec cases"],"A","FR-ZAK-01…04, BR-ZAK-*")
T("zakah_ui","M7","US-19-1","Zakah screen S-46 behind flag with disclaimer","C2","flutter-ui-engineer",["zakah_engine","flags","arb2"],
  "app/lib/features/zakah/presentation/",
  "Hidden unless the flag is on.",
  "Per-asset table, payment status, disclaimer always visible; hidden when flag off; data kept (EC-49).",
  ["Flag off → no entry point anywhere"],["Widget tests"],"G","S-46, FR-ZAK-05/06")
T("roi_engine","M7","US-19-2","Smart ROI general-advice rules with no-names check","C3","flutter-core-engineer",["chart_q"],
  "packages/zaghlol_domain/lib/roi/",
  "8 rules with 1- and 2-year projections using product kinds only.",
  "Rules from spec §12; example rates table (catalog-updatable); CI test that no output contains registry institution names or product names (D-38).",
  ["Spec numbers as test cases","No institution/product names in any suggestion"],["Unit tests + name check"],"A","FR-ROI-01/05")
T("roi_ui","M7","US-19-2","Smart ROI screen S-51 behind flag","C2","flutter-ui-engineer",["roi_engine","flags","arb2"],
  "app/lib/features/roi/presentation/",
  "Tips with 'not financial advice' disclaimer.",
  "Suggestion cards, projection chart, disclaimer on each, share projection card (C).",
  ["Hidden when flag off","Disclaimer on every suggestion"],["Widget tests"],"G","S-51, FR-ROI-02/03/04")

# ───────────────────────── M7 Quality & release ─────────────────────────
T("privacy_tests","M7","US-21-1","Privacy verification suite (sandbox scan, data-boundary proxy, ignore no-trace)","C4","test-engineer",["delete_all","app_sync","ignore_domain","bk_snapshot","os_backup_excl"],
  "tools/privacy_scan/, app/integration_test/privacy/",
  "Proof that the privacy promises hold for every release.",
  "Scripted session; scan sandbox for plaintext amounts/digits/merchants/message text; recording client asserts every request ⊆ BR-SYNC-03 schema; ignored-card SMS leaves no trace; OS backup exclusion check.",
  ["All four checks green on release candidate"],["The suite itself, run in CI on main"],"A","testing-strategy §1/§6, NFR-PRIV-01/02/03", model="opus")
T("e2e","M7","US-21-1","Device end-to-end suites (Android killed-app capture, iOS intents, backup, purchases)","C3","test-engineer",["onb_android","onb_ios","bk_ui","iap"],
  "app/integration_test/",
  "Critical journeys automated on devices.",
  "Android: adb SMS with app killed → Home < 10 s; notification capture; scan 10k < 60 s. iOS: intent → visible on open. Backup Android→iOS restore. Sandbox purchase/restore.",
  ["Suites pass on reference devices"],["—"],"A","testing-strategy §1")
T("perf","M7","US-21-1","Performance benchmarks and CI budgets","C2","test-engineer",["pipeline","txn_repo","chart_q","scan"],
  "benchmarks/, CI job",
  "NFR-PERF budgets enforced.",
  "parse/scan/search/chart benchmarks; cold start measurement on reference devices; battery 24 h check; regression > 10% fails.",
  ["All NFR-PERF targets met on reference devices"],["Benchmarks"],"A","NFR-PERF-01…06")
T("a11y","M7","US-21-1","Accessibility and golden coverage pass (130% text, both themes, screen readers)","C2","test-engineer",["home_ui","txn_list_ui","settings_ui","charts_free"],
  "app/test/goldens, a11y tests",
  "WCAG AA and full RTL/LTR coverage.",
  "Semantics guidelines tests; text scale 1.3 goldens for every screen; TalkBack/VoiceOver labels AR/EN audit.",
  ["No guideline violations","All screens have 1.3× goldens"],["Automated + manual audit"],"G","NFR-UX-02")
T("security_review","M7","US-21-1","Security assessment: MobSF, ZAP, dependency scans, pen test","C4","security-privacy-reviewer",["privacy_tests","be_infra"],
  "docs/05-reviews/security-assessment.md",
  "MASVS L2 / ASVS L2 evidence before launch.",
  "Static scans, staging DAST, dependency/SCA review, manual pen test findings tracked to closure.",
  ["No open high/critical findings"],["Assessment report"],"A","NFR-SEC-*, A-51")
T("release_android","M7","US-21-1","Android release pipeline, Play listings, Data safety and SMS declaration package","C3","flutter-core-engineer",["e2e","privacy_tests"],
  ".github/workflows/release-android.yml, store docs",
  "Ship prodSms and keep prodNoSms ready.",
  "Signed AABs for both flavors; symbols upload; internal → closed → staged rollout; Data safety form from security-model §2; SMS permission declaration with demo video script; target API 36 check.",
  ["Both AABs pass Play pre-launch report","Declaration package ready"],["Release dry run"],"A","ADR-004, deployment §2, NFR-LEGAL-01, NFR-PRIV-05")
T("release_ios","M7","US-21-1","iOS release pipeline, privacy labels and App Review notes","C3","flutter-core-engineer",["e2e","privacy_tests"],
  ".github/workflows/release-ios.yml, store docs",
  "Ship to TestFlight and the App Store.",
  "fastlane/match; App Store Connect API key; privacy nutrition labels (no tracking); review notes explaining Shortcuts automations & Sign in with Apple; account deletion path.",
  ["TestFlight build installs","Privacy labels match data boundary"],["Release dry run"],"A","deployment §2, NFR-LEGAL-02, NFR-PRIV-05")
