#!/usr/bin/env python3
"""Generate app/assets/rive/zaghlol.riv (Captain Zaghlol) from the rig SVG.

Deterministic: no timestamps, no randomness. Usage: python3 generate.py [out.riv]
Also writes moods.json (timings and probe poses used by verify/).
"""
import json
import math
import sys
from pathlib import Path

from rig import parse_svg, GROUP_ORDER
from rivefile import RiveFile
from motion import build_motion, REST, NODES, KEYED, MOODS

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SVG = ROOT / "docs/02-design/brand/zaghlol-mascot-rig.svg"
OUT = ROOT / "app/assets/rive/zaghlol.riv"

ART = 1000.0
S = 0.85  # svg -> artboard scale, leaves headroom for hops
OFF = (101.5, 115.0)  # artboard offset of svg (-10, -10)


def world(p):
    return ((p[0] + 10) * S + OFF[0], (p[1] + 10) * S + OFF[1])


# Pivot (svg coords) and parent of every named node. Order = hierarchy build order.
PIVOT = {
    "character": (455, 940),
    "face": (440, 300),
    "tail": (766, 600),
    "wing": (225, 560),
    "browL": (327, 135),
    "browR": (533, 151),
    "eyeL": (317, 219),
    "eyeR": (511, 236),
    "jaw": (430, 280),
    "beak": (430, 275),
    "cere": (397, 245),
}
PARENT = {"face": "character", "tail": "character", "wing": "character",
          "browL": "face", "browR": "face", "eyeL": "face", "eyeR": "face",
          "jaw": "face", "beak": "face", "cere": "face"}
JOIN = {"round": 1, "miter": 0, "bevel": 2}


def argb(hexs):
    return 0xFF000000 | int(hexs.lstrip("#"), 16)


def add_shape(f, parent_slot, shape, pivot_svg, name):
    a = shape["attrs"]
    sh = f.add("Shape", name=name, parentId=parent_slot)
    for si, (start, segs) in enumerate(shape["subpaths"]):
        # vertices: start + each seg end except the last (== start, closes the loop)
        pts = [start] + [e for (_, e) in segs[:-1]]
        n = len(pts)
        assert segs[-1][1] == start
        # cubic handles from quadratics: c1 = p0 + 2/3 (c - p0); c2 = p1 + 2/3 (c - p1)
        outs, ins = [None] * n, [None] * n
        for i, (c, e) in enumerate(segs):
            p0 = pts[i]
            p1 = pts[(i + 1) % n]
            outs[i] = (S * 2 / 3 * (c[0] - p0[0]), S * 2 / 3 * (c[1] - p0[1]))
            ins[(i + 1) % n] = (S * 2 / 3 * (c[0] - p1[0]), S * 2 / 3 * (c[1] - p1[1]))
        path = f.add("PointsPath", parentId=sh, isClosed=True)
        for i, p in enumerate(pts):
            x = S * (p[0] - pivot_svg[0])
            y = S * (p[1] - pivot_svg[1])
            ox, oy = outs[i]
            ix, iy = ins[i]
            f.add("CubicDetachedVertex", parentId=path, x=x, y=y,
                  inRotation=math.atan2(iy, ix), inDistance=math.hypot(ix, iy),
                  outRotation=math.atan2(oy, ox), outDistance=math.hypot(ox, oy))
    fill = f.add("Fill", parentId=sh, fillRule=1 if a.get("fill-rule") == "evenodd" else 0)
    f.add("SolidColor", parentId=fill, colorValue=argb(a["fill"]))
    if "stroke" in a:
        st = f.add("Stroke", parentId=sh, thickness=float(a["stroke-width"]) * S,
                   join=JOIN[a.get("stroke-linejoin", "miter")])
        f.add("SolidColor", parentId=st, colorValue=argb(a["stroke"]))


def node_xy(name):
    p = PIVOT[name]
    par = PARENT.get(name)
    if par is None:
        w = world(p)
        return w
    wp, wc = world(p), world(PIVOT[par])
    return (wp[0] - wc[0], wp[1] - wc[1])


