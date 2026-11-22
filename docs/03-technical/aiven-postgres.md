# Aiven for PostgreSQL profile (T-207, D-80)

Free plan, single node: 1 GB storage, 1 GB RAM, `max_connections` 20 with about 6 reserved for Aiven, TLS required, no connection pooler
(Aiven's free-plan page: pooling not supported). Admin user `avnadmin` owns the database (`defaultdb`) and has CREATEROLE but is **not** a
superuser. The application never connects as `avnadmin`.

## 1. TLS (AC1)

Download the project CA (`ca.pem`) from the Aiven console (service overview, "CA certificate"). Connection strings use
`SSL Mode=VerifyFull`; the CA is given to the process as one of:

| Setting | Meaning |
|---|---|
| `Database__CaCertificatePem` | the PEM text (a one-line secret with literal `\n` is accepted) |
| `Database__CaCertificatePath` | path of a mounted file |

Rules enforced at startup (API, worker and `--migrate`; messages never print connection strings or certificate text):

- In **Production and Staging** every role's connection string must be `VerifyFull` or `VerifyCA`; `Disable`, `Allow`, `Prefer` and `Require` (and
  the default, which is `Prefer`) stop the host. The only escape is `Database__AllowInsecureTransport=true`, used by
  `deploy/server/docker-compose.prod.yml` (database on a private bridge network, not published). Never set it for Aiven.
- A configured CA with a non-verifying `SSL Mode` is rejected (the CA would be silently unused).
- Setting both PEM and path is rejected; an unparsable PEM is rejected.

