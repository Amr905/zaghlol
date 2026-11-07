#!/usr/bin/env bash
# T-165 (FR-SEC-05): assert that a final APK lets no OS mechanism copy app data.
#
#   check-no-os-backup.sh <aapt2> <apk>
#
# Checks the compiled manifest and the compiled rule files inside the APK (not
# the sources), so manifest merging, flavors and resource shrinking are covered:
#   - <application> allowBackup=false and hasFragileUserData=false
#   - no android:backupAgent anywhere and no fullBackupOnly=true (a custom
#     agent ignores dataExtractionRules on D2D)
#   - fullBackupContent -> @xml/backup_rules, dataExtractionRules -> @xml/data_extraction_rules
#   - data_extraction_rules: exactly <cloud-backup> and <device-transfer>, each
#     with exactly the 9 domains below as <exclude path=".">, no <include>
#   - backup_rules: the same 9 excludes directly under <full-backup-content>
#
# Sourcing the file defines the functions only; test-check-no-os-backup.sh
# feeds them fixtures (negative controls). Any parse surprise fails closed.
set -euo pipefail

EXPECTED_DOMAINS="root file database sharedpref external device_root device_file device_database device_sharedpref"
# Prefix for failure lines; the self-test overrides it so expected failures
# are not reported as GitHub error annotations.
ERR_PREFIX="${ERR_PREFIX-::error::}"

_err() { echo "${ERR_PREFIX}$*"; }

# Reads `aapt2 dump xmltree` output of a rules file on stdin and prints:
#   ROOT <name> | SECTION <name> | EXCLUDE <section> <domain> <path>
#   INCLUDE <section> | UNKNOWN <section> <element>
_parse_rules() {
  awk '
    function flush() {
      if (inex) print "EXCLUDE", section, (dom == "" ? "<none>" : dom), (pth == "" ? "<none>" : pth)
      inex = 0; dom = ""; pth = ""
    }
    /^ *E: / {
      flush()
      match($0, /^ */); ind = RLENGTH; name = $2
      if (root == "") { root = name; rootind = ind; section = name; print "ROOT", name; next }
      # aapt2 indentation width varies by version: depth 1 is the indent of
      # the first element nested under the root.
      if (childind == "" && ind > rootind) childind = ind
      if (ind == childind) {
        if (name == "exclude" || name == "include") section = root
        else { section = name; print "SECTION", name; next }
      }
      if (name == "exclude") inex = 1
      else if (name == "include") print "INCLUDE", section
      else print "UNKNOWN", section, name
      next
    }
    /^ *A: / && inex {
      if (match($0, /A: ([^ =]*:)?domain="[^"]*"/)) {
        s = substr($0, RSTART, RLENGTH); sub(/.*domain="/, "", s); sub(/"$/, "", s); dom = s
      }
      if (match($0, /A: ([^ =]*:)?path="[^"]*"/)) {
        s = substr($0, RSTART, RLENGTH); sub(/.*path="/, "", s); sub(/"$/, "", s); pth = s
      }
    }
    END { flush() }
  '
}

_expected_excludes() {
  local d
  for d in $EXPECTED_DOMAINS; do echo "$d ."; done | sort
}

