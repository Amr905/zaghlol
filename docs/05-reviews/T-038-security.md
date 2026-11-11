# T-038 Security and privacy review

| Field | Value |
|-------|-------|
| Task | T-038 Android Capture Guard (Kotlin) with the two-part config reader (C4, SMS/notification ingestion) |
| Branch / commit | `task/T-038-guard-kotlin` @ `fb606d7` (diff base `origin/task/T-038-T-039-design-notes`) |
| CI | app-ci on `ci/T-038`, run 42996490126: green. `kotlin unit tests (Gradle)` ran `testDevNoSmsDebugUnitTest` / `testDevSmsDebugUnitTest`, so the guard JVM suite ran. The instrumented suite did **not** run (see M-1). |
| Reviewer | security-privacy-reviewer (Opus), 2026-11-11 |
| Verdict | **APPROVED**. Nothing must change before this merge. M-1 and L-1 must be done before T-040 merges, because T-040 is the first task that calls this code. |

## Scope and method

I read every file in `app/android/app/src/main/kotlin/app/zaghlol/platform/guard/`, `SpoolKey.kt` (imported, unchanged), the `build.gradle.kts` delta, the manifest and the backup / data-extraction rules, the new `golden.json` entries and config `t1`, and the shared runner and tests. For parity I compared the code with the Dart `capture_guard.dart`, `guard_config.dart`, `text_normalizer.dart` (the fold tables, entry by entry) and `portable_regex.dart`. I checked the CI job log to confirm that the guard JVM tests ran. I did not run anything on a device.

## What I verified (no finding)

- **Never logging (CLAUDE.md §2.6).** `platform/guard/*.kt` has no `Log`, `print`, `System.out/err`, `printStackTrace` or `Timber`. No exception message carries input:
  - `StrictJsonException` has a fixed message.
  - `ConfigFailure`, `GuardConfigException` and `GuardConfigWriteException` carry an error code and a JSON path only. Path segments are fixed key names, indexes, or institution codes that passed `isInstShape` before they are used (`GuardConfig.kt:361-363`, `371-375`). An unknown key is reported at the parent path, without echoing the key (`GuardConfig.kt:300-305`).
  - The three config exceptions override `fillInStackTrace`.
  - Store failures replace the underlying `IOException`/Keystore exception instead of wrapping it, so no file path and no cause chain leaks (`GuardUserConfigStore.kt:174-179`).
  - Every `toString` (decision, snapshot, load, keys, senders, store, limiter) prints kinds, reasons, modes or codes only. `Keep.toString` omits `last4` and `inst`.
  - `GuardNeverLogsTest` covers this with a canary and captured stdout/stderr, plus a scan of the source files.
- **Key.** The user part uses `SpoolKey.get()` (`GuardUserCipher.kt:34`, `46`). That is alias `zaghlol_spool_v1`: TEE-only (`REQUEST_STRONGBOX = false`), no `setIsStrongBoxBacked`, non-exportable, no user-auth requirement (so capture works while the app is locked). There is no `KeyGenerator` in `guard/` (FU-068). It is separate from `zaghlol_db_kek_v1` (K_db) and from the backup key, and matches the K_spool row of security-model §3.
- **Nonce and AAD.** `init(ENCRYPT_MODE, key)` passes no IV, so the Keystore generates a random 96-bit nonce (`setRandomizedEncryptionRequired(true)`), and the code checks the length (`GuardUserCipher.kt:36-37`). The tag is 128 bits. The AAD `zaghlol.guard.v1|user` is a separate domain from `zaghlol.share.v1|…` and `zaghlol/k_db/v1`, so a share or spool blob under the same K_spool cannot be swapped in, and the AAD-swap test proves it. Not binding a generation counter (I-6) is an accepted risk: a rollback needs sandbox write access, and T-047 rewrites the file on every start.
- **Location and backup.** The file is `noBackupFilesDir/guard/guard.user.enc` (L-1), created by `Files.createDirectories` under the app umask (0700). `allowBackup=false`, `fullBackupContent` and `dataExtractionRules` (cloud **and** `<device-transfer>`) exclude every domain. Even if the file were copied off the device, it cannot be decrypted without the non-exportable key.
- **Atomic write.** The order is: validate (size, then the full reader) → encrypt → `.tmp` + `fd.sync()` → `ATOMIC_MOVE` → best-effort directory `Os.fsync`. Any failure deletes the tmp and keeps the old file and the old snapshot. Fault-injection tests cover each step.
- **Auth failure and key loss.** `AEADBadTagException` (and a too-short or oversized file) → `Unreadable` → `baseOnly` + `UNREADABLE`, cached, file kept, never deleted. Other Keystore or I/O errors → `Transient` and not cached. Neither path leads to "capture everything":
  - an invalid or missing base → `INVALID_SNAPSHOT` → every message is dropped as `config_invalid` (`GuardRuntime.kt:65-70`, `119-124`);
  - a user-part failure → base rules only (PO Q1 `KEEP_WITH_BASE`);
  - an exception inside `decide` → drop (`CaptureGuard.kt:20-25`).
