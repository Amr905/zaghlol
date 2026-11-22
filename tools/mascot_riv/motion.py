"""Animations for the Zaghlol rig. Times in seconds; transforms are deltas from rest
(x/y px in artboard units, rotation in degrees), scales are absolute (1.0 = rest)."""
import math

FPS = 60

# node -> animated props, in a fixed order (body animations key every one of them)
BODY = {
    "character": ["x", "y", "rotation", "scaleX", "scaleY"],
    "face": ["x", "y", "rotation"],
    "wing": ["rotation"],
    "tail": ["rotation"],
    "browL": ["y", "rotation"],
    "browR": ["y", "rotation"],
    "eyeL": ["scaleX", "scaleY"],
    "eyeR": ["scaleX", "scaleY"],
}
TALK = {"jaw": ["rotation"], "beak": ["rotation"], "cere": ["rotation"]}
NODES = list(BODY) + list(TALK)
KEYED = {**BODY, **TALK}
PROP_KEY = {"x": 13, "y": 14, "rotation": 15, "scaleX": 16, "scaleY": 17}
REST = {"scaleX": 1.0, "scaleY": 1.0}


def both(t, nodes):  # helper: same timeline on several nodes
    return {n: t for n in nodes}


def tl(*pairs):
    return list(pairs)


def sym(times, vals):
    return list(zip(times, vals))


def _blink(t0):
    return [(0, 1), (t0, 1), (t0 + 0.06, 0.1), (t0 + 0.14, 1)]


def idle():
    d = 4.8
    wag = []
    for i in range(3):
        b = i * 1.6
        wag += [(b, 0), (b + 0.4, 5), (b + 0.8, -2), (b + 1.2, 4)]
    wag.append((d, 0))
    return d, "loop", {
        ("character", "scaleY"): [(0, 1), (1.2, 1.014), (2.4, 1), (3.6, 1.014), (4.8, 1)],
        ("character", "scaleX"): [(0, 1), (1.2, 0.992), (2.4, 1), (3.6, 0.992), (4.8, 1)],
        ("tail", "rotation"): wag,
        ("eyeL", "scaleY"): _blink(3.7) + [(d, 1)],
        ("eyeR", "scaleY"): _blink(3.7) + [(d, 1)],
    }


def both_eyes(key, pts):
    return {("eyeL", key): pts, ("eyeR", key): pts}


def both_brows(key, pts):
    return {("browL", key): pts, ("browR", key): pts}


def merge(*ds):
    out = {}
    for d in ds:
        out.update(d)
    return out


def mood_tourGuide():
    return 1.6, "oneShot", merge(
        {("wing", "rotation"): [(0, 0), (0.2, 20), (0.45, 5), (0.7, 20), (0.95, 5), (1.2, 20), (1.6, 0)],
         ("face", "rotation"): [(0, 0), (0.3, -3), (1.2, -3), (1.6, 0)],
         ("character", "rotation"): [(0, 0), (0.3, -2), (1.2, -2), (1.6, 0)],
         ("character", "y"): [(0, 0), (0.2, -6), (0.45, 0), (0.7, -6), (0.95, 0), (1.2, -6), (1.6, 0)]},
        both_brows("y", [(0, 0), (0.25, -6), (1.3, -6), (1.6, 0)]))


def mood_proud():
    return 0.9, "oneShot", merge(
        {("character", "scaleX"): [(0, 1), (0.25, 1.05), (0.55, 0.99), (0.9, 1)],
         ("character", "scaleY"): [(0, 1), (0.25, 1.06), (0.55, 0.97), (0.9, 1)],
         ("character", "y"): [(0, 0), (0.25, -14), (0.55, 0), (0.9, 0)],
         ("wing", "rotation"): [(0, 0), (0.25, 12), (0.9, 0)],
         ("face", "y"): [(0, 0), (0.25, -6), (0.9, 0)]},
        both_brows("y", [(0, 0), (0.25, -5), (0.9, 0)]))


def mood_shocked():
    return 1.1, "oneShot", merge(
        {("character", "y"): [(0, 0), (0.18, -55), (0.42, 0), (0.52, 0), (1.1, 0)],
         ("character", "scaleX"): [(0, 1), (0.18, 0.96), (0.42, 1.08), (0.55, 1), (1.1, 1)],
         ("character", "scaleY"): [(0, 1), (0.18, 1.05), (0.42, 0.92), (0.55, 1), (1.1, 1)],
         ("wing", "rotation"): [(0, 0), (0.18, 25), (0.6, 5), (1.1, 0)]},
        both_eyes("scaleY", [(0, 1), (0.15, 1.35), (0.95, 1.35), (1.1, 1)]),
        both_eyes("scaleX", [(0, 1), (0.15, 1.2), (0.95, 1.2), (1.1, 1)]),
        both_brows("y", [(0, 0), (0.15, -16), (0.95, -16), (1.1, 0)]))


