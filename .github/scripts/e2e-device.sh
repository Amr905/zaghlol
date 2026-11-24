#!/usr/bin/env bash
# T-238 (device-flows.yml job `e2e-settings`): four E2E device tests of the real
# app on the Android emulator, one after the other, each on a clean app:
#   E2E-09 export as Free / Gold      integration_test/e2e_export_device_test.dart
#   E2E-10 language and digits        integration_test/e2e_locale_device_test.dart
#   E2E-11 app lock, secure window    integration_test/e2e_lock_device_test.dart
#   E2E-12 delete everything          integration_test/e2e_wipe_device_test.dart
# A failure of one does not hide the others. E2E-11 and E2E-12 need the device
# side: the script reads `dumpsys window` (FLAG_SECURE) and `dumpsys
# notification` / `dumpsys alarm` while the test waits after printing a marker.
# Synthetic data only; logs hold counts and file names, never message text.
# Inputs: DEVICE (emulator-5554), RUNNER_TEMP.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"

pull_files() {
  for f in $(adb -s "$DEVICE" shell run-as "$PKG" ls app_flutter/ci_screens 2> /dev/null | tr -d '\r'); do
    case "$f" in *.png | *.md) ;; *) continue ;; esac
    adb -s "$DEVICE" exec-out run-as "$PKG" cat "app_flutter/ci_screens/$f" > "$OUT/screens/$f" || true
  done
}

fresh_app() {
  adb -s "$DEVICE" shell pm clear "$PKG" > /dev/null 2>&1 || true
  for p in POST_NOTIFICATIONS READ_SMS RECEIVE_SMS; do
    adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" > /dev/null 2>&1 || true
  done
  adb -s "$DEVICE" shell am force-stop "$PKG" || true
}

# The app window's attributes line from `dumpsys window windows`.
window_attrs() {
  adb -s "$DEVICE" shell dumpsys window windows < /dev/null 2> /dev/null | tr -d '\r' |
    awk -v pkg="$PKG" '/^  Window #/{inw=(index($0,pkg)>0 && index($0,"MainActivity")>0)} inw && /fl=/{print}' | head -3
}
# 0: FLAG_SECURE set; 1: not set; 2: could not tell.
secure_state() {
  local a hex
  a=$(window_attrs)
  if [ -z "$a" ]; then echo "  window attrs: none found"; return 2; fi
  echo "  window attrs: $(echo "$a" | grep -oE 'fl=[^}]*' | cut -c1-160 | head -1)"
  if echo "$a" | grep -qE 'fl=[^}]*(^|[ =])(FLAG_)?SECURE([ }]|$)'; then return 0; fi
  hex=$(echo "$a" | grep -oE 'fl=[0-9a-fA-F]{6,8}' | head -1 | cut -d= -f2)
  if [ -n "$hex" ]; then
    if [ $((0x$hex & 0x2000)) -ne 0 ]; then return 0; else return 1; fi
  fi
  # Named flags without SECURE: not secure.
  if echo "$a" | grep -qE 'fl=[A-Z_ ]+'; then return 1; fi
  return 2
}

wait_marker() { # log marker pid seconds
  for _ in $(seq 1 "$4"); do
    grep -q "$2" "$1" && return 0
    kill -0 "$3" 2> /dev/null || return 1
    sleep 1
  done
  return 1
}

run_test() { # name file [extra]
  echo "==== $1"
  fresh_app
  timeout 1500 flutter test "integration_test/$2" \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    > "$OUT/$1.log" 2>&1
  local r=$?
  grep -E "E2E[0-9]+ |Some tests|All tests" "$OUT/$1.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then echo "---- test log tail"; tail -50 "$OUT/$1.log" | cut -c1-220; fi
  pull_files
  adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-$1.png" || true
  return "$r"
}