Example (secrets from the host's secret store, never from the repository):

```
ConnectionStrings__App=Host=<svc>.aivencloud.com;Port=<port>;Database=defaultdb;Username=zaghlol_api;Password=...;SSL Mode=VerifyFull
Database__CaCertificatePem=-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----
```

## 2. Connection budget (AC2)

Usable connections: 20 - 6 reserved = **14**. Pool sizes (`Database__MaxPoolSize__<App|Admin|Worker|Migrator>` overrides; otherwise a
`Maximum Pool Size` in the connection string; otherwise the default below):

| Consumer | Default max | Note |
|---|---|---|
| API `/v1` (login `zaghlol_api`) | 5 | |
| API `/admin/v1` (login `zaghlol_admin`) | 1 | operators only |
| API readiness probe | 1 | fixed |
| Workers (login `zaghlol_worker`) | 3 | embedded or separate process |
| **Runtime total** | **10** | |
| Migrator (`--migrate`) | 2 | only while a deploy runs; EF holds one |
| Headroom | 2 | operator `psql`, `pg_dump` |

**IIS overlapped recycle (FU-281, MonsterASP).** A recycle starts the new `w3wp.exe` before the old one stops, so for a moment two
processes hold pools. `disallowOverlappingRotation="true"` is an application-pool setting (`applicationHost.config`), not available in
`web.config`, and the shared host doesn't expose it, so the committed `web.config` template keeps each process small instead:
`Database__MaxPoolSize__App=2`, `Admin=1`, `Worker=1` (+ readiness 1 = 5 per process). Two overlapping processes hold 10, the migrator's 2
still fit (12 of 14), and 2 stay free for `psql`. A test in `deploy/monsterasp/tests/test_package.py` fails if the template stops fitting.
If the pool is ever under your control (own IIS), set `disallowOverlappingRotation="true"` and raise the pools to the table above.

With two API replicas, set `Database__MaxPoolSize__App=3` on each (total stays 10). Npgsql opens connections lazily (`Minimum Pool Size`
0), so idle replicas cost nothing. Pool exhaustion shows as request timeouts, not as Aiven errors; watch
`pg_stat_activity` grouped by `application_name` (`zaghlol-api`, `zaghlol-admin`, `zaghlol-api-readiness`, `zaghlol-worker`).

## 3. Role bootstrap (AC3)

`backend/deploy/db/aiven-bootstrap.sh` runs the unchanged-for-every-platform `bootstrap-roles.sql` as `avnadmin`, then sets passwords:

```
export ZAGHLOL_ADMIN_URI='postgres://avnadmin:<pw>@<host>:<port>/defaultdb?sslmode=verify-full'
export PGSSLROOTCERT=/path/to/ca.pem
export ZAGHLOL_MIGRATOR_PASSWORD=... ZAGHLOL_API_PASSWORD=... ZAGHLOL_ADMIN_API_PASSWORD=... ZAGHLOL_WORKER_PASSWORD=...   # >= 24 chars each
bash backend/deploy/db/aiven-bootstrap.sh            # roles + schema + passwords
bash backend/deploy/db/aiven-bootstrap.sh --passwords-only   # rotation
```

It needs `psql` 15+ (passwords are read with `\getenv`, never in argv). It creates `migrator` (owns schema `zaghlol`), `zaghlol_api`,
`zaghlol_admin`, `zaghlol_worker`, `zaghlol_ops_ro` (LOGIN, no password: break-glass only) and the groups `app_rw`, `ops_rw`, `worker_rw`,
`ops_ro`, all NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS, then verifies that and the schema owner.

What changed in `bootstrap-roles.sql` for a non-superuser admin: roles are created with the restricted attributes and `ALTER ROLE` runs only
when a role has drifted (an unconditional `ALTER ROLE ... NOSUPERUSER` is refused for non-superusers even when it changes nothing); on
PostgreSQL 16+ the admin gets `SET` on `migrator` so it can create the schema for it. Safe to re-run, also as a superuser.

`avnadmin` stays a member of the roles it created (ADMIN, SET). Keep its password out of the deploy workflow: only the one-off bootstrap and
password rotation use it.

## 4. Migrations (AC4)

Entry point (for T-206's deploy workflow): `dotnet Zaghlol.Workers.dll --migrate` (the image's worker with `--migrate`), configured with
`ConnectionStrings__Migrator` (login `migrator`, `SSL Mode=VerifyFull`), `Database__CaCertificatePem` or `Database__CaCertificatePath`,
and `DOTNET_ENVIRONMENT=Production`. Exit codes: 0 applied (or nothing to do), 1 migration failed, 2 configuration error (missing connection
string or the TLS guard above). Migrations are N-1 compatible (deployment.md section 3). The runtime logins never run DDL.
The `db-platform` workflow tests the Flutter/SQLCipher database and is unrelated; the backend checks (including these tests) run in `backend-ci`.

## 5. Backups, RPO and RTO (AC5)

Aiven's free-plan page lists backups as included but gives no frequency, retention or point-in-time recovery; we therefore **assume no PITR**
and a best-effort daily backup that we cannot restore on our own schedule (confirm in the console under "Backups"). Honest numbers:
RPO up to 24 h with Aiven's backup alone, RTO hours (restore request, then re-point the connection strings). The free service can also be
powered off after inactivity (Aiven notifies first); the app's worker traffic normally prevents that, but power it on from the console if
it happens.

Optional own copy (off by default): a weekly `pg_dump` (custom format) from a scheduled GitHub Actions job run with the migrator-or-admin
read credentials, encrypted (`age`/`gpg` with a public key) before upload as an artifact or to the PO's storage. The database holds no
financial data (SRS BR-SYNC-03: install IDs, purchase tokens, entitlements, catalog, contributions, audit), so the loss ceiling is
entitlement and catalog state, which the stores and the catalog build can rebuild. Entitlements can be re-derived by store re-verification;
this is why a weaker RPO than the NFR target of the self-hosted design (WAL archive) is accepted for this profile. Record the PO's acceptance
in PO_DECISIONS if the NFR text demands a stricter figure. Not built in T-207: no workflow was added (T-206 owns workflows).

## 6. Data location (AC6, PDPL CR-03)

Choose the Aiven cloud and region when creating the service; it cannot be changed on the free plan without migrating (Aiven may also change
region or configuration of free services). Recommended: an EU region close to Egypt (for example Frankfurt, `aws-eu-central-1` or
`google-europe-west3`), subject to what the free plan offers in the console. Record the chosen region here: **region: ______ (PO to fill in
at creation)**. Data stored is pseudonymous, non-financial service data (no names, no phone numbers; an optional account e-mail or
provider subject only when the user signs in for cross-platform Gold). Transfer outside Egypt is covered by the CR-03 notice and consent
wording; legal review owns the final position.