# check_rules_xmltree <expected-root> <"section1 section2" | "-"> <xmltree-file>
# "-" means the excludes sit directly under the root (full-backup-content).
check_rules_xmltree() {
  local want_root=$1 want_sections=$2 file=$3 parsed fail=0 s actual expected got_sections want_sorted
  parsed=$(_parse_rules < "$file")
  if ! grep -qx "ROOT $want_root" <<< "$parsed"; then
    _err "$file: root element is not <$want_root>: $(grep '^ROOT' <<< "$parsed" || echo none)"
    return 1
  fi
  if grep -q '^INCLUDE' <<< "$parsed"; then
    _err "$file: <include> is forbidden: $(grep '^INCLUDE' <<< "$parsed" | tr '\n' ' ')"
    fail=1
  fi
  if grep -q '^UNKNOWN' <<< "$parsed"; then
    _err "$file: unexpected element(s): $(grep '^UNKNOWN' <<< "$parsed" | tr '\n' ' ')"
    fail=1
  fi
  if [ "$want_sections" = "-" ]; then
    want_sorted=""
    want_sections=$want_root
  else
    want_sorted=$(tr ' ' '\n' <<< "$want_sections" | sort)
  fi
  got_sections=$(awk '$1 == "SECTION" { print $2 }' <<< "$parsed" | sort)
  if [ "$got_sections" != "$want_sorted" ]; then
    _err "$file: sections are [$(echo $got_sections)], expected exactly [$(echo $want_sorted)]"
    fail=1
  fi
  expected=$(_expected_excludes)
  for s in $want_sections; do
    actual=$(awk -v s="$s" '$1 == "EXCLUDE" && $2 == s { print $3, $4 }' <<< "$parsed" | sort)
    if [ "$actual" != "$expected" ]; then
      _err "$file: <$s> excludes are [$(echo "$actual" | tr '\n' ',')], expected exactly [$(echo "$expected" | tr '\n' ',')]"
      fail=1
    fi
  done
  return $fail
}

# _application_attrs <xmltree-file>: prints the attribute lines of the
# <application> element itself (not of its children). Exits non-zero unless
# the manifest has exactly one <application>.
_application_attrs() {
  awk '
    /^ *E: / {
      match($0, /^ */); ind = RLENGTH
      if ($2 == "application") { apps++; inapp = 1; appind = ind; next }
      inapp = 0
      next
    }
    inapp && /^ *A: / { match($0, /^ */); if (RLENGTH > appind) print }
    END { if (apps != 1) { print "APPLICATION_COUNT=" apps + 0; exit 1 } }
  ' "$1"
}

# check_manifest_xmltree <xmltree-file>: prints "<fullBackupContent id> <dataExtractionRules id>".
check_manifest_xmltree() {
  local file=$1 fail=0 n attr fbc der app
  if ! app=$(_application_attrs "$file"); then
    _err "manifest: expected exactly one <application> element ($(tail -n 1 <<< "$app"))"
    return 1
  fi
  # A custom BackupAgent (for example merged in from a library manifest) can
  # stream any file during D2D: dataExtractionRules only drive the default
  # FullBackupAgent. Forbidden anywhere in the merged manifest.
  if grep -qE 'android:backupAgent\(0x[0-9a-f]{8}\)=' "$file"; then
    _err "manifest: android:backupAgent is declared (bypasses dataExtractionRules on D2D): $(grep -E 'android:backupAgent' "$file" | xargs)"
    fail=1
  fi
  if grep -qE 'android:fullBackupOnly\(0x[0-9a-f]{8}\)=true( |$)' "$file"; then
    _err "manifest: android:fullBackupOnly is true"
    fail=1
  fi
  # Each attribute must appear exactly once in the manifest, on <application>.
  for attr in allowBackup hasFragileUserData fullBackupContent dataExtractionRules; do
    n=$(grep -cE "android:${attr}\(0x[0-9a-f]{8}\)=" "$file" || true)
    if [ "$n" != "1" ]; then
      _err "manifest: android:$attr appears $n times, expected exactly 1"
      fail=1
    fi
    n=$(grep -cE "android:${attr}\(0x[0-9a-f]{8}\)=" <<< "$app" || true)
    if [ "$n" != "1" ]; then
      _err "manifest: android:$attr is not an attribute of <application>"
      fail=1
    fi
  done
  if ! grep -qE 'android:allowBackup\(0x01010280\)=false( |$)' <<< "$app"; then
    _err "manifest: <application> android:allowBackup is not false: $(grep -E 'android:allowBackup' <<< "$app" || echo missing)"
    fail=1
  fi
  if ! grep -qE 'android:hasFragileUserData\(0x[0-9a-f]{8}\)=false( |$)' <<< "$app"; then
    _err "manifest: <application> android:hasFragileUserData is not false: $(grep -E 'android:hasFragileUserData' <<< "$app" || echo missing)"
    fail=1
  fi
  fbc=$(grep -oE 'android:fullBackupContent\(0x[0-9a-f]{8}\)=@0x[0-9a-fA-F]{8}' <<< "$app" | head -n 1 | sed 's/.*=@//' || true)
  der=$(grep -oE 'android:dataExtractionRules\(0x[0-9a-f]{8}\)=@0x[0-9a-fA-F]{8}' <<< "$app" | head -n 1 | sed 's/.*=@//' || true)
  if [ -z "$fbc" ]; then _err "manifest: <application> android:fullBackupContent is not a resource reference"; fail=1; fi
  if [ -z "$der" ]; then _err "manifest: <application> android:dataExtractionRules is not a resource reference"; fail=1; fi
  [ $fail -eq 0 ] || return 1
  echo "$fbc $der"
}

