# Institution logos

Bank, wallet and BNPL logos are trademarks. Nothing is bundled yet. Before shipping any logo the PO must hold written permission from the institution or use a licensed source, and record it in the table at the bottom.

## Adding a logo
1. Get the official asset under that permission. Do not redraw, recolour or trace it.
2. Square PNG or WebP, 256x256 px, transparent or on the brand background, under 30 KB. The avatar clips it to a circle, so keep 12% padding.
3. Save as `app/assets/brand/logos/<institution_code>.png` (code from `app/assets/registry/institutions/`).
4. In `app/assets/brand/institutions_brand.json` set `logoAsset` to `assets/brand/logos/<code>.png` and check `brandColor` against the institution's brand guide.
5. If the file is missing or fails to load, the avatar shows initials on the brand colour, then the neutral style. No code change needed.

## Permission log
| Code | Source / licence | Granted by | Date |
|------|------------------|-----------|------|
