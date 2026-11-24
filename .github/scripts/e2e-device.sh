#!/usr/bin/env bash
# T-237: E2E-04 (manual add/edit/delete/undo/bulk), E2E-05 (payday 25, budget,
# 80 % alert, safe to spend) and E2E-06 (own transfer paired, reimbursement) on
# the Android emulator, with the real app (integration_test/e2e0*_test.dart).
# The tests print `E2E_DEVICE SEND <phase>`; this script then sends that
# phase's synthetic SMS through the emulator modem. Logs hold phase names,
# sender ids and counts, never a message body or amount. Called from
# device-flows.sh (E2E_ONLY=1). Inputs: DEVICE, RUNNER_TEMP.
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

sms_live() { # sender body
  local out
  out=$(adb -s "$DEVICE" emu sms send "$1" "$2" < /dev/null 2>&1 | tr -d '\r' | tr '\n' ' ')
  case "$out" in OK*) echo "  sent: $1"; return 0 ;; *) echo "  REFUSED: $1"; return 1 ;; esac
}
budget_notifs() { # how many notifications of the budget channel are posted
  adb -s "$DEVICE" shell dumpsys notification --noredact < /dev/null 2> /dev/null | grep -c "channel=zaghlol_alert_budget" || true
}

send_phase() { # test phase
  local dmy hm ref
  dmy=$(adb -s "$DEVICE" shell date +%d-%m-%Y < /dev/null | tr -d '\r')
  hm=$(adb -s "$DEVICE" shell date +%H:%M < /dev/null | tr -d '\r')
  ref=$(printf '%08x' "$(date +%s)")
  echo "---- phase $1/$2"
  case "$1/$2" in
    e2e05/p1)
      sms_live NBE 'NBE: Purchase of EGP 310.00 from NBE Visa **4567 at TALABAT. Balance EGP 7000.00'
      sleep 4
      sms_live NBE 'NBE: Purchase of EGP 290.00 from NBE Visa **4567 at TALABAT. Balance EGP 6710.00'
      ;;
    e2e05/p2)
      sleep 6
      echo "E2E_DEVICE NOTIF budget channel before 80%: $(budget_notifs)"
      sms_live NBE 'NBE: Purchase of EGP 200.00 from NBE Visa **4567 at TALABAT. Balance EGP 6510.00'
      ;;
    e2e06/x1)
      sms_live NBE 'NBE: Purchase of EGP 1200.00 from NBE Visa **4567 at TALABAT. Balance EGP 9000.00'
      ;;
    e2e06/x2)
      sms_live CIB "CIB: An instant transfer of EGP 2000.00 was made from your account ending ****7316, ref $ref on $dmy $hm. For more info call 19666."
      sleep 4
      sms_live NBE "National Bank of Egypt: You received an instant transfer of EGP 2000.00 from Ahmed Ali into your account ending ****9921, ref ${ref}a on $dmy $hm."
      ;;
    e2e06/x3)
      sms_live InstaPay "InstaPay: You received EGP 400.00 from SARA MAHMOUD into A/C *1234. Ref: 6291${ref}"
      ;;
    *) echo "unknown phase $1/$2" ;;
  esac
}

fresh_app() {
  adb -s "$DEVICE" shell pm clear "$PKG" || true
  for p in READ_SMS RECEIVE_SMS POST_NOTIFICATIONS; do
    adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" || echo "grant $p failed"
  done
  adb -s "$DEVICE" shell am force-stop "$PKG"
  adb -s "$DEVICE" shell "sqlite3 /data/user_de/0/com.android.providers.telephony/databases/mmssms.db 'DELETE FROM sms'" < /dev/null > /dev/null 2>&1 || true
}

run_one() { # name test-file
  local name=$1 file=$2 log="$OUT/$1-test.log" r tpid done_=" "
  echo "==== $name"
  fresh_app
  adb -s "$DEVICE" logcat -c || true
  timeout 1100 flutter test "integration_test/$file" \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    > "$log" 2>&1 &
  tpid=$!
  while kill -0 "$tpid" 2> /dev/null; do
    for p in $(grep -o 'E2E_DEVICE SEND [a-z0-9_]*' "$log" | awk '{print $3}' | sort -u); do
      case "$done_" in *" $p "*) continue ;; esac
      done_="$done_$p "
      send_phase "$name" "$p"
    done
    sleep 2
  done
  wait "$tpid"
  r=$?
  echo "$name exit: $r"
  grep -E "E2E_DEVICE|^[0-9:]+ [+-][0-9]+.*(Some tests|All tests)" "$log" | cut -c1-240
  if [ "$r" -ne 0 ]; then echo "---- $name log tail (no message text is printed)"; tail -40 "$log" | cut -c1-220; fi
  adb -s "$DEVICE" logcat -d -b crash 2> /dev/null | tail -10
  pull_files
  return "$r"
}

flutter devices
# one build + install (the grants below need the app installed)
flutter build apk --debug --flavor devSms 2>&1 | tail -3
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
echo "apk: ${apk:-none}"
[ -n "$apk" ] || exit 1
adb -s "$DEVICE" install -r "$apk" || exit 1

rc4=0; rc5=0; rc6=0
run_one e2e04 e2e04_manual_device_test.dart 2>&1 | tee "$OUT/e2e04-script.log"; rc4=${PIPESTATUS[0]}
run_one e2e05 e2e05_budget_device_test.dart 2>&1 | tee "$OUT/e2e05-script.log"; rc5=${PIPESTATUS[0]}
# the 80 % alert must be posted (the app is still installed, the alert stays)
n=$(budget_notifs)
echo "E2E_DEVICE NOTIF budget channel after 80%: $n"
if [ "${n:-0}" -lt 1 ]; then echo "E2E_DEVICE PROBLEM no budget notification posted"; rc5=1; fi
if grep -q "budget channel before 80%: [1-9]" "$OUT/e2e05-script.log"; then echo "E2E_DEVICE PROBLEM alert posted before 80%"; rc5=1; fi
run_one e2e06 e2e06_transfer_device_test.dart 2>&1 | tee "$OUT/e2e06-script.log"; rc6=${PIPESTATUS[0]}
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-e2e.png" || true
ls -la "$OUT/screens"
echo "E2E rc: e2e04=$rc4 e2e05=$rc5 e2e06=$rc6"
[ "$rc4" -eq 0 ] && [ "$rc5" -eq 0 ] && [ "$rc6" -eq 0 ]
