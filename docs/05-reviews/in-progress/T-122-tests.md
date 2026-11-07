## Test verification: T-122 (branch `task/T-122-ef-model` @ `0b73ac5`)

**Method.** I read the diff and every test file under `backend/tests/Zaghlol.Infrastructure.Tests`, plus `ReadinessTests`, `ZaghlolTestDatabase`, `PostgresDatabaseReadiness`, `GrantMatrix`, `InitialCreateSql` and `bootstrap-roles.sql`. I did not re-run the suite locally.

**Limit on CI evidence.** The `backend-ci` job "build, format, test" (job 128344295567) logs only per-assembly totals, because the test logger is not verbose. Per-test PASS therefore rests on those totals, on "no failures", and on reading the assertions. The logged results are:
- Infrastructure: 168 passed, 0 failed, 0 skipped (13 s).
- Api: 7 passed.
- Contract: 35 passed.
- Application: 3, Workers: 3, Ops: 2.
- `dotnet ef migrations has-pending-model-changes` printed "No changes have been made to the model since the last migration."
- Build with `-warnaserror` and `dotnet format --verify-no-changes` succeeded.

### Criterion to test to evidence

| Criterion / design-note requirement | Test | Evidence |
|---|---|---|
| Migration applies on empty PG17 | `ZaghlolTestDatabase.StartAsync` (used by `SchemaFixture`) | Infra 168/0 failed; the fixture throws if the migration fails. |
| Schema equals doc column by column, all 25 tables (name, type, NOT NULL, DEFAULT, identity), extras flagged | `SchemaTests.EveryColumnMatchesTheDocumentByNameTypeNullabilityDefaultAndIdentity`, `EveryDocumentedTableExistsAndNoOtherTableDoes` (asserts 25 tables, so a parser regression fails) | CI green. |
| The six named tables diffed | `AcceptanceTablesAreDocumentedAndDiffed` (theory ×6) | CI green. It is a column-count check only; the real diff is the test above. |
| `v_entitlements` columns | `EntitlementViewHasTheDocumentedColumns` | CI green. |
| Privacy CHECKs, digit run (≥6 digits), length caps (65 rejected, 64 accepted, 5 digits accepted) | `CheckRejectsTheRow` cases for `merchant_contributions` and `bank_requests`; `ContributionsJustInsideThePrivacyLimitsAreAccepted` | CI green. The SQLSTATE `23514` and constraint name are asserted. |
| Forbidden columns | `NoColumnCanHoldARawSeatKeyOrderIdNonceOrDeviceIdentifier` (denylist regex, exactly two allowed exceptions) | CI green. |
| `purchase_seats` CHECKs (holder without proof; not on a whole hour; 3 rebinds; `last_moved_at` without `next_move_at`) | `CheckRejectsTheRow`: "holder without proof", "next_move_at not on a whole hour", "three recent rebinds", "last_moved_at without next_move_at" | CI green. These also have the reverse and boundary cases (one microsecond past the hour; `next_move_at` without `last_moved_at`; proof without holder). Positive cases: `TwoRecentRebindsAndAWholeUtcHourAreAccepted` and `AWholeUtcHourIsAcceptedInASessionWithAHalfHourTimeZoneOffset`. |
| `purchases` link pair, both directions | Cases "account_id without account_linked_by" and "account_linked_by without account_id" | CI green. |
| Account delete clears the link and keeps `attach_reclaim_used_at` | `CascadeTests.DeletingAnAccountClearsTheLinkAndItsSourceButKeepsTheReclaimMarker` | CI green. It runs as `zaghlol_api` and covers both `signin` and `support` links. It also asserts `install_id` is kept. |
| Install delete: claimants and attest key gone; seat vacated; `device_key_hash` and `device_key_trusted` kept | `DeletingAnInstallCascadesClaimantsAndAttestKeysAndVacatesTheSeatKeepingTheDeviceKey` | CI green. It runs as `zaghlol_worker`, which proves SECURITY DEFINER. It also checks that another install's claimant survives, and the `account_installs` and `purchases.install_id` effects. |
| Purchase delete cascades | `DeletingAPurchaseDeletesItsSeatEventsAndClaimants` | CI green. |
| R5-2 default false, NOT NULL, comment equals doc and model | `SeatKeyTrustedDefaultsToFalseAndCarriesTheDocumentedR52Comment` | CI green. |
| R5-7 | `SupportLinkNoticeIatSitsNextToSupportLinkNoticePending` | CI green. |
| FU-003 readiness with real stop/start | `Api.Tests.ReadinessTests.HealthIs503...` | CI green (Api 7/0). It checks the 503 problem+json, the `UPSTREAM_UNAVAILABLE` code, `no-store`, and recovery within 5 s. |
| 1 s timeout, 2 s cache, single flight | `ReadinessProbeTests.ProbeTimesOutAfterOneSecondCachesForTwoSecondsAndRunsOnlyOnceAtATime` | CI green. |
| Every CHECK (39) has a negative case | `CheckConstraintTests.CheckRejectsTheRow` (about 60 cases), `EveryCheckConstraintInTheSchemaHasANegativeCase`, `EveryDocumentedCauseIsAccepted` (17 valid causes), `TheBaseRowIsValidSoEachNegativeCaseFailsOnlyForItsOverride` | CI green. |
| Grants matrix | `GrantTests.TableAndColumnPrivilegesEqualTheGrantMatrix`, `RoleIsDenied` (24 cases), `RoleIsAllowed` (6), `MigratorOwnsTheSchemaAndEveryObjectInIt`, `OnlyTheFourGroupsMayUseTheSchemaAndNobodyMayUsePublic`, `TriggerFunctionsAreSecurityDefiner...`, `LoginsBelongToExactlyOneGroupAndHaveNoAttributes`; `ModelTests` invariants | CI green. `app_rw` getting `42501` on `UPDATE audit_log` and `CREATE TABLE` is covered. |
| Migrate twice is a no-op | `MigrationTests.MigratingAgainIsANoOp` | CI green. It compares the object count and the history row count. The fixture also runs the bootstrap script twice. |
| Down to zero, then up | `MigrationRoundTripTests.DownToZeroRemovesEverythingAndUpRestoresIt` (own container) | CI green. |
| Drift | `MigrationTests.TheModelHasNoChangesMissingFromTheMigrations` plus the CI step | The CI log shows "No changes". |
| No pgcrypto, nothing in `public`, no floating-point properties | `OnlyPlpgsqlIsInstalled...`, `NothingIsCreatedInThePublicSchema`, `NoPropertyIsFloatingPoint`, `PricesAreNumericWithTheDocumentedPrecision` | CI green. |

