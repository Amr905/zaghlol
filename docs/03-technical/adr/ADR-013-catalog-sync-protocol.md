# ADR-013: Catalog sync protocol

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | backend-api §4.2 |

## Context
D-15: at most one successful sync per 24 h, on app open; deltas; atomic apply; signed payloads (FR-SYNC-01…07). The same call refreshes flags, prices and entitlement (FR-SYNC-07). Up-to-date clients must get ≤ 2 KB (NFR-BE-03).

## Options considered
1. **Separate REST calls per resource (catalog, flags, prices, entitlement)** — Simple endpoints, but 4 round-trips and 4 signatures.
2. ****One `POST /v1/sync` with versions in, combined signed response out; full snapshots from CDN**** — One round-trip; tiny when nothing changed; server-side throttle; uploads outbox in the same call.
3. **Push (FCM/APNs) on change** — Needs push SDK/tokens, so more data and an SDK; not needed for daily freshness.

## Decision
**Option 2.** Immutable catalog versions with a change log, deltas `(a, b]` including tombstones, full snapshot when 0 or > 20 behind. ES256 signature over the body bytes. The client applies everything in one DB transaction.

## Consequences
The catalog is versioned monotonically by operator publishes. The app needs signature verification code (shared with entitlement).
