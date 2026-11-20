#!/usr/bin/env python3
"""T-192 (T-175 pass 1, scan pins): turn `gradlew :app:dependencies` output into a gradle.lockfile for osv-scanner.

  gradle-deps-to-lockfile.py <out-gradle.lockfile> <deps.txt>...

Reads the dependency trees printed by Gradle (the resolved graph, including transitive artifacts and plugin
classpaths), takes the final version of each `group:artifact:requested -> resolved` line, and writes
`group:artifact:version=<configs>` lines (the format osv-scanner parses as gradle.lockfile).
Fails when no coordinate is found (an empty graph must not look like a clean scan). Stdlib only.
"""
import re
import sys

COORD = re.compile(r"([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+):([^\s:]+?)(?:\s+->\s+([^\s]+))?(?:\s+\(\*\)|\s+\(c\)|\s+\(n\))?\s*$")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    found = set()
    for path in argv[2:]:
        with open(path, encoding="utf-8") as f:
            for line in f:
                # Tree lines start with "+--- ", "\--- " or "|    "; skip project() and FAILED entries.
                if "--- " not in line or "project :" in line or "FAILED" in line:
                    continue
                m = COORD.search(line.split("--- ", 1)[1].rstrip())
                if not m:
                    continue
                group, artifact, requested, resolved = m.groups()
                version = resolved or requested
                # A range or a "{strictly ...}" constraint is not a version; a bare "->" target is already resolved.
                if not re.match(r"^[0-9][A-Za-z0-9_.\-+]*$", version):
                    continue
                if resolved and ":" in resolved:  # "-> group:artifact:version" substitution
                    g, a, v = resolved.split(":")[:3]
                    group, artifact, version = g, a, v
                found.add(f"{group}:{artifact}:{version}")
    if not found:
        print("::error::no Gradle coordinates found in the dependency graph; the scan would be vacuous")
        return 1
    with open(argv[1], "w", encoding="utf-8") as out:
        out.write("# Generated from :app:dependencies by gradle-deps-to-lockfile.py (T-192). Not committed.\n")
        for c in sorted(found):
            out.write(f"{c}=exported\n")
    print(f"{len(found)} coordinates")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
