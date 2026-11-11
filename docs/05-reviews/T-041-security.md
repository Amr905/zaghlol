# T-041 — Security and privacy review (IngestionWorker, headless engine, foreground events; T-042 reader wired)

| Field | Value |
|-------|-------|
| Reviewer | `security-privacy-reviewer` (Opus) |
| Date | 2026-11-11 |
| Branch / commit | `task/T-041-worker` @ `eaa11dd` (delta from `4df62f2`, includes the T-042 merge `0e5c4a8`) |
| CI | app-ci 43041073195, sms-spike 43041073291 (API 26/30/34/36; canary 0 logcat lines), green per Lead brief |
| Scope | `platform/ingest/**`, `platform/capture/{CaptureRuntime,AndroidCaptureHost,AndroidCaptureDevice}.kt`, `spool/{SpoolStore,SpoolKey,SpoolCipher,CaptureStatusStore}.kt`, `MainActivity.kt`, manifests (`main`, `devSms`, `noSms`, `sms`) and the WorkManager 2.12.0 AAR manifest, `build.gradle.kts`, `pigeons/ingestion_api.dart`, `capture_api.dart`, `lib/ingestion/**`, `lib/main.dart`, `check-sms-spike-placement.sh`, `app-ci.yml`, `HeadlessPluginAllowlistTest`, `CaptureRuntimeTest` |
| **Verdict** | **APPROVED** (no Critical, High or Medium; L-2 is "before merge of T-040", not of this branch; the rest are follow-ups) |

## Summary

The worker adds no network path and no new data store. It adds no exported component other than WorkManager's `SystemJobService`, which only the system can bind. It puts no content in WorkManager data, notifications, logs or exceptions. The WorkManager AAR's exported `DiagnosticsReceiver` is removed, and CI checks the merged manifest of every flavour. The headless engine registers only JNI, the secret store, a capture host and the ingestion Pigeon APIs. The headless capture host gets no inbox reader and no Guard writer, and a JVM test built through the runtime's own factory proves this. That test closes T-042 security L-1. Held entries are a rename inside the app-private `noBackupFilesDir`. They keep the same AES-GCM bytes and AAD, are never deleted silently, and count towards the spool caps. The remaining findings are about resource use (L-1, L-2) and defence in depth (Info).

## Checks

