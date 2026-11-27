#!/usr/bin/env bash
# T-363 (device-flows.yml job `e2e-llm-cat`): the automatic category (LLM-
# CATEGORISE) on the Android emulator with the real app and a fake backend that
# runs inside the test (integration_test/e2e_llm_cat_device_test.dart), once in
# Arabic and once in English, each on a clean app.
#
# The test prints `E2ELCAT SEND <phase>`; this script then sends that phase's
# synthetic SMS through the emulator modem. Logs hold phase names, sender ids
# and counts, never a message body, amount or shop name.
#
# Keys: nothing is committed. At run time the script generates (a) a P-256 dev
# signing key whose public half the app pins through ZAGHLOL_DEV_KEYS (debug
# builds only) and whose private scalar the test uses to sign the fake sync
# answers, and (b) the HMAC dev proof key of the Fake attestation mode
# (ask-llm.md 5; ZAGHLOL_LLM_DEV_KEY, debug builds only). They exist only in
# this process and are masked in the GitHub log.
# Inputs: DEVICE, RUNNER_TEMP. E2E_LCAT_LANGS (default "ar en") limits a re-run.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
PORT=18480
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"

b64u() { perl -ne 'chomp; print pack("H*", $_)' | base64 -w0 | tr '+/' '-_' | tr -d '='; }

keydir=$(mktemp -d)
openssl ecparam -name prime256v1 -genkey -noout -out "$keydir/k.pem" || exit 1
txt=$(openssl ec -in "$keydir/k.pem" -text -noout 2> /dev/null)
priv=$(echo "$txt" | awk '/^priv:/{f=1;next}/^pub:/{f=0}f' | tr -d ' :\n')
pub=$(echo "$txt" | awk '/^pub:/{f=1;next}/^ASN1|^NIST/{f=0}f' | tr -d ' :\n')
rm -rf "$keydir"
priv=${priv: -64}
if [ "${#priv}" -ne 64 ] || [ "${#pub}" -ne 130 ]; then echo "key generation failed"; exit 1; fi
SIGN_D=$(echo "$priv" | b64u)
PUB_X=$(echo "${pub:2:64}" | b64u)
PUB_Y=$(echo "${pub:66:64}" | b64u)
LLM_KEY=$(openssl rand -base64 32)
for v in "$SIGN_D" "$PUB_X" "$PUB_Y" "$LLM_KEY"; do echo "::add-mask::$v"; done
# B98-m5: the leak checks below match these as fixed strings; an empty one would match every line, or hide a leak.
if [ -z "$SIGN_D" ] || [ -z "$LLM_KEY" ]; then echo "::error::e2e-llm-cat: signing key or LLM key is empty; the key-leak check cannot run"; exit 1; fi
echo "dev keys generated (masked)"

pull_files() {
  for f in $(adb -s "$DEVICE" shell run-as "$PKG" ls app_flutter/ci_screens 2> /dev/null | tr -d '\r'); do
    case "$f" in *.png | *.md) ;; *) continue ;; esac
    adb -s "$DEVICE" exec-out run-as "$PKG" cat "app_flutter/ci_screens/$f" > "$OUT/screens/$f" || true
  done
}

sms_live() { # sender body
  local out
  out=$(adb -s "$DEVICE" emu sms send "$1" "$2" < /dev/null 2>&1 | tr -d '\r' | tr '\n' ' ')
  case "$out" in OK*) echo "  sent: $1"; return 0 ;; *) echo "  REFUSED: $1"; return 1 ;; esac
}

send_phase() { # phase: synthetic SMS only (card purchases of unknown shops,
  # a wallet payment to a person-like name)
  echo "---- phase $1"
  case "$1" in
    p1)
      sms_live NBE 'NBE: Purchase of EGP 310.00 from NBE Visa **4567 at QUIBLEXO. Balance EGP 7000.00'
      sleep 4
      sms_live NBE 'NBE: Purchase of EGP 290.00 from NBE Visa **4567 at ZYMOTRON. Balance EGP 6710.00'
      sleep 4
      sms_live NBE 'NBE: Purchase of EGP 120.00 from NBE Visa **4567 at BRAVEXO. Balance EGP 6590.00'
      sleep 4
      sms_live OrangeCash 'Orange Cash: You paid EGP 180.00 at MOHAMED HASSAN. Avl Bal: EGP 820.00'
      ;;
    p2)
      sms_live NBE 'NBE: Purchase of EGP 75.00 from NBE Visa **4567 at DELTRAXA. Balance EGP 6515.00'
      ;;
    *) echo "unknown phase $1" ;;
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

