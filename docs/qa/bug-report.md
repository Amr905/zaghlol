# Bug report

_IDs BUG-015…018 were first published locally as BUG-010…013; renumbered on 25 Nov because QA B57 (`bug-report-2.md` in the repo) used BUG-010…014 for other bugs._

Audit of `Amr905/zaghlol`, branch `main` @ `bc5b9d1d` (merge of PR #76), 19 Nov 2026.
Every bug below was reproduced or read directly in the code during this audit. Nothing was fixed; no application code was changed.

| ID | Severity | Title | Requirement / task |
|---|---|---|---|
| BUG-001 | HIGH | A release build trusts no backend key, so sync and Gold cannot work in release | FR-GOLD-02/04, FR-SYNC-04, T-140, FU-115 |
| BUG-002 | MEDIUM | Backend API process aborts (exit 134) on every graceful shutdown | T-005, FU-023, NFR-BE-02 |
| BUG-003 | MEDIUM | Two operator endpoints in the API contract do not exist | FR-BE-10, backend-api.md §5, T-137 |
| BUG-004 | LOW | `Zaghlol-App` header is "required" in the contract but not checked on install registration | backend-api.md §1, OpenAPI |
| BUG-005 | LOW | Three request limits in the contract are not enforced as `400` | OpenAPI `zaghlol-v1.yaml` |
| BUG-006 | LOW | SRS no longer matches two product decisions that are implemented | FR-CAT-01, FR-CHT-02 |
| BUG-007 | LOW | `flutter analyze` fails on a clean checkout of `main` | CLAUDE.md §7 (Definition of Done) |
| BUG-008 | LOW | Status documents contradict each other; README says "zero-backend" | CLAUDE.md §9, docs/workflow |
| BUG-009 | LOW | `installs.catalog_version` accepts negative values at database level | backend-schema.md |
| BUG-015 | MEDIUM | Gold paywall never leaves "Loading prices…" when the store has no offers | FR-GOLD-01, explorer finding 16 |
| BUG-016 | MEDIUM | App icon is Flutter's default logo on Android and iOS, not Captain Zaghlol | CLAUDE.md §8, docs/02-design/brand |
| BUG-017 | LOW | About screen shows two identical unlabelled "Not updated yet" lines | FR-SYNC-06 |
| BUG-018 | LOW | Card-filter sheet opens under the tab bar; the Add button covers its "Done" button | FR-HOME-05, FR-CARD-01 |
| BUG-019 | LOW | Transfer pairing returns "ambiguous" when the pool contains the leg itself, against its documented contract | BR-XFR-01 |
| BUG-020 | LOW | Decision IDs D-67…D-70 each name two different decisions in the SRS | requirements.md §2 |

BUG-015…018 were found on the emulator in a second session (19 Nov, evening). No CRITICAL bug was found. That statement covers only what was tested: see `release-readiness.md` for what was not.

---

## BUG-001 — A release build trusts no backend key

- **Severity:** HIGH (blocks the paid tier and catalog sync in any store build). Known to the team and intentional as a fail-closed default; it is listed here because it must be closed before release.
- **Related:** FR-GOLD-02, FR-GOLD-04, FR-SYNC-04, FR-ZAK-06; T-140 (BLOCKED), FU-115.
- **How verified:** code inspection. A release build was not produced or run in this audit.
- **Steps to reproduce:**
  1. Open `app/lib/features/catalog_sync/application/sync_providers.dart` line 38: `releaseResponseKeys` is an empty list.
  2. Open `app/lib/features/gold/application/entitlement.dart` line 46: `releaseEntitlementKeys` is an empty list.
  3. `devBackendKeys` is forced empty when `kReleaseMode` is true (same file, line 54).
- **Expected:** a release build pins the production sync and entitlement public keys.
- **Actual:** with no key, no `Zaghlol-Signature` and no entitlement token can verify. The app drops every sync body and never grants Gold. Feature flags can never be switched on remotely.
- **Evidence:** the source comment at `entitlement.dart:43-45`: "Empty until T-140 creates the production keys (FU-115): with no key nothing verifies".
- **Suspected root cause:** production KMS keys do not exist yet because hosting is undecided (BLK-04).
- **Recommended fix:** after T-140 creates the keys, embed the public JWKs, and add a CI check that fails a `prod` flavor build while either list is empty.

## BUG-002 — Backend API aborts on graceful shutdown

- **Severity:** MEDIUM. No data loss was observed, but every deploy, scale-down or restart ends in a crash with a stack trace, and the exit code is always 134 instead of the value the code intends to return.
- **Related:** T-005, FU-023 (non-zero exit when a start-up guard stops the host).
- **Steps to reproduce:**
  1. Build the backend (`dotnet build Zaghlol.sln -c Release`).
  2. Start PostgreSQL 17, apply `deploy/db/bootstrap-roles.sql`, run the migrator, create dev keys (`tools/dev-keys.sh`).
  3. Start `Zaghlol.Api.dll` in `Development`; wait for `GET /v1/health` = 200.
  4. Send `SIGTERM` to the process (what Docker, Cloud Run and Kubernetes send).
- **Expected:** clean stop, exit code 0.
- **Actual:** `Unhandled exception. System.ObjectDisposedException: Cannot access a disposed object. Object name: 'IServiceProvider'.` at `Program.cs:line 133`; exit code 134. The exception was in the API log of every run I checked (3); the exit code was measured once.
- **Evidence:** `docs/qa/evidence/api-shutdown.log`; script `docs/qa/tools/run_backend_local.sh` prints `API exit code after SIGTERM: 134`.
- **Root cause:** `Program.cs` reads `app.Services.GetRequiredService<HostExitCode>()` after `await app.RunAsync()`; `RunAsync` disposes the host, so the provider is gone.
- **Recommended fix:** resolve `HostExitCode` before `RunAsync` (it is a singleton) and return its value afterwards. Add a test that starts the host, stops it and asserts exit code 0.

## BUG-003 — Two operator endpoints in the contract do not exist

- **Severity:** MEDIUM. Operators cannot see "request my bank" submissions or daily-active counts through the API; the data is collected but has no reader.
- **Related:** FR-BE-10 ("operators see a ranked list"), backend-api.md §5 role table, OpenAPI operations `adminListBankRequests` and `adminDailyActive`.
- **Steps to reproduce:** against a running backend, `GET /admin/v1/bank-requests` and `GET /admin/v1/metrics/daily-active` with no token.
- **Expected:** `401` (as the other 9 admin routes tested return), and `200` for an operator.
- **Actual:** `404 NOT_FOUND` for both. No `MapGet` for either path exists under `backend/src/Zaghlol.Api`.
- **Evidence:** `api_blackbox_results.json` cases API-127 and API-128; route list from `grep -rn "Map(Get|Post|Put|Delete)" backend/src/Zaghlol.Api`.
- **Suspected root cause:** the read side was left for T-137 (ops CLI, TODO) and no task owns the two routes. The contract tests do not fail on a declared operation that has no route.
- **Recommended fix:** implement both routes with the documented roles, or remove them from the OpenAPI file and backend-api.md until they exist. Make the contract test fail when a declared operation has no route.

## BUG-004 — `Zaghlol-App` header not checked on install registration

- **Severity:** LOW.
- **Steps to reproduce:** `POST /v1/installs` with a valid body and `Idempotency-Key` but (a) no `Zaghlol-App` header, (b) `Zaghlol-App: android 1.0`.
- **Expected:** `400 VALIDATION_FAILED` (the OpenAPI parameter is `required: true` with a pattern; `/v1/sync` does return 400 in both cases, F-02 and F-03).
- **Actual:** `201` in both cases (API-014, API-015).
- **Root cause:** only `SyncEndpoints.TryReadAppVersion` reads the header.
- **Recommended fix:** validate the header in one shared filter for every `/v1` app operation, or mark it optional in the contract where it is unused.

## BUG-005 — Contract limits not enforced as `400`

- **Severity:** LOW. No invalid data was stored in any case.
- **Cases:**
  1. `purchaseToken` of 513 characters (contract `maxLength: 512`): `422 PURCHASE_TOKEN_INVALID` instead of `400 VALIDATION_FAILED` (API-083, F-23).
  2. `bankRequests[].country = "eg"` (contract pattern `^[A-Z]{2}$`): `200`, the row is silently dropped (API-048, F-04).
  3. `bankRequests[].channel = "email"` (contract enum `sms | notification`): `200`, silently dropped (API-049, F-04).
- **Side effect of 2 and 3:** the call counts as the install's one effective sync for 24 hours.
- **Recommended fix:** decide which behaviour is intended and make the OpenAPI file and the server agree. If silent drop is intended for bank requests, say so in the schema description as it does for contributions.

## BUG-006 — SRS out of date for two implemented decisions

- **Severity:** LOW (documentation), but it makes two requirements fail as written.
- **FR-CAT-01:** "Ship the 14 system categories". The seed (`tools/catalog_build/data/catalog_seed.csv`) has 16 category rows (PO decisions CAT-INSTAPAY and CAT-CASH).
- **FR-CHT-02:** "Free users get 4 core charts… Others show a Gold-locked preview". All 12 charts are free (`GoldGate.chartsOpenToFree`, PO decision CHARTS-FREE, 16 Nov).
- **Recommended fix:** update the SRS (and the entitlement matrix in §5.2) or revert the behaviour. The decisions are recorded only in `docs/workflow/PO_DECISIONS.md`.

## BUG-007 — `flutter analyze` fails on a clean checkout

- **Severity:** LOW.
- **Steps to reproduce:** clean clone of `main`, Flutter 3.47.9, `flutter pub get`, `flutter analyze` at the repo root.
- **Expected:** "No issues found" (Definition of Done §7).
- **Actual:** exit code 1: `warning • Flutter applications using Riverpod must contain a ProviderScope at the root of their widget tree • app/lib/main.dart:67:3 • missing_provider_scope`.
- **Evidence:** `docs/qa/evidence/analyze.log`.
- **Note:** GitHub Actions run 44394261225 (`app-ci`, same tree) is green, so the result depends on the environment. The `// ignore: missing_provider_scope (…)` comment on line 66 carries a trailing explanation in brackets; whether that is why the ignore is not honoured here was not established.
- **Recommended fix:** move the explanation to its own comment line so the ignore is a bare rule name, and confirm the plugin actually runs in CI.

## BUG-008 — Status documents contradict each other

- **Severity:** LOW.
- `docs/implementation-status.md` lists T-059, T-099 and T-159 as `TODO`; `docs/workflow/LEAD_HANDOFF.md` says all three were built in batch 39.
- `docs/workflow/PHASE_LOG.md` stops at 8 Nov.
- `README.md` line 3 says "zero-backend", against CLAUDE.md §9 ("Never claim 'no server'").
- The local folder `C:\Projects\Zaghlol` is a documents-only snapshot from 3 Nov with empty `app/` and `backend/`; it is not a git checkout.
- **Recommended fix:** correct the three task rows, the README line and the phase log; replace the local folder with a real clone.

## BUG-009 — `installs.catalog_version` has no lower bound in the database

- **Severity:** LOW. The API rejects a negative `catalogVersion` (API-041).
- **Steps to reproduce:** as a database superuser, insert an `installs` row with `catalog_version = -1`.
- **Expected:** CHECK violation, like `platform` (D-01).
- **Actual:** accepted (D-03).
- **Recommended fix:** add `CHECK (catalog_version >= 0)` in a migration.

## BUG-015 — Gold paywall stuck on "Loading prices…"

- **Severity:** MEDIUM. The user can close the screen, but cannot buy, retry or learn what is wrong.
- **Environment:** emulator, Pixel 10 Pro XL AVD, Android 17 (API 37), `zaghlol-devSms-debug-apk` from app-ci run 44394261225 (same tree as `main`). Google Play cannot sell products for this package.
- **Steps to reproduce:** Settings → Zaghlol Gold banner; wait.
- **Expected:** after 8 seconds (`goldStoreTimeout`), "prices failed" with a retry button, as the paywall code and `store_timeout_test.dart` describe.
- **Actual:** three empty plan placeholders and "Loading prices…" for more than 30 seconds; reproduced after closing and reopening (20 s more). "Restore purchases" on the same screen did fail cleanly ("The store reported a problem. Try again in a bit."), so the store connection itself answers.
- **Evidence:** screenshots taken during the session (described in `test-results.md` §5).
- **Suspected root cause:** not established; no device logs were available. The 8-second timeout wraps only `queryProductDetails`; something that runs before it, or the provider being rebuilt without settling, may keep it in loading. The host test fakes the store, so it cannot catch this.
- **Recommended fix:** reproduce with `adb logcat` on an emulator without Play billing; add a device or integration test for the "store unavailable" path.

## BUG-016 — App icon is the Flutter default

- **Severity:** MEDIUM. It would ship to the stores as is.
- **Steps:** install any flavour; look at the launcher or the system app list.
- **Expected:** Captain Zaghlol icon (approved in Phase 2; files `docs/02-design/brand/zaghlol-app-icon-*.png`).
- **Actual:** Flutter logo. `app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` has the same MD5 (`afe1b655…`) as Flutter's template icon; iOS `Icon-App-1024x1024@1x.png` has the same MD5 (`c785f893…`) as Flutter's template.
- **Recommended fix:** generate launcher icons from the brand files (adaptive icon on Android), and add a CI check that the icons differ from Flutter's template.

## BUG-017 — About screen: two identical unlabelled lines

- **Severity:** LOW.
- **Steps:** fresh install, never synced; Settings → About.
- **Expected:** "Merchant list updated …" and "Prices updated …", or a labelled "not updated yet" for each (FR-SYNC-06).
- **Actual:** "Not updated yet (works offline)" twice, with nothing saying which is which.
- **Root cause:** `about_screen.dart` lines 52 and 57 both fall back to `aboutMainNeverSynced`.
- **Recommended fix:** a fallback string per row, e.g. "Merchant list: not updated yet".

## BUG-018 — Card-filter sheet covered by the tab bar and Add button

- **Severity:** LOW (a workaround exists).
- **Steps:** Home → filter icon.
- **Expected:** a bottom sheet above the tab bar and the floating Add button.
- **Actual:** the sheet opens under the tab bar; the Add button covers all but the first letter of "Done". Tapping that letter does close the sheet. With many cards, the end of the list would also sit under the tab bar.
- **Recommended fix:** show the sheet on the root navigator (`useRootNavigator: true`), or hide the Add button while a sheet is open; add a golden test with the sheet open.

## BUG-019 — Transfer pairing breaks its own contract when the pool contains the leg

- **Severity:** LOW (latent). Found 26 Nov on `main` @ `89583b27` by an independent QA test (`packages/zaghlol_parsing/test/qa/qa_independent_spec_test.dart`, TC-XFR-003b).
- **Steps:** call `decideSameCurrency(a, [a, b])` with `a` = 1,000 EGP out of NBE and `b` = 1,000 EGP into CIB two minutes later.
- **Expected:** `PairWith(b)`. The function's comment says the pool "may contain [leg]; it is ignored".
- **Actual:** `AmbiguousMatch`. With `[b]` alone it pairs.
- **Root cause:** `transfer_matching.dart` runs the reverse check on `[...all, leg]`, so the leg is counted twice when it is already in the pool, and "exactly one reverse candidate" fails.
- **Impact today:** none seen. The app's only caller (`transfer_pairing.dart`) leaves the leg out of the pool. A future caller that trusts the comment would stop pairing every self-transfer and send them all to "ask the user".
- **Recommended fix:** drop the leg from `all` before both checks (or fix the comment), and add the two-element case to the existing "leg ignores itself" test, which only checks a pool of one.

## BUG-020 — Duplicate decision IDs in the SRS

- **Severity:** LOW (documentation).
- **Where:** `docs/01-requirements/requirements.md` §2 on `main` @ `89583b27`.
- **Actual:** D-67 is both "XAD hidden" and "Hide amounts in the app"; D-68 is both "Late-month salary" and "Chart periods"; D-69 is both "Hidden accounts still count" and "App size budget"; D-70 is both "Dark-mode quip" and "Lost database key".
- **Impact:** code comments, tests and task files that cite one of these IDs cannot be traced to one decision. The test catalogue cannot attribute tests that cite them.
- **Recommended fix:** renumber the later four and update the references.

---

## Not bugs: expectations I withdrew

| Case | What happened | Why it is not a bug |
|---|---|---|
| API-063…065 | First "valid" sync returned only the throttle fields | My own earlier case (API-048) had used the install's 24 h window. Retested with fresh installs (F-01, F-11). |
| API-100 | Forged ID token answered `422 ID_TOKEN_INVALID`, I expected 400/401 | 422 is the documented code. |
| API-104, 106, 107 | `429 RATE_LIMITED` | The per-install limiter fired after my burst. Retested on fresh installs (F-26, F-28). |
| F-29 | Forged `Zaghlol-Account` header on `GET /v1/entitlement` answered 200 | backend-api.md §4.4: an account token that does not validate counts as absent; the token returned had `acct: null` and no Gold. |
| F-12 | A flag key I inserted (`qa_flag_on`) was not delivered | The server delivers only the keys it knows (`zakah`, `smart_roi`, `roi_named_products`). Toggling `zakah` was delivered correctly. |
| F-07 | A valid merchant contribution was not stored | Category codes are checked against the published catalog, and the test database had none. Recorded as BLOCKED, not failed. |
| D-04 | Hard `DELETE` of an install as superuser succeeded | The trigger vacates seats; it is not meant to block deletion. |
| Device | Money tab total looked like "ج.م" with no number | The dot before it is the Arabic-Indic zero "٠"; the card reads 0 EGP. |
