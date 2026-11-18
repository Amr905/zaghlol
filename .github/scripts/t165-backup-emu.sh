#!/usr/bin/env bash
# Part 4 builds a NON-debuggable stagingSms release APK (Android 12+ lets adb back up
# debuggable apps, so the debug rows are not release evidence).
# T-165 on an Android emulator (t165-backup-emu.yml): FR-SEC-05 as far as an
# emulator can show it. devSms debug build (debuggable, so run-as works),
# canary files planted in files/, databases/, shared_prefs/, then Auto Backup
# via the local transport, adb backup, and (API 31+) the device-to-device
# transport. Nothing may leave the app. Synthetic canaries only.
# Env: DEVICE, API, RUNNER_TEMP. Lines starting T165 are the evidence.
set -uo pipefail
: "${DEVICE:?}" "${API:?}" "${RUNNER_TEMP:?}"
PKG=app.zaghlol.dev
OUT="$RUNNER_TEMP/t165"
mkdir -p "$OUT"
A() { adb -s "$DEVICE" "$@"; }
S() { A shell "$@" < /dev/null | tr -d '\r'; }
fails=0
res() { echo "T165 api=$API $1: $2 ($3)"; [ "$2" != FAIL ] || fails=$((fails + 1)); }
cd "$(dirname "$0")/../../app"

flutter build apk --debug --flavor devSms 2>&1 | tail -3
apk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i devsms | head -1)
[ -n "$apk" ] || { echo "T165 no apk"; exit 1; }
A install -r -g "$apk" > /dev/null || exit 1
S am start -W -n "$PKG/app.zaghlol.MainActivity" > /dev/null
sleep 20

echo "---- static: what the installed package says"
S dumpsys package "$PKG" | grep -iE "ALLOW_BACKUP|hasFragileUserData|FRAGILE|dataExtractionRules" | sed 's/^ */  /'
# pkgFlags=[ NAMES ] is the readable line; a bare flags=0x0 elsewhere in the dump is not.
flags=$(S dumpsys package "$PKG" | grep -m1 -E "^ *pkgFlags=")
[ -n "$flags" ] || flags=$(S dumpsys package "$PKG" | grep -m1 -E "^ *flags=")
echo "  $flags"
# The flag list must be readable (devSms is debuggable, so DEBUGGABLE has to be
# in it). An empty or unparsable line (e.g. flags=0x0) proves nothing: UNKNOWN.
case "$flags" in
  *ALLOW_BACKUP*) res manifest FAIL "ALLOW_BACKUP flag present: $flags" ;;
  *"["*DEBUGGABLE*"]"*) res manifest PASS "flags list read (DEBUGGABLE seen), no ALLOW_BACKUP: $flags" ;;
  *) res manifest UNKNOWN "package flags not readable, no evidence: $flags" ;;
esac

# adb shell joins its arguments, so the remote command is one quoted string.
rs() { A shell "run-as $PKG sh -c '$1'" < /dev/null 2>&1 | tr -d '\r'; }
plant() { rs 'mkdir -p files databases shared_prefs; echo T165 > files/t165-canary.txt; echo T165 > databases/t165-canary.db; echo X > shared_prefs/t165-canary.xml'; }
canaries() { local c=0 f; for f in files/t165-canary.txt databases/t165-canary.db shared_prefs/t165-canary.xml; do [ "$(rs "test -f $f && echo yes")" = yes ] && c=$((c + 1)); done; echo "$c"; }
plant
n=$(canaries); echo "canaries planted: $n/3"
[ "$n" = 3 ] || { res plant FAIL "canaries not planted ($n/3)"; exit 1; }
echo "data files before (names only):"; rs "ls files databases shared_prefs no_backup" | sed 's/^/  /'

echo "---- 1. Auto Backup (local transport)"
S bmgr enable true
S bmgr transport com.android.localtransport/.LocalTransport
S settings put secure backup_local_transport_parameters 'is_encrypted=true'
out=$(S bmgr backupnow "$PKG" 2>&1); echo "$out" | sed 's/^/  backupnow: /' | head -8
S dumpsys backup | grep -i -B1 -A3 zaghlol | head -20 | sed 's/^/  dumpsys: /'
if echo "$out" | grep -qiE "not allowed|not eligible|is not currently|Package .* not (found|eligible)|Backup is not allowed"; then
  res auto-backup PASS "backupnow refused"
elif echo "$out" | grep -qiE "Backup finished with result: Success|result: Success"; then
  res auto-backup FAIL "backupnow reported Success: $(echo "$out" | head -3 | tr '\n' ' ')"
else
  res auto-backup UNKNOWN "unexpected output, see log"
