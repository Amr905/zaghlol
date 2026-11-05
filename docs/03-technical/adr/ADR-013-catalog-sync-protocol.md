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

## Amendment (2026-11-05): draft keys, tombstones and keyword identity (FU-009)
**Context.** The T-006 admin draft API had `PUT` but no way to delete. Its `{id}` format (`merchantId:alias` for both aliases and keywords) didn't match the sync ops: the `keyword` op is keyed by `keyword` + `lang`. Both `catalog_keywords` tables were keyed `(keyword_norm, category_code)`, so a delta's keyword delete couldn't name its row.

**Options.**
1. Key keywords by `(keyword, lang, category)` and add `category` to the delete op. This allows one keyword per several categories, but changes the sync contract.
2. **Key keywords by `(keyword, lang)`, one category per keyword per language.** This matches the existing sync op and keeps the scoring simple: each keyword votes once.

**Decision: option 2,** plus explicit draft keys and tombstones (`backend-api.md` §5.2):
- **Keys in the path, non-key fields in the body.**
  - categories: `<code>`
  - merchants: `<id>` (server-allocated by `POST /admin/v1/catalog/draft/merchants`, never reused)
  - aliases: `<merchantId>:<b64u(alias)>`
  - keywords: `<lang>:<b64u(keyword)>`
  - Free text is base64url-encoded so it never needs path escaping.
- **Deletes are tombstones.** `DELETE /admin/v1/catalog/draft/{entity}/{id}` marks the entry deleted. Publish writes `deleted = true` at the new version, and deltas `(a, b]` emit `op: delete`.
- **Merchant cascades.** Deleting a merchant cascades to its aliases; the alias tombstones come first in the delta.
- **Conflicts.** Removing or referencing a non-live category or merchant gives `409 ADMIN_CONFLICT`.
- **Contribution keys move to the body** (`POST /admin/v1/contributions:promote|:reject`), because `merchantNorm` is free text.
- *Security review (2026-11-05):*
  - **Collecting looks absent:** a `collecting` aggregate gets the same `404` as a missing one (same body, one query, no timing difference). `409` is only for `promoted`/`rejected` aggregates or draft conflicts. T-129 tests that the two responses are byte-identical.
  - **Canonical `b64u` keys:** no padding; re-encoding must round-trip; the decoded text must equal its normalized form; at most 64 characters. Anything else gives `400`.

**Consequences.**
- T-125 builds the draft workspace with these keys and cascades, and adds `ADMIN_CONFLICT` to `ErrorCodes`.
- T-129 uses the body-keyed promote/reject.
- T-030 (seed) and T-075 (categorizer) treat `(keyword, lang)` as unique.
- No sync wire change.
