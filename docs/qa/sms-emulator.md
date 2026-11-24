# Sending the SMS scenario to your own emulator

1. Android Studio, Device Manager: create a phone, **API 34, Google APIs image** (not "Google Play"; Play Store images refuse `adb root`, which `--historical` needs). Start it.
2. Install the devSms build (`flutter build apk --debug --flavor devSms`, then `adb install -r <apk>`), open it once, and grant SMS and notification permissions (or `adb shell pm grant app.zaghlol.dev android.permission.READ_SMS`, `RECEIVE_SMS`, `POST_NOTIFICATIONS`).
3. From the repo root (Windows: `powershell docs\qa\tools\sms_scenario.ps1 ...`; elsewhere `python3 docs/qa/tools/sms_scenario.py ...`). adb is found on PATH, `ANDROID_HOME` or `%LOCALAPPDATA%\Android\Sdk\platform-tools`.
   - `--list`: entries, sender counts and the expected spend/income per month and currency (posted only; internal transfer legs, ignored and declined entries excluded; spend = expense/fee/transfer_out, income = income/transfer_in/refund).
   - `--historical`: the `delivery=inbox` entries are sent through the emulator modem with the emulator clock set to each entry's own time (auto time off, root), then the clock is put back (also on an error or Ctrl-C). Needs a Google APIs image where `adb root` works. Each entry is reported as sent or failed from the console's `OK`. Do this before the app's first scan, then open the app. Texts with a newline or control character are refused.
   - `--live`: sends the `delivery=live` entries now through the emulator modem while the app runs; `--all-live` sends every non-manual entry that way (current date). `manual` entries are skipped with a note (the test adds them through the app).
   - Dates: each entry is dated from the PC clock (`monthsAgo` months back, day clamped to the month length, at its local time).
   - `--sender CIB --text "..."`: one message.
   - `--scenario <file>` picks another scenario (default `app/test/fixtures/sms/scenarios/month_story.json`).
4. The tool prints sender ids and counts only, never message text. It refuses a device whose serial is not `emulator-*` unless you pass `--i-know-this-is-a-real-phone`.

## What to check
Compare with the "expected spend/income" lines the tool prints (per currency, never summed):
- Home: the recent list shows the latest messages.
- Insights, Overview: spend hero equals expected spend for the period; income and saved per month match.
- Categories: totals and shares per category; the unknown merchant sits in "Other"/uncategorized.
- Trends: heatmap day totals.
- Not counted: self-transfers, OTP/promo/declined messages. Refunds reduce spend. USD purchases show separately from EGP.

Tests for the tool: `python3 -m unittest discover -s docs/qa/tools -p "test_*.py"`.
