# Mascot Rive hand-off (T-088 -> T-099)

The app already runs Captain Zaghlol with an interim Flutter animation of the approved brand still (`app/lib/features/mascot/presentation/interim_mascot.dart`). When `app/assets/rive/zaghlol.riv` exists in the build, `ZaghlolAvatar` selects `RiveMascot` automatically (no code change). Rebuild `brand/zaghlol-mascot-rig.svg` in Rive; keep the character exactly as in the rig.

## File
- Path: `app/assets/rive/zaghlol.riv` (add `assets/rive/` to `app/pubspec.yaml` assets when the file lands; the app checks the asset manifest). Max 500 KB.
- Runtime: `rive` 0.14.x (legacy state machine inputs).

## Names (constants in `rive_mascot.dart`)
| Item | Name | Type / values |
|---|---|---|
| Artboard | `Zaghlol` | square, character centred |
| State machine | `ZaghlolAvatar` | |
| Input | `state` | Number. Index of the moment: 0 tourGuide, 1 proud, 2 shocked, 3 detective, 4 professor, 5 listening, 6 thinking, 7 scanning, 8 counting, 9 saved, 10 payday, 11 oops, 12 sleep, 13 pull, 14 tap (order of `ZaghlolMoment`) |
| Input | `talk` | Boolean. Beak moves while true |
| Input | `reduceMotion` | Boolean. The app never mounts Rive when reduce motion is on (it shows the still), so this is for the file's own preview |

Deviation from T-088 wording: it says `state` is an enum. Rive state machine inputs have no enum type, so a Number is used. If the illustrator prefers a data-binding enum, tell the lead; the change is in `rive_mascot.dart` only.

## Timing (08-mascot-motion section 1)
Looping only while real work runs: listening, thinking, scanning, counting. One-offs <= 3 s then rest on the idle pose: tourGuide 1.6 s, proud 0.9, shocked 1.1, detective 2.0, professor 1.4, saved 0.9, payday 1.6, oops 1.4, sleep 2.8 (two breaths), pull follows the finger, tap 0.8. Setting `state` again to the same value must replay (the app toggles via a different value first when needed).
