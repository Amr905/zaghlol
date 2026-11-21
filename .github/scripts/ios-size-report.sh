#!/usr/bin/env bash
# T-190: iOS size report. Usage: ios-size-report.sh <tmp dir> <path to Runner.app>
set -uo pipefail
T="$1"; APP="$2"; OUT="$T/out"; TSV="$OUT/sizes.tsv"; MD="$OUT/report.md"
: > "$TSV"; : > "$MD"
mb() { awk -v b="$1" 'BEGIN{printf "%.2f", b/1048576}'; }
IPA="$T/ipa/Zaghlol-UNSIGNED.ipa"
ipa=$(stat -f %z "$IPA" 2>/dev/null || stat -c %s "$IPA")
printf 'ios.release_ipa_unsigned\t%s\n' "$ipa" >> "$TSV"
{
  echo "## iOS prod sizes"; echo
  echo "Unsigned IPA (zip of Runner.app, arm64 only): $ipa bytes = $(mb "$ipa") MB."
  echo "The App Store download size is not measurable without signing (App Thinning report needs"
  echo "an exported, signed archive); the compressed IPA is the closest proxy and slightly over-states it."
  echo; echo "### Runner.app by component (uncompressed KiB)"; echo '```'
  du -sk "$APP"/* "$APP"/Frameworks/* "$APP"/PlugIns/* 2>/dev/null | sort -rn | head -n 40
  echo '```'
  echo; echo "### Mach-O slices"; echo '```'
  for f in "$APP"/Runner "$APP"/Frameworks/*.framework/*; do [ -f "$f" ] && file "$f" | head -n 1; done 2>/dev/null | head -n 40
  echo '```'
  echo; echo "### 25 largest files in the IPA (compressed bytes)"; echo '```'
  unzip -v "$IPA" | awk 'NR>3 && $1 ~ /^[0-9]+$/ {printf "%12d  %12d  %s\n",$3,$1,$NF}' | sort -rn | head -n 25
  echo '```'
} >> "$MD"
cat "$MD" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$MD"
