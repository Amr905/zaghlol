#!/usr/bin/env bash
# T-015 (AC3): fails if any form of the synthetic test key appears in the
# given log files (flutter test output, adb logcat, simulator log). Prints
# only per-file match counts, never a matching line. A positive control
# proves the grep finds a planted needle.
# Usage: db-key-log-scan.sh <log>...
set -euo pipefail
[ "$#" -ge 1 ] || { echo "::error::usage: db-key-log-scan.sh <log>..."; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 -I "$(dirname "$0")/db-key-needles.py" > "$work/needles"
[ "$(wc -l < "$work/needles")" -eq 6 ] || { echo "::error::unexpected needle count"; exit 1; }

# Positive control: a fixture line with an embedded needle must match.
{ echo "I/flutter (1234): control "; sed -n '1p' "$work/needles"; echo " end"; } | tr -d '\n' > "$work/control.log"
if ! grep -qF -f "$work/needles" "$work/control.log"; then
  echo "::error::positive control failed: the grep did not find a planted needle"
  exit 1
fi
echo "key log scan: positive control matched"

hits=0
for f in "$@"; do
  if [ ! -s "$f" ]; then
    echo "::error::log $f is missing or empty"
    exit 1
  fi
  n=$(grep -cF -f "$work/needles" "$f" || true)
  echo "key log scan: $(basename "$f"): $(wc -l < "$f") lines, $n matching"
  hits=$((hits + n))
done
if [ "$hits" -ne 0 ]; then
  echo "::error::a form of the synthetic database key appears in the device logs ($hits lines)"
  exit 1
fi
echo "key log scan: 0 matches"