- **Untrusted input.** Base ≤ 200 KB (bounded asset read), user ≤ 64 KB, file ≤ 64 KB + 28 bytes, all checked before decoding. UTF-8 decoding is strict (REPORT). JSON is a strict RFC 8259 parser with depth ≤ 16 and recursion bounded by that depth. Unknown keys, types, lengths, list caps and pattern length are all enforced. Body ≤ 4,000 and source ≤ 256 UTF-16 units are checked before any fold or regex.
- **No user-controlled regex.** The user part holds only literal institution codes, last-4 values, channels and sender keys (`GuardConfig.kt:414-443`). Every pattern comes from the bundled base asset, which is covered by the APK signature and by the registry lint (portable subset plus backtracking heuristic) at export. `decide` catches `StackOverflowError` from `java.util.regex` recursion and rethrows OOM.
- **Parity with Dart.** The decision steps, their order, the `lines`/`folded` split, `guardLast4` (first match per pattern), `_resolve` (including the Apple Pay tie), the fold tables (identical code-unit sets), the Dart trim set and the reader quirks (BOM, duplicate key, duplicate package, int vs double) were ported line for line. Each is pinned by golden entries and by named negative proofs. On the JVM, the trimmed folded text never ends in a line terminator, so the Java-vs-Dart `$` difference cannot show up. The portable subset bans `\s \d \w \b`, which removes the ICU Unicode-class gap. I found no remaining port-level path where native keeps an OTP Dart drops, or drops a transaction Dart keeps. The device engine is still unproven (M-1).
- **Golden fixtures** are synthetic (`"synthetic"` flag; `NBE` / `com.example.nbe`, made-up amounts). The golden directory is added only to the `androidTest` assets and is never packaged into the app APK; `GuardGoldenInstrumentedTest` asserts this.
- **Rate limiter.** In memory only (sender ids are never persisted), `@Synchronized`, uses a monotonic clock, and handles a clock that goes backwards.

## Findings

### M-1 Medium, before T-040 merges: device-regex parity and ICU timing are unproven (AC1)

**Where.** `GuardGoldenInstrumentedTest.kt` is compiled but has never run. The implementation notes say it is waiting for T-039's `connectedDevSmsDebugAndroidTest` step. AC1 requires both the JVM and the instrumented suite on API 26/30/34/36.

**Leak path.** On a device, `Regex` runs on ICU4C (libcore), not on the JVM engine that the green suite used. Any engine difference in the global drop patterns is the T-035 M-1/M-2 class of bug, and it would surface only there:
- a pattern that matches on the JVM but not on ICU means an OTP is kept and spooled (BR-ING-03);
- the reverse means a real debit is dropped.

There is also a time risk. ICU has no regex time limit by default, so a pathological match of an attacker-sent 4,000-char body against a registry pattern runs on the receiver thread with no timeout. The only bound is the lint heuristic plus the adversarial golden bodies, and on ICU those bodies have only run on paper.

**Required change.** Run the instrumented golden suite on all four API levels. Record the parse/compile time and the worst adversarial `decide` time in the task file. Keep AC1 unchecked until both pass. T-040 must not wire `GuardRuntime.decide` into the receiver until this is green. This does not block merging T-038 itself, because nothing in production calls this code yet.

### L-1 Low, before T-040 merges: the channel is a free string, and three channels keep regardless of sender

**Where.** `GuardRuntime.decide(channel: String, …)` (`GuardRuntime.kt:78`) and `CaptureGuard.kt:46-49`. `apple_pay`, `shortcut_message` and `share` are `GENERIC` keeps for **any** source and body that is not an OTP/promo.

**Leak path.** On Android only `sms` and `notification` are legitimate. Suppose a T-040/T-043 wiring mistake passes one of the iOS/sender-less wires: a constant mix-up, a future "paste from SMS" path reusing `share`, or a mapping from an unknown intent extra. On that path the native Guard becomes "keep every non-OTP message". That spools personal SMS, which is exactly the Play SMS-policy and spyware failure that the Guard exists to prevent (security-model §1, FR-ING-A-02). Today an unknown string fails closed (`unknown_channel`), but these three known strings fail open.

**Required change (owner T-040).** Give the Android entry point a typed channel restricted to `{SMS, NOTIFICATION}`. Either add an `AndroidGuardChannel` enum, or reject the other three in `GuardRuntime.decide` with `Drop(unknown_channel)`. Add a test that `GuardRuntime.decide("share" | "apple_pay" | "shortcut_message", "anyone", "hello")` drops. `CaptureGuard` stays the shared port, so golden parity is unaffected.

### L-2 Low, follow-up: the transient read path recompiles the whole base for every message

**Where.** `GuardRuntime.kt:145-153`: on `Read.Transient`, the snapshot is not cached, so every message calls `GuardConfig.parse(base, …)`. The base bytes are cached; the compiled config is not.

