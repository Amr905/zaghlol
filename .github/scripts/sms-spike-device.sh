#!/usr/bin/env bash
# T-008 (SPK-01) on an Android emulator: real receiver → spool → WorkManager →
# headless engine → parse → DB commit → ack, with the app process killed
# before each SMS. Injects synthetic SMS with `adb emu sms send` (sender
# 5550100, the only allowlisted test sender) and pulls the spike metrics CSV
# (ULIDs + stage timings only) with run-as from the debuggable profile build.
#
# Negative proofs: a spoofed SMS_RECEIVED broadcast from the shell is denied
# (BROADCAST_SMS) and spools nothing; a non-allowlisted sender and an OTP
# leave spool/ empty; the canary never appears in the app's logcat lines.
#
# Env: DEVICE (emulator-5554), API (26..36), RUNNER_TEMP, N (SMS per cell).
# Results: $RUNNER_TEMP/sms-spike/{metrics.csv,report.md}; the report rows go
# into ADR-005 (emulator rows only; device rows come from T-008.md steps).
# Called as one line (android-emulator-runner runs `script` line by line).
set -euo pipefail
: "${DEVICE:?}" "${API:?}" "${RUNNER_TEMP:?}"
N=${N:-6}
PKG=app.zaghlol.dev
SENDER=5550100
CANARY=ZG_CANARY_7731
OUT="$RUNNER_TEMP/sms-spike"
mkdir -p "$OUT"
A() { adb -s "$DEVICE" "$@"; }
sh_() { A shell "$@" < /dev/null; }
runas() { sh_ run-as "$PKG" "$@"; }
rows() { runas cat no_backup/spike/metrics.csv 2>/dev/null | tail -n +2 | grep -c . || true; }
spool_count() { runas ls no_backup/spool 2>/dev/null | grep -c '\.bin$' || true; }
fail() { echo "::error::$*"; exit 1; }

cd "$(dirname "$0")/../../app"
flutter build apk --profile --flavor devSms > "$OUT/build.log" 2>&1 || { tail -n 40 "$OUT/build.log"; fail "devSms profile build failed"; }
APK=$(find build/app/outputs -iname '*devSms*profile.apk' | head -n 1)
[ -n "$APK" ] || fail "no devSms profile APK"
A install -r -g "$APK" > /dev/null
sh_ pm grant "$PKG" android.permission.RECEIVE_SMS
sh_ pm grant "$PKG" android.permission.READ_SMS
A logcat -c

# First launch: the UI engine creates the database (the headless engine never does).
sh_ am start -W -n "$PKG/app.zaghlol.MainActivity" > /dev/null
for _ in $(seq 1 60); do
  if runas ls files/db/zaghlol.db > /dev/null 2>&1; then break; fi
  sleep 1
done
runas ls files/db/zaghlol.db > /dev/null 2>&1 || fail "the UI engine did not create the database"
sh_ input keyevent KEYCODE_HOME
sleep 2

kill_app() {
  sh_ input keyevent KEYCODE_HOME
  sh_ am kill "$PKG"
  sleep 2
  if [ -n "$(sh_ pidof "$PKG" | tr -d '\r')" ]; then echo "warn: process still alive after am kill"; fi
}

# send_and_wait <label> <count>: one SMS per iteration, killed app before each.
seq_no=0
send_and_wait() {
  local label=$1 count=$2 before after i
  for i in $(seq 1 "$count"); do
    kill_app
    seq_no=$((seq_no + 1))
    before=$(rows)
    A emu sms send "$SENDER" "spike: you paid EGP $seq_no.00 at SYNTH SHOP $seq_no card *4321" > /dev/null
    for _ in $(seq 1 90); do
      after=$(rows)
      [ "$after" -gt "$before" ] && break
      sleep 1
    done
    echo "$label #$i: rows $before -> $after"
  done
}

