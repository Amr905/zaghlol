# Batch review — batch 55 (T-205, T-206, T-207)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, CLAUDE.md §6) |
| Date | 2026-11-22 |
| Diff | `git diff origin/main...batch/2026-11-22-55` (merge `eed38a25`) |
| Context | D-80: MonsterASP.NET (Windows/IIS shared host, one site) + Aiven for PostgreSQL |
| Overall | **CHANGES_REQUESTED**: one major in T-206; T-205 and T-207 APPROVED |

## Checks run

| Command | Result |
|---|---|
| `dotnet build Zaghlol.sln -warnaserror` | 0 warnings, 0 errors |
| Infrastructure tests `~Kms` or `~DatabaseSettings` (without `OpenBaoLive` and `ManagedPostgres`) | 315 passed, 1 skipped (G2 off-Linux) |
| Api tests `~HostSecrets` or `~FileKms` or `~EmbeddedWorkers` | 13 passed |
| Workers tests (all) | 39 passed |
| `python3 -I -m unittest discover -s backend/deploy/monsterasp/tests` | 5 passed |
| Testcontainers suites (`ManagedPostgresBootstrapTests`, DB host tests) | not run here (no Docker); covered by backend-ci |

## Lead merge resolutions

- `ProductionApiFactory.cs:28` gained `Database:AllowInsecureTransport=true`. This is correct: the factory uses an unreachable plain connection string, and `DatabaseSettingsTests` covers the TLS guard. Test-only.
- `deployment.md` §7 joins the T-205 subsection ("Keys: HostSecrets provider") and the T-206 subsection ("Hosting profile, deploy and keep-alive") cleanly. One content conflict between the two remains (see F-206-2).

---

## T-205 — HostSecrets key provider (C4, crypto/keys) — **APPROVED**

### Acceptance criteria
| AC | Result | Evidence |
|----|--------|----------|
| 1 ports, `ZAGHLOL_KEYS__…`, Win + Linux | PASS | `HostSecretsKmsTests.CorrectKeysStartAndServeEveryPort`, `HostSecretsWorkerTests` (real env vars) |
| 2 refusals, constant messages | PASS | `HostSecretsKmsTests` refusal set (exact message + sentinel absent); traced `ReadValue`/`ParseJson` |
| 3 tool prints once, no file, `--from-dir` | PASS | `HostSecretsKeyToolTests`; code: no file API in `HostSecretsKeyTool` except reads in `--from-dir` |
| 4 same kids/HMAC/envelope as File | PASS | `TheConvertedFileKeysGiveTheSameKidsHmacsAndEnvelopes`; the provider delegates to `FileKms.FromLoadedKeys` (same `Wrap` AAD, same HMAC) |
| 5 negative proofs | PASS | NP1–NP3 recorded; custody refusal tested at provider, API host and worker process |
| 6 ADR-026 + deployment §7 | PASS | |

### Security part
- **Custody opt-in.** `HostSecretsKms.Load` checks `strict = !Development && !Testing`. Staging is included, and the value must parse to `true` (`bool.TryParse`, so "yes" fails closed). The check runs before any key is read. OK.
- **No key bytes in output.** Every refusal is a `const` message. `ParseJson` catches `JsonException`/`InvalidOperationException`/`ArgumentException` and drops the reader's text. `KmsConfigurationException` derives from `SafeException`, so it does not fall into that catch. The key tool echoes neither an unknown argument nor a file name, and a crypto failure prints the type name only. The only key output is the one-time stdout block, and the tool refuses to run inside a source tree. The tests assert a sentinel is absent from logs and `/v1/health`.
- **FileKms refactor.** The diff moves code without changing it. `CheckDevKids`, `CheckOtherEnvironmentSettings`, `KeyRefs`, `CheckSecret` (degenerate check, then denylist, other environment, pin) and `ParseEcPem`/`ParseSecret` keep their order and their conditions. Buffer zeroing in `LoadEc` moved to an outer `finally`, which is equivalent. File passes `FileKms.Messages`, so its messages are unchanged. The POSIX directory, entry, `prctl` and source-tree guards are untouched. No File guard is weaker.
- **Key in a config file.** The provider refuses a `ZAGHLOL_KEYS` value served by any `FileConfigurationProvider`, and any `appsettings*.json` in the content root or base directory that contains the name or the value marker. Unreadable files are skipped, which is fine because they can't be loaded either. No committed `appsettings*.json` mentions the name.
- **Values left in `IConfiguration` and the environment block.** I accept this risk. The strings are immutable and the same text is already on the host's disk in `web.config`. ADR-026 states the residual, and scrubbing `IConfiguration` would buy little on a host whose staff can read the file. ADR-026 also names `web.config` on the host's disk, Web Deploy credentials and the host's backups as readers, and gives the exit path with rotation for signing keys.
- **Memory hygiene.** Buffers are pinned and zeroed. On the catch path the partially loaded keys are disposed through `FromLoadedKeys(...).Dispose()`. OK.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| F-205-1 | minor (FU-276, shared with T-206) | `HostSecretsKeyTool.cs:70`, `deployment.md:381` | The tool and step 1 say to store each `ZAGHLOL_KEYS__…` line as its own GitHub environment secret. The deploy workflow (T-206) reads only `BACKEND_APP_SETTINGS`, so keys stored that way never reach `web.config`. The start then fails closed. | Tell the operator to put the lines into `BACKEND_APP_SETTINGS`, or make the workflow read them. Trivial; the fix agent may fold it into F-206-1. |

