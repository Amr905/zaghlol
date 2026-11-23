"""Compiles the Motion Lab (via labcss.py) into Rive animations.

Every animation is a dict {name, D (s), kind (loop|oneShot|hold), tracks}, where tracks maps
(node, comp) -> [(t_seconds, value_in_rive_units, ease_key)]; comp is one of
x y rotation scaleX scaleY opacity; ease_key is "hold", "linear" or a cubic-bezier "x1,y1,x2,y2".
Rest positions come from scene.py.  Nothing here knows about the .riv byte format.
"""
import math

import labcss as L
from labcss import IDENT, parse_animation, parse_transform
import scene

FPS = 60
LAB = L.Lab()
EPS = 1.0 / FPS

BODY_NODE = {"bird": "bird", "head": "head", "wingL": "wingL", "brows": "brows", "eyeL": "eyeL",
             "eyeR": "eyeR", "pupilsL": "pupilsL", "pupilsR": "pupilsR", "jaw": "jaw"}
VIS = ["eyeHappyL", "eyeHappyR", "eyeOpenL", "eyeOpenR", "eyeClosed", "jaw", "mouthClosed", "glasses",
       "hat", "mag", "sweat", "pointer"]
BLINK_OPEN = {"eyeL": "blinkL", "eyeR": "blinkR"}
INFINITE_STEP = 1.0 / 30  # sampling step for baked (phase-shifted) loops


def ekey(ease):
    return L.easing_key(ease)


# ---------------------------------------------------------------- compile one CSS animation
def _points_for(css_pts, a, D, base, kind, vars):
    """[(t, value, ease)] of one CSS property (all keyframes of one @keyframes entry) over [0, D]."""
    pts = [(p, L.parse_value(v, kind, vars)) for p, v in css_pts]
    if pts[0][0] > 0:
        pts.insert(0, (0.0, base))
    if pts[-1][0] < 100:
        pts.append((100.0, base))
    dur, delay = a["dur"], a["delay"]
    n = a["iters"]
    if n == math.inf:
        n = max(1, math.ceil((D - delay) / dur - 1e-9))
    n = int(n)
    forwards = a["fill"] in ("forwards", "both")
    ek = ekey(a["ease"])
    out = []

    def push(t, v, e):
        if out and abs(out[-1][0] - t) < 1e-9:
            if _same(out[-1][1], v):
                out[-1] = (out[-1][0], v, e)
                return
            t = out[-1][0] + EPS
        out.append((t, v, e))

    if delay > 0:
        lead = pts[0][1] if a["fill"] in ("backwards", "both") else base
        push(0.0, lead, "hold")
    for i in range(n):
        for p, v in pts:
            push(delay + (i + p / 100.0) * dur, v, ek)
    end = delay + n * dur
    last = pts[-1][1]
    if not forwards and not _same(last, base):
        push(end + EPS, base, "hold")
    elif out[-1][0] < D:
        pass
    if out[0][0] > 0:
        out.insert(0, (0.0, out[0][1], "hold"))
    out = [(t, v, e) for t, v, e in out if t <= D + 1e-9]
    if out[-1][0] < D - 1e-9:
        out.append((D, out[-1][1], "hold"))
    return out


def _same(a, b):
    if isinstance(a, dict):
        return all(abs(a[c] - b[c]) < 1e-9 for c in L.COMPS)
    return abs(a - b) < 1e-9


def _split_tf(points):
    """[(t, tf-dict, e)] -> {comp: [(t, v, e)]} (rotateY folded into scaleX)."""
    res = {c: [] for c in ("x", "y", "rot", "sx", "sy")}
    for t, v, e in points:
        for c in ("x", "y", "rot", "sx", "sy"):
            val = v[c]
            if c == "sx":
                val *= math.cos(math.radians(v["ry"]))
            res[c].append((t, val, e))
    return res


def compile_anim(a, D, base_tf=None, base_op=1.0, vars=None, steady=False):
    """-> {"x","y","rot","sx","sy","opacity"} point lists (only properties the @keyframes set).
    steady=True bakes the steady state of an infinite loop with a delay (phase-shifted) at 30 Hz."""
    kfs = LAB.keyframes[a["name"]]
    base_tf = base_tf or IDENT
    out = {}
    if steady:
        n = int(round(D * 30))
        for kind in ("transform", "opacity"):
            if kind not in kfs:
                continue
            pts = []
            for i in range(n + 1):
                t = i * INFINITE_STEP
                aa = dict(a, delay=0.0, fill="both")
                tt = (t - a["delay"]) % a["dur"]
                tf, op = L.eval_anim(LAB, aa, tt, base_tf, base_op, vars)
                v = tf if kind == "transform" else op
                pts.append((t, v, "linear"))
            if kind == "transform":
                out.update(_split_tf(pts))
            else:
                out["opacity"] = pts
        return out
    if "transform" in kfs:
        out.update(_split_tf(_points_for(kfs["transform"], a, D, base_tf, "transform", vars)))
    if "opacity" in kfs:
        out["opacity"] = _points_for(kfs["opacity"], a, D, base_op, "opacity", vars)
    return out


def const(D, v):
    return [(0.0, v, "hold"), (D, v, "hold")]


# ---------------------------------------------------------------- rive units
def to_rive(node, comp, v):
    if comp == "x":
        return scene.rest(node)[0] + v
    if comp == "y":
        return scene.rest(node)[1] + v
    if comp == "rot":
        return math.radians(v)
    return v


RIVE_COMP = {"x": "x", "y": "y", "rot": "rotation", "sx": "scaleX", "sy": "scaleY", "opacity": "opacity"}


