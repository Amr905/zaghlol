# T-190 — App size report (measured 2026-11-20)

Measured in GitHub Actions (`size-report.yml`, Flutter 3.47.9, `ubuntu-latest` / `macos-15` with Xcode 26). Before = commit `8a1c6fd0` plus the workflow; after = this branch. All numbers are bytes from the built files; MiB = 1,048,576 bytes. Raw logs and per-component tables are in the run summaries and in the `size-android-*` / `size-ios` artifacts of the runs listed at the end (30-day retention). No binary was uploaded (public repo).

## 1. Which artifact is "150 MB"?

It cannot be proven from here which file the PO looked at. Candidates, all measured on the unchanged code (prodSms):

| Artifact | Size before | Comment |
|---|---|---|
| Debug universal APK (`devSms`, the CI artifact the PO sideloads) | **278.1 MiB** (291.6 MB) | 153 MB of it is the uncompressed Dart kernel (`flutter_assets`) plus 3 x debug `libflutter.so` (33-40 MB each) plus the Vulkan validation layer (15 MB). Installed on one phone it is still about 150 MB or more. |
| Release universal APK (3 ABIs) | 179.1 MiB | native `.so` files are stored uncompressed (16 KB aligned), so the file is the sum of three ABIs |
| Release AAB (3 ABIs) | 127.9 MiB | includes 33 MB R8 mapping and per-ABI native debug symbols that Play strips; never downloaded by users |
| Release arm64 APK (what a phone installs) | 63.3 MiB | |
| **Play download, arm64 (bundletool `get-size total`)** | **28.8 MiB** | what a user downloads |

So the number the PO saw is almost certainly a debug or universal build; the real store download is far smaller. The Play download already met the proposed 40 MB target before any change.

## 2. Before / after

| Artifact (prodSms; prodNoSms differs by under 20 KB) | Before | After | Change |
|---|---|---|---|
| Debug universal APK (unchanged: debug keeps x86_64) | 278.11 MiB | 278.11 MiB | 0 |
| Release universal APK | 179.12 MiB | **115.51 MiB** | -63.6 MiB (x86_64 dropped) |
| Release APK arm64-v8a (installed size) | 63.30 MiB | 63.38 MiB | +0.08 MiB (explicit keep rules) |
| Release APK armeabi-v7a | 52.41 MiB | 52.49 MiB | +0.08 MiB |
| Release APK x86_64 | 66.77 MiB | not shipped | |
| Release AAB (upload size) | 127.94 MiB | **86.63 MiB** | -41.3 MiB |
| Play download arm64-v8a (bundletool) | 28.79 MiB (30,190,585 B) | 28.88 MiB (30,284,567 B) | +0.09 MiB |
| Play download armeabi-v7a (bundletool) | not measured | 26.97 MiB (28,284,704 B) | |
| Play download x86_64 | 29.68 MiB (apkanalyzer estimate) | not served | x86_64 devices (emulators, some Chromebooks) lose support |
| iOS unsigned IPA (arm64 only), prod | 17.36 MiB | 17.36 MiB (no iOS change) | |

R8 and resource shrinking were already on before this task (the Flutter Gradle plugin enables them for release unless `-Pshrink=false`; a 33 MB `mapping.txt` was produced). Making them explicit and adding `proguard-rules.pro` therefore saved nothing and costs 94 KB of dex (`classes.dex` 1.59 MB to 1.68 MB compressed) because the belt-and-braces keep rules retain classes the libraries' own consumer rules would also keep. That is the price of the explicit, reviewed rule set; the rules can be narrowed once a release smoke run on a device exists.

Targets (NFR-PERF-07, proposed, not yet confirmed by the PO): Play download arm64 <= 40 MB: **met (28.9 MiB)**. App Store download <= 60 MB: **met** (unsigned IPA 17.4 MiB is an upper bound of the download; the real App Thinning report needs a signed export and could not be produced here).

## 3. Where the arm64 Play download goes (about 30 MB)

Compressed bytes taken from the per-file listing of the release AAB (arm64 split, all values MiB):

