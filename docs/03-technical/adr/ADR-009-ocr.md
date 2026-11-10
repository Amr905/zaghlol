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

## Implementation notes (T-159, Android)
- **Pinned versions:** `com.google.mlkit:text-recognition:16.0.1` (bundled Latin model; no Play Services download), `cz.adaptech.tesseract4android:tesseract4android:4.9.0` (standard single-thread build, Tesseract 5.5; the OpenMP build was not chosen: larger, and one recognition runs at a time anyway), model `ara.traineddata` from tessdata_fast, 1,432,056 bytes, SHA-256 `e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729` (checked by `TessdataInstaller` and by a unit test against the asset). Licences: Tesseract4Android and tessdata_fast Apache-2.0; ML Kit under the Google ML Kit terms.
- **Size (measured from the published artifacts, not from a built APK):** ML Kit bundled adds about 4.4 MB (arm64-v8a) / 3.5 MB (armeabi-v7a) compressed per ABI (`libmlkit_google_ocr_pipeline.so`, 11 MB raw) plus a few hundred KB of model assets and Java; the `ara` model is 1.4 MB and compresses little; the Tesseract native libraries add a few MB per ABI (to be measured). A universal APK carries all ABIs; use per-ABI splits or an app bundle for release.
- **Open privacy point (needs a PO decision before release):** the bundled ML Kit pulls in `transport-backend-cct`, whose manifest declares `INTERNET` and `ACCESS_NETWORK_STATE`, and `com.google.mlkit:common` reports SDK usage through Google's data transport. The app has no `INTERNET` in release manifests today (only debug and profile), but the backend features will need it. Constraint 1 and BR-SYNC-03 allow no other traffic. Options: (a) keep ML Kit and exclude the data-transport artifacts (risk: runtime failure, needs a device test); (b) replace ML Kit Latin by Tesseract `eng`/`ara` only (accuracy to be measured in SPK-02); (c) accept and disclose. Not decided by T-159.
- **SPK-02:** T-010 has no results in the repository, so the accuracy numbers this ADR requires are still missing; the merge thresholds in `OcrMerger` are unvalidated.
