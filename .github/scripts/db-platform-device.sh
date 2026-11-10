#!/usr/bin/env bash
# T-007 (db-platform.yml): runs the encrypted-SQLite contract (and, with
# BENCH=true, the 50k-row FTS benchmark) on an Android emulator or iOS
# simulator. T-015: the same launch runs the database key bootstrap tests;
# then the device logs are scanned for the synthetic test key
# (db-key-log-scan.sh). Called as a single line because android-emulator-runner runs its
# `script` input line by line. Inputs come from the environment:
#   FLAVOR   devNoSms (Android) or dev (iOS)
#   DEVICE   flutter device id (emulator-5554, or a simulator UDID)
#   DB_ENV   label for the output lines (android-emu-api35, ios-sim, ...)
#   BENCH    true to run the benchmark
# Output: $RUNNER_TEMP/device.log (the test log; the contract never prints
# keys, sentinels or row text) and the device system log
# ($RUNNER_TEMP/system.log, scanned, not uploaded).
set -euo pipefail
: "${FLAVOR:?}" "${DEVICE:?}" "${DB_ENV:?}" "${BENCH:?}" "${RUNNER_TEMP:?}"
case "$FLAVOR" in devNoSms|dev) ;; *) echo "::error::unexpected flavor"; exit 1 ;; esac
[[ "$DB_ENV" =~ ^[a-z0-9-]+$ ]] || { echo "::error::unexpected DB_ENV"; exit 1; }

scripts=$(cd "$(dirname "$0")" && pwd)
cd "$(dirname "$0")/../../app"
args=(test integration_test/db_platform_test.dart
  --flavor "$FLAVOR" -d "$DEVICE" --reporter expanded
  "--dart-define=ZAGHLOL_DB_ENV=$DB_ENV"
  "--dart-define=ZAGHLOL_RUN_ID=${GITHUB_RUN_ID:-}")
if [ "$BENCH" = "true" ]; then
  args+=("--dart-define=ZAGHLOL_DB_BENCH=1")
fi
flutter devices
flutter "${args[@]}" 2>&1 | tee "$RUNNER_TEMP/device.log"

# T-015: the key bootstrap tests ran in the same launch (db_platform_test.dart
# registers them). Scan the test log and the device system log for the key.
if [ "$FLAVOR" = "devNoSms" ]; then
  adb -s "$DEVICE" logcat -d > "$RUNNER_TEMP/system.log"
else
  xcrun simctl spawn "$DEVICE" log show --last 60m --style compact > "$RUNNER_TEMP/system.log"
fi
grep -oE 'ZAGHLOL_KEY_SCAN \{.*\}' "$RUNNER_TEMP/device.log" || {
  echo "::error::no ZAGHLOL_KEY_SCAN line in the test log"; exit 1; }
bash "$scripts/db-key-log-scan.sh" "$RUNNER_TEMP/device.log" "$RUNNER_TEMP/system.log"
