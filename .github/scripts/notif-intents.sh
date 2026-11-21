#!/usr/bin/env bash
# T-193 AC5 (device-flows.yml, notif_only): forged `am start` intents to the
# exported MainActivity versus real notification taps, on the emulator.
#
#  - forged: the notification extras with no token, a wrong token, a mark-paid
#    route plus a cancel id; warm (app in front) and cold (process dead). The
#    app must do nothing: no `open` / `confirm` / `paid` probe line, the seeded
#    notification is not dismissed, nothing is paid. The non-exported trampoline
#    refuses a direct start from the shell.
#  - real: a tap on the app's own notification and its "Mark as paid" action,
#    warm and after process death; the confirmation dialog appears and
#    confirming pays the bill.
# Observed through the debug-only NOTIF_PROBE lines the app prints (a target
# type name or a boolean, never data) and the integration test
# integration_test/notification_intents_device_test.dart (database checks).
# Synthetic data only. Inputs: DEVICE, RUNNER_TEMP.
set -uo pipefail
: "${DEVICE:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/device-flows"
LOG="$OUT/notif-device-test.log"
REPORT="$OUT/screens/notif-intents-report.md"
mkdir -p "$OUT/screens"
cd "$(dirname "$0")/../../app"
A() { adb -s "$DEVICE" "$@"; }

ACT=app.zaghlol.action.NOTIFICATION_TAP
X_ROUTE=app.zaghlol.notification.route
X_CANCEL=app.zaghlol.notification.cancel_id
X_TOKEN=app.zaghlol.extra.NOTIFICATION_TOKEN
FAKE=00000000000000000000000000000000

fails=0
: > "$REPORT"
echo "# T-193 AC5 device run" >> "$REPORT"
echo >> "$REPORT"
result() { # PASS|FAIL name detail
  echo "- $1: $2 ($3)" | tee -a "$REPORT"
  [ "$1" = PASS ] || fails=$((fails + 1))
}

