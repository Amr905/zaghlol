# ADR-024: App size, and what to do about the OCR engines and PDFium

| | |
|---|---|
| Status | **Proposed** (PO decision needed; nothing in this ADR is implemented) |
| Date | 2026-11-20 |
| Deciders | Product owner (approval), native-platform-engineer (author, T-190) |
| References | T-190, `docs/05-reviews/T-190-size.md`, NFR-PERF-07, D-69, ADR-009 (OCR), ADR-020 (mascot), T-156 (PDF import) |

## Context
The PO reported about 150 MB. T-190 measured (see the size report): the release Play download for arm64 is 28.8 MiB and the unsigned iOS IPA 17.4 MiB, both under the proposed NFR-PERF-07 targets (40 MB / 60 MB). The large numbers come from debug (278 MiB) and universal (179 MiB, now 115 MiB without x86_64) builds and from the AAB's debug symbols and R8 mapping, which users never download. Installed size on an arm64 phone is about 63 MiB because native libraries are stored uncompressed.

The remaining weight of the arm64 download: Flutter engine 5.2 MiB, Dart AOT 5.0, OCR 8.7 (ML Kit 5.2, Tesseract + Leptonica 2.8, `ara` model 0.7), PDFium 3.2, Rive 2.7, SQLite3MultipleCiphers 1.0, dex 1.5, assets 0.9.

The task forbids dropping or deferring an OCR engine or PDFium without a PO decision, so this ADR only records the options.

## Options
| # | Option | Download saved (arm64) | Breaks | Effort |
|---|---|---|---|---|
| 0 | **Do nothing**: ship per-ABI AAB, no x86_64 (done in T-190), size guard in CI | 0 | nothing; the 40 MB target is met with 11 MiB of headroom | done |
| A | Drop Tesseract and the `ara` model; ML Kit Latin only | 3.5 MiB | Arabic text on receipts is not read (names, labels); OcrMerger simplifies | 2-3 days; needs the SPK-02 accuracy numbers |
| B | Drop ML Kit; Tesseract `ara` + `eng` | about 2-3 MiB net | Latin and digit accuracy probably lower; removes the datatransport exclusion and the open privacy point in ADR-009 (CR-02) | 3-5 days plus accuracy run |
| C | OCR as a Play Feature Delivery on-demand module | 8.7 MiB | first scan needs a download; Play installs only (side-loads need the fused module); SplitCompat and Play feature-delivery dependency; nothing on iOS (Apple Vision is built in) | 1-2 weeks |
| D | PDFium as an on-demand module | 3.2 MiB | pdfrx's PDFium is a Flutter native asset that cannot sit in a dynamic feature; needs a custom loader or fork | 2+ weeks, high risk |
| E | OS PDF APIs instead of PDFium (Android `PdfRenderer`, iOS PDFKit) | 3.2 MiB (Android), 3.1 (iOS) | no text extraction from `PdfRenderer`; T-156 would have to OCR rendered pages | 1-2 weeks, behaviour change |
| F | Defer `rive` until `zaghlol.riv` exists (T-088) | 2.7 MiB | nothing today (no `.riv` file; `RiveMascot` already falls back to the PNG) | half a day |

## Decision
**Proposed:** keep both OCR engines and PDFium for now (Option 0), because the NFR-PERF-07 targets are met and each of A-E trades product capability or risk for size. Option F is recommended as a free saving if the PO agrees to defer the Rive runtime until the animation file ships. If a smaller download is wanted later, decide A or B on the SPK-02 accuracy numbers; C is the largest single saving.

This stays "Proposed" until the PO answers. T-190 does not change the shipped OCR, PDF or mascot code.

## Consequences
- Option 0: no change; the CI size guard (`.github/size-baseline.json`) fails a release build that grows by more than 10 % or passes 40 MiB (arm64 Play download) / 60 MiB (App Store). Raising a baseline is an explicit edit in the same commit.
- Release builds no longer contain x86_64 libraries (x86_64 phones, emulators and some Chromebooks cannot install the release; debug and the device-flow emulators are unaffected; `-Pzaghlol.releaseX86=true` keeps them for a release smoke run).
- Any of A-F changes the privacy and accuracy picture documented in ADR-009 and must update it, the Data-safety / privacy docs under `docs/06-release/` and requirements D-69.