# Cell 1: default settings (battery optimisation on), cold process.
send_and_wait default "$N"
# Cell 2: battery optimisation exemption (whitelist), cold process.
sh_ dumpsys deviceidle whitelist +"$PKG" > /dev/null
send_and_wait exempt "$N"
sh_ dumpsys deviceidle whitelist -"$PKG" > /dev/null
# Cell 3: standby bucket rare (API 28+) and restricted (API 30+).
if [ "$API" -ge 28 ]; then
  sh_ am set-standby-bucket "$PKG" rare
  send_and_wait rare "$N"
  if [ "$API" -ge 30 ]; then
    sh_ am set-standby-bucket "$PKG" restricted
    send_and_wait restricted "$N"
  fi
  sh_ am set-standby-bucket "$PKG" active
fi
# Cell 4: Doze forced (deep idle); recorded, delivery may wait for a window.
sh_ dumpsys battery unplug > /dev/null
sh_ dumpsys deviceidle force-idle > /dev/null || true
send_and_wait doze 2
sh_ dumpsys deviceidle unforce > /dev/null || true
sh_ dumpsys battery reset > /dev/null

# Negative proofs.
kill_app
before=$(rows)
sh_ am broadcast -a android.provider.Telephony.SMS_RECEIVED -n "$PKG/app.zaghlol.spike.sms.SpikeSmsReceiver" > "$OUT/spoof.txt" 2>&1 || true
A emu sms send 5550199 "$CANARY hello from a friend" > /dev/null
A emu sms send "$SENDER" "$CANARY your OTP is 123456" > /dev/null
sleep 15
[ "$(spool_count)" = 0 ] || fail "spool not empty after spoofed / non-allowlisted / OTP messages"
[ "$(rows)" = "$before" ] || fail "a dropped message produced a metrics row"
A logcat -d > "$OUT/logcat-all.txt"
if grep -q "Permission Denial.*SMS_RECEIVED.*BROADCAST_SMS\|requires android.permission.BROADCAST_SMS" "$OUT/logcat-all.txt"; then
  echo "spoofed broadcast: denied (BROADCAST_SMS)"
else
  echo "warn: no permission-denial line found for the spoofed broadcast (spool stayed empty)"
fi
# Canary through the kept path too, then scan the app's own log lines.
send_and_wait canary 1
A emu sms send "$SENDER" "spike: you paid EGP 77.00 at $CANARY card *4321" > /dev/null
sleep 20
UID_N=$(sh_ dumpsys package "$PKG" | grep -m1 -oE 'userId=[0-9]+' | cut -d= -f2)
A logcat -d -v uid > "$OUT/logcat-uid.txt" || true
APP_NAME="u0_a$((UID_N - 10000))"
hits=$(grep -F "$CANARY" "$OUT/logcat-uid.txt" | grep -E "(^|[[:space:]])($UID_N|$APP_NAME)[[:space:]]" | grep -c . || true)
all_hits=$(grep -cF "$CANARY" "$OUT/logcat-all.txt" || true)
echo "canary: app log lines $hits; all buffers $all_hits (system telephony lines are not the app's)"
[ "$hits" = 0 ] || fail "the canary appeared in the app's logcat"
grep -E "ZG-SPK" "$OUT/logcat-all.txt" | grep -F "$CANARY" && fail "spike log carried content" || true

runas cat no_backup/spike/metrics.csv > "$OUT/metrics.csv"
grep -qF "$CANARY" "$OUT/metrics.csv" && fail "metrics carried content" || true
grep -qF "$SENDER" "$OUT/metrics.csv" && fail "metrics carried the sender" || true
dart run tool/spike/latency_report.dart "$OUT/metrics.csv" "emu-api$API" | tee "$OUT/report.md"
n=$(tail -n +2 "$OUT/metrics.csv" | grep -c . || true)
[ "$n" -ge "$N" ] || fail "only $n messages were committed"
rm -f "$OUT/logcat-all.txt" "$OUT/logcat-uid.txt"
