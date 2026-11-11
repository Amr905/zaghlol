# ADR-011: Backup format & key derivation

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-BAK-*, security-model §5 |

## Context
FR-BAK-01: AES-256-GCM, unreadable without the user's passphrase (A-23); automatic backups (Gold) must run without asking for the passphrase; cross-platform restore (A-24); EC-27 forgotten passphrase.

## Options considered
1. **Encrypt the whole file with Argon2id(passphrase) each time** — Must ask for the passphrase at every backup, so it breaks automatic schedules.
2. ****Random backup data key K_bk, wrapped by Argon2id(passphrase) in the header; K_bk also kept in secure storage for automatic runs; chunked AES-256-GCM stream**** — Passphrase only needed at setup and restore; streaming for large files; tamper-evident chunks.
3. **PBKDF2-SHA256 instead of Argon2id** — Universally available, but weaker against GPU attacks; would need 600k+ iterations.

## Decision
**Option 2 with Argon2id** (m = 64 MiB, t = 3, p = 1; parameters in the header for upgrades), via the `cryptography` package (native-accelerated AES-GCM). The DB snapshot is taken with the SQLite backup API into a temp DB keyed with HKDF(K_bk). Format in security-model §5.

## Consequences
About 1 s KDF on mid-range phones at setup and restore. A forgotten passphrase means an unrecoverable backup (a clear warning at setup). A printable recovery code is a possible later enhancement.

## Amendment 2026-11-11 (T-148 design note)
- **Argon2id comes from `hashlib`** (pure Dart, no FFI, one small dependency), not `cryptography`: `cryptography_flutter` accelerates AES-GCM but not Argon2, and `hashlib` publishes timings at these exact parameters. AES-256-GCM and HKDF stay on `cryptography` + `cryptography_flutter`. Expected KDF time on a low-end Android is about 2–4 s (budget p50 ≤ 4 s, p95 ≤ 8 s; fallback t = 2 at 64 MiB if exceeded, recorded here).
- **Per-file chunk key** `K_chunk = HKDF(K_bk, fileId)` and nonces derived from a per-file prefix and the chunk index (not stored), because `K_bk` is shared by every backup. The wrap has its own AAD binding the KDF parameters and a `kbkId` fingerprint. The header manifest digest is dropped (the AEAD covers every byte). Format in security-model §5.
- **A passphrase change rotates `K_bk`** instead of re-wrapping it: an old file plus the old passphrase reveals the old `K_bk`, so a re-wrap would not protect later backups. Old backups keep needing the old passphrase.
- The passphrase is normalized (Arabic-Indic digits to ASCII, spaces, NFC through a small platform method) so a restore on the other platform gets the same bytes.
