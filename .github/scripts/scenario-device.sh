#!/usr/bin/env bash
# T-233: the SMS month story on the Android emulator. Synthetic bank/wallet SMS
# from app/test/fixtures/sms/scenarios/month_story.json are put in the system
# inbox with their own dates (past ones, before the app's first launch) or sent
# through the emulator modem while the app runs (live ones). The real app
# (integration_test/sms_charts_device_test.dart) must save them as the scenario
# expects and its Insights screens must show the expected numbers.
# Logs hold entry ids, sender ids and counts, never a message body.
# Inputs: DEVICE (emulator-5554), RUNNER_TEMP. Called from device-flows.sh
# (SCENARIO_ONLY=1) so that android-emulator-runner runs one line.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"
SCEN=test/fixtures/sms/scenarios/month_story.json

pull_files() {
  for f in $(adb -s "$DEVICE" shell run-as "$PKG" ls app_flutter/ci_screens 2>/dev/null | tr -d '\r'); do
    case "$f" in *.png | *.md) ;; *) continue ;; esac
    adb -s "$DEVICE" exec-out run-as "$PKG" cat "app_flutter/ci_screens/$f" > "$OUT/screens/$f" || true
  done
}

# The device's own clock and zone decide "this month" and the dates of the
# entries (the test computes the same).
tz=$(adb -s "$DEVICE" shell getprop persist.sys.timezone | tr -d '\r')
[ -n "$tz" ] || tz=UTC
today=$(adb -s "$DEVICE" shell date +%Y-%m-%d | tr -d '\r')
ym="${today:0:7}"
echo "scenario: device zone $tz, month $ym"

# the dart-define file the test reads the scenario from
jq -c '{SCENARIO_JSON: tojson}' "$SCEN" > "$OUT/scenario-define.json"
n_inbox=$(jq '[.entries[] | select(.delivery=="inbox")] | length' "$SCEN")
n_live=$(jq '[.entries[] | select(.delivery=="live")] | length' "$SCEN")
echo "scenario: inbox=$n_inbox live=$n_live manual=$(jq '[.entries[] | select(.delivery=="manual")] | length' "$SCEN")"

# entry_time <monthsAgo> <day> <HH:MM>: prints "<epoch ms> <DD-MM-YYYY> <HH:MM>"
entry_time() {
  local ym2 d
  ym2=$(date -d "${ym}-01 -$1 month" +%Y-%m)
  d=$(printf '%02d' "$2")
  local ms
  ms=$(TZ="$tz" date -d "${ym2}-${d} $3" +%s)000
  echo "$ms ${d}-${ym2:5:2}-${ym2:0:4} $3"
}

sms_live() { # sender body
  local out
  out=$(adb -s "$DEVICE" emu sms send "$1" "$2" < /dev/null 2>&1 | tr -d '\r' | tr '\n' ' ')
  case "$out" in OK*) return 0 ;; *) return 1 ;; esac
}

