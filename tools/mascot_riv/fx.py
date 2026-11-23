"""The Lab's HTML props (props() in zaghlol-motion.html) as vector shapes and Rive animations.

Positions/sizes are the Lab's stage pixels (380x400); the `fx` node scales them onto the bird.
Math.random in the Lab is replaced by mulberry32(SEED), the same generator the contact-sheet
capture injects, so the Lab frames and ours use the same confetti and rain.
"""
import math

import labcss as L
from labcss import parse_animation
import motion
import scene
import shapes as S

W, H = scene.STAGE_W, scene.STAGE_H
SEED = 20261123
PRIMARY, COIN, COIN_RING, COIN_HI = "#0F7A55", "#F6C445", "#D99A1E", "#FFE08A"
ALT, MUTED, BOLT, WHITE = "#E5F5EC", "#4D695C", "#E2582B", "#FFFFFF"
CONF = ["#0F7A55", "#34B27D", "#FFB86B", "#FFA94D", "#B8EED3"]


def mulberry32(seed):
    a = seed & 0xFFFFFFFF

    def rnd():
        nonlocal a
        a = (a + 0x6D2B79F5) & 0xFFFFFFFF
        t = a
        t = ((t ^ (t >> 15)) * (1 | t)) & 0xFFFFFFFF
        t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) & 0xFFFFFFFF) ^ t
        return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296

    return rnd


def anim(name, dur, ease="ease", delay=0.0, iters=math.inf, fill="none"):
    return {"name": name, "dur": dur, "delay": delay, "ease": L.parse_easing(ease), "iters": iters, "fill": fill}


def disc(r, color, cx=0.0, cy=0.0):
    return S.shape([S.ellipse(cx, cy, r, r)], fill=S.argb(color))


def coin_shapes():
    ring = S.shape([S.ellipse(0, 0, 11, 11), S.ellipse(0, 0, 8, 8)], fill=S.argb(COIN_RING), rule=1)
    return [disc(11, COIN), disc(8, COIN_HI), disc(7, COIN, 2.6, -2.6), ring]


def rect_shape(w, h, r, fill, stroke=None):
    return S.shape([S.rrect(-w / 2, -h / 2, w, h, r)], fill=S.argb(fill) if fill else None, stroke=stroke)


def env_shapes(i):
    body = S.shape([S.rrect(-14, -9, 28, 18, 3)], fill=S.argb(WHITE),
                   stroke=S.stroke(S.argb(PRIMARY), 2, "butt", "miter"))
    v = S.shape([S.polyline([(-12.7, -9), (1, 4.7), (14.7, -9)])], stroke=S.stroke(S.argb(PRIMARY), 2, "butt", "miter"))
    return [body, v]


def rot(pts, deg, cx=0, cy=0):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


# ---------------------------------------------------------------- items
ITEMS = []  # {name, mood, center, shapes, anims:[(anim, vars, steady)], base_op}
GROUP_OF = {}


def item(name, mood, center, shapes, anims=(), base_op=1.0):
    ITEMS.append({"name": name, "mood": mood, "center": center, "shapes": shapes, "anims": list(anims),
                  "base_op": base_op})


