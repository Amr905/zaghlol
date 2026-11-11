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
**Option 3.** The Guard implements sender allowlist, OTP/promo drop and ignore rules from a config written by Dart (since T-035 two parts: a plaintext base part bundled with the app and an encrypted user part; platform-channels §1.1). Kept messages go into an AES-GCM spool keyed by a non-exportable Keystore/Keychain key. Entries are deleted only after the DB commit.

## Consequences
Guard logic exists in three languages (about 150 lines each), kept in lock-step by shared golden tests and generated config. On iOS, processing may wait until the next app open or BG refresh (SPK-03 tests a headless engine for immediate processing).

## Threats (T-035, FU-084c)

- **Spoofed sender IDs.** Alphanumeric SMS sender IDs can be spoofed over the phone network, and the Guard keeps on a sender match. The Guard is a privacy filter (what may be written), not an authenticity check. Mitigations: messages from generic and user senders always go to review (T-073); a template-matched spoof from a registry sender is auto-saved, an **accepted residual** (the user can delete it; no money moves).
- **Flooding.** The per-`(channel, sender)` rate limit in the Guard (more than 20 kept per sliding minute → `rate_limited`, PO Q3 provisional) is **best-effort**: it is in memory, per process, and resets when the process dies (a cold process per SMS starts empty). The **hard** bound is the spool: 500 entries / 4 MiB, new messages refused, never old ones evicted; and Guard `generic` keeps (unknown senders that look financial, the easiest to spoof) may use at most half of it (250 entries / 2 MiB) and 10 writes per minute process-wide, so a flood from unknown senders can't crowd out bank messages (T-035 security L-3, T-039; numbers PO-provisional). Every refusal is counted in the encrypted capture status; Dart then shows a degraded-capture state and runs the inbox catch-up from the first missed SMS. Rate-limited or refused SMS come back through that catch-up; refused notifications are lost.
- **Config tampering or corruption.** The base part ships inside the signed app; the user part is AES-GCM with the spool key. An unreadable user part falls back to the base rules (bank SMS kept; ignored cards caught by the drain-time re-check in Dart), an unreadable base drops everything (`config_invalid`). No generation counter in the user part's AAD (T-035 security I-6, rejected in T-038): replaying an older user file needs write access to the app sandbox, which defeats every other control, and Dart rewrites the file on every app start. A lost spool key makes pending entries and the user part undecryptable: entries are deleted only on a tag failure, the loss is reported to Dart (`keyInvalidatedAtMs`), and SMS are recovered by the catch-up (T-039).
- **OTP shape residuals (T-035 review M-1/M-2).** The global OTP patterns must both drop OTPs and keep real transactions that carry a security footer; they are resolved by structure (sentence-bounded gap where a line break is also a sentence end, code accepted only right after the keyword or a lead-in such as `is`/`هو`/`:`, never after a card, currency or `call` word; no 5-digit `19xxx` hotline code; platform-channels §1.2). The global patterns run on `foldKeyLines` text, which keeps line breaks; only the tight form (`OTP:` / `482913`) may span one. Where a shape is ambiguous the patterns prefer the keep, because a dropped transaction is unrecoverable and a kept OTP is not. What is left, pinned by golden `residual.*`: (a) **kept OTPs**: a 5-digit code starting with `19`, a keyword-to-code distance over 24 characters without a period, a code on the line after a keyword with words or a lead-in between (`Your OTP for login is` / `482913`), a keyword split by a line break, an obfuscated keyword (`O T P`), and wordings outside the keyword list (bare `الرمز`, `Fawry code is`: T-036). Such a message is stored like any kept message (spool, then DB and FTS, then backups) and reaches review or, if a template matches, is auto-saved; the completed-transaction SMS normally follows, so a duplicate is possible. (b) **dropped transactions**: a keyword and a reference number in the same sentence on the same line with a lead-in between (`... by OTP, ref is 482913`) is dropped with no trace. A security line on its own line next to a `Ref:`/`Txn:` line no longer drops (T-035 fix round 2). Real registry templates (T-036) must add institution-specific fixtures for both directions.
- **Regex dialect drift.** Patterns are limited to a portable subset checked by the registry lint and run against one normalisation; the shared golden cases run in all three languages.

## SPK-01 measurement (T-008)

**Question.** Does a bank SMS reach a DB commit within 10 s with the app killed (FR-ING-A-01), on the real path `SmsReceiver → Guard → encrypted spool → expedited WorkManager → headless FlutterEngine (ingestionMain) → parse (T-033) → raw_messages insert (T-017 DAO) → ack`? Is a battery-optimisation prompt needed?

