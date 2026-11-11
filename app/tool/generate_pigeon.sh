#!/usr/bin/env bash
# Regenerates every Pigeon output (Dart, Kotlin, Swift) from app/pigeons/*.dart.
# Run from anywhere after `flutter pub get`. CI runs this and fails when it
# changes any tracked file (see .github/workflows/README.md).
set -euo pipefail
cd "$(dirname "$0")/.."

# FU-042: CI's stale check (app-ci.yml) only watches these three directories,
# so an output anywhere else could go stale unnoticed. Refuse it.
allowed='^(lib/core/platform/|android/app/src/main/kotlin/app/zaghlol/platform/|ios/Runner/Platform/)'
for input in pigeons/*.dart; do
  outs=$(grep -oE "[A-Za-z]+Out: *'[^']+'" "$input" | sed -E "s/.*'([^']+)'/\1/")
  [ -n "$outs" ] || { echo "no outputs configured in $input" >&2; exit 1; }
  for out in $outs; do
    if ! [[ "$out" =~ $allowed ]] || [[ "$out" == *..* ]]; then
      echo "pigeon output outside the checked directories: $input -> $out" >&2
      exit 1
    fi
  done
done

for input in pigeons/*.dart; do
  dart run pigeon --input "$input"
done

# Pigeon's Dart output is not always dart-format clean, and CI checks format.
dart format pigeons lib/core/platform