run_scenario() {
  echo "==== scenario device"
  adb -s "$DEVICE" uninstall "$PKG" > /dev/null 2>&1 || true
  flutter build apk --debug --flavor devSms 2>&1 | tail -3
  apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
  echo "apk: ${apk:-none}"
  [ -n "$apk" ] || return 1
  adb -s "$DEVICE" install -r "$apk" || return 1
  for p in READ_SMS RECEIVE_SMS POST_NOTIFICATIONS; do
    adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" || echo "grant $p failed"
  done
  adb -s "$DEVICE" shell am force-stop "$PKG"
  adb -s "$DEVICE" root > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  adb -s "$DEVICE" shell "sqlite3 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db 'DELETE FROM sms'" < /dev/null > /dev/null 2>&1 || true
  # ---- the past: into the inbox with their dates, before the first launch
  # The system SMS provider refuses writes and reads from the shell (`content
  # insert` answers nothing or its usage text, direct sqlite3 rows are never
  # seen by apps; probe on ci/T-233-probe, 2026-11-24). What works is the
  # modem, which stamps a message with the device clock: so the clock is set
  # to each entry's own time (root, auto time off), the message is sent through
  # the emulator console, and the clock is put back at the end.
  adb -s "$DEVICE" shell "settings put global auto_time 0" < /dev/null > /dev/null 2>&1 || true
  adb -s "$DEVICE" shell "settings put global auto_time_zone 0" < /dev/null > /dev/null 2>&1 || true
  adb -s "$DEVICE" shell "sqlite3 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db 'DELETE FROM sms'" < /dev/null > /dev/null 2>&1 || true
  restore_clock() {
    adb -s "$DEVICE" shell "date -u $(date -u +%m%d%H%M%Y.%S)" < /dev/null > /dev/null 2>&1
    adb -s "$DEVICE" shell "settings put global auto_time 1" < /dev/null > /dev/null 2>&1 || true
    adb -s "$DEVICE" shell "settings put global auto_time_zone 1" < /dev/null > /dev/null 2>&1 || true
  }
  # a cancelled or failed job must not leave the emulator clock in the past
  trap restore_clock EXIT INT TERM
  local ok=0 bad=0 start_s
  start_s=$(date -u +%s)
  while IFS=$'\t' read -r id sender mago day time body; do
    read -r ms dmy hm <<< "$(entry_time "$mago" "$day" "$time")"
    body=${body//\{DD-MM-YYYY\}/$dmy}
    body=${body//\{HH:MM\}/$hm}
    adb -s "$DEVICE" shell "date -u $(date -u -d "@$((ms / 1000))" +%m%d%H%M%Y.%S)" < /dev/null > /dev/null 2>&1
    if sms_live "$sender" "$body"; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "  past send refused: $id ($sender)"; fi
    sleep 2
  done < <(jq -r '.entries[] | select(.delivery=="inbox") | [.id, .sender, .monthsAgo, .day, .time, .body] | @tsv' "$SCEN")
  # the clock back: host time now
  adb -s "$DEVICE" shell "date -u $(date -u +%m%d%H%M%Y.%S)" < /dev/null > /dev/null 2>&1
  adb -s "$DEVICE" shell "settings put global auto_time 1" < /dev/null > /dev/null 2>&1 || true
  adb -s "$DEVICE" shell "settings put global auto_time_zone 1" < /dev/null > /dev/null 2>&1 || true
  echo "past messages sent: $ok refused: $bad; device date now: $(adb -s "$DEVICE" shell date -u < /dev/null | tr -d '\r')"
  echo "in the telephony database: $(adb -s "$DEVICE" shell "sqlite3 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db 'SELECT count(*) FROM sms WHERE type=1'" < /dev/null | tr -d '\r')"
  adb -s "$DEVICE" unroot > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  sleep 3
  adb -s "$DEVICE" shell am force-stop "$PKG"
  adb -s "$DEVICE" logcat -c || true
  timeout 1200 flutter test integration_test/sms_charts_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    --dart-define-from-file="$OUT/scenario-define.json" \
    > "$OUT/scenario-device-test.log" 2>&1 &
  tpid=$!
  for _ in $(seq 1 400); do
    grep -q "SCENARIO_DEVICE READY_FOR_LIVE" "$OUT/scenario-device-test.log" && break
    kill -0 "$tpid" 2> /dev/null || break
    sleep 3
  done
  if grep -q "SCENARIO_DEVICE READY_FOR_LIVE" "$OUT/scenario-device-test.log"; then
    echo "---- live"
    while IFS=$'\t' read -r id sender body; do
      if sms_live "$sender" "$body"; then echo "  live ok: $id ($sender)"; else echo "  live REFUSED: $id ($sender)"; fi
      sleep 4
    done < <(jq -r '.entries[] | select(.delivery=="live") | [.id, .sender, .body] | @tsv' "$SCEN")
    echo "SCENARIO_LIVE_SENT"
  else
    echo "the test never reached the live part"
  fi
  wait "$tpid"
  r=$?
  echo "scenario device test exit: $r"
  grep -E "SCENARIO_DEVICE|^[0-9:]+ [+-][0-9]+.*(Some tests|All tests)" "$OUT/scenario-device-test.log" | cut -c1-260
  if [ "$r" -ne 0 ]; then echo "---- test log tail (the test prints no message text)"; tail -40 "$OUT/scenario-device-test.log" | cut -c1-220; fi
  adb -s "$DEVICE" logcat -d -b crash 2> /dev/null | tail -20
  return "$r"
}


if [ -n "${SCENARIO_PROBE:-}" ]; then
  # Diagnostics only (ci/T-233-probe): which way puts a dated, colon-bearing
  # message into the system inbox? Synthetic strings; no APK needed.
  cnt() { adb -s "$DEVICE" shell "content query --uri content://sms --projection address:date" < /dev/null 2>&1 | tr -d '\r' | grep -c '^Row:'; }
  adb -s "$DEVICE" root > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  echo "probe: id=$(adb -s "$DEVICE" shell id -un < /dev/null | tr -d '\r') sdk=$(adb -s "$DEVICE" shell getprop ro.build.version.sdk < /dev/null | tr -d '\r')"
  echo "probe: sqlite3=$(adb -s "$DEVICE" shell 'which sqlite3' < /dev/null | tr -d '\r')"
  adb -s "$DEVICE" shell 'ls -l /data/user_de/0/com.android.providers.telephony/databases/' < /dev/null 2>&1 | tr -d '\r' | head -8
  echo "probe: count start=$(cnt)"
  ms=$(( $(date +%s) - 86400 * 40 ))000
  r=$(adb -s "$DEVICE" shell "content insert --uri content://sms/inbox --bind address:s:CIB --bind body:s:plain_body_no_colon --bind date:l:$ms --bind read:i:0 --bind type:i:1" < /dev/null 2>&1 | tr -d '\r' | head -2 | cut -c1-100)
  echo "probe T0 plain: answer='$r' count=$(cnt)"
  r=$(adb -s "$DEVICE" shell "content insert --uri content://sms/inbox --bind address:s:CIB --bind 'body:s:has colon\: here, and comma' --bind date:l:$ms --bind read:i:0 --bind type:i:1" < /dev/null 2>&1 | tr -d '\r' | head -2 | cut -c1-100)
  echo "probe T1 escaped colon: answer='$r' count=$(cnt)"
  r=$(adb -s "$DEVICE" shell "content insert --uri content://sms/inbox --bind address:s:CIB --bind 'body:s:has colon: here' --bind date:l:$ms --bind read:i:0 --bind type:i:1" < /dev/null 2>&1 | tr -d '\r' | head -2 | cut -c1-100)
  echo "probe T2 raw colon: answer='$r' count=$(cnt)"
  r=$(adb -s "$DEVICE" shell "content insert --uri content://sms/inbox --bind address:s:CIB --bind 'body:s:has comma, only' --bind date:l:$ms --bind read:i:0 --bind type:i:1" < /dev/null 2>&1 | tr -d '\r' | head -2 | cut -c1-100)
  echo "probe T3 comma: answer='$r' count=$(cnt)"
  r=$(adb -s "$DEVICE" shell "sqlite3 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db \"INSERT INTO sms (address, body, date, date_sent, read, seen, type) VALUES ('CIB', 'sqlite colon: here, comma', $ms, $ms, 0, 0, 1)\"" < /dev/null 2>&1 | tr -d '\r' | head -2 | cut -c1-120)
  echo "probe T4 sqlite3: answer='$r' count=$(cnt)"
  adb -s "$DEVICE" shell "content query --uri content://sms --projection address:date:type" < /dev/null 2>&1 | tr -d '\r' | head -8
  exit 0
fi

flutter devices
run_scenario 2>&1 | tee "$OUT/scenario-device-script.log"
rc=${PIPESTATUS[0]}
pull_files
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-scenario.png" || true
ls -la "$OUT/screens"
exit "$rc"
