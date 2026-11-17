#!/usr/bin/env bash
# FIX-device-flows + TEST-explorer (device-flows.yml): runs
# integration_test/device_flows_test.dart (the real app composition), then
# integration_test/app_explorer_test.dart (taps every control of every screen,
# in Arabic, then English, dark, text scale 1.3, the paywall and onboarding;
# synthetic data) on the Android emulator, and pulls the
# screenshots and the explorer report the tests wrote to the app's private
# dir. Called as one line because android-emulator-runner runs its `script`
# input line by line. Inputs: DEVICE (emulator-5554), RUNNER_TEMP.
# Synthetic data only.
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

flutter devices
adb -s "$DEVICE" logcat -c || true

# ---- 0. SMS on the device (SMS-device): permissions by `pm grant`, synthetic
# SMS before the first launch (historical inbox scan) and while the app runs
# (live receiver), then the real app must have saved them. The emulator console
# (`adb emu sms send`) is tried first for every sender, alphanumeric ones
# included (the current emulator accepts letters). If the console ever refuses
# a sender id, the historical part falls back to `content insert` into the
# system inbox (the emulator image allows adb root).
# Logs hold sender ids and counts, never a message body.
HSBC_USD_H='Your Credit Card ending with * 5076 has been used for USD 115.00 on 09/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is EGP 110096.30'
HSBC_EGP_H='Your Credit Card ending with * 9376 has been used for EGP 1959.40 on 08/11/2026 at UDEMY SUBSCRIPTION. Your available limit is EGP 27623.16'
CIB_H='يرجى العلم انه تم تنفيذ تحويل لحظي بمبلغ 510.00 جم من حسابك المنتهي بـ ****0939 برقم مرجعي b25d10dd بتاريخ 17-05-2026 22:32 للمزيد، برجاء الاتصال بـ 19666'
NBE_H='Dear customer, EGP 251.00 was debited from your account *4568 at CARREFOUR MAADI on 09/11/2026'
HSBC_USD_L='Your Credit Card ending with * 5077 has been used for USD 116.00 on 10/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is EGP 110097.31'
HSBC_EGP_L='Your Credit Card ending with * 9377 has been used for EGP 1960.40 on 09/11/2026 at UDEMY SUBSCRIPTION. Your available limit is EGP 27624.17'
CIB_L='يرجى العلم انه تم تنفيذ تحويل لحظي بمبلغ 520.00 جم من حسابك المنتهي بـ ****0940 برقم مرجعي b25d10de بتاريخ 18-05-2026 22:33 للمزيد، برجاء الاتصال بـ 19666'
NBE_L='Dear customer, EGP 252.00 was debited from your account *4569 at SPINNEYS ZAMALEK on 10/11/2026'
NODIGIT='Thank you for banking with HSBC'
PERSONAL='hello from a friend 5'
# Live copies differ from the historical ones: telephony drops an identical repeat.
NODIGIT_L='Thank you for banking with HSBC again'
PERSONAL_L='hello from a friend 6'

sms_emu() { # sender body: the emulator modem (real telephony, the real SmsReceiver when the app runs)
  local out
  out=$(adb -s "$DEVICE" emu sms send "$1" "$2" 2>&1 | tr -d '\r' | tr '\n' ' ')
  echo "  emu[$1]: ${out:0:40}"
  case "$out" in OK*) return 0 ;; *) return 1 ;; esac
}
sms_inbox_insert() { # sender body: a row in the system inbox (fallback when the console refuses the sender)
  local out
  out=$(adb -s "$DEVICE" shell "content insert --uri content://sms/inbox --bind address:s:'$1' --bind body:s:'$2' --bind date:l:$(date +%s)000 --bind read:i:0 --bind type:i:1" 2>&1 | tr -d '\r' | head -3 | tr '\n' ' ')
  echo "  insert[$1]: ${out:-ok}"
}
sms_hist() { sms_emu "$1" "$2" || sms_inbox_insert "$1" "$2"; }
sms_live() { sms_emu "$1" "$2"; }
inbox_rows() { # counts per sender in the system inbox (needs root); no bodies
  adb -s "$DEVICE" shell "content query --uri content://sms/inbox --projection address:date" 2>&1 | tr -d '\r' | sed -n 's/^Row: [0-9]* address=\(.*\), date=.*/\1/p' | sort | uniq -c | sed 's/^/  inbox: /'
}

