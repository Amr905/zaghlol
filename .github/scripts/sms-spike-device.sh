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
# Instrumented suites (T-039 design note section 11): after the spike, the
# devSms debug app + test APK replace the profile build and run the native
# instrumented tests on the same emulator: spool (fatal), guard (T-038, fatal;
# skips allowed only by name), share (T-060, a warning until its owner makes it green),
# then the two-phase kill test (AC1: a write phase halted between fsync and
# rename of a 21st entry, a read phase in a new process).
# T-041: the receiver feeds the production worker, drain loop and headless
# engine (src/main); the metrics come from the devSms IngestTrace. AC1: after
# the default cell (app killed before each SMS) the spool is empty. AC2: a
# foreground cell (app open, UI engine drains on onSpoolChanged): p95 of
# receive → commit for `foreground` rows <= 2000 ms. A burst of 40 SMS with
# the app killed, the app launched during the headless drain: every entry
# committed once (40 new rows, spool empty). Instrumented: the headless
# plugin allowlist (fatal) and the #6 Cipher.init probe (recorded).
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
# T-041 AC1: the killed app's spool was drained by the worker.
for _ in $(seq 1 15); do [ "$(spool_count)" = 0 ] && break; sleep 1; done
[ "$(spool_count)" = 0 ] || fail "AC1: spool not empty after the default cell ($(spool_count) entries)"
echo "AC1: spool empty after $N SMS with the app killed"
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

# T-041 AC2: foreground. The app is open (UI engine attached); no kill.
sh_ am start -W -n "$PKG/app.zaghlol.MainActivity" > /dev/null
sleep 3
for i in $(seq 1 "$N"); do
  seq_no=$((seq_no + 1))
  before=$(rows)
  A emu sms send "$SENDER" "spike: you paid EGP $seq_no.00 at SYNTH SHOP $seq_no card *4321" > /dev/null
  for _ in $(seq 1 30); do
    after=$(rows)
    [ "$after" -gt "$before" ] && break
    sleep 1
  done
  sh_ dumpsys activity broadcasts history > "$BH/$(printf %04d "$seq_no").txt" 2>/dev/null || true
  echo "foreground #$i: rows $before -> $after"
done
runas cat no_backup/spike/metrics.csv > "$OUT/metrics-fg.csv"
# p95 (nearest rank) of t8_commit (else t9_acked) over the foreground rows.
FG_P95=$(awk -F, 'NR==1{for(i=1;i<=NF;i++)h[$i]=i; next} $h["path"]=="foreground"{v=$h["t8_commit"]; if(v=="")v=$h["t9_acked"]; if(v!="")print v}' "$OUT/metrics-fg.csv" \
  | sort -n | awk '{a[NR]=$1} END{if(NR==0){print "none"; exit} r=int((95*NR+99)/100); print a[r]}')
rm -f "$OUT/metrics-fg.csv"
echo "AC2: foreground receive -> commit p95 = ${FG_P95} ms"
[ "$FG_P95" != none ] || fail "AC2: no foreground row was recorded"
[ "$FG_P95" -le 2000 ] || fail "AC2: foreground p95 ${FG_P95} ms > 2000 ms"

# T-041: UI attach mid-drain. A burst with the app killed; the app is launched
# while the headless engine drains; nothing lost or doubled.
kill_app
before=$(rows)
for i in $(seq 1 40); do
  seq_no=$((seq_no + 1))
  A emu sms send "$SENDER" "spike: you paid EGP $seq_no.00 at SYNTH SHOP $seq_no card *4321" > /dev/null
done
for _ in $(seq 1 60); do [ "$(rows)" -gt "$before" ] && break; sleep 0.5; done
sh_ am start -W -n "$PKG/app.zaghlol.MainActivity" > /dev/null
for _ in $(seq 1 120); do
  [ "$(rows)" -ge $((before + 40)) ] && [ "$(spool_count)" = 0 ] && break
  sleep 1
