#!/usr/bin/env bash
# FIX-device-flows (device-flows.yml): runs integration_test/device_flows_test.dart
# (the real app composition) on the Android emulator, then pulls the
# screenshots the test wrote to the app's private dir. Called as one line
# because android-emulator-runner runs its `script` input line by line.
# Inputs: DEVICE (emulator-5554), RUNNER_TEMP. Synthetic data only.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"
flutter devices
adb -s "$DEVICE" logcat -c || true
perl -e 'alarm shift; exec @ARGV' 1800 \
  flutter test integration_test/device_flows_test.dart \
  --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
  2>&1 | tee "$OUT/test.log"
rc=${PIPESTATUS[0]}
for f in $(adb -s "$DEVICE" shell run-as "$PKG" ls app_flutter/ci_screens 2>/dev/null | tr -d '\r'); do
  case "$f" in *.png) ;; *) continue ;; esac
  adb -s "$DEVICE" exec-out run-as "$PKG" cat "app_flutter/ci_screens/$f" > "$OUT/screens/$f" || true
done
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-screen.png" || true
# Flutter's own log lines only (Dart errors, the test's prints).
adb -s "$DEVICE" logcat -d -s flutter:V > "$OUT/flutter-logcat.txt" 2>/dev/null || true
ls -la "$OUT/screens"
exit "$rc"
