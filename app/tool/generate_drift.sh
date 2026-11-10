#!/usr/bin/env bash
# T-016: regenerates the drift code and the schema dumps for
# app/lib/core/db/schema/ (database-schema.md §4). CI runs this and fails when
# it changes any tracked file (app-ci "drift generated files and schema dump").
#
# drift_dev can't resolve inside the pub workspace (see
# tools/drift_codegen/pubspec.yaml), so:
#   1. tools/drift_codegen gets app/build.yaml and a copy of the schema folder
#      (*.dart and *.drift; T-017: any drift_dev warning fails the run)
#      at the same relative path, runs build_runner and hands back *.g.dart;
#   2. the drift_dev CLI, run with the codegen package's resolution, reads the
#      app directory (app/build.yaml) and writes app/drift_schemas/. With more
#      than one schema version it also writes the stepByStep helper
#      (lib/core/db/schema/app_schema.steps.dart) and the test schemas
#      (test/core/db/migrations/).
#      `--no-test`: the generated test template needs drift_dev at runtime;
#      the app's own migration tests use test/core/db/migration_harness.dart.
#   3. dart format.
#
# Usage: app/tool/generate_drift.sh   (needs `dart` on PATH and pub access, or
# a warm pub cache; the codegen lock is enforced).
set -euo pipefail
app="$(cd "$(dirname "$0")/.." && pwd)"
gen="$(cd "$app/../tools/drift_codegen" && pwd)"
schema_rel="lib/core/db/schema"

(cd "$gen" && dart pub get --enforce-lockfile > /dev/null)

# The copies are scratch: never leave them for format/analyze to find.
cleanup() { rm -rf "$gen/lib" "$gen/build.yaml"; }
trap cleanup EXIT

# 1. build_runner in the codegen package on an exact copy of the schema folder.
rm -rf "$gen/lib"
mkdir -p "$gen/$schema_rel"
cp "$app/build.yaml" "$gen/build.yaml"
find "$app/$schema_rel" -maxdepth 1 \( -name '*.dart' -o -name '*.drift' \) ! -name '*.g.dart' -exec cp {} "$gen/$schema_rel/" \;
(cd "$gen" && dart run build_runner build --delete-conflicting-outputs > "$gen/.dart_tool/build_runner.log" 2>&1) || {
  cat "$gen/.dart_tool/build_runner.log"
  exit 1
}
# T-017: a drift analysis warning (unknown table, unparsable SQL) still
# "builds" but silently drops the entity: treat it as an error.
if grep -q '^W drift_dev' "$gen/.dart_tool/build_runner.log"; then
  grep -A8 '^W drift_dev' "$gen/.dart_tool/build_runner.log" >&2
  echo "drift_dev reported warnings" >&2
  exit 1
fi
find "$app/$schema_rel" -maxdepth 1 -name '*.g.dart' -delete
find "$gen/$schema_rel" -maxdepth 1 -name '*.g.dart' -exec cp {} "$app/$schema_rel/" \;

# 2. drift_dev CLI against the app directory.
drift_dev_root=$(python3 -I -c '
import json, sys, os
cfg = json.load(open(sys.argv[1]))
for p in cfg["packages"]:
    if p["name"] == "drift_dev":
        root = p["rootUri"]
        if root.startswith("file://"):
            root = root[len("file://"):]
        else:
            root = os.path.normpath(os.path.join(os.path.dirname(sys.argv[1]), root))
        print(root)
' "$gen/.dart_tool/package_config.json")
[ -f "$drift_dev_root/bin/drift_dev.dart" ] || { echo "drift_dev not found in tools/drift_codegen" >&2; exit 1; }
(cd "$app" && dart --packages="$gen/.dart_tool/package_config.json" \
  "$drift_dev_root/bin/drift_dev.dart" make-migrations --no-test)

# 3. Format what was generated.
dart format "$app/$schema_rel" "$app/drift_schemas" > /dev/null
if [ -d "$app/test/core/db/migrations" ]; then
  dart format "$app/test/core/db/migrations" > /dev/null
fi
