# SMS-device: bank SMS on a real Android phone (C4, native ingestion)

PO report (real Android phone, 2026-11-16 21:00, devSms debug APK from `main` after batch 30): "HSBC SMS still not read and it didn't read ANY message". Unit tests and the Dart e2e passed, so the break was on the device.

## Design note

**What was wrong (three independent defects, each with a test that fails without its fix).**

1. **The re-parse after a registry bump never ran at app start.** SMS-AUTO relies on "stored review rows are re-evaluated once after the registry version bump", but `ReparseJob` was constructed in one place only: after the user saves a custom template (`custom_template_reparse.dart`). A phone that stored HSBC and 100+ other SMS in review under an older build (registry version 1) kept them there: body-hash dedupe stops the same text being read again, and nothing re-evaluated the stored row. Fix: `reparseOnStart` (`features/capture/application/startup_reparse.dart`), started once by `captureCoordinatorProvider`; each examined row is stamped, so a later start finds nothing to do. Test: `startup_reparse_test.dart`; on the device the test seeds a stale review row and asserts it is a saved transaction after launch.
2. **Regex senders were never in the historical inbox scan.** `DriftScanSenderSource` took registry *exact* senders only. HSBC is the one institution with a regex-only sender (`^hsbc(?:[ ._-]?(?:eg|egy|egypt|bank))?$`), and `queryInbox` filters by `address IN (...)`, so no HSBC message in the inbox was ever read (live capture was fine). Fix: `expandSenderRegex` (`capture/domain/sender_expansion.dart`) lists the finite set of addresses a simple regex matches (literals, `[ ._-]`, `(?:a|b)`, `?`; anything else is not expanded), plus Title Case variants; native binds `{a, lower, upper}` of each. Tests: `sender_expansion_test.dart`, `inbox_scan_integration_test.dart` (real bundled registry).
3. **No way back after "Skip" or "Don't allow".** `CaptureSettingsScreen` was built without `onFix`, so the Fix button next to "SMS: Off" did not exist. The only code that asks for the SMS permission is the onboarding step. A user who skipped it (or reinstalled over a build that had it denied) could not turn live SMS on. Fix: a default `fixCapturePermission` (SMS prompt, then the first-run scan; notification access list). Test: `capture_permission_fix_test.dart`.

Not a defect but worth knowing: on Android 13+ a sideloaded APK may have its SMS permission request greyed out until "Allow restricted settings" is turned on in App info. The app can't detect that; the device test grants with `pm grant`.

