# backend/

.NET 10 + PostgreSQL 17 services for Zaghlol (SRS D-13, §7.29): modular monolith (ADR-022) with the API and workers as separate processes from one image.

Never stores user financial data (SRS BR-SYNC-03).

## Layout

| Path | Purpose |
|------|---------|
| `src/Zaghlol.Api` | ASP.NET Core Minimal API (`GET /v1/health`, RFC 9457 Problem Details, Serilog JSON logs) |
| `src/Zaghlol.Application` | Handlers per module |
| `src/Zaghlol.Domain` | Pure domain rules and stable error codes |
| `src/Zaghlol.Infrastructure` | Logging setup, DI wiring, EF Core model + migrations (`Persistence/`, T-122), KMS abstraction: signer, keyed hasher, envelope cipher (`Kms/`, T-123) |
| `src/Zaghlol.Workers` | BackgroundService host (no jobs yet; writes a heartbeat file); `--migrate` is the migration job |
| `src/Zaghlol.Ops` | `zaghlol-ops` operator CLI (stub) |
| `tools/dev-keys.sh` | Creates development KMS keys and the matching key-ring config for compose (T-123) |
| `deploy/db/` | `bootstrap-roles.sql` (roles + schema, run once by an admin), `dev-passwords.sql` (compose only) |
| `tests/` | xUnit unit tests and Testcontainers PostgreSQL 17 integration tests (schema, CHECKs, grants, readiness) |

## Run locally

```sh
cd backend
tools/dev-keys.sh                # throwaway Local KMS keys in .dev-keys/ (git-ignored)
docker compose up --build        # api on :8080, worker, postgres 17
curl http://localhost:8080/v1/health
```

Without Docker: `tools/dev-keys.sh`, then run `src/Zaghlol.Api` as `Development` with the variables of
`.dev-keys/kms.env` and `Kms__Local__KeyDirectory` pointing at `.dev-keys`. The API refuses to start without a valid key
ring, and refuses the Local KMS outside Development/Testing (T-123; `docs/03-technical/deployment.md` §3).

## Checks (same as CI, `.github/workflows/backend-ci.yml`)

```sh
dotnet build Zaghlol.sln -warnaserror
dotnet format Zaghlol.sln --verify-no-changes
dotnet test Zaghlol.sln          # integration tests need a running Docker daemon
```

## Database (T-122)

All objects live in schema `zaghlol`, owned by `migrator`. Roles come from `deploy/db/bootstrap-roles.sql`, which an
administrator runs once per database (never a migration). Per-table grants are in the migrations (`GrantMatrix.cs`).

| Setting | Process | Login (group) |
|---|---|---|
| `ConnectionStrings:App` | API, `/v1/*` | `zaghlol_api` (`app_rw`) |
| `ConnectionStrings:Admin` | API, `/admin/v1/*` | `zaghlol_admin` (`ops_rw`) |
| `ConnectionStrings:Worker` | worker | `zaghlol_worker` (`worker_rw`) |
| `ConnectionStrings:Migrator` | `dotnet Zaghlol.Workers.dll --migrate` | `migrator` (owner) |

Each is required at startup by the process that uses it. Real credentials come from the secrets manager (T-140); the
compose file uses the throwaway values in `deploy/db/dev-passwords.sql`. `GET /v1/health` answers `503
UPSTREAM_UNAVAILABLE` while the `App` database is unreachable.

**New migration:** there is no local SDK requirement. Push a commit whose message contains
`[ef-migration-add:<Name>]` to a `task/**` branch; the `backend-ef-migration` workflow runs `dotnet ef migrations add`
and commits the generated files back (see `.github/workflows/README.md`). Raw SQL that EF can't model lives in a
style-checked class under `Persistence/` (InitialCreate's is `Persistence/InitialCreateSql.cs`, pinned by a golden
test); the generated migration only calls it from `Up()` / `Down()`. `backend-ci` fails when the model and the
snapshot differ (`dotnet ef migrations has-pending-model-changes`). A shipped migration is never edited: changes go in
a new one.
