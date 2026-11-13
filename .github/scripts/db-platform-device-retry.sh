#!/usr/bin/env bash
# Runs db-platform-device.sh with a time limit per attempt and one retry after
# a launch hang (the emulator sometimes installs the APK and then nothing
# happens until the job times out: batches 14 and 15). A real test failure
# (any exit other than the time limit) is not retried.
# Usage: db-platform-device-retry.sh [minutes per attempt, default 25]
set -u
LIMIT_MIN="${1:-25}"
LIMIT_S=$((LIMIT_MIN * 60))

attempt() {
  perl -e 'alarm shift; exec @ARGV' "$LIMIT_S" bash .github/scripts/db-platform-device.sh
}

attempt
rc=$?
if [ "$rc" -eq 142 ]; then
  echo "::warning::${DB_ENV:-device}: attempt 1 hit the ${LIMIT_MIN}-minute limit (launch hang); restarting the app process and retrying once"
  pkill -f 'flutter_tools.snapshot' || true
  if command -v adb >/dev/null 2>&1; then
    adb shell am kill-all >/dev/null 2>&1 || true
    adb shell input keyevent 82 >/dev/null 2>&1 || true
  fi
  attempt
  rc=$?
  if [ "$rc" -eq 142 ]; then
    echo "::error::${DB_ENV:-device}: attempt 2 also hit the ${LIMIT_MIN}-minute limit"
  fi
fi
exit "$rc"
