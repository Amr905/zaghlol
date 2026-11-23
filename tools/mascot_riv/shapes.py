"""Vector helpers: SVG path strings and primitives -> shape specs for generate.py.

A shape spec is {"subs": [(closed, [(x, y, in(dx,dy), out(dx,dy)), ...])], "fill": argb|None,
"rule": 0|1, "stroke": (argb, width, cap, join)|None}; coordinates are absolute (Lab units),
the generator re-bases them on the owning node's pivot."""
import math
import re

KAPPA = 0.5522847498
CAP = {"butt": 0, "round": 1, "square": 2}
JOIN = {"miter": 0, "round": 1, "bevel": 2}


def argb(hexs, alpha=1.0):
    return (int(round(alpha * 255)) << 24) | int(hexs.lstrip("#"), 16)


def _cubic_nodes(start, segs, closed):
    """segs: ('L', end) | ('Q', c, end) | ('C', c1, c2, end) -> vertex list with handles."""
    pts = [start]
    outs = [(0.0, 0.0)]
    ins = [(0.0, 0.0)]
    p0 = start
    for sg in segs:
        if sg[0] == "L":
            c1, c2, end = p0, sg[1], sg[1]
        elif sg[0] == "Q":
            c, end = sg[1], sg[2]
            c1 = (p0[0] + 2 / 3 * (c[0] - p0[0]), p0[1] + 2 / 3 * (c[1] - p0[1]))
            c2 = (end[0] + 2 / 3 * (c[0] - end[0]), end[1] + 2 / 3 * (c[1] - end[1]))
        else:
            c1, c2, end = sg[1], sg[2], sg[3]
        outs[-1] = (c1[0] - p0[0], c1[1] - p0[1])
        pts.append(end)
        outs.append((0.0, 0.0))
        ins.append((c2[0] - end[0], c2[1] - end[1]))
        p0 = end
    if closed:
        if abs(p0[0] - start[0]) < 1e-6 and abs(p0[1] - start[1]) < 1e-6:
            ins[0] = ins[-1]
            pts.pop()
            ins.pop()
            outs.pop()
    return [(pts[i][0], pts[i][1], ins[i], outs[i]) for i in range(len(pts))]


def parse_path(d):
    """SVG path data (M L H V Q C Z, absolute and relative) -> list of (closed, vertices)."""
    toks = re.findall(r"([MmLlHhVvQqCcZz])|(-?\d*\.?\d+(?:e-?\d+)?)", d)
    items, cur = [], None
    nums = []
    cmd = None
    out = []
    i = 0
    seq = []
    for c, n in toks:
        if c:
            seq.append(c)
        else:
            seq.append(float(n))
    pos = (0.0, 0.0)
    start = pos
    subs = []
    segs = []
    k = 0

    def flush(closed):
        nonlocal segs
        if segs or closed:
            subs.append((closed, _cubic_nodes(start, segs, closed)))
        segs = []

    while k < len(seq):
        c = seq[k]
        k += 1
        if c in "Zz":
            flush(True)
            pos = start
            continue
        argc = {"M": 2, "L": 2, "H": 1, "V": 1, "Q": 4, "C": 6}[c.upper()]
        first = True
        while k < len(seq) and not isinstance(seq[k], str):
            a = seq[k:k + argc]
            k += argc
            rel = c.islower()
            u = c.upper()
            ox, oy = pos if rel else (0.0, 0.0)
            if u == "M":
                if not first:
                    u = "L"
                else:
                    flush(False)
                    pos = (a[0] + ox, a[1] + oy)
                    start = pos
                    first = False
                    continue
            first = False
            if u == "L":
                pos = (a[0] + ox, a[1] + oy)
                segs.append(("L", pos))
            elif u == "H":
                pos = (a[0] + ox, pos[1])
                segs.append(("L", pos))
            elif u == "V":
                pos = (pos[0], a[0] + oy)
                segs.append(("L", pos))
            elif u == "Q":
                cc = (a[0] + ox, a[1] + oy)
                pos = (a[2] + ox, a[3] + oy)
                segs.append(("Q", cc, pos))
            elif u == "C":
                c1 = (a[0] + ox, a[1] + oy)
                c2 = (a[2] + ox, a[3] + oy)
                pos = (a[4] + ox, a[5] + oy)
                segs.append(("C", c1, c2, pos))
    flush(False)
    return subs


def ellipse(cx, cy, rx, ry):
    kx, ky = rx * KAPPA, ry * KAPPA
    v = [(cx + rx, cy, (0, -ky), (0, ky)), (cx, cy + ry, (kx, 0), (-kx, 0)),
         (cx - rx, cy, (0, ky), (0, -ky)), (cx, cy - ry, (-kx, 0), (kx, 0))]
    return (True, v)


def rrect(x, y, w, h, r_tl, r_tr=None, r_br=None, r_bl=None):
    r_tr = r_tl if r_tr is None else r_tr
    r_br = r_tl if r_br is None else r_br
    r_bl = r_tl if r_bl is None else r_bl
    k = KAPPA
    v = []

    def corner(px, py, r, hin, hout):
        # hin/hout: unit direction of incoming/outgoing handles (as (dx,dy)) scaled by r*(1-k)... use r*k
        pass

    # vertices walk clockwise from top-left corner's end on the top edge
    def add(px, py, i=(0, 0), o=(0, 0)):
        v.append((px, py, i, o))

    if r_tl:
        add(x, y + r_tl, (0, r_tl * k), (0, -r_tl * k))
        add(x + r_tl, y, (-r_tl * k, 0), (0, 0))
    else:
        add(x, y)
    if r_tr:
        add(x + w - r_tr, y, (0, 0), (r_tr * k, 0))
        add(x + w, y + r_tr, (0, -r_tr * k), (0, 0))
    else:
        add(x + w, y)
    if r_br:
        add(x + w, y + h - r_br, (0, 0), (0, r_br * k))
        add(x + w - r_br, y + h, (r_br * k, 0), (0, 0))
    else:
        add(x + w, y + h)
    if r_bl:
        add(x + r_bl, y + h, (0, 0), (-r_bl * k, 0))
        add(x, y + h - r_bl, (0, r_bl * k), (0, 0))
    else:
        add(x, y + h)
    return (True, v)


def polyline(pts, closed=False):
    return (closed, [(x, y, (0, 0), (0, 0)) for x, y in pts])


def shape(subs, fill=None, rule=0, stroke=None):
    return {"subs": subs, "fill": fill, "rule": rule, "stroke": stroke}


def stroke(color, width, cap="butt", join="miter"):
    return (color, width, CAP[cap], JOIN[join])
