# ADR-022: Backend architecture style

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | architecture §5 |

## Context
Small, non-financial backend (D-13) with about 12 modules, 99.5% availability, low cost, a small team.

## Options considered
1. ****Modular monolith** (one ASP.NET Core 10 service + workers, one PostgreSQL)** — Simple ops, transactional consistency, cheap; clear module boundaries keep options open.
2. **Microservices** — Independent scaling we don't need; more ops and cost.
3. **Serverless functions** — Cheap at idle; cold starts, harder local testing, vendor lock-in for RTDN/ASSN handlers.

## Decision
**Modular monolith on .NET 10 (LTS)** with EF Core 10 and PostgreSQL 17. API and workers are separate processes from one image. Singleton workers use PostgreSQL advisory locks.

## Consequences
Scale by adding API replicas. A module can be split out later if needed.