def main(out):
    groups = parse_svg(SVG)
    f = RiveFile()
    f.add("Backboard")
    f.add("Artboard", name="Zaghlol", width=ART, height=ART)
    slots = {}
    # hierarchy, in draw order: tail, base, wing, face(brows, eyes, jaw, beak, cere)
    slots["character"] = f.add("Node", name="character", parentId=0, x=node_xy("character")[0],
                               y=node_xy("character")[1])

    def node(name, parent):
        x, y = node_xy(name)
        slots[name] = f.add("Node", name=name, parentId=slots[parent], x=x, y=y)

    for n in ["tail", "wing", "face"]:
        node(n, "character")
    for g in ["browL", "browR", "eyeL", "eyeR", "jaw", "beak", "cere"]:
        node(g, "face")
    # The runtime draws the LAST drawable in the file first (back), so emit shapes
    # front-to-back: reverse of the rig's paint order (tail is the rearmost group).
    owner = {"base": "character"}
    seq = [(g, i, sh) for g in GROUP_ORDER for i, sh in enumerate(groups[g])]
    for g, i, sh in reversed(seq):
        own = owner.get(g, g)
        add_shape(f, slots[own], sh, PIVOT[own], f"{g}{i}")

    # shared easing (cubic ease in-out) -> interpolator slot
    ease = f.add("CubicEaseInterpolator", x1=0.42, y1=0.0, x2=0.58, y2=1.0)

    meta = build_motion(f, slots, ease, node_xy)
    sm = meta["sm"]
    build_state_machine(f, sm)
    data = f.to_bytes()
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_bytes(data)
    meta_out = {k: v for k, v in meta.items() if k != "sm"}
    (HERE / "moods.json").write_text(json.dumps(meta_out, indent=1, sort_keys=True) + "\n")
    print(f"wrote {out} ({len(data)} bytes, {f.slot} components)")


def build_state_machine(f, sm):
    """sm: animation indices {idle, moods:[(index, oneShot/loop/hold, exit_ms)], talkOff, talkOn, still}"""
    f.add("StateMachine", name="ZaghlolAvatar")
    f.add("StateMachineNumber", name="state", value=-1.0)  # input 0
    f.add("StateMachineBool", name="talk", value=False)  # input 1
    f.add("StateMachineBool", name="reduceMotion", value=False)  # input 2
    IN_STATE, IN_TALK, IN_REDUCE = 0, 1, 2

    # ---- layer 0: moods. state indices: 0 entry, 1 any, 2 exit, 3 idle,
    # 4..18 mood k -> 4+k, then rest states for one-offs.
    moods = sm["moods"]
    n = len(moods)
    IDLE = 3
    MOOD = lambda k: 4 + k
    rest_of = {}
    nxt = 4 + n
    for k, m in enumerate(moods):
        if m["kind"] == "oneShot":
            rest_of[k] = nxt
            nxt += 1

    def to_mood(k_to, ms=100):
        f.add("StateTransition", stateToId=MOOD(k_to), duration=ms)
        f.add("TransitionNumberCondition", inputId=IN_STATE, opValue=0, value=float(k_to))

    def to_idle_on_negative(ms=150):
        f.add("StateTransition", stateToId=IDLE, duration=ms)
        f.add("TransitionNumberCondition", inputId=IN_STATE, opValue=4, value=0.0)  # state < 0

    f.add("StateMachineLayer", name="moods")
    f.add("EntryState")
    f.add("StateTransition", stateToId=IDLE, duration=0)
    f.add("AnyState")
    f.add("ExitState")
    f.add("AnimationState", animationId=sm["idle"])  # IDLE
    for k in range(n):
        to_mood(k)
    for k, m in enumerate(moods):
        f.add("AnimationState", animationId=m["anim"])  # MOOD(k)
        for j in range(n):
            if j != k:
                to_mood(j, 120)
        to_idle_on_negative()
        if m["kind"] == "oneShot":
            f.add("StateTransition", stateToId=rest_of[k], duration=250, flags=4, exitTime=m["exit_ms"])
    for k in sorted(rest_of):
        f.add("AnimationState", animationId=sm["idle"])  # rest_k
        for j in range(n):
            if j != k:
                to_mood(j, 120)
        to_idle_on_negative()

    # ---- layer 1: talk (jaw/beak/cere only)
    f.add("StateMachineLayer", name="talk")
    f.add("EntryState")
    f.add("StateTransition", stateToId=3, duration=0)
    f.add("AnyState")
    f.add("ExitState")
    f.add("AnimationState", animationId=sm["talkOff"])  # 3
    f.add("StateTransition", stateToId=4, duration=80)
    f.add("TransitionBoolCondition", inputId=IN_TALK, opValue=0)
    f.add("AnimationState", animationId=sm["talkOn"])  # 4
    f.add("StateTransition", stateToId=3, duration=120)
    f.add("TransitionBoolCondition", inputId=IN_TALK, opValue=1)

    # ---- layer 2: reduceMotion holds the rest pose while true
    f.add("StateMachineLayer", name="reduceMotion")
    f.add("EntryState")
    f.add("StateTransition", stateToId=3, duration=0)
    f.add("AnyState")
    f.add("ExitState")
    f.add("AnimationState")  # 3: no animation (lower layers show through)
    f.add("StateTransition", stateToId=4, duration=100)
    f.add("TransitionBoolCondition", inputId=IN_REDUCE, opValue=0)
    f.add("AnimationState", animationId=sm["still"])  # 4
    f.add("StateTransition", stateToId=3, duration=100)
    f.add("TransitionBoolCondition", inputId=IN_REDUCE, opValue=1)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else OUT)
