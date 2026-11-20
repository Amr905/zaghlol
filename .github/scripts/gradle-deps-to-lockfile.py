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

MARKERS = re.compile(r"(\s+\((?:\*|c|n)\))+\s*$")
VERSION = re.compile(r"^[0-9][A-Za-z0-9_.\-+]*$")


def parse_line(text):
    """Return (group, artifact, version) for one tree entry, or None.

    Handles `g:a:1.0`, `g:a:1.0 -> 1.1`, BOM-managed `g:a -> 1.1`, `g:a:{strictly 1.0} -> 1.1` and
    `g:a:1.0 -> g2:a2:2.0` (substitution). Ranges and unresolved constraints are not versions.
    """
    text = MARKERS.sub("", text.strip())
    left, _, right = text.partition(" -> ")
    parts = left.strip().split(":")
    if len(parts) < 2 or not all(re.match(r"^[A-Za-z0-9_.\-]+$", x) for x in parts[:2]):
        return None
    group, artifact = parts[0], parts[1]
    version = parts[2] if len(parts) > 2 else ""
    right = right.strip()
    if right:
        if ":" in right:  # "-> group:artifact:version" substitution
            r = right.split(":")
            if len(r) < 3:
                return None
            group, artifact, version = r[0], r[1], r[2]
        else:
            version = right
    return (group, artifact, version) if VERSION.match(version) else None


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
                c = parse_line(line.split("--- ", 1)[1])
                if c:
                    found.add(":".join(c))
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