done
burst=$(( $(rows) - before ))
echo "burst with UI attach mid-drain: $burst of 40 committed, spool $(spool_count)"
[ "$burst" = 40 ] || fail "burst: $burst rows for 40 SMS (lost or doubled)"
[ "$(spool_count)" = 0 ] || fail "burst: spool not empty after the UI took over"

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

# ---- Instrumented tests (T-039) --------------------------------------------
RUNNER="$PKG.test/androidx.test.runner.AndroidJUnitRunner"
(cd android && ./gradlew --no-daemon :app:assembleDevSmsDebug :app:assembleDevSmsDebugAndroidTest) > "$OUT/it-build.log" 2>&1 \
  || { tail -n 60 "$OUT/it-build.log"; fail "instrumented test build failed"; }
APP_APK=$(find build/app/outputs/apk/devSms/debug -name '*.apk' 2>/dev/null | head -n 1)
TEST_APK=$(find build/app/outputs/apk/androidTest/devSms/debug -name '*.apk' 2>/dev/null | head -n 1)
[ -n "$APP_APK" ] && [ -n "$TEST_APK" ] || { find build/app/outputs -name '*.apk'; fail "instrumented APKs not found"; }
A uninstall "$PKG" > /dev/null 2>&1 || true  # the profile build's signature may differ
A install -r -t -g "$APP_APK" > /dev/null
A install -r -t "$TEST_APK" > /dev/null
# instr <name> <am instrument args...>: output to $OUT/it-<name>.txt; returns 0 only on "OK (n tests)".
# Raw mode (-r): only it prints the per-test status codes (-4 = assumption
# failure, counted inside "OK (n tests)") and the tests' own status values
# (guard.timing); the final stream with "OK (n tests)" is printed as well.
instr() {
  local name=$1; shift
  sh_ am instrument -w -r "$@" "$RUNNER" > "$OUT/it-$name.txt" 2>&1 || true
  tr -d '\r' < "$OUT/it-$name.txt" | grep -E "^(OK|FAILURES|Tests run|INSTRUMENTATION_RESULT: shortMsg|[0-9]+\))" | head -n 20 || true
  tr -d '\r' < "$OUT/it-$name.txt" | grep -qE "^OK \([0-9]+ tests?\)" && return 0
  # Failure causes into the log (the artifact is not always reachable); test data is synthetic.
  tr -d '\r' < "$OUT/it-$name.txt" | awk '/^INSTRUMENTATION_STATUS: stack=/{n=6} n>0{print "  " substr($0,1,300); n--}' | head -n 60 || true
  return 1
}
KILL=app.zaghlol.platform.spool.SpoolKillRecoveryTest
# skipped <name>: assumption failures (am instrument counts them inside "OK (n tests)").
skipped() { tr -d '\r' < "$OUT/it-$1.txt" | grep -c "^INSTRUMENTATION_STATUS_CODE: -4" || true; }
# skipped_names <name>: the method names of those skips, one per line (a status block ends at its code line).
skipped_names() { tr -d '\r' < "$OUT/it-$1.txt" | awk '/^INSTRUMENTATION_STATUS: test=/{t=substr($0,30)} /^INSTRUMENTATION_STATUS_CODE: -4$/{print t}' | sort -u; }
# Guard skips allowed by name: bundledBaseLoads until T-036 bundles guard_base.json.
GUARD_ALLOWED_SKIPS="bundledBaseLoads"
instr spool -e package app.zaghlol.platform.spool -e notClass "$KILL" || fail "spool instrumented tests failed (it-spool.txt)"
tr -d '\r' < "$OUT/it-spool.txt" | grep -qE "^OK \(0 tests\)" && fail "no spool instrumented test ran"
echo "spool instrumented: $(skipped spool) skipped"
[ "$(skipped spool)" = 0 ] || fail "a spool instrumented test was skipped by an assumption (it-spool.txt)"
INIT_PROBE=$(tr -d '\r' < "$OUT/it-spool.txt" | sed -n 's/^INSTRUMENTATION_STATUS: spool\.initProbe=//p' | head -n 1)
echo "spool init probe (#6): ${INIT_PROBE:-none}"
# T-041: the headless engine's plugin allowlist (fatal).
instr ingest -e package app.zaghlol.platform.ingest || fail "ingest instrumented tests failed (it-ingest.txt)"
tr -d '\r' < "$OUT/it-ingest.txt" | grep -qE "No tests found|^OK \(0 tests\)" && fail "no ingest instrumented test ran"
[ "$(skipped ingest)" = 0 ] || fail "an ingest instrumented test was skipped"
# Guard (T-038, security M-1): fatal; at least one test must run and every skip must be allowed by name.
instr guard -e package app.zaghlol.platform.guard && guard_ok=1 || guard_ok=0
GUARD_TIMING=$(tr -d '\r' < "$OUT/it-guard.txt" | sed -n 's/^INSTRUMENTATION_STATUS: guard\.timing=//p' | head -n 1)
echo "guard timing: ${GUARD_TIMING:-none}"
[ "$guard_ok" = 1 ] || fail "guard instrumented tests failed (it-guard.txt)"
tr -d '\r' < "$OUT/it-guard.txt" | grep -qE "No tests found|^OK \(0 tests\)" && fail "no guard instrumented test ran"
guard_skips=$(skipped_names guard | tr '\n' ' ')
echo "guard instrumented: $(skipped guard) skipped ${guard_skips:+($guard_skips)}"
for t in $guard_skips; do
  case " $GUARD_ALLOWED_SKIPS " in *" $t "*) ;; *) fail "guard instrumented test $t was skipped by an assumption (it-guard.txt)" ;; esac
