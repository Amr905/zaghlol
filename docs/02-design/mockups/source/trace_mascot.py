"""Trace the original Captain Zaghlol artwork into layered vector parts for rigging."""
import numpy as np, cv2, json
from PIL import Image

im = np.array(Image.open('../kit/assets/mascot-coin.png').convert('RGBA')).astype(int)
H, W = im.shape[:2]
cen = np.load('cen.npy')
rgb, a = im[..., :3], im[..., 3]
d = ((rgb[..., None, :] - cen[None, None]) ** 2).sum(-1)
lab = d.argmin(-1).astype(np.uint8)
lab[a <= 200] = 255
from scipy import ndimage
lum = (rgb * [0.3, 0.59, 0.11]).sum(-1)
fg = a > 200
ink = (lum < 78) & fg
ink = cv2.morphologyEx(ink.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)).astype(bool) & fg
# clean silhouette: close pinholes, then make the outer rim solid ink so no pale edge pixels survive
fg = cv2.morphologyEx(fg.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))).astype(bool)
inner = cv2.erode(fg.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))).astype(bool)
ink |= fg & ~inner
# pale anti-alias specks that touch ink become ink (kills thin white lines inside outlines)
pale = (lum > 175) & ((rgb.max(-1) - rgb.min(-1)) < 45) & fg
near_ink = cv2.dilate(ink.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
cerezone = (np.mgrid[0:H, 0:W][1] > 346) & (np.mgrid[0:H, 0:W][1] < 446) & (np.mgrid[0:H, 0:W][0] > 205) & (np.mgrid[0:H, 0:W][0] < 270)
ink |= pale & near_ink & ~cerezone
# fills: every ink pixel takes the nearest non-ink colour, so fills run under the lines
nonink = fg & ~ink & ~np.isin(lab, [2, 6, 12])
_, (iy, ix) = ndimage.distance_transform_edt(~nonink, return_indices=True)
lab = lab[iy, ix]
lab[~fg] = 255
lab = cv2.medianBlur(lab, 5)
lab[fg & (lab == 255)] = 5
lab[~fg] = 255
INKLAB = 254
lab_full = lab.copy()
INK = {INKLAB}
TEAL = 3
yy, xx = np.mgrid[0:H, 0:W]

def with_ink(labmap, inkmask):
    out = labmap.copy()
    out[inkmask & (labmap != 255)] = INKLAB
    return out

def box(x0, y0, x1, y1):
    return (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)

notteal = (~np.isin(lab, [TEAL, 0, 13, 255])) | ink
feat = {
    'browL': box(296, 112, 356, 150) & notteal,
    'browR': box(498, 124, 566, 176) & notteal,
    'eyeL':  box(276, 184, 354, 246) & notteal,
    'eyeR':  box(458, 200, 564, 266) & notteal,
    'cere':  box(346, 210, 446, 268) & notteal,
}
beak = box(322, 232, 452, 356) & notteal
line_y = 300 - (xx - 332) * 35 / 110
feat['jaw'] = beak & (yy > line_y) & ~feat['cere']
feat['beak'] = beak & (yy <= line_y) & ~feat['cere']
# grow each feature a little so its outline anti-aliasing comes along
for k in feat:
    feat[k] = cv2.dilate(feat[k].astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool) & (lab != 255)

# hand/arm cut follows the left edge of the body outline (the outline itself stays with the body)
cy = np.array([288, 425, 440, 460, 480, 500, 530, 600, 640, 664]); cx = np.array([212, 214, 219, 212, 206, 201, 197, 195, 197, 199])
edge = np.interp(yy, cy, cx)
wing = (xx < edge + 2) & (yy > 288) & (yy < 664) & (lab != 255)
tail = (xx > 762) & (yy > 496) & (yy < 724) & (np.isin(lab, [3, 0, 13]) | (ink & (xx > 792)))
tail = cv2.morphologyEx(tail.astype(np.uint8), cv2.MORPH_OPEN, np.ones((5,5),np.uint8)).astype(bool)

# base = everything else; face features replaced by hood teal underneath
base = lab.copy()
facemask = np.zeros_like(wing)
for k in feat: facemask |= feat[k]
base[facemask] = TEAL
base[wing] = 255
base[tail] = 255
base = with_ink(base, ink & ~facemask & ~wing & ~tail)

def part_labels(mask):
    out = np.full_like(lab, 255)
    out[mask] = lab[mask]
    return with_ink(out, ink & mask)

def to_path(cnt):
    pts = cnt[:, 0, :].astype(float)
    n = len(pts)
    if n < 3: return ''
    # quadratic smoothing through midpoints
    mids = (pts + np.roll(pts, -1, 0)) / 2
    s = f'M{mids[-1][0]:.1f} {mids[-1][1]:.1f}'
    for i in range(n):
        s += f'Q{pts[i][0]:.1f} {pts[i][1]:.1f} {mids[i][0]:.1f} {mids[i][1]:.1f}'
    return s + 'Z'

def trace(labmap, min_area=6):
    """Return list of (colour, path) layers: large fills first, ink last."""
    present = [l for l in np.unique(labmap) if l != 255]
    areas = {l: (labmap == l).sum() for l in present}
    order = sorted([l for l in present if l not in INK], key=lambda l: -areas[l]) + [l for l in present if l in INK]
    layers = []
    # silhouette underlay in the part's dominant fill so seams never show background
    sil = (labmap != 255).astype(np.uint8)
    for l in order:
        m = (labmap == l).astype(np.uint8)
        if l not in INK:
            m = cv2.dilate(m, np.ones((3, 3), np.uint8)) & sil
        cnts, hier = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
        ds = []
        for c in cnts:
            if abs(cv2.contourArea(c)) < (min_area if l in INK else max(min_area, 40)): continue
            c = cv2.approxPolyDP(c, 1.1, True)
            p = to_path(c)
            if p: ds.append(p)
        if ds:
            r, g, b = (29, 64, 57) if l == INKLAB else cen[l]
            layers.append((f'#{r:02x}{g:02x}{b:02x}', ''.join(ds)))
    return layers

def sil_path(labmap):
    m = cv2.morphologyEx((labmap != 255).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5,5),np.uint8))
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    return ''.join(to_path(cv2.approxPolyDP(c, 1.2, True)) for c in cnts if cv2.contourArea(c) > 200)

wl, tl = part_labels(wing), part_labels(tail)
parts = {'base': trace(base), 'wing': trace(wl), 'tail': trace(tl)}
parts['sil'] = {'base': sil_path(base), 'wing': sil_path(wl), 'tail': sil_path(tl)}
for k in feat:
    parts[k] = trace(part_labels(feat[k]), min_area=3)
json.dump(parts, open('parts.json', 'w'))
print({k: len(v) for k, v in parts.items()})
