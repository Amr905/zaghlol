#!/usr/bin/env bash
# T-007 (db-platform.yml): copies the ZAGHLOL_DB_BENCH / ZAGHLOL_DB_FINDINGS
# lines from a test log into the step summary and $RUNNER_TEMP/db-results/.
# Usage: db-platform-results.sh <log> <label> <require-bench: true|false>
set -euo pipefail
log=$1 label=$2 need_bench=$3
out="$RUNNER_TEMP/db-results"
mkdir -p "$out"
touch "$log"
grep -oE 'ZAGHLOL_DB_(BENCH|FINDINGS) \{.*\}' "$log" | sort -u > "$out/$label.txt" || true
{
  echo "### $label"
  echo '```'
  cat "$out/$label.txt"
  echo '```'
} >> "$GITHUB_STEP_SUMMARY"
cat "$out/$label.txt"
if ! grep -q '^ZAGHLOL_DB_FINDINGS ' "$out/$label.txt"; then
  echo "::warning::$label: no ZAGHLOL_DB_FINDINGS line in the log"
fi
if [ "$need_bench" = "true" ] && ! grep -q '^ZAGHLOL_DB_BENCH ' "$out/$label.txt"; then
  echo "::error::$label: no ZAGHLOL_DB_BENCH line in the log"
  exit 1
fi
