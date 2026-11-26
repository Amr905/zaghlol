# Test execution, 26 Nov 2026

Target: `Amr905/zaghlol` `main` @ `89583b27` (merge of PR #125, batch 76). Catalogue: `test-cases.md` / `test-cases.csv` (621 cases). No application code was changed.

## 1. Result in one table

| Group | Cases | PASS | FAIL | BLOCKED | NOT RUN | Not implemented | N/A |
|---|---|---|---|---|---|---|---|
| Requirements (FR, BR, NFR) | 316 | 239 | 1 | 73 | 0 | 1 | 2 |
| Edge cases (EC) | 73 | 62 | 0 | 8 | 3 | 0 | 0 |
| SRS decisions (D) | 88 | 44 | 0 | 12 | 30 | 0 | 2 |
| PO decisions (`PO_DECISIONS.md` Part 1) | 68 | 46 | 0 | 0 | 22 | 0 | 0 |
| User stories of 25 Nov (US-P01…P11) | 11 | 1 | 0 | 0 | 10 | 0 | 0 |
| QA-written: odd behaviour, live backend, device journeys | 65 | 36 | 6 | 3 | 20 | 0 | 0 |
| **Total** | **621** | **428** | **7** | **96** | **85** | **1** | **4** |

## 2. How strong each PASS is

| Level | Meaning | Cases |
|---|---|---|
| I | An independent test QA wrote from the SRS example passed | 46 |
| D (+L) | Tests that cite the requirement, rule or decision ID passed (developer tests, component level) | 107 |
| L | Live check against the running backend or a direct file check | 23 |
| K | No test cites the ID; tests whose names match the case passed (QA keyword map) | 28 |
| T | Tests of the task that implemented a PO decision passed | 38 |
| via linked | A decision whose linked requirement cases all pass | 12 |
| S | No test cites the ID; only the feature's suite passed | 174 |

The 174 level-S cases are the soft spot: the feature is tested, but nothing ties a test to that exact sentence. Nothing in this run was executed on a phone.

## 3. What was executed

| Run | Passed | Failed | Could not run here | Skipped |
|---|---|---|---|---|
| Existing automated suites (app unit, widget and golden; packages; tools; backend on a real PostgreSQL 17) | 11,984 | 0 | 166 | 44 |
| Independent QA spec tests (new, `packages/zaghlol_parsing/test/qa/qa_independent_spec_test.dart`) | 40 | 1 | 0 | 0 |
| Live API black box (`api_blackbox.py`) | 92 | 0 new | 9 known, see below | |
| Live API and database follow-up (`api_db_followup.py`) | 45 | 0 new | 5 known, see below | |
| Static: `flutter analyze`, `dart format`, backend build with warnings as errors, OpenAPI lint | 4 | 0 | | |

- **166 "could not run here":** backend key-management tests (File KMS, OpenBao, host secrets: 163) and 3 tests that need Docker. The key tests refuse any key folder whose parent is not owned by root or the current user; in this sandbox `/` is owned by `nobody`, so the guard fires before the test starts. This is the sandbox, not a product failure, but it means those tests are unverified here.
- **14 live checks that did not pass, none new:** bank-request values dropped silently (API-048, API-049, F-04: now documented as intended); my own earlier call used the sync window (API-063…065); expectation or rate-limit effects (API-100, 104, 106, 107, F-12, F-29, D-04); one blocked without a published catalog (F-07).
- **Fixes from the first audit confirmed live:** API exits 0 on SIGTERM (BUG-002); both admin routes exist (BUG-003); `Zaghlol-App` is required (BUG-004); a 513-character purchase token is 400 (BUG-005); negative catalog version refused by the database (BUG-009); `flutter analyze` is clean (BUG-007).

## 4. Failures (7 cases, 6 bugs)

| Case | Bug | Severity | What | Evidence in this run |
|---|---|---|---|---|
| TC-X-XFR-01 | BUG-019 (new) | Low | Transfer pairing returns "ambiguous" when the pool contains the leg itself, against its own documented contract. The app's caller leaves the leg out, so users are not affected today | independent test failed |
| TC-X-DOC-01 | BUG-020 (new) | Low | D-67, D-68, D-69 and D-70 each name two different decisions in the SRS | file check |
| TC-FR-GOLD-01, TC-X-UI-06 | BUG-015 | Medium | Gold paywall stuck on "Loading prices…" | seen on the emulator on the 19 Nov build; code unchanged; not re-run on a device |
| TC-X-UI-07 | BUG-016 | Medium | App icon is Flutter's default on Android and iOS | re-checked on this commit (same file hashes) |
| TC-X-UI-08 | BUG-017 | Low | About screen: two identical unlabelled "not updated yet" lines | re-checked in the code on this commit |
| TC-X-UI-05 | BUG-018 | Low | Card-filter sheet under the tab bar and Add button | seen on the 19 Nov build; sheet helper unchanged; not re-run on a device |

## 5. Not executed

- **96 BLOCKED:** need a phone or emulator with typing, an iPhone, store sandbox accounts, real bank samples, a deployed backend or a human reviewer.
- **85 NOT RUN:**
  - 30 SRS decisions and 22 PO decisions that no test cites and that link to no requirement (several are process or infrastructure decisions; they need a review, not a test).
  - 10 of the 11 user stories of 25 Nov: no test cites them yet.
  - 20 device cases QA wrote (double-tap save, rotation, back button, restart, journeys with data).
  - 3 edge cases with no matching test: EC-09 multi-part SMS (handled in native Android code, whose tests were not run here), EC-57 bank notification in another language, and one more listed in the catalogue.
- **Android native tests, iOS tests, device integration tests, container checks:** not run (no Android SDK, macOS or Docker here).

## 6. Next steps to finish execution

1. Emulator in its own window (not inside Android Studio) with a current `devSms` debug build, so the 20 device cases and the SMS month-story (`docs/qa/sms-emulator.md`) can run.
2. Decide which of the 52 uncited decisions are testable; give each a test that cites its ID, or mark it as process-only.
3. Tests that cite US-P01…P11 as those stories are built.
4. Run the 166 key-management and Docker tests where they can run (CI or the PC runner) and attach the result.
