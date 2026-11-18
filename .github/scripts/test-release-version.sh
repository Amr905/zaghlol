#!/usr/bin/env bash
# Self-test of release-version.sh (T-176/T-177), run by the release workflows.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { # name, expected-substring, actual
  if ! grep -qxF "$2" <<<"$3"; then echo "FAIL $1: wanted '$2' in: $3"; fail=1; else echo "ok   $1"; fi
}
printf 'name: x\nversion: 1.4.2+7\n' > "$tmp/p.yaml"
out=$(bash "$here/release-version.sh" "$tmp/p.yaml" 42 "" prodSms)
check name BUILD_NAME=1.4.2 "$out"
check sms-code ANDROID_VERSION_CODE=84 "$out"
check ios IOS_BUILD_NUMBER=42 "$out"
out=$(bash "$here/release-version.sh" "$tmp/p.yaml" 42 "" prodNoSms)
check nosms-code ANDROID_VERSION_CODE=85 "$out"
out=$(bash "$here/release-version.sh" "$tmp/p.yaml" 42 100 prodSms)
check override ANDROID_VERSION_CODE=200 "$out"
for bad in "version: 1.4+1" "version: 1.4.2-beta+1" "nothing: here"; do
  printf '%s\n' "$bad" > "$tmp/b.yaml"
  if bash "$here/release-version.sh" "$tmp/b.yaml" 1 >/dev/null 2>&1; then echo "FAIL accepted '$bad'"; fail=1; else echo "ok   rejects '$bad'"; fi
done
for badn in 0 abc 1000000000 -3; do
  if bash "$here/release-version.sh" "$tmp/p.yaml" 1 "$badn" >/dev/null 2>&1; then echo "FAIL accepted build '$badn'"; fail=1; else echo "ok   rejects build '$badn'"; fi
done
if bash "$here/release-version.sh" "$tmp/p.yaml" 1 "" devSms >/dev/null 2>&1; then echo "FAIL accepted devSms"; fail=1; else echo "ok   rejects devSms"; fi
exit $fail
