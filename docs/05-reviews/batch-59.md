# Batch 59 review (T-212, C3), reviewer: code-reviewer (Opus)

Branch `batch/2026-11-23-59`. Procedure: `.claude/commands/review-batch.md`.

## T-212 Build zaghlol.riv in code. Verdict: APPROVED

| Check | Result |
|---|---|
| Generator deterministic | Ran `generate.py` twice to `/tmp`: identical, and byte-identical to committed `app/assets/rive/zaghlol.riv` (277,863 B, under 500 KB). |
| Generator safety | Stdlib only. No network, env, subprocess (except `extract_defs.py`, which only calls `git rev-parse` on a local checkout) or secrets; no timestamps or randomness. |
| Verifier | `npm ci` + `node check.mjs` ran here (Node 22, Chrome present): 43/43 pass (names and input types, state 0-14, talk, reduceMotion, size). |
| App wiring | `ZaghlolAvatar` picks `RiveMascot` when the asset is present; reduce motion (OS or in-app) shows the still and never mounts Rive. `RiveMascot._load` wraps file load, `Factory.rive` access, null decode and controller creation in try/catch and shows the still on any failure; the still is shown while loading. A missing native library or a corrupt `.riv` therefore ends in the still, not a crash or blank. |
| Licensing | No rive-mcp-server code. Keys come from rive-runtime headers (MIT), commit `eaa5e03c...` recorded in README, `rive_defs.json`, task file. |
| Tests | `flutter test test/features/mascot`: 56 passed. `dart analyze`: no issues. |
| Scope | Only T-212 files, plus a `.gitignore` line for the verifier's `node_modules`. No new app dependency (`rive` already present). |

Shipping safety: the Flutter `rive` runtime was never exercised, so playback in the app is unproven. The fallback covers load-time failures (the realistic ones: native library, decode). Shipping before a real-phone check is acceptable. The remaining risk is a paint-time exception inside `RiveWidget` after a successful load, which the try/catch does not cover. Do a real-phone check before the release build.

No blockers or majors.

### Minors (proposed FU-287, owner T-099 or the real-phone check)
1. `rive_mascot.dart`: loading and fallback is only tested for the "no native library" path; the "native present, file loads and plays" path has no automated check on the Flutter side. Verify on a phone (state 0-14, talk, no flicker when `moment` changes).
2. `rive_mascot.dart`: no `RiveNative.init()` call anywhere in `lib/`. If rive 0.14 requires it before `Factory.rive`, the app silently always shows the still. Confirm on the phone.
3. `rive_mascot.dart`: each mount re-reads and decodes the asset (no shared `rive.File`); fine for one avatar per screen, revisit if lists use it.
4. `rive_mascot.dart`: `_push` writes `reduceMotion=false` always; harmless since Rive is not mounted when reducing, but the `reduceMotion` layer is untested in-app.
5. Loop cycle times differ from the interim animation (README notes them); the PO should confirm via `docs/02-design/mascot-riv/contact-sheet.png`.

## Lead delta check
`RiveMascot._load` now awaits `rive.RiveNative.init()` before `File.asset` (rive 0.14 keeps `RiveNative.instance` as a `late` field, so without it every load threw and the still was shown). Failure still falls back to the still. Mascot tests 56/56, analyze clean.
