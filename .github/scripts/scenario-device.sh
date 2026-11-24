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

inbox_insert() { # sender body ms  (a row in the system inbox with its own date)
  local out
  out=$(adb -s "$DEVICE" shell "content insert --uri content://sms/inbox --bind address:s:'$1' --bind body:s:'$2' --bind date:l:$3 --bind read:i:0 --bind type:i:1" 2>&1 | tr -d '\r' | head -3 | tr '\n' ' ')
  [ -z "$out" ]
}
sms_live() { # sender body
  local out
  out=$(adb -s "$DEVICE" emu sms send "$1" "$2" 2>&1 | tr -d '\r' | tr '\n' ' ')
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
  adb -s "$DEVICE" shell "content delete --uri content://sms" > /dev/null 2>&1 || true
  # ---- the past: into the inbox with their dates, before the first launch
  local ok=0 bad=0
  while IFS=$'\t' read -r id sender mago day time body; do
    read -r ms dmy hm <<< "$(entry_time "$mago" "$day" "$time")"
    body=${body//\{DD-MM-YYYY\}/$dmy}
    body=${body//\{HH:MM\}/$hm}
    if inbox_insert "$sender" "$body" "$ms"; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "  inbox insert failed: $id ($sender)"; fi
  done < <(jq -r '.entries[] | select(.delivery=="inbox") | [.id, .sender, .monthsAgo, .day, .time, .body] | @tsv' "$SCEN")
  echo "inbox rows written: $ok failed: $bad"
  adb -s "$DEVICE" shell "content query --uri content://sms/inbox --projection address" 2>&1 | tr -d '\r' | sed -n 's/^Row: [0-9]* address=//p' | sort | uniq -c | sed 's/^/  inbox: /'
  adb -s "$DEVICE" unroot > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  sleep 3
  adb -s "$DEVICE" shell am force-stop "$PKG"
  adb -s "$DEVICE" logcat -c || true
  timeout 1500 flutter test integration_test/sms_charts_device_test.dart \
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

flutter devices
run_scenario 2>&1 | tee "$OUT/scenario-device-script.log"
rc=${PIPESTATUS[0]}
pull_files
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-scenario.png" || true
ls -la "$OUT/screens"
exit "$rc"
