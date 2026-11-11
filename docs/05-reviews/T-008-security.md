# T-008 security and privacy review (SPK-01 SMS ingestion spike, devSms)

Reviewer: security-privacy-reviewer (Opus). Branch `origin/task/T-008-sms-spike` @ 73421ad. Scope: T-008's own changes
(`git diff 283766b..73421ad`, 84 files; the T-017/T-033 merge commits are out of scope). Inputs: T-008.md (design note,
Lead/PO decisions Q2-Q8, deviations), ADR-005, security-model §1/§3/§7 (`K_spool`, logging, IPC), platform-channels §1.3,
CLAUDE.md non-negotiables 1, 2, 6. I read every Kotlin file in `src/devSms` and `src/testDevSms`, the three flavour manifests,
the Dart ingestion engine, the opener/bootstrap changes, both CI scripts and the workflows. I did not build or run anything
(no Gradle/emulator in this sandbox); emulator evidence is the cited `sms-spike` run 42957206135.

## Verdict: APPROVED

No Critical, High or Medium finding. Five Low and five Info items become follow-ups; none is marked "before merge". L-1
(`VISIBILITY_PUBLIC`) is a one-line fix the implementer may take in the same pass.

## What I checked and found sound

- **Egress.** No network code in the spike. The headless engine registers only `JniPlugin`, `JniFlutterPlugin`,
  `SecretStoreRegistration`, the spool host and the spike metrics channel (`HeadlessEngine.kt` l.137-147,
  `automaticallyRegisterPlugins = false`). WorkManager 2.12.0 is the only new dependency, scoped to `devSmsImplementation`
  (`build.gradle.kts`), and it has no telemetry.
- **Receiver spoofing.** `exported="true"` with `android:permission="android.permission.BROADCAST_SMS"`, no priority, never
  `abortBroadcast` (`src/devSms/AndroidManifest.xml` l.13-21). The receiver also returns unless the action is
  `SMS_RECEIVED_ACTION` (`SpikeSmsReceiver.kt` l.21). `SMS_RECEIVED` is also a protected broadcast, so the shell broadcast in
  `sms-spike-device.sh` l.111 is refused by the system before the receiver's own check runs. That is defence in depth, and
  the hard checks are an empty spool, the aapt2 receiver/permission check (`check-sms-spike-placement.sh` l.23-30) and
  `SpikeSourceTest` (attribute removed → red, per the negative proofs). Third-party apps can't deliver to the receiver.
- **Flavour placement.** Receiver, permissions, WorkManager and all spike Kotlin are in `src/devSms`/`src/sms` source sets
  only. `src/noSms` removes the six SMS/MMS/WAP permissions in both `uses-permission` and `uses-permission-sdk-23` forms
  (T-003 F11 closed). `staging*`/`prod*` can't compile `src/devSms` (Gradle source-set rule), and the CI step checks the merged
  manifest of all six APKs. `EngineHooks` in `main` is an empty list unless the devSms-only `androidx.startup` initializer
  registers the hook.
- **Log / crash / exception hygiene (non-negotiable 6).** `SpikeLog.e(code, ms)` has no parameter that could carry text and
  is enabled only on debuggable builds (`SpikeLog.kt`). Every `toString()` of a message-bearing type is redacted (`SmsPart`,
  `AssembledSms`, `SpoolRecord`, `Keep`, `ReadResult.Ok`). Every host method rethrows `CaptureApiError(code, null, null)`
  (`SpoolHost.kt` l.123-130), so Pigeon's `wrapError` (`CaptureApi.g.kt` l.33-37, which adds `toString()` and the stack for
  other throwables) is never reached from spike code. In Dart, `PlatformFailure.fromChannel` drops non-UPPER_SNAKE codes
  (FU-034). The headless isolate installs `FlutterError.onError`, `PlatformDispatcher.onError` → `true` and a muted
  `debugPrint` before any work (`ingestion_main.dart`, `quiet_errors.dart`). The cycle catches parser, DB (incl. drift
  `SqliteException`, whose `toString` would include bound parameters) and channel errors and returns codes only
  (`ingestion_cycle.dart`). Exception constructors in spool code use fixed codes (`"SPOOL_DIR"`, `"BODY_TOO_LONG"`, ...).
  Canary coverage: JVM (`CanaryTest`: log sink, stdout, stderr, thrown errors, metrics CSV, spool bytes), Dart
  (`quiet_errors_test` with zone `print` capture, `spike_channel_test`), CI grep over spike Kotlin + `lib/ingestion`, and the
  emulator logcat scan filtered to the app uid, which fails if that filter matches no line (`sms-spike-device.sh` l.140-146).
