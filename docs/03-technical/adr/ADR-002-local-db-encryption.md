# ADR-002: Local database & encryption

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | database-schema.md; security-model §3; https://drift.simonbinder.eu/platforms/encryption |

## Context
All data on the phone must be encrypted from the first write with AES-256 (FR-SEC-01, D-18). The app needs relational queries, FTS for search over 50k rows in < 200 ms (FR-TXN-01), reliable migrations and background-isolate access. Drift's docs say that since drift 2.32, SQLite3MultipleCiphers bundled through the `sqlite3` package's build hook is the recommended way to encrypt on all native platforms. `sqlcipher_flutter_libs` has reached end of life.

## Options considered
1. **Drift + `sqlite3` hook `source: sqlite3mc` (SQLite3MultipleCiphers)** — Officially recommended; one native library; supports the SQLCipher-compatible AES-256 scheme; FTS5; Drift migrations tooling.
2. **Drift + `sqflite_sqlcipher` (encrypted_drift)** — Works, but needs extra setup (ProGuard rules etc.), and drift itself describes it as no longer the simple path.
3. **Isar / ObjectBox / Realm** — Fast object stores, but weaker or no SQL aggregation, FTS and migration tooling; Isar maintenance risk.

## Decision
**Drift ≥ 2.32 with SQLite3MultipleCiphers**, using the SQLCipher-compatible AES-256 cipher (`PRAGMA cipher='sqlcipher'; legacy=4`) to meet FR-SEC-01 literally. The 256-bit random key `K_db` comes from `flutter_secure_storage` (Keystore/Keychain, device-only). The app verifies on open that encryption is active.

## Consequences
One encrypted file holds *all* app state (settings, catalog, entitlement cache, outbox), which satisfies FR-SEC-03 without separate encrypted preferences. The build uses Dart build hooks, so CI needs a recent Flutter. If Keystore invalidates the key, the DB can't be recovered; restore from backup is the path (error-handling §1).
