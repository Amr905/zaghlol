# ADR-005: Background capture: native Guard + encrypted spool

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | platform-channels §1; architecture §4.3 |

## Context
SMS and notification events arrive while the app is killed. A `BroadcastReceiver` has about 10 s, and iOS App Intents run before Flutter is up. BR-CAP-01 requires ignored messages to be discarded **before anything is written**. NFR-REL-01 requires no loss if the process dies.

## Options considered
1. **Start a headless Flutter engine inside the receiver and parse immediately** — Single parser, but engine start-up of about 1–2 s within receiver limits is fragile; iOS intents can't wait for it reliably.
2. **Port the whole parser to Kotlin and Swift** — Fast, but triples the parser and its fixtures; drift between implementations.
3. ****Native Guard (rules only) → encrypted spool → Dart pipeline via WorkManager / BGTask / foreground**** — Parser stays single (Dart). The Guard is small, generated from registry data and tested with shared golden cases. The spool gives idempotent, loss-free hand-off.

## Decision
**Option 3.** The Guard implements sender allowlist, OTP/promo drop and ignore rules from an encrypted config written by Dart. Kept messages go into an AES-GCM spool keyed by a non-exportable Keystore/Keychain key. Entries are deleted only after the DB commit.

## Consequences
Guard logic exists in three languages (about 150 lines each), kept in lock-step by shared golden tests and generated config. On iOS, processing may wait until the next app open or BG refresh (SPK-03 tests a headless engine for immediate processing).
