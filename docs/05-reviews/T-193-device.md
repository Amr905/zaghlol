# T-193 AC5: emulator run of forged intents and real taps

Branch `task/B53-t193-ac5`. Runner: the `device-flows` workflow (Android emulator API 34, `devSms` debug build), script `.github/scripts/notif-intents.sh` plus `app/integration_test/notification_intents_device_test.dart`. Evidence: the final green run (id in the commit log / PR; the last run before the lint-only move was 44864460325 at 8599191d, 20 of 20 device checks PASS).

## Cases (all PASS)

| Case | Result |
|---|---|
| Cold forged `am start` to `MainActivity`: no action/no token; action/no token; action/wrong token (backup route); action/wrong token and action/no token with the mark-paid route and a cancel id; plain launch with no extras | Nothing opened, nothing paid, no dialog, nothing cancelled (started=1, probes=1 each) |
| Warm forged: same set, plus a token without the action | Same: nothing happens |
| Forged start of the non-exported tap trampoline | Refused by the system |
| In-process checks (database, dialog) after the forged runs | No bill paid, no dialog |
| Real tap on the notification, warm and cold | Opens the backup screen (`open BackupTarget ctx=true`); notification auto-cancelled |
| Real "Mark as paid" action, warm and cold | Confirm dialog shown, nothing paid before the user's tap, bill paid in the database after it; action notification cancelled |

## Real app finding (fixed in 8599191d)

After process death the system delivered a tap to the restored task before the root navigator existed, and the event was dropped. `_open` in `app/lib/app/notification_taps.dart` now waits for the navigator (bounded, about 10 s). Unit test: `app/test/app/notification_tap_early_test.dart` (tap before the navigator waits then opens; a tap that never finds one gives up quietly).

## Test-only hooks

The `NOTIF_PROBE` marker lines (no data in them) and the cold-fixture poster live in `app/lib/app/notification_taps_debug.dart` (a debug-only file for the print lint) and run only under `kDebugMode`, a compile-time constant, so release builds drop them. The forged-intent script and integration test touch no release code.

## Not covered

Real-device vendors (OEM notification shades) and the iOS path: emulator only.