- **Spool crypto.** Key only through `SpoolKey.get()` (TEE, non-StrongBox, alias `zaghlol_spool_v1`; no `KeyGenerator` in
  spike code, asserted by `SpikeSourceTest`). AES-256-GCM with a Keystore-chosen random 12-byte IV and a 128-bit tag. AAD
  `zaghlol.spool.v1|entry|<ulid>` binds the entry to its file name (`SpoolStore.kt` aad()), and the swap → delete case is tested.
  The `.tmp` holds ciphertext only (encrypt happens before the file opens), then fsync and atomic rename. Plaintext buffers
  are zeroed (`plain.fill(0)`, `body.fill(0)`). The directory is `noBackupFilesDir/spool` (excluded by T-165). File names
  are ULIDs only. Decoding is strict (version, field bounds, UTF-8 REPORT, trailing bytes).
- **Delete-on-proof and caps.** Only `AEADBadTagException`, `SpoolFormatException` or an oversize file, on all 4
  attempts, delete; any I/O or provider exception keeps the entry (`SpoolStore.kt` l.115-145). 500 entries / 4 MiB, counting
  `.tmp`; new messages are refused, never evicted (l.72). `.tmp` > 60 s is swept on drain. Ack deletes only valid ULIDs.
- **Capture Guard before write.** Unknown senders → `NOT_ALLOWLISTED`, OTP patterns → `OTP_OR_PROMO`, > 4,000 chars →
  `TOO_LONG` (checked before any regex). All three return before `SpoolRecord` is built (`SmsIntake.kt` process()), so dropped
  messages are never stored, even encrypted. `SmsIntakeTest`, the canary test and the emulator run show an empty `spool/`. The
  allowlist is synthetic only (`5550100`, `+15550100`); `spike_tester_sender` is empty and `SpikeSourceTest` l.62-63 fails if a
  number is committed. No real phone number in the diff (only the `+201000000000` placeholder in a test).
- **Headless engine never creates, wipes or migrates (Q6).** `ingest_store.dart` overrides `allowMigration`,
  `allowCreateOrWipe` to false (Riverpod refuses a second override). Opener: no `directory.create`. `_recoverFiles` only
  checks for leftovers and defers. `KeyBootstrap._decide(mayCreate:false)` returns `createNotAllowed` before reading the key
  when no DB file exists. `KeyCreated`/`KeyInvalidated`/rejected-key paths release the lease and return `DB_DEFERRED`.
  `MigrationGuard` throws `createNotAllowed` on `user_version 0` in drift `setup`, before `onCreate` runs. Every one of these is
  covered by `headless_open_test` with negative proofs. Missing DB → no open, spool kept.
- **Ack after commit.** The ack is sent only after `store.commit` returned. A commit failure returns `RETRY` without an ack,
  and a crash between commit and ack is absorbed by the unique `body_hash` (tested). Parser-dropped entries (`SkipEntry`) are
  acked without being stored.
- **Inter-engine claim.** One JVM lock in the single app process (no `android:process` anywhere). The claim is released
  on full ack, on detach or after 60 s. UI attach destroys a lingering headless engine. If the claim expires the result is
  double processing, and the DB dedupe absorbs it. Two writers never get the same entries concurrently (`SpoolHostTest`,
  `SpoolClaimTest`).
- **Metrics/latency files.** CSV columns are ULID, path, SDK, exemption, Doze, bucket, linger and stage deltas
  (`SpikeMetrics.kt` HEADER), with no sender, body, amount or last4. `CanaryTest` asserts neither the canary nor `5550100`
  appears. The file is capped at 1 MiB under `no_backup`. The CI artifact holds only `metrics.csv` and `report.md`
  (synthetic emulator data).
- **Foreground notification (Android 8-11).** Fixed localized strings, no message data, `IMPORTANCE_LOW`, and the worker
  never calls `setForeground` (but see L-1).
- **Battery exemption (Q3).** `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` only. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is not
  declared anywhere.

## Findings

