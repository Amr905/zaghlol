# T-208 - Installed size on the phone (measured 2026-11-22)

PO report: "250 MB on the phone with no user data" (Android Settings, app storage, "App size"). Measured on the CI Android emulator (API 34 google_apis x86_64, workflow `installed-size.yml`, run 45025218208 on `ci/T-208`, commit d60738f). Sizes from `du -k` of `/data/app/.../` and `/data/data/<pkg>` (device-reported), file sizes from the built APKs. MiB = 1,048,576 bytes. Raw per-phase text: branch `installed-size-report` (`installed-size-<sha>/`) and the `installed-size-report` artifact.

## 1. What the 250 MB is

The only app-ci artifacts the PO can install are the `zaghlol-devSms-debug-apk` / `zaghlol-devNoSms-debug-apk` ones (REST list on 2026-11-22: 156.8 MB each, zipped; no release APK artifact exists). Unzipped, that file is the **debug universal APK: 291,756,062 bytes = 278.2 MiB**. Android counts a non-extracted APK fully in "App size", so Settings shows about 278 MiB (291 MB; the PO's 250 MB is the same order, and earlier CI artifacts were a little smaller; it cannot be proven which exact file or Settings rounding was used). It is not release code and not user data:

| Part of a debug install | Size | Why |
|---|---|---|
| `base.apk` (code, "App size") | 278.2 MiB (284,924 KiB on disk) | 3 ABIs x debug `libflutter.so` (33-40 MB each), the Vulkan validation layer, the uncompressed Dart kernel `kernel_blob.bin` (135 MB, stored in the APK), plus all native libs of the three ABIs, stored uncompressed |
| `oat/` | 0 (the debug build is `run-from-apk`: not compiled at install) | JIT only |
| **after the first launch**, `app_flutter/flutter_assets/` in the app's data dir | **+143 MiB** (`kernel_blob.bin` 132 MiB, `isolate_snapshot_data` 11 MiB) | the Flutter debug engine copies the kernel out of the APK on first run; this is counted as "Data", not "App size", and a "no user data" install still has it |
| everything else in the data dir (empty DB, WorkManager db) | about 1.4 MiB | |
| **Debug total on the phone after one launch** | **about 421 MiB** | |

So: the PO is looking at the debug universal build. It cannot be made small (debug needs the kernel and the debug engine); the fix for size checks is a release build.

## 2. Packaging (the question about every .so stored twice)

Checked, not the case, in both modes:
- Merged manifest has `android:extractNativeLibs="false"` (aapt `0x0`); `dumpsys package` on the device says `extractNativeLibs=false`; `/data/app/.../lib/` holds only an empty `x86_64` directory; `dexopt: run-from-apk`. `app/android` sets no `useLegacyPackaging` or `extractNativeLibs` anywhere (AGP default for minSdk 26).
- In the release APK every `.so` is `Stored` (uncompressed, 16 KB aligned), mapped from the APK. Compressing them (legacy packaging) would shrink the APK by about 30 MiB but add about 54 MiB of extracted libs on the phone, i.e. a bigger installed size; so the current layout is the right one for installed size (Play still downloads compressed, 28.9 MiB).
- Tesseract model: `assets/tessdata/ara.traineddata` (1.4 MiB, 0.7 MiB compressed in the APK) is copied to `filesDir/tessdata` on the first OCR use (`TessdataInstaller`; Tesseract needs a real directory). That is a 1.4 MiB duplicate only after the first scan; no copy exists after install or a plain first launch (verified: no `tessdata` in the data dir). ML Kit models are read from assets in place. Not worth changing.

## 3. Before / after installed size (devSms, emulator, no user data)

| Build | APK file | `/data/app` (code dir) | data dir after first launch | Installed total |
|---|---|---|---|---|
| Debug universal (before = after, unchanged) | 278.2 MiB | 278.3 MiB (284,948 KiB) | 144.7 MiB (148,164 KiB) | **423 MiB** |
| Release x86_64 + the arm64/armv7 AAR libs (emulator stand-in, `-Pzaghlol.releaseX86=true`) | 112.8 MiB | 116.6 MiB (119,436 KiB; oat 3.8 MiB, `status=verify`) | 1.5 MiB | 118 MiB (not a shipped configuration) |
| Release arm64 sideload, **new** (`--split-per-abi --target-platform android-arm64`) | **65.9 MiB** (69,098,136 B) | about 66 MiB + about 4 MiB oat = **about 70 MiB** (derived from the release x86_64 oat; not run: no arm64 device in CI) | about 1.5 MiB | **about 72 MiB** |
| Release arm64 sideload, first attempt (`--target-platform android-arm64`, no split) | 84.2 MiB (88,255,425 B) | | | not used: AAR libs of armeabi-v7a stay in the APK because `--target-platform` filters only Flutter's own libs |
| Prod release arm64 as Play installs it (T-190) | 63.4 MiB | about 63 MiB + oat | | about 67 MiB; Play download 28.9 MiB |

What a release install costs on a phone, therefore: about 66 MiB APK + about 4 MiB compiled code (+ about 1.5 MiB data) = about 72 MiB, not 250 MB. The dev flavor is a little larger than prod (unobfuscated `libapp.so` 15.7 MiB; the sideload build is not `--obfuscate`).

## 4. Where the 65.9 MiB of the arm64 release APK goes (uncompressed, all native libs Stored)

libapp.so (Dart AOT) 15.7, libflutter.so 11.2, libmlkit_google_ocr_pipeline.so 10.6, librive_native.so 7.3 (no `.riv` yet, ADR-024 option F), libpdfium.so 6.3, libtesseract.so 4.0, libleptonica.so 2.7, libsqlite3mc.so 1.9, small libs 0.6, classes.dex 1.6 (compressed), assets and resources about 3. OCR engines, PDFium and sqlite3mc are PO-protected (ADR-024); Rive is the only unused native lib and its deferral is a product decision (ADR-024 F, 7.3 MiB installed), left to the PO.

## 5. What changed

- `app/android/app/build.gradle.kts`: explicit `packaging.jniLibs.useLegacyPackaging = false` (no behaviour change; locks the default).
- `.github/workflows/app-ci.yml`: every Android APK now fails the job if `extractNativeLibs` is true or any `.so` is not stored uncompressed.
- `.github/workflows/installed-size.yml` (new), `.github/scripts/installed-size-emu.sh`, `installed-size-run.sh`: the emulator measurement and the **sideload artifact** `zaghlol-<devSms|devNoSms>-release-arm64-sideload` (release, arm64 only, `--split-per-abi`, debug key, dev backend, file named `...-NOT-FOR-STORE.apk`; 14 days). Runs on `workflow_dispatch`, on `ci/T-208*` and on pushes to `main` that touch `app/android/**`.
- `docs/06-release/README.md`: which file to install for size checks.

## 6. Not verified

- No arm64 device or emulator: the arm64 installed size is derived (APK + the x86_64 release oat), not read from `dumpsys`. The PO can read it from Settings on a phone with the sideload APK; expect about 70 MiB "App size".
- `dumpsys diskstats` printed nothing on the emulator (no storage-stats provider for the shell); the `du` numbers above are the device-side evidence.
- The sideload release build runs R8 (T-190 keep rules) and has not been smoke-run on a device (same open point as T-190 section 6); the dev release uses the dev backend and the debug certificate.