| Area | Result | Evidence |
|---|---|---|
| Data egress | Pass | No new dependency other than `androidx.work:work-runtime:2.12.0` (Google, no telemetry; `build.gradle.kts:110`). No `HttpClient`, socket or URL code in `platform/ingest` or `lib/ingestion`. Pubspec unchanged. The headless isolate imports only DB, parsing and Pigeon code (`ingestion_runner.dart:10-25`). |
| Exported components / IPC | Pass | AAR manifest checked: `SystemJobService` is `exported=true` with `permission=BIND_JOB_SERVICE` and `directBootAware=false`. `SystemForegroundService`, `ForceStopRunnable$BroadcastReceiver`, `RescheduleReceiver` and `InitializationProvider` are not exported. `DiagnosticsReceiver` (exported, `DUMP`) is removed in `src/main/AndroidManifest.xml:75-77`, so it is gone from every flavour. CI fails the build if it is present (`check-sms-spike-placement.sh:35-38`); negative proof recorded. No new receiver, service or provider in `src/main`. The devSms `InitializationProvider` merge stays `exported=false`. |
| Intent / work input trust | Pass | The only work input is `attempt` (an int), clamped to `0..MAX_ATTEMPTS` (`IngestionWorker.kt:62`). No extras are read. WorkManager's own DB is in `no_backup` and holds class names and this int only. |
| Pigeon surface | Pass | `HeadlessIngestionApi` (`drain`, `close`) is a FlutterApi: only native calls it. `HeadlessIngestionHostApi.ready` is registered only on the headless messenger (`FlutterHeadlessStarter.kt:401-406`). Channels are per engine and in-process, so no other app can reach them. `holdSpool`: at most 100 ids, ULID-validated, only ids this host drained (`AndroidCaptureHost.kt` `holdSpool`). Two-host negative proof recorded. The UI engine cannot hold or ack the headless engine's entries, and the headless engine cannot hold or ack the UI engine's. |
| Headless plugin allowlist | Pass (see I-3) | `setAutomaticallyRegisterPlugins(false)` plus explicit adds (`FlutterHeadlessStarter.kt:388-406`). Instrumented `HeadlessPluginAllowlistTest` is green on 4 API levels. |
| Headless engine never reads the inbox | Pass (closes T-042 L-1) | `CaptureRuntime.kt:227` `inbox = if (headless) null else uiInbox()`. `CaptureRuntimeTest.theUiHostGetsTheInboxReaderAndTheHeadlessHostAnswersNotAvailable` gets the headless host from the runtime's own factory and gets `NOT_AVAILABLE`, with no reader built. The UI handler serves the reader's page. Both negative proofs are recorded. The headless host also has `guardWriter = null` (`:222`). |
| Held entries | Pass (see I-5) | `SpoolStore.hold` (`:335`) is an atomic rename into `spool/held/` under `noBackupFilesDir`. That directory is app-private (0700), has no `FileProvider`, and is excluded from backup and D2D (`allowBackup=false` plus rules that exclude every domain). The bytes and AAD are the same, so entries stay authenticated. Cap 50 (`:60`), counted in the 500 / 4 MiB caps. Release (`:368`) only renames back and never deletes. `ack` deletes only top-level `spool/<ulid>.bin`, and `sweepTmp` touches only top-level `.tmp`, so neither can reach `held/`. `.app_version` holds only a version number. |
| DB-open failure | Pass | The headless container has `allowMigration=false` and `allowCreateOrWipe=false` (`ingest_store.dart:58-68`). A missing DB returns `NO_DATABASE`, and migration codes return `DEFERRED`; neither retries. F4 `invalidate` only re-runs the opener, which wipes only on a proven `KeyInvalidated` (T-016). It does not add a wipe path. |
| Logs / crash output | Pass | No `Log`, `println` or `printStackTrace` in `platform/ingest`, `platform/capture` or `MainActivity` (local grep plus the extended app-ci grep). `CycleReport.toString` and `DrainScope.toString` hold counts only. `IngestTrace` receives ULIDs and numbers. Dart `installQuietErrorHandlers` mutes `debugPrint` and uncaught errors in the headless isolate. Pigeon `wrapError` (`IngestionApi.g.kt:36`) can only wrap an exception from `ready()` → `onReady(true)`, which carries no content. Canary: JVM devSms drain/ack/hold, Dart report encode, and device logcat (0 lines). `SpikeLog` is devSms-only and limited to debuggable builds. |
| Foreground notification | Pass | API 26-30 fallback only. Title from `capture_strings.xml` ("Zaghlol is saving a transaction"), with no amount, sender or body. `VISIBILITY_SECRET` on the notification and on the channel (`IngestionWorker.kt:93, 99`). `IMPORTANCE_LOW`. The app never calls `setForeground`. |
| FGS / background limits | Pass | No `foregroundServiceType` and no `FOREGROUND_SERVICE_*` type permission (CI `:39-46`, negative proof recorded). On API 31+ the live work is an expedited job (quota, then a regular job) and no FGS starts from the background. Loop budget 60 s, far under the 10-minute job stop. `NonCancellable` shutdown, never a direct destroy. One worker at a time (`Mutex`). Retry series 10…900 s, stopped after 8. Not direct-boot aware, so nothing runs before the first unlock, when the CE-storage key and DB are locked. |
| Spike absent from release | Pass (see I-2) | Kotlin: the spike classes are in `src/devSms` only. The dex check covers `Lapp/zaghlol/spike/` plus R8-surviving strings in every non-devSms flavour. Dart: `kIsSpikeBuild` is a `const` from `appFlavor` (`ingestion_config.dart:96`), so AOT drops `loadSpikeRegistry` and `SpikeChannel` from prod. The prod-release `libapp.so` grep for `5550100` (`app-ci.yml:560-568`) passes, and the earlier step (`:528-533`) asserts that each ABI's `libapp.so` exists, so a missing file cannot make the grep pass by accident. |
| Release has no `androidx.test` | Pass | The release-mode manifest check is in `check-sms-spike-placement.sh:47-50` and runs on `prodSms` and `prodNoSms` release. |
| Play policy (NoSms) | Pass | WorkManager merges `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED` and `FOREGROUND_SERVICE`. None is restricted or needs a Play declaration. `RECEIVE_BOOT_COMPLETED` is needed because WorkManager persists jobs across reboot. `*NoSms` still removes every SMS permission (`src/noSms/AndroidManifest.xml`). The FGS has no type, so the Android 14 FGS-type declaration does not apply. |
| UI attach / detach | Pass | `detachUi` releases only the attached engine's claim and handlers. The F3 re-check on the main thread means a headless engine never runs next to the UI one. The 40-SMS burst with a UI attach lost nothing and doubled nothing on 4 API levels. |

## Findings

### L-1 (Low, follow-up) — every spool write appends another expedited work to the live chain

**Where:** `IngestionWorker.kt:26` (`enqueueUniqueWork(LIVE, APPEND_OR_REPLACE, liveRequest())`), called from `CaptureRuntime.afterSpoolWrite()` (`CaptureRuntime.kt:153-159`) after every kept **or refused** write.

**Path:** with `APPEND_OR_REPLACE`, WorkManager adds the new request as a child of every leaf of an unfinished chain. While one live run is running, each new SMS adds one more expedited work behind it, so N messages give a chain of N works. The design note's "it can only append behind a running head" holds for the head but not for the chain length. Most of the appended runs find the spool empty and end at once, but each one is still an expedited job that uses the app's standby-bucket expedited quota. A burst, or a flood from a spoofed allowlisted alphanumeric sender, keeps calling `afterSpoolWrite` even after the spool caps refuse the writes. That flood can use up the quota, so later real messages run as regular jobs. In Doze or the rare/restricted buckets, a regular job can wait minutes to hours. The user then sees capture delayed with no visible error. There is no data loss and no leak.

