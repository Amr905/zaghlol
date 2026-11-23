#!/usr/bin/env python3
"""Generate app/assets/rive/zaghlol.riv (Captain Zaghlol) from the rig SVG and the Motion Lab.

Deterministic: no timestamps, no randomness (the Lab's Math.random is a fixed seed).
Usage: python3 generate.py [out.riv]. Also writes moods.json (what the verifier reads).
"""
import json
import math
import sys
from pathlib import Path

import fx
import labcss as L
import motion
import scene
import shapes as S
from rig import parse_svg
from rivefile import RiveFile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SVG = ROOT / "docs/02-design/brand/zaghlol-mascot-rig.svg"
OUT = ROOT / "app/assets/rive/zaghlol.riv"
FPS = 60
INK = "#1d4039"

# Lab mood id -> ZaghlolMoment index/name (08-mascot-motion section 1, mascot-rive-handoff.md)
STATES = [("hello", "tourGuide"), ("proud", "proud"), ("shock", "shocked"), ("detect", "detective"),
          ("explain", "professor"), ("listen", "listening"), ("think", "thinking"), ("scan", "scanning"),
          ("count", "counting"), ("saved", "saved"), ("payday", "payday"), ("oops", "oops"),
          ("sleep", "sleep"), ("pull", "pull"), ("tap", "tap")]


# ---------------------------------------------------------------- shapes
def rig_shapes(groups, name):
    out = []
    for sh in groups[name]:
        a = sh["attrs"]
        subs = []
        for start, segs in sh["subpaths"]:
            subs.append((True, S._cubic_nodes(start, [("Q", c, e) for c, e in segs], True)))
        st = None
        if "stroke" in a:
            st = S.stroke(S.argb(a["stroke"]), float(a["stroke-width"]), "butt", a.get("stroke-linejoin", "miter"))
        out.append(S.shape(subs, S.argb(a["fill"]), 1 if a.get("fill-rule") == "evenodd" else 0, st))
    return out


def path_shape(d, fill=None, stroke=None, rule=0):
    return S.shape(S.parse_path(d), fill, rule, stroke)


def circle(cx, cy, r, fill=None, stroke=None):
    return S.shape([S.ellipse(cx, cy, r, r)], fill, 0, stroke)


def lab_shapes(groups):
    """(owner node, spec) in paint order, back to front, as drawn by birdSVG() in the Lab."""
    ink = S.argb(INK)
    P = []
    P.append(("stage", S.shape([S.ellipse(460, 948, 250, 24)], S.argb("#0F5E43", 0.16))))
    P += [("tail", s) for s in rig_shapes(groups, "tail")]
    P += [("breath", s) for s in rig_shapes(groups, "base")]
    P += [("wingL", s) for s in rig_shapes(groups, "wing")]
    brown = S.argb("#7A4A2A")
    P.append(("pointer", path_shape("M40 420 L-70 290", stroke=S.stroke(brown, 16, "round"))))
    P.append(("pointer", circle(-74, 284, 13, S.argb("#FFB86B"))))
    P += [("brows", s) for s in rig_shapes(groups, "browL") + rig_shapes(groups, "browR")]
    P += [("blinkHappyL", s) for s in rig_shapes(groups, "eyeL")]
    P += [("blinkHappyR", s) for s in rig_shapes(groups, "eyeR")]
    for side, (ex, ey, px, py, hx, hy) in (("L", (315, 214, 305, 222, 312, 211)), ("R", (511, 232, 500, 240, 507, 229))):
        P.append((f"blink{side}", S.shape([S.ellipse(ex, ey, 31, 38)], S.argb("#FFFFFF"), 0, S.stroke(ink, 9))))
        P.append((f"pupils{side}", S.shape([S.ellipse(px, py, 15, 19)], S.argb("#10302A"))))
        P.append((f"pupils{side}", circle(hx, hy, 6.5, S.argb("#FFFFFF"))))
    for d in ("M284 206 Q315 232 346 206", "M480 226 Q511 252 542 226"):
        P.append(("eyeClosed", path_shape(d, stroke=S.stroke(ink, 12, "round"))))
    P += [("jaw", s) for s in rig_shapes(groups, "jaw")]
    P.append(("mouthClosed", path_shape("M334 286 C372 300 412 290 446 258 C450 282 434 304 406 314 C378 322 350 314 334 286Z",
                                         S.argb("#E9A23B"), S.stroke(ink, 9, "butt", "round"))))
    P += [("head", s) for s in rig_shapes(groups, "beak") + rig_shapes(groups, "cere")]
    gl = S.stroke(S.argb("#5B3A24"), 10)
    P.append(("glasses", circle(315, 214, 52, None, gl)))
    P.append(("glasses", circle(511, 232, 52, None, gl)))
    P.append(("glasses", path_shape("M366 210 Q414 196 460 222", stroke=gl)))
    hs = S.stroke(ink, 9, "butt", "round")
    P.append(("hat", path_shape("M240 176 Q440 -90 700 150 Q470 108 240 176Z", S.argb("#9A6A45"), hs)))
    P.append(("hat", path_shape("M200 190 Q460 112 740 162 Q460 150 200 190Z", S.argb("#7A4E30"), hs)))
    P.append(("hat", path_shape("M330 70 q120 -40 250 0", stroke=S.stroke(S.argb("#C59A6E"), 13, "butt", "round"))))
    mg = S.argb("#5B3A24")
    P.append(("mag", circle(560, 262, 64, S.argb("#D2F0FF", 0.35), S.stroke(mg, 16))))
    P.append(("mag", path_shape("M604 310 L664 380", stroke=S.stroke(mg, 24, "round"))))
    P.append(("sweat", path_shape("M640 96 q22 32 0 48 q-22 -16 0 -48Z", S.argb("#7CC7F2"),
                                  S.stroke(S.argb("#2F7FB0"), 6, "butt", "miter"))))
    for it in fx.ITEMS:
        P += [(it["name"], s) for s in it["shapes"]]
    return P