| ID | Severity | Where | Issue and leak/exploit path | Required change (owner) |
|----|----------|-------|-----------------------------|--------------------------|
| L-1 | Low | `IngestionWorker.kt` l.118 | The Android 8-11 FGS notification is `VISIBILITY_PUBLIC`, so "Zaghlol is saving a transaction" is shown in full on the lock screen. Someone near a locked phone learns that a money movement just happened, and when. It carries no amount, but it is financial metadata on a surface the owner didn't choose. | Use `VISIBILITY_SECRET` (or `PRIVATE` with a neutral public version) when T-041 moves the strings to the Sms flavour. A one-line fix the implementer may take now. |
| L-2 | Low | `SpikeGuard.kt` l.51-56 (and the registry `drop.global` it mirrors) | The OTP drop list is four patterns. `\botp\b` misses "OTP123"/"OTPcode", and the list doesn't cover "verification code", "كلمة السر لمرة واحدة", "الرقم السري المؤقت" or digits/ZWJ/tatweel variants, and there is no normalisation before the regex. For an allowlisted bank sender, an OTP that misses these patterns would be spooled and stored as a `review` row in `raw_messages`, which breaks BR-CAP-01 ("dropped before anything is written"). No impact in the spike, which allowlists only synthetic senders. | T-038: generate the Guard from the registry export with a broader OTP/promo corpus (EG Arabic + English, Arabic-Indic digits, ZWJ/tatweel), normalise (T-033 `normalizeText` equivalent) before matching, and add shared golden cases in Kotlin/Swift/Dart. Align the Dart spike registry with the native list (it lacks "كود التفعيل"; Info). |
| L-3 | Low | `lib/main.dart` l.15-17, `lib/ingestion/**` | `@pragma('vm:entry-point') ingestionMain` and the whole ingestion engine, including the synthetic spike registry, ship in every AOT build, staging and prod included (Dart has no flavours). It does nothing today, because no native code outside devSms starts that entrypoint. But it is an unreviewed DB-writing entrypoint in prod, and the CI placement check covers only native code. | Until T-041 replaces it, make `runIngestionMain` return immediately unless `appFlavor == kSpikeFlavor`, and add that case to `spike_ingestion_test`. Or accept explicitly in T-041's brief. Not before merge. |
| L-4 | Low | `SpoolStore.kt` l.72; `SpikeGuard.kt` l.37 | **SMS sender spoofing (phone network).** Alphanumeric/short sender IDs can be spoofed through SMS gateways, and the Guard keeps on sender match alone. Privacy is not at risk, because the attacker supplies the content and no personal SMS of the user is kept. Two risks remain: (a) integrity, since fake "bank" transactions enter the DB; (b) capture DoS, since 500 spoofed messages fill the spool while the DB is deferred (migration pending, first launch) or the headless engine can't run. New genuine SMS are then refused (`SPOOL_FULL`) until the UI drains, and each spoofed SMS also uses an expedited job from the App Standby quota. | T-038/T-039/T-041: (a) never auto-confirm balance or transaction effects from a sender match without a template match, and keep the review/confirm path for unrecognised bodies; (b) per-sender rate limit in the Guard (e.g. > N kept per minute → drop with a diag code), and make sure the Q7 catch-up runs after a `SPOOL_FULL` so refused genuine messages are recovered; (c) record this residual in ADR-005 threats. |
| L-5 | Low | T-008.md "Inbox catch-up design (Q7)" | Catch-up privacy and Play policy. The design is sound: address filter in SQL, the same Guard and pipeline, dedupe via `body_hash`, no logging, nothing leaves the phone. Gaps for T-042/T-048: (a) a null watermark (no `sms` row yet, or a DB wiped after a lost key) would make `since = null − 10 min` a full-history read on an ordinary app open. A first scan must go through T-048's consented, bounded first-run path, never a silent per-open read. (b) A wall-clock jump forward stores a future `received_at` as the watermark, and later scans then skip messages. (c) The projection must be minimal (`_id, address, body, date, sub_id`), with bound selection args and no `LIKE`. (d) The declaration and prominent disclosure must say "on every app open". Play's SMS-based money management exception covers budgeting apps (`READ_SMS`, `RECEIVE_SMS`), on condition that they "may not exfiltrate or share non-financial or personal SMS history"; the SQL address filter is the evidence. | T-042/T-048: null watermark → no catch-up (first-run path only); clamp the watermark to `min(maxReceivedAt, now)` and also keep the max inbox `_id` seen; minimal projection; tests that a non-allowlisted inbox row is never read into memory. T-176: per-open inbox read in the declaration, demo video and disclosure. |
| I-1 | Info | `check-sms-spike-placement.sh` l.35-36 | `prodSms`/`prodNoSms` are built `--release`, and R8 can rename `app/zaghlol/spike/*` and `androidx/work/*`, so the dex grep alone could miss a leak in release. The real control is the source-set boundary, and the manifest check (receiver, `SMS_RECEIVED`) is robust. | Optionally also grep for stable strings that survive R8 (`zaghlol.ingest`, `ingestionMain` in the AOT snapshot is L-3). |
| I-2 | Info | `SpikeMetrics.kt`, `SpikeRuntime.kt` l.30/77 | `no_backup/spike/metrics.csv` and spool file names hold ULIDs, i.e. per-message receive times in ms, as plaintext metadata outside the encrypted DB. That is acceptable for a devSms spike with synthetic senders. These files are not removed by "Delete everything" (security-model §7). | T-041: don't carry the metrics recorder or `linger_ms` into `*Sms`. When the spike is removed, delete `no_backup/spike/`. T-039: note in §1.3 that spool names reveal receive times (accepted, app-private). |
| I-3 | Info | `SpoolStore.kt` l.134 | With a regenerated `zaghlol_spool_v1` key, every pending entry fails the tag check and is deleted after 1.3 s of retries each. That matches security-model ("pending spool is lost, rare, logged"), but a drain of up to 100 such entries blocks the host thread for up to ~130 s. | T-039: detect "key newer than entry" once (e.g. one failed entry with a fresh key → `KEY_INVALIDATED`), skip the per-entry retry ladder, and trigger the catch-up scan. |
| I-4 | Info | `SpikeLog.kt` | Debug-build logcat lines (`RX_KEEP`/`RX_DROP` + ms) reveal when a message from an allowlisted sender arrived. Other apps can't read them (no `READ_LOGS`), so only adb/bugreport can. | T-021's production logger: keep `RX_*` events out of release diag, or aggregate them as counts. |
| I-5 | Info | `BoundedDispatch` / single-thread executor | If one intake hangs (Keystore stall), later broadcasts queue behind it and their `PendingResult` finishes at 5 s, so the process may be killed with queued messages. They are lost, which is the known gap that the Q7 catch-up recovers. | T-040: count `SPOOL_TIMEOUT` and trigger catch-up on next open. |

