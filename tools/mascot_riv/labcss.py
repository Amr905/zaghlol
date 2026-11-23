"""Reads the approved Motion Lab (docs/02-design/motion/zaghlol-motion.html) literally:
@keyframes, the `.zg .part` base rules and the `.st-<mood> .part` rules (cascade by
specificity, then order), CSS transform lists and cubic-bezier timing.  Python stdlib only.

Used by motion.py (compile to Rive animations) and by verify/lab_expect.py (expectations).
"""
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
LAB = ROOT / "docs/02-design/motion/zaghlol-motion.html"

MOODS = ["hello", "think", "scan", "count", "saved", "payday", "proud", "shock", "detect", "explain",
         "listen", "oops", "sleep", "pull", "tap"]

# Body elements of the bird SVG and the CSS classes each carries (see birdSVG() in the Lab).
ELEMENTS = {
    "bird": {"bird"}, "breath": {"breath"}, "tail": {"tail"}, "wingL": {"wingL"}, "pointer": {"pointer"},
    "head": {"head"}, "brows": {"brows"},
    "eyeHappyL": {"eyeHappy", "l"}, "eyeHappyR": {"eyeHappy", "r"},
    "eyeOpenL": {"eyeOpen", "l"}, "eyeL": {"eye", "l"}, "pupilsL": {"pupils"},
    "eyeOpenR": {"eyeOpen", "r"}, "eyeR": {"eye", "r"}, "pupilsR": {"pupils"},
    "eyeClosed": {"eyeClosed"}, "jaw": {"jaw"}, "mouthClosed": {"mouthClosed"},
    "glasses": {"glasses"}, "hat": {"hat"}, "mag": {"mag"}, "sweat": {"sweat"},
}

EASING = {
    "ease": (0.25, 0.1, 0.25, 1.0), "ease-in": (0.42, 0.0, 1.0, 1.0), "ease-out": (0.0, 0.0, 0.58, 1.0),
    "ease-in-out": (0.42, 0.0, 0.58, 1.0), "linear": None,
}


def _strip(css):
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def _blocks(css):
    """Top-level `selector{body}` blocks (bodies may nest)."""
    out, i, n = [], 0, len(css)
    while i < n:
        j = css.find("{", i)
        if j < 0:
            break
        sel = css[i:j].strip()
        depth, k = 1, j + 1
        while depth and k < n:
            depth += {"{": 1, "}": -1}.get(css[k], 0)
            k += 1
        out.append((sel, css[j + 1:k - 1]))
        i = k
    return out


def _decls(body):
    d = {}
    for part in body.split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            d[k.strip()] = v.strip()
    return d


def _split_top(s, sep):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == sep and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return [x.strip() for x in out if x.strip()]


# ---------- transforms ----------
def _num(s):
    return float(re.sub(r"(px|deg|s)$", "", s.strip()))


def parse_transform(s):
    """CSS transform list -> dict(x, y, rot (deg), sx, sy) in the T*R*S form used by Rive nodes.
    Supports translate/translateX/translateY/rotate/scale/scaleX/scaleY (what the Lab uses)."""
    a, b, c, d, e, f = 1.0, 0.0, 0.0, 1.0, 0.0, 0.0
    rot = 0.0
    ry = 0.0
    if s and s != "none":
        for fn, args in re.findall(r"(\w+)\(([^)]*)\)", s):
            v = [x.strip() for x in args.split(",")]
            if fn == "translate":
                m = (1, 0, 0, 1, _num(v[0]), _num(v[1]) if len(v) > 1 else 0.0)
            elif fn == "translateX":
                m = (1, 0, 0, 1, _num(v[0]), 0)
            elif fn == "translateY":
                m = (1, 0, 0, 1, 0, _num(v[0]))
            elif fn == "rotate":
                r = math.radians(_num(v[0]))
                rot += _num(v[0])
                m = (math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0)
            elif fn == "rotateY":  # kept as an angle; the caller turns it into scaleX = cos
                ry += _num(v[0])
                m = (1, 0, 0, 1, 0, 0)
            elif fn == "scale":
                sx = _num(v[0])
                m = (sx, 0, 0, _num(v[1]) if len(v) > 1 else sx, 0, 0)
            elif fn == "scaleX":
                m = (_num(v[0]), 0, 0, 1, 0, 0)
            elif fn == "scaleY":
                m = (1, 0, 0, _num(v[0]), 0, 0)
            else:
                raise ValueError(f"unsupported transform function {fn}")
            a, b, c, d, e, f = (a * m[0] + c * m[1], b * m[0] + d * m[1],
                                a * m[2] + c * m[3], b * m[2] + d * m[3],
                                a * m[4] + c * m[5] + e, b * m[4] + d * m[5] + f)
    sx = math.hypot(a, b)
    sy = (a * d - b * c) / sx if sx else 0.0
    return {"x": e, "y": f, "rot": rot, "sx": sx, "sy": sy, "ry": ry}


