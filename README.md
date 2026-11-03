# Zaghlol (زغلول)

On-device, zero-backend personal finance and SMS expense analyzer for Egypt, with Captain Zaghlol as an Egyptian-Arabic-speaking coach.

- Product spec: `Zaghlol_Feature_and_Product_Specification_v4.docx`
- How this project is built: `CLAUDE.md` and `docs/workflow/`
- Current phase: `docs/workflow/PHASE_LOG.md`

## Developer setup

Prerequisites: Flutter stable (Dart >= 3.6), JDK 17, Android SDK (API 36) and, for iOS, Xcode with an iOS 17+ SDK.

The repo is a Dart **pub workspace** (`app`, `packages/zaghlol_domain`, `packages/zaghlol_parsing`). Resolve everything once from the repo root:

```sh
flutter pub get
```

Common commands:

```sh
dart format --output=none --set-exit-if-changed .   # formatting check
flutter analyze                                      # strict lints
(cd packages/zaghlol_domain && dart test)            # pure-Dart package tests
(cd packages/zaghlol_parsing && dart test)
```

### Flavors

Environment flavors: `dev` (`app.zaghlol.dev`), `staging` (`app.zaghlol.staging`), `prod` (`app.zaghlol`).

Android has a second flavor dimension for SMS policy (ADR-004). `READ_SMS`/`RECEIVE_SMS` are declared only in the `sms` flavor source set (`app/android/app/src/sms/AndroidManifest.xml`), so the variants are `<env>Sms` and `<env>NoSms`:

```sh
cd app
flutter run --flavor devNoSms
flutter build apk --flavor prodNoSms      # no SMS permissions
flutter build appbundle --flavor prodSms  # declares READ_SMS / RECEIVE_SMS
flutter build ios --flavor dev --no-codesign
```

iOS has `dev` / `staging` / `prod` schemes (and matching build configurations).

Minimum OS: Android 8.0 (minSdk 26, targetSdk 36), iOS 17.0 (ADR-019).
