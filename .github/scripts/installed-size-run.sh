#!/usr/bin/env bash
# T-208: one line per android-emulator-runner script entry; this wrapper runs the measurements.
set -uo pipefail
: "${RUNNER_TEMP:?}"
export OUT="$RUNNER_TEMP/size-out" DEVICE="${DEVICE:-emulator-5554}"
mkdir -p "$OUT"
S="$(dirname "$0")/installed-size-emu.sh"
bash "$S" debug-universal "$RUNNER_TEMP/apks/debug-universal.apk" app.zaghlol.dev
bash "$S" release-x86_64 "$RUNNER_TEMP/apks/release-x86_64.apk" app.zaghlol.dev
cat "$OUT/installed-size.md" >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
