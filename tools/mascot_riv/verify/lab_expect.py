#!/usr/bin/env python3
"""Derives verify/expectations.json from the Motion Lab: for every state, the range each node
property must sweep (min/max, Rive units) while the mood runs, sampled straight from the Lab's
CSS (labcss.eval_anim) at 120 Hz.  check.mjs compares the .riv, played by the official runtime,
against it.  Usage: python3 lab_expect.py > expectations.json"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import fx  # noqa: E402
import labcss as L  # noqa: E402
import motion  # noqa: E402
import scene  # noqa: E402
from generate import STATES  # noqa: E402

LAB = L.Lab()
STEP = 1 / 120


def rng(samples):
    return [min(samples), max(samples)]


def node_ranges(node, series):
    """series: [tf dict] over time -> {comp: [min, max]} in Rive units (rest included)."""
    rx, ry = scene.rest(node)
    out = {}
    for comp, fn in (("x", lambda s: rx + s["x"]), ("y", lambda s: ry + s["y"]),
                     ("rotation", lambda s: math.radians(s["rot"])),
                     ("scaleX", lambda s: s["sx"] * math.cos(math.radians(s["ry"]))), ("scaleY", lambda s: s["sy"])):
        out[comp] = rng([fn(s) for s in series])
    return out


def sample_el(mood, el, D):
    st = LAB.style(mood, el)
    a = L.parse_animation(st.get("animation"))
    base = L.parse_transform(st.get("transform"))
    if a and a["name"] in ("talk", "blink"):
        a = None
    series = []
    n = int(D / STEP) + 1
    for i in range(n):
        t = i * STEP
        tf = None
        if a:
            tf, _ = L.eval_anim(LAB, a, t, base)
        series.append(tf or base)
    return series


def main():
    body, _ = motion.build_body()
    bodyD = {m: a["D"] for m, a in body.items()}
    states = {}
    for i, (lab_id, nm) in enumerate(STATES):
        D, kind = motion.mood_spec(lab_id)
        nodes = {}
        for el, node in list(motion.BODY_NODE.items()):
            nodes[node] = node_ranges(node, sample_el(lab_id, el, D))
        bst, dst = LAB.style(lab_id, "breath"), LAB.style("default", "breath")
        if bst.get("animation") != dst.get("animation"):
            nodes["breath"] = node_ranges("breath", sample_el(lab_id, "breath", D))
        fxn = {}
        fxD = None
        if lab_id in fx.FX_MOODS:
            fxD, fkind = fx.mood_D(lab_id, bodyD)
            for it in fx.ITEMS:
                if it["mood"] != lab_id:
                    continue
                series = []
                for a, vars, steady in it["anims"]:
                    for k in range(int(fxD / STEP) + 1):
                        t = k * STEP
                        if steady:
                            aa = dict(a, delay=0.0, fill="both")
                            tf, _ = L.eval_anim(LAB, aa, (t - a["delay"]) % a["dur"], None, it["base_op"], vars)
                        else:
                            tf, _ = L.eval_anim(LAB, a, t, None, it["base_op"], vars)
                        series.append(tf or L.IDENT)
                if series:
                    fxn[it["name"]] = node_ranges(it["name"], series)
        states[str(i)] = {"lab": lab_id, "name": nm, "D": D, "kind": kind, "fxD": fxD, "nodes": nodes, "fx": fxn}
    rest = {n: {"x": scene.rest(n)[0], "y": scene.rest(n)[1]} for n, _, _ in scene.NODES}
    ambient = {
        "breath": node_ranges("breath", [L.parse_transform("scale(1,1)"), L.parse_transform("scale(1.012,1.022)")]),
        "tail": node_ranges("tail", [L.parse_transform("rotate(0)"), L.parse_transform("rotate(-7deg)")]),
        "blinkScaleY": [0.08, 1.0],
        "jaw": node_ranges("jaw", [L.parse_transform("rotate(0)"), L.parse_transform("rotate(-8deg)")]),
    }
    json.dump({"source": "docs/02-design/motion/zaghlol-motion.html", "states": states, "rest": rest,
               "ambient": ambient}, sys.stdout, indent=1, sort_keys=True)
    print()


main()
