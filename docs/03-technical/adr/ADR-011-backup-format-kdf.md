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
