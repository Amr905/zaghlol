# T-039 Security and privacy review

| Field | Value |
|-------|-------|
| Task | T-039 Android encrypted spool + spool host API (C4, SMS/notification ingestion, keys) |
| Branch / commit | `task/T-039-spool` @ `34ff60e` (diff base `origin/task/T-038-T-039-design-notes`) |
| Reviewer | security-privacy-reviewer (Opus), 2026-11-11 |
| Verdict | **APPROVED** (no Critical, High or Medium findings; Low/Info are follow-ups, none marked before merge) |

## Scope and method

I read the whole diff. I paid most attention to `platform/spool/{SpoolStore,SpoolKey,SpoolCipher,CaptureStatusStore,SpoolRecord,Ulid,SpoolClaim}.kt`, `platform/capture/AndroidCaptureHost.kt`, the regenerated `CaptureApi.g.kt` (error wrapping, `SpoolEntry`), `app/pigeons/capture_api.dart`, `src/androidTest/AndroidManifest.xml`, both instrumented tests, the devSms spike changes, the `app-ci.yml` no-logging grep, the main manifest and the backup/extraction rules, and the task file (design note, implementation notes, deviations 1-6). I checked the key alias against the other Keystore aliases in `src/main` and looked at the `KeyErrorClassifier` used for the delete-on-proof rule. I did not run the suites again; CI is green (app-ci 43003825211, sms-spike 43003825506 on API 26/30/34/36).

## What holds (checked)

- **No plaintext on disk at any point.** `SpoolStore.write` (l. 182-234) encodes and encrypts in memory. Only the ciphertext reaches `<ulid>.bin.tmp`, which then goes through fsync, `ATOMIC_MOVE` and a directory fsync. The encoded plaintext is zeroed in `finally`. `CaptureStatusStore.writeLocked` (l. 185-205) works the same way. The host never writes the Guard config itself: it passes the bytes to the injected writer and zeroes them (`AndroidCaptureHost` l. 60-71), so the `encryptedConfig` → `userConfigJson` rename changes only the name. The bytes stay in memory on the platform channel, and encryption at rest is T-038's job (`GuardRuntime`).
- **K_spool.** Alias `zaghlol_spool_v1`. It is separate from `zaghlol_db_kek_v1`, and no other code in `src/main` generates or deletes it (`KeystoreShareCipher` goes through `SpoolKey.get()`). The key is AES-256-GCM, non-exportable, requires no user auth, uses `setRandomizedEncryptionRequired(true)` (Keystore picks the IV) and never calls `setIsStrongBoxBacked`, which the instrumented test asserts on API 31+. The key is deleted and recreated only after four `UNUSABLE` answers in a row (`SpoolKeyManager.get` l. 110-125). Any `UNAVAILABLE` answer throws and deletes nothing. The retry ladder now runs inside `SpoolKey` (T-038 security I-2 is resolved).
- **Nonce / AAD.** Every entry and the status file get a fresh 96-bit IV from Keystore, and `KeystoreSpoolCipher.encrypt` checks it is 12 bytes. The AAD domains are distinct: `zaghlol.spool.v1|entry|<ulid>` binds each entry to its own name, so a swap or rename fails the tag (`swappedFileFails…` test). The status file uses `zaghlol.capture.v1|status`, Guard uses `zaghlol.guard.v1|user` and share uses `zaghlol.share.v1|…`. One key covers several domains, which is safe with distinct AADs, and the volume is far below the random-nonce GCM limit.
- **Delete on proof only.** A tag failure, a format error or an oversize file is proof. I/O and Keystore errors keep the entry (`read` l. 264-307). Absence is proven with `NoSuchFileException`, never `FileNotFoundException` (l. 271-277, M10). The stale-key fast path (l. 293-296) still needs a real tag failure. A clock moved back can only make an entry that already failed authentication skip the ladder, and that entry would be deleted at the end of the ladder anyway. So the clock cannot cause any extra deletion.
- **Location / backup.** The files live in `noBackupFilesDir/spool`, `/capture` and `/guard`. The manifest sets `allowBackup=false`, and `data_extraction_rules.xml` excludes every domain from both `<cloud-backup>` and `<device-transfer>`. Even if a copy leaked, the Keystore key does not travel with it, so the copy is unreadable and the stale-key path deletes it.
- **Ack authority.** `ackSpool` keeps only ids that are valid ULIDs **and** are in this host's own `drained` set (l. 114-120), and refuses more than 100 ids. A late ack after a claim expiry, or a stray ack from the other engine, cannot delete an entry that engine never received. If both engines receive the same entry after an expiry, the DB's `body_hash` deduplicates it, and the drained set is pruned to the entries still on disk at each drain (deviation 6).
- **Flood bounds.** There is a hard cap of 500 entries / 4 MiB with tmp files counted. Generic keeps are refused once the spool holds 250 entries or 2 MiB of any kind. On top of that, a best-effort limit of 10 generic writes per minute uses the monotonic clock. Nothing is ever evicted. A refusal is recorded and the drain is still scheduled (spike `SmsIntake`, AC4).
- **No leaks through text.** `SpoolRecord`, `WriteResult`, `ReadResult.Ok` and the status exceptions have redacted or code-only `toString`/messages. The `guarded` wrapper (l. 160-166) rethrows every failure as `CaptureApiError(code, null, null)`, so Pigeon's `wrapError` fallback (which would add `toString()` and a stack trace) is never reached. `canaryNeverLeaks` covers exceptions, `toString`, stdout/stderr and file bytes. The no-logging grep now covers `platform/spool`, `platform/capture` (non-generated) and `platform/guard`.
- **Status file.** It has a fixed length of 49 bytes, holds no content and is written only on an alert or a clear. If the file is proven unreadable it is reset with a random `seq` (deviation 4), so a stale `clearSpoolAlerts` cannot wipe alerts that came after the key loss.
- **androidTest manifest.** `src/androidTest/AndroidManifest.xml` is merged only into the instrumentation APK, not into any app variant. It only adds `exported="true"` to androidx.test invoker activities, which come from `androidTestImplementation` and from the dev-only `integration_test` plugin.