def mood_detective():
    return 2.0, "oneShot", merge(
        {("character", "rotation"): [(0, 0), (0.3, 5), (1.7, 5), (2.0, 0)],
         ("face", "x"): [(0, 0), (0.4, -14), (1.0, 14), (1.5, -14), (1.8, 0), (2.0, 0)],
         ("face", "rotation"): [(0, 0), (0.4, -2), (1.0, 2), (1.5, -2), (1.8, 0), (2.0, 0)]},
        both_brows("y", [(0, 0), (0.3, 6), (1.7, 6), (2.0, 0)]),
        both_eyes("scaleY", [(0, 1), (0.3, 0.8), (1.7, 0.8), (2.0, 1)]))


def mood_professor():
    return 1.4, "oneShot", merge(
        {("face", "y"): [(0, 0), (0.2, 10), (0.45, -2), (0.7, 10), (0.95, -2), (1.4, 0)],
         ("face", "rotation"): [(0, 0), (0.2, 3), (0.45, -1), (0.7, 3), (0.95, -1), (1.4, 0)],
         ("character", "rotation"): [(0, 0), (0.3, -2), (1.1, -2), (1.4, 0)],
         ("wing", "rotation"): [(0, 0), (0.4, 10), (1.0, 10), (1.4, 0)]},
        both_brows("y", [(0, 0), (0.2, -8), (1.1, -8), (1.4, 0)]))


def mood_listening():
    return 3.0, "loop", merge(
        {("character", "rotation"): [(0, 0), (1.2, -4), (1.8, -4), (3.0, 0)],
         ("face", "rotation"): [(0, 0), (1.2, -7), (1.8, -7), (3.0, 0)],
         ("face", "y"): [(0, 0), (1.2, 3), (1.8, 3), (3.0, 0)]},
        both_eyes("scaleY", [(0, 1), (1.2, 1.12), (1.8, 1.12), (3.0, 1)]),
        both_brows("y", [(0, 0), (1.2, -6), (1.8, -6), (3.0, 0)]))


def mood_thinking():
    return 2.4, "loop", merge(
        {("character", "rotation"): [(0, 0), (0.8, 3), (1.6, -3), (2.4, 0)],
         ("face", "x"): [(0, 0), (0.5, -10), (1.9, -10), (2.4, 0)],
         ("face", "y"): [(0, 0), (0.5, -6), (1.9, -6), (2.4, 0)],
         ("browR", "y"): [(0, 0), (0.5, -12), (1.9, -12), (2.4, 0)],
         ("browR", "rotation"): [(0, 0), (0.5, -6), (1.9, -6), (2.4, 0)]},
        both_eyes("scaleY", [(0, 1), (1.1, 1), (1.17, 0.1), (1.26, 1), (2.4, 1)]))


def mood_scanning():
    return 2.0, "loop", merge(
        {("face", "x"): [(0, 0), (0.5, -16), (1.5, 16), (2.0, 0)],
         ("character", "rotation"): [(0, 0), (0.5, -3), (1.5, 3), (2.0, 0)]},
        both_brows("y", [(0, 0), (0.3, 4), (1.7, 4), (2.0, 0)]),
        both_eyes("scaleY", [(0, 1), (0.3, 0.85), (1.7, 0.85), (2.0, 1)]))


def mood_counting():
    return 1.2, "loop", merge(
        {("face", "y"): [(0, 0), (0.3, 9), (0.6, 0), (0.9, 9), (1.2, 0)],
         ("face", "rotation"): [(0, 0), (0.3, 2), (0.6, 0), (0.9, 2), (1.2, 0)],
         ("character", "scaleY"): [(0, 1), (0.3, 0.99), (0.6, 1), (0.9, 0.99), (1.2, 1)],
         ("wing", "rotation"): [(0, 0), (0.3, 8), (0.6, 0), (0.9, 8), (1.2, 0)]})


def mood_saved():
    return 0.9, "oneShot", merge(
        {("character", "y"): [(0, 0), (0.12, 6), (0.35, -45), (0.65, 0), (0.75, 3), (0.9, 0)],
         ("character", "scaleY"): [(0, 1), (0.12, 0.95), (0.35, 1.05), (0.65, 0.94), (0.75, 1.0), (0.9, 1)],
         ("character", "scaleX"): [(0, 1), (0.12, 1.04), (0.35, 0.97), (0.65, 1.06), (0.9, 1)],
         ("wing", "rotation"): [(0, 0), (0.35, 28), (0.9, 0)]},
        both_brows("y", [(0, 0), (0.35, -8), (0.7, -8), (0.9, 0)]))


