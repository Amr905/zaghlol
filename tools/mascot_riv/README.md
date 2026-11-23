# tools/mascot_riv: build `zaghlol.riv` from code

`app/assets/rive/zaghlol.riv` (Captain Zaghlol, artboard `Zaghlol`, state machine `ZaghlolAvatar`, inputs `state` / `talk` / `reduceMotion`) is generated here, with no Rive editor (PO decision MASCOT-RIV-CODE). The generator is deterministic: the same inputs give the same bytes.

## Rebuild

```bash
python3 tools/mascot_riv/generate.py          # writes app/assets/rive/zaghlol.riv and tools/mascot_riv/moods.json
```

Python 3 standard library only. Inputs: `docs/02-design/brand/zaghlol-mascot-rig.svg` (the rig; groups become named nodes) and the motion tables in `motion.py`.

## Files

| File | What |
|---|---|
| `generate.py` | Rig to Rive hierarchy (shapes, cubic paths, fills/strokes), then the state machine |
| `motion.py` | The 17 animations: idle, 15 moods, talk (timings from `docs/02-design/08-mascot-motion-and-bank-logos.md` section 1) |
| `rig.py` | SVG (M/Q/Z paths in named groups) parser |
| `rivefile.py` | Minimal `.riv` v7 binary writer (varuint, float32, color, string; ToC; artboard-local ids) |
| `rive_defs.json` | Type and property keys, extracted by `extract_defs.py` from the official generated headers of `rive-app/rive-runtime` at commit `eaa5e03cfa81ab3cdfa002e8b4ed40d957194fa4` (MIT). The public repo no longer ships `dev/defs`. |
| `extract_defs.py` | `python3 extract_defs.py <rive-runtime checkout> > rive_defs.json` (only needed to refresh the keys) |
| `moods.json` | Written by the generator: timings, rest pose and the keyed poses the checker expects |
| `verify/check.mjs` | Loads the file with the official `@rive-app/canvas-advanced` WASM runtime in headless Chrome and checks it (see below) |
| `verify/render.mjs`, `contact_sheet.py` | Render one frame per mood with the same runtime and compose `docs/02-design/mascot-riv/contact-sheet.png` |

## Verify (needs Node 20+ and Chrome; `CHROME=/path/to/chrome` if not at `/usr/bin/google-chrome`)

```bash
cd tools/mascot_riv/verify && npm ci
node check.mjs ../../../app/assets/rive/zaghlol.riv          # 43 checks, exit 1 on any failure
node render.mjs ../../../app/assets/rive/zaghlol.riv /tmp/frames
python3 ../contact_sheet.py /tmp/frames ../../../docs/02-design/mascot-riv
```

`check.mjs` proves: names and input types; every `state` 0-14 (from a fresh start and for all 210 ordered switches) enters its own animation and reaches its keyed poses; one-offs return to idle and stay there; loops keep looping; `state` set again after another value replays; `talk` true/false moves and closes the beak, also during a mood; `reduceMotion` freezes the pose; size is at most 500 KB. `flutter test` cannot load `rive_native` (its library comes from a host this workspace cannot reach), so the Flutter-side test only checks the asset, the contract strings and the avatar's selection logic.

## Format notes (learned the hard way)

- Draw order: the runtime paints the last drawable in the file first, so shapes are written front to back.
- Layer states carry no names in the file; `stateChangedNameByIndex` reports the animation name.
- Every animation keys the full set of animated properties, so switching moods never leaves a part displaced.
- `state` defaults to -1 (idle); a negative value returns any mood to idle. Layers: `moods`, `talk` (jaw, beak, cere only), `reduceMotion` (holds the rest pose while true).
