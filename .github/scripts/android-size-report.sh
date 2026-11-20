#!/usr/bin/env bash
# T-190: Android size report. Usage: android-size-report.sh <tmp dir> <flavor>
# Reads <tmp>/debug-universal.apk, release-universal.apk, split/*.apk, release.aab,
# release-arm64.aab and writes <tmp>/out/sizes.tsv (key<TAB>bytes), report.md and
# per-component breakdowns. Text only: nothing here is a binary.
set -uo pipefail
T="$1"; FLAVOR="$2"; OUT="$T/out"; TSV="$OUT/sizes.tsv"; MD="$OUT/report.md"
: > "$TSV"; : > "$MD"
size() { stat -c %s "$1"; }
mb() { awk -v b="$1" 'BEGIN{printf "%.2f", b/1048576}'; }
rec() { printf '%s\t%s\n' "$1" "$2" >> "$TSV"; printf '| %s | %s | %s MB |\n' "$1" "$2" "$(mb "$2")" >> "$MD"; }
{ echo "## Android $FLAVOR sizes"; echo; echo "| artifact | bytes | MB (MiB) |"; echo "|---|---|---|"; } >> "$MD"

rec "android.$FLAVOR.debug_universal_apk" "$(size "$T/debug-universal.apk")"
rec "android.$FLAVOR.release_universal_apk" "$(size "$T/release-universal.apk")"
for f in "$T"/split/*.apk; do
  abi=$(basename "$f" | grep -oE 'arm64-v8a|armeabi-v7a|x86_64')
  [ -n "$abi" ] || continue
  rec "android.$FLAVOR.release_split_apk.$abi" "$(size "$f")"
  # apkanalyzer's download-size is the compressed (gzip) estimate of what Play sends for this APK.
  dl=$("$APKANALYZER" apk download-size "$f" 2>/dev/null || true)
  [[ "$dl" =~ ^[0-9]+$ ]] && rec "android.$FLAVOR.apk_download_estimate.$abi" "$dl"
done
rec "android.$FLAVOR.release_aab" "$(size "$T/release.aab")"
rec "android.$FLAVOR.release_aab_arm64_only" "$(size "$T/release-arm64.aab")"

# Per-device download size (what Play serves) from the AAB.
JAR="$T/tools/bundletool.jar"
for abi in arm64-v8a armeabi-v7a x86_64; do
  spec="$T/spec-$abi.json"
  printf '{"supportedAbis":["%s"],"supportedLocales":["en","ar"],"deviceFeatures":[],"glExtensions":[],"screenDensity":420,"sdkVersion":34}\n' "$abi" > "$spec"
  apks="$T/$abi.apks"
  if java -jar "$JAR" build-apks --bundle="$T/release.aab" --output="$apks" --overwrite \
       --ks="$T/tools/size.jks" --ks-pass=pass:sizepass --ks-key-alias=size --key-pass=pass:sizepass > "$OUT/bundletool-build-$abi.log" 2>&1; then
    java -jar "$JAR" get-size total --apks="$apks" --device-spec="$spec" > "$OUT/bundletool-size-$abi.csv" 2>> "$OUT/bundletool-build-$abi.log"
    echo "bundletool get-size ($abi):"; cat "$OUT/bundletool-size-$abi.csv"; tail -n 3 "$OUT/bundletool-build-$abi.log"
    max=$(tail -n 1 "$OUT/bundletool-size-$abi.csv" | cut -d, -f2)
    [[ "$max" =~ ^[0-9]+$ ]] && rec "android.$FLAVOR.play_download.$abi" "$max"
  else
    echo "::warning::bundletool build-apks failed for $abi: $(tail -n 5 "$OUT/bundletool-build-$abi.log" | tr '\n' '|')"
  fi
done

# Component breakdown of an archive (compressed bytes, by category).
breakdown() { # <zip> <label>
  echo; echo "### $2 (compressed bytes by component)"; echo; echo '```'
  unzip -v "$1" | awk 'NR>3 && NF>=8 && $1 ~ /^[0-9]+$/ {
    name=$NF; c=$3; n=name
    if (n ~ /^lib\//)                { split(n,p,"/"); k="lib/" p[2] "/" p[3] }
    else if (n ~ /classes[0-9]*\.dex$/) k="dex"
    else if (n ~ /^assets\/flutter_assets\//) { k="assets/flutter_assets" }
    else if (n ~ /^assets\//)        k="assets/other"
    else if (n ~ /^res\//)           k="res"
    else if (n ~ /resources\.arsc/)  k="resources.arsc"
    else if (n ~ /^base\/lib\//)     { split(n,p,"/"); k="lib/" p[3] "/" p[4] }
    else if (n ~ /^base\/dex\//)     k="dex"
    else if (n ~ /^base\/assets\/flutter_assets/) k="assets/flutter_assets"
    else if (n ~ /^base\/assets\//)  k="assets/other"
    else if (n ~ /^base\/res\//)     k="res"
    else                             k="other"
    s[k]+=c; u[k]+=$1 }
    END { for (k in s) printf "%12d  %12d  %s\n", s[k], u[k], k }' | sort -rn | head -n 40
  echo '```'
}
{
  echo; echo "Columns: compressed bytes, uncompressed bytes, component."
  breakdown "$T/release-universal.apk" "release universal APK"
  for f in "$T"/split/*.apk; do breakdown "$f" "$(basename "$f")"; done
  breakdown "$T/release.aab" "release AAB (all ABIs)"
  breakdown "$T/debug-universal.apk" "debug universal APK"
} >> "$MD"

# Biggest single files in the arm64 split.
A64=$(ls "$T"/split/*arm64-v8a*.apk 2>/dev/null | head -n 1)
if [ -n "$A64" ]; then
  { echo; echo "### 25 largest files in the arm64 release APK (compressed bytes)"; echo; echo '```'
    unzip -v "$A64" | awk 'NR>3 && $1 ~ /^[0-9]+$/ {printf "%12d  %12d  %s\n",$3,$1,$NF}' | sort -rn | head -n 25; echo '```'; } >> "$MD"
  # Per-package dex size (apkanalyzer), best effort.
  { echo; echo "### dex: top 40 defined packages by size (arm64 APK, apkanalyzer)"; echo; echo '```'
    "$APKANALYZER" dex packages --defined-only "$A64" 2>/dev/null | awk '$1=="P"{print}' | sort -k5 -rn | head -n 40; echo '```'; } >> "$MD"
  { echo; echo "### apkanalyzer summary (arm64 APK)"; echo '```'
    echo "file-size:     $("$APKANALYZER" apk file-size "$A64" 2>/dev/null)"
    echo "download-size: $("$APKANALYZER" apk download-size "$A64" 2>/dev/null)"; echo '```'; } >> "$MD"
fi
cat "$MD" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$MD"