def mood_payday():
    return 1.6, "oneShot", merge(
        {("character", "y"): [(0, 0), (0.25, -50), (0.5, 0), (0.75, -50), (1.0, 0), (1.6, 0)],
         ("character", "scaleY"): [(0, 1), (0.25, 1.04), (0.5, 0.93), (0.75, 1.04), (1.0, 0.93), (1.2, 1), (1.6, 1)],
         ("wing", "rotation"): [(0, 0), (0.25, 30), (0.5, 10), (0.75, 30), (1.0, 10), (1.3, 28), (1.6, 0)],
         ("tail", "rotation"): [(0, 0), (0.25, 12), (0.5, -5), (0.75, 12), (1.0, -5), (1.3, 10), (1.6, 0)]},
        both_brows("y", [(0, 0), (0.2, -10), (1.3, -10), (1.6, 0)]),
        both_eyes("scaleY", [(0, 1), (0.2, 1.15), (1.3, 1.15), (1.6, 1)]))


def mood_oops():
    return 1.4, "oneShot", merge(
        {("character", "x"): [(0, 0), (0.1, -12), (0.2, 12), (0.3, -10), (0.4, 10), (0.5, -7), (0.6, 6), (0.7, -4),
                              (0.8, 3), (0.9, 0), (1.4, 0)],
         ("character", "scaleY"): [(0, 1), (0.15, 0.95), (1.0, 0.95), (1.4, 1)],
         ("character", "rotation"): [(0, 0), (0.15, -3), (1.0, -3), (1.4, 0)],
         ("face", "y"): [(0, 0), (0.15, 6), (1.0, 6), (1.4, 0)],
         ("wing", "rotation"): [(0, 0), (0.15, -8), (1.0, -8), (1.4, 0)],
         ("browL", "rotation"): [(0, 0), (0.12, 12), (1.0, 12), (1.4, 0)],
         ("browR", "rotation"): [(0, 0), (0.12, -12), (1.0, -12), (1.4, 0)]},
        both_eyes("scaleY", [(0, 1), (0.12, 0.4), (1.0, 0.4), (1.4, 1)]),
        both_brows("y", [(0, 0), (0.12, 8), (1.0, 8), (1.4, 0)]))


def mood_sleep():
    return 2.8, "oneShot", merge(
        {("character", "scaleY"): [(0, 1), (0.7, 1.03), (1.4, 0.985), (2.1, 1.03), (2.8, 1)],
         ("character", "scaleX"): [(0, 1), (0.7, 0.99), (1.4, 1.005), (2.1, 0.99), (2.8, 1)],
         ("face", "y"): [(0, 0), (0.5, 12), (2.3, 12), (2.8, 0)],
         ("face", "rotation"): [(0, 0), (0.5, 6), (2.3, 6), (2.8, 0)],
         ("wing", "rotation"): [(0, 0), (0.5, -6), (2.3, -6), (2.8, 0)]},
        both_eyes("scaleY", [(0, 1), (0.4, 0.08), (2.4, 0.08), (2.8, 1)]),
        both_brows("y", [(0, 0), (0.5, 4), (2.3, 4), (2.8, 0)]))


def mood_pull():
    return 0.4, "hold", merge(
        {("character", "scaleY"): [(0, 1), (0.4, 1.12)],
         ("character", "scaleX"): [(0, 1), (0.4, 0.94)],
         ("character", "y"): [(0, 0), (0.4, -8)],
         ("face", "y"): [(0, 0), (0.4, -4)],
         ("wing", "rotation"): [(0, 0), (0.4, 14)]},
        both_eyes("scaleY", [(0, 1), (0.4, 1.2)]),
        both_brows("y", [(0, 0), (0.4, -8)]))


def mood_tap():
    return 0.8, "oneShot", merge(
        {("character", "y"): [(0, 0), (0.12, 5), (0.35, -40), (0.6, 0), (0.7, 2), (0.8, 0)],
         ("character", "scaleY"): [(0, 1), (0.12, 0.88), (0.35, 1.08), (0.6, 0.92), (0.7, 1), (0.8, 1)],
         ("character", "scaleX"): [(0, 1), (0.12, 1.1), (0.28, 0.1), (0.4, -1), (0.52, 0.1), (0.64, 1), (0.8, 1)]},
        both_brows("y", [(0, 0), (0.3, -8), (0.8, 0)]))


