#!/usr/bin/env bash
# T-190 / NFR-PERF-07 size guard. Usage: check-app-size.sh <sizes.tsv> <label> [baseline.json]
# sizes.tsv: "key<TAB>bytes" per line. Prints every size, then fails when
#   - a key with a recorded baseline grew by more than growth_percent, or
#   - a key with a budget passes it and enforce_budget is true (the committed baseline sets it true, so the
#     40 MB / 60 MB budgets of D-69 are enforced; with false they would only warn).
# Keys without a baseline or budget are only printed. After an intended size change,
# update .github/size-baseline.json in the same commit (the new value is the new reference).
set -euo pipefail
TSV="$1"; LABEL="$2"; BASE="${3:-$(dirname "$0")/../size-baseline.json}"
[ -f "$TSV" ] || { echo "::error::no size table at $TSV"; exit 1; }
[ -f "$BASE" ] || { echo "::error::no baseline file $BASE"; exit 1; }
pct=$(jq -r '.growth_percent' "$BASE")
enforce=$(jq -r '.enforce_budget' "$BASE")
fail=0
echo "size guard ($LABEL): growth limit ${pct}%, budget enforced: $enforce"
while IFS=$'\t' read -r key bytes; do
  [ -n "$key" ] || continue
  [[ "$bytes" =~ ^[0-9]+$ ]] || { echo "::error::size of $key is not a number"; fail=1; continue; }
  mib=$(awk -v b="$bytes" 'BEGIN{printf "%.2f", b/1048576}')
  line="$key = $bytes bytes ($mib MiB)"
  base=$(jq -r --arg k "$key" '.baseline_bytes[$k] // empty' "$BASE")
  budget=$(jq -r --arg k "$key" '.budget_bytes[$k] // empty' "$BASE")
  if [ -n "$base" ]; then
    limit=$(awk -v b="$base" -v p="$pct" 'BEGIN{printf "%d", b*(100+p)/100}')
    line="$line; baseline $base, limit $limit"
    if [ "$bytes" -gt "$limit" ]; then
      echo "::error::$key grew from $base to $bytes bytes (more than ${pct}%)"; fail=1
    fi
  fi
  if [ -n "$budget" ]; then
    line="$line; budget $budget"
    if [ "$bytes" -gt "$budget" ]; then
      if [ "$enforce" = "true" ]; then echo "::error::$key is over the NFR-PERF-07 budget ($bytes > $budget)"; fail=1
      else echo "::warning::$key is over the NFR-PERF-07 budget ($bytes > $budget); not enforced until the PO confirms the targets"; fi
    fi
  fi
  echo "$line"
done < "$TSV"
exit $fail