done
[ -n "$GUARD_TIMING" ] || fail "the guard timing test reported no guard.timing value"
instr share -e class app.zaghlol.platform.share.ShareIntakeInstrumentedTest || echo "::warning::T-060 ShareIntakeInstrumentedTest failed on API $API (it-share.txt); reported to the Lead, not a T-039 gate"
# AC1 for real: phase write halts the process between fsync and rename of entry 21.
instr kill-write -e class "$KILL#phaseWrite" -e spoolPhase write && fail "the write phase finished instead of halting"
runas ls no_backup/spool-it-kill > "$OUT/it-kill-ls.txt" 2>&1 || true
bins=$(grep -cE '^[0-9A-Z]{26}\.bin$' "$OUT/it-kill-ls.txt" || true)
tmps=$(grep -cE '^[0-9A-Z]{26}\.bin\.tmp$' "$OUT/it-kill-ls.txt" || true)
echo "after halt: $bins entries, $tmps tmp"
[ "$bins" = 20 ] && [ "$tmps" = 1 ] || fail "after the halt expected 20 entries and 1 tmp, found $bins and $tmps"
instr kill-read -e class "$KILL#phaseRead" -e spoolPhase read || fail "the read phase after the halt failed (it-kill-read.txt)"
[ "$(skipped kill-read)" = 0 ] || fail "the read phase was skipped (spoolPhase argument not received)"
# ---- Inbox reader (T-042) ----------------------------------------------------
# Real provider: 30 messages from $SENDER (#10 a 3-part one, #20 an OTP, #7
# with the canary) and 10 from 5550199, `inboxMid` taken between #15 and #16;
# the test reads with page size 7 (only $SENDER's non-OTP rows), then AC2
# (10k × 4,000 chars) and, after `pm revoke`, PERMISSION_DENIED. The app's
# logcat lines must not carry the canary.
INBOX=app.zaghlol.platform.capture.inbox.InboxReaderInstrumentedTest
LONG_TAIL="this synthetic statement line is repeated to make one message span three parts"
inbox_body() {
  case "$1" in
    7) echo "inbox-it 7 paid EGP 7.00 at $CANARY SHOP card *4321" ;;
    10) echo "inbox-it 10 paid EGP 10.00 at SYNTH SHOP card *4321 $LONG_TAIL $LONG_TAIL $LONG_TAIL $LONG_TAIL $LONG_TAIL END-OF-LONG" ;;
    20) echo "inbox-it 20 your OTP is 123456" ;;
    *) echo "inbox-it $1 paid EGP $1.00 at SYNTH SHOP card *4321" ;;
  esac
}
sh_ pm grant "$PKG" android.permission.READ_SMS
A logcat -c || true
sleep 2
INBOX_SINCE=$(( $(sh_ date +%s | tr -d '\r') * 1000 ))
sleep 2
for i in $(seq 1 30); do
  A emu sms send "$SENDER" "$(inbox_body "$i")" > /dev/null
  if [ $((i % 3)) = 0 ]; then A emu sms send 5550199 "inbox-it friend $i $CANARY EGP 5.00" > /dev/null; fi
  if [ "$i" = 15 ]; then
    sleep 8
    INBOX_MID=$(( $(sh_ date +%s | tr -d '\r') * 1000 ))
    sleep 2
  fi
  sleep 1