MOODS = [("tourGuide", mood_tourGuide), ("proud", mood_proud), ("shocked", mood_shocked),
         ("detective", mood_detective), ("professor", mood_professor), ("listening", mood_listening),
         ("thinking", mood_thinking), ("scanning", mood_scanning), ("counting", mood_counting),
         ("saved", mood_saved), ("payday", mood_payday), ("oops", mood_oops), ("sleep", mood_sleep),
         ("pull", mood_pull), ("tap", mood_tap)]


def talk_on():
    return 0.5, "loop", {
        ("jaw", "rotation"): [(0, 0), (0.12, -14), (0.25, -2), (0.37, -12), (0.5, 0)],
        ("beak", "rotation"): [(0, 0), (0.12, 5), (0.25, 0), (0.37, 4), (0.5, 0)],
        ("cere", "rotation"): [(0, 0), (0.12, 2), (0.25, 0), (0.37, 2), (0.5, 0)],
    }


def rest_value(node, prop, xy):
    if prop in REST:
        return REST[prop]
    if prop in ("x", "y"):
        return xy[node][0 if prop == "x" else 1]
    return 0.0


def to_unit(node, prop, v, xy):
    if prop == "rotation":
        return math.radians(v)
    if prop in ("x", "y"):
        return xy[node][0 if prop == "x" else 1] + v
    return v


def emit(f, slots, ease, xy, name, dur_s, loop, timeline, keyed):
    """Write one LinearAnimation keying every prop in `keyed` (rest where unspecified)."""
    frames = max(1, round(dur_s * FPS))
    loopv = {"loop": 1, "oneShot": 0, "hold": 0}[loop]
    f.add("LinearAnimation", name=name, duration=frames, fps=FPS, loopValue=loopv)
    idx = f.anim_count
    f.anim_count += 1
    probes = []
    for node, props in keyed.items():
        for prop in props:
            pts = list(timeline.get((node, prop), []))
            rest_delta = 1.0 if prop in REST else 0.0
            if not pts:
                pts = [(0, rest_delta), (dur_s, rest_delta)]
            if pts[0][0] > 0:
                pts.insert(0, (0, rest_delta))
            if loop != "hold" and pts[-1][0] < dur_s - 1e-9:
                pts.append((dur_s, rest_delta))
            f.add("KeyedObject", objectId=slots[node])
            f.add("KeyedProperty", propertyKey=PROP_KEY[prop])
            last = -1
            for t, v in pts:
                fr = max(round(t * FPS), last + 1 if round(t * FPS) <= last else 0)
                last = fr
                f.add("KeyFrameDouble", frame=fr, value=to_unit(node, prop, v, xy),
                      interpolationType=2, interpolatorId=ease)
            vals = [v for _, v in pts]
            hi = max(vals, key=lambda v: abs(v - rest_delta))
            if abs(hi - rest_delta) > 0:
                probes.append({"node": node, "prop": prop,
                               "extreme": to_unit(node, prop, hi, xy),
                               "mag": abs(hi - rest_delta) * (100 if prop in REST else 1 / 10 if prop == "rotation" else 1 / 10),
                               "t": [t for t, v in pts if v == hi][0]})
    probes.sort(key=lambda p: (-p["mag"], p["node"], p["prop"]))
    return idx, probes


def build_motion(f, slots, ease, node_xy):
    xy = {n: node_xy(n) for n in NODES}
    meta = {"fps": FPS, "rest": {n: {p: rest_value(n, p, xy) for p in props} for n, props in KEYED.items()},
            "animations": []}
    sm = {"moods": []}

    d, k, t = idle()
    idx, pr = emit(f, slots, ease, xy, "idle", d, k, t, BODY)
    sm["idle"] = idx
    meta["animations"].append({"name": "idle", "duration": d, "loop": k, "probes": pr[:3]})
    for i, (nm, fn) in enumerate(MOODS):
        d, k, t = fn()
        name = f"mood{i:02d}_{nm}"
        idx, pr = emit(f, slots, ease, xy, name, d, k, t, BODY)
        sm["moods"].append({"anim": idx, "kind": k, "exit_ms": round(d * 1000)})
        meta["animations"].append({"name": name, "state": i, "duration": d, "loop": k, "probes": pr[:3]})
    # talk layer
    idx, _ = emit(f, slots, ease, xy, "talkOff", 1 / FPS, "loop", {}, TALK)
    sm["talkOff"] = idx
    d, k, t = talk_on()
    idx, pr = emit(f, slots, ease, xy, "talkOn", d, k, t, TALK)
    sm["talkOn"] = idx
    meta["animations"].append({"name": "talkOn", "duration": d, "loop": k, "probes": pr[:3]})
    # reduce-motion still pose
    idx, _ = emit(f, slots, ease, xy, "still", 1 / FPS, "loop", {}, BODY)
    sm["still"] = idx
    meta["sm"] = sm
    return meta
