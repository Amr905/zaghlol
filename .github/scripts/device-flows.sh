#!/usr/bin/env bash
# FIX-device-flows + TEST-explorer (device-flows.yml): runs
# integration_test/device_flows_test.dart (the real app composition), then
# integration_test/app_explorer_test.dart (taps every control of every screen,
# in Arabic, with synthetic data) on the Android emulator, and pulls the
# screenshots and the explorer report the tests wrote to the app's private
# dir. Called as one line because android-emulator-runner runs its `script`
# input line by line. Inputs: DEVICE (emulator-5554), RUNNER_TEMP.
# Synthetic data only.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"

pull_files() {
  for f in $(adb -s "$DEVICE" shell run-as "$PKG" ls app_flutter/ci_screens 2>/dev/null | tr -d '\r'); do
    case "$f" in *.png | *.md) ;; *) continue ;; esac
    adb -s "$DEVICE" exec-out run-as "$PKG" cat "app_flutter/ci_screens/$f" > "$OUT/screens/$f" || true
  done
}

flutter devices
adb -s "$DEVICE" logcat -c || true

# ---- 1. device flows (English, empty database)
rc=0
if [ -z "${EXPLORER_ONLY:-}" ]; then
  perl -e 'alarm shift; exec @ARGV' 1800 \
    flutter test integration_test/device_flows_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    2>&1 | tee "$OUT/test.log"
  rc=${PIPESTATUS[0]}
  pull_files
  adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-screen.png" || true
fi

# ---- 2. explorer (Arabic, seeded database)
# A clean app: no leftovers from step 1. Notification and microphone
# permissions are granted up front so no system dialog covers the app.
adb -s "$DEVICE" shell pm clear "$PKG" || true
for p in POST_NOTIFICATIONS RECORD_AUDIO READ_SMS RECEIVE_SMS; do
  adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" 2>/dev/null || true
done
# If a tap sends the app to the background (a link, the share sheet, a system
# screen), press Back and bring it forward again.
(
  misses=0
  while true; do
    sleep 10
    if adb -s "$DEVICE" shell pidof "$PKG" >/dev/null 2>&1; then
      # The app is installed by now: grant what its screens ask for, so no
      # system permission dialog covers it.
      for p in POST_NOTIFICATIONS RECORD_AUDIO READ_SMS RECEIVE_SMS; do
        adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" >/dev/null 2>&1 || true
      done
      focus=$(adb -s "$DEVICE" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)
      case "$focus" in
        # No focused window yet (the app is starting) or ours: all fine.
        *"$PKG"* | *"=null"*) misses=0 ;;
        *)
          misses=$((misses + 1))
          # Two looks in a row: another window really is in front.
          if [ "$misses" -ge 2 ]; then
            echo "KEEPER: app not focused ($focus)"
            adb -s "$DEVICE" shell input keyevent 4 || true
            sleep 1
            adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
            misses=0
          fi
          ;;
      esac
    fi
  done
) &
keeper=$!
perl -e 'alarm shift; exec @ARGV' 2100 \
  flutter test integration_test/app_explorer_test.dart \
  --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
  2>&1 | tee "$OUT/explorer.log"
rc2=${PIPESTATUS[0]}
kill "$keeper" 2>/dev/null || true
pull_files
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-explorer.png" || true

# Flutter's own log lines only (Dart errors, the tests' prints).
adb -s "$DEVICE" logcat -d -s flutter:V > "$OUT/flutter-logcat.txt" 2>/dev/null || true
ls -la "$OUT/screens"
if [ "$rc" -ne 0 ]; then exit "$rc"; fi
exit "$rc2"