**Required change (owner T-040, which owns the receiver's enqueue; or a T-041 follow-up):** coalesce live enqueues. For example, skip the enqueue when the unique work already has an `ENQUEUED` (not yet `RUNNING`) item, or rate-limit `afterSpoolWrite` enqueues after refused writes. Add a JVM test: 50 `afterSpoolWrite` calls during a running run leave at most one waiting live work.

### L-2 (Low, **before merge of T-040**, not of this branch) — non-devSms builds retry a cycle that cannot succeed

**Where:** `ingestion_runner.dart:32-36` (`_bundledRegistryMissing` throws) and `:152-158` (`_runOnce` maps any setup failure to `CycleOutcome.retry` / `INGEST_SETUP_FAILED`). `DrainLoop.kt:131-134` turns `RETRY` into `RunResult.RETRY`.

**Path:** today nothing writes the spool in `staging*`/`prod*`, so this cannot happen. Once T-040 (SMS) or T-043 (notifications) writes the spool in those builds before T-036 ships the bundled registry, two things happen for every message. First, the live run and up to 8 retries (about 36 minutes) each boot a headless Flutter engine and open the DB, and none of them can succeed. Second, `startForegroundIngestion` is not wired outside devSms until T-047, so entries pile up until the 500 / 4 MiB caps refuse new ones. Real bank messages are then missed (`refusedFull`), and the engine boots waste battery.

**Required change:** either (a) report a missing registry as a no-retry outcome (for example `DEFERRED` with code `INGEST_REGISTRY_MISSING`; the entries stay for the build that has it), or (b) the Lead makes T-036 a dependency of T-040/T-043 enabling capture in non-devSms builds. With (a), add a test that a missing registry gives `RunResult.NO_RETRY`.

### I-1 (Info) — the headless capture host has more authority than it needs

**Where:** `CaptureRuntime.kt:216-228`. The headless host gets `device` (`openBatteryOptimizationSettings` → `startActivity`), `scheduler` (`scheduleIngestionNow`), and `clearSpoolAlerts` / `getSpoolStatus`.

**Path:** only the app's own `ingestionMain` code can call these, and no other app can reach them. But a bug in the headless isolate could zero the user-facing alerts (`keyInvalidatedAtMs`, `refusedFull`, `decryptDeleted`) before the UI shows them, or try to start an activity from the background. The inbox and the Guard writer are already closed off this way.

**Suggested:** apply the same least-privilege rule to the headless host: `device = null`, and make `clearSpoolAlerts` answer `NOT_AVAILABLE` on the headless host. Test it the same way as the inbox.

### I-2 (Info) — the prod `libapp.so` spike grep has no positive control

**Where:** `app-ci.yml:560-568`.

**Path:** the earlier step proves the file exists, but nothing proves that Dart string constants can be found by `grep` in this build. The check would also pass if the snapshot format ever stored strings in a form `grep` cannot match. It has only ever been seen green, never red, on a real AOT binary.

**Suggested:** in the same loop, require a string that must be in prod (for example `INGEST_REGISTRY_MISSING`) before asserting that `5550100` is absent. Alternatively, build devSms in release once and expect a hit.

### I-3 (Info) — the plugin allowlist test checks a hard-coded list of two plugins

**Where:** `HeadlessPluginAllowlistTest.kt:32-35`.

**Path:** a plugin added later (for example a sign-in, billing or Drive plugin) would not be in `registrantPlugins`, so the test would not see it registered. The code is safe by construction (`automaticallyRegisterPlugins = false`). Separately, `DartPluginRegistrant.ensureInitialized()` (`ingestion_main.dart:56`) runs every Dart-side `dartPluginClass` in the headless isolate. Today that is only `path_provider_android` (JNI).

**Suggested:** build the candidate list by reflection from `GeneratedPluginRegistrant` (or assert the engine's total plugin count). Also add a note in `architecture.md` §7 that any new plugin with a `dartPluginClass` must be reviewed for headless use.

### I-4 (Info) — `ACCESS_NETWORK_STATE` is merged but unused

No work request uses a constraint, so the worker does not need the permission. It is a normal permission, it reveals nothing, and the app will need network access for the backend later anyway. Optional: remove it with `tools:node="remove"` once a device run confirms WorkManager 2.12 does not query connectivity without network constraints. No change required.

### I-5 (Info, follow-up to the "Delete everything" owner and PO Q1) — retention of held entries

Up to 50 raw message bodies (encrypted, app-private, not backed up) can stay in `spool/held/` until the next app update, and indefinitely if each update still cannot store them. `security-model.md` "Delete everything" step 3 says "spool". The implementing task must delete `noBackupFilesDir/spool` **recursively**, including `held/` and `held/.app_version`, and its test must cover a held entry. If PO Q1 keeps "diagnostics only", consider a time bound later, for example releasing or reporting entries held across more than N versions.

## Verdict

**APPROVED.** There are no Critical, High or Medium findings. The data-never-leaves-the-phone promise, encryption at rest, backup exclusion, the exported-component surface and the Play SMS policy split all hold on this branch. L-2 must be settled before T-040 (or T-043) makes the spool writable in non-devSms builds. L-1, I-1…I-5 are follow-ups (`FU-###`).