## Findings

### L-1 Low: a spoofed-SMS flood can make *notifications* unrecoverable (cross-channel spool exhaustion)

**Where.** `SpoolStore.write` l. 198-205: the `FULL` cap is shared by both channels, and `PRIORITY` keeps have no per-channel share.
**Path.** An attacker spoofs a registry bank sender ID with alphanumeric sender spoofing through a cheap SMS gateway and sends financial-looking texts. These are `PRIORITY` keeps. The per-sender Guard limit is best-effort per process (20/min, T-035 Q3). While the spool cannot drain (worker deferred, DB busy, app killed), about 500 such SMS fill it. From then on, every real wallet or bank *notification* is refused and lost for good: only `missedNotifications` is counted. The refused SMS themselves are recovered by the inbox catch-up. So the cheap, recoverable channel can push out the channel that cannot be recovered.
**Required change (follow-up, T-040/T-043 owner, with PO Q1).** Keep a share for notifications. One option is to refuse `sms` keeps at about 80 % of the caps (SMS can always be recovered from the inbox), so that notifications keep the last 100 entries / 0.8 MiB. Add one test: SMS stop at the reserve while a notification is still written.

### L-2 Low: every refused write rewrites the status file inside the store lock (flood amplification)

**Where.** `SpoolStore.write` l. 206-208 → `CaptureStatusStore.recordRefused` → `mergedLocked` (read + Keystore decrypt + encrypt + fsync + rename), all while the store lock is held.
**Path.** When the spool is full, each further kept message costs two Keystore operations and two fsyncs on the single intake executor, which the SMS receiver's `goAsync` window also uses. Under a flood this adds latency and flash writes per message. The refused messages are already lost or recoverable, but legitimate writes queued behind the flood are delayed too.
**Required change (follow-up).** Coalesce: keep refusals in the in-memory `Delta` and persist at most once every N seconds, or on the next drain or `getSpoolStatus`. The first refusal in a window is still written at once, so a process kill loses at most the count, not the fact.

