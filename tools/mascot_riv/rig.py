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