def add_shape(f, parent_slot, spec, pivot, name):
    sh = f.add("Shape", name=name, parentId=parent_slot)
    for closed, verts in spec["subs"]:
        path = f.add("PointsPath", parentId=sh, isClosed=closed)
        for (x, y, hin, hout) in verts:
            f.add("CubicDetachedVertex", parentId=path, x=x - pivot[0], y=y - pivot[1],
                  inRotation=math.atan2(hin[1], hin[0]), inDistance=math.hypot(*hin),
                  outRotation=math.atan2(hout[1], hout[0]), outDistance=math.hypot(*hout))
    if spec["fill"] is not None:
        fill = f.add("Fill", parentId=sh, fillRule=spec["rule"])
        f.add("SolidColor", parentId=fill, colorValue=spec["fill"])
    if spec["stroke"] is not None:
        col, width, cap, join = spec["stroke"]
        st = f.add("Stroke", parentId=sh, thickness=width, cap=cap, join=join)
        f.add("SolidColor", parentId=st, colorValue=col)


# ---------------------------------------------------------------- animations
PROP_KEY = {"x": 13, "y": 14, "rotation": 15, "scaleX": 16, "scaleY": 17, "opacity": 18}
COMP_ORDER = ["x", "y", "rotation", "scaleX", "scaleY", "opacity"]


class Writer:
    def __init__(self, f, slots):
        self.f, self.slots = f, slots
        self.eases = {}
        self.anims = []  # {name, index, D, kind, layer}

    def add_eases(self, all_keys):
        for k in sorted(all_keys):
            if k in ("hold", "linear") or k in self.eases:
                continue
            x1, y1, x2, y2 = (float(v) for v in k.split(","))
            self.eases[k] = self.f.add("CubicEaseInterpolator", x1=x1, y1=y1, x2=x2, y2=y2)

    def emit(self, name, D, kind, tracks, layer, state=None):
        f = self.f
        frames = max(1, round(D * FPS))
        f.add("LinearAnimation", name=name, duration=frames, fps=FPS, loopValue=1 if kind == "loop" else 0)
        idx = f.anim_count
        f.anim_count += 1
        order = {n: i for i, (n, _, _) in enumerate(scene.NODES)}
        by_node = {}
        for (node, comp), pts in tracks.items():
            by_node.setdefault(node, {})[comp] = pts
        for node in sorted(by_node, key=lambda n: order[n]):
            f.add("KeyedObject", objectId=self.slots[node])
            for comp in COMP_ORDER:
                pts = by_node[node].get(comp)
                if pts is None:
                    continue
                f.add("KeyedProperty", propertyKey=PROP_KEY[comp])
                last = -1
                for t, v, e in pts:
                    fr = max(round(t * FPS), last + 1)
                    last = fr
                    if e == "hold":
                        f.add("KeyFrameDouble", frame=fr, value=v, interpolationType=0)
                    elif e == "linear":
                        f.add("KeyFrameDouble", frame=fr, value=v, interpolationType=1)
                    else:
                        f.add("KeyFrameDouble", frame=fr, value=v, interpolationType=2, interpolatorId=self.eases[e])
        self.anims.append({"name": name, "index": idx, "D": D, "kind": kind, "layer": layer, "state": state})
        return idx


