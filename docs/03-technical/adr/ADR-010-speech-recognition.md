# ADR-010: Voice entry speech recognition

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-VOI-*, EC-32 |

## Context
FR-VOI-01 needs ar-EG and English speech-to-text, preferably on device (R-05). OQ-06 asks whether the OS's online recognizer may be used with consent. On-device Arabic availability varies by device and OS version.

## Options considered
1. **Platform recognizers via `speech_to_text`, on-device first** — No extra model; quality equals the OS dictation.
2. **Bundled offline ASR model (e.g. Whisper-small)** — Consistent offline support, but 100+ MB, slow on mid-range phones, weaker on Egyptian dialect without fine-tuning.

## Decision
**Option 1.** The app requests on-device recognition. If ar-EG on-device isn't available, it explains and offers (a) the OS online recognizer **only after explicit consent** (recommended answer to OQ-06; audio goes to Google/Apple, not Zaghlol) or (b) manual entry. The phrase parser (domain §9) is independent of the recognizer.

## Consequences
Behaviour differs by device. Consent copy goes in the copy deck. The product owner must confirm OQ-06.