fi
sets=$(S bmgr list sets 2>&1); echo "$sets" | sed 's/^/  sets: /' | head -5
S pm clear "$PKG" > /dev/null
tok=$(echo "$sets" | grep -oE '^[ ]*[0-9a-f]{6,}' | head -1 | tr -d ' ')
if [ -n "$tok" ]; then S bmgr restore "$tok" "$PKG" 2>&1 | sed 's/^/  restore: /' | head -5; else echo "  no restore set"; fi
# pm clear removed the planted files; whatever is back now came from a backup.
# The app has to be started once for run-as to see its dirs again.
S am start -W -n "$PKG/app.zaghlol.MainActivity" > /dev/null; sleep 10
n=$(canaries)
[ "$n" = 0 ] && res auto-restore PASS "0/3 canaries after clear+restore" || res auto-restore FAIL "$n/3 canaries came back"

echo "---- 2. adb backup (backup password empty)"
plant
# The confirm screen (com.android.backupconfirm) needs a tap: find the button with uiautomator.
# A tap is logged to $OUT/confirm-tapped; without it the archive proves nothing.
rm -f "$OUT/confirm-tapped" "$OUT/z.ab"
tap_confirm() {
  sleep 10
  for _ in $(seq 1 12); do
    A shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 < /dev/null
    xy=$(A exec-out cat /sdcard/ui.xml 2> /dev/null | python3 -I -c '
import re,sys
x=sys.stdin.read()
for m in re.finditer(r"<node[^>]*>", x):
    n=m.group(0)
    if re.search(r"(?i)button_allow|back up my data|text=\"(back up|backup)\"", n):
        b=re.search(r"bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n)
        if b:
            a=list(map(int,b.groups())); print((a[0]+a[2])//2,(a[1]+a[3])//2); break
')
    if [ -n "$xy" ]; then echo "  confirm button at $xy"; S input tap $xy; echo "$xy" > "$OUT/confirm-tapped"; return; fi
    sleep 4
  done
  echo "  no confirm button found (UI listing follows, text only)"
  A exec-out cat /sdcard/ui.xml 2> /dev/null | grep -o 'text="[^"]*"' | grep -v '=""' | head -10
}
tap_confirm &
tp=$!
timeout 120 adb -s "$DEVICE" backup -noapk -f "$OUT/z.ab" "$PKG" < /dev/null 2>&1 | head -3 | sed 's/^/  adb backup: /'
wait "$tp" 2> /dev/null
sz=$(stat -c %s "$OUT/z.ab" 2> /dev/null || echo 0)
echo "  archive bytes: $sz"
tapped=no; [ -s "$OUT/confirm-tapped" ] && tapped=yes
echo "  confirm tapped: $tapped"
# API 31+: the OS still lets adb back up a DEBUGGABLE app (allowBackup=false is not
# honoured for it), so leaked entries from this debug build say nothing about release.
exempt=no; [ "$API" -ge 31 ] && case "$flags" in *DEBUGGABLE*) exempt=yes ;; esac
cat > "$OUT/analyze.py" << 'PY'
import io, sys, tarfile, zlib
try:
    data = open(sys.argv[1], "rb").read()
except OSError:
    data = b""
tapped = sys.argv[2] == "yes"
if not tapped:
    print("RESULT UNKNOWN confirm screen was not tapped, the archive proves nothing"); sys.exit(0)
if not data:
    print("RESULT PASS empty file after a confirmed tap, nothing backed up"); sys.exit(0)
lines = data.split(b"\n", 4)
if len(lines) < 4 or lines[0] != b"ANDROID BACKUP":
    print("RESULT UNKNOWN not an adb backup archive"); sys.exit(0)
if lines[3] != b"none":
    print("RESULT UNKNOWN encrypted archive"); sys.exit(0)
body = lines[4] if len(lines) == 5 else b""
if not body:
    print("RESULT PASS header only, no app data"); sys.exit(0)
tar = zlib.decompress(body) if lines[2] == b"1" else body
names = tarfile.open(fileobj=io.BytesIO(tar)).getnames()
leaks = [n for n in names if n.startswith("apps/") and not n.endswith("/_manifest")]
for n in leaks[:30]:
    print("  entry: " + n)
if leaks and sys.argv[3] == "yes":
    print("RESULT UNKNOWN %d app data entries, but this is a debuggable build on API 31+ (debuggable apps are exempt from the adb backup restriction); not evidence for release, verify on a release build" % len(leaks)); sys.exit(0)
print("RESULT %s %d entries, %d app data entries" % ("FAIL" if leaks else "PASS", len(names), len(leaks)))
PY
python3 -I "$OUT/analyze.py" "$OUT/z.ab" "$tapped" "$exempt" | tee "$OUT/adb-backup.txt"
grep '^  entry:' "$OUT/adb-backup.txt" | head -30
r=$(grep -m1 '^RESULT' "$OUT/adb-backup.txt" | awk '{print $2}')
res adb-backup "${r:-UNKNOWN}" "$(grep -m1 '^RESULT' "$OUT/adb-backup.txt" | cut -d' ' -f3-) (bytes=$sz)"

if [ "$API" -ge 31 ]; then
  echo "---- 3. device-to-device transport (API 31+)"
  D2D=com.google.android.gms/.backup.migrate.service.D2dTransport
  S bmgr list transports | sed 's/^/  transport: /'
  if S bmgr list transports | grep -q D2dTransport; then
    plant
    S settings put secure backup_enable_d2d_test_mode 1
    S bmgr transport "$D2D" | sed 's/^/  /'
    S bmgr init "$D2D" | sed 's/^/  init: /'
    out=$(S bmgr backupnow "$PKG" 2>&1); echo "$out" | head -6 | sed 's/^/  d2d backupnow: /'
    S dumpsys backup | grep -i -A3 zaghlol | head -12 | sed 's/^/  d2d dumpsys: /'
    if echo "$out" | grep -qiE "not allowed|not eligible|Backup is not allowed"; then
      res d2d PASS "backupnow refused on the D2D transport"
    else
      res d2d UNKNOWN "see log"
    fi
    S settings put secure backup_enable_d2d_test_mode 0
  else
    res d2d SKIP "no D2dTransport on this image (real device row stays open)"
  fi
fi
echo "---- 4. NON-debuggable release-type build (stagingSms, debug keystore, no secrets)"
RPKG=app.zaghlol.staging
flutter build apk --release --flavor stagingSms 2>&1 | tail -3
rapk=$(ls build/app/outputs/flutter-apk/*.apk 2> /dev/null | grep -i stagingsms | grep -i release | head -1)
if [ -z "$rapk" ]; then
  res release-build FAIL "no release apk"
  echo "T165 api=$API summary: failures=$fails"; exit 1
fi
A install -r -g "$rapk" > /dev/null || { res release-install FAIL "install failed"; echo "T165 api=$API summary: failures=$((fails + 1))"; exit 1; }
S am start -W -n "$RPKG/app.zaghlol.MainActivity" > /dev/null
sleep 20
[ -n "$(S pidof "$RPKG")" ] && echo "  release app running" || echo "  release app not running"
rflags=$(S dumpsys package "$RPKG" | grep -m1 -E "^ *pkgFlags=")
[ -n "$rflags" ] || rflags=$(S dumpsys package "$RPKG" | grep -m1 -E "^ *flags=")
echo "  $rflags"
case "$rflags" in
  *DEBUGGABLE*) res release-flags FAIL "release build is DEBUGGABLE: $rflags" ;;
  *ALLOW_BACKUP*) res release-flags FAIL "ALLOW_BACKUP: $rflags" ;;
  *"["*"]"*) res release-flags PASS "no DEBUGGABLE, no ALLOW_BACKUP: $rflags" ;;
  *) res release-flags UNKNOWN "flags not readable: $rflags" ;;
esac
if S run-as "$RPKG" id 2>&1 | grep -qiE "not debuggable|unknown package"; then
  res release-run-as PASS "run-as refused: package is not debuggable"
else
  res release-run-as FAIL "run-as worked on the release build"
fi

# Merged manifest and data extraction rules, read from the APK itself.
AAPT=$(ls "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"/build-tools/*/aapt2 2> /dev/null | sort -V | tail -1)
echo "  aapt2: ${AAPT:-none}"
if [ -n "$AAPT" ]; then
  "$AAPT" dump xmltree --file AndroidManifest.xml "$rapk" > "$OUT/manifest.txt" 2>&1
  grep -E "allowBackup|dataExtractionRules|fullBackupContent|debuggable" "$OUT/manifest.txt" | sed 's/^ */  /'
  if grep -q 'allowBackup.*=false' "$OUT/manifest.txt"; then res manifest-allowbackup PASS "allowBackup=false in the release manifest"; else res manifest-allowbackup FAIL "allowBackup not false"; fi
  if grep -q 'dataExtractionRules' "$OUT/manifest.txt"; then res manifest-rules-ref PASS "dataExtractionRules attribute present"; else res manifest-rules-ref FAIL "no dataExtractionRules"; fi
  if grep -qE 'debuggable.*=true' "$OUT/manifest.txt"; then res manifest-debuggable FAIL "debuggable=true"; else res manifest-debuggable PASS "not debuggable"; fi
  rf=$("$AAPT" dump resources "$rapk" 2> /dev/null | grep -A4 'xml/data_extraction_rules' | grep -oE 'res/[^ ]+\.xml' | head -1)
  echo "  rules file in apk: ${rf:-none}"
  if [ -n "$rf" ]; then
    "$AAPT" dump xmltree --file "$rf" "$rapk" > "$OUT/rules.txt" 2>&1
    sed 's/^/    /' "$OUT/rules.txt" | head -50
    python3 -I - "$OUT/rules.txt" << 'PY' | tee "$OUT/rules-check.txt"
import re, sys
want = {"root", "file", "database", "sharedpref", "external", "device_root", "device_file", "device_database", "device_sharedpref"}
sec = None; got = {}; inc = 0
for l in open(sys.argv[1]):
    m = re.search(r"E: (cloud-backup|device-transfer)", l)
    if m:
        sec = m.group(1); got[sec] = set(); continue
    if re.search(r"E: include", l): inc += 1
    m = re.search(r'domain.*?="([a-z_]+)"', l)
    if m and sec: got[sec].add(m.group(1))
ok = inc == 0 and all(got.get(k) == want for k in ("cloud-backup", "device-transfer"))
print("RESULT %s cloud-backup=%d device-transfer=%d includes=%d domains" % ("PASS" if ok else "FAIL", len(got.get("cloud-backup", ())), len(got.get("device-transfer", ())), inc))
PY
    r=$(grep -m1 '^RESULT' "$OUT/rules-check.txt" | awk '{print $2}')
    res rules-domains "${r:-UNKNOWN}" "$(grep -m1 '^RESULT' "$OUT/rules-check.txt" | cut -d' ' -f3-)"
  else
    res rules-domains UNKNOWN "rules file not found in the apk"
  fi
else
  res manifest-apk UNKNOWN "no aapt2 on the runner"
fi

echo "---- 4a. release: Auto Backup (local transport)"
S bmgr transport com.android.localtransport/.LocalTransport > /dev/null
out=$(S bmgr backupnow "$RPKG" 2>&1); echo "$out" | sed 's/^/  backupnow: /' | head -8
if echo "$out" | grep -qiE "not allowed|not eligible|is not currently|Backup is not allowed"; then
  res release-auto-backup PASS "backupnow refused"
elif echo "$out" | grep -qiE "result: Success"; then
  res release-auto-backup FAIL "backupnow reported Success: $(echo "$out" | head -3 | tr '\n' ' ')"
else
  res release-auto-backup UNKNOWN "unexpected output, see log"
fi
sets=$(S bmgr list sets 2>&1); echo "$sets" | sed 's/^/  sets: /' | head -5
S pm clear "$RPKG" > /dev/null
tok=$(echo "$sets" | grep -oE '^[ ]*[0-9a-f]{6,}' | head -1 | tr -d ' ')
if [ -n "$tok" ]; then S bmgr restore "$tok" "$RPKG" 2>&1 | sed 's/^/  restore: /' | head -5; else echo "  no restore set"; fi
# run-as is impossible on a release build, so no canary can be planted or read back.
# The restore check here is: backupnow was refused (nothing was ever stored for the package).
S dumpsys backup | grep -c "$RPKG" | sed 's/^/  dumpsys backup lines naming the release package: /'

echo "---- 4b. release: adb backup"
rm -f "$OUT/confirm-tapped" "$OUT/r.ab"
tap_confirm &
tp=$!
timeout 150 adb -s "$DEVICE" backup -noapk -f "$OUT/r.ab" "$RPKG" < /dev/null 2>&1 | head -3 | sed 's/^/  adb backup: /'
wait "$tp" 2> /dev/null
rsz=$(stat -c %s "$OUT/r.ab" 2> /dev/null || echo 0)
rtapped=no; [ -s "$OUT/confirm-tapped" ] && rtapped=yes
echo "  release archive bytes: $rsz, confirm tapped: $rtapped"
python3 -I "$OUT/analyze.py" "$OUT/r.ab" "$rtapped" no | tee "$OUT/adb-backup-release.txt"
r=$(grep -m1 '^RESULT' "$OUT/adb-backup-release.txt" | awk '{print $2}')
res release-adb-backup "${r:-UNKNOWN}" "$(grep -m1 '^RESULT' "$OUT/adb-backup-release.txt" | cut -d' ' -f3-) (bytes=$rsz)"

echo "---- logcat: backup lines for the package (no app data)"
A logcat -d 2> /dev/null | grep -iE "BackupManagerService|BackupAgent|KeyValueBackup|FullBackup" | grep -i zaghlol | cut -c1-200 | tail -10
echo "T165 api=$API summary: failures=$fails"
[ "$fails" -eq 0 ]
