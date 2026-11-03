# ADR-020: Mascot animation runtime

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-MAS-*, design 08 |

## Context
D-35 approved a rigged mascot with about 15 states, reduce-motion support (FR-MAS-03) and the vector rig traced from the original artwork (`brand/zaghlol-mascot-rig.svg`).

## Options considered
1. ****Rive (`rive` 0.14.x runtime) state machine**** — Inputs map to states; small files; runtime-driven expressions; static fallback.
2. **Lottie** — Timeline animations only; no state-machine inputs; larger JSON.
3. **Flutter-native (CustomPainter + implicit animations on the SVG parts)** — No dependency, but a lot of bespoke code and no designer tooling.

## Decision
**Rive.** An illustrator rebuilds the rig in the Rive editor from the SVG parts. One `zaghlol.riv` file holds one state machine `ZaghlolAvatar` with inputs `state` (enum), `talk` (bool) and `reduceMotion` (bool). A static SVG/PNG pose fallback covers reduce-motion and low-end devices.

## Consequences
An illustrator task is needed before the mascot UI tasks. Runtime about 1 MB native.