def all_ease_keys(anims):
    keys = set()
    for a in anims:
        for pts in a["tracks"].values():
            keys |= {e for _, _, e in pts}
    return keys


# ---------------------------------------------------------------- main
def main(out):
    groups = parse_svg(SVG)
    f = RiveFile()
    f.add("Backboard")
    f.add("Artboard", name="Zaghlol", width=scene.ART, height=scene.ART, clip=True)
    slots = {}
    for name, parent, pivot in scene.NODES:
        x, y = scene.rest(name)
        props = {"name": name, "parentId": slots[parent] if parent else 0, "x": x, "y": y}
        if name == "stage":
            props.update(scaleX=scene.S, scaleY=scene.S)
        if name == "fx":
            props.update(scaleX=scene.K, scaleY=scene.K)
        slots[name] = f.add("Node", **props)
    # The runtime paints the LAST drawable in the file first: write front to back.
    for owner, spec in reversed(lab_shapes(groups)):
        pivot = (0.0, 0.0) if owner.startswith(("think_", "scan_", "count_", "saved_", "payday_", "listen_",
                                                "oops_", "sleep_z", "explain_")) else scene.PIVOT[owner]
        add_shape(f, slots[owner], spec, pivot, owner)

    body, _ = motion.build_body()
    amb = motion.ambient()
    fxa = fx.build_fx({m: a["D"] for m, a in body.items()})
    # the state machine's reset pose: idle body + ambient nodes at rest + props hidden + jaw closed
    still = dict(body["default"]["tracks"])
    for a in amb.values():
        for k, pts in a["tracks"].items():
            rest_v = pts[0][1] if k[1] in ("x", "y") else (1.0 if k[1] in ("scaleX", "scaleY") else 0.0)
            still[k] = [(0.0, rest_v, "hold"), (1.0, rest_v, "hold")]
    still.update(fxa["idle"]["tracks"])
    allanims = list(body.values()) + list(amb.values()) + list(fxa.values()) + [{"tracks": still}]
    w = Writer(f, slots)
    w.add_eases(all_ease_keys(allanims))

    idx = {}
    idx["breath"] = w.emit("breathe", amb["breath"]["D"], "loop", amb["breath"]["tracks"], "breath")
    idx["tail"] = w.emit("wag", amb["tail"]["D"], "loop", amb["tail"]["tracks"], "tail")
    idx["blink"] = w.emit("blink", amb["blink"]["D"], "loop", amb["blink"]["tracks"], "blink")
    idx["idle"] = w.emit("idle", 1.0, "loop", body["default"]["tracks"], "moods")
    moods = []
    for i, (lab_id, nm) in enumerate(STATES):
        a = body[lab_id]
        ai = w.emit(f"mood{i:02d}_{nm}", a["D"], a["kind"], a["tracks"], "moods", i)
        moods.append({"anim": ai, "kind": a["kind"], "exit_ms": round(a["D"] * 1000)})
    idx["idleFx"] = w.emit("idleFx", 1.0, "loop", fxa["idle"]["tracks"], "fx")
    fxm = []
    for i, (lab_id, nm) in enumerate(STATES):
        if lab_id in fxa:
            a = fxa[lab_id]
            ai = w.emit(f"fx{i:02d}_{nm}", a["D"], a["kind"], a["tracks"], "fx", i)
            fxm.append({"anim": ai, "kind": a["kind"], "exit_ms": round(a["D"] * 1000)})
        else:
            fxm.append(None)
    idx["talkOn"] = w.emit("talkOn", amb["talk"]["D"], "loop", amb["talk"]["tracks"], "talk")
    idx["still"] = w.emit("still", 1.0, "loop", still, "reduceMotion")

    build_state_machine(f, idx, moods, fxm)
    data = f.to_bytes()
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_bytes(data)
    meta = {"fps": FPS, "animations": [{k: v for k, v in a.items() if k != "index"} for a in w.anims],
            "crop": {  # artboard rectangle that shows the Lab's 380x400 stage (contact sheets)
                "x": scene.S * scene.FX_U0 + scene.UCENTER * (1 - scene.S),
                "y": scene.S * (scene.FX_V0 - scene.VTOP),
                "w": scene.STAGE_W * scene.K * scene.S, "h": scene.STAGE_H * scene.K * scene.S},
            "states": [{"state": i, "lab": lab, "name": nm} for i, (lab, nm) in enumerate(STATES)]}
    (HERE / "moods.json").write_text(json.dumps(meta, indent=1, sort_keys=True) + "\n")
    print(f"wrote {out} ({len(data)} bytes, {f.slot} components)")


