"""Node tree of the Rive scene (names, parents, pivots), all in the Lab's user units.

Pivots are the Lab's CSS transform-origins (labcss reads them); a node's rest position is its
pivot minus its parent's pivot.  `stage` scales the Lab units into the artboard; `fx` re-bases
the Lab's HTML-prop pixels (stage 380x400, bird 76% high) onto the same units.
"""
import labcss as L

LAB = L.Lab()
ART = 1000.0
S = 0.75                      # Lab unit -> artboard unit
VTOP = -345.0                 # Lab v shown at the artboard top
UCENTER = 500.0               # Lab u shown at the artboard centre (the bird's own centre)
STAGE_W, STAGE_H = 380.0, 400.0
K = 1090.0 / (0.76 * STAGE_H)  # Lab units per stage pixel (svg viewBox 1090 high, drawn 76% of 400)
FX_U0 = 460.0 - (STAGE_W / 2) * K                       # Lab u of stage px x=0
FX_V0 = -110.0 - (STAGE_H - 6 - 0.76 * STAGE_H) * K     # Lab v of stage px y=0 (svg bottom sits 6 px up)


def _o(el):
    return LAB.origin(el)


# (name, parent, pivot) in build order; the parent comes first
NODES = [
    ("stage", None, (0.0, 0.0)),
    ("bird", "stage", _o("bird")),
    ("breath", "bird", _o("breath")),
    ("tail", "breath", _o("tail")),
    ("wingL", "breath", _o("wingL")),
    ("pointer", "wingL", _o("wingL")),
    ("head", "breath", _o("head")),
    ("brows", "head", _o("brows")),
    ("eyeHappyL", "head", (317.0, 219.0)),
    ("blinkHappyL", "eyeHappyL", (317.0, 219.0)),
    ("eyeHappyR", "head", (511.5, 235.75)),
    ("blinkHappyR", "eyeHappyR", (511.5, 235.75)),
    ("eyeOpenL", "head", (315.0, 214.0)),
    ("eyeL", "eyeOpenL", (315.0, 214.0)),
    ("blinkL", "eyeL", (315.0, 214.0)),
    ("pupilsL", "blinkL", (305.0, 222.0)),
    ("eyeOpenR", "head", (511.0, 232.0)),
    ("eyeR", "eyeOpenR", (511.0, 232.0)),
    ("blinkR", "eyeR", (511.0, 232.0)),
    ("pupilsR", "blinkR", (500.0, 240.0)),
    ("eyeClosed", "head", _o("head")),
    ("jaw", "head", _o("jaw")),
    ("mouthClosed", "head", _o("head")),
    ("glasses", "head", _o("head")),
    ("hat", "head", _o("head")),
    ("mag", "head", _o("head")),
    ("sweat", "head", _o("head")),
    ("fx", "stage", (0.0, 0.0)),
]
PIVOT = {n: p for n, _, p in NODES}
PARENT = {n: par for n, par, _ in NODES}


def add_node(name, parent, pivot):
    NODES.append((name, parent, pivot))
    PIVOT[name] = pivot
    PARENT[name] = parent


def rest(name):
    """Rest x, y of a node relative to its parent's pivot."""
    if name == "stage":
        return (UCENTER * (1 - S), -VTOP * S)
    if name == "fx":
        return (FX_U0, FX_V0)
    p = PARENT[name]
    px, py = PIVOT[name]
    ox, oy = PIVOT[p] if p else (0.0, 0.0)
    return (px - ox, py - oy)
