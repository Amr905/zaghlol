#!/usr/bin/env bash
# Regenerates every Pigeon output (Dart, Kotlin, Swift) from app/pigeons/*.dart.
# Run from anywhere after `flutter pub get`. CI runs this and fails when it
# changes any tracked file (see .github/workflows/README.md).
set -euo pipefail
cd "$(dirname "$0")/.."

for input in pigeons/*.dart; do
  dart run pigeon --input "$input"
done

# Pigeon's Dart output is not always dart-format clean, and CI checks format.
dart format pigeons lib/core/platform