run_sms_device() {
  echo "==== SMS device"
  adb -s "$DEVICE" uninstall "$PKG" > /dev/null 2>&1 || true
  flutter build apk --debug --flavor devSms 2>&1 | tail -3
  apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
  echo "apk: ${apk:-none}"
  [ -n "$apk" ] || return 1
  adb -s "$DEVICE" install -r "$apk" || return 1
  for p in READ_SMS RECEIVE_SMS POST_NOTIFICATIONS; do
    adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" || echo "grant $p failed"
  done
  adb -s "$DEVICE" shell dumpsys package "$PKG" | grep -E "android.permission.(READ|RECEIVE)_SMS: granted" | sed 's/^ */  /'
  adb -s "$DEVICE" shell am force-stop "$PKG"
  adb -s "$DEVICE" root > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  echo "adb id: $(adb -s "$DEVICE" shell id -un | tr -d '\r')"
  echo "inbox before:"; inbox_rows
  # ---- historical: in the inbox before the app's first launch
  sms_hist HSBC "$HSBC_USD_H"
  sms_hist 'HSBC EG' "$HSBC_EGP_H"
  sms_hist CIB "$CIB_H"
  sms_hist NBE "$NBE_H"
  sms_hist HSBC "$NODIGIT"
  sms_hist 5550199 "$PERSONAL"
  sleep 5
  echo "inbox after:"; inbox_rows
  adb -s "$DEVICE" unroot > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  sleep 3
  adb -s "$DEVICE" shell am force-stop "$PKG"

  adb -s "$DEVICE" logcat -c || true
  timeout 1500 flutter test integration_test/sms_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    > "$OUT/sms-device-test.log" 2>&1 &
  tpid=$!
  # ---- live: when the test says the historical part is done
  for _ in $(seq 1 300); do
    grep -q "SMS_DEVICE READY_FOR_LIVE" "$OUT/sms-device-test.log" && break
    kill -0 "$tpid" 2> /dev/null || break
    sleep 3
  done
  if grep -q "SMS_DEVICE READY_FOR_LIVE" "$OUT/sms-device-test.log"; then
    echo "---- live"
    sms_live HSBC "$HSBC_USD_L"
    sms_live 'HSBC EG' "$HSBC_EGP_L"
    sms_live CIB "$CIB_L"
    sms_live NBE "$NBE_L"
    sms_live HSBC "$NODIGIT_L"
    sms_live 5550199 "$PERSONAL_L"
  else
    echo "the test never reached the live part"
  fi
  wait "$tpid"
  r=$?
  echo "sms device test exit: $r"
  grep -E "SMS_DEVICE|^[0-9:]+ [+-][0-9]+.*(SMS|Some tests|All tests)" "$OUT/sms-device-test.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then echo "---- test log tail (no message text is printed by the test)"; tail -60 "$OUT/sms-device-test.log" | cut -c1-220; fi
  adb -s "$DEVICE" logcat -d -b crash 2> /dev/null | tail -20
  adb -s "$DEVICE" logcat -d 2> /dev/null | grep -E "FATAL|ANR in|Process $PKG.*died" | cut -c1-200 | tail -10
  return "$r"
}

