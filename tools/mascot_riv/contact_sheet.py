#!/usr/bin/env python3
"""Side-by-side contact sheets: the Motion Lab (verify/lab_capture.mjs) above our .riv
(verify/render.mjs), one PNG per mood, one column per time in verify/shots.json.
Usage: contact_sheet.py <lab_dir> <riv_dir> <out_dir>; prints a per-frame difference score."""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

lab, riv, out = (Path(a) for a in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
shots = json.loads((Path(__file__).parent / "verify/shots.json").read_text())
BG = (212, 244, 228)  # the Lab stage colour used for both
CW, CH = 380, 400
LIMIT = 600  # unmatched pixels in a 332x352 frame (see README)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
except OSError:
    font = ImageFont.load_default()


def load(p, comp):
    im = Image.open(p).convert("RGBA")
    if comp:
        bg = Image.new("RGBA", im.size, BG + (255,))
        im = Image.alpha_composite(bg, im)
    return im.convert("RGB").resize((CW, CH), Image.LANCZOS)


def bad_pixels(a, b, shift=4, thr=60):
    """Pixels of the Lab frame that no pixel within `shift` px of the .riv frame matches (and the
    other way round): small timing lags only move edges, a missing or wrong part does not match."""
    x, y = np.asarray(a).astype(int), np.asarray(b).astype(int)

    def one_way(p, q):
        best = np.full(p.shape[:2], 255)
        for dy in range(-shift, shift + 1):
            for dx in range(-shift, shift + 1):
                best = np.minimum(best, np.abs(p - np.roll(q, (dy, dx), (0, 1))).max(axis=2))
        return int((best[24:-24, 24:-24] > thr).sum())

    return max(one_way(x, y), one_way(y, x))


scores = {}
for mood, times in shots.items():
    sheet = Image.new("RGB", (CW * len(times), 2 * (CH + 22)), (243, 251, 247))
    d = ImageDraw.Draw(sheet)
    for i, t in enumerate(times):
        name = f"{mood}_{round(t * 1000)}.png"
        a, b = load(lab / name, False), load(riv / name, True)
        diff = ImageStat.Stat(ImageChops.difference(a, b)).mean
        score = sum(diff) / 3
        sheet.paste(a, (i * CW, 22))
        sheet.paste(b, (i * CW, CH + 44))
        d.text((i * CW + 6, 3), f"{mood} t={t}s  LAB", fill=(15, 42, 32), font=font)
        d.text((i * CW + 6, CH + 25), f"{mood} t={t}s  RIV  diff={score:.1f}", fill=(15, 42, 32), font=font)
        bad = bad_pixels(a, b)
        scores[name] = bad
        print(f"{mood:8s} t={t:4.2f}  diff={score:5.1f}  unmatched_px={bad}")
    sheet.quantize(200).save(out / f"{mood}.png", optimize=True)
(out / "scores.json").write_text(json.dumps(scores, indent=1, sort_keys=True) + "\n")
worst = max(scores.values())
print("worst unmatched px:", worst)
sys.exit(1 if worst > LIMIT else 0)
