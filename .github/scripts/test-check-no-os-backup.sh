#!/usr/bin/env bash
# T-165 negative controls for check-no-os-backup.sh: feeds synthetic
# `aapt2 dump xmltree` output and expects the good fixtures to pass and every
# broken fixture (allowBackup=true, a missing domain, an <include>, ...) to fail.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ERR_PREFIX="  (expected) "
# shellcheck source=check-no-os-backup.sh
source "$here/check-no-os-backup.sh"
set +e

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
cases=0

manifest() { # $1 allowBackup, $2 hasFragileUserData, $3 extra attribute lines (optional)
  cat << EOF
N: android=http://schemas.android.com/apk/res/android (line=0)
  E: manifest (line=0)
    A: http://schemas.android.com/apk/res/android:versionCode(0x0101021b)=1
    A: package="app.zaghlol.dev" (Raw: "app.zaghlol.dev")
      E: application (line=13)
        A: http://schemas.android.com/apk/res/android:label(0x01010001)=@0x7f0f0000
        A: http://schemas.android.com/apk/res/android:icon(0x01010002)=@0x7f0d0000
        A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=$1
        A: http://schemas.android.com/apk/res/android:fullBackupContent(0x010104eb)=@0x7f0e0000
        A: http://schemas.android.com/apk/res/android:hasFragileUserData(0x0101059a)=$2
        A: http://schemas.android.com/apk/res/android:dataExtractionRules(0x0101063e)=@0x7f0e0001
${3:-}
EOF
}

excludes() { # $1 indent, $2 domains (default: all 9), $3 path
  local d
  for d in ${2:-$EXPECTED_DOMAINS}; do
    printf '%sE: exclude (line=1)\n%s  A: domain="%s" (Raw: "%s")\n%s  A: path="%s" (Raw: "%s")\n' \
      "$1" "$1" "$d" "$d" "$1" "${3:-.}" "${3:-.}"
  done
}

der() { # $1 cloud domains, $2 transfer domains, $3 extra lines inside device-transfer
  echo 'E: data-extraction-rules (line=6)'
  echo '    E: cloud-backup (line=7)'
  echo '      A: disableIfNoEncryptionCapabilities=true'
  excludes '        ' "${1:-}"
  echo '    E: device-transfer (line=18)'
  excludes '        ' "${2:-}"
  if [ -n "${3:-}" ]; then echo "$3"; fi
}

fbc() { # $1 domains, $2 path
  echo 'E: full-backup-content (line=5)'
  excludes '    ' "${1:-}" "${2:-}"
}

expect() { # expect pass|fail <description> <command...>
  local want=$1 desc=$2 out rc
  shift 2
  cases=$((cases + 1))
  out=$("$@" 2>&1)
  rc=$?
  if { [ "$want" = pass ] && [ $rc -eq 0 ]; } || { [ "$want" = fail ] && [ $rc -ne 0 ]; }; then
    echo "ok   - $desc ($want)"
  else
    echo "::error::self-test: '$desc' should $want but exit code was $rc"
    echo "$out"
    failures=$((failures + 1))
  fi
}

all_but() { tr ' ' '\n' <<< "$EXPECTED_DOMAINS" | grep -vx "$1" | tr '\n' ' '; }

# Fixture layout copied from real aapt2 output (build-tools 36, app-ci run
# 42314155525): 4 spaces per nesting level, attributes 2 deeper.

# Positive controls.
manifest false false > "$work/m_ok"
der > "$work/der_ok"
fbc > "$work/fbc_ok"
expect pass "good manifest" check_manifest_xmltree "$work/m_ok"
expect pass "good data_extraction_rules" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/der_ok"
expect pass "good backup_rules" check_rules_xmltree full-backup-content - "$work/fbc_ok"

# Negative controls: manifest.
manifest true false > "$work/m1"
expect fail "allowBackup=true" check_manifest_xmltree "$work/m1"
manifest false true > "$work/m2"
expect fail "hasFragileUserData=true" check_manifest_xmltree "$work/m2"
manifest false false | grep -v dataExtractionRules > "$work/m3"
expect fail "dataExtractionRules missing" check_manifest_xmltree "$work/m3"
manifest false false | grep -v fullBackupContent > "$work/m4"
expect fail "fullBackupContent missing" check_manifest_xmltree "$work/m4"
manifest false false | grep -v allowBackup > "$work/m5"
expect fail "allowBackup missing (defaults to true)" check_manifest_xmltree "$work/m5"
manifest false false \
  '        A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=true' > "$work/m6"
expect fail "allowBackup declared twice" check_manifest_xmltree "$work/m6"

# Negative controls: data_extraction_rules.
der "" "$(all_but device_sharedpref)" > "$work/d1"
expect fail "device-transfer misses device_sharedpref" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d1"
der "$(all_but database)" > "$work/d2"
expect fail "cloud-backup misses database" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d2"
der "" "" '        E: include (line=30)
          A: domain="file" (Raw: "file")
          A: path="." (Raw: ".")' > "$work/d3"
expect fail "<include> present" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d3"
der | awk '/E: device-transfer/ { stop = 1 } !stop' > "$work/d4"
expect fail "device-transfer section missing" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d4"
der | sed '0,/path="\."/s//path="databases" (Raw: "databases")/' > "$work/d5"
expect fail "an exclude path is not '.'" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d5"
{ der; echo '    E: device-transfer (line=40)'; } > "$work/d6"
expect fail "duplicate device-transfer section" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d6"
der | sed 's/A: domain="\([a-z_]*\)" (Raw: "[a-z_]*")/A: domain=\1/' > "$work/d7"
expect fail "unparseable attribute format fails closed" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d7"
der "$EXPECTED_DOMAINS bogus" > "$work/d8"
expect fail "extra unknown domain" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d8"

der | awk '{ match($0, /^ */); p = ""; for (i = 0; i < RLENGTH / 2; i++) p = p " "; print p substr($0, RLENGTH + 1) }' > "$work/d9"
expect pass "older 2-space aapt2 layout still parses" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d9"
der "" "" '        E: exclude-all (line=31)' > "$work/d10"
expect fail "unknown element inside a section" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/d10"

# Negative controls: backup_rules.
fbc "$(all_but root) file" > "$work/f1"
expect fail "backup_rules: root replaced by duplicate file" check_rules_xmltree full-backup-content - "$work/f1"
fbc > "$work/f2"
expect fail "backup_rules checked as data-extraction-rules" check_rules_xmltree data-extraction-rules "cloud-backup device-transfer" "$work/f2"
der > "$work/f3"
expect fail "data-extraction-rules where full-backup-content expected" check_rules_xmltree full-backup-content - "$work/f3"

echo "$cases cases, $failures failed"
[ "$failures" -eq 0 ]
