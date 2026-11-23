#!/usr/bin/env python3
"""Extract the Rive core type/property table from a rive-runtime checkout.

Usage: extract_defs.py <rive-runtime-dir> > rive_defs.json
The runtime's generated headers (include/rive/generated/**/*_base.hpp) carry
typeKey, propertyKey and field-type ids; no editor and no network are needed.
Only the types the mascot generator uses (and their ancestors) are kept.
"""
import json, re, subprocess, sys
from pathlib import Path

USED = """Backboard Artboard Node Shape PointsPath StraightVertex CubicDetachedVertex
Fill SolidColor Stroke LinearAnimation KeyedObject KeyedProperty KeyFrameDouble
CubicEaseInterpolator StateMachine StateMachineNumber StateMachineBool
StateMachineLayer AnimationState EntryState AnyState ExitState StateTransition
TransitionNumberCondition TransitionBoolCondition""".split()

# Field type per core field type (runtime ids: 0 uint, 1 string, 2 float, 3 color, 4 bool)
KIND = {"Double": "float", "Uint": "uint", "Id": "uint", "Int": "uint", "Bool": "bool",
        "String": "string", "Color": "color", "Bytes": "string", "FractionalIndex": "uint"}


def main(root):
    root = Path(root)
    classes = {}
    for f in (root / "include/rive/generated").rglob("*_base.hpp"):
        t = f.read_text()
        m = re.search(r"class (\w+)Base\s*:\s*public (\w+)", t)
        if not m:
            continue
        name, sup = m.group(1), m.group(2)
        tk = re.search(r"typeKey = (\d+);", t)
        props = {}
        for pm in re.finditer(r"static const uint16_t (\w+)PropertyKey = (\d+);", t):
            pname, key = pm.group(1), int(pm.group(2))
            mm = re.search(r"case " + pname + r"PropertyKey:(?:(?!case ).)*?Core(\w+?)Type::(?:runtimeD|d)eserialize", t, re.S)
            kind = KIND.get(mm.group(1)) if mm else None
            if kind is None:
                kind = "uint" if mm is None else "?" + mm.group(1)  # Id fields use another reader: varuint
            props[pname] = [key, kind]
        classes[name] = {"super": sup, "typeKey": int(tk.group(1)) if tk else None, "props": props}
    keep = set()
    for u in USED:
        n = u
        while n in classes:
            keep.add(n)
            n = classes[n]["super"]
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    out = {"source": "rive-app/rive-runtime include/rive/generated", "commit": commit,
           "classes": {k: classes[k] for k in sorted(keep)}}
    json.dump(out, sys.stdout, indent=1, sort_keys=True)


if __name__ == "__main__":
    main(sys.argv[1])
