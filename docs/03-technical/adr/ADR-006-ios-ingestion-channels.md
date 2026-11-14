# ADR-006: iOS ingestion channels (and removal of the message filter extension)

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-ING-I-*, R-02, R-07; https://developer.apple.com/forums/thread/97953; https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications |

## Context
D-09 keeps 5 iOS channels "subject to architect feasibility study". Apple documents that a Message Filter extension cannot write to containers shared with its app and cannot access the network. It only receives messages from unknown senders. iOS 17 made Shortcuts automations (including Message triggers) able to run immediately, always with a notification.

## Options considered
1. **Keep the message filter extension** — It cannot hand messages to Zaghlol, so it can't meet FR-ING-I-03's purpose, and risks review rejection.
2. **Shortcuts Message + Wallet automations via App Intents (primary), Share Extension / Back Tap OCR, statement import** — All supported by Apple; competitors use the same; iOS 17+.

## Decision
**Channels:** (1) Shortcuts **Message** automations with Arabic/English keywords → `LogBankMessageIntent`; (2) Shortcuts **Transaction (Wallet)** automation → `LogWalletTransactionIntent`; (3) Share Extension + Back Tap screenshot OCR; (4) PDF/CSV statement import; (5) paste. **Change request CR-01: remove FR-ING-I-03** (the message filter extension, priority S), replacing it with this documented feasibility result. **Minimum iOS 17.0.**

## Consequences
A one-tap signed `.shortcut` package plus a setup checker are essential (FR-ING-I-06/07). Each automation run shows an iOS notification, so the intent returns a short, amount-free dialog. The product owner must approve CR-01.

## Addendum: SPK-03 result (T-009, 2026-11-13) - verdict: GO WITH LIMITS

Question: can an App Intent with `openAppWhenRun = false` hand a message to a headless Flutter engine and finish processing inside `perform()`?

**Proof (simulator, app-ci run 43508028241, job "ios intent spike", Xcode 16.4, iPhone 16 Pro, iOS 18.x, Debug-dev JIT build; the iOS 26 runtime exists on the runner but was not used).** `LogBankMessageSpikeIntent.perform()` ran end to end in an XCTest: encrypted spool write, `FlutterEngine(allowHeadlessExecution: true)`, `run(withEntrypoint: "spikeIntentMain")`, plugin registration (`GeneratedPluginRegistrant`, `SecretStoreRegistration`), Dart handshake, one `process` round trip, spool ack, `destroyContext()`. 5 of 5 tests pass. Code: `app/ios/Runner/Spike/IosIntentSpike.swift`, `app/lib/ingestion/ios_intent_spike.dart`, `app/ios/RunnerTests/IosIntentSpikeTests.swift` (spike only; excluded from `*-prod` builds by `ZAGHLOL_PROD`; deleted by T-063, whose production intents use T-062's `HeadlessIngestion`).

| Measurement (debug, simulator, Apple-silicon runner; not device numbers) | Cold | Warm (2nd engine, same process) |
|---|---|---|
| spool write (AES-GCM, 58-char synthetic body) | 0.6 ms | 1.5 ms |
| engine init + run + plugin registration | 287 ms (intent path: 451 ms) | 264 ms |
| Dart ready handshake | 109 ms | 81 ms |
| `process` round trip | 11 ms | 11 ms |
| total, perform() body | 407 ms (intent path: 561 ms) | 356 ms |
| `phys_footprint` before / after | 212 MB / 300 MB (+88 MB; the host already holds the UI engine, so a background cold launch starts lower) | 212 / 298 MB |

A 3 s hold inside Dart was answered normally (total 3.4 s). `os_proc_available_memory()` returns 0 on the simulator, so the memory headroom is unmeasured.

**Findings that change the T-061..T-067 design**
1. The Flutter binary messenger **aborts the process** (`FlutterEngine.mm:1372` assertion) if a channel handler is installed before `run()`. Install handlers after `run()`; Dart retries `ready` until native answers (done in the spike).
2. A missing Dart entrypoint is not a recoverable error path to rely on; test the "engine never answers" case with an entrypoint that never says ready.
3. Engine start dominates (about 90 percent of the time). A real pipeline adds SQLCipher open, Guard and parse; budget these on a device.
4. The intent may only claim success after the spool write. Any engine failure (start, ready or process timeout) leaves the entry in the spool and the intent answers a neutral "saved for later" dialog. Test `testFailedEngineLeavesTheEntryAndForegroundDrainProcessesIt` shows the fallback path (drain on next foreground / BGAppRefresh) processes it, at-least-once.

**Decision.** Immediate processing is allowed as an optimisation, never as the guarantee. T-061..T-067 must: (a) write the encrypted spool entry first and return success only for that; (b) attempt the headless engine inside `perform()` with a hard timeout (suggested 8 s until device numbers exist), and ack only after the DB commit; (c) always keep the fallback: drain on app foreground, plus a `BGAppRefreshTask` as a best-effort nudge (the system decides when it runs); (d) keep the spike's rule that dialogs and metrics never contain the body or amount.

**Not proven on the simulator, device steps required** (needs a real iPhone on iOS 17.x and 26.x, a Release or Profile build, because a Debug build cannot cold-launch from the home screen or Shortcuts):
1. Build `--release --flavor dev`; in Shortcuts add "Zaghlol spike: log message" with a text input and run it with the phone unlocked and the app force-quit. Expect a "Done N ms" dialog; the Shortcut banner shows the elapsed time. Repeat for iOS 17 and 26.
2. Same with the phone locked after first unlock (Shortcuts automation, "run immediately"): does `perform()` run, and can the Keychain spool key (`AfterFirstUnlock`) and the App Group files be read? Also right after a reboot before first unlock (expect no run; the entry must wait).
3. Time limit: run with `holdSeconds` = 5, 10, 20, 30, 60; record the longest value that still answers and whether the process is killed or the Shortcut times out.
4. Memory: Xcode Instruments or MetricKit footprint of the process during step 1; `os_proc_available_memory()` is logged in the metrics (device only). Watch for jetsam at large `holdSeconds`.
5. Low Power Mode and Background App Refresh off: same run.
6. Real automation trigger: a Message automation with "Run Immediately" and a Wallet transaction automation, each with the spike intent as the action.
7. `BGAppRefreshTask`: register and schedule it in a dev build, background the app, use `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"..."]` to prove the handler drains the spool; real-world frequency can only be observed over days.
8. Real engine cost: repeat step 1 with the production headless entrypoint (SQLCipher open, Guard, parse) once T-044/T-046 exist.

Until steps 1-3 are done the status stays "go with limits": the fallback path is mandatory and the SLA to the user is "processed when the Shortcut finishes, else on next open".