def state_layer(f, name, idle_anim, moods, IN_STATE):
    """A layer driven by `state`: idle, one state per mood (None = stay/return to idle), one-offs
    return to a clone of idle after their length, loops keep looping, `hold` stays."""
    f.add("StateMachineLayer", name=name)
    f.add("EntryState")
    f.add("StateTransition", stateToId=3, duration=0)
    f.add("AnyState")
    f.add("ExitState")
    n = len(moods)
    IDLE = 3
    have = [k for k in range(n) if moods[k] is not None]
    pos = {}
    nxt = 4
    for k in have:
        pos[k] = nxt
        nxt += 1
    rest_of = {}
    for k in have:
        if moods[k]["kind"] == "oneShot":
            rest_of[k] = nxt
            nxt += 1

    def target(k):
        return pos[k] if k in pos else IDLE

    def to_mood(k, ms, frm):
        if frm == k and False:
            return
        f.add("StateTransition", stateToId=target(k), duration=ms)
        f.add("TransitionNumberCondition", inputId=IN_STATE, opValue=0, value=float(k))

    def to_idle(ms=150):
        f.add("StateTransition", stateToId=IDLE, duration=ms)
        f.add("TransitionNumberCondition", inputId=IN_STATE, opValue=4, value=0.0)

    f.add("AnimationState", animationId=idle_anim)  # IDLE
    for k in have:
        to_mood(k, 100, None)
    for k in have:
        f.add("AnimationState", animationId=moods[k]["anim"])
        for j in have:
            if j != k:
                to_mood(j, 120, k)
        for j in range(n):  # a mood without props goes back to the idle props
            if j != k and j not in pos:
                to_mood(j, 120, k)
        to_idle()
        if moods[k]["kind"] == "oneShot":
            f.add("StateTransition", stateToId=rest_of[k], duration=250, flags=4, exitTime=moods[k]["exit_ms"])
    for k in sorted(rest_of):
        f.add("AnimationState", animationId=idle_anim)
        for j in have:
            if j != k:
                to_mood(j, 120, k)
        to_idle()


def simple_layer(f, name, anim):
    f.add("StateMachineLayer", name=name)
    f.add("EntryState")
    f.add("StateTransition", stateToId=3, duration=0)
    f.add("AnyState")
    f.add("ExitState")
    f.add("AnimationState", animationId=anim)


def toggle_layer(f, name, anim, inp):
    f.add("StateMachineLayer", name=name)
    f.add("EntryState")
    f.add("StateTransition", stateToId=3, duration=0)
    f.add("AnyState")
    f.add("ExitState")
    f.add("AnimationState")  # 3: no animation (lower layers show through)
    f.add("StateTransition", stateToId=4, duration=100)
    f.add("TransitionBoolCondition", inputId=inp, opValue=0)
    f.add("AnimationState", animationId=anim)  # 4
    f.add("StateTransition", stateToId=3, duration=100)
    f.add("TransitionBoolCondition", inputId=inp, opValue=1)


def build_state_machine(f, idx, moods, fxm):
    f.add("StateMachine", name="ZaghlolAvatar")
    f.add("StateMachineNumber", name="state", value=-1.0)  # input 0
    f.add("StateMachineBool", name="talk", value=False)  # input 1
    f.add("StateMachineBool", name="reduceMotion", value=False)  # input 2
    IN_STATE, IN_TALK, IN_REDUCE = 0, 1, 2
    simple_layer(f, "breath", idx["breath"])
    simple_layer(f, "tail", idx["tail"])
    simple_layer(f, "blink", idx["blink"])
    state_layer(f, "moods", idx["idle"], moods, IN_STATE)
    state_layer(f, "fx", idx["idleFx"], fxm, IN_STATE)
    toggle_layer(f, "talk", idx["talkOn"], IN_TALK)
    toggle_layer(f, "reduceMotion", idx["still"], IN_REDUCE)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else OUT)
