#!/usr/bin/env bash
# T-348 (device-flows.yml job `e2e-ask-llm`): the online helper of Ask Zaghlol
# end to end in the real app on the Android emulator, once in Arabic and once
# in English, each on a clean app:
#   integration_test/ask_llm_device_test.dart  (E2E_LLM_LANG=ar | en)
# The backend is a FAKE that runs inside the test (support/fake_llm_backend.dart,
# an HttpServer on the device's loopback). The app is built with:
#   ZAGHLOL_API_BASE        http://127.0.0.1:<port>  (debug builds accept it)
#   ZAGHLOL_DEV_KEYS        the PUBLIC half of a throwaway signing key (s0000a)
#   ZAGHLOL_E2E_SIGN_D      its private scalar, for the fake only
#   ZAGHLOL_LLM_DEV_KEY     a throwaway device-proof key (debug-only dev proof,
#                           ask-llm.md section 5)
# All keys are made here at run time and go to a dart-define file outside the
# published output; nothing is committed and nothing is printed. The fixtures
# (ask-plan responses, sync config blocks) go in the same file because the
# device cannot read the repo.
# Synthetic data only. The script also fails when the test log or logcat holds
# a fixture merchant name or a question fragment (AC4: no question text in
# logs). Inputs: DEVICE (emulator-5554), RUNNER_TEMP.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
PORT=18090
OUT="$RUNNER_TEMP/device-flows"
mkdir -p "$OUT/screens"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/app"

KEYDIR=$(mktemp -d)
DEFINES="$KEYDIR/defines.json"
python3 -I - "$ROOT" "$DEFINES" "$PORT" << 'PY'
import base64, json, os, subprocess, sys, tempfile
root, out, port = sys.argv[1], sys.argv[2], sys.argv[3]
with tempfile.TemporaryDirectory() as t:
    pem = os.path.join(t, "k.pem")
    subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", pem], check=True)
    txt = subprocess.run(["openssl", "ec", "-in", pem, "-text", "-noout"], check=True, capture_output=True, text=True).stdout
priv, pub, cur = "", "", None
for line in txt.splitlines():
    s = line.strip()
    if s.startswith("priv:"):
        cur = "priv"
    elif s.startswith("pub:"):
        cur = "pub"
    elif s.startswith("ASN1") or s.startswith("NIST"):
        cur = None
    elif cur and all(c in "0123456789abcdef:" for c in s):
        if cur == "priv":
            priv += s.replace(":", "")
        else:
            pub += s.replace(":", "")
d = bytes.fromhex(priv)[-32:]
raw = bytes.fromhex(pub)
assert len(d) == 32 and len(raw) == 65 and raw[0] == 4
b64u = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
read = lambda p: open(os.path.join(root, p), encoding="utf-8").read()
json.dump({
    "ZAGHLOL_API_BASE": "http://127.0.0.1:" + port,
    "ZAGHLOL_DEV_KEYS": "s0000a:%s:%s" % (b64u(raw[1:33]), b64u(raw[33:65])),
    "ZAGHLOL_E2E_SIGN_D": b64u(d),
    "ZAGHLOL_LLM_DEV_KEY": base64.b64encode(os.urandom(48)).decode(),
    "E2E_LLM_PLAN_FIXTURE": read("backend/contracts/fixtures/ask-plan-responses-v1.json"),
    "E2E_LLM_CONFIG_FIXTURE": read("app/test/fixtures/llm/sync-config-provider-v1.json"),
}, open(out, "w"))
PY
[ -s "$DEFINES" ] || { echo "could not make the run keys"; exit 1; }

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

run_lang() { # ar | en
  echo "==== ask-llm $1"
  fresh_app
  adb -s "$DEVICE" logcat -c || true
  timeout 900 flutter test integration_test/ask_llm_device_test.dart \
    --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded \
    --dart-define-from-file="$DEFINES" --dart-define=E2E_LLM_LANG="$1" \
    > "$OUT/ask-llm-$1.log" 2>&1
  local r=$?
  grep -E "E2ELLM-[a-z]+ |Some tests|All tests" "$OUT/ask-llm-$1.log" | cut -c1-240
  if [ "$r" -ne 0 ]; then
    echo "---- test log tail"
    grep -m1 -B2 -A28 -E "EXCEPTION CAUGHT|Test failed|Expected:" "$OUT/ask-llm-$1.log" | cut -c1-220
    tail -30 "$OUT/ask-llm-$1.log" | cut -c1-220
  fi
  adb -s "$DEVICE" logcat -d -s flutter:V > "$OUT/flutter-logcat-$1.txt" 2> /dev/null || true
  pull_files
  adb -s "$DEVICE" exec-out screencap -p > "$OUT/screens/zz-final-ask-llm-$1.png" || true
  return "$r"
}

flutter devices
echo "==== build and install"
adb -s "$DEVICE" uninstall "$PKG" > /dev/null 2>&1 || true
flutter build apk --debug --flavor devSms --dart-define-from-file="$DEFINES" > "$OUT/build.log" 2>&1
tail -3 "$OUT/build.log" | cut -c1-220
grep -m1 -B3 -A14 -E "What went wrong|FAILURE:|Error:|error:" "$OUT/build.log" | cut -c1-220
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
echo "apk: ${apk:-none}"
[ -n "$apk" ] || exit 1
adb -s "$DEVICE" install -r "$apk" || exit 1

want() { [ -z "${ASK_LLM_LANGS:-}" ] || [[ " ${ASK_LLM_LANGS} " == *" $1 "* ]]; }
rar=0 ren=0
want ar && { run_lang ar; rar=$?; }
want en && { run_lang en; ren=$?; }

# AC4: no question text and no fixture merchant name in any log.
leak=0
if grep -qE "Palm Garden|Blue Door|Sun Pharmacy|aside every month|على جنب|got my money" "$OUT"/ask-llm-*.log "$OUT"/flutter-logcat-*.txt 2> /dev/null; then
  echo "E2E LOGS PROBLEM question text or a fixture merchant name is in a log (file names only):"
  grep -lE "Palm Garden|Blue Door|Sun Pharmacy|aside every month|على جنب|got my money" "$OUT"/ask-llm-*.log "$OUT"/flutter-logcat-*.txt
  leak=1
fi
rm -rf "$KEYDIR"
echo "E2E RESULT ar=$rar en=$ren logs=$leak"
ls -la "$OUT/screens"
[ "$rar" -eq 0 ] && [ "$ren" -eq 0 ] && [ "$leak" -eq 0 ]