---

## T-206 — MonsterASP hosting profile, embedded workers, deploy (C3) — **CHANGES_REQUESTED**

### Acceptance criteria
| AC | Result | Evidence |
|----|--------|----------|
| 1 embedded workers, off by default, double-run refusal | PASS | `EmbeddedWorkersTests`; one job list (`WorkerJobRegistration`) shared by both hosts. The `SeparateWorkerRunning` declaration is documented as a declaration, not a detector. Jobs without a lease are safe to run twice: the contribution aggregation recomputes in one transaction (set, not increment), prices upsert, retention deletes in batches. So an IIS overlapped recycle is also harmless. |
| 2 win-x64 publish, web.config, ForwardedHeaders | PASS | template: in-process, stdout log off, 4 public env vars, request limits, `App_Data` hidden; `check` enforces it; `NoProxy=true` (see FU-280) |
| 3 snapshots under App_Data | PASS | `SnapshotDirectoryDefaultsToAppDataOnlyWhenEmbeddedAndUnset`, msdeploy skip rules |
| 4 deploy workflow | **FAIL (F-206-1)** | environment `backend-production`, enable flag, secrets never echoed, msdeploy output masks the password, package uploaded before render (no secrets in the rollback artifact), migration before sync, rollback by run id. **But the migration cannot connect to Aiven** (below). |
| 5 keep-alive | PASS | `backend-keepalive-monsterasp.yml`, recycle safety documented |
| 6 OTel off, no PII logs | PASS | |
| 7 runbook | PASS (with F-206-2) | |

Render script: `parse_settings` rejects control characters, bad names and duplicates. ElementTree XML-escapes attribute values, and only line numbers are printed. OK. Under bash `-e`, `settings.env` (umask 077) survives a failed render, but it sits on an ephemeral runner, so that is acceptable.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| F-206-1 | **major** | `.github/workflows/backend-deploy-monsterasp.yml:119-124` | The migrate step passes only `ConnectionStrings__Migrator`. The runner has no `DOTNET_ENVIRONMENT`, so the environment is Production and the T-207 guard requires `VerifyFull`/`VerifyCA`. No `Database__CaCertificatePem` is given, so Npgsql verifies against the system store, which does not hold the Aiven project CA. Every normal deploy therefore stops at migration and AC4 is not met. `aiven-postgres.md` §4 says the CA must be supplied. | Pass the CA to the step, for example `Database__CaCertificatePem: ${{ secrets.BACKEND_DB_CA_PEM }}` (add it to the required-secret check and to the secrets lists in the workflow header and deployment §7), or extract the `Database__CaCertificatePem` line from `BACKEND_APP_SETTINGS`. Also set `DOTNET_ENVIRONMENT=Production` explicitly. Add an actionlint-visible check, or a unit test of the extraction if you choose that route. |
| F-206-2 | minor (FU-276) | `deployment.md:381` vs. the T-206 secrets list | This is F-205-1 seen from the workflow side. | Fix with F-205-1. |
| F-206-3 | minor (FU-279) | `monsterasp_package.py:24` | `FORBIDDEN` does not include `ASPNETCORE_ENVIRONMENT`, `DOTNET_ENVIRONMENT` or `Database__AllowInsecureTransport`. One line in `BACKEND_APP_SETTINGS` overrides the template and silently switches off the custody, TLS and dev-kid guards. | Add these names to `FORBIDDEN`, with a test. |
| F-206-4 | minor (FU-280) | `web.config:21` | `ForwardedHeaders__NoProxy=true` assumes IIS sees the real client. If MonsterASP puts a proxy or load balancer in front of the site, every client shares one rate-limit partition (self-DoS). Not verifiable yet. | On the first deploy, check that `RemoteIpAddress` varies across clients. If it doesn't, set `KnownProxies`/`KnownNetworks` to the host's front addresses. Record the result in §7. |
| F-206-5 | nit (FU-282) | `backend/deploy/monsterasp/tests/__pycache__/test_package.cpython-313.pyc` | A bytecode file is committed. | Delete it and add `__pycache__/` to `.gitignore`. |

