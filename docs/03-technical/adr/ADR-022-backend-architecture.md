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

## Amendment (2026-11-05): input schemas, query strings and image layout (FU-007, FU-008, FU-001)
**1. Open schemas for third-party bodies (FU-007).**
- Options:
  - (a) Keep every request schema closed. A field that Google or Apple add would then be rejected with 400, and the store would retry. Pub/Sub would redeliver until the dead-letter policy, so we'd silently lose notifications.
  - (b) **Close what we define, open what third parties define.**
- Decision: (b).
  - App and operator requests stay closed (`400 UNKNOWN_FIELD`). That is the BR-SYNC-03 guard.
  - The Pub/Sub push envelope, the ASSN V2 body and the Apple `form_post` are open (`additionalProperties: true`) and marked `x-third-party-body: true`.
  - The server reads only the listed fields and never stores or logs the rest. Their authenticity comes from the OIDC token or JWS, not from their shape.
  - A contract test pins the marked set to exactly those three operations and checks they accept unknown fields. The closed-schema walk covers everything else.

**2. No personal data in URLs; query strings never logged (FU-008).**
- Options:
  - (a) Keep `GET …?email=` and rely on log scrubbing. This is fragile: proxies, CDNs and tracing all see URLs.
  - (b) **Move sensitive keys to bodies and ban query logging.**
- Decision: (b).
  - The support lookup becomes `POST /admin/v1/support/entitlement:lookup` with `{installId}` or `{email}`.
  - Logs and spans carry the route template only. Query strings, raw paths and `Location` headers are never logged (`error-handling-and-observability.md` §3.2).
  - *Security review (2026-11-05):* the rule also covers framework log categories (hosting diagnostics, Kestrel, HttpClient at `Warning` or filtered), HttpLogging (off or allow-listed), outbound spans (redacted URL template, because Play v2 URLs carry the purchase token) and edge body logging for `/v1/apple/*` and `/v1/notifications/*`.
  - The lookup audit row stores `HMAC-SHA256(K_audit, NFC(trim(lower(email))))` with a dedicated KMS key, plus `account_id`. It is pseudonymous personal data, retained 3 years unless the PO decides otherwise (D2).
  - Third-party bodies: authenticate before reading (Pub/Sub OIDC in the auth handler) or before writing (ASSN JWS chain). Store only extracted columns. No catch-all DTO members.

**3. Dockerfile location (FU-001).**
- Options:
  - (a) `backend/deploy/Dockerfile` as first drafted.
  - (b) **`backend/Dockerfile`, with `backend/` as the build context,** as T-005 built it.
- Decision: (b). The image builds the whole solution (API, workers, ops), so the context has to be `backend/` anyway. Keeping the Dockerfile at the context root keeps `docker build backend` and compose simple. `backend/deploy/` holds only OpenTofu and environment configs.

**Consequences.**
- T-133/T-134 bind the notification DTOs leniently.
- T-136 implements the POST lookup with hashed audit.
- T-138 implements and tests the logging rule.
- `project-structure.md` is updated.
