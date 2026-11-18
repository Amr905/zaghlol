#!/usr/bin/env bash
# T-176 / T-177: derive the store version numbers. Prints KEY=VALUE lines.
#
#   release-version.sh <pubspec.yaml> <run-number> [override-build-number] [android-flavor]
#
# - BUILD_NAME: the semver part of `version:` in app/pubspec.yaml (MAJOR.MINOR.PATCH).
# - BUILD_BASE: the override when given, else the workflow run number.
# - IOS_BUILD_NUMBER: BUILD_BASE (CFBundleVersion; must grow for one BUILD_NAME).
# - ANDROID_VERSION_CODE: BUILD_BASE * 2 (+1 for a NoSms flavor). prodSms and
#   prodNoSms share one applicationId, and Play wants a unique, growing
#   versionCode per uploaded bundle, so the two flavors never collide.
# Fails on a malformed version, a non-numeric base, or a code over Play's limit (2100000000).
set -euo pipefail
pubspec=${1:?pubspec path}
run=${2:?run number}
override=${3:-}
flavor=${4:-prodSms}

line=$(grep -E '^version:[[:space:]]*' "$pubspec" | head -n 1 || true)
ver=${line#version:}
ver=$(echo "$ver" | tr -d '[:space:]')
name=${ver%%+*}
if ! [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::pubspec version '$ver' is not MAJOR.MINOR.PATCH[+build]" >&2
  exit 1
fi
base=${override:-$run}
if ! [[ "$base" =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo "::error::build number '$base' must be a positive integer of at most 9 digits" >&2
  exit 1
fi
offset=0
case "$flavor" in
  prodSms) offset=0 ;;
  prodNoSms) offset=1 ;;
  *) echo "::error::unknown flavor '$flavor' (prodSms or prodNoSms)" >&2; exit 1 ;;
esac
code=$((base * 2 + offset))
if [ "$code" -gt 2100000000 ]; then
  echo "::error::versionCode $code exceeds Play's limit" >&2
  exit 1
fi
echo "BUILD_NAME=$name"
echo "BUILD_BASE=$base"
echo "IOS_BUILD_NUMBER=$base"
echo "ANDROID_VERSION_CODE=$code"