# ---- 0b. TEST-explorer4: Cash/InstaPay categories, a cash payment, the Add
# button (integration_test/sms_device_cash_test.dart), then two quick resumes of
# the app and a count of its posted notifications (no duplicates). Synthetic.
notif_count() { adb -s "$DEVICE" shell dumpsys notification --noredact 2> /dev/null | grep -c "pkg=$PKG" || true; }
run_cash_device() {
  echo "==== cash device"
  adb -s "$DEVICE" shell pm clear "$PKG" || true
  for p in READ_SMS RECEIVE_SMS POST_NOTIFICATIONS; do
    adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" || true
  done
  adb -s "$DEVICE" shell am force-stop "$PKG"
  adb -s "$DEVICE" root > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  sms_hist CIB 'Cash withdrawal of EGP 1000.00 with Card ending 1234 at ATM CAIRO FESTIVAL. Avl Bal EGP 5000.00'
  sms_hist CIB 'CIB: An instant transfer of EGP 500.00 was made from your account ending ****7316, ref e7a3c9f1 on 10-11-2026 22:32. For more info call 19666.'
  sleep 5
  adb -s "$DEVICE" unroot > /dev/null 2>&1 || true
  adb -s "$DEVICE" wait-for-device
  sleep 3
  adb -s "$DEVICE" shell am force-stop "$PKG"
  timeout 900 flutter test integration_test/sms_device_cash_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    > "$OUT/cash-device-test.log" 2>&1
  r=$?
  grep -E "CASH_DEVICE|Some tests|All tests" "$OUT/cash-device-test.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then tail -40 "$OUT/cash-device-test.log" | cut -c1-220; fi
  # Two quick resumes: Home, then the app again, twice; the number of the
  # app's posted notifications must not grow from the second resume to the third.
  adb -s "$DEVICE" shell am start -n "$PKG/app.zaghlol.MainActivity" > /dev/null 2>&1 || adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  sleep 6
  n0=$(notif_count)
  for i in 1 2; do
    adb -s "$DEVICE" shell input keyevent 3; sleep 1
    adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; sleep 2
  done
  sleep 5
  n1=$(notif_count)
  echo "CASH_DEVICE NOTIFICATIONS after launch=$n0 after two resumes=$n1"
  if [ "$n1" -gt "$n0" ]; then echo "CASH_DEVICE PROBLEM resuming twice posted new notifications"; r=1; fi
  adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-cash.png" || true
  return "$r"
}
cash_rc=0
run_cash_device 2>&1 | tee "$OUT/cash-device-script.log"
cash_rc=${PIPESTATUS[0]}
pull_files

sms_rc=0
run_sms_device 2>&1 | tee "$OUT/sms-device-script.log"
sms_rc=${PIPESTATUS[0]}
pull_files
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-sms.png" || true
if [ -n "${SMS_ONLY:-}" ]; then
  ls -la "$OUT/screens"
  [ "$cash_rc" -ne 0 ] && exit "$cash_rc"
  exit "$sms_rc"
fi


# ---- 1. device flows (English, empty database)
rc=0
if [ -z "${EXPLORER_ONLY:-}" ]; then
  perl -e 'alarm shift; exec @ARGV' 1800 \
    flutter test integration_test/device_flows_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    2>&1 | tee "$OUT/test.log"
  rc=${PIPESTATUS[0]}
  pull_files
  adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-screen.png" || true
fi

# ---- 2. explorer (Arabic, seeded database)
# A clean app: no leftovers from step 1. Notification and microphone
# permissions are granted up front so no system dialog covers the app.
adb -s "$DEVICE" shell pm clear "$PKG" || true
for p in POST_NOTIFICATIONS RECORD_AUDIO READ_SMS RECEIVE_SMS; do
  adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" 2>/dev/null || true