All eight acceptance criteria and all the design-note test items have a corresponding test, and CI is green. The DoD "RTL / UI" item does not apply.

### Assessments

**2. Schema-vs-doc test: not circular for what it covers, but it has a blind spot.**
- The doc is the independent oracle and the DB is built from the EF migration. It is not the model diffing itself.
- A column missing from both doc and model is not caught. That is inherent in diffing against the doc. Mitigation: `SchemaTests` explicitly checks `seat_key_trusted` and `support_link_notice_iat`, and I grepped the doc: the R3 to R5 columns named in the task are all present.
- Gap: the task lists `response_body_enc`. My grep for it at the start of a line returned 0, but line 228 shows it is defined inline, so the doc has it. This is not a defect.
- The doc was edited in the same commit as the code (+4 lines: hardening bullet and index list). The implementer could shape the doc to the implementation. Only a reviewer reading the doc diff protects against that.
- Not diffed against the doc: PK, UNIQUE, FK targets, ON DELETE actions, CHECK predicate text, and most indexes. The doc lists six indexes by `CREATE INDEX`, and the retention indexes are asserted from a hand-written list in the test. CHECK predicates are pinned only by the negative tests.
- The parser is sensitive to doc formatting. The table-count assertion catches silent loss of a table. A column parsed incorrectly would fail loudly.

**3. CHECK coverage guard: real.**
- It compares `pg_constraint` (`contype='c'`) names with the case table in both directions, plus a hard-coded count of 39. A new unguarded CHECK fails it. A stale case also fails.
- Each case asserts the constraint name, so a case cannot pass because of a different CHECK.
- Weaknesses:
  - The guard checks names only. A multi-clause CHECK (for example `code_lengths`) needs a case per clause, which the author supplied.
  - The magic number 39 needs a manual bump, which is acceptable.
  - NOT NULL is not covered, but it is covered by the column diff.