---

## T-207 — Aiven for PostgreSQL profile (C3) — **APPROVED**

### Acceptance criteria
| AC | Result | Evidence |
|----|--------|----------|
| 1 VerifyFull + CA (PEM or path), Production refusal | PASS | `DatabaseSettingsTests`. The guard runs in `AddZaghlolDatabase` (`ValidateOnStart`) and in `--migrate`. The CA reaches every data source that is built: the role sources, the readiness probe and the migrator. No other `NpgsqlDataSource`/`NpgsqlConnection` is created in `src`. A configured CA with a non-verifying mode is refused. |
| 2 pool budget | PASS | defaults App 5 + Admin 1 + probe 1 + Worker 3 = 10 ≤ 14 usable; migrator 2; override order tested |
| 3 non-superuser bootstrap | PASS (CI) | conditional `ALTER ROLE` only on drift (idempotent; a drifted privileged role makes a non-superuser fail loudly); PG16+ `GRANT migrator TO current_user WITH SET TRUE` only when needed; restricted attributes on create; script verifies attributes and schema owner; `ManagedPostgresBootstrapTests` in backend-ci |
| 4 migrations from deploy | PASS for T-207's part (entry point, exit codes, CA support). The workflow gap is F-206-1. | |
| 5 backups / RPO | PASS | honest "assume no PITR" |
| 6 region | PASS | PO fills it in at creation |

`AllowInsecureTransport=true` is set in four places: `docker-compose.yml`, `docker-compose.phone-test.yml`, `deploy/server/docker-compose.prod.yml` (self-hosted, private bridge network), the backend-ci container smoke run, and test factories. None of these is on the MonsterASP/Aiven path: the `web.config` template, the deploy workflow and the publish profile never set it. FU-279 closes the remaining override path.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| F-207-1 | minor (FU-277) | `aiven-bootstrap.sh:8,45` | The header says secrets never appear in argv, but `psql "$ZAGHLOL_ADMIN_URI"` passes the avnadmin password in argv, where the process list shows it. | Pass host, port, database and user as `PG*` variables and the password through `PGPASSWORD` or a temporary `.pgpass` (0600), or correct the comment. |
| F-207-2 | minor (FU-278) | `PersistenceServiceCollectionExtensions.cs:71`, `MigrateCommand.cs` | The TLS guard applies only to `IsProduction()`. ADR-026 treats Staging as the same kind of host, but a Staging site on Aiven may use `Require`/`Prefer` unverified. | Use `!Development && !Testing`, matching the KMS strict mode, or state in `aiven-postgres.md` why Staging is excluded. |
| F-207-3 | minor (FU-281) | `aiven-postgres.md` §2 | The budget ignores an IIS overlapped recycle: old and new w3wp briefly up to 20 connections, more than the 14 usable. Npgsql is lazy, so this is unlikely to hurt, but it is not stated. | Document it, or recommend disabling overlapped recycle on the site. |
| F-207-4 | nit (FU-283) | `aiven-bootstrap.sh:63` | The comment says the script verifies that each login is in exactly its group. It doesn't. | Add the membership check or fix the comment. |

---

## Follow-ups (do not block merge)
FU-276 (T-205/T-206 docs: where the `ZAGHLOL_KEYS__` lines go; trivial, may be fixed in the fix round), FU-277 (bootstrap password in argv), FU-278 (TLS guard for Staging), FU-279 (forbid environment and insecure-transport overrides at render), FU-280 (verify ForwardedHeaders on the first deploy), FU-281 (pool budget during recycle), FU-282 (remove .pyc), FU-283 (bootstrap comment).

## Fix round
One fix agent, T-206 lane: F-206-1, plus FU-276 if it stays trivial. The change should be about 30 lines or fewer, so a Lead delta check is enough.
