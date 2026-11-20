# Review - batch 43 (QA fixes BUG-002 to BUG-009)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Sonnet) |
| Date | 2026-11-19 |
| Diff | `git diff bc5b9d1d HEAD` on `batch/2026-11-19-43-qa-fixes` (HEAD b1eb3251); BUG-001 out of scope |
| Verdict | **APPROVED** (no blocker, no major; minors below are optional follow-ups) |

## What I ran
- `dotnet build backend/Zaghlol.sln -c Release -warnaserror`: 0 warnings, 0 errors.
- `GracefulShutdownTests`: passes at HEAD. Re-run in a scratch copy with the old `Program.cs` (from bc5b9d1d): it fails with `ObjectDisposedException`, so the test does catch BUG-002.
- Non-database tests: Application.Tests 1057/1057; Infrastructure `ModelTests`+`InitialCreateGoldenTests` 28/28; Contract `AdminRolesLiveContractTests` 3/3 (includes the new `EverySpecOperationHasAMappedRoute`); Api `ArchitectureTests` 15/15.
- `flutter analyze --no-pub` at the repo root: "No issues found".
- Not run (Testcontainers cannot pull images): `OpsReportEndpointTests`, `AppHeaderTests`, the sync and purchase endpoint tests, `CheckConstraintTests`, `InstallsLiveContractTests`. Findings on those are from reading, not from running.

## Per-bug result
| Bug | Closed? | Evidence |
|-----|---------|----------|
| BUG-002 SIGTERM exit 134 | Yes | `Program.cs` (Api and Workers) now resolve `HostExitCode` before `RunAsync`; the real-process test fails on the old code and passes on the new. |
| BUG-003 missing admin routes | Yes (DB part unverified here) | Both routes mapped; spec-vs-routes contract test added and passes. |
| BUG-004 `Zaghlol-App` | Yes | One filter, on the `/v1` install-scoped group and on `POST /v1/installs`. Set of operations carrying `ZaghlolApp` in the OpenAPI file equals the set of filtered routes exactly (checked by script; catalog, health, notifications and the Apple callback are correctly excluded). |
| BUG-005 limits | Yes | `purchaseToken` over 512 or empty is 400 (matches restore and `PlayStateMapping.MaxTokenLength` = 512); invalid bank-request country/channel is documented as a silent drop in OpenAPI, and the existing drop is tested. |
| BUG-006 SRS | Yes | FR-CAT-01, FR-CHT-02 and the tier table updated. |
| BUG-007 analyze | Yes here | Ignore is now `riverpod_lint/missing_provider_scope` on its own comment line; analyze is clean in this environment. See F6. |
| BUG-008 status docs | Yes | T-059/T-099/T-159 rows, README line 3, PHASE_LOG. |
| BUG-009 CHECK | Yes | Entity config, migration, snapshot, schema doc and the CHECK-count test all agree (57 to 58). |

## Specific checks you asked for
- **Contract agreement.** OpenAPI, `backend-api.md` and the server agree on: 400 for `Zaghlol-App` (new `400` responses added to `registerInstall` and `deleteInstall`; the other seven already had it), the 400/422 split for `purchaseToken`, the bank-request drop rule, the 10/50 item caps, and the BankRequestRank / DailyActive shapes (`date` as `yyyy-MM-dd`, `lastRequestedAt` ending in `Z`, `count >= 1`, `activeInstalls >= 0`). Gaps are F2 and F3.
- **No financial or install-identifying data in the two reports.** `OpsReportStore` returns only the normalized institution name, country, channel, a distinct-install count and the latest `received_at`; `install_hash` is counted (`COUNT(DISTINCT)`) and never selected. Daily active is a sum over platform and version, with no install data. Both set `Cache-Control: no-store`. The institution name has already passed the privacy filter and the DB CHECK (no `@`, no 6-digit run). Residual: a name asked for by one install is shown with its exact last-request time (F4).
- **Authorization.** `/admin/v1/bank-requests` uses `RequireOperatorRole(catalog_editor)`; `/admin/v1/metrics/daily-active` uses a new `operator:any` policy that requires a role claim in `OperatorRoles.All` (a token with an unknown role gets 403, a missing or bad token 401). The operator scheme is not the default, so install tokens cannot reach these routes. The tests cover 401, every other role on bank-requests getting 403, every known role on daily-active getting 200, and `bogus_role` getting 403. `ops_rw` has SELECT on both tables in `GrantMatrix.cs:228-229`, so the Admin login can read them.
- **`Zaghlol-App` filter vs the app.** The app sends `zaghlol-app: <platform>/<version> (<build>)` on every operation (`backend_client.dart:382`) and on registration (`:601`). `ClientIdentity` requires a 3-part version and `\S+` build with total length at most 64; the server regex accepts the same version form and `[!-~]+` for the build, so any header the app can build passes. Defaults (`pubspec` 0.1.0+1) pass. The filter is a group-level filter, so it runs after authentication (401 stays 401) and before the endpoint-level time-nonce and idempotency filters, so a rejected header claims no idempotency key. For `POST /v1/installs` the check runs before the handler's own idempotency logic. It is narrower than the OpenAPI pattern (`\S+`); that is consistent with how `/v1/sync` already behaved. Not breaking.
- **Migration.** `ADD CONSTRAINT ... CHECK (catalog_version >= 0)`: no API path writes a negative value (sync rejects a negative cursor with 400), so it applies to existing data; the `Down` drops it. It takes a full-table validation scan under lock; fine at launch scale (F5).

## Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | minor | `backend/tests/Zaghlol.Contract.Tests/InstallsLiveContractTests.cs` (new `EveryOperationThatRequiresTheAppHeaderRejectsAMissingOrMalformedOne`) | The theory sends body `{}`. Endpoint filters run after body binding and validation, so for sync, purchases verify/restore and sign-in the 400 VALIDATION_FAILED may come from the empty body, not the missing header. The test would likely pass with the filter removed for those operations. Registration (valid body) and delete (no body) are tested precisely in `AppHeaderTests`; entitlement, sign-out and account delete have no body, so they are fine. | Send a valid minimal body per operation, or assert the filter ran by also asserting the stateful effect (as `AppHeaderTests` does for registration). |
| F2 | minor | `backend/openapi/zaghlol-v1.yaml` (adminListBankRequests responses) | The server answers `400 VALIDATION_FAILED` to any query parameter on bank-requests and the description says "No query parameters", but the operation declares no `400` response (daily-active does). | Add `'400': BadRequest`. |
| F3 | minor | `docs/03-technical/backend-api.md:542-543` | The §5 role table still says only "Ranked list" / "Aggregate counters". The 500 cap, ordering, `days` 1-90 default 14, ASCII-digit and repeated-parameter rules, and the zero-filled days live only in the OpenAPI text. | Add a short §5 paragraph or point to the OpenAPI description. |
| F4 | nit | `backend/src/Zaghlol.Infrastructure/Reports/OpsReportStore.cs:23`, `OpsReportEndpoints.cs:81` | An institution requested by a single install appears with count 1 and an exact timestamp. No identifier leaks, but a minimum count or day-level timestamp would harden it. Free text is already privacy-filtered, so this is acceptable as built. | Optional: report `lastRequestedAt` at day precision, or note the choice in the schema. |
| F5 | nit | `.../Migrations/20261119104549_InstallsCatalogVersionNonNegative.cs:19` | `AddCheckConstraint` validates every row under an exclusive lock. Fine now; at scale use `NOT VALID` then `VALIDATE CONSTRAINT`. | None now; remember for later check-constraint migrations on `installs`. |
| F6 | nit | `app/lib/main.dart:67` | Git history shows two forms tried (bare, then plugin-prefixed). The prefixed form is clean here, but I did not confirm the QA environment's failure was cured by it, nor that the plugin runs in CI. | Confirm once in CI that `flutter analyze` is clean and the plugin is active. |
| F7 | nit | `OpsReportStore.cs:26-29` | Ordering ties beyond count and last request use name and country but not channel, so two channels of one institution with equal count and timestamp have no defined order; `TheRankingIsByDistinctInstallsThen...` asserts notification before sms for exactly that tie. It will pass in practice but depends on Postgres sort order. | Add `.ThenBy(x => x.Channel)` and say so in the OpenAPI text. |
| F8 | nit | `backend/src/Zaghlol.Workers/Program.cs:71-74` | The Workers copy of the BUG-002 fix has no test of its own (the API one does). Same two-line pattern. | Optional. |
| F9 | nit | `docs/qa/tools/run_backend_local.sh:8,17,23-24` | Committed scripts carry dev-only DB passwords (`*_dev_only`). They match `deploy/db/dev-passwords.sql` and are not secrets, but they are scanned-for strings. | Optional: read them from the dev files. |

## Checklist
- [x] Build clean with warnings as errors; no new analyzer warnings.
- [x] `flutter analyze` clean.
- [x] No financial data or install identifiers in the new reports; no raw SMS anywhere in the diff.
- [x] No `double` money; no app-side logic changed beyond one comment.
- [x] Scope: only the BUG-002..009 fixes, their docs, tests, and the QA audit files added to `docs/qa/`.
- [ ] DB-backed tests of this batch were not run here (no container runtime); the Lead's CI must run `OpsReportEndpointTests`, `AppHeaderTests`, `SyncEndpointTests`, `PurchaseVerifyEndpointTests`, `CheckConstraintTests` and the live contract tests before merge.

## Notes for the Lead
Merge after the DB-backed suites are green in CI. F1 is the only item that weakens the test claim; the code itself is structurally right (one group-level filter).
