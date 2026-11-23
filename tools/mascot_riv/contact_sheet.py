#!/usr/bin/env python3
"""Compose frames rendered by verify/render.mjs into contact sheets (Pillow).
Usage: contact_sheet.py <frames_dir> <out_dir>"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

frames, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
names = ["idle"] + [p.stem for p in sorted(frames.glob("mood*.png"))] + ["talk", "reduceMotion"]
CELL, COLS = 256, 5
BG = (243, 251, 247)  # mint bg #F3FBF7
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
except OSError:
    font = ImageFont.load_default()
rows = (len(names) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * CELL, rows * (CELL + 24)), BG)
d = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    im = Image.open(frames / f"{n}.png").convert("RGBA").resize((CELL, CELL), Image.LANCZOS)
    x, y = (i % COLS) * CELL, (i // COLS) * (CELL + 24)
    sheet.paste(im, (x, y + 24), im)
    d.text((x + 8, y + 4), n, fill=(15, 42, 32), font=font)
sheet.quantize(160).save(out / "contact-sheet.png", optimize=True)
print("saved", out / "contact-sheet.png", sheet.size)