**4. Grants tests: they catch excess as well as missing privileges, but the oracle is partly circular.**
- `TableAndColumnPrivilegesEqualTheGrantMatrix` asserts both `expected - actual` and `actual - expected` empty. It reads table and column ACLs including PUBLIC, and it ignores the owner only.
- The matrix that renders the SQL is the same matrix that is compared (`GrantMatrix.Current`). A wrong privilege in the matrix therefore passes.
- The independent checks are `ModelTests`: audit_log is append-only, `app_rw` has no admin-table writes, `ops_ro` has select-only with no sensitive columns, and every table appears in the matrix. There are also the 24 live denial probes.
- Not asserted: sequence privileges, database-level CONNECT/TEMP, default ACLs, or membership beyond "one group per login".
- No test asserts positive writes for `app_rw` and `worker_rw` beyond what the fixtures exercise implicitly.

**5. Readiness timing: low to moderate flake risk.**
- `ManualClock` overrides only `GetUtcNow`. Timers stay on the real clock, so the 1 s timeout is real.
- The assertions are 0.8 s to 5 s for the first probe and under 500 ms for the cached call. The connection count is checked after a 1 s wait, so the accept loop has time to run.
- Eight concurrent callers share one probe via the semaphore. The expected count of 2 is deterministic.
- Residual risks:
  - The count is read right after the probe, with an asynchronous accept loop.
  - The cache window is checked at 1.9 s and 2.1 s of manual-clock time, which is robust.
  - `FreeTcpPort()` has a time-of-check/time-of-use race in `ReadinessFixture`.
  - The 5 s recovery budget includes container start, the 2 s cache and a 1 s probe. It passed on CI, but it is the likeliest flake on a slow runner.
  - The 15 s poll for the 503 is generous.
- Not tested: the success path being cached for 2 s, caller cancellation not poisoning the cache, and `dataSource.Clear()` on failure.

**6. Isolation.**
- All Infrastructure schema tests share one container via a collection fixture. Execution is sequential, and the rows use random UUIDs, random store keys and random catalog versions. I found no order dependence.
- `MigrationRoundTripTests` and the Api readiness fixture each use their own container, which is correct for destructive tests.
- Latent risk: the `RoleIsDenied` cases include `DELETE FROM zaghlol.purchases` and `TRUNCATE zaghlol.installs`. If a grant regressed, they would wipe shared data and cascade failures into other tests. That only happens when the suite is already failing.
- Count-based assertions apply to schema objects, not rows, so they are safe.

### Gaps

| # | Gap | Severity |
|---|-----|----------|
| G1 | No UNIQUE or PK violation test (SQLSTATE `23505`). Untested: `(provider, provider_subject)`, `(store, store_key)`, `(store, external_id)`, `app_attest_keys.install_id` ("one key per install"), `catalog_merchants.canonical`, the contribution unique triple, `operators.oidc_subject`, the composite PKs of `seat_claimants`/`idempotency_records`/`replay_guard`. A dropped constraint would pass; doc-vs-DB does not diff constraints. | Medium |
| G2 | FK actions are not exhaustively tested. Covered: installs and purchases children, and the accounts trigger. Not covered: `account_installs` on account delete (CASCADE), `idempotency_records.account_id`, the catalog FKs (NO ACTION: merchant to category, alias and keyword to merchant, category self-parent) deleted while referenced (`23503`), and orphan inserts. Nor is the non-trigger path tested as a restricted role (for example, `ops_rw` deleting an install is denied). | Medium |
| G3 | The two CHECK pairs are exercised on INSERT only. The risky production path is UPDATE of one column by `ops_rw`, which holds column grants on the support-correction columns. There is no test that an `ops_rw` `UPDATE purchases SET account_linked_by=NULL` alone, or `UPDATE purchase_seats SET next_move_at=NULL` alone, is rejected, nor that a paired update is accepted. The triggers fire on DELETE only, so "some paired columns change" is not a trigger issue. Related trigger gaps: an install-delete trigger case where other seats and other accounts' purchases are untouched; multiple purchases per account (the signin and support case covers two, but not unrelated accounts); and deleting an install that holds no seat. | Medium |
| G4 | Grants oracle is circular (matrix to SQL to matrix). The semantic invariants in `ModelTests` and 24 probes mitigate it, but the privileges of `app_rw`/`worker_rw` for the write paths used by T-124/T-135/T-139 are not independently asserted. Sequences and database-level privileges are not checked. | Medium |
| G5 | Digit-run CHECK uses `[0-9]` and is not tested with Arabic-Indic digits (`٠-٩`). A 6+ digit run in Arabic-Indic digits would pass. CLAUDE.md §2.5 requires normalization at input; the DB CHECK is only a backstop, but there is no test asserting either way (normalized upstream, or rejected). Also untested: a phone number with a separator, and NULL columns, though those columns are NOT NULL. | Medium (privacy) |
| G6 | NULL handling in length CHECKs: nullable hash columns (`registration_key_hash`, `seat_key_hash`, `registration_body_sha256`, `device_key_hash`) accept NULL, which the base rows implicitly prove. `NOT NULL` columns are guarded by the column diff. No explicit test says "NULL passes the length CHECK, wrong length fails", so a future change to the nullability would be flagged only by the doc diff. | Low |
| G7 | `audit_log` privacy CHECK covers top-level keys only: `{"x":{"email":...}}` and `"Email"` pass. The doc defines it as top-level, so this is a design limit rather than a defect. No test documents the limit. | Low |
| G8 | Doc-vs-DB does not compare CHECK predicate text, index definitions (only 16 names/fragments), column comments other than `seat_key_trusted`, or view definition text (columns only). | Low |
| G9 | Readiness: the 5 s recovery budget and the `FreeTcpPort` race are the flake risks. No unit test for the success-path cache or cancellation behaviour. Container stop/start timing is CI-runner dependent. | Low |
| G10 | CI logs have no per-test names, so the per-test PASS evidence is indirect. Recommend a verbose or trx summary step. | Low |
| G11 | Hard-coded `39` in the CHECK guard. Intentional; it needs a manual bump. | Info |

