# Running the device cases

The 20 cases in `test-cases.md` with method "device" and status NOT RUN. They need a phone or emulator because they depend on typing, gestures, the OS or the clock.

## Set-up (once)

1. **Emulator:** Android Studio → Device Manager → create a phone with an **API 34, Google APIs** image (not "Google Play": the SMS tool needs `adb root`). Start it.
   For Claude to drive it, it must be in its own window: Settings → Tools → Emulator → untick "Launch in the Running Devices tool window", then restart the emulator.
2. **Build:** from `app/`, `flutter build apk --debug --flavor devSms`, then `adb install -r build/app/outputs/flutter-apk/app-devSms-debug.apk`. Or download `zaghlol-devSms-debug-apk` from the latest green `app-ci` run on GitHub and drag the `.apk` onto the emulator.
3. **Data:** `python3 docs/qa/tools/sms_scenario.py --historical` then `--live` (see `sms-emulator.md`). It sends synthetic bank SMS and prints the totals to expect.
4. **Backend, only for TC-X-E2E-07:** `docs/workflow/run-backend-locally.md`, and build with `ZAGHLOL_API_BASE=http://10.0.2.2:8080` and the dev keys.

A real Android phone works the same way for everything except step 3's `--historical` (use `--all-live`).

## The cases

Record PASS or FAIL with a screenshot per case. Expected results are in `test-cases.md`.

| Case | Steps |
|---|---|
| TC-X-E2E-01 | Fresh install → open. Tap the main button, allow SMS, skip notification access. Count the taps to the permission (expect 3). Home must appear with no question about account, payday or income. |
| TC-X-UI-12 | Same fresh install with the phone language set to English. The app must still open in Arabic, right-to-left, light. |
| TC-X-E2E-02 | Run the SMS scenario (set-up 3). Compare Home and Insights totals per month and currency with the tool's printed figures. |
| TC-X-CAP-06 | Real phone only: force-stop the app, send one bank-format SMS from a second phone, wait 10 s, open the app. One transaction, no duplicate. |
| TC-X-E2E-03 | Add → Type it: save an expense. Edit its amount, then delete it. Select 3 transactions → change category → Undo. Totals must follow each step. |
| TC-X-UI-01 | In the new-expense form, fill amount and category and tap Save twice as fast as possible. Exactly one transaction. |
| TC-X-UI-02 | Start a new expense, type an amount, rotate the phone, press Home, reopen. The typed values must still be there. |
| TC-X-UI-03 | Open each of: Add sheet, currency picker, category picker, card filter, paywall, discard dialog. Press system Back on each. Only the top layer closes. |
| TC-X-TXT-06 | Copy a very long text (for example 1 MB of Lorem ipsum from a notes app) → Settings → Capture → Share or paste a message → paste. A message or truncation, no freeze. |
| TC-X-E2E-04 | Insights → Budget: set a limit of 1,000 for one category. Add expenses of 800, then 250 in it. One alert at 80 %, one at 100 %; safe-to-spend = remaining ÷ days left. |
| TC-X-E2E-05 | Add a 1,000 transfer out of one account and a 1,000 transfer into another within 2 minutes: spend unchanged, both marked internal. Then add a 1,200 expense and a 400 income; on the income choose "money back for…" → the expense shows 800. |
| TC-X-E2E-06 | Settings → Capture → Don't track a card → pick a bank and last-4. Send an SMS for that card (`sms_scenario.py --sender … --text …`). Nothing in Home, review or diagnostics counts. |
| TC-X-E2E-07 | With the local backend: open the app, `curl -X POST http://localhost:8080/dev/v1/grant-gold`, reopen. Gold is active and Export works. Turn on airplane mode, reopen: still Gold. |
| TC-X-E2E-08 | Add a Google account to the emulator. Settings → Backup → Back up now (set a passphrase). Settings → Privacy & data → Delete everything → the app returns to Welcome. "I already use Zaghlol" → restore. Data identical. |
| TC-X-E2E-09 | Settings → Preferences → English, Dark. Walk Home, Insights, Money, Zaghlol and Settings. Everything left-to-right, True Black theme, no clipped text. |
| TC-X-UI-04 | After E2E-09, force-stop the app and reopen. Still English and dark. |
| TC-X-DATE-04 | With data loaded, change the phone's time zone (Settings → System → Date & time) by +8 hours and reopen. No transaction changes day or month by mistake; no duplicates. Set it back. |
| TC-X-UI-11 | After the SMS scenario plus the `--all-live` run a few times (several hundred rows): scroll the transaction list, search a merchant, open each chart. No visible stutter. |
| TC-X-SEC-14 | Settings → Preferences → App lock on. Press Recents: the app preview must be blank. Take a screenshot inside the app: blocked. Reopen: asks for fingerprint or PIN. |
| TC-X-E2E-10, 11 | iPhone and store sandboxes: blocked until an iPhone, a Mac and Play / App Store test accounts are available. |

Also re-check on the device the four fixes of 26 Nov: BUG-015 (paywall shows "prices failed" and Try again within about 8 s), BUG-016 (launcher icon is Captain Zaghlol), BUG-017 (About shows two different lines), BUG-018 (card-filter sheet sits above the tab bar).

## What already runs without you

GitHub's `device-flows` workflow (Actions → device-flows → Run workflow, on any branch) runs scripted versions of about half of these on an API 34 emulator:

| Script in `app/integration_test/` | Covers |
|---|---|
| `sms_charts_device_test.dart` (month-story job) | TC-X-E2E-02 |
| `sms_killed_device_test.dart` | TC-X-CAP-06 on an emulator (not a real phone), TC-X-E2E-06 |
| `e2e04_manual_device_test.dart`, `e2e05_budget_device_test.dart`, `e2e06_transfer_device_test.dart` | TC-X-E2E-03, 04, 05 |
| `e2e_locale_device_test.dart`, `e2e_lock_device_test.dart`, `e2e_wipe_device_test.dart`, `e2e_export_device_test.dart` | TC-X-E2E-09, TC-X-UI-04, TC-X-SEC-14, the wipe half of TC-X-E2E-08 |
| `app_explorer_test.dart` | walks every screen looking for dead taps, exceptions and overflows |

Still manual, because they need judgement or something a script cannot do: TC-X-UI-01 (double tap), TC-X-UI-02 (rotation), TC-X-UI-03 (system Back), TC-X-TXT-06 (huge paste), TC-X-DATE-04 (time zone), TC-X-UI-11 (stutter), TC-X-UI-12 (phone language), TC-X-E2E-07 (local backend), the backup half of TC-X-E2E-08 (Google account), and TC-X-CAP-06 on a real phone.
