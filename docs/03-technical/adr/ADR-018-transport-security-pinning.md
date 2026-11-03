# ADR-018: Transport security & certificate pinning

| | |
|---|---|
| Status | Proposed (answers OQ-15) |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | backend-api §1; security-model §6 |

## Context
FR-SEC-08 needs TLS 1.2+ and asks whether to pin. Pinning protects against mis-issued certificates but risks outages on certificate or CA rotation, and the app may stay un-updated for months.

## Options considered
1. **Leaf or intermediate certificate pinning** — Strong, but bricks networking on rotation unless backup pins are managed carefully.
2. ****No TLS pinning; application-layer ES256 signatures on all security-relevant responses (sync, entitlement, catalog snapshots)**** — MITM can't forge catalog, flags or entitlements; rotation-safe; still TLS everywhere.

## Decision
**Option 2.** The requests themselves carry no sensitive data (BR-SYNC-03). Integrity of what the app trusts comes from signatures with keys embedded in the app and rotated via release.

## Consequences
A MITM with a rogue certificate could observe install IDs and purchase tokens (low value; tokens are bound by HMAC to the install) but can't change what the app applies.
