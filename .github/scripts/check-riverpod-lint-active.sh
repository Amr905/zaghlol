#!/usr/bin/env bash
# Fails when `flutter analyze` does not load the riverpod_lint analyzer plugin (T-193 AC4, FU-263 a).
#
# Why: riverpod_lint 3.x is an analyzer plugin read from the workspace root analysis_options.yaml. If it silently fails to load
# (a version it cannot resolve, a plugin that did not build, a changed workspace layout), `flutter analyze` stays green and every
# riverpod_lint rule is off. BUG-007: app-ci was green while a clean local analyze reported missing_provider_scope.
# The check adds a file that breaks two rules on purpose, runs the same whole-workspace `flutter analyze` as app-ci (analyzing
# one path alone did not report plugin diagnostics on CI), and demands a riverpod_lint diagnostic on that file. Run from the
# repository root.
set -u

probe_src=.github/probes/riverpod_lint_probe.dart.txt
probe=app/lib/zz_riverpod_lint_probe.dart
log=$(mktemp)
trap 'rm -f "$probe" "$log"' EXIT

cp "$probe_src" "$probe"
# The probe has an expected finding, so a non-zero exit of analyze is normal here; only the output matters.
flutter analyze > "$log" 2>&1

if grep -E 'zz_riverpod_lint_probe\.dart' "$log" | grep -Eq '(missing_provider_scope|avoid_public_notifier_properties)'; then
  echo "riverpod_lint is active: the probe produced its diagnostics."
  exit 0
fi

echo "::error::flutter analyze did not report a riverpod_lint diagnostic (missing_provider_scope, avoid_public_notifier_properties) for the probe: the riverpod_lint plugin is not loaded, so none of its rules run. Check 'plugins:' in analysis_options.yaml (workspace root) and the plugin build log."
tail -n 20 "$log"
exit 1
