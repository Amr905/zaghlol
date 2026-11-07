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
manifest false false \
  '        A: http://schemas.android.com/apk/res/android:backupAgent(0x0101027f)="app.zaghlol.LeakyAgent" (Raw: "app.zaghlol.LeakyAgent")' > "$work/m7"
expect fail "backupAgent present (custom agent bypasses D2D rules)" check_manifest_xmltree "$work/m7"
manifest false false \
  '        A: http://schemas.android.com/apk/res/android:fullBackupOnly(0x01010473)=true' > "$work/m8"
expect fail "fullBackupOnly=true" check_manifest_xmltree "$work/m8"
manifest false false \
  '        A: http://schemas.android.com/apk/res/android:fullBackupOnly(0x01010473)=false' > "$work/m9"
expect pass "fullBackupOnly=false is allowed" check_manifest_xmltree "$work/m9"
child='        E: activity (line=20)
          A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=false'
{ manifest false false | grep -v allowBackup; printf '%s\n' "$child"; } > "$work/m10"
expect fail "allowBackup=false only on a child of <application>" check_manifest_xmltree "$work/m10"
manifest false false | sed 's/E: application/E: not-application/' > "$work/m11"
expect fail "no <application> element" check_manifest_xmltree "$work/m11"
{ manifest false false; echo '      E: application (line=40)'; } > "$work/m12"
expect fail "two <application> elements" check_manifest_xmltree "$work/m12"

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

# check_apk end to end with a stub aapt2 serving fixtures: covers resolving
# the manifest IDs through `aapt2 dump resources`, including R8-shortened
# file names (res/Qq.xml, as in the real release APKs).
resources() {
  cat << 'EOF'
Binary APK
Package name=app.zaghlol id=7f
  type mipmap id=0d entryCount=1
    resource 0x7f0d0000 mipmap/ic_launcher
      (mdpi) (file) res/mipmap-mdpi-v4/ic_launcher.png type=PNG
  type xml id=0e entryCount=2
    resource 0x7f0e0000 xml/backup_rules
      () (file) res/Qq.xml type=XML
    resource 0x7f0e0001 xml/data_extraction_rules
      () (file) res/4j.xml type=XML
EOF
}

stub_apk() { # stub_apk <dir> <resources-text>: fixtures + a stub aapt2 in <dir>
  mkdir -p "$1"
  manifest false false > "$1/AndroidManifest.xml"
  fbc > "$1/res_Qq.xml"
  der > "$1/res_4j.xml"
  printf '%s\n' "$2" > "$1/resources"
  cat > "$1/aapt2" << EOF
#!/usr/bin/env bash
# stub: "dump resources <apk>" or "dump xmltree --file <path> <apk>"
case "\$2" in
  resources) cat "$1/resources" ;;
  xmltree) f="$1/\$(tr / _ <<< "\$4")"; [ -f "\$f" ] && cat "\$f" || exit 1 ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$1/aapt2"
}

stub_apk "$work/a_ok" "$(resources)"
expect pass "check_apk: obfuscated res/Qq.xml + res/4j.xml resolve and pass" check_apk "$work/a_ok/aapt2" fake.apk
stub_apk "$work/a1" "$(resources | sed 's#xml/backup_rules#xml/TMP#; s#xml/data_extraction_rules#xml/backup_rules#; s#xml/TMP#xml/data_extraction_rules#')"
expect fail "check_apk: resource names swapped" check_apk "$work/a1/aapt2" fake.apk
stub_apk "$work/a2" "$(resources | grep -v 'resource 0x7f0e0001')"
expect fail "check_apk: dataExtractionRules ID missing from the resource table" check_apk "$work/a2/aapt2" fake.apk
stub_apk "$work/a3" "$(resources | grep -v 'res/Qq.xml')"
expect fail "check_apk: (file) line missing for backup_rules" check_apk "$work/a3/aapt2" fake.apk
stub_apk "$work/a4" "$(resources)"
rm "$work/a4/res_4j.xml"
expect fail "check_apk: rules file missing from the APK" check_apk "$work/a4/aapt2" fake.apk
mkdir -p "$work/a5"
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/a5/aapt2"
chmod +x "$work/a5/aapt2"
expect fail "check_apk: aapt2 exits non-zero with empty output" check_apk "$work/a5/aapt2" fake.apk
before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -type d 2> /dev/null | wc -l)
check_apk "$work/a5/aapt2" fake.apk > /dev/null 2>&1
check_apk "$work/a_ok/aapt2" fake.apk > /dev/null 2>&1
after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -type d 2> /dev/null | wc -l)
cases=$((cases + 1))
if [ "$after" -le "$before" ]; then
  echo "ok   - check_apk removes its work directory on success and failure"
else
  echo "::error::self-test: check_apk left $((after - before)) work directories behind"
  failures=$((failures + 1))
fi

echo "$cases cases, $failures failed"
[ "$failures" -eq 0 ]
