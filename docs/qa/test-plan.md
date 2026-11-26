# Test plan

Independent QA audit of Zaghlol. Target: `Amr905/zaghlol`, `main` @ `bc5b9d1d`. Date: 19 Nov 2026.

## 1. Objective

Show, with executed tests, how far the implementation matches the approved requirements (`docs/01-requirements/requirements.md`, 312 requirement IDs), the design (`docs/02-design`, 46 screens) and the technical specification (`docs/03-technical`, OpenAPI contract). Status reports from the development agents are treated as claims, not evidence.

## 2. Rules for this audit

- No application code is changed. The only edit was a test-harness shim in a scratch clone (see `test-results.md` §2).
- A result is PASS only if the test was executed in this audit.
- Findings are split into verified bugs, risks and untested areas.
- Missing or contradictory requirements are recorded as ambiguities, not invented.

## 3. What is under test

| Part | Technology | Size |
|---|---|---|
| Mobile app | Flutter 3.47.9, Riverpod, Drift + SQLite3MultipleCiphers, Kotlin and Swift hosts | 498 Dart files in `app/lib`, about 128,000 lines |
| Pure-Dart packages | `zaghlol_domain`, `zaghlol_parsing`, `zaghlol_catalog` | |
| Backend | .NET 10 ASP.NET Core, PostgreSQL 17 | about 63,000 lines of C#, 6 projects |
| Existing tests | 428 Dart test files, 233 C# test files | |

## 4. Environment

| Item | Value |
|---|---|
| Host | Linux x86-64 VM on the product owner's PC: 2 CPU, 3 GB RAM, no Docker, no Android SDK, no macOS |
| Toolchains installed for the audit | Flutter 3.47.9 / Dart 3.13.7 (the version CI pins), .NET SDK 10.0.404, PostgreSQL 17.12 binaries, zig as C compiler |
| Backend under test | `Zaghlol.Api` Release build, `ASPNETCORE_ENVIRONMENT=Development`, `Dev:FakeStores=true`, local KMS with throwaway keys, fresh database with `bootstrap-roles.sql` and all migrations |
| Start command documented by the project | `docker compose -f docker-compose.phone-test.yml up` (could not be used: no Docker). Equivalent script: `docs/qa/tools/run_backend_local.sh` |
| External services | Google Play, App Store, Google / Apple sign-in, Drive, iCloud, gold price feed: none available |

## 5. Test levels and approach

| Level | Approach | Tooling | Planned | Done |
|---|---|---|---|---|
| Static checks | Format, analyzer, project lints, warnings-as-errors build, vulnerable packages | `dart format`, `flutter analyze`, `zaghlol_lints`, `dotnet build`, `dotnet list package` | yes | yes |
| Unit and widget (app) | Run the existing suites unchanged | `flutter test` | yes | yes, except benchmark-tagged tests |
| Golden (app UI in ar/en, light/dark) | Run the existing golden suites | `flutter test --tags golden` | yes | yes |
| Unit (packages, tools) | Run unchanged | `dart test` | yes | yes |
| Backend unit and integration | Run unchanged against a real PostgreSQL 17 | `dotnet test` + local-cluster shim | yes | yes |
| API black box | New tests against the running backend: valid, invalid, missing field, unauthorized, boundary, unexpected input | Python `requests` | yes | yes (101 + 30 cases) |
| Database | New tests: persistence, constraints, relationships, role privileges, duplicate and invalid rows | Python `psycopg` | yes | yes (20 cases) |
| Security | Authentication and authorization probes, forged tokens, closed schemas, secrets scan, manifest review, production-guard start-up checks | scripts + inspection | yes | partly: no dynamic scan (MobSF, ZAP), no penetration test |
| UI on a device | Navigation, forms, validation messages, loading / empty / error states, RTL and LTR, text scaling | Android emulator on the PC, driven by screen control | yes | partly: 36 click-only checks (second session); typing and scrolling blocked |
| End-to-end journeys | the journeys in `docs/02-design/01-user-journeys.md` | emulator, dev backend | yes | E2E-01 and E2E-10 done; the rest blocked |
| Regression | Full existing suite as the baseline | as above | yes | yes for host-level suites |
| Performance | NFR-PERF targets | reference phone | no | not run |

## 6. Entry and exit criteria

- **Entry:** code builds; documented start commands identified. Met.
- **Exit for a PASS on a requirement:** executed evidence at the level stated in `requirements-coverage.md`.
- **Exit for release recommendation:** no open CRITICAL or HIGH bug, every "Must" requirement PASS, device journeys run. Not met (see `release-readiness.md`).

## 7. Journeys planned for the emulator

Status after the second session: E2E-01 done (PASS). E2E-10 done (PASS). E2E-04 validation only. All others blocked: they need typing, swiping, a Google account or a dev backend.

| # | Journey | Requirements |
|---|---|---|
| E2E-01 | First launch → welcome → skip set-up → empty Home, Arabic RTL, light theme | FR-ONB-01…03, 11 |
| E2E-02 | Grant SMS → inject bank SMS with `adb emu sms send` → transaction on Home, categorised | FR-ING-A-01, FR-ONB-06, FR-CAT-03 |
| E2E-03 | Killed app → SMS → transaction within 10 s | FR-ING-A-01, NFR-REL-01 |
| E2E-04 | Manual add, edit, delete, bulk edit with undo | FR-TXN-02, FR-TXN-06 |
| E2E-05 | Budget with payday 25, alert at 80 %, safe-to-spend figure | FR-BUD-01…04 |
| E2E-06 | Self-transfer pairing and reimbursement assignment | FR-XFR-01, FR-XFR-06 |
| E2E-07 | Ignore a card, send its SMS, confirm nothing stored | FR-CAP-01, FR-CAP-02 |
| E2E-08 | Dev backend: sync, `grant-gold`, Gold unlocks; airplane mode keeps Gold | FR-GOLD-04, FR-SYNC-01 |
| E2E-09 | Export CSV as Gold; preview only as Free | FR-EXP-01, FR-EXP-02 |
| E2E-10 | Switch language and digits; every tab in English LTR | FR-L10N-01, FR-L10N-03 |
| E2E-11 | App lock, app-switcher snapshot hidden | FR-SEC-02, NFR-SEC-04 |
| E2E-12 | Delete everything → first-launch state | FR-ONB-08 |

To unblock: start an emulator (API 34), install a `devSms` debug APK built with `ZAGHLOL_API_BASE=http://10.0.2.2:8080` and the dev keys, and start the dev backend. The APK that `app-ci` uploads as an artifact can be used.

## 8. Deliverables

`implementation-audit.md`, `test-plan.md`, `test-results.md`, `requirements-coverage.md`, `bug-report.md`, `release-readiness.md`, plus `tools/` (scripts, raw results, shim patch) and `evidence/` (logs, per-test results).
