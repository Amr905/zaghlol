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

## SPK-01 measurement (T-008)

**Question.** Does a bank SMS reach a DB commit within 10 s with the app killed (FR-ING-A-01), on the real path `SmsReceiver → Guard → encrypted spool → expedited WorkManager → headless FlutterEngine (ingestionMain) → parse (T-033) → raw_messages insert (T-017 DAO) → ack`? Is a battery-optimisation prompt needed?

**Build under test.** The spike lives in `app/android/app/src/devSms/` only (Lead decision Q5); no staging or prod artifact contains it (CI checks the merged manifest and dex of every flavour). Measure on `flutter build apk --profile --flavor devSms` (AOT like release, still debuggable for `run-as`). Only synthetic senders are allowlisted (`5550100` for `adb emu sms send`, plus the tester's second phone set in `spike_tester_sender`), so real bank SMS on tester phones are dropped and never measured. The commit measured is one `raw_messages` row (the T-041 transaction insert and FTS cost come on top).

**Clock and stages.** One clock (`elapsedRealtimeNanos`, native; Dart marks are stamped when they reach native code). Per message, ms after t0 (receive): t1 spooled, t2 enqueued, t3 worker start, t4 Dart entry, t5 DB open, t6 drained, t7 parsed, **t8 commit (primary metric)**, t9 acked. Paths: `cold_process`, `warm_process`, `warm_engine` (linger 20 s), `foreground`. Rows from a different boot are discarded. CSV: `no_backup/spike/metrics.csv` (ULIDs, path, conditions, stage deltas; no sender, body or amount). Summary: `dart run tool/spike/latency_report.dart metrics.csv <device>` (in `app/`), which prints the rows below.

**Results.** Emulator rows come from the `sms-spike` workflow (`ci/T-008`, API 26/30/34/36, x86_64 emulator, CI hardware: indicative only). Device rows come from the manual runs in `docs/04-tasks/tasks/T-008.md` (Verification) and are pending the devices (PO question Q1).

| Device | Android | Condition | n | p50 ms | p95 ms | max ms | ≤ 10 s |
|---|---|---|---|---|---|---|---|
| Emulator (CI) | 26 / 30 / 34 / 36 | default, exempt, rare, restricted, Doze | see workflow summary | | | | |
| Samsung A-series (Q1) | | default / exempt / Doze / rare / restricted / "Sleeping apps" | pending | | | | |
| Xiaomi / Redmi (Q1) | | default / exempt / Autostart off / battery saver | pending | | | | |

**Battery-optimisation prompt (AC2).** Decision rule: the prompt is needed only if a device's default-settings p95 exceeds 10 s **and** the exemption brings it within 10 s. Until the device rows exist the answer is "not shown". If it is needed, the app only links to the system settings list (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, no permission); the `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog, which Play restricts, is never used (PO, Q3, 2026-11-11). If a device misses the 10 s p95 only under OEM defaults (e.g. Xiaomi Autostart off, Samsung sleeping apps), the product adds an OEM guidance screen (PO, Q2) rather than restating FR-ING-A-01. Force-stop blocks delivery until the next launch; it is recorded, not counted as a failure.

**Known gaps the spike does not close** (each has an owner): messages lost before the spool rename (ms window), during force-stop, before the first unlock (the receiver is not direct-boot aware; credential storage is locked anyway), on a full spool or after a lost spool key are recovered only by the inbox catch-up scan the PO approved for every app open in the Sms build (Q7, 2026-11-11; native `queryInbox` T-042, Dart scan T-048; `kInboxCatchUpEnabled` stays false until they land).
