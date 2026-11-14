# Batch 20b review (T-066, T-092, T-100, T-117, T-118)

Reviewer: code-reviewer (code and security), batch/2026-11-14-20 at 927e37ff. Production diffs read per task; capture and widgets_bridge suites run (228 capture tests green twice; `capture_providers_test` "starts after the database opened" failed once in a loaded parallel run and passed alone and on two reruns: timing flake, not a defect found in this batch).

## T-066 iOS capture integration — APPROVED
- AC "captures appear on next open": coordinator runs on iOS (`captureIosProvider`), shared drain, `foreground` hook calls `scheduleIngestionNow` (registerBackgroundRefresh) at start and each resume. OK.
- AC "7-day nudge": `deriveIosSetupStatus` pure, `shortcut_message`/`apple_pay` only, baseline = start of first-run local day, future capture counts as now. Query selects only `MAX(received_at)`, no body. OK.
- Held release per build: `AppDelegate` calls `releaseHeldIfVersionChanged(CFBundleVersion)` on a utility queue; releases, never deletes. OK.
- Lead merge check: one `IosCaptureHostPort` in `ios_capture_host_port.dart`, `writeGuardConfig` goes to `_api.writeGuardConfig` through `_guard` (code-only errors); stale NOT_AVAILABLE header text is gone. T-063 writer tests live in `ios_guard_writer_test.dart` and exercise the real call and the NOT_AVAILABLE reply; `ios_capture_host_port_test.dart` no longer asserts the old stub. OK.
- Minor: `CaptureCaps.ios` makes both SMS and notification channels `unavailable` and never `degraded`; fine for iOS. No Home nudge UI or copy yet (builder-declared, follow-up).
- Minor: `capture_providers.dart` import order (`ios_setup_providers.dart` between data imports); cosmetic.

## T-092 pair suggestions — APPROVED
- Money never converted: reimbursement query filters `e.currency = incoming.currency`; `acceptFxPair` only calls `TransferPairingUseCase.link`, which keeps both legs' amounts.
- Applies only on tap: `suggestReimbursement` only inserts a review item (payload = ids only); `acceptReimbursement` / `acceptFxPair` require an open item of the right kind and a candidate named in the payload (`SUGG_NOT_CANDIDATE`); reimbursement goes through the manual `Reimbursements.assign` with the incoming's remaining amount.
- Dismiss memory: resolved item with resolution `dismissed` keeps its candidates; both the reimbursement path and `TransferPairingUseCase._dismissedFx` (either leg) exclude them. Resolve on an already resolved item returns false (no overwrite).
- Minor: `_dismissedFx` uses `payload LIKE '%"id"%'` (works, ids are UUIDs, scan is small).

## T-100 duplicate-charge and weekly-summary notifications — APPROVED
- Duplicate detector pure, grouped by account + merchantNorm + currency + amount, 10-minute chain, one cluster per run keyed by the earliest txn (no re-alert on a third charge), zero amount and blank merchant never cluster. Input type `DupTxn` carries no message text.
- Weekly summary: one alert per currency with spend, `subjectId` = currency code, never summed; figures from the chart repository (internal transfers excluded); redacted variant is the caller's (hide-amounts is enforced in `NotificationService`, existing code). Payloads are routes only.
- Minor: nothing in `app/lib` instantiates `DuplicateChargeAlerts`, `WeeklySummaryAlert` or `backupAlertSinkOver` yet (no provider or scheduler); the alerts do not fire until the Lead/T-087 wiring task exists. Track as a follow-up.
- Minor: detector does not restrict to POS channel; "identical charges at the same merchant within 10 minutes" is the implemented rule.

## T-117 share cards — APPROVED (one major functional gap, not blocking by sprint rule)
- Hidden by default (`_showAmounts = false`); hidden mode builds card text and the Semantics label from percentages only; the "Show amounts" strings are used only when the switch is on. Unencrypted-image banner shown. Nothing else leaves the phone: only the PNG bytes go to the share call, no network.
- Staging file is written in the temp dir, deleted in `finally` on success and failure.
- **Major (functional, non-blocking per sprint rule) `share_providers.dart:38`:** `MethodChannel('zaghlol/share').invokeMethod('shareImage')` has no native implementation anywhere in `app/android`, `app/ios` or `app/pigeons`, and it is not in `platform-channels.md`. On a device the call throws `MissingPluginException`, which the screen swallows into the "render failed" banner, so Share never works. Follow-up: add the channel to the contract with native hosts (or use a share package), and make sure the native side keeps the file readable until the target app has taken it (the Dart code deletes it as soon as `invokeMethod` returns, which on Android returns when the chooser is launched).
- Minor: a crash between `writeAsBytes` and `finally` leaves a PNG in the temp dir; add a start-up sweep of `share_*.png`.
- Minor: screen is not routed from anywhere yet (no reference outside `share_cards/`).

## T-118 home widgets (C3 native) — APPROVED
- Redaction is done in Dart (`buildWidgetSnapshot`): hidden or locked yields `•••/day`, no digit or currency reaches the channel; primary currency only, no sums. Native only stores and draws strings.
- Storage: AES-GCM with the spool key (Keystore / shared Keychain), AAD `zaghlol.widget.v1|snapshot`, atomic replace, 4 KiB cap, decode validates version/state/trailing bytes; unreadable file reads as nothing and is not deleted by a read. Android file in `noBackupFilesDir/widget`; iOS App Group `Library/Application Support/widget` excluded from backup before each write, `completeFileProtectionUntilFirstUserAuthentication`. No logging, errors code-only.
- Android receiver exported with only `APPWIDGET_UPDATE`, no permission, no other intent filter; tap opens `zaghlol://home` with package pinned. `updatePeriodMillis=0`. Registered on UI engine only and unregistered in cleanup.
- iOS widget entitlements match the Runner's group and keychain access group scheme; `.privacySensitive()` on the amount.
- Contract change documented in `platform-channels.md` §5 (flagged for Lead sign-off). `WidgetBridgeHostApi` stub moved out of `device_api.dart` to avoid the Swift module name clash; generated files consistent.
- Minor (builder-declared): `widgetBridgeWiringProvider` and `widgetCopyProvider` are not wired in the app shell and "Delete everything" does not call `clear()` yet. Until the Lead wires them the widget stays empty. Wiring must include `clear()` in the delete flow, otherwise a stored snapshot survives "Delete everything" (the Android wipe clears `noBackupFilesDir`, which covers it; the iOS wipe clears the App Group, so both platform wipers cover it already).
- Minor (design residual): while the app process is not running, a previously unmasked snapshot stays on the home screen after the app locks (app-lock masking happens only while the app runs the wiring). Users who care use `hide_amounts.widget`; consider masking on lock-timeout in a follow-up.
- Minor: "days to payday" does not roll over at midnight until the app republishes (builder-declared).

## Fix list (blocking findings only)
| Task | file:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| none | | | |
