# backend/

.NET 10 + PostgreSQL 17 services for Zaghlol (SRS D-13, §7.29): modular monolith (ADR-022) with the API and workers as separate processes from one image.

Never stores user financial data (SRS BR-SYNC-03).

## Layout

| Path | Purpose |
|------|---------|
| `src/Zaghlol.Api` | ASP.NET Core Minimal API (`GET /v1/health`, RFC 9457 Problem Details, Serilog JSON logs) |
| `src/Zaghlol.Application` | Handlers per module |
| `src/Zaghlol.Domain` | Pure domain rules and stable error codes |
| `src/Zaghlol.Infrastructure` | Logging setup, DI wiring (EF Core, store clients arrive later) |
| `src/Zaghlol.Workers` | BackgroundService host (no jobs yet; writes a heartbeat file) |
| `src/Zaghlol.Ops` | `zaghlol-ops` operator CLI (stub) |
| `tests/` | xUnit unit tests and the Testcontainers PostgreSQL 17 integration test |

## Run locally

```sh
cd backend
docker compose up --build        # api on :8080, worker, postgres 17
curl http://localhost:8080/v1/health
```

Without Docker: `dotnet run --project src/Zaghlol.Api`.

## Checks (same as CI, `.github/workflows/backend-ci.yml`)

```sh
dotnet build Zaghlol.sln -warnaserror
dotnet format Zaghlol.sln --verify-no-changes
dotnet test Zaghlol.sln          # integration tests need a running Docker daemon
```