run_one() { # lang
  local lang=$1 log="$OUT/llm-cat-$1-test.log" r tpid done_=" "
  echo "==== e2e-llm-cat $lang"
  fresh_app
  adb -s "$DEVICE" logcat -c || true
  timeout 1100 flutter test integration_test/e2e_llm_cat_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    --dart-define="ZAGHLOL_API_BASE=http://127.0.0.1:$PORT" \
    --dart-define="ZAGHLOL_DEV_KEYS=s0000c:$PUB_X:$PUB_Y" \
    --dart-define="ZAGHLOL_LLM_DEV_KEY=$LLM_KEY" \
    --dart-define="E2E_FAKE_SIGN_D=$SIGN_D" \
    --dart-define="E2E_LCAT_LANG=$lang" \
    > "$log" 2>&1 &
  tpid=$!
  while kill -0 "$tpid" 2> /dev/null; do
    for p in $(grep -o 'E2ELCAT SEND [a-z0-9_]*' "$log" | awk '{print $3}' | sort -u); do
      case "$done_" in *" $p "*) continue ;; esac
      done_="$done_$p "
      send_phase "$p"
    done
    sleep 2
  done
  wait "$tpid"
  r=$?
  echo "e2e-llm-cat $lang exit: $r"
  grep -E "E2ELCAT|Some tests|All tests" "$log" | cut -c1-240
  if [ "$r" -ne 0 ]; then
    echo "---- $lang first exception"
    grep -m1 -B2 -A14 -E "EXCEPTION CAUGHT|Test failed|Expected:" "$log" | cut -c1-200
    echo "---- $lang log tail (no message text is printed)"
    tail -30 "$log" | cut -c1-220
  fi
  adb -s "$DEVICE" logcat -d -b crash 2> /dev/null | tail -10
  # The logs must not hold a key, a message body or a shop name.
  if grep -qF -e "$SIGN_D" -e "$LLM_KEY" "$log" || grep -qE "QUIBLEXO|ZYMOTRON|BRAVEXO|DELTRAXA|MOHAMED" "$log"; then
    echo "E2ELCAT PROBLEM the log holds a key, a shop name or a payee: matches per needle (key, llm key, names)"
    grep -c -F -e "$SIGN_D" "$log"; grep -c -F -e "$LLM_KEY" "$log"; grep -c -E "QUIBLEXO|ZYMOTRON|BRAVEXO|DELTRAXA|MOHAMED" "$log"
    grep -E "QUIBLEXO|ZYMOTRON|BRAVEXO|DELTRAXA|MOHAMED" "$log" | sed -E 's/(QUIBLEXO|ZYMOTRON|BRAVEXO|DELTRAXA|MOHAMED)/#/g' | cut -c1-160 | head -3
    r=1
  fi
  pull_files
  adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-llm-cat-$lang.png" || true
  return "$r"
}

flutter devices
adb -s "$DEVICE" shell cmd bluetooth_manager disable > /dev/null 2>&1 || true
adb -s "$DEVICE" shell svc bluetooth disable > /dev/null 2>&1 || true
# one build + install (the grants in fresh_app need the app installed)
flutter build apk --debug --flavor devSms 2>&1 | tail -3
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
echo "apk: ${apk:-none}"
[ -n "$apk" ] || exit 1
adb -s "$DEVICE" install -r "$apk" || exit 1

rc=0
for lang in ${E2E_LCAT_LANGS:-ar en}; do
  run_one "$lang" 2>&1 | tee "$OUT/llm-cat-$lang-script.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
done
adb -s "$DEVICE" logcat -d -s flutter:V > "$OUT/flutter-logcat.txt" 2> /dev/null || true
if grep -qF -e "$SIGN_D" -e "$LLM_KEY" "$OUT/flutter-logcat.txt" 2> /dev/null || grep -qE "QUIBLEXO|ZYMOTRON|BRAVEXO|DELTRAXA|MOHAMED" "$OUT/flutter-logcat.txt" 2> /dev/null; then
  echo "E2ELCAT PROBLEM the device log holds a key, a shop name or a payee"
  rc=1
fi
ls -la "$OUT/screens"
echo "E2E-LLM-CAT rc=$rc"
exit "$rc"
