#!/usr/bin/env bash
# T-236 (E2E-03, E2E-07, notification capture): SMS while the app is not
# running, an ignored card, and a notification from a user-chosen package, on
# the Android emulator. Drives integration_test/sms_killed_device_test.dart one
# PHASE at a time (see the header of that file); each phase is its own
# `flutter test` run against the same installed app and data. Synthetic data;
# logs hold phases, counts and times, never a message body.
# Inputs: DEVICE (emulator-5554), RUNNER_TEMP. Called from device-flows.sh
# (KILLED_ONLY=1) so that android-emulator-runner runs one line.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"
A() { adb -s "$DEVICE" "$@" < /dev/null; }
LISTENER="$PKG/app.zaghlol.platform.capture.BankNotificationListener"

pull_files() {
  for f in $(A shell run-as "$PKG" ls app_flutter/ci_screens 2> /dev/null | tr -d '\r'); do
    case "$f" in *.png | *.md) ;; *) continue ;; esac
    adb -s "$DEVICE" exec-out run-as "$PKG" cat "app_flutter/ci_screens/$f" > "$OUT/screens/$f" || true
  done
}

sms_send() { # sender body
  local out
  out=$(A emu sms send "$1" "$2" 2>&1 | tr -d '\r' | tr '\n' ' ')
  echo "  emu[$1]: ${out:0:30}"
  case "$out" in OK*) return 0 ;; *) return 1 ;; esac
}

# One synthetic HSBC card SMS: card, amount (EGP, "731.25"), the device's today.
hsbc_body() {
  local dmy
  dmy=$(A shell date +%d/%m/%Y | tr -d '\r')
  echo "Your Credit Card ending with * $1 has been used for EGP $2 on $dmy at UDEMY SUBSCRIPTION. Your available limit is EGP 27623.16"
}

phase_rc=()
run_phase() { # name [extra dart-define args...]
  local name=$1
  shift
  echo "---- flutter test PHASE=$name"
  timeout 900 flutter test integration_test/sms_killed_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    --dart-define=PHASE="$name" "$@" > "$OUT/killed-$name-test.log" 2>&1
  local r=$?
  grep -E "KILLED_DEVICE|Some tests|All tests" "$OUT/killed-$name-test.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then tail -30 "$OUT/killed-$name-test.log" | cut -c1-220; fi
  phase_rc+=("$name=$r")
  pull_files
  return "$r"
}

device_s() { A shell date +%s | tr -d '\r'; }
is_stopped() { A shell dumpsys package "$PKG" 2> /dev/null | grep -c "stopped=true" || true; }

echo "==== killed-app device (T-236)"
A uninstall "$PKG" > /dev/null 2>&1 || true
flutter build apk --debug --flavor devSms 2>&1 | tail -3
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
echo "apk: ${apk:-none}"
[ -n "$apk" ] || exit 1
A install -r "$apk" || exit 1
for p in READ_SMS RECEIVE_SMS POST_NOTIFICATIONS; do
  A shell pm grant "$PKG" "android.permission.$p" || echo "grant $p failed"
done
A logcat -c || true

rc=0
# ---- prep: watermark, ignore rule (card 5555), notification sender
run_phase prep || rc=1

# ---- E2E-03 + E2E-07: force-stop, then the SMS, then the launch
A shell am force-stop "$PKG"
sleep 2
echo "stopped state: $(is_stopped)"
sent=$(device_s)
sms_send HSBC "$(hsbc_body 4444 731.25)" || echo "  send refused (kept)"
sleep 2
sms_send HSBC "$(hsbc_body 5555 953.75)" || echo "  send refused (ignored)"
sleep 6
echo "waited with the app force-stopped; pid: '$(A shell pidof "$PKG" | tr -d '\r')'"
run_phase forcestop --dart-define=SENT_MS="${sent}000" || rc=1

# ---- the process killed (not force-stopped): the receiver cold-starts it
A shell am start -n "$PKG/app.zaghlol.MainActivity" > /dev/null 2>&1 || A shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 10
pid=$(A shell pidof "$PKG" | tr -d '\r')
echo "kill: pid '$pid'"
if [ -n "$pid" ]; then
  A shell run-as "$PKG" kill -9 "$pid" > /dev/null 2>&1 || A shell kill -9 "$pid" > /dev/null 2>&1 || true
  sleep 3
fi
echo "after kill: pid '$(A shell pidof "$PKG" | tr -d '\r')' stopped=$(is_stopped)"
sent=$(device_s)
sms_send HSBC "$(hsbc_body 4444 842.50)" || echo "  send refused (killed)"
sleep 10
echo "after the SMS: pid '$(A shell pidof "$PKG" | tr -d '\r')'"
run_phase kill --dart-define=SENT_MS="${sent}000" || rc=1

# ---- notification capture: listener access, a notification from the shell
echo "---- notification capture"
A shell cmd notification allow_listener "$LISTENER" 2>&1 | tr -d '\r' | head -2
A shell settings get secure enabled_notification_listeners | tr -d '\r' | grep -c "$PKG" | sed 's/^/listener entries: /'
timeout 480 flutter test integration_test/sms_killed_device_test.dart \
  --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
  --dart-define=PHASE=notif > "$OUT/killed-notif-test.log" 2>&1 &
tpid=$!
for _ in $(seq 1 300); do
  grep -q "KILLED_DEVICE READY_FOR_NOTIF" "$OUT/killed-notif-test.log" && break
  kill -0 "$tpid" 2> /dev/null || break
  sleep 3
done
if grep -q "KILLED_DEVICE READY_FOR_NOTIF" "$OUT/killed-notif-test.log"; then
  sleep 3
  body=$(hsbc_body 4444 612.50)
  out=$(A shell "cmd notification post -S bigtext -t HSBC zagtag '$body'" 2>&1 | tr -d '\r' | head -2 | cut -c1-80)
  echo "posted: ${out:-ok}"
  A shell dumpsys notification --noredact 2> /dev/null | tr -d '\r' | grep -c "pkg=com.android.shell" | sed 's/^/shell notifications present: /'
else
  echo "the notif test never reached READY_FOR_NOTIF"
fi
wait "$tpid"
r=$?
grep -E "KILLED_DEVICE|Some tests|All tests" "$OUT/killed-notif-test.log" | cut -c1-240
if [ "$r" -ne 0 ]; then tail -30 "$OUT/killed-notif-test.log" | cut -c1-220; rc=1; fi
phase_rc+=("notif=$r")
pull_files

echo "---- phases: ${phase_rc[*]}"
A logcat -d -b crash 2> /dev/null | tail -20
A logcat -d 2> /dev/null | grep -E "FATAL|ANR in|Process $PKG.*died" | cut -c1-200 | tail -10
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-killed.png" || true
ls -la "$OUT/screens"
exit "$rc"
