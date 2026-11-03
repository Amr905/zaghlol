# Project Structure & Naming

The repository is a mono-repo with a **Dart pub workspace** for the app and its pure-Dart packages, and a **.NET solution** for the backend.

```
/                                   repo root
├─ pubspec.yaml                     pub workspace root (workspace: app, packages/*); sqlite3 hook → sqlite3mc
├─ app/                             Flutter application
│  ├─ lib/
│  │  ├─ main.dart                  UI entrypoint
│  │  ├─ ingestion_main.dart        @pragma('vm:entry-point') headless entrypoint for background ingestion
│  │  ├─ core/
│  │  │  ├─ db/                     AppDatabase (Drift), tables/, daos/, migrations/, key_bootstrap.dart
│  │  │  ├─ crypto/                 aes_gcm.dart, argon2.dart, es256_verifier.dart
│  │  │  ├─ backend/                backend_client.dart, signed_response.dart, dto/
│  │  │  ├─ platform/               pigeon-generated APIs (capture_api.g.dart, ocr_api.g.dart, icloud_api.g.dart …)
│  │  │  ├─ flags/                  feature_flags.dart (defaults OFF)
│  │  │  ├─ l10n/                   app_ar.arb, app_en.arb (gen-l10n), digits.dart, money_format.dart
│  │  │  ├─ theme/                  tokens.dart (Mint Fresh / Jade Night), components/
│  │  │  ├─ routing/                router.dart
│  │  │  ├─ logging/                redacting_log.dart (local ring buffer)
│  │  │  └─ result/                 result.dart, failures.dart
│  │  └─ features/<feature>/
│  │     ├─ data/                   repositories, DAOs use, adapters
│  │     ├─ application/            use cases
│  │     └─ presentation/           screens/, widgets/, controllers (Riverpod notifiers)
│  ├─ test/                         mirrors lib/ (widget + golden tests: goldens/ar, goldens/en)
│  ├─ integration_test/             device flows (onboarding, capture→home, backup→restore, purchase sandbox)
│  ├─ assets/
│  │  ├─ registry/                  institutions/*.json (templates), senders.json, registry_manifest.json
│  │  ├─ catalog/                   catalog_seed.json.gz (+ signature)
│  │  ├─ rive/                      zaghlol.riv
│  │  ├─ mascot/                    static pose PNG/SVG fallbacks
│  │  └─ shortcuts/                 Zaghlol.shortcut (signed) + install guide images
│  ├─ android/
│  │  └─ app/src/main/kotlin/app/zaghlol/
│  │     ├─ capture/                SmsReceiver.kt, BankNotificationListener.kt, InboxReader.kt
│  │     ├─ guard/                  CaptureGuard.kt, GuardConfig.kt (shared rules, generated config reader)
│  │     ├─ spool/                  SpoolStore.kt (AES-GCM, Keystore key), IngestionWorker.kt (headless engine)
│  │     ├─ ocr/                    OcrHost.kt (ML Kit Latin + Tesseract ara)
│  │     ├─ widget/                 SafeSpendWidget.kt (Glance)
│  │     └─ PigeonHosts.kt
│  └─ ios/
│     ├─ Runner/
│     │  ├─ Capture/                LogBankMessageIntent.swift, LogWalletTransactionIntent.swift, ZaghlolShortcuts.swift
│     │  ├─ Guard/                  CaptureGuard.swift, GuardConfig.swift
│     │  ├─ Spool/                  SpoolStore.swift (Keychain key, App Group container)
│     │  ├─ OCR/                    VisionOcrHost.swift
│     │  └─ ICloud/                 ICloudBackupHost.swift
│     ├─ ShareExtension/            ShareViewController.swift → spool
│     └─ ZaghlolWidget/             SwiftUI WidgetKit
├─ packages/
│  ├─ zaghlol_domain/               pure Dart: money/, entities/, budget/, transfers/, recurring/, wealth/, zakah/, roi/, chat/, voice/, mascot_rules/
│  └─ zaghlol_parsing/              pure Dart: registry/, normalize/, extract/, classify/, merchant/, generic/, guard_rules/ (+ fixtures/)
├─ tools/
│  ├─ registry_lint/                validates institution JSON, runs fixtures, emits guard config schema
│  ├─ catalog_build/                builds catalog_seed from the backend export
│  └─ privacy_scan/                 sandbox plaintext scanner used in integration tests
├─ backend/
│  ├─ Zaghlol.sln
│  ├─ src/
│  │  ├─ Zaghlol.Api/               Program.cs, Endpoints/{Installs,Sync,Purchases,Accounts,Notifications,Admin}.cs
│  │  ├─ Zaghlol.Application/       handlers per module
│  │  ├─ Zaghlol.Domain/            entitlement rules, flag targeting, contribution filters
│  │  ├─ Zaghlol.Infrastructure/    EF Core DbContext + Migrations/, GooglePlay/, AppStore/, Kms/, Prices/
│  │  ├─ Zaghlol.Workers/           PriceFetcher, NotificationProcessor, EntitlementSweeper, RetentionPurger, ContributionAggregator
│  │  └─ Zaghlol.Ops/               `zaghlol-ops` CLI (operator, OIDC device flow)
│  ├─ tests/                        Zaghlol.*.Tests (xUnit + Testcontainers PostgreSQL)
│  ├─ openapi/zaghlol-v1.yaml       source of truth for the public API
│  └─ deploy/                       Dockerfile, IaC (OpenTofu), environment configs
├─ docs/                            (this documentation)
└─ .github/workflows/               app-ci.yml, backend-ci.yml, release-android.yml, release-ios.yml
```

## Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Dart files | `snake_case.dart` | `safe_to_spend.dart` |
| Dart types | `UpperCamelCase`; use cases are verbs | `IngestRawMessages`, `PairSelfTransfers` |
| Providers | `<thing>Provider` (generated) | `homeSummaryProvider` |
| Drift tables | plural snake_case in SQL, class `UpperCamel` | `transactions` / `Transactions` |
| IDs | ULID strings (sortable, generated on device) for user data; integers for catalog | `01JC…` |
| Money columns | `<name>_minor INTEGER` + `<name>_currency TEXT(3)` | `amount_minor`, `currency` |
| Times | UTC epoch milliseconds `INTEGER` + `tz_offset_min` when local time matters | `occurred_at`, `occurred_tz_offset_min` |
| Institution codes | lowercase ASCII slug, stable | `nbe`, `cib`, `instapay`, `vodafone_cash`, `wise` |
| Template IDs | `<institution>.<event>.<lang>.v<n>` | `nbe.card_purchase.ar.v2` |
| Copy keys (ARB) | `<feature>_<screen>_<element>` | `home_hero_safeToSpend` |
| Feature flags | snake_case | `zakah`, `smart_roi`, `roi_named_products` |
| Backend endpoints | `/v1/<resource>` kebab-case | `/v1/purchases/verify` |
| C# | .NET conventions; one endpoint group per module | `SyncEndpoints.MapSync()` |
| Error codes | `UPPER_SNAKE` stable strings | `PURCHASE_TOKEN_INVALID` |
| Branches / commits | `feature/T-123-short-name`, Conventional Commits | `feat(parsing): add QNB templates` |