done
# If a tap sends the app to the background (a link, the share sheet, a system
# screen), press Back and bring it forward again.
(
  misses=0
  while true; do
    sleep 10
    if [ $((SECONDS % 60)) -lt 10 ]; then
      adb -s "$DEVICE" shell dumpsys meminfo "$PKG" 2>/dev/null | grep -E "TOTAL PSS|Graphics:|Java Heap:|Native Heap:" | tr -s ' ' | tr '\n' ';' | sed 's/^/MEM: /'; echo
    fi
    if adb -s "$DEVICE" shell pidof "$PKG" >/dev/null 2>&1; then
      # The app is installed by now: grant what its screens ask for, so no
      # system permission dialog covers it.
      for p in POST_NOTIFICATIONS RECORD_AUDIO READ_SMS RECEIVE_SMS; do
        adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" >/dev/null 2>&1 || true
      done
      focus=$(adb -s "$DEVICE" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)
      case "$focus" in
        # No focused window yet (the app is starting) or ours: all fine.
        *"$PKG"* | *"=null"*) misses=0 ;;
        *)
          misses=$((misses + 1))
          # Two looks in a row: another window really is in front.
          if [ "$misses" -ge 2 ]; then
            echo "KEEPER: app not focused ($focus)"
            adb -s "$DEVICE" shell input keyevent 4 || true
            sleep 1
            adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
            misses=0
          fi
          ;;
      esac
    fi
  done
) &
keeper=$!
rc2=0
# One app process per run. EXPLORER_PLAN: "base" (Arabic, light: the four tabs
# and the Add sheet as parts 0-4), "variants" (FU-245: English, dark, text
# scale 1.3, paywall, onboarding in both languages; two levels deep) or "all".
runs=""
case "${EXPLORER_PLAN:-all}" in base | all) runs="ar:0 ar:1 ar:2 ar:3 ar:4" ;; esac
case "${EXPLORER_PLAN:-all}" in variants | all) runs="$runs en:-1 dark:-1 scale:-1 paywall:-1 onboarding:-1 onboarding_en:-1" ;; esac
# TEST-explorer3: doubtful SMS on the Review screen, SMS diagnostics, all charts as a free user.
case "${EXPLORER_PLAN:-all}" in new | all) runs="$runs review:-1 charts:-1" ;; esac
for run in $runs; do
  mode=${run%%:*}
  part=${run##*:}
  echo "==== explorer mode $mode part $part"
  adb -s "$DEVICE" shell pm clear "$PKG" || true
  for p in POST_NOTIFICATIONS RECORD_AUDIO READ_SMS RECEIVE_SMS; do
    adb -s "$DEVICE" shell pm grant "$PKG" "android.permission.$p" 2>/dev/null || true
  done
  # Doubtful SMS (known bank, unfamiliar wording) for the Review screen: sent
  # through the emulator modem while the app is not running (the receiver
  # spools them; the test also runs the inbox scan). Synthetic.
  if [ "$mode" = review ]; then
    sms_emu NBE 'Dear customer, EGP 311.00 was debited from your account at CARREFOUR MAADI on 12/11/2026' || true
    sms_emu NBE 'Dear customer, EGP 322.00 was debited from your account at SPINNEYS ZAMALEK on 13/11/2026' || true
    sms_emu NBE 'Dear customer, EGP 333.00 was credited to your account on 14/11/2026' || true
    sms_emu NBE 'Dear customer, EGP 344.00 on your account *4567 at SOME SHOP 15/11/2026' || true
    sms_emu HSBC 'Dear customer, EGP 355.00 was debited from your card at KOSHARY TAHRIR on 16/11/2026' || true
    sleep 3
  fi
  # Text scale 1.3 is a system setting: set for the scale run only.
  if [ "$mode" = scale ]; then
    adb -s "$DEVICE" shell settings put system font_scale 1.3 || true
  else
    adb -s "$DEVICE" shell settings put system font_scale 1.0 || true
  fi
  perl -e 'alarm shift; exec @ARGV' 900 \
    flutter test integration_test/app_explorer_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    --dart-define=EXPLORER_PART=$part --dart-define=EXPLORER_MODE=$mode \
    2>&1 | tee "$OUT/explorer-$mode-p$part.log"
  r=${PIPESTATUS[0]}
  [ "$r" -ne 0 ] && rc2=$r
  pull_files
done
adb -s "$DEVICE" shell settings put system font_scale 1.0 || true
kill "$keeper" 2>/dev/null || true
kill "$keeper" 2>/dev/null || true
# Why did the app go away (if it did)? Crash, low-memory kill, ANR.
echo "---- logcat: crashes and kills ----"
adb -s "$DEVICE" logcat -d -b crash 2>/dev/null | tail -40 || true
adb -s "$DEVICE" logcat -d 2>/dev/null | grep -E "FATAL|am_proc_died|am_kill|lowmemorykiller|lmkd|ANR in|Process $PKG|has died|signal [0-9]+ \(SIG" | tail -30 || true
echo "---- end logcat ----"
pull_files
adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-explorer.png" || true

# Flutter's own log lines only (Dart errors, the tests' prints).
adb -s "$DEVICE" logcat -d -s flutter:V > "$OUT/flutter-logcat.txt" 2>/dev/null || true
ls -la "$OUT/screens"
if [ "$sms_rc" -ne 0 ]; then exit "$sms_rc"; fi
if [ "$rc" -ne 0 ]; then exit "$rc"; fi
exit "$rc2"