# resolve_resource <aapt2-dump-resources-file> <0xid>: prints "<type/name> <path-in-apk>".
resolve_resource() {
  awk -v id="$(tr 'A-F' 'a-f' <<< "$2")" '
    $1 == "resource" && tolower($2) == id { name = $3; want = 1; next }
    want && $1 == "resource" { exit }
    want && /\(file\)/ { for (i = 1; i < NF; i++) if ($i == "(file)") { print name, $(i + 1); exit } }
  ' "$1"
}

# check_apk <aapt2> <apk>. The body is a subshell, so its EXIT trap removes
# the work directory on every return path.
check_apk() (
  aapt2=$1
  apk=$2
  fail=0
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  if ! "$aapt2" dump xmltree --file AndroidManifest.xml "$apk" > "$work/manifest.txt" \
    || [ ! -s "$work/manifest.txt" ]; then
    _err "aapt2 dump xmltree AndroidManifest.xml failed or printed nothing"
    exit 1
  fi
  if ! "$aapt2" dump resources "$apk" > "$work/resources.txt" || [ ! -s "$work/resources.txt" ]; then
    _err "aapt2 dump resources failed or printed nothing"
    exit 1
  fi
  grep -E 'allowBackup|hasFragileUserData|fullBackupContent|dataExtractionRules|backupAgent|fullBackupOnly' \
    "$work/manifest.txt" || true
  if ! ids=$(check_manifest_xmltree "$work/manifest.txt"); then
    echo "$ids"
    exit 1
  fi
  read -r fbc der <<< "$ids"
  for pair in "$fbc:xml/backup_rules:full-backup-content:-" \
    "$der:xml/data_extraction_rules:data-extraction-rules:cloud-backup device-transfer"; do
    IFS=: read -r id want_name want_root want_sections <<< "$pair"
    res=$(resolve_resource "$work/resources.txt" "$id")
    name=""
    path=""
    read -r name path <<< "$res" || true
    if [ "$name" != "$want_name" ] || [ -z "$path" ]; then
      _err "$id resolves to '${name:-?}' (file '${path:-?}'), expected $want_name"
      fail=1
      continue
    fi
    echo "$want_name -> $path"
    if ! "$aapt2" dump xmltree --file "$path" "$apk" > "$work/rules.txt" || [ ! -s "$work/rules.txt" ]; then
      _err "aapt2 dump xmltree $path failed or printed nothing"
      fail=1
      continue
    fi
    cat "$work/rules.txt"
    check_rules_xmltree "$want_root" "$want_sections" "$work/rules.txt" || fail=1
  done
  exit $fail
)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -ne 2 ]; then
    echo "usage: $0 <aapt2> <apk>" >&2
    exit 2
  fi
  if check_apk "$1" "$2"; then
    echo "OK: $2 excludes all app data from OS backup and device transfer"
  else
    _err "$2 fails the T-165 no-OS-backup assertions"
    exit 1
  fi
fi
