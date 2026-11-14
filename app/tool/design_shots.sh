#!/usr/bin/env bash
# Renders the main screens with real Arabic text (390x844 @2x, ar + light) to
# app/build/design_shots/<screen>.png. Not committed. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
export DESIGN_SHOTS=1
flutter test --tags design_shot test/tool/design_shots_test.dart "$@"
echo "Shots: $(pwd)/build/design_shots"
