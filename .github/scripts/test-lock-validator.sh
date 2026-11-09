#!/usr/bin/env bash
# Self-test of the pubspec.lock validator embedded in app-regen.yml (T-003
# review R2-N1, landed in T-007). Extracts the Python between
# "# BEGIN lock-validator" and "# END lock-validator" from the commit job's
# step exactly as Actions would see it (YAML-parsed run script), then runs it
# with the system Python (-I) against:
#   - the repository's current pubspec.lock (must pass), and
#   - every fixture in .github/scripts/fixtures/pubspec-lock/bad-*.lock (must
#     fail, with the message given in the fixture's "# expect: " first line).
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
fixtures="$root/.github/scripts/fixtures/pubspec-lock"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

/usr/bin/python3 -I - "$root/.github/workflows/app-regen.yml" "$work/validator.py" <<'PY'
import sys
import yaml

workflow = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
scripts = [
    step["run"]
    for step in workflow["jobs"]["commit"]["steps"]
    if "# BEGIN lock-validator" in step.get("run", "")
]
if len(scripts) != 1:
    sys.exit("expected exactly one step with the lock-validator markers, found %d" % len(scripts))
lines = scripts[0].split("\n")
begin = lines.index("# BEGIN lock-validator")
end = lines.index("# END lock-validator")
if end <= begin:
    sys.exit("markers out of order")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(lines[begin : end + 1]) + "\n")
PY

total=0
failed=0

run_case() { # name file expect(pass|fail) [message]
  local name=$1 file=$2 expect=$3 message=${4:-}
  local out status=0
  total=$((total + 1))
  out=$(/usr/bin/python3 -I "$work/validator.py" "$file" 2>&1) || status=$?
  if [ "$expect" = pass ]; then
    if [ "$status" -ne 0 ]; then
      echo "FAIL $name: expected pass, got exit $status: $out"; failed=$((failed + 1)); return
    fi
  else
    if [ "$status" -eq 0 ]; then
      echo "FAIL $name: expected rejection, validator accepted it"; failed=$((failed + 1)); return
    fi
    if [ -n "$message" ] && ! grep -qF -- "$message" <<<"$out"; then
      echo "FAIL $name: rejected for the wrong reason (want '$message'): $out"; failed=$((failed + 1)); return
    fi
  fi
  echo "ok   $name ($expect)"
}

run_case "good: current pubspec.lock" "$root/pubspec.lock" pass

shopt -s nullglob
bad=("$fixtures"/bad-*.lock)
if [ "${#bad[@]}" -lt 8 ]; then
  echo "::error::expected at least 8 bad fixtures in $fixtures, found ${#bad[@]}"
  exit 1
fi
for f in "${bad[@]}"; do
  expect=$(head -n 1 "$f" | sed -n 's/^# expect: //p')
  if [ -z "$expect" ]; then
    echo "::error::$f has no '# expect: <message>' first line"
    exit 1
  fi
  run_case "bad: $(basename "$f")" "$f" fail "$expect"
done

echo "$total cases, $failed failed"
if [ "$failed" -ne 0 ]; then
  echo "::error::lock validator self-test: $failed of $total cases failed"
  exit 1
fi
