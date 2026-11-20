#!/usr/bin/env python3
"""Self-test for gradle-deps-to-lockfile.py (BOM-managed lines must keep their resolved version). Stdlib only."""
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("conv", os.path.join(here, "gradle-deps-to-lockfile.py"))
conv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(conv)

CASES = {
    "androidx.core:core:1.13.0": ("androidx.core", "core", "1.13.0"),
    "androidx.core:core:1.12.0 -> 1.13.0 (*)": ("androidx.core", "core", "1.13.0"),
    "com.google.firebase:firebase-bom -> 33.1.0": ("com.google.firebase", "firebase-bom", "33.1.0"),
    "io.netty:netty-codec -> 4.1.110.Final (*)": ("io.netty", "netty-codec", "4.1.110.Final"),
    "org.jetbrains.kotlin:kotlin-stdlib:{strictly 2.0.0} -> 2.0.21 (c)": ("org.jetbrains.kotlin", "kotlin-stdlib", "2.0.21"),
    "a.b:old:1.0 -> c.d:new:2.0": ("c.d", "new", "2.0"),
    "g:a:[1.0,2.0)": None,
    "g:a:{strictly 1.0}": None,
    "project :app": None,
}
bad = [(k, conv.parse_line(k), v) for k, v in CASES.items() if conv.parse_line(k) != v]
for b in bad:
    print("FAIL", b)
if bad:
    sys.exit(1)
print(f"{len(CASES)} cases ok")