### Verdict

**TESTS_SUFFICIENT.**

Every acceptance criterion and every design-note test item maps to a test. The CI run is green: Infrastructure 168/168, Api 7/7, and the model drift check clean. The CHECK guard and the doc diff are real. Excess grants are detected.

I recommend G1 to G5 as follow-up tests, by the T-122 closing review or in T-124/T-184, whichever first touches those columns. None of them blocks the acceptance criteria.

---

## Test verification, round 2 (delta): T-122 @ `d5943be`

**Evidence.** backend-ci run 42407789072, job "build, format, test" (128509135065), plus a read of the new and changed tests. All 5 jobs are green. Totals: Infrastructure 341/0 failed (13 s), Api 7/0, Contract 35, Application 3, Workers 3, Ops 2 (391 total). `has-pending-model-changes` reports "No changes". The log shows only per-assembly totals, so per-test PASS evidence is indirect, as in round 1. I did not run anything locally.

I was not given the F1 to F12 definitions. I mapped them from the SQL, the doc diff, the test comments and the `GrantTests` comments:

| Finding | What I took it to mean |
|---|---|
| F1 | `ops_ro` column hiding |
| F2 | privacy CHECK widening (digit runs in every script, `@`, slug codes) |
| F3 | `audit_log` details and target CHECKs |
| F4 | `audit_log` RLS |
| F8 | format CHECKs |
| F9 | invariant triggers |
| F10 | `app_rw` and worker column narrowing |
| F11 | login guard |
| F12 | forbidden-column denylist |

### 1. G1 to G3: closed

| Gap | Test | Verdict |
|---|---|---|
| G1 (unique / PK, `23505`) | `ConstraintBehaviourTests.ASecondRowWithTheSameKeyIsRejected` (13 cases) | Closed. It asserts SQLSTATE and constraint name. Cases: accounts, purchases, store_notifications, app_attest_keys (unique install and PK), catalog_merchants, contributions, operators, seat_claimants, purchase_seats, idempotency_records, replay_guard, bank_requests. |
| G2 (FK actions) | `AnOrphanRowIsRejected` (6, `23503`), `AMerchantNeedsAnExistingCategory`, `DeletingAnAccountCascadesItsInstallLinks`, `ACatalogRowStillReferencedCannotBeDeleted`, `ACategoryWithAChildCategoryCannotBeDeleted` | Closed. The NO ACTION deletes run as the owner, so only the FK can stop them. |
| G3 (single-column corrections) | `ASupportDetachMustClearTheLinkAndItsSourceTogether`, `ASupportSeatMoveMustKeepTheSeatPairsConsistent` (as `ops_rw`); `DeletingAnInstallLeavesOtherSeatsAndInstallsUntouched`; `DeletingAnInstallWithoutASeatSucceeds` | Closed. Both halves are rejected, and the paired update is accepted. |
| G5 (Arabic-Indic digits) | 26 contribution cases, including Arabic-Indic, Extended, fullwidth, mixed-script, spaced, dashed, dotted, `@`. `ValuesJustInsideTheLimitsAreAccepted` adds accepted values such as Arabic-digit `١٢٣٤٥` (5 digits) and `shop 12 34 5`. | Closed. |
| G7 (audit nesting and case) | 7 audit cases: nested, in an array, `Email`, `ORDER_ID`, `e-mail`, `@` in another value, `@` in target. | Closed. |
| G4 (grants circular) | Partly addressed. `GrantTests` now has about 30 new denied cases and a database-level CONNECT ACL equality test. `ModelTests` pins the hidden columns and the `app_rw`/worker narrowing. `InitialCreateGoldenTests` pins SHA-256 of each frozen block. | Better. The comparison oracle is still the matrix itself (see "Remaining gaps"). |