IDENT = {"x": 0.0, "y": 0.0, "rot": 0.0, "sx": 1.0, "sy": 1.0, "ry": 0.0}
COMPS = ["x", "y", "rot", "sx", "sy", "ry"]


# ---------- timing functions ----------
def bezier(p, x):
    """CSS cubic-bezier(x1,y1,x2,y2) progress for input x in [0,1]."""
    if p is None:
        return x
    x1, y1, x2, y2 = p

    def bx(t):
        return 3 * (1 - t) ** 2 * t * x1 + 3 * (1 - t) * t * t * x2 + t ** 3

    def by(t):
        return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t * t * y2 + t ** 3

    lo, hi = 0.0, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if bx(mid) < x:
            lo = mid
        else:
            hi = mid
    return by((lo + hi) / 2)


def parse_easing(tok):
    if tok.startswith("cubic-bezier"):
        return tuple(float(x) for x in re.search(r"\(([^)]*)\)", tok).group(1).split(","))
    return EASING[tok]


def easing_key(e):
    return "linear" if e is None else ",".join(f"{v:g}" for v in e)


# ---------- animation shorthand ----------
def parse_animation(v):
    if v in (None, "none"):
        return None
    a = {"name": None, "dur": 0.0, "delay": 0.0, "ease": EASING["ease"], "iters": 1.0, "fill": "none"}
    times = []
    for t in _split_top(v, " "):
        if re.fullmatch(r"-?[\d.]+s", t):
            times.append(float(t[:-1]))
        elif t == "infinite":
            a["iters"] = math.inf
        elif re.fullmatch(r"\d+", t):
            a["iters"] = float(t)
        elif t in ("forwards", "backwards", "both"):
            a["fill"] = t
        elif t in EASING or t.startswith("cubic-bezier"):
            a["ease"] = parse_easing(t)
        else:
            a["name"] = t
    a["dur"] = times[0]
    a["delay"] = times[1] if len(times) > 1 else 0.0
    return a


class Lab:
    def __init__(self, path=LAB):
        html = Path(path).read_text()
        css = _strip(html[html.index("<style>") + 7:html.index("</style>")])
        self.keyframes = {}
        self.rules = []  # (scope, spec, order, classes-required, decls)
        for order, (sel, body) in enumerate(_blocks(css)):
            if sel.startswith("@keyframes"):
                self.keyframes[sel.split()[1]] = self._parse_kf(body)
            elif sel.startswith("@"):
                continue
            else:
                self._add_rule(sel, _decls(body), order)

    @staticmethod
    def _parse_kf(body):
        props = {}
        for sel, b in _blocks(body):
            pcts = []
            for p in sel.split(","):
                p = p.strip()
                pcts.append(0.0 if p == "from" else 100.0 if p == "to" else float(p.rstrip("%")))
            for k, v in _decls(b).items():
                for p in pcts:
                    props.setdefault(k, []).append((p, v))
        return {k: sorted(v, key=lambda t: t[0]) for k, v in props.items()}

    def _add_rule(self, sel, decls, order):
        for s in _split_top(sel, ","):
            m = re.fullmatch(r'\.zg(:not\(\[class\*="st-"\]\))?\s+\.(\w+)((?:\.\w+)*)', s)
            if m:
                subs = set(x for x in m.group(3).split(".") if x)
                scope = "default" if m.group(1) else "any"
                self.rules.append((scope, 2 + (1 if m.group(1) else 0) + len(subs), order,
                                   {m.group(2)} | subs, decls))
                continue
            m = re.fullmatch(r"\.st-(\w+)\s+\.(\w+)((?:\.\w+)*)", s)
            if m:
                subs = set(x for x in m.group(3).split(".") if x)
                self.rules.append((m.group(1), 2 + len(subs), order, {m.group(2)} | subs, decls))

    def style(self, mood, element):
        """Cascaded declarations for `element` ("default" mood = no st- class)."""
        cls = ELEMENTS[element]
        best = {}
        for scope, spec, order, need, decls in self.rules:
            if not need <= cls:
                continue
            if scope not in ("any", mood) and not (scope == "default" and mood == "default"):
                continue
            for k, v in decls.items():
                if k not in best or (spec, order) >= best[k][0]:
                    best[k] = ((spec, order), v)
        return {k: v for k, (_, v) in best.items()}

    def origin(self, element):
        """transform-origin (user units) from the CSS; 'center' means the fill-box centre."""
        o = self.style("default", element).get("transform-origin")
        if o is None:
            return None
        if o == "center":
            return "center"
        x, y = o.split()
        return (_num(x), _num(y))

    def kf_tracks(self, name):
        return self.keyframes[name]


