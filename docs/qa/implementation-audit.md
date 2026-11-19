# Implementation audit

Target: `Amr905/zaghlol`, `main` @ `bc5b9d1d`, 19 Nov 2026. Method: documentation review, then code review focused on the highest-risk areas, with every claim checked by a command or a test where possible. The codebase is about 190,000 lines; this is a targeted review, not a line-by-line one. Section 7 says what was not reviewed.

## 1. Where the code is

`C:\Projects\Zaghlol` does not contain the application. `app/` and `backend/` hold one README each, the folder is not a git checkout, and its documents stop at 3 Nov. The audited code is a fresh clone of the public GitHub repository.

## 2. Documentation reviewed

CLAUDE.md, SRS (`requirements.md`), design set (journeys, 46-screen inventory, navigation, design system, theme, voice), technical specification (architecture, backend API, both schemas, security model, testing strategy), OpenAPI `zaghlol-v1.yaml`, task board (186 tasks), `implementation-status.md`, `LEAD_HANDOFF.md`, `PO_DECISIONS.md`.

Implementation status claimed by the project: 167 of 186 tasks DONE, 3 IN_REVIEW, 12 TODO, 4 BLOCKED. This audit did not re-verify task by task.

## 3. Architecture

| Question | Finding | How checked |
|---|---|---|
| Follows the approved architecture? | Yes in structure. App is feature-first (`app/lib/features/<feature>`, 27 features) with shared code in `app/lib/core`; domain, parsing and catalog logic are separate pure-Dart packages. Backend is layered: Domain ← Application ← Infrastructure ← Api / Workers | directory listing; `.csproj` references |
| Responsibilities separated? | The three pure packages import nothing from Flutter (0 files). Backend `Domain` references no other project | `grep` over `packages/*/lib`; project references |
| Dependencies managed? | Pub workspace with an enforced lockfile; NuGet central package management; no vulnerable NuGet package reported. App dependencies contain no analytics, ads or crash-reporting SDK | `pubspec.yaml`, `dotnet list package --vulnerable`, `test/privacy/dependency_scan_test.dart` (passed) |
| Unneeded abstraction or duplication? | Not assessed in depth. 2 TODO/FIXME markers in production code | `grep` |
| Stack as planned? | One documented change: SQLite3MultipleCiphers instead of SQLCipher (ADR-002). CLAUDE.md §3 still says "sqflite_sqlcipher" and "Riverpod 2"; the app uses Riverpod 3 | `pubspec.yaml` |

## 4. Backend

| Question | Finding | Evidence |
|---|---|---|
| All required APIs implemented? | **No.** 14 of 14 app-facing operations have routes. Of the admin operations, `GET /admin/v1/bank-requests` and `GET /admin/v1/metrics/daily-active` have none | route list; API-127, API-128; BUG-003 |
| Contracts match the specification? | Mostly. Deviations: required `Zaghlol-App` header not checked on registration (BUG-004); three schema limits not enforced as 400 (BUG-005) | black-box tests |
| Business rules | 24 h sync throttle, idempotent registration with token rotation, one seat per purchase, forged purchase rejected, flags default off: all behaved as specified in live tests. Existing 3,063 backend tests pass | `test-results.md` |
| Input validation | Request bodies are closed at every level: unknown fields, including financial ones, get `400 UNKNOWN_FIELD`. Size limit, content type, malformed and duplicate-key JSON handled | API-008, 009, 016…019, 044…046, 050 |
| Error handling | Consistent `application/problem+json` with a stable `code`; error bodies did not echo input | API-150 |
| Database relationships and constraints | 57 CHECK, 14 foreign-key and 28 primary-key constraints. 9 of 10 constraint probes rejected bad data; one gap (BUG-009) | D-01…D-09 |
| Authentication and authorization | Install tokens are 32 random bytes stored as a hash and bound to the install ID. Admin routes answer 401 without an operator token. Database logins are least-privilege: the API login cannot read operators or the audit log, change flags or delete purchases | API-030…033, 120…136; D-10…D-18 |
| Operations | **The API process aborts on graceful shutdown** (BUG-002) | reproduced |

## 5. Frontend (app)

Reviewed through the test suites and static checks only. Nothing here was seen on a screen.