| Component | Compressed | Installed (raw) | Notes |
|---|---|---|---|
| `libapp.so` (Dart AOT) | 5.04 | 13.2 | 4 MB `package:zaghlol`, 4 MB Flutter, 0.8 `pointycastle`; `googleapis` is tree-shaken out of the AOT snapshot (absent from the symbol list) |
| `libflutter.so` (engine) | 5.23 | 11.2 | fixed cost |
| `libmlkit_google_ocr_pipeline.so` (ML Kit) | 4.20 | 10.6 | plus about 1.0 MiB of ML Kit model assets |
| `libpdfium.so` (pdfrx) | 3.16 | 6.3 | plus 5 KB gate library |
| `librive_native.so` (Rive) | 2.68 | 7.3 | **no `.riv` file exists yet** (`find` finds none): the mascot is the PNG still until T-088 |
| `libtesseract.so` + `libleptonica.so` | 1.60 + 1.20 | 4.0 + 2.7 | plus `ara.traineddata` 0.69 (1.37 raw) |
| `libsqlite3mc.so` | 0.97 | 1.9 | needed (ADR-002) |
| `classes.dex` | 1.51 (1.60 after) | 3.3 | Flutter, androidx, Play services auth, Billing, WorkManager, Glance |
| `flutter_assets` (fonts 0.4, mascot PNG 0.22, catalog, registry) | 0.85 | 1.6 | |
| resources, other | 0.9 | | |

OCR as a whole (ML Kit + Tesseract + Leptonica + models) is about 8.7 MiB of the download (30 %); PDFium 3.2 MiB (11 %); Rive 2.7 MiB (9 %); the engine plus Dart code 10.3 MiB (35 %).

Small wins evaluated (step 5) and not applied:
- **Font subsetting:** the four IBM Plex Sans Arabic files already contain only Arabic and Latin. Subsetting to Arabic, Latin-1/Extended-A, general punctuation and currency symbols (fonttools, layout features kept) gives 968 KB to 864 KB raw, about 90 KB after compression (0.3 % of the download) and risks tofu for characters outside the kept ranges. Skipped.
- **`googleapis`:** tree-shaken by AOT (the package does not appear in the Dart symbol breakdown); the cost is only `pub get` time. Nothing to do.
- **Icons:** `--tree-shake-icons` is on by default in release; `MaterialIcons` went from 1,645,184 to 17,044 bytes.
- **Mascot PNG (230 KB):** re-encoding would save about 0.1 MiB; the Rive file replaces it in T-088 anyway. Skipped.

## 4. Options for the PO (step 4; nothing applied, nothing dropped)

Savings are arm64 Play download / installed size, measured from the table above. "Effort" is rough engineering time. Details and the draft decision are in `docs/03-technical/adr/ADR-024-app-size-ocr-pdf-options.md` (Proposed).

| # | Option | Saves (download / installed) | What breaks | Effort |
|---|---|---|---|---|
| A | Drop Tesseract + `ara` model, keep ML Kit Latin | 3.5 MiB (12 %) / 8.1 MiB | no Arabic OCR on Android (counterparty names and Arabic labels on receipts; amounts, dates and references are mostly Latin digits); the OcrMerger and tessdata installer go | S-M (2-3 days); needs the SPK-02 accuracy numbers, which do not exist yet (ADR-009) |
| B | Drop ML Kit, keep Tesseract (`ara` + `eng`) | about 2-3 MiB net (ML Kit 5.2 less an `eng` model, not measured) / about 8 MiB less the `eng` model | Latin and digit accuracy is probably lower than ML Kit's; removes the Google data-transport/telemetry exclusion work (CR-02) and the open privacy point in ADR-009 | M (3-5 days) plus an accuracy run |
| C | Move OCR (ML Kit, Tesseract, Leptonica, models) to a Play Feature Delivery on-demand module | 8.7 MiB (30 %) / about 20 MiB | first scan needs a network download (offline first use fails); only Play installs (side-loaded APKs need the module fused in); needs Play Core / feature-delivery library and SplitCompat; INTERNET is already declared | L (1-2 weeks) incl. test matrix; nothing for iOS (iOS uses Apple Vision, no OCR binary shipped) |
| D | Move PDFium to an on-demand module | 3.2 MiB (11 %) / 6.3 MiB | pdfrx ships PDFium as a Flutter native asset in the base module; Flutter hooks cannot place it in a dynamic feature, so this needs a custom loader or a pdfrx fork; first PDF import needs network | XL (2+ weeks), high risk; not recommended |
| E | Replace PDFium by the OS PDF APIs (Android `PdfRenderer`, iOS PDFKit) | 3.2 MiB (11 %) Android; iOS 3.1 MiB (PDFium.framework, 6.7 MiB raw) | `PdfRenderer` cannot extract text, but T-156 import extracts text with geometry (`PdfrxTextExtractor`), so PDF statements would need OCR of rendered pages (slower, less accurate) and a password-protected PDF path | L (1-2 weeks), behaviour change |
| F | Defer `rive` until the `.riv` file ships (T-088) | 2.7 MiB (9 %) / 7.3 MiB | nothing today (no `.riv` exists, `RiveMascot` already falls back to the PNG); the dependency returns with T-088 | S (half a day); product decision on ADR-020 timing |