done
instr inbox -e class "$INBOX" -e inboxPhase seeded -e inboxSince "$INBOX_SINCE" -e inboxMid "$INBOX_MID" \
  || fail "inbox instrumented tests failed (it-inbox.txt)"
[ "$(skipped inbox)" = 1 ] || fail "expected exactly the denied-phase test skipped in the seeded run (it-inbox.txt)"
sh_ pm revoke "$PKG" android.permission.READ_SMS
instr inbox-denied -e class "$INBOX#revokedPermissionIsPermissionDenied" -e inboxPhase denied \
  || fail "inbox permission-denied test failed (it-inbox-denied.txt)"
[ "$(skipped inbox-denied)" = 0 ] || fail "the inbox denied phase was skipped"
sh_ pm grant "$PKG" android.permission.READ_SMS
sh_ pm list packages -U > "$OUT/pkg.txt"
UID_N=$(grep -E "^package:$PKG uid:" "$OUT/pkg.txt" | grep -oE 'uid:[0-9]+' | cut -d: -f2 || true)
if [ -z "$UID_N" ]; then
  sh_ dumpsys package "$PKG" > "$OUT/pkg.txt"
  UID_N=$(grep -oE '(userId|appId)=[0-9]+' "$OUT/pkg.txt" | cut -d= -f2 | sort -u | tail -n 1 || true)
fi
[ -n "$UID_N" ] || fail "could not read the app uid (inbox step)"
APP_NAME="u0_a$((UID_N - 10000))"
A logcat -d -v uid > "$OUT/logcat-uid.txt" || true
inbox_own=$(grep -E "(^|[[:space:]])($UID_N|$APP_NAME)[[:space:]]" "$OUT/logcat-uid.txt" | grep -c . || true)
inbox_hits=$(grep -F "$CANARY" "$OUT/logcat-uid.txt" | grep -E "(^|[[:space:]])($UID_N|$APP_NAME)[[:space:]]" | grep -c . || true)
echo "inbox canary: app log lines $inbox_hits of $inbox_own app lines"
[ "$inbox_own" -gt 0 ] || fail "the logcat uid filter matched no app line after the inbox tests; canary scan would be vacuous"
[ "$inbox_hits" = 0 ] || fail "the canary appeared in the app's logcat during the inbox tests"
rm -f "$OUT/logcat-uid.txt" "$OUT/pkg.txt"
{
  echo
  echo "### Instrumented (T-039), API $API"
  for n in spool guard share kill-read ingest inbox inbox-denied; do
    echo "- $n: $(tr -d '\r' < "$OUT/it-$n.txt" | grep -E "^(OK|FAILURES|Tests run)" | tr '\n' ' ')"
  done
  echo "- kill-write: halted with $bins entries + $tmps tmp on disk"
  echo "- guard skipped: $(skipped guard) ${guard_skips:+($guard_skips; allowed until T-036)}"
  echo "- guard timing: $GUARD_TIMING"
  echo "- spool init probe (#6): ${INIT_PROBE:-none}"
  echo "- foreground receive -> commit p95 (AC2): ${FG_P95} ms"
  echo "- burst with UI attach mid-drain: $burst of 40"
} >> "$OUT/report.md"
