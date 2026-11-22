#!/usr/bin/env bash
# T-208: installed size of the app on a device (emulator). Usage:
#   installed-size-emu.sh <label> <apk> <package>
# Installs the APK, records what the OS reports (dumpsys diskstats "App Size",
# pm path, du of the code dir, native-lib extraction, dexopt state), launches
# the app once (no user data besides what first run creates) and records
# again. Appends to $OUT/installed-size.md and $OUT/<label>.txt. Text only.
# Inputs: DEVICE (emulator-5554), OUT (output dir). Never reads app data
# contents; sizes only.
set -uo pipefail
: "${DEVICE:?}" "${OUT:?}"
LABEL="$1"; APK="$2"; PKG="$3"
mkdir -p "$OUT"
A() { adb -s "$DEVICE" "$@"; }
LOG="$OUT/$LABEL.txt"; : > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

A root > /dev/null 2>&1 || true
A wait-for-device
A uninstall "$PKG" > /dev/null 2>&1 || true
say "== $LABEL: $(basename "$APK") $(stat -c %s "$APK") bytes"
if ! A install -r -t "$APK" >> "$LOG" 2>&1; then say "INSTALL FAILED"; tail -n 5 "$LOG"; exit 0; fi
sleep 5

measure() { # <phase>
  local phase="$1"
  say "-- $phase"
  A shell pm path "$PKG" | tr -d '\r' | tee -a "$LOG"
  local dir; dir=$(A shell pm path "$PKG" | tr -d '\r' | head -n 1 | sed 's/^package://; s#/[^/]*$##')
  say "code dir: $dir"
  say "du -k of code dir (APK + oat + extracted libs):"
  A shell "du -ak '$dir' 2>/dev/null | sort -rn | head -n 25" | tr -d '\r' | tee -a "$LOG"
  say "du -sk code dir / data dir:"
  A shell "du -sk '$dir' /data/data/$PKG 2>/dev/null" | tr -d '\r' | tee -a "$LOG"
  say "data dir tree (sizes only):"
  A shell "du -ak /data/data/$PKG 2>/dev/null | sort -rn | head -n 12" | tr -d '\r' | tee -a "$LOG"
  say "dumpsys package (packaging fields):"
  A shell dumpsys package "$PKG" | tr -d '\r' | grep -E "nativeLibraryDir|legacyNativeLibraryDir|primaryCpuAbi|codePath|extractNativeLibs|EXTRACT_NATIVE|pkgFlags|privateFlags|Dexopt|\[base.apk\]|status=|reason=" | head -n 20 | tee -a "$LOG"
  say "dumpsys diskstats (App Size = what Settings shows as App size):"
  A shell dumpsys diskstats | tr -d '\r' | grep -E "^(App Size|App Data Size|App Cache Size|Package Names|Cache Size)|$PKG" | head -n 12 | tee -a "$LOG"
  say "cmd package art dump (compile filter):"
  A shell dumpsys package dexopt 2>/dev/null | tr -d '\r' | grep -A4 "$PKG" | head -n 10 | tee -a "$LOG"
}
measure "after install, before first launch (no user data)"
A shell pm clear "$PKG" > /dev/null 2>&1 || true
A shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
sleep 25
measure "after first launch (onboarding screen, no user data entered)"
A shell am force-stop "$PKG" || true
{
  echo "### $LABEL"; echo; echo '```'
  grep -E "^== |^-- |^App Size|^App Data Size|^App Cache Size|du -sk|^[0-9]+\s+/data|nativeLibraryDir|legacyNativeLibraryDir|extractNativeLibs|EXTRACT_NATIVE|status=" "$LOG" | head -n 60
  echo '```'; echo
} >> "$OUT/installed-size.md"
exit 0