Recommendation (for the PO to accept or reject): the targets are already met, so none of A-E is needed for NFR-PERF-07. F is free today and is the cheapest saving. If a smaller download is wanted later, A or B decide on the SPK-02 accuracy numbers, and C is the largest single saving.

## 5. What was changed

- `app/android/app/build.gradle.kts`: explicit `isMinifyEnabled` / `isShrinkResources` for release; x86_64 `.so` excluded from release packaging via `androidComponents.onVariants` (override `-Pzaghlol.releaseX86=true` for an x86_64-emulator smoke of the release configuration; debug and profile keep x86_64).
- `app/android/app/proguard-rules.pro` (new): keep rules for Tesseract JNI, ML Kit components, Glance receivers and action callbacks, WorkManager workers, Play Billing, Play Integrity, Rive; Pigeon needs none (documented in the file). The Flutter plugin adds the file automatically.
- `release-android.yml`, `app-ci.yml`: release builds use `--target-platform android-arm,android-arm64`; the assertions now require arm64-v8a and armeabi-v7a and fail if any `lib/x86_64/` entry is present. The universal-APK step of the release workflow gets `-Ptarget-platform=...`.
- `size-report.yml` (new; manual dispatch or push to `size/**`), `android-size-report.sh`, `ios-size-report.sh`: debug universal, release universal, per-ABI APKs, AAB, bundletool per-device download, apkanalyzer, `--analyze-size`, iOS IPA.
- Size guard: `.github/scripts/check-app-size.sh` (+ self-test `test-check-app-size.sh` run in the `static` job) reads `.github/size-baseline.json`: fails above +10 % of the recorded baseline or over the budget (arm64 Play download 40 MiB, App Store 60 MiB; enforced because both are met). Wired into `app-ci.yml` (release APK size and compressed lib sizes per ABI), `release-android.yml` (AAB), `release-ios.yml` (unsigned IPA, dry-run path) and `size-report.yml`.
- `--obfuscate --split-debug-info` was already used by both release workflows; symbols are only kept encrypted (unchanged). `flutter ... --analyze-size` refuses to combine with them, so the analyze build is not obfuscated.

## 6. Not verified here

- Runtime behaviour of the R8-minified release build on a device (OCR with both engines, PDF import, voice, backup, purchases). The CI release builds pass R8, the aapt2 / zipalign / placement assertions and the Kotlin unit tests; there is no device or arm64 emulator in CI. Needs a manual smoke of a release build (or an x86_64-emulator run with `-Pzaghlol.releaseX86=true`) before store submission.
- The real App Store download size (needs a signed export for the App Thinning report); the unsigned IPA is a slight over-statement.
- The pinned bundletool 1.18.1 jar is downloaded in CI without a hash check (sha256 seen in the first run: `675786493983787ffa11550bdb7c0715679a44e1643f3ff980a529e9c822595c`); the jar only measures, it does not touch the shipped app.

## Runs

- before: size-report run 44745837662 (branch `size/T-190-before`); after: run 44745846062 and the final guard run on `size/T-190-after`; app-ci release legs: run 44743467475 (`ci/T-190-size`; only the pre-existing riverpod_lint probe step failed, unrelated to this task).