## Answers to the brief's specific questions

- **Raw SMS never logged / in crash output / metrics / exceptions:** confirmed at every layer (see above), with canaries at
  JVM, Dart and emulator level.
- **Spoofed broadcasts refused:** yes. `BROADCAST_SMS` on the receiver plus the protected-broadcast rule, proven on API
  26/30/34/36 (empty spool; denial line in `spoof.txt`).
- **Restricted permissions only in `*Sms`; spike code only in devSms:** yes (source sets, `noSms` removals, merged-manifest
  CI on all six APKs). The Dart side is the exception, see L-3.
- **Spool encryption:** sound. TEE-only `SpoolKey`, AAD bound to the id, no plaintext temp, no-backup dir, caps refuse new,
  atomic rename, delete only on proof or ack.
- **Capture Guard:** OTPs and unknown senders are dropped before any write, so they are never stored, even encrypted, within the
  patterns it knows (L-2 for coverage).
- **Headless DB:** never creates, wipes, rotates keys or migrates; verified in code and by negative proofs.
- **Sender spoofing over the phone network:** the sender-only Guard is acceptable for privacy (no user personal SMS kept)
  but not for integrity or availability; see L-4.
- **Inbox catch-up (Q7):** acceptable under the Play exception if the address filter stays in SQL and the declaration says
  "every app open"; see L-5 for the null-watermark full-history risk.

## Sources

- [Google Play: Use of SMS or Call Log permission groups](https://support.google.com/googleplay/android-developer/answer/10208820?hl=en)
  (SMS-based money management exception, eligible permissions, non-financial SMS restriction).
- [Google Play: Permissions and APIs that access sensitive information](https://support.google.com/googleplay/android-developer/answer/9047303)

---

## Re-review (delta) — `git diff 73421ad 2726f54` (Sonnet, 2026-11-11)

- **L-1 fixed.** `IngestionWorker.NOTIFICATION_VISIBILITY = VISIBILITY_SECRET`, used in the builder; `WorkRequestTest.captureNotificationIsSecretOnTheLockScreen` also fails on any `VISIBILITY_PUBLIC` in the spike sources. The channel has no explicit lockscreen visibility, so the notification's value applies (note for T-041: set it on the channel too).
- **New data in the delta.** `metrics.csv` gains `rx_wall_ms` and `t_proc` (timings only; no sender, body or amount) and stays in `noBackupFilesDir`. The emulator script saves `dumpsys activity broadcasts history` to a temp dir in CI, keeps only enqueue/dispatch timestamps of SMS_RECEIVED records in `broadcasts.txt`, deletes the dumps, and fails if the package name appears in the output. Dumps are not in the artifact list. The manual step warns testers not to share raw dumps. Emulator-only synthetic SMS. No new exposure.
- **Shutdown change.** The `close` command carries no data. Closing the database before destroy reduces the chance of a dangling SQLCipher handle; no new attack surface.
- No new finding at Low or above. L-2…L-5 and I-1…I-5 are filed as FU-082…FU-086 with owners.

**Re-review verdict: APPROVED.**
