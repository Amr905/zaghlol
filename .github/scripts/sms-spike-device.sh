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
# Broadcast times (review F2): after each SMS the system broadcast history
# (`dumpsys activity broadcasts history`) is saved to a temp dir; at the end
# only the SMS_RECEIVED enqueue/dispatch timestamps are extracted into
# broadcasts.txt and the raw dumps are deleted. The report matches them to
# the rows by the receive wall clock (enqueue → commit = FR-ING-A-01).
# Results: $RUNNER_TEMP/sms-spike/{metrics.csv,broadcasts.txt,report.md}; the report rows go
# into ADR-005 (emulator rows only; device rows come from T-008.md steps).
# Called as one line (android-emulator-runner runs `script` line by line).
set -euo pipefail
: "${DEVICE:?}" "${API:?}" "${RUNNER_TEMP:?}"
N=${N:-6}
PKG=app.zaghlol.dev
SENDER=5550100
CANARY=ZG_CANARY_7731
OUT="$RUNNER_TEMP/sms-spike"
BH="$OUT/bh"  # raw broadcast history dumps; deleted after extraction
mkdir -p "$OUT" "$BH"
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
A logcat -c || true  # some emulator images refuse to clear "main"

# First launch: the UI engine creates the database (the headless engine never does).
sh_ am start -W -n "$PKG/app.zaghlol.MainActivity" > /dev/null
for _ in $(seq 1 60); do
  if runas ls files/db/zaghlol.db > /dev/null 2>&1; then break; fi
  sleep 1
done
runas ls files/db/zaghlol.db > /dev/null 2>&1 || fail "the UI engine did not create the database"
sh_ input keyevent KEYCODE_HOME
sleep 2

# Process death as the low-memory killer does it, never `am force-stop` (that
# puts the app in the stopped state, which blocks SMS delivery). `am kill`
# leaves the process alive on some images (API 26: every run labelled
# "foreground"), so fall back to SIGKILL from the app's own uid via run-as.
kill_app() {
  local pid
  sh_ input keyevent KEYCODE_HOME
  sh_ am kill "$PKG"
  sleep 2
  pid=$(sh_ pidof "$PKG" | tr -d '\r' || true)
  if [ -n "$pid" ]; then
    runas kill -9 $pid || true
    sleep 2
    if [ -n "$(sh_ pidof "$PKG" | tr -d '\r' || true)" ]; then echo "warn: process still alive after am kill and SIGKILL"; fi
  fi
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
    sh_ dumpsys activity broadcasts history > "$BH/$(printf %04d "$seq_no").txt" 2>/dev/null || true
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
# SMS_RECEIVED is a protected broadcast, so the shell's send is refused by the
# system (SecurityException in am's output); the receiver's BROADCAST_SMS
# requirement is the second line of defence. The hard check is the empty spool.
if grep -qiE "SecurityException|Permission Denial|not allowed to send broadcast" "$OUT/spoof.txt" "$OUT/logcat-all.txt"; then
  echo "spoofed broadcast: denied ($(grep -hoiE "SecurityException|Permission Denial|not allowed to send broadcast" "$OUT/spoof.txt" "$OUT/logcat-all.txt" | sort -u | tr '\n' ' '))"
else
  echo "warn: no denial line found for the spoofed broadcast (spool stayed empty)"
fi
# Canary through the kept path too, then scan the app's own log lines.
send_and_wait canary 1
A emu sms send "$SENDER" "spike: you paid EGP 77.00 at $CANARY card *4321" > /dev/null
sleep 20
sh_ pm list packages -U > "$OUT/pkg.txt"  # no early-exit grep in a pipe (pipefail)
UID_N=$(grep -E "^package:$PKG uid:" "$OUT/pkg.txt" | grep -oE 'uid:[0-9]+' | cut -d: -f2 || true)
if [ -z "$UID_N" ]; then
  sh_ dumpsys package "$PKG" > "$OUT/pkg.txt"
  UID_N=$(grep -oE '(userId|appId)=[0-9]+' "$OUT/pkg.txt" | cut -d= -f2 | sort -u | tail -n 1 || true)
fi
[ -n "$UID_N" ] || fail "could not read the app uid"
A logcat -d -v uid > "$OUT/logcat-uid.txt" || true
APP_NAME="u0_a$((UID_N - 10000))"
# The filter must see the app's own lines (its ZG-SPK codes), or it proves nothing.
own=$(grep -E "(^|[[:space:]])($UID_N|$APP_NAME)[[:space:]]" "$OUT/logcat-uid.txt" | grep -c . || true)
[ "$own" -gt 0 ] || fail "the logcat uid filter matched no app line; canary scan would be vacuous"
grep -F "$CANARY" "$OUT/logcat-uid.txt" > "$OUT/canary-lines.txt" || true  # synthetic text only
hits=$(grep -E "(^|[[:space:]])($UID_N|$APP_NAME)[[:space:]]" "$OUT/canary-lines.txt" | grep -c . || true)
all_hits=$(grep -cF "$CANARY" "$OUT/logcat-all.txt" || true)
echo "canary: app log lines $hits of $own app lines; all buffers $all_hits (non-app lines in canary-lines.txt)"
[ "$hits" = 0 ] || fail "the canary appeared in the app's logcat"
grep -E "ZG-SPK" "$OUT/logcat-all.txt" | grep -F "$CANARY" && fail "spike log carried content" || true

runas cat no_backup/spike/metrics.csv > "$OUT/metrics.csv"
grep -qF "$CANARY" "$OUT/metrics.csv" && fail "metrics carried content" || true
grep -qF "$SENDER" "$OUT/metrics.csv" && fail "metrics carried the sender" || true
# Last dump after every send (incl. the negative proofs and the last canary
# SMS): matching needs the broadcast of every SMS, also of dropped ones.
sh_ dumpsys activity broadcasts history > "$BH/9999.txt" 2>/dev/null || true
TZ_OFF=$(sh_ date +%z | tr -d '\r')
dart run tool/spike/latency_report.dart --extract-broadcasts "$BH" "$TZ_OFF" > "$OUT/broadcasts.txt"
nb=$(grep -c '^enqueue_ms=' "$OUT/broadcasts.txt" || true)
if [ "$nb" = 0 ]; then  # format diagnosis (emulator, synthetic SMS only): timestamps/record lines near the action
  last=$(ls "$BH" | tail -n 1)
  [ -n "$last" ] && grep -n -B4 -A8 'SMS_RECEIVED' "$BH/$last" | grep -iE 'BroadcastRecord|Historical|#[0-9]+:|enqueue|dispatch|act=' | head -n 40 || true
fi
rm -rf "$BH"
echo "broadcast history: $nb SMS_RECEIVED records (device tz $TZ_OFF)"
[ "$nb" -gt 0 ] || fail "no SMS_RECEIVED record in the broadcast history; enqueue → commit can't be reported"
grep -qF "$PKG" "$OUT/broadcasts.txt" && fail "broadcasts.txt carried more than timestamps" || true
dart run tool/spike/latency_report.dart "$OUT/metrics.csv" "emu-api$API" "$OUT/broadcasts.txt" | tee "$OUT/report.md"
n=$(tail -n +2 "$OUT/metrics.csv" | grep -c . || true)
[ "$n" -ge "$N" ] || fail "only $n messages were committed"
rm -f "$OUT/logcat-all.txt" "$OUT/logcat-uid.txt" "$OUT/pkg.txt"
