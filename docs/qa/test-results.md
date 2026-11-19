# Test results

Target: `Amr905/zaghlol`, `main` @ `bc5b9d1d`. Run on 19 Nov 2026 in a Linux x86-64 VM (2 CPU, 3 GB RAM) with Flutter 3.47.9 / Dart 3.13.7, .NET SDK 10.0.404 and PostgreSQL 17.12.

## 1. Totals

| Group | Executed | Passed | Failed | Skipped | Not run |
|---|---|---|---|---|---|
| Existing automated suites (app, packages, tools, backend) | 10,547 | 10,547 | 0 | 39 | see §4 |
| New black-box API and database cases written for this audit | 151 | 130 | 10 | 0 | 1 blocked, 10 withdrawn |
| Extra live checks (rate limit, flag toggle, shutdown, production guards) | 5 | 4 | 1 | 0 | |
| On-device UI and end-to-end journeys | 0 | 0 | 0 | 0 | all (blocked) |

"Withdrawn" means my expectation was wrong or my own earlier case caused the result; each one is listed in `bug-report.md` under "Not bugs".

## 2. Existing suites

Raw per-test results: `docs/qa/evidence/tests_all.json` (10,586 rows) and the `.trx` files.

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| `packages/zaghlol_domain` | `dart test` | 426 | 0 | 0 |
| `packages/zaghlol_parsing` | `dart test --exclude-tags benchmark` | 1,591 | 0 | 0 |
| `packages/zaghlol_catalog` | `dart test` | 38 | 0 | 0 |
| `tools/lints` | `dart test` | 34 | 0 | 0 |
| `tools/registry_lint` | `dart test` | 8 | 0 | 0 |
| `tools/catalog_build` | `dart test` | 65 | 0 | 0 |
| `app` unit and widget | `flutter test --exclude-tags golden,benchmark` (7 chunks) | 4,845 | 0 | 35 |
| `app` golden | `flutter test --tags golden` (39 files, 2 chunks) | 477 | 0 | 0 |
| `Zaghlol.Application.Tests` | `dotnet test` | 1,057 | 0 | 0 |
| `Zaghlol.Infrastructure.Tests` | `dotnet test` (real PostgreSQL 17) | 1,162 | 0 | 3 |
| `Zaghlol.Api.Tests` | `dotnet test` (real PostgreSQL 17) | 644 | 0 | 1 |
| `Zaghlol.Contract.Tests` | `dotnet test` (real PostgreSQL 17) | 167 | 0 | 0 |
| `Zaghlol.Ops.Tests` | `dotnet test` | 3 | 0 | 0 |
| `Zaghlol.Workers.Tests` | `dotnet test` | 30 | 0 | 0 |
| **Total** | | **10,547** | **0** | **39** |

Skipped: 34 design-screenshot tests (run only with `DESIGN_SHOTS`), 1 sqlcipher CLI interop test, 4 backend tests that need live store credentials or recorded store vectors.