**Build under test.** The spike lives in `app/android/app/src/devSms/` only (Lead decision Q5); no staging or prod artifact contains it (CI checks the merged manifest and dex of every flavour). Measure on `flutter build apk --profile --flavor devSms` (AOT like release, still debuggable for `run-as`). Only synthetic senders are allowlisted (`5550100` for `adb emu sms send`, plus the tester's second phone set in `spike_tester_sender`), so real bank SMS on tester phones are dropped and never measured. The commit measured is one `raw_messages` row (the T-041 transaction insert and FTS cost come on top).

**Clock and stages.** One clock (`elapsedRealtimeNanos`, native; Dart marks are stamped when they reach native code). Per message, ms after t0 (receive): t1 spooled, t2 enqueued, t3 worker start, t4 Dart entry, t5 DB open, t6 drained, t7 parsed, **t8 commit (primary metric)**, t9 acked. Paths: `cold_process`, `warm_process`, `warm_engine` (linger 20 s), `foreground`. Rows from a different boot are discarded. The row is written when the ack reaches native code (Pigeon background queue); the Dart `commit` mark comes over the metrics channel on the main thread and can arrive after it, so some rows have no t8. The report then uses t9 (after the commit by construction) as an upper bound and counts those rows in the "commit = ack stamp" column, so no row is dropped and the latency is never understated (T-041 can stamp the commit natively). CSV: `no_backup/spike/metrics.csv` (ULIDs, path, conditions, stage deltas; no sender, body or amount). Summary: `dart run tool/spike/latency_report.dart metrics.csv <device> [broadcasts.txt]` (in `app/`), which prints the rows below.

**Which interval the tables show (review F2).** t0 is stamped at the start of `onReceive`, so receive → commit leaves out broadcast queueing and, on the killed-app path, the whole process start (fork, `Application`/provider init, WorkManager init), which is where OEM battery managers lose time. The FR-ING-A-01 number is therefore **broadcast enqueue → commit**: the system's `SMS_RECEIVED` enqueue time from `dumpsys activity broadcasts history` (wall clock; only the two timestamps are kept, see T-008 manual step 6), matched to each row by its receive wall clock (`rx_wall_ms`) and the latest dispatch before it, to the DB commit. Next to it: **process start → commit** (`t_proc` = `Process.getStartElapsedRealtime()`, `cold_process` rows only) and **receive → commit** (t0 → t8, the stage the app controls). The AC2 decision rule below is applied to enqueue → commit. Android 8.0 (API 26) prints broadcast times in whole seconds, so on that image enqueue → commit is overstated by < 1 s (the report flags those rows). The enqueue time is the system's, not the SMSC's: radio and modem delays before the telephony stack enqueues the broadcast are outside every interval (optional SMSC delta column: FU-081).

**Results.** Emulator rows come from the `sms-spike` workflow (`ci/T-008`, API 26/30/34/36, x86_64 emulator, CI hardware: indicative only). Device rows come from the manual runs in `docs/04-tasks/tasks/T-008.md` (Verification) and are pending the devices (PO question Q1).

Emulator, killed process before each SMS (`sms-spike` run 42963791982 @ be50e98, profile build, linger 0; small n, so p95 ≈ max). Each cell is p50 / p95 / max in ms. Bucket 5 = exempted, 10 = active, 40 = rare, 45 = restricted; API 26 has no buckets; the API 30 image keeps `restricted` at 40, so its rare row holds both cells. The default row includes the canary message; the one `warm_process` message per run (process still alive) is left out. "ack" = rows timed by the ack stamp (upper bound, see Clock).

| Device | Android | Condition | n | **enqueue → commit** | process start → commit | receive → commit | ≤ 10 s (enqueue) | ack |
|---|---|---|---|---|---|---|---|---|
| Emulator (CI) | 26 | cold, default | 7 | 1009 / 1431 / 1431 ¹ | 357 / 449 / 449 | 333 / 408 / 408 | 7/7 | 2 |
| Emulator (CI) | 26 | cold, exempt | 6 | 1014 / 1498 / 1498 ¹ | 367 / 490 / 490 | 317 / 400 / 400 | 6/6 | 0 |
| Emulator (CI) | 26 | cold, Doze forced | 2 | 722 / 1057 / 1057 ¹ | 316 / 351 / 351 | 273 / 334 / 334 | 2/2 | 0 |
| Emulator (CI) | 30 | cold, default (active) | 7 | 583 / 724 / 724 | 538 / 672 / 672 | 307 / 375 / 375 | 7/7 | 0 |
| Emulator (CI) | 30 | cold, exempt | 6 | 612 / 620 / 620 | 556 / 576 / 576 | 304 / 324 / 324 | 6/6 | 0 |
| Emulator (CI) | 30 | cold, rare (+ restricted request) | 12 | 590 / 632 / 632 | 538 / 565 / 565 | 284 / 326 / 326 | 12/12 | 0 |
| Emulator (CI) | 30 | cold, Doze forced | 2 | 521 / 538 / 538 | 481 / 502 / 502 | 256 / 267 / 267 | 2/2 | 0 |
| Emulator (CI) | 34 | cold, default (active) | 7 | 455 / 697 / 697 | 370 / 603 / 603 | 224 / 433 / 433 | 7/7 | 1 |
| Emulator (CI) | 34 | cold, exempt | 6 | 461 / 538 / 538 | 379 / 410 / 410 | 210 / 252 / 252 | 6/6 | 0 |
| Emulator (CI) | 34 | cold, rare | 6 | 472 / 515 / 515 | 383 / 447 / 447 | 215 / 246 / 246 | 6/6 | 1 |
| Emulator (CI) | 34 | cold, restricted | 6 | 499 / 602 / 602 | 411 / 504 / 504 | 259 / 321 / 321 | 6/6 | 0 |
| Emulator (CI) | 34 | cold, Doze forced | 2 | 483 / 545 / 545 | 384 / 458 / 458 | 235 / 312 / 312 | 2/2 | 0 |
| Emulator (CI) | 36 | cold, default (active) | 7 | 708 / 1348 / 1348 | 593 / 1198 / 1198 | 285 / 648 / 648 | 7/7 | 1 |
| Emulator (CI) | 36 | cold, exempt | 6 | 722 / 1149 / 1149 | 610 / 1054 / 1054 | 288 / 439 / 439 | 6/6 | 1 |
| Emulator (CI) | 36 | cold, rare | 6 | 731 / 765 / 765 | 630 / 668 / 668 | 299 / 337 / 337 | 6/6 | 1 |
| Emulator (CI) | 36 | cold, restricted | 6 | 737 / 778 / 778 | 619 / 672 / 672 | 317 / 370 / 370 | 6/6 | 1 |
| Emulator (CI) | 36 | cold, Doze forced | 2 | 697 / 744 / 744 | 589 / 641 / 641 | 272 / 309 / 309 | 2/2 | 0 |

¹ Android 8.0 broadcast history has whole-second times: overstated by < 1 s.

Every emulator message committed within 1.5 s of the system enqueuing its broadcast; on API 30-36 receive → commit is only 40-55 % of it, the rest being process start and broadcast queueing, so the earlier receive → commit table (run 42957206135 @ d20b370) understated FR-ING-A-01 latency by about that much. On emulators the battery exemption makes no difference. Emulators have no OEM battery managers and run Doze/bucket states on demand, so these rows don't answer FR-ING-A-01 for real phones.

| Device | Android | Condition | n | **enqueue → commit** | process start → commit | receive → commit | ≤ 10 s (enqueue) | ack |
|---|---|---|---|---|---|---|---|---|
| Samsung A-series (Q1) | | default / exempt / Doze / rare / restricted / "Sleeping apps" | pending | | | | | |
| Xiaomi / Redmi (Q1) | | default / exempt / Autostart off / battery saver | pending | | | | | |

**Battery-optimisation prompt (AC2).** Decision rule: the prompt is needed only if a device's default-settings p95 (enqueue → commit) exceeds 10 s **and** the exemption brings it within 10 s. Until the device rows exist the answer is "not shown". If it is needed, the app only links to the system settings list (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, no permission); the `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog, which Play restricts, is never used (PO, Q3, 2026-11-11). If a device misses the 10 s p95 only under OEM defaults (e.g. Xiaomi Autostart off, Samsung sleeping apps), the product adds an OEM guidance screen (PO, Q2) rather than restating FR-ING-A-01. Force-stop blocks delivery until the next launch; it is recorded, not counted as a failure.

**Known gaps the spike does not close** (each has an owner): messages lost before the spool rename (ms window), during force-stop, before the first unlock (the receiver is not direct-boot aware; credential storage is locked anyway), on a full spool or after a lost spool key are recovered only by the inbox catch-up scan the PO approved for every app open in the Sms build (Q7, 2026-11-11; native `queryInbox` T-042, Dart scan T-048; `kInboxCatchUpEnabled` stays false until they land).