### 2. Security fixes: does a negative test fail if the fix is reverted?

| Fix | Negative test | Fails on revert? |
|---|---|---|
| F1 `ops_ro` can't read email, provider_subject, store_key, linked_purchase_token, store_notifications.store_key | `GrantTests.RoleIsDenied` ×6 live `42501` probes; `ModelTests.ReadOnlyOperatorsNeverSee...` (8 columns); matrix equality | Yes. |
| F2 privacy CHECK widening | `CheckConstraintTests` cases above, with constraint names asserted | Yes. The accepted-value cases pin false positives. |
| F3 audit CHECK depth, case, `@` | 7 cases plus `AuditDetailsWithTheDocumentedShapesAreAccepted` (the documented support-move shape is still accepted) | Yes. |
| F4 audit RLS | `AuditLogSecurityTests`: exact policy list and RLS flag. The worker cannot delete a fresh row (returns 0 rows). Age theory ×7. `OperatorsAppendFreshRowsButCannotBackdateThem` (`42501`). `ARowMustNameARealOperator` (FK). `ReadersSeeTheLog`. | Yes. A removed policy or RLS flag fails the exact-policy test, and the fresh-row delete would return 1. |
| F8 format CHECKs | 5 `app_version` cases, `daily_active_counts`, `last_error` ×2, `store_key` length ×2, `country` ×3, plus accepted values (including `1.4.0-beta.1`, `1.4.0+42`) | Yes. |
| F9 invariant triggers | `InvariantTriggerTests`: seat_key_hash replace and clear rejected, same value allowed, tombstone allowed; trusted true to false rejected; `attach_reclaim_used_at` clear or move rejected as both `api` and `admin`; `23514` plus constraint name. `GrantTests.TriggerFunctions...` now lists 4 functions. | Yes, with one hole below. |
| F10 `app_rw` / worker column narrowing | `GrantTests` denied: `app_rw` can't update `dispute_frozen_until` or `daily_active_counts`, can't SELECT other installs' contributions; the worker can't update `token_hash`, `seat_key_trusted`, `account_id`, `account_linked_by`. `ModelTests` pins the matrix; allowed probes pin the worker's legitimate columns. | Yes (grant equality also guards). |
| F11 login guard | `DatabaseRoleGuardTests`: 9-row accept/reject matrix, superuser rejected, host stop with the migrator login, right login keeps running, readiness 503 for the wrong login. | Mostly. Gaps below. |
| F12 denylist | `TheDenylistCatchesTheseNames` ×12 and `TheDenylistLeavesTheseNamesAlone` ×3, plus the schema-wide column scan | Yes. Note the regex `_payload` and `raw_`; the "leave alone" cases show `payload_digest` is intentionally untouched. |

### 3. Isolation change (Serilog)

- Cause of the flake: `Log.Logger` is process-wide and each `WebApplicationFactory` host replaces it. `ApiTests` and `ReadinessTests` were separate collections, so xunit ran them in parallel, and `RequestBodiesAreNeverLogged` could see no logs.
- `ApiHostGroup` has `DisableParallelization = true`, and both classes use it. xunit runs non-parallel collections alone, one after another, so each class's fixture and tests run without another host being built or replaced.
- The only two classes in `Zaghlol.Api.Tests` that build a host are those two (no other `WebApplicationFactory` in the folder). `ContractApiFixture` is in another assembly, hence another process. This addresses the cause for this test assembly.
- It is a workaround of the process-global logger and not a fix of it. A future third host-building class has to remember to join `ApiHostGroup`. Suggest a comment, or a guard test that fails when a class using a host fixture lacks the collection.
- `ApiHostGroup` has no assertion enforcing membership.