# ---------- evaluation ----------
def _lerp(a, b, t):
    return a + (b - a) * t


def eval_track(points, dur, ease, t, base, kind):
    """Value of one CSS property at local time t (0..dur) of one iteration.
    points: [(pct, valuestr)] for that property; implicit 0/100 use `base`
    (a decomposed transform dict or a float opacity)."""
    pts = [(p, parse_value(v, kind)) for p, v in points]
    if pts[0][0] > 0:
        pts.insert(0, (0.0, base))
    if pts[-1][0] < 100:
        pts.append((100.0, base))
    pct = 100.0 * t / dur
    for (p0, v0), (p1, v1) in zip(pts, pts[1:]):
        if pct <= p1 or p1 == pts[-1][0]:
            span = p1 - p0
            u = 1.0 if span == 0 else min(1.0, max(0.0, (pct - p0) / span))
            u = bezier(ease, u)
            if kind == "opacity":
                return _lerp(v0, v1, u)
            return {c: _lerp(v0[c], v1[c], u) for c in COMPS}
    return pts[-1][1]


def parse_value(v, kind, vars=None):
    if vars:
        v = re.sub(r"var\((--\w+)(?:,[^)]*)?\)", lambda m: vars[m.group(1)], v)
    if kind == "opacity":
        return float(v)
    return parse_transform(v)


def eval_anim(lab, a, t, base_tf=None, base_op=1.0, vars=None, kfs=None):
    """State of animation `a` (dict from parse_animation) at absolute time t:
    returns (transform dict or None, opacity or None); None = the animation sets no value
    for that property at t (element shows its base style)."""
    kfs = kfs or lab.keyframes[a["name"]]
    base_tf = base_tf or IDENT
    local = t - a["delay"]
    tf = op = None
    if local < 0:
        if a["fill"] in ("backwards", "both"):
            local = 0.0
        else:
            return None, None
    total = a["dur"] * a["iters"]
    forwards = a["fill"] in ("forwards", "both")
    if local >= total:
        if not forwards:
            return None, None
        local = total
        cyc = a["dur"]
    else:
        cyc = local % a["dur"]
        if cyc == 0 and local > 0 and local < total:
            cyc = 0.0
    if local >= total and a["iters"] != math.inf:
        cyc = a["dur"]
    if "transform" in kfs:
        pts = kfs["transform"]
        pts = [(p, _vars(v, vars)) for p, v in pts]
        tf = eval_track(pts, a["dur"], a["ease"], cyc, base_tf, "transform")
    if "opacity" in kfs:
        pts = [(p, _vars(v, vars)) for p, v in kfs["opacity"]]
        op = eval_track(pts, a["dur"], a["ease"], cyc, base_op, "opacity")
    return tf, op


def _vars(v, vars):
    if vars:
        return re.sub(r"var\((--\w+)(?:,[^)]*)?\)", lambda m: vars[m.group(1)], v)
    return v


def rotate_y_scale(angle_deg):
    return math.cos(math.radians(angle_deg))
