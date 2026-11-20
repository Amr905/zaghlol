#!/usr/bin/env bash
# T-190: self-test of check-app-size.sh (negative controls).
set -euo pipefail
G="$(dirname "$0")/check-app-size.sh"; D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
cat > "$D/b.json" <<J
{"growth_percent":10,"enforce_budget":false,"budget_bytes":{"a":1000,"c":1000},"baseline_bytes":{"a":1000,"b":1000}}
J
t() { printf '%s\t%s\n' "$1" "$2" > "$D/s.tsv"; bash "$G" "$D/s.tsv" t "$D/b.json" > "$D/o.log" 2>&1 && echo ok || echo fail; }
[ "$(t a 1100)" = ok ] || { echo "within 10% must pass"; exit 1; }
[ "$(t b 1101)" = fail ] || { echo "growth over 10% must fail"; exit 1; }
[ "$(t z 99999999)" = ok ] || { echo "unknown key must only print"; exit 1; }
[ "$(t c 5000)" = ok ] && grep -q "::warning::" "$D/o.log" || { echo "budget breach without enforce must warn"; exit 1; }
sed -i 's/"enforce_budget":false/"enforce_budget":true/' "$D/b.json"
[ "$(t c 5000)" = fail ] || { echo "budget breach with enforce must fail"; exit 1; }
[ "$(t a abc)" = fail ] || { echo "non-numeric must fail"; exit 1; }
echo "check-app-size self-test passed"
