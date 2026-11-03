# ADR-009: OCR for screenshots and receipts

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | platform-channels §4 |

## Context
FR-ING-I-04 needs on-device OCR of Arabic and English receipts (InstaPay screens). Google ML Kit Text Recognition v2 supports Latin, Chinese, Devanagari, Japanese and Korean scripts, **not Arabic**. Apple Vision exposes its supported recognition languages at runtime.

## Options considered
1. **ML Kit only** — Small; reads digits and English, misses Arabic labels/names.
2. ****iOS: Vision; Android: ML Kit Latin + Tesseract (`ara` fast model) merged by box**** — Covers Arabic on both platforms; about 1.5 MB extra on Android.
3. **Cloud OCR** — Violates the data boundary.

## Decision
**Option 2.** InstaPay/wallet receipt templates focus on amount, IPA/reference and date, which are mostly Latin digits. Arabic text improves counterparty names. **CR-02** records the Tesseract dependency.

## Consequences
A spike (SPK-02) measures accuracy on 50 synthetic receipt images per platform before the OCR task starts. If iOS Vision lacks Arabic on a device, the app falls back to Latin-only plus user editing.
