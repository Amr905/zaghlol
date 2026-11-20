#!/usr/bin/env bash
# Fails when `flutter analyze` does not load the riverpod_lint analyzer plugin (T-193 AC4, FU-263 a).
#
# Why: riverpod_lint 3.x is an analyzer plugin read from the workspace root analysis_options.yaml. If it silently fails to load
# (a version it cannot resolve, a plugin that did not build, a changed workspace layout), `flutter analyze` stays green and every
# riverpod_lint rule is off. BUG-007: app-ci was green while a clean local analyze reported missing_provider_scope.
# The check analyzes a file that breaks one rule on purpose and demands that rule's diagnostic. Run from the repository root.
set -u

probe_src=.github/probes/riverpod_lint_probe.dart.txt
probe=app/lib/zz_riverpod_lint_probe.dart
log=$(mktemp)
trap 'rm -f "$probe" "$log"' EXIT

cp "$probe_src" "$probe"
# The probe has an expected finding, so a non-zero exit of analyze is normal here; only the output matters.
flutter analyze "$probe" > "$log" 2>&1

if grep -q 'riverpod_lint/missing_provider_scope' "$log"; then
  echo "riverpod_lint is active: the probe produced riverpod_lint/missing_provider_scope."
  exit 0
fi

echo "::error::flutter analyze did not report riverpod_lint/missing_provider_scope for the probe: the riverpod_lint plugin is not loaded, so none of its rules run. Check 'plugins:' in analysis_options.yaml (workspace root) and the plugin build log."
tail -n 20 "$log"
exit 1