**SMS-NODIGIT (PO).** A message with no digit at all (after the Guard's fold, so Arabic-Indic digits count) is dropped as `no_digit` in step 0 of the Guard, on every channel, in Dart, Kotlin and Swift. Golden cases `nodigit.*` (7 drop, 2 keep) in `golden.json`; ten existing golden/unit-test bodies got a digit so they keep testing what they tested. Recorded in `docs/workflow/PO_DECISIONS.md` and `platform-channels.md` section 1.2.

**Diagnostics (dev flavours only).** Native `SmsDiagStore` (`platform/diag`) counts per sender and stage: `received`, `kept:<kind>`, `drop:<reason>`, `spooled`, `refused`, `write_failed`, `inbox_kept`, `inbox_drop:<reason>`. Counts and sender ids only; a phone-number sender is `(number)`; no body, amount or time is ever stored or shown. Gated by `BuildConfig.SMS_DIAG` (true for the `dev` env only; every other build gets `SmsDiagSink.NONE`), and by a seam in `CaptureSeams` so JVM tests write nothing. The debug channel `app.zaghlol/sms_diag` (`snapshot`, `reset`) is **not** part of the platform contract. Dart merges native counts with database counts (stored by parse status, saved, open review by kind) in `Settings -> About -> SMS diagnostics` (`kIsDevBuild`). The screen is English only on purpose (developer tool, file name `debug_*` for the string lint).

**Device test.** `app/integration_test/sms_device_test.dart`, driven by `.github/scripts/device-flows.sh` (`run_sms_device`, first stage of the device-flows workflow; `ci/SMS-device` runs only this stage via `SMS_ONLY`). The Android 34 emulator console **accepts alphanumeric sender ids** (the first run said `OK`, and the inbox listed them), so every SMS goes through the emulator modem: the real telephony stack, the real `SmsReceiver` and the real inbox. No debug hook is needed (a devSms-only broadcast receiver was built and removed again). Fallback kept in the script only: if the console ever refuses a sender, the historical part uses `content insert` into the inbox as root.
- historical: the app is installed, granted with `pm grant`, force-stopped (so the broadcast is not delivered to it); the synthetic SMS from `HSBC`, `HSBC EG`, `CIB`, `NBE` (plus a no-digit HSBC SMS and a personal number) are sent; then the test seeds one stale HSBC review row (registry version 1) and starts the real app; it runs the same first-run scan onboarding runs;
- live: the test prints `SMS_DEVICE READY_FOR_LIVE`, the script sends the same kinds of SMS while the app runs; the native receiver, Guard, spool, drain and ingest do the rest.
The test asserts per sender family: stored, saved, in review (CIB InstaPay goes to review, no template reads it); that the Guard dropped the no-digit SMS and the personal one; that nothing is left in the spool; that the Guard base loaded (`full`); that the stale review row was re-read at start; and that Settings, About, SMS diagnostics lists HSBC. The emulator shows `HSBC EG` to the app as `HSBC` (it drops the space), so the `HSBC EG` address expansion is covered by unit tests only. Native code does not log (a source-scan test forbids it), so the "native logcat counts" are the diagnostics counters the test prints (`SMS_DEVICE SENDER ...` lines) plus the crash buffer.

## Files

Dart: `packages/zaghlol_parsing/lib/guard/{capture_guard,guard_types}.dart`; `app/lib/features/capture/{application/{capture_permission_fix,startup_reparse,capture_providers}.dart,data/scan_sources.dart,domain/sender_expansion.dart,presentation/capture_settings_screen.dart}`; `app/lib/features/settings/{debug/*,presentation/about_screen.dart}`; `app/lib/ingestion/ingestion_config.dart`.
Kotlin: `guard/{CaptureGuard,GuardTypes}.kt`; `platform/diag/{SmsDiag,SmsDiagChannel}.kt`; `capture/{CaptureIntake,CaptureRuntime}.kt`; `capture/inbox/{InboxReader,AndroidInbox}.kt`; `MainActivity.kt`; `build.gradle.kts` (`SMS_DIAG`).
Swift: `Guard/{CaptureGuard,GuardTypes}.swift`.

## Manifest / permissions

No new permission, no manifest change, no entitlement. Store policy: none (the diagnostics code is inert outside the `dev` env: `BuildConfig.SMS_DIAG` is false and the sink is `NONE`).

## Missing l10n keys

None: the diagnostics screen is a developer tool (English constants in `debug_sms_diagnostics_screen.dart`).

## Manual device steps (real phone)

1. Install a devSms debug build, finish onboarding, allow SMS. Settings -> About -> SMS diagnostics: Guard line says `base_only` or `full`, not `invalid`.
2. Have a bank send a purchase SMS (or ask a friend to send one from a number the app knows). The sender row shows `received`, `kept:registry`, `spooled`, then `stored:parsed` and `saved`.
3. Skip the SMS step in a fresh onboarding, then Settings -> Capture: SMS shows Off with Fix; Fix opens the SMS prompt and then reads the inbox.
4. Update over an old build that left review rows: after the first launch they are converted (Home count drops).

## Results

Local: `dart test` (parsing package, all), the capture / ingestion / settings / onboarding Flutter tests, analyze, format, repo lints. Kotlin unit tests and the emulator run: see the report.