def build_items():
    ITEMS.clear()
    # think: flipping coin + three dots
    item("think_coin", "think", (250 + 11, 48 + 11), coin_shapes(), [(anim("flip", 1.0, "ease-in-out"), {}, True)])
    for i in range(3):
        item(f"think_dot{i}", "think", (120.5 + 4.5 + 15 * i, 64 + 4.5), [disc(4.5, PRIMARY)],
             [(anim("dot", 1.0, "ease", i * 0.15), {}, True)])
    # scan: five envelopes flying into the bird
    for i in range(5):
        item(f"scan_env{i}", "scan", (370 + 15, 56 + 48 * i + 10), env_shapes(i),
             [(anim("flyin", 1.6, "ease-in", i * 0.35), {"--dx": f"{-W / 2 + 20}px", "--dy": f"{H * .28 - i * H * .12}px"}, True)])
    # count: five coins share one phase in the Lab (delay i*.6 on a .6 s loop): one column falling
    item("count_coin", "count", (190 + 16 + 11, 11), coin_shapes(),
         [(anim("fall", 0.6, "ease-in"), {"--to": f"{H * .5}px"}, False)])
    # saved: 24 confetti pieces
    rnd = mulberry32(SEED)
    for i in range(24):
        a = rnd() * math.pi * 2
        d = 70 + rnd() * 90
        r = rnd() * 540
        delay = .25 + rnd() * .15
        v = {"--dx": f"{math.cos(a) * d}px", "--dy": f"{math.sin(a) * d - 40}px", "--r": f"{r}deg"}
        item(f"saved_conf{i}", "saved", (190 + 4, 288 + 6),
             [S.shape([S.rrect(-4, -6, 8, 12, 2)], fill=S.argb(CONF[i % 5]))],
             [(anim("burst", 1.0, "ease-out", delay, 1, "both"), v, False)])
    # payday: 16 coins raining
    rnd = mulberry32(SEED)
    for i in range(16):
        left = (5 + rnd() * 90) / 100 * W
        dur = 1 + rnd() * .6
        delay = rnd() * .8
        item(f"payday_coin{i}", "payday", (left + 11, 11), coin_shapes(),
             [(anim("fall", dur, "ease-in", delay, 1, "both"), {"--to": f"{H + 20}px"}, False)])
    # listen: three rings
    for i in range(3):
        item(f"listen_ring{i}", "listen", (190 - 20, 136),
             [S.shape([S.ellipse(0, 0, 58.5, 58.5)], stroke=S.stroke(S.argb(PRIMARY), 3, "butt", "miter"))],
             [(anim("ring", 1.8, "ease-out", i * .6), {}, True)], base_op=0.0)
    # oops: cloud with the orange bolt (static)
    cx, cy = 380 - 380 * .14 - 58 + 29, 88 + 13
    cloud = S.shape([S.rrect(-28, -12, 56, 24, 12)], fill=S.argb(ALT), stroke=S.stroke(S.argb(MUTED), 2, "butt", "miter"))
    bolt_pts = rot([(-2, -24), (2, -24), (2, 24), (-2, 24)], 40)
    bolt = S.shape([S.polyline([(x - 1, y + 1) for x, y in bolt_pts], True)], fill=S.argb(BOLT))
    item("oops_cloud", "oops", (cx, cy), [cloud, bolt])
    # sleep: three Z
    for i in range(3):
        zs = S.shape([S.polyline([(-6, -8), (6, -8), (-6, 8), (6, 8)])], stroke=S.stroke(S.argb(PRIMARY), 3.5, "round", "round"))
        item(f"sleep_z{i}", "sleep", (248, 105), [zs], [(anim("zz", 2.4, "ease-out", i * .8), {}, True)])
    # explain: four bars growing
    for i, h in enumerate([24, 40, 30, 56]):
        item(f"explain_bar{i}", "explain", (30.4 + 17 * i + 6, 280),
             [S.shape([S.rrect(-6, -h, 12, h, 4, 4, 0, 0)], fill=S.argb(PRIMARY))],
             [(anim("grow", .6, "ease", .3 + i * .12, 1, "both"), {}, False)])


FX_MOODS = ["think", "scan", "count", "saved", "payday", "listen", "oops", "sleep", "explain"]
build_items()
for _g in FX_MOODS:
    scene.add_node(f"fx_{_g}", "fx", (0.0, 0.0))
for _it in ITEMS:
    scene.add_node(_it["name"], f"fx_{_it['mood']}", _it["center"])


def mood_D(mood, body_D):
    """(D, kind) of the prop clock for a mood."""
    its = [i for i in ITEMS if i["mood"] == mood]
    if mood in ("oops", "explain", "sleep"):
        return body_D[mood], "oneShot"
    periods = [a["dur"] for i in its for a, _, st in i["anims"] if a["iters"] == math.inf]
    if periods:
        return max(periods), "loop"
    return max(a["delay"] + a["dur"] * a["iters"] for i in its for a, _, _ in i["anims"]) + motion.EPS, "oneShot"


def build_fx(body_D):
    """-> {mood or 'idle': {D, kind, tracks}}; every animation keys all group opacities."""
    out = {}
    for mood in ["idle"] + FX_MOODS:
        D, kind = (1.0, "loop") if mood == "idle" else mood_D(mood, body_D)
        tracks = {}
        for g in FX_MOODS:
            tracks[(f"fx_{g}", "opacity")] = [(0.0, 1.0 if g == mood else 0.0, "hold"), (D, 1.0 if g == mood else 0.0, "hold")]
        for it in ITEMS:
            if it["mood"] != mood:
                continue
            for a, vars, steady in it["anims"]:
                pts = motion.compile_anim(a, D, None, it["base_op"], vars, steady)
                for comp, p in pts.items():
                    dflt = 1.0 if comp in ("sx", "sy", "opacity") else 0.0
                    if comp == "opacity" and False:
                        pass
                    if all(abs(v - dflt) < 1e-9 for _, v, _ in p) and comp != "opacity":
                        continue
                    motion.put(tracks, it["name"], comp, p)
        out[mood] = {"D": D, "kind": kind, "tracks": tracks}
    return out
