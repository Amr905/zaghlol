# docs/03-technical — Technical Specification (Phase 3)

| | |
|---|---|
| Version | 1.0 — **APPROVED 2026-11-03** (CR-03/OQ-16 open) |
| Author | solution-architect (Lead session) |
| Date | 2026-11-03 |
| Based on | SRS v1.2 (approved), Phase 2 design (approved 2026-11-03, incl. D-35) |

## How the spec is organised

| # | Topic asked for | Where |
|---|---|---|
| 1 | System architecture | [`architecture.md`](architecture.md) §1–4, §8 · [`project-structure.md`](project-structure.md) |
| 2 | Component responsibilities | [`architecture.md`](architecture.md) §4.2 (app modules), §5 (backend modules) · [`parsing-engine.md`](parsing-engine.md) · [`domain-algorithms.md`](domain-algorithms.md) |
| 3 | Database schema & relationships | [`database-schema.md`](database-schema.md) (on-device, Drift) · [`backend-schema.md`](backend-schema.md) (PostgreSQL) |
| 4 | API endpoints & contracts | [`backend-api.md`](backend-api.md) (public + admin API) · [`platform-channels.md`](platform-channels.md) (Dart ↔ native) |
| 5 | Authentication & authorization | [`security-model.md`](security-model.md) §4 · [`backend-api.md`](backend-api.md) §3 |
| 6 | Integration points | [`architecture.md`](architecture.md) §6 |
| 7 | Error handling | [`error-handling-and-observability.md`](error-handling-and-observability.md) §1–2 |
| 8 | Logging & monitoring | [`error-handling-and-observability.md`](error-handling-and-observability.md) §3–5 |
| 9 | Security considerations | [`security-model.md`](security-model.md) |
| 10 | Deployment considerations | [`deployment.md`](deployment.md) |
| — | Testing strategy | [`testing-strategy.md`](testing-strategy.md) |
| — | Decisions & alternatives | [`adr/`](adr/) (22 ADRs, below) |

## Decision log (ADRs)

| ADR | Decision | Main alternative(s) rejected | Status |
|---|---|---|---|
| [001](adr/ADR-001-state-management.md) | Riverpod 3 for state + DI | Bloc, Provider + get_it | Proposed |
| [002](adr/ADR-002-local-db-encryption.md) | Drift + SQLite3MultipleCiphers (AES-256, SQLCipher scheme), key in Keystore/Keychain | sqflite_sqlcipher, Isar/ObjectBox | Proposed |
| [003](adr/ADR-003-parsing-engine.md) | Data-driven regex template registry + generic heuristics | Hand-coded parsers, on-device ML | Proposed |
| [004](adr/ADR-004-android-sms-policy.md) | Two Android flavors (`prodSms` / `prodNoSms`); notifications first-class | Single SMS build, no SMS at all | Proposed |
| [005](adr/ADR-005-capture-guard-and-spool.md) | Native Capture Guard + encrypted spool → Dart pipeline | Headless engine in receiver; native parser ports | Proposed |
| [006](adr/ADR-006-ios-ingestion-channels.md) | Shortcuts Message + Wallet App Intents, Share/OCR, statements; **drop the message filter extension (CR-01)** | Keep the filter extension | Proposed: **needs approval of CR-01** |
| [007](adr/ADR-007-inter-layer-contracts.md) | Pigeon channels + pure-Dart workspace packages | Hand-written MethodChannels | Proposed |
| [008](adr/ADR-008-chat-engine.md) | Rules/intent grammar chat (no LLM) | On-device classifier, LLM | Proposed |
| [009](adr/ADR-009-ocr.md) | iOS Vision; Android ML Kit Latin + Tesseract Arabic (CR-02) | ML Kit only, cloud OCR | Proposed |
| [010](adr/ADR-010-speech-recognition.md) | Platform speech recognizers, on-device first; online only with consent | Bundled ASR model | Proposed: **confirm OQ-06** |
| [011](adr/ADR-011-backup-format-kdf.md) | Random backup key wrapped by Argon2id(passphrase); chunked AES-256-GCM | Per-backup passphrase KDF, PBKDF2 | Proposed |
| [012](adr/ADR-012-purchase-verification-entitlements.md) | Backend store verification + ES256-signed entitlement, 7-day offline grace; *amended 2026-11-05:* Android restore `{productId, purchaseToken}` + Play v2 endpoints | Client-side receipts, online check each launch | Proposed |
| [013](adr/ADR-013-catalog-sync-protocol.md) | One signed daily `POST /v1/sync`; deltas; full snapshots on CDN; *amended 2026-11-05:* draft keys, tombstones, keyword key = keyword + lang | Separate calls, push | Proposed |
| [014](adr/ADR-014-price-data-source.md) | Pluggable price providers; local Egyptian gold feed preferred, spot-derived fallback | Scraping | Proposed: **pick provider (OQ-02)** |
| [015](adr/ADR-015-backend-hosting-region.md) | Provider-neutral; recommend EU region + PDPL licence/cross-border permit | Egypt-local host, Gulf region | Proposed: **decide region + start PDPL licence (CR-03, OQ-16)** |
| [016](adr/ADR-016-optional-sign-in.md) | Native Google/Apple sign-in, own account JWT; Apple on Android via web flow (CR-05); *amended 2026-11-05:* `form_post` callback | Firebase Auth | Proposed |
| [017](adr/ADR-017-localization.md) | Flutter gen-l10n, Arabic template locale, digits preference | easy_localization, slang | Proposed |
| [018](adr/ADR-018-transport-security-pinning.md) | No TLS pinning; ES256-signed responses (answers OQ-15) | Certificate pinning | Proposed |
| [019](adr/ADR-019-minimum-os-versions.md) | Android 8.0 (API 26) / target 36; iOS 17.0 (answers OQ-03, CR-04) | Android 10 / iOS 18 | Proposed |
| [020](adr/ADR-020-mascot-animation-runtime.md) | Rive state machine from the traced vector rig | Lottie, Flutter-native | Proposed |
| [021](adr/ADR-021-success-metrics-measurement.md) | Backend aggregate counters + store consoles + CI accuracy (answers OQ-01) | Telemetry | Proposed |
| [022](adr/ADR-022-backend-architecture.md) | .NET 10 modular monolith + PostgreSQL 17; *amended 2026-11-05:* open third-party bodies, no query logging, `backend/Dockerfile` | Microservices, serverless | Proposed |

