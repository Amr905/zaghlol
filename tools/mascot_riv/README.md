# tools/mascot_riv: build `zaghlol.riv` from code

`app/assets/rive/zaghlol.riv` (Captain Zaghlol, artboard `Zaghlol`, state machine `ZaghlolAvatar`, inputs `state` / `talk` / `reduceMotion`) is generated here, with no Rive editor (PO decision MASCOT-RIV-CODE). Since T-232 the motion is **the approved Motion Lab, parsed literally**: `docs/02-design/motion/zaghlol-motion.html` (its `@keyframes`, `.zg`/`.st-<mood>` rules and prop code) is the single source; nothing is re-keyed by hand. The generator is deterministic: the same inputs give the same bytes.

## Rebuild

```bash
python3 tools/mascot_riv/generate.py          # writes app/assets/rive/zaghlol.riv and tools/mascot_riv/moods.json
```

Python 3 standard library only. Inputs: the Lab HTML and `docs/02-design/brand/zaghlol-mascot-rig.svg` (the rig paths).

## Files

| File | What |
|---|---|
| `labcss.py` | Reads the Lab: `@keyframes`, cascade (specificity, order) of `.zg .part` / `.st-<mood> .part`, CSS transform lists, cubic-bezier easing, animation shorthand, evaluation at a time |
| `scene.py` | Node tree (Lab hierarchy, pivots from the CSS `transform-origin`), the `stage` scale into the 1000 square artboard, the `fx` pixel-to-unit scale |
| `motion.py` | Compiles the Lab into Rive tracks: 16 body animations (idle + 15 moods), ambient breathe / wag / blink, jaw talk |
| `fx.py` | The Lab's HTML props (coins, dots, envelopes, confetti, rain, rings, cloud, Zzz, bars) as vector items and tracks; `mulberry32` seed replaces `Math.random` |
| `shapes.py` | SVG path / ellipse / rounded-rect helpers to cubic vertices |
| `generate.py` | Writes the file: nodes, shapes (front to back), interpolators, animations, 7 state machine layers |
| `rivefile.py`, `rive_defs.json`, `extract_defs.py` | Minimal `.riv` v7 writer and the type/property keys from `rive-app/rive-runtime` at `eaa5e03` (MIT) |
| `moods.json` | Written by the generator: animation names, lengths, kinds and the stage crop |
| `contact_sheet.py` | Lab vs `.riv` side by side per mood, plus an unmatched-pixel gate |
| `verify/check.mjs`, `verify/lab_expect.py`, `verify/expectations.json` | The Lab's per-part ranges (derived from the Lab by `lab_expect.py`) checked against the file played by the official runtime |
| `verify/lab_capture.mjs`, `verify/render.mjs`, `verify/shots.json` | Headless Chrome screenshots of the Lab (animations paused at t, same random seed) and of the `.riv` at the same times |

## Layers of the state machine

`breath` (3 s), `tail` (2.6 s) and `blink` (4.2 s) are ambient loops, each with the Lab's own clock; `moods` holds the body (bird, head, wing, brows, pupils, eyes, jaw) and shows or hides the expression parts (open/closed/happy eyes, closed beak, hat, magnifier, glasses, pointer, sweat); `fx` plays the props with clocks that differ from the body (scan envelopes 1.6 s, rings 1.8 s, Zzz 2.4 s, confetti 1.4 s, rain up to 2.2 s); `talk` is the Lab's jaw `talk` (-8 degrees, 0.34 s); `reduceMotion` holds the rest pose. `state` -1 is idle, 0-14 are the moments in `ZaghlolMoment` order; one-offs return to idle by themselves, loops loop while `state` stays, sleep stops after two breaths, pull has no mix-in (the bird drops in from above).

## Verify (needs Node 20+ and Chrome; `CHROME=/path/to/chrome` if not at `/usr/bin/google-chrome`)

```bash
cd tools/mascot_riv/verify && npm ci
node check.mjs ../../../app/assets/rive/zaghlol.riv                 # 59 checks, exit 1 on any failure
node lab_capture.mjs /tmp/lab && node render.mjs ../../../app/assets/rive/zaghlol.riv /tmp/riv
python3 ../contact_sheet.py /tmp/lab /tmp/riv ../../../docs/02-design/mascot-riv/lab-vs-riv   # exit 1 over the limit
python3 lab_expect.py > expectations.json                           # only after the Lab changes
```

`check.mjs` proves: names and input types; for every `state` 0-14 from a fresh start, its animations (`moodNN_*`, and `fxNN_*` for moments with props) play and every part (and prop) sweeps the range the Lab's CSS gives it; one-offs return to idle and stay there; loops keep looping; sleep holds still; all 210 ordered switches; replay; `state` < 0 returns to idle with its props; breathe / wag / blink amplitudes; `talk` true/false, also during a mood; `reduceMotion` freezes the pose; size is at most 500 KB. Visibility of parts (the Lab's `display`) and props cannot be read from the runtime, so the contact sheets carry it: every frame is compared with the Lab's and fails the gate when more than 600 pixels have no match within 4 px (a missing hat, wrong eyes or missing prop is thousands). `flutter test` cannot load `rive_native`, so the Flutter-side tests check the asset, the contract strings and the avatar's selection logic; `app/integration_test/rive_mascot_device_test.dart` runs every state on the emulator (`device-flows`).

## Known differences from the Lab (on purpose)

- The idle blink also closes the happy eyes (doc section 1); the Lab blinks only the open eyes.
- Loops start in their steady state: the Lab's start-up delays (infinite animations with `animation-delay` show their un-animated style until the delay passes) are not reproduced. The five count coins share one phase in the Lab, so one coin is drawn.
- `Math.random` (confetti, rain) is the fixed `mulberry32(20261123)`; the capture uses the same seed.
- Sleep stops after two breaths (6.4 s) and the Zzz stop with it; the Lab loops for ever.
- Props use the light-theme colours; the artboard clips (Lab: the stage's edges), and the bird is 11% smaller in its box than in T-212 to leave room for props.

## Format notes (learned the hard way)

- Draw order: the runtime paints the last drawable in the file first, so shapes are written front to back.
- Layer states carry no names in the file; `stateChangedNameByIndex` reports the animation name.
- Visibility is a keyed `opacity` on the part's node (CSS `display`), mixed by the state transitions.
- Layers apply in file order, later ones win; the mood layer only keys `breath` / the open-eye blink in the moods where the Lab overrides them (shock, sleep), so the ambient layers keep running elsewhere.
- Every mood animation keys the full set of body properties, so switching moods never leaves a part displaced; prop nodes are hidden by their group's opacity.
- A one-off is one frame longer than the Lab's animation, so the frame that the CSS snaps back to the base pose is in the file (a spin ending at 360 degrees would otherwise mix back).
