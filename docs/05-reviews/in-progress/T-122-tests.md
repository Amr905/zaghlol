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