## Change requests raised by this phase (need product-owner approval)

| ID | Change | Affects |
|---|---|---|
| CR-01 | Remove FR-ING-I-03 (iOS message filter extension): Apple blocks it from sharing data with the app or the network | SRS FR-ING-I-03, D-09, R-02 |
| CR-02 | Add Tesseract (Arabic OCR) on Android, about 1.5 MB | INT-06, R-06 |
| CR-03 | Obtain the Egypt PDPC licence, appoint a DPO, and (if hosted abroad) a cross-border permit before launch | NFR-PRIV-05, OQ-16 |
| CR-04 | Minimum OS: Android 8.0 / iOS 17.0 | NFR-COMP-01, OQ-03 |
| CR-05 | Offer Sign in with Apple on Android via Apple's web flow (one extra backend endpoint) | FR-ACCT-01 |

## Spikes planned for the start of Phase 5 (time-boxed, results recorded in the ADRs)

| ID | Question | ADR |
|---|---|---|
| SPK-01 | Android: receiver → spool → WorkManager → headless engine latency < 10 s on Samsung/Xiaomi with app killed | 005 |
| SPK-02 | OCR accuracy on 50 synthetic InstaPay/wallet receipts (Vision vs ML Kit + Tesseract) | 009 |
| SPK-03 | iOS: can an App Intent boot a headless Flutter engine to process immediately within limits? | 005, 006 |
| SPK-04 | On-device ar-EG speech availability across the device matrix | 010 |
| SPK-05 | SQLite3MultipleCiphers via `sqlite3` hooks + FTS5 trigram on both platforms; key bootstrap timing | 002 |

## Sources consulted
- Drift — Encryption (SQLite3MultipleCiphers recommended from drift 2.32): https://drift.simonbinder.eu/platforms/encryption
- Apple Developer Forums — Message Filter extension can't write to shared containers or access the network: https://developer.apple.com/forums/thread/97953
- Matthew Cassinelli — iOS 17 automations run immediately (notification required): https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications
- Foresight Mobile — Play Billing Library 8 deadlines; `in_app_purchase` 3.3 bundles PBL 8: https://foresightmobile.com/blog/google-play-billing-library-8-migration
- NuGet — Enjna.AppStoreServerLibrary (community, MIT): https://www.nuget.org/packages/Enjna.AppStoreServerLibrary
- CMS — Egypt PDPL Executive Regulations (Decision 816/2025), licences & cross-border transfers: https://cms.law/en/are/legal-updates/egypt-s-pdpl-executive-regulations-issued-one-year-compliance-countdown-begins
- The Stack — AWS Gulf regions offline after 2026 attacks; Saudi region Dec 2026: https://www.thestack.technology/while-its-other-persian-gulf-data-centers-remain-idle-aws-prepares-to-open-in-saudi-arabia/
- pub.dev — flutter_riverpod 3.x, rive 0.14.x changelogs; Flutter 3.41/3.44 release notes (2026)

## Approval

| Role | Name | Decision | Date |
|---|---|---|---|
| Product owner | amr905 | ☑ Architecture + ADRs approved · ☑ CR-01 (FinArt/Say iOS approach), CR-02, CR-04, CR-05 · ☑ OQ-02 local Egyptian gold-market feed · ☑ OQ-06 yes · ☐ **CR-03 / OQ-16 hosting region & PDPL licence — still open** | 2026-11-03 |

On approval, Phase 4 (task breakdown) may start.
