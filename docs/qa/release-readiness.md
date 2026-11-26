# Release readiness

Zaghlol, `main` @ `bc5b9d1d`. Audit date: 19 Nov 2026.

## Recommendation: NOT READY for release

The code that could be tested on a host machine is in good shape: every existing automated test passes and the backend held up under independent API and database testing. On the emulator, onboarding, navigation, both languages and both themes work. It is not releasable because the core journeys with data (SMS capture, saving transactions, budgets, purchases, backup) were never run on a device, a release build cannot verify any backend response, and 19 planned tasks, including the security assessment and both store pipelines, are still open.

## 1. Overall implementation status

| Measure | Value | Source |
|---|---|---|
| Tasks reported DONE | 167 of 186 (89.8 %) | `docs/implementation-status.md` (project's own claim, not re-verified per task) |
| Tasks IN_REVIEW / TODO / BLOCKED | 3 / 12 / 4 | same |
| Open follow-ups | 85 in the lane table; 307 rows in the itemised table | same |
| Screens in the inventory with an implementation by name | 46 of 46 | `grep` of screen IDs |
| App-facing API operations with a route | 14 of 14 | route list |
| Admin API operations in the contract without a route | 2 | BUG-003 |

## 2. Requirements coverage

312 requirement IDs in the SRS. Detail: `requirements-coverage.md`.

| Status | Count | Share |
|---|---|---|
| PASS | 233 | 74.7 % |
| FAIL | 3 | 1.0 % |
| BLOCKED | 73 | 23.4 % |
| NOT IMPLEMENTED | 2 | 0.6 % |
| NOT TESTED | 1 | 0.3 % |

Read the 74.7 % with care. A PASS means the tests in the feature's suites were executed and passed, mostly at component level on Linux. The mapping from requirement to suite is by feature folder, so it shows the feature is exercised, not that each sentence of the requirement was individually proven. 37 requirements were also observed on an emulator, click-only; the rest were not seen on a device. The 72 BLOCKED ones are those whose acceptance criterion needs a device, a store, real bank samples, a deployed backend or a human reviewer; they include most of capture, purchases, backup to the cloud, app lock and all performance targets.

## 3. Test execution statistics

| Group | Executed | Passed | Failed | Skipped / other |
|---|---|---|---|---|
| Existing suites (app, packages, tools, backend) | 10,547 | 10,547 | 0 | 39 skipped |
| New API and database cases | 151 | 130 | 10 | 10 withdrawn, 1 blocked |
| Extra live checks | 5 | 4 | 1 | |
| Benchmark-tagged tests (host timing) | 21 | 21 | 0 | `db-platform` benchmarks not run |
| Static checks | 7 | 6 | 1 | `flutter analyze` |
| On-device checks on the emulator | 36 | 32 | 4 | click-only; typing, swiping and server steps blocked |

Not run at all: Android Gradle tests and lint, iOS tests, device integration tests, device benchmarks, container image checks. Host benchmarks are far inside the phone targets (for example 0.06 ms per parsed message against 10 ms), which lowers but does not remove the performance risk. GitHub Actions shows these green on the same tree; that was read, not re-verified.

## 4. Critical and high-severity bugs

| ID | Severity | Summary |
|---|---|---|
| BUG-001 | HIGH | A release build embeds no backend public key, so it rejects every sync and never grants Gold. Intentional until production keys exist (T-140), but a release blocker |

No CRITICAL bug found. Medium: BUG-002 (API aborts on shutdown), BUG-003 (two operator endpoints missing), BUG-015 (paywall stuck loading), BUG-016 (Flutter default app icon). Low: BUG-004…009, BUG-017, BUG-018. See `bug-report.md`.

## 5. Security findings

- **Verified good:** token handling, closed request schemas that reject financial fields, signed responses, least-privilege database logins, immutable audit log for the admin login, rate limiting, refusal to start with dev features in Production, no secrets in the repository, no tracking SDKs.
- **Open:** BUG-001 (trust anchors). Operator sign-in path untested because no identity provider is chosen (T-136). 
- **Not assessed:** on-device encryption, key storage, app lock and screenshot protection as they behave on a phone; native Kotlin and Swift code; MobSF, ZAP and penetration testing (T-175 not started).

## 6. Missing functionality

| Item | Reference |
|---|---|
| Operator list of bank requests; daily-active metrics endpoint | BUG-003, FR-BE-10 |
| Operator command-line tool and support runbook | T-137 TODO |
| Production hosting, KMS keys, deployment | T-140 BLOCKED |
| Gold price feed provider and key | T-127 / BLK-03 |
| Statement import: review UI, real-statement validation | FU-262, T-156, T-157 BLOCKED |
| Animated mascot (Rive file) | T-088 TODO |
| Quick-add / lock-screen widget (priority C) | FR-WID-02 |
| Store pipelines, listings, Data safety and SMS declaration | T-176, T-177 TODO |
| Native-speaker copy review | T-058 TODO |
| Device end-to-end suites | T-172 TODO |

## 7. Known risks

1. **Only partly run on a device.** Onboarding, permissions, navigation, settings, languages and themes were seen on an emulator. SMS capture (including with the app killed), saving data, budgets, purchases and backup were not.
2. **Parsing accuracy is unproven on real messages.** 197 registry entries are marked `synthetic-unverified`; real samples are still awaited (BLK-02). This is the core value of the product.
3. **Google Play SMS permission.** Approval of the "SMS-based money management" declaration is outside the team's control.
4. **Purchases untested against real stores.** Only the fake-store path ran.
5. **iOS untested entirely** in this audit.
6. **Requirements drift.** Product decisions since 13 Nov live in `PO_DECISIONS.md`, not in the SRS; two requirements already fail as written (BUG-006).
7. **Legal.** PDPL licence and hosting region undecided (BLK-04).
8. **Volume of open follow-ups** (85 to 307 depending on the table).

## 8. Conditions to change the recommendation

1. Finish the device journeys in `test-plan.md` §7 that need typing (run the emulator in its own window so it can be granted full control), on at least one real Android phone too; run the iOS equivalents.
2. Close BUG-001 after T-140; fix BUG-002 and BUG-003.
3. Validate parsing against real samples for the launch banks.
4. Complete T-175 (security assessment) and T-172 (device suites).
5. Verify a purchase, a refund and a restore against Play and App Store sandboxes.
6. Bring the SRS in line with the PO decisions, then re-run this coverage.

## 9. Next step

Per the audit brief, nothing is fixed until these findings are reviewed and approved. After approval the confirmed bugs become tasks:

| Bug | Proposed class | Proposed implementer | Re-test |
|---|---|---|---|
| BUG-001 | C4 (keys, entitlements) | Opus, `flutter-core-engineer`, after T-140 | release-build sync and Gold on a device |
| BUG-002 | C2 | Sonnet, `backend-engineer` | SIGTERM exit-code test |
| BUG-003 | C2 | Sonnet, `backend-engineer` | API-127, API-128 plus an operator-token case |
| BUG-004, BUG-005 | C2 | Sonnet, `backend-engineer` | API-014, 015, 048, 049, 083, F-04, F-23 |
| BUG-006, BUG-008 | C1 (documents) | Haiku, `boilerplate-engineer`, with PO sign-off on the SRS text | coverage regeneration |
| BUG-007 | C1 | Haiku | `flutter analyze` on a clean clone |
| BUG-009 | C4 (data migration) | Opus, `backend-engineer` | D-03 |
| BUG-015 | C3 (billing UI, failure path unclear) | Sonnet with a short Opus design note, `flutter-ui-engineer` | paywall on an emulator without Play billing |
| BUG-016 | C1 (assets) | Haiku, `boilerplate-engineer` | launcher on Android and iOS |
| BUG-017, BUG-018 | C2 | Sonnet, `flutter-ui-engineer` | About on a fresh install; filter sheet golden |