# The app's probe lines: while `flutter test` drives the app (warm part) they go
# to the test's stdout from line $MARK on; for the standalone cold launches they
# are in logcat.
MARK=
probes() {
  if [ -n "$MARK" ]; then
    tail -n +"$((MARK + 1))" "$LOG" | tr -d '\r' | sed -n 's/.*\(NOTIF_PROBE .*\)$/\1/p'
  else
    A logcat -d 2> /dev/null | tr -d '\r' | sed -n 's/.*\(NOTIF_PROBE .*\)$/\1/p'
  fi
}
mark_log() { MARK=$(wc -l < "$LOG"); }
sig() { A shell "run-as $PKG sh -c 'mkdir -p app_flutter/sig && touch app_flutter/sig/$1'" > /dev/null; }
present() { A shell dumpsys notification --noredact 2> /dev/null | tr -d '\r' | grep -c "|$PKG|$1|"; }
have_log() { grep -q "$1" "$LOG" 2> /dev/null; }
wait_log() { # pattern seconds
  for _ in $(seq 1 "$2"); do
    have_log "$1" && return 0
    # the test process is gone (it failed): stop waiting
    kill -0 "$tpid" 2> /dev/null || { have_log "$1" && return 0; return 1; }
    sleep 1
  done
  return 1
}
wait_probe() { # pattern seconds
  for _ in $(seq 1 "$2"); do probes | grep -q "$1" && return 0; sleep 1; done
  return 1
}
kill_app() { # process death without force-stop (force-stop cancels notifications)
  A shell input keyevent 3; sleep 1
  for _ in 1 2 3 4 5; do
    pid=$(A shell pidof "$PKG" | tr -d '\r')
    [ -z "$pid" ] && return 0
    A shell "run-as $PKG kill $pid" > /dev/null 2>&1 || A shell am kill "$PKG" > /dev/null 2>&1
    sleep 2
  done
  return 1
}
ui_tap() { # text: tap the first node whose text or description holds it
  for _ in 1 2 3 4 5 6; do
    A shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
    A pull /sdcard/ui.xml "$OUT/ui.xml" > /dev/null 2>&1
    xy=$(python3 -I - "$OUT/ui.xml" "$1" << 'PY'
import re, sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
want = sys.argv[2]
for n in root.iter("node"):
    if want in (n.get("text") or "") or want in (n.get("content-desc") or ""):
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
        if m:
            a, b, c, d = map(int, m.groups())
            print((a + c) // 2, (b + d) // 2)
            break
PY
)
    if [ -n "$xy" ]; then
      A shell input tap $xy
      return 0
    fi
    sleep 2
  done
  A exec-out screencap -p > "$OUT/screens/notif-ui-miss.png" 2> /dev/null || true
  return 1
}
# Two or more notifications of the app are shown as one collapsed group
# ("Zaghlol Dev", Expand): open it first so a tap lands on the notification.
shade() {
  A shell cmd statusbar expand-notifications; sleep 2
  A shell uiautomator dump /sdcard/ui3.xml > /dev/null 2>&1
  A pull /sdcard/ui3.xml "$OUT/ui3.xml" > /dev/null 2>&1
  xy=$(python3 -I - "$OUT/ui3.xml" << 'PY'
import re, sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
def center(n):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if not m:
        return None
    a, b, c, d = map(int, m.groups())
    return (a + c) // 2, (b + d) // 2
probe_y = None
for n in root.iter("node"):
    if "ZPROBE" in (n.get("text") or ""):
        xy = center(n)
        if xy:
            probe_y = xy[1]
            break
if probe_y is None:
    sys.exit(0)
best = None
for n in root.iter("node"):
    d = n.get("content-desc") or n.get("text") or ""
    xy = center(n)
    if d in ("Expand", "Collapse") and xy and xy[1] <= probe_y:
        if best is None or xy[1] > best[1][1]:
            best = (d, xy)
if best and best[0] == "Expand":
    print(best[1][0], best[1][1])
PY
)
  if [ -n "$xy" ]; then echo "  group is collapsed: expanding"; A shell input tap $xy; sleep 2; fi
}
# Diagnostics (synthetic data only): what is on screen, what is posted, what started.
ui_texts() {
  A shell uiautomator dump /sdcard/ui2.xml > /dev/null 2>&1
  A pull /sdcard/ui2.xml "$OUT/ui2.xml" > /dev/null 2>&1
  python3 -I - "$OUT/ui2.xml" << 'PY' | head -40 | sed 's/^/    ui: /'
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print("dump failed", type(e).__name__)
    sys.exit(0)
for n in root.iter("node"):
    t = (n.get("text") or n.get("content-desc") or "").strip()
    if t:
        print(t[:60])
PY
}
diag() {
  echo "  diag $1: posted ids: $(for i in 9101 9102 9103 9104; do echo -n "$i=$(present $i) "; done)"
  echo "  diag $1: probes: $(probes | tr '\n' ';')"
  A logcat -d 2> /dev/null | tr -d '\r' | grep -E "ActivityTaskManager.*(START|Displayed)|NotificationTap|FATAL EXCEPTION|Force stopping|Killing .*$PKG|Process $PKG.*(died|has died)" | grep -i "$PKG" | cut -c1-200 | tail -12 | sed "s/^/    log: /"
}

# ---- install
A uninstall "$PKG" > /dev/null 2>&1 || true
flutter build apk --debug --flavor devSms 2>&1 | tail -3
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
[ -n "$apk" ] || { echo "no apk"; exit 1; }
A install -r "$apk" || exit 1
A shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || echo "grant failed"
A shell am force-stop "$PKG"
A logcat -c || true

timeout 1500 flutter test integration_test/notification_intents_device_test.dart \
  --flavor devSms -d "$DEVICE" --no-uninstall --reporter expanded > "$LOG" 2>&1 &
tpid=$!

wait_log "NOTIF_DEVICE READY_WARM" 600 || { result FAIL "test reached READY_WARM" "never"; tail -40 "$LOG" | cut -c1-200; exit 1; }
BILL_W=$(sed -n 's/.*NOTIF_DEVICE BILL_IDS warm=\([^ ]*\) cold=\([^ ]*\) due=\(.*\)$/\1/p' "$LOG" | head -1 | tr -d '\r')
BILL_C=$(sed -n 's/.*NOTIF_DEVICE BILL_IDS warm=\([^ ]*\) cold=\([^ ]*\) due=\(.*\)$/\2/p' "$LOG" | head -1 | tr -d '\r')
DUE=$(sed -n 's/.*NOTIF_DEVICE BILL_IDS warm=\([^ ]*\) cold=\([^ ]*\) due=\(.*\)$/\3/p' "$LOG" | head -1 | tr -d '\r')
echo "bills: $BILL_W $BILL_C due $DUE"
sleep 3
echo "notifications posted: 9101=$(present 9101) 9103=$(present 9103)"
echo >> "$REPORT"; echo "## Warm (app in front)" >> "$REPORT"

# forged <label> <cold|warm> <cancel-id|-> <am start extras...>
forged() {
  local label=$1 mode=$2 cancel=$3
  shift 3
  if [ "$mode" = cold ]; then
    MARK=
    kill_app || echo "app still alive"
    A logcat -c || true
  else
    mark_log
  fi
  local out
  out=$(A shell am start -W -n "$PKG/app.zaghlol.MainActivity" "$@" 2>&1 | tr -d '\r' | tr '\n' ' ')
  if [ "$mode" = cold ]; then
    # debug JIT start on the emulator is slow: wait for the launch check, then
    # a few seconds more for any (unwanted) open/confirm/paid line
    wait_probe "launch route=" 90
    sleep 8
  else
    sleep 5
  fi
  local p bad ok=1 detail
  p=$(probes)
  bad=$(echo "$p" | grep -E "NOTIF_PROBE (open|confirm|paid)" | head -3 | tr '\n' ';')
  detail="started=$(echo "$out" | grep -c 'Status: ok') probes=$(echo "$p" | wc -l)"
  [ -z "$bad" ] || ok=0
  if [ "$mode" = cold ]; then echo "$p" | grep -q "launch route=false" || { ok=0; detail="$detail, app did not reach its launch check"; }; fi
  if [ "$cancel" != - ] && [ "$(present "$cancel")" -lt 1 ]; then ok=0; detail="$detail, notification $cancel was dismissed"; fi
  if [ "$ok" != 1 ] && [ "$mode" = cold ]; then
    echo "    am: ${out:0:300}"
    echo "    pid: $(A shell pidof "$PKG" | tr -d '\r')"
    A logcat -d 2> /dev/null | tr -d '\r' | grep -E "I flutter|AndroidRuntime|FATAL|Displayed|ANR" | cut -c1-200 | tail -8 | sed 's/^/    lc: /'
  fi
  [ "$ok" = 1 ] && result PASS "$mode forged: $label" "$detail" || result FAIL "$mode forged: $label" "$detail, saw: $bad"
}

# ---- warm forged intents
forged "no action, no token, backup route" warm 9103 --es $X_ROUTE /settings/backup
forged "action, no token, backup route" warm 9103 -a $ACT --es $X_ROUTE /settings/backup
forged "action, wrong token, backup route" warm 9103 -a $ACT --es $X_TOKEN $FAKE --es $X_ROUTE /settings/backup
forged "token without the action" warm 9103 --es $X_TOKEN $FAKE --es $X_ROUTE /settings/backup
forged "action, wrong token, mark-paid route, cancel id" warm 9103 -a $ACT --es $X_TOKEN $FAKE --es $X_ROUTE "/recurring/$BILL_W/paid/$DUE" --ei $X_CANCEL 9103
forged "action, no token, mark-paid route, cancel id" warm 9103 -a $ACT --es $X_ROUTE "/recurring/$BILL_W/paid/$DUE" --ei $X_CANCEL 9103
# the trampoline is not exported: the shell may not start it
mark_log
out=$(A shell am start -n "$PKG/app.zaghlol.platform.notifications.NotificationTapActivity" --es $X_ROUTE /settings/backup 2>&1 | tr -d '\r' | tr '\n' ' ')
sleep 3
if echo "$out" | grep -qiE "not exported|Permission Denial" && ! probes | grep -qE "open|confirm|paid"; then
  result PASS "forged start of the non-exported trampoline" "refused: ${out:0:90}"
else
  result FAIL "forged start of the non-exported trampoline" "${out:0:120}"
fi
sig forged_warm_done
wait_log "NOTIF_DEVICE FORGED_WARM_CHECKED" 60 && result PASS "warm: nothing paid, no dialog (test checked the database)" "in-process" || result FAIL "warm: nothing paid, no dialog" "test did not confirm"

# ---- warm real taps
echo >> "$REPORT"; echo "## Warm real taps" >> "$REPORT"
mark_log
shade
ui_texts
if ui_tap "ZPROBE tap warm" && wait_probe "open BackupTarget" 20; then
  result PASS "real tap on the notification (warm)" "open BackupTarget"
else
  result FAIL "real tap on the notification (warm)" "no open BackupTarget"
fi
[ "$(present 9101)" -eq 0 ] && result PASS "tapped notification was cancelled" "auto-cancel" || result FAIL "tapped notification was cancelled" "still posted"
diag "after warm tap"
sig real_tap_warm_done
sleep 2
mark_log
shade
ui_texts
if ui_tap "ZPROBE PAY WARM"; then
  sig real_action_warm_tapped
  wait_log "NOTIF_DEVICE PAID_WARM=true" 60 && result PASS "real Mark-as-paid action then confirm (warm)" "dialog, confirm, bill paid in the database" || result FAIL "real Mark-as-paid action then confirm (warm)" "see test log"
  probes | grep -q "confirm shown" && probes | grep -q "paid ok=true" || result FAIL "warm Mark-as-paid probes" "$(probes | tr '\n' ';')"
else
  sig real_action_warm_tapped
  result FAIL "real Mark-as-paid action (warm)" "action button not found in the shade"
fi
[ "$(present 9103)" -eq 0 ] && result PASS "action notification was cancelled" "cancel id" || result FAIL "action notification was cancelled" "still posted"

# ---- end of the in-process part. The test is left waiting: the process is killed
# below (killing it keeps the notifications; a finished `flutter test` force-stops
# the app and cancels them).
wait_log "NOTIF_DEVICE READY_COLD" 60 && result PASS "cold notifications posted" "READY_COLD" || result FAIL "cold notifications posted" "never"
sleep 2
if grep -q "NOTIF_DEVICE PROBLEM" "$LOG"; then
  result FAIL "in-process checks (database, dialog)" "$(grep 'NOTIF_DEVICE PROBLEM' "$LOG" | cut -c1-160 | tr '\n' ';')"
else
  result PASS "in-process checks (database, dialog)" "no PROBLEM line"
fi
grep -E "NOTIF_DEVICE|NOTIF_PROBE" "$LOG" | cut -c1-200
MARK=
# The tool first (SIGKILL: it must not run its cleanup, which force-stops the
# app and cancels its notifications), then the app's process.
pkill -9 -f flutter_tools 2> /dev/null; pkill -9 -f "flutter test" 2> /dev/null
kill -9 "$tpid" 2> /dev/null; wait "$tpid" 2> /dev/null
sleep 1
echo "notifications posted before the kill: 9102=$(present 9102) 9104=$(present 9104)"
kill_app || echo "app still alive"
echo "notifications posted after the test ended: 9102=$(present 9102) 9104=$(present 9104)"

# ---- cold forged intents (the process is dead before each)
echo >> "$REPORT"; echo "## Cold (process dead)" >> "$REPORT"
forged "no action, no token, backup route" cold 9104 --es $X_ROUTE /settings/backup
forged "action, no token, backup route" cold 9104 -a $ACT --es $X_ROUTE /settings/backup
forged "action, wrong token, backup route" cold 9104 -a $ACT --es $X_TOKEN $FAKE --es $X_ROUTE /settings/backup
forged "action, wrong token, mark-paid route, cancel id" cold 9104 -a $ACT --es $X_TOKEN $FAKE --es $X_ROUTE "/recurring/$BILL_C/paid/$DUE" --ei $X_CANCEL 9104
forged "action, no token, mark-paid route, cancel id" cold 9104 -a $ACT --es $X_ROUTE "/recurring/$BILL_C/paid/$DUE" --ei $X_CANCEL 9104
forged "plain launch (no extras)" cold 9104

# ---- cold real taps
echo >> "$REPORT"; echo "## Cold real taps" >> "$REPORT"
MARK=
kill_app || echo "app still alive"
A logcat -c || true
shade
ui_texts
if ui_tap "ZPROBE tap cold" && wait_probe "open BackupTarget" 60; then
  probes | grep -q "launch route=true" && result PASS "real tap on the notification (cold)" "launch route=true, open BackupTarget" || result FAIL "real tap (cold)" "no launch route"
else
  result FAIL "real tap on the notification (cold)" "no open BackupTarget: $(probes | tr '\n' ';')"
fi
kill_app || echo "app still alive"
A logcat -c || true
shade
if ui_tap "ZPROBE PAY COLD" && wait_probe "confirm shown" 60; then
  if probes | grep -q "paid ok"; then
    result FAIL "real Mark-as-paid action (cold)" "paid before the user confirmed"
  elif ui_tap "Mark paid" && wait_probe "paid ok=true" 30; then
    result PASS "real Mark-as-paid action then confirm (cold)" "confirm shown, nothing paid before the tap, paid ok=true"
  else
    A exec-out screencap -p > "$OUT/screens/notif-cold-dialog.png" 2> /dev/null || true
    result FAIL "real Mark-as-paid confirm (cold)" "dialog button not tapped or not paid: $(probes | tr '\n' ';')"
  fi
else
  A exec-out screencap -p > "$OUT/screens/notif-cold-action.png" 2> /dev/null || true
  result FAIL "real Mark-as-paid action (cold)" "no confirm dialog: $(probes | tr '\n' ';')"
fi
diag final
A exec-out screencap -p > "$OUT/screens/zz-final-notif.png" 2> /dev/null || true
A logcat -d -b crash 2> /dev/null | tail -20
echo >> "$REPORT"; echo "failed checks: $fails" | tee -a "$REPORT"
cat "$REPORT"
[ "$fails" -eq 0 ]