### L-3 Low (before the PO device run, not before merge): the instrumented key test deletes the real spool key of the installed dev app

**Where.** `SpoolKeyInstrumentedTest.kt` l. 75: `deleteEntry(SpoolKey.ALIAS)`. Manual steps 1-2 in the task file install the devSms debug build with `-r` on a phone.
**Path.** If the PO's phone has used `app.zaghlol.dev` with real messages, running step 2 replaces the production alias. Pending spool entries, the Guard user file and share-intake files of that install become unreadable and are deleted on proof. The test directories are separate, but the alias is shared.
**Required change.** Add a warning line to the manual steps: run only on a clean dev install, or `adb uninstall app.zaghlol.dev` first. A test-only alias seam would also work, but `SpoolKey` is a fixed `object` by design, so the warning is enough.

### I-1 Info: wiring defaults that T-041 must override

`SpoolStore`'s defaults are `status = null`, which means refusals and decrypt deletions are not recorded, and `keyCreatedAtMs = { null }`, which means every stale entry pays the 1.3 s ladder (the I-3 regression). The spike wires both (`SpikeRuntime`). T-041 must pass `CaptureStatusStore`, `SpoolKey::creationDateMs` and `SystemClock::elapsedRealtime` when it registers `AndroidCaptureHost`, and should add a test that builds the production graph and asserts that `status` is non-null.

### I-2 Info: plaintext metadata (accepted)

Anyone with the app UID or root can see: ULID names, which give receive times to the millisecond (accepted, FU-086 I-2, platform-channels §1.3); the entry count; the exact size of each file, which is plaintext length + 28 and so roughly the body length, enough to tell a short OTP-like text from a long statement; and whether `capture/status.bin` exists, which shows that some alert happened. None of this is content, and it is gone after ack. If the PO wants to reduce it later, padding records to 256-byte buckets would hide most of the length signal at little cost.

### I-3 Info: deletion is unlink only (acceptable)

Ack and delete-on-proof call `File.delete()`. The ciphertext can stay in freed flash blocks, but those blocks are under file-based encryption (CE key) and the spool key is non-exportable. "Delete everything" (security-model, step 4) deletes the Keystore items, so what is left cannot be decrypted. Overwriting before unlink would add nothing on flash with wear levelling.

### I-4 Info: heap copies of plaintext

`SpoolRecord.body`, `SpoolEntry.body` (Kotlin `String`), `ByteArrayOutputStream`'s internal buffer in `SpoolRecordCodec.encode`, and Pigeon's codec copy of `userConfigJson` cannot be zeroed. This is inherent to the JVM and the platform channel. The zeroing that is done is still worth keeping.

### I-5 Info: generated `SpoolEntry` is a Kotlin `data class` (pre-existing, T-004)

Its auto-generated `toString()` contains `body` and `source`. Nothing prints it today, and the grep plus `canaryNeverLeaks` would catch a direct log. Still, any future `"…$entry"` in an exception message would leak the SMS body. Record it in the T-040/T-043 briefs: never interpolate a `SpoolEntry` into a string.

### I-6 Info: status file rollback

The status AAD is constant. Someone who can write the app's private storage could put back an older valid `status.bin` and hide alerts. That needs the app UID or root, which already exposes everything else, so no change is needed.

### I-7 Info: release-manifest assertion

Consider extending the `apk-perms` CI step so that it asserts the release (prod) merged manifest contains no `androidx.test` component. That way the androidTest manifest override can never reach a shipped APK, even if a future dependency change moves androidx.test onto a main classpath.

## Store policy

T-039 adds no permission, no exported component and no network call. The spool keeps only messages the Guard kept, and the status file is written only on alerts (a personal SMS leaves no file). This matches the minimisation that the SMS-based money-management exception expects.

## Verdict

**APPROVED.** The spool's at-rest encryption, the key lifecycle, delete-on-proof, ack scoping and the redaction meet the security model and the T-039 design note. L-1 and L-2 go to follow-ups (T-040/T-043, alongside PO Q1). L-3 is a one-line doc warning to add before anyone runs the manual device steps. I-1 must be covered in the T-041 brief.