**Leak path / impact.** This is availability, not a leak. While the Keystore or the file system keeps failing (for example a Keystore daemon problem after an OTA), each SMS or notification costs a file read, a Keystore op, a full JSON parse and around a hundred regex compiles (target ≤ 20 ms; the emulator bound is 100 ms) on the receiver or listener thread. A burst of spoofed SMS multiplies that. It is not unbounded and it fails closed toward the base rules.

**Required change.** Cache the compiled base `GuardConfig` separately from the user state, and on `Transient` reuse it with an empty user part. Track it as a follow-up owned by T-040.

### L-3 Low, follow-up: the per-sender rate limit can be turned against the user

**Where.** `SenderRateLimiter.kt:30-45`; `GuardRuntime.kt:82` applies it to every `Keep`.

**Leak path / impact.**
1. **Suppression.** Someone who spoofs a registry alphanumeric sender (SMS blasters and SIM boxes make sender-ID spoofing practical in Egypt) can send `perSenderPerMin` non-OTP messages under `NBE` and push a genuine NBE debit in the same 60 s window into `rate_limited`. That is a silently missed transaction. Dart behaves the same; the rate limiter is the design.
2. **No global bound.** Keys are per `(channel, source)` with an LRU of 64, so a flood that rotates generic-hint senders gets a fresh budget per id. The limiter is a courtesy bound, not an abuse control. The real bound is the spool cap (T-039).

**Required change (follow-up, owners T-039/T-040/T-041).**
- Confirm that the spool cap is the hard global bound.
- Count `rate_limited` drops in the capture diag (count only, no sender).
- Have the SMS inbox catch-up (T-041) re-read a sender's window after a rate-limited drop, so a suppressed debit is recovered from the system inbox.

Notifications cannot be recovered that way; document that.

### I-1 Info: the `KEEP_WITH_BASE` window ignores the user's ignore rules and user senders

While the user part is `UNREADABLE` or `RETRY`, the native Guard spools messages from cards and institutions the user chose to ignore, and drops messages from senders the user added (`not_financial`). The first is covered by the T-046 drain-time Dart re-check (platform-channels: "Drain-time re-check"), so **T-046 must land before T-040 ships**. The second is data loss for notifications. This is PO Q1 (provisional); the reviewer has no objection to the default, provided the state is surfaced through `getSpoolStatus().guardState` (T-039).

### I-2 Info: a Guard read can create the spool key on the receiver thread

`KeystoreGuardUserCipher.decrypt` → `SpoolKey.get()` (`GuardUserCipher.kt:46`). The current `SpoolKey` creates a key when `getKey` returns null. A spurious recreate invalidates every spooled entry. The T-039 classifier-and-retry policy (platform-channels §1.3: recreate only on `UNUSABLE` after the 100/300/900 ms retries) must sit **inside `SpoolKey`**, not in the spool's callers, so that this new caller inherits it. Owner T-039.

### I-3 Info: "Delete everything" and the in-memory snapshot

After a wipe (security-model §5, step 3 deletes `noBackupFilesDir/guard/`), the process-wide `GuardRuntime` keeps the old user senders and ignore rules in memory until the process dies, and a cached `FULL` snapshot keeps being used. The wipe owner should reset `GuardRuntime` (add a `reset()`) or end the process. Owner: the wipe task, with T-040.

### I-4 Info: zeroing is partial (documentation only)

`json.fill(0)` and `read.bytes.fill(0)` zero the byte arrays. The decoded `String`, the parsed maps and the cipher's internal buffers cannot be zeroed, and the parsed rules live in the snapshot anyway. That is acceptable for this data class. The self-check should say "best effort" rather than imply that the plaintext is gone.

### I-5 Info: the native reader trusts the export-time portability lint

`GuardConfig.compile` (`GuardConfig.kt:208-214`) accepts any pattern Java can compile. Portability is enforced only by `exportGuardConfig`/the registry lint. The base is APK-signed, so this is acceptable. When T-036 bundles the real base, the instrumented "bundled base" test should also assert that it passes the golden runner on device (already planned), so a lint bypass is caught there.

## Summary

| ID | Severity | Before merge? | Owner |
|----|----------|---------------|-------|
| M-1 | Medium | Before T-040 merges (not T-038) | T-038/T-039 CI step |
| L-1 | Low | Before T-040 merges | T-040 |
| L-2 | Low | Follow-up | T-040 |
| L-3 | Low | Follow-up | T-039/T-040/T-041 |
| I-1 | Info | T-046 before T-040 ships | T-046/T-039 |
| I-2 | Info | Follow-up | T-039 |
| I-3 | Info | Follow-up | wipe task/T-040 |
| I-4 | Info | Follow-up | T-038 docs |
| I-5 | Info | Follow-up | T-036 |

**Verdict: APPROVED.** T-038 adds no egress, no logging, no user-controlled regex and no fail-open path. The encrypted user part uses the right key, a Keystore-generated nonce, role-bound AAD, a no-backup location and an atomic write, and it never silently discards data. AC1 stays open until the instrumented suite runs (M-1).