| Question | Finding | Evidence |
|---|---|---|
| All required screens implemented? | All 46 screen IDs in the inventory are referenced in `app/lib` or its tests. This shows a screen exists by name, not that it is complete | `grep` of `S-nn` IDs |
| Navigation matches the user flows? | Not verified on a device. Routing and wiring tests pass (58 tests in `test/app` and `test/core/routing`) | host tests |
| Components reusable and consistent? | Shared design-system components in `core/ui` with 108 passing tests and 477 passing golden images (Arabic and English, light and dark) | host tests |
| Forms validated? | Widget tests for forms pass; behaviour with a real keyboard not seen | host tests |
| Loading, empty, success and error states? | Covered by widget and golden tests in the feature suites; not seen on a device | host tests |
| Matches the approved designs? | **Not verified.** Golden images were compared with the repository's own reference images, not with the mockups in `docs/02-design/mockups` | — |
| No hard-coded strings, no `double` for money, no `print` | Project linter: 563 files, 0 issues | `zaghlol_lints` |
| Known gaps stated by the project | Statement-import review UI not built (FU-262); Rive mascot file missing (T-088); about 20 UI follow-ups not started (FU-257); 85 open follow-ups in the lane table, 307 in the itemised table | `implementation-status.md` |

## 6. Security

| Area | Finding | Status |
|---|---|---|
| Authentication | Forged, superseded, foreign and deleted install tokens all rejected. `alg=none` ID token and account token rejected or ignored as documented. Pub/Sub push without a token rejected | verified live |
| Authorization | Admin API closed without a token; install token not accepted as operator token. Operator OIDC with MFA exists in code but no identity provider is configured, so the positive path is untested | negative path verified; positive path BLOCKED |
| Input validation | Closed schemas, size and type limits; SQL-injection-shaped path answered 404 | verified live |
| Sensitive data exposure | No database column for IP, IMEI, phone, advertising ID, amounts or balances. Phone numbers and IPA sent as "merchant" contributions were not stored. No server banner headers. Request log lines carry the route template only | verified live |
| Response integrity | Sync responses and entitlement tokens are ES256-signed; a changed body or swapped payload does not verify | verified live |
| Configuration and secrets | No private key or credential found in the repository by pattern scan. Dev keys are generated at run time. The host refuses `Dev:FakeStores` and an unconfigured KMS in `Production` | verified |
| Rate limiting | 60 registrations per hour per /24 enforced | verified live |
| Android manifest | `allowBackup=false`, backup and transfer rules exclude all data, network security config present, SMS permissions only in the `sms` flavor and removed in `noSms` | inspection |
| App key handling, encrypted storage, app lock, screenshot protection | Code and passing host tests exist; behaviour on a device not verified | BLOCKED |
| Release build trust anchors | **Empty** (BUG-001) | inspection |
| Dynamic and third-party assessment | MobSF, ZAP, penetration test: not done (T-175 is TODO) | NOT TESTED |

No vulnerability rated CRITICAL or HIGH was found in what was tested. The untested areas above are where one could still be.

## 7. Not reviewed

- Kotlin and Swift host code beyond the manifest (SMS receiver, notification listener, key stores, App Intents, widgets).
- Backup cryptography design, entitlement trusted-time logic, seat-move rules: relied on the existing tests passing.
- Parsing templates against real bank messages. 197 template entries are marked `synthetic-unverified` in the registry.
- Arabic copy quality.
- Infrastructure as code and release pipelines.

## 8. Ambiguities and contradictions found in the documents

| # | Item |
|---|---|
| 1 | FR-CAT-01 says 14 system categories; 16 are shipped by PO decision. SRS not updated |
| 2 | FR-CHT-02 says 4 free charts; all 12 are free by PO decision. SRS and entitlement matrix not updated |
| 3 | FR-BE-01 says "first/last-seen dates only"; the schema stores timestamps with microseconds. Unclear whether "dates" was meant literally |
| 4 | BR-SYNC-04 excludes "anything matching a person-name pattern"; the Lead handoff says server-side person-name detection was waived (T-128). In my test a three-word personal name was dropped, but I could not tell which rule dropped it |
| 5 | The OpenAPI schema gives a pattern and an enum for bank requests; the server silently drops violations. The description says silent drop for contributions only |
| 6 | Feature flags: an operator-created key is not delivered to apps; only keys compiled into the backend are. FR-BE-05 does not say whether new flags need a backend release |
| 7 | CLAUDE.md §4 still describes `app/` and `backend/` as "empty until Phase 5" and lists Riverpod 2 and sqflite_sqlcipher |