Static checks:

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed .` | PASS (1,126 files, 0 changed) |
| `flutter analyze` | **FAIL**: 1 warning, exit 1 (BUG-007) |
| `zaghlol_lints` (no double for money, no UI string literals, no print) | PASS (563 files, 0 issues) |
| `dotnet build Zaghlol.sln -c Release -warnaserror` | PASS (0 warnings) |
| `dotnet list package --vulnerable --include-transitive` | PASS (none reported) |
| `dotnet format --verify-no-changes` | PASS for repository files (the only finding was in my test shim) |

### Deviations from the project's own way of running tests

1. **Backend database tests.** They start PostgreSQL through Testcontainers (Docker). The VM has no Docker, so I replaced the container start in `backend/tests/Shared/ZaghlolTestDatabase.cs` with a throwaway local PostgreSQL 17 cluster per fixture (trust authentication). Patch: `docs/qa/tools/local-postgres-test-shim.patch`. It was applied only to my scratch clone. Role bootstrap, migrations and the least-privilege logins ran unchanged.
2. **C compiler.** The `pdfium_dart` build hook needs clang. I supplied `zig cc` under the names `clang`, `ar` and `ld.lld`.
3. **Chunks.** Each command had a 3-minute limit, so app tests ran directory by directory.

## 3. New tests written for this audit

Scripts and raw results are in `docs/qa/tools/`: `api_blackbox.py` → `api_blackbox_results.json`, `api_db_followup.py` → `api_db_followup_results.json`. The backend ran in `Development` with `Dev:FakeStores=true`, started by `run_backend_local.sh` on a fresh database.

### 3.1 API (valid, invalid, missing fields, unauthorized, boundary, unexpected input)

| Area | Cases | Pass | Fail | Withdrawn | Blocked | Notes |
|---|---|---|---|---|---|---|
| Health | 1 | 1 | 0 | 0 | 0 | |
| Install registration, idempotent retry, token rotation | 22 | 20 | 2 | 0 | 0 | API-014, API-015 → BUG-004 |
| Sync: authentication | 4 | 4 | 0 | 0 | 0 | wrong token, another install's token, unknown install: all 401 |
| Sync: validation, closed schema | 14 | 12 | 2 | 0 | 0 | API-048, API-049 → BUG-005. `balance`, `transactions`, an `amount` in a contribution and a message body in a bank request are all rejected with `400 UNKNOWN_FIELD` |
| Sync: first call, throttle, signature | 9 | 6 | 0 | 3 | 0 | API-063…065 withdrawn. Throttled body is 117 bytes |
| Sync retests on fresh installs: headers, contributions, flags, signature | 14 | 11 | 1 | 1 | 1 | F-04 → BUG-005; F-12 withdrawn; F-07 blocked (no published catalog). Signature verifies with the published key and fails on a changed body. Phone numbers and IPA were never stored |
| Entitlement, purchases, seats | 25 | 23 | 2 | 0 | 0 | API-083, F-23 → BUG-005. Forged token → `422`, no Gold. Fake-store purchase → signed `monthly` token, one seat; another install gets nothing |
| Accounts | 11 | 6 | 0 | 5 | 0 | API-100, 104, 106, 107 and F-29 withdrawn. `alg=none` ID token rejected, no account row created |
| Store notifications | 3 | 3 | 0 | 0 | 0 | no Pub/Sub token, `alg=none` bearer, forged Apple payload: all rejected |
| Admin API without or with wrong credentials | 13 | 11 | 2 | 0 | 0 | API-127, API-128 → BUG-003 (404, route missing) |
| Generic HTTP behaviour (404, 405, 413, 415, injection-shaped path, banners, error echo) | 10 | 10 | 0 | 0 | 0 | |
| Delete install | 5 | 5 | 0 | 0 | 0 | token dead at once, ID cannot be reused |
| Database constraints and privileges | 20 | 18 | 1 | 1 | 0 | D-03 → BUG-009; D-04 withdrawn |
| **Total** | **151** | **130** | **10** | **10** | **1** | |

### 3.2 Database (the 20 D- cases)

Persistence was also checked through the API cases: a bank request is stored against a keyed hash, not the install ID (F-09, F-10); a purchase row and exactly one seat exist after a grant (F-21, F-22); a deleted install is tombstoned (F-30).

| ID | Check | Result |
|---|---|---|
| D-01 | `installs.platform` outside `android`/`ios` | rejected (PASS) |
| D-02 | duplicate install primary key | rejected (PASS) |
| D-03 | negative `installs.catalog_version` | **accepted (FAIL, BUG-009)** |
| D-05 | seat with a purchase that does not exist | rejected (PASS) |
| D-06, D-07 | bank request with bad channel / country | rejected (PASS) |
| D-08 | negative price | rejected (PASS) |
| D-09 | duplicate store purchase key | rejected (PASS) |
| D-10…D-14 | API login reading operators or audit log, changing flags, deleting purchases, creating tables | all rejected (PASS) |
| D-15, D-16 | read-only ops login writing | rejected (PASS) |
| D-17, D-18 | admin login deleting or updating audit rows | rejected (PASS) |
| D-19 | no column for IP address, IMEI, phone, advertising ID, device ID, amount or balance | none found (PASS) |
| D-20 | install token stored as a hash only | `bytea` hash (PASS) |
| D-04 | withdrawn (see bug report) | |

Transactions were not tested separately; the existing Infrastructure tests that passed cover concurrent seat and idempotency paths, and I did not add to them.

### 3.3 Extra live checks

| Check | Result |
|---|---|
| 61st `POST /v1/installs` from one /24 inside an hour | `429 RATE_LIMITED`, `Retry-After: 3600` (PASS; documented limit is 60/hour) |
| Switch `zakah` on in the database, sync from a new install | delivered as `true`, flags version 2 → 3 (PASS) |
| `Dev:FakeStores=true` with `ASPNETCORE_ENVIRONMENT=Production` | host refuses to start (PASS) |
| `Production` with the local KMS and no key configuration | host refuses to start, "Kms:HmacKeys:Seat must be set" (PASS) |
| `SIGTERM` to the running API | **unhandled exception, exit 134 (FAIL, BUG-002)** |

## 4. Not run, and why

| Item | Reason | Status |
|---|---|---|
| On-device UI, navigation, responsive behaviour, forms on a real screen | No emulator was running on the PC; Android Studio was closed and I can only click in it, not type or build | BLOCKED |
| End-to-end journeys (onboarding → SMS capture → categorise → budget; purchase; backup and restore) | Same; also need Play billing, Drive, an iPhone | BLOCKED |
| `app/integration_test/*` (7 files: database on device, explorer, device flows, SMS on device) | Need an emulator | BLOCKED |
| Android Gradle unit tests, Android lint, APK assertions | No Android SDK in the VM | NOT TESTED |
| iOS `xcodebuild test`, iOS build | No macOS | NOT TESTED |
| Benchmark-tagged tests (parse time, 50k-row search, chart speed) | Timing on a 2-CPU VM is not the reference device | NOT TESTED |
| Docker image, non-root, Trivy scan, `docker compose up` | No Docker | NOT TESTED |
| OpenAPI Spectral lint, Prometheus rule check | Not attempted | NOT TESTED |
| Admin API with a valid operator token | No identity provider configured (T-136 open) | BLOCKED |
| Real Google Play / App Store verification, RTDN, App Store notifications | No store accounts | BLOCKED |
| Regression against a previous release | There is no earlier release; the 10,547 existing tests are the regression baseline recorded here | — |

GitHub Actions reported `app-ci`, `backend-ci` and `db-platform` green on the same tree (`a9969346`, 18 Nov). Those runs include the Android, iOS and emulator jobs I could not run. I read the run list only; I did not re-verify their logs, so they are not counted in any figure above.