run_lock() {
  echo "==== e2e11-lock"
  fresh_app
  timeout 1500 flutter test integration_test/e2e_lock_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    > "$OUT/e2e11-lock.log" 2>&1 &
  local tpid=$! bad=0 s
  if wait_marker "$OUT/e2e11-lock.log" "E2E11 SECURE_ON_CHECK" "$tpid" 900; then
    sleep 2
    secure_state; s=$?
    echo "E2E11 DEVICE lock on: secure state=$s (0 secure, 1 not, 2 unknown)"
    [ "$s" -eq 0 ] || { echo "E2E11 DEVICE PROBLEM FLAG_SECURE is not set while the lock is on"; bad=1; }
    adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/E2E11-device-locked.png" || true
  else
    echo "E2E11 DEVICE PROBLEM the test never reached the lock-on check"; bad=1
  fi
  if wait_marker "$OUT/e2e11-lock.log" "E2E11 SECURE_OFF_CHECK" "$tpid" 120; then
    sleep 2
    secure_state; s=$?
    echo "E2E11 DEVICE lock off: secure state=$s"
    [ "$s" -eq 1 ] || { echo "E2E11 DEVICE PROBLEM FLAG_SECURE is still set (or unknown) after the lock was turned off"; bad=1; }
  else
    echo "E2E11 DEVICE PROBLEM the test never reached the lock-off check"; bad=1
  fi
  wait "$tpid"
  local r=$?
  grep -E "E2E[0-9]+ |Some tests|All tests" "$OUT/e2e11-lock.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then tail -50 "$OUT/e2e11-lock.log" | cut -c1-220; fi
  pull_files
  [ "$r" -ne 0 ] && return "$r"
  return "$bad"
}

run_wipe() {
  echo "==== e2e12-wipe"
  fresh_app
  timeout 1500 flutter test integration_test/e2e_wipe_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    > "$OUT/e2e12-wipe.log" 2>&1 &
  local tpid=$! bad=0 n a
  if wait_marker "$OUT/e2e12-wipe.log" "E2E12 WIPED" "$tpid" 900; then
    n=$(adb -s "$DEVICE" shell dumpsys notification --noredact < /dev/null 2> /dev/null | grep -c "pkg=$PKG" || true)
    a=$(adb -s "$DEVICE" shell dumpsys alarm < /dev/null 2> /dev/null | grep -c "$PKG" || true)
    echo "E2E12 DEVICE after the wipe: posted notifications=$n, alarm lines=$a"
    echo "E2E12 DEVICE files:" $(adb -s "$DEVICE" shell run-as "$PKG" ls files databases app_flutter 2> /dev/null | tr -d '\r' | tr '\n' ' ' | cut -c1-300)
    [ "${n:-0}" -eq 0 ] || { echo "E2E12 DEVICE PROBLEM notifications are still posted after the wipe"; bad=1; }
  else
    echo "E2E12 DEVICE PROBLEM the test never reached the wipe check"; bad=1
  fi
  wait "$tpid"
  local r=$?
  grep -E "E2E[0-9]+ |Some tests|All tests" "$OUT/e2e12-wipe.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then tail -50 "$OUT/e2e12-wipe.log" | cut -c1-220; fi
  pull_files
  [ "$r" -ne 0 ] && return "$r"
  return "$bad"
}

flutter devices
echo "==== build and install"
adb -s "$DEVICE" uninstall "$PKG" > /dev/null 2>&1 || true
flutter build apk --debug --flavor devSms 2>&1 | tail -3
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
echo "apk: ${apk:-none}"
[ -n "$apk" ] || exit 1
adb -s "$DEVICE" install -r "$apk" || exit 1

run_test e2e09-export e2e_export_device_test.dart
r09=$?
run_test e2e10-locale e2e_locale_device_test.dart
r10=$?
run_lock
r11=$?
run_wipe
r12=$?
adb -s "$DEVICE" logcat -d -s flutter:V > "$OUT/flutter-logcat.txt" 2> /dev/null || true
echo "E2E RESULT 09=$r09 10=$r10 11=$r11 12=$r12"
ls -la "$OUT/screens"
[ "$r09" -eq 0 ] && [ "$r10" -eq 0 ] && [ "$r11" -eq 0 ] && [ "$r12" -eq 0 ]