### 4. Determinism

- **RLS cases.** Age margins are 10 days for the 1-year rule (360 vs 370), 5 days below and 5 days above for the 3-year rule (1090 vs 1100), and `interval '1 year'` / `'3 years'` is at most 366 / 1096 days. The values are fixed offsets from `Rows.Now()` (the owner inserts backdated rows), so there is no wall-clock sensitivity. The "backdate" test uses a two-year offset. Not tested: the +1 minute upper bound of the append policy, so a future-stamped row is untested.
- **Readiness timing.** The black-hole server is now shared (`BlackHoleServer`). Timer waits are 1 s with assertions of 0.8 to 5 s; the cache window is moved with a manual `GetUtcNow` only. The accepted-connection count is read after the 1 s timeout. The residual risk is a loaded CI runner, but the margins are wide. `FreeTcpPort` TOCTOU in `Api.Tests.ReadinessFixture` is unchanged. The 5 s recovery budget in `HealthIs503...` is unchanged and still the likeliest flake.
- **Role guard host test.** Success path awaits `StopApplication` with a 20 s ceiling; the failure case is slow but not flaky.
- **Pool test.** `AProbeTimeoutLeavesTheAppPoolAlone` depends on Npgsql's lazy `DISCARD ALL` leaving `application_name` visible on the idle backend. That behaviour is documented in the comment and passed in CI. It is a driver-behaviour dependency, but it is deterministic here. The test is nearly tautological, though: the probe source and the App source are independent objects, so one cannot affect the other. The DI test `ReadinessUsesItsOwnOneConnectionPool...` (`NotSame`, `MaxPoolSize == 1`) is the one that would catch a revert.
- **Isolation.** The shared container is still used, with random IDs. The new audit rows accumulate, but only `>= 1` and per-id counts are asserted.

### Remaining gaps

| # | Gap | Severity |
|---|-----|----------|
| N1 | **Trigger tombstone hole (production).** `installs_before_update` allows any change of `seat_key_hash` when `NEW.deleted_at IS NOT NULL`. `UPDATE ... SET deleted_at = now(), seat_key_hash = <other value>` is therefore accepted. The doc says the tombstone clears it. The test only exercises the clear-to-NULL case, so this is untested and wrong in principle. The trigger should require `NEW.seat_key_hash IS NULL` when the tombstone exempts the change. Which logins can reach it is limited by column grants (worker has `deleted_at` and `seat_key_hash`). | Medium |
| N2 | Role-guard group tests miss the "member of own group plus another" case (extra membership) and the non-superuser privileged flags (`createrole`, `createdb`, `bypassrls`). Only `ops_ro` under App, `worker` under App and similar are covered. | Low to Medium |
| N3 | The grants oracle is still the matrix. Mitigated by the invariant tests, the live probes, the golden hashes and the DB CONNECT ACL. Sequences are still unchecked. | Low |
| N4 | `AProbeTimeoutLeavesTheAppPoolAlone` is tautological on its own (see Determinism). | Low |
| N5 | Golden test hashes: a pinned hash blocks any later edit, including legitimate comment fixes. It is also circular for correctness: it asserts the file is unchanged, not that it is right. That is its stated purpose. | Info |
| N6 | No test that the RLS append policy rejects future-dated rows, or at the exact one-minute boundary. | Low |
| N7 | `ApiHostGroup` membership is not enforced for future host-building tests. | Low |
| N8 | No explicit test that other login-guard role reasons (`RejectMigrator` via membership rather than being the owner) fire. `migrator` hits `RejectOwner` first. | Low |
| N9 | From round 1, still open: sequence privileges, success-path readiness caching, and cancellation behaviour. | Low |

### Verdict: **TESTS_SUFFICIENT**

G1 to G3 and the other round-1 requests (G5, G7) are closed. Every security fix I could map has a negative test that fails when the fix is reverted. The isolation change addresses the cause for this test assembly. The timing cases use wide margins.

Recommend fixing N1 before merge (production trigger plus one added test: `deleted_at` set and `seat_key_hash` replaced with a different value must fail), and adding N2's extra-membership case. Neither changes the verdict on test sufficiency, but N1 is a real weakness that the current tests do not detect.