def put(tracks, node, comp, pts):
    tracks[(node, RIVE_COMP[comp])] = [(t, to_rive(node, comp, v), e) for t, v, e in pts]


# ---------------------------------------------------------------- body moods
def _anim_of(st):
    a = parse_animation(st.get("animation"))
    return a


def mood_spec(mood):
    """(D, kind) from the Lab's animations on the body (the jaw `talk` and the ambient
    breathe/wag/blink are separate layers)."""
    ends, periods = [], []
    for el in L.ELEMENTS:
        st = LAB.style(mood, el)
        a = _anim_of(st)
        if not a or a["name"] in ("talk", "blink", "wag"):
            continue
        if a["name"] == "breathe" and mood != "sleep":
            continue
        if a["iters"] == math.inf:
            periods.append(a["dur"])
        else:
            ends.append(a["delay"] + a["dur"] * a["iters"])
    if mood == "sleep":
        return 2 * max(periods), "hold"
    if periods:
        return max(periods), "loop"
    return max(ends) + EPS, "oneShot"  # one extra frame shows the base pose the CSS snaps back to


def body_mood(mood, keyed):
    """Tracks of the `moods` layer for one Lab mood ('default' = idle)."""
    if mood == "default":
        D, kind = 1.0, "loop"
    else:
        D, kind = mood_spec(mood)
    raw = {}  # (node, comp) -> points (lab units)
    for el, node in list(BODY_NODE.items()) + [("breath", "breath")]:
        st = LAB.style(mood, el)
        a = _anim_of(st)
        if el == "breath":
            dst = LAB.style("default", el)
            if st.get("animation") == dst.get("animation") and not st.get("transform"):
                continue
        if a and a["name"] in ("talk", "blink"):
            a = None
        base = parse_transform(st.get("transform"))
        pts = compile_anim(a, D, base, 1.0) if a else {}
        for c in ("x", "y", "rot", "sx", "sy"):
            if c in pts:
                raw[(node, c)] = pts[c]
            else:
                raw[(node, c)] = const(D, base[c] * (math.cos(math.radians(base["ry"])) if c == "sx" else 1))
    # shock: `.eye{animation:none}` stops the blink on the open eyes
    for el, bn in BLINK_OPEN.items():
        if LAB.style(mood, el).get("animation") == "none":
            raw[(bn, "sy")] = const(D, 1.0)
    # display + sweat's own animation
    for el in VIS:
        st = LAB.style(mood, el)
        shown = 0.0 if st.get("display") == "none" else 1.0
        a = _anim_of(st)
        if a and a["name"] not in ("talk",):
            pts = compile_anim(a, D, parse_transform(st.get("transform")), 1.0)
            if "opacity" in pts:
                raw[(el, "opacity")] = [(t, v * shown, e) for t, v, e in pts["opacity"]]
            if "y" in pts:
                for c in ("x", "y", "rot", "sx", "sy"):
                    raw[(el, c)] = pts[c]
            if "opacity" not in pts:
                raw[(el, "opacity")] = const(D, shown)
        else:
            raw[(el, "opacity")] = const(D, shown)
    return D, kind, raw


def build_body():
    """All 16 body animations (idle + 15 moods) with a common key set per node."""
    specs = {m: body_mood(m, None) for m in ["default"] + L.MOODS}
    union = {}
    for D, kind, raw in specs.values():
        for (node, c), pts in raw.items():
            default_v = 1.0 if c in ("sx", "sy", "opacity") else 0.0
            if any(abs(v - default_v) > 1e-9 for _, v, _ in pts):
                union.setdefault(node, set()).add(c)
    # sweat/other visibility always keyed; mood-layer nodes keep a fixed comp order
    for el in VIS:
        union.setdefault(el, set()).add("opacity")
    order = ["x", "y", "rot", "sx", "sy", "opacity"]
    anims = {}
    for m, (D, kind, raw) in specs.items():
        tracks = {}
        for node, comps in union.items():
            for c in order:
                if c not in comps:
                    continue
                pts = raw.get((node, c))
                if pts is None and node in ("breath", "blinkL", "blinkR"):
                    continue  # ambient layers own these; only shock/sleep override them
                if pts is None:
                    pts = const(D, 1.0 if c in ("sx", "sy", "opacity") else 0.0)
                put(tracks, node, c, pts)
        anims[m] = {"D": D, "kind": kind, "tracks": tracks}
    return anims, union


# ---------------------------------------------------------------- ambient, talk
def ambient():
    out = {}
    st = LAB.style("default", "breath")
    a = parse_animation(st["animation"])
    pts = compile_anim(a, a["dur"])
    t = {}
    put(t, "breath", "sx", pts["sx"])
    put(t, "breath", "sy", pts["sy"])
    out["breath"] = {"D": a["dur"], "kind": "loop", "tracks": t}
    a = parse_animation(LAB.style("default", "tail")["animation"])
    pts = compile_anim(a, a["dur"])
    t = {}
    put(t, "tail", "rot", pts["rot"])
    out["tail"] = {"D": a["dur"], "kind": "loop", "tracks": t}
    a = parse_animation(LAB.style("default", "eyeL")["animation"])
    pts = compile_anim(a, a["dur"])
    t = {}
    for bn in ("blinkL", "blinkR", "blinkHappyL", "blinkHappyR"):
        put(t, bn, "sy", pts["sy"])
    out["blink"] = {"D": a["dur"], "kind": "loop", "tracks": t}
    a = parse_animation(LAB.style("default", "jaw")["animation"])
    pts = compile_anim(a, a["dur"])
    t = {}
    put(t, "jaw", "rot", pts["rot"])
    out["talk"] = {"D": a["dur"], "kind": "loop", "tracks": t}
    return out
