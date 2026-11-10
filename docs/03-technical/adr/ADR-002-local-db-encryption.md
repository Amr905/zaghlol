# ADR-002: Local database & encryption

| | |
|---|---|
| Status | Accepted — CI evidence; device confirmation pending (T-007, 2026-11-08) |
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
**Drift ≥ 2.32 with SQLite3MultipleCiphers**, using the SQLCipher-compatible AES-256 cipher (`PRAGMA cipher='sqlcipher'; legacy=4`) to meet FR-SEC-01 literally. The 256-bit random key `K_db` is kept in the Android Keystore / iOS Keychain (device-only) through the app's own Pigeon channel `SecretStoreHostApi`, not `flutter_secure_storage` *(Amendment 2026-11-10)*. The app verifies on open that encryption is active.

## Consequences
One encrypted file holds *all* app state (settings, catalog, entitlement cache, outbox), which satisfies FR-SEC-03 without separate encrypted preferences. The build uses Dart build hooks, so CI needs a recent Flutter. If Keystore invalidates the key, the DB can't be recovered; restore from backup is the path (error-handling §1).

## Amendment (2026-11-10): K_db storage through a native channel (T-015, PO approved)

**Decision.** `K_db` is stored by a project Pigeon channel, `SecretStoreHostApi` (`app/pigeons/secret_store_api.dart`), instead of `flutter_secure_storage`. The PO approved this on 2026-11-10 (T-015 design note, Q1).
- **Android:** a Keystore AES-256-GCM key `zaghlol_db_kek_v1` (non-exportable, no user authentication, no unlocked-device requirement, StrongBox when available) wraps `K_db`. The blob is `noBackupFilesDir/keys/db_key_v1.bin` = `0x01 ‖ iv(12) ‖ ct(32) ‖ tag(16)`, AAD `zaghlol/k_db/v1`, written as tmp, fsync, rename, and read back before a create returns. Every create makes a fresh wrapping key.
- **iOS:** a Keychain generic password (service `app.zaghlol.keys`, account `db_key_v1`), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`, `kSecAttrAccessGroup` pinned to Runner's own application-identifier group (`<AppIdentifierPrefix><bundle id>`, never a shared group). Queries always name service and account and never touch the D-62 seat keys.
- **Read classes:** `found`, `notFound` (positive evidence of absence), `unusable` (positive evidence the key can't be read again: alias missing, tag failure, malformed blob, invalidated key), `unavailable` (everything else, including an Android blob whose presence can't be determined). Every non-`found` read is retried at 100/300/900 ms; `notFound`/`unusable` only when every attempt agrees (Android `notFound` is proven by the file system and returns at once), any disagreement is `unavailable`, and one `found` wins. Only `notFound`/`unusable` with a database present lead to `KeyInvalidated` and the D-50 orphan wipe; `unavailable` never wipes.
- A process-wide **bootstrap lease** (30 s expiry) serialises the bootstrap and database creation/wipe across Flutter engines.

**Why not the plugin.** Since 10.0 `flutter_secure_storage` defaults `resetOnError` to true (it deletes stored values on read errors), and 11.0 makes data saved with removed algorithms unusable: both are wrong for the one key whose loss erases all user data. It flattens Keystore errors into strings, so the exact classification FR-SEC-05 needs (T-165 review F6) is impossible. Its Android store is SharedPreferences, against the T-165 policy. The native code is small (we need Keystore/Keychain code for `K_spool` anyway) and adds no pub or native dependency.

**Consequences.** Every engine that opens the database must register the channel (the UI engine does; T-008's headless engine must). `K_spool` (T-008) and `K_bk` (T-148) reuse the channel by adding slots. Contract: platform-channels §5/§6; key table: security-model §3; implementation and tests: T-015.

## Spike results (T-007)

Evidence: `.github/workflows/db-platform.yml` run **42506507228** (head `bf2419e`, all four legs green) and app-ci run **42506507253**. Harness: `app/test/core/db/sqlite3mc_contract.dart` and `fts_benchmark.dart`, used by the host tests and by `app/integration_test/db_platform_test.dart`.

**Versions.** `package:sqlite3` **3.9.1** (lock sha256 `8765980411f9…886b`), `package:drift` **2.35.3**. `sqlite_version()` **3.54.0**, `sqlite3mc_version()` **SQLite3 Multiple Ciphers 2.6.1**, the same on all four legs. The Android code asset is **`lib/<abi>/libsqlite3mc.so`** (arm64-v8a, armeabi-v7a, x86_64). On the Linux host the hook downloads `.dart_tool/hooks_runner/shared/sqlite3/build/download-*/libsqlite3mc.so`, and `gh attestation verify --repo simolus3/sqlite3.dart` passes on it. SQLite3MultipleCiphers is MIT-licensed; note it for the OSS-notices task.

**Contract (asserted on host, Android emulator API 35 and API 26, iOS simulator):**
- The open sequence is `cipher='sqlcipher'`, `legacy=4`, raw `x'…'` key, `temp_store=2`, WAL/NORMAL. Its verification (`count(*) FROM sqlite_master`, `PRAGMA cipher` = `sqlcipher`, `sqlite3mc_codec_data('cipher_salt')` non-NULL) passes, including inside `NativeDatabase.createInBackground`.
- No key → SQLITE_NOTADB (26). Wrong key → 26. A key applied to a plaintext file made by the same library → 26; it never opens as plaintext, and the full open sequence refuses it.
- The header is not `SQLite format 3\0`. Neither sentinel (ASCII or Arabic) appears in `.db`, `-wal` or `-shm`, whether open with an un-checkpointed WAL or after close. Positive control: the scanner finds both in a plaintext file. Only the three DB files are in the directory.
- `PRAGMA rekey` round-trip: K2 opens, K1 → 26. Rekey also worked in WAL mode on every leg.
- **SQLCipher compatibility (host):** Ubuntu's `sqlite3` CLI reports "file is not a database (26)". The `sqlcipher` CLI with SQLCipher 4 defaults and the raw key reads the sentinel rows (2/2).
- FTS5: `ENABLE_FTS5` is present. The database-schema.md `transactions_fts` DDL works as written, with external content and sync triggers. `Café` ↔ `cafe`/`CAFÉ`, Arabic substring `كارفور`, and Latin and Arabic-Indic digits in `amount_text` all match.
- Temp files: on Android `Directory.systemTemp` is `/data/user/0/app.zaghlol.dev/code_cache`; on iOS it is the app container's `tmp/`.

**Findings (recorded, not asserted; for T-015/T-016 and the search task):**
1. **`LIKE` is not served by the index with `remove_diacritics 1`.** The plan is `SCAN transactions_fts VIRTUAL TABLE INDEX 0:` (empty idxStr) on every leg. Control: the same LIKE on a `tokenize='trigram'` table gives `INDEX 0:L0`. Search must use `MATCH`; `LIKE` is a full scan with this tokenizer. The design note expected an indexed LIKE: **deviation**, now recorded instead of asserted.
2. `remove_diacritics` does **not** strip Arabic tashkeel (`محمد` does not match `مُحَمَّد`). It folds Latin only. Normalize Arabic (tashkeel, and probably alef/yaa/taa-marbuta forms) in Dart, on both the indexed text and the query.
3. Queries of 1–2 characters return **0 rows** via `MATCH` (trigram needs 3 or more). The `LIKE` fallback finds them but scans (`like_short_ms` p95 below). The search task needs a fallback for short queries, ideally limited (recent rows / LIMIT) or debounced.
4. The encrypted/plaintext ratio is about 1.5× for the rank query but **4.6–5.7×** for the list query (join + `ORDER BY occurred_at`), which touches many random pages to decrypt. The first lever is `cache_size` tuning: the 50k DB is about 18 MB against the default 2 MB cache.
5. A passphrase key (PBKDF2, 256k) costs 140–240 ms per open, against 6–9 ms for the raw key. That confirms the raw `x'…'` key.

**Timings** (50,000 rows; ms; p50 / p95 / max for queries). Every CI row is **emulator/simulator or CI host, debug mode, x86_64/arm64-sim on CI hardware**. They are not device numbers and do not prove FR-TXN-01. Only the host row is gated (testing-strategy §5: p95 < 50 ms).

| Environment | Run | open cold / warm | insert 50k | FTS rank | FTS list | LIKE 2-char | enc/plain list p95 | PBKDF2 open | DB size |
|---|---|---|---|---|---|---|---|---|---|
| CI host (ubuntu x86_64, `flutter test`) | 42506507228 | 7.1 / 5.7 | 2658 | 6.9 / 9.1 / 10.1 | 15.7 / 18.3 / 18.8 | 4.8 / 463 / 468 | 5.72 | 175 | 17.98 MB |
| Android emulator API 35 (x86_64, debug) | 42506507228 | 8.9 / 8.0 | 2428 | 6.4 / 9.9 / 12.5 | 13.1 / 16.7 / 18.5 | 3.8 / 349 / 351 | 4.64 | 140 | 17.98 MB |
| Android emulator API 26 (x86_64, debug) | 42506507228 | contract only | | | | | | | |
| iOS simulator (iPhone 17 Pro, iOS 26.2, arm64-sim, debug) | 42506507228 | 12.6 / 8.6 | 3711 | 8.9 / 15.8 / 27.5 | 23.6 / 45.2 / 76.5 | 8.1 / 718 / 761 | 5.32 | 237 | 17.98 MB |
| Mid-range Android (profile) | — | **PENDING** | | | | | | | |
| iPhone 12 (profile) | — | **PENDING** | | | | | | | |

Plaintext baseline, same binary (FTS list p95): host 3.2, API 35 3.6, iOS simulator 8.5.

**Recommendation:** **confirmed on CI evidence.** SQLite3MultipleCiphers with the SQLCipher-4 AES-256 scheme and a raw key works on every platform leg, and the indexed search shapes are well under 200 ms even in debug on emulators. Two items remain open:
- **Device rows (PENDING):** run `docs/05-reviews/T-007-device.md` and fill these rows before the first release candidate. This item goes on the T-171 checklist.
- **`like_short_ms` p95:** the 2-character fallback is 350–720 ms p95 on emulators, which is a full scan for rare terms. This is a search-design item, not a cipher one.

If a device FTS p95 is 200 ms or more, try the fallbacks in this order:
1. `cache_size` and page-size tuning;
2. query shape;
3. sqlite3mc's default ChaCha20-Poly1305. This conflicts with "AES-256" in FR-SEC-01, so it needs a PO decision first.
