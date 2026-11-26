"""Parse docs/02-design/brand/zaghlol-mascot-rig.svg (M/Q/Z paths in named groups)."""
import re
from pathlib import Path

GROUP_ORDER = ["tail", "base", "wing", "browL", "browR", "eyeL", "eyeR", "jaw", "beak", "cere"]


def _nums(s):
    return [float(x) for x in re.findall(r"-?\d+\.?\d*", s)]


def parse_svg(path):
    text = Path(path).read_text()
    body = text[text.index("<!-- Captain"):]
    groups = {}
    for g in re.finditer(r'<g id="(\w+)">(.*?)</g>', body, re.S):
        shapes = []
        for attrs in re.findall(r"<path ([^>]*?)/>", g.group(2)):
            d = re.search(r'\bd="([^"]+)"', attrs).group(1)
            a = dict(re.findall(r'([\w-]+)="([^"]*)"', re.sub(r'\bd="[^"]*"', "", attrs)))
            subs = []
            for sp in re.findall(r"M[^M]*", d):
                toks = re.findall(r"([MQZ])([^MQZ]*)", sp)
                start = None
                segs = []  # (control, end)
                for cmd, args in toks:
                    v = _nums(args)
                    if cmd == "M":
                        start = (v[0], v[1])
                    elif cmd == "Q":
                        segs.append(((v[0], v[1]), (v[2], v[3])))
                subs.append((start, segs))
            shapes.append({"attrs": a, "subpaths": subs})
        groups[g.group(1)] = shapes
    assert list(groups) == GROUP_ORDER, list(groups)
    return groups


# T-274: the wing group carries the shirt-cuff tab that sits at the shoulder/neck joint. In
# the approved still the neck feathers cover it; as a part of the rotating wing it is drawn over
# the chest and shows as a small light patch with a dark outline. Cut it off the arm along the
# sleeve's edge (leftover pieces of the traced art only; nothing is redrawn).
TAB_X = 218.0          # the sleeve's edge; everything right of it, inside the band below, is the tab
TAB_Y0, TAB_Y1 = 425.0, 497.0


def _bbox(sub):
    start, segs = sub
    xs = [start[0]] + [p[0] for c, e in segs for p in (c, e)]
    ys = [start[1]] + [p[1] for c, e in segs for p in (c, e)]
    return min(xs), min(ys), max(xs), max(ys)


def _clamp(p):
    x, y = p
    if TAB_Y0 <= y <= TAB_Y1 and x > TAB_X:
        return (TAB_X, y)
    return p


def trim_cuff_tab(groups):
    """Drops the tab's fill pieces and clamps the dark silhouette at the sleeve edge."""
    for gi, sh in enumerate(groups["wing"]):
        fill = sh["attrs"].get("fill")
        kept = []
        for sub in sh["subpaths"]:
            x0, y0, x1, y1 = _bbox(sub)
            small = x1 - x0 < 60 and y1 - y0 < 60
            if small and x0 >= 210.0 and y0 >= TAB_Y0 and y1 <= TAB_Y1 and (x1 > TAB_X + 1 or fill != "#7ea682"):
                continue
            if fill == "#1d4039" and not small:
                start, segs = sub
                sub = (_clamp(start), [(_clamp(c), _clamp(e)) for c, e in segs])
            kept.append(sub)
        sh["subpaths"] = kept
    return groups
