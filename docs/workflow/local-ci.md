> **Batch CI (PO, 2026-11-10):** this runner is the only check on `task/**` pushes. GitHub Actions runs once per batch (`batch/**`) or on opt-in pushes to `ci/<task-id>` for iOS/device-only changes. Keep the PC on, Docker Desktop running and `START-LOCAL-CI.cmd` open while agents work.

# Local CI on the PO's PC (fast feedback)

GitHub Actions (`app-ci`, `backend-ci`) is still the **merge gate**. The local runner exists only to give agents faster feedback.

## Runner

- Location: `C:\Projects\Zaghlol\.zaghlol-local-ci\` on the PO's Windows PC. The source copy is in `docs/workflow/tools/local-ci/`.
- Toolchain: **everything builds and tests inside pinned Linux Docker containers**, not on Windows (Windows Smart App Control blocks freshly built DLLs, and Windows-only test differences hid real results). Images: `zaghlol-flutter:3.47.9`, built once on the PC from `flutter.Dockerfile` next to `runner.ps1` (no published image exists for every Flutter release; same version and commit as `app-ci.yml`/`app-regen.yml`; ~5–10 min the first time) and `mcr.microsoft.com/dotnet/sdk:10.0.402` (.NET 10 like `backend-ci.yml`). Android steps use a third image, `zaghlol-flutter-android:3.47.9`, built on first use from `flutter-android.Dockerfile` on top of the Flutter image (see "Android build verification" below). Change the pins at the top of `runner.ps1`, or set the environment variables `ZAGHLOL_FLUTTER_IMAGE` / `ZAGHLOL_ANDROID_IMAGE` / `ZAGHLOL_DOTNET_IMAGE`.
- Git polling and publishing still run on Windows. Only Git and Docker Desktop are needed on the PC (no local Flutter or .NET).
- The PO starts it with `START-LOCAL-CI.cmd`. It runs only while that window is open.

## Requirements on the PC

- **Docker Desktop** with Linux containers, **running**, and set to **start at login** (Settings > General > "Start Docker Desktop when you sign in"). If Docker is down, the runner publishes `FAIL ... docker-not-running=1` instead of checking anything.
- **First run pulls the images** (several GB for the Flutter image) and fills the cache volumes `zaghlol-ci-pub-cache`, `zaghlol-ci-nuget-cache` and `zaghlol-ci-gradle-cache`; it can take 10+ minutes. Later runs reuse them. Remove the volumes with `docker volume rm` to reset.
- Backend tests use Testcontainers: the runner mounts `/var/run/docker.sock` into the .NET container and sets `TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal`, so the PostgreSQL containers start next to it on Docker Desktop.
- The clone in `%USERPROFILE%\zaghlol-ci\repo` is mounted at `/work`. Its build output (`.dart_tool`, `bin`, `obj`) is written by the containers.
- The runner forces LF line endings in its clone (`core.autocrlf=false`), because `dotnet format` and `dart format` reject CRLF. After updating `runner.ps1`, close the runner window and start `START-LOCAL-CI.cmd` again.

## What it does

- Every 30 seconds it checks `task/*` branches for new commits.
- For each new commit it runs the **quick** pipeline:
  - **app and packages:** `pub get`, format, analyze, `flutter test`, and `dart test` in each package;
  - **android** (whenever the commit changes `app/` or `packages/`, or a root `pubspec.*`): `apk-devNoSms`, `apk-perms`, `android-unit`, `android-lint` (details below);
  - **backend:** build `-warnaserror`, `dotnet format`, `dotnet test`.
- It publishes the result to the `local-ci` branch. The step names (`pub-get`, `format`, `analyze`, `app-test`, `dart-test-<pkg>`, `apk-devNoSms`, `apk-perms`, `android-unit`, `android-lint`, `dotnet-build`, `dotnet-format`, `dotnet-test`) and the status line format are unchanged.

## Android build verification

Mirrors the Android parts of `app-ci.yml` (Java 17, `flutter build apk`, Gradle unit tests, lint, aapt2 permission asserts). iOS is not covered.

| Step | Command (inside `zaghlol-flutter-android`, in `app/`) | Fails when |
|---|---|---|
| `apk-devNoSms` | `flutter build apk --debug --flavor devNoSms` | the Gradle/Kotlin/resource build fails |
| `apk-perms` | `aapt2 dump permissions` on the devNoSms APK | it declares `READ_SMS`, `RECEIVE_SMS`, `SEND_SMS`, `RECEIVE_MMS`, `RECEIVE_WAP_PUSH` or `READ_CELL_BROADCASTS` (the app-ci restricted list) |
| `android-unit` | `./gradlew testDevNoSmsDebugUnitTest` | a Kotlin test fails, or zero `<testcase>` results exist |
| `android-lint` | `./gradlew :app:lintDevNoSmsDebug` | lint errors, including the fatal backup rules from `lint.xml` (T-165) |

- If `apk-devNoSms` fails, `apk-perms`, `android-unit` and `android-lint` are skipped (their results would only repeat the build error).
- The queued `app` and `all` pipelines also build the other five flavors of the app-ci matrix (`apk-devSms`, `apk-stagingSms`, `apk-stagingNoSms`, `apk-prodSms`, `apk-prodNoSms`, the last two `--release`), each followed by `apk-perms-<flavor>`: `*NoSms` must have no restricted SMS permission, `*Sms` must declare `READ_SMS` and `RECEIVE_SMS`. Pushes to `task/*` run only the devNoSms steps. Manual `quick-app` jobs always run the four steps.
- In the published `.log`, the `== ERRORS: <step> ==` section of a failing android step holds the Gradle `What went wrong` blocks, Kotlin `e:` compiler errors, lint errors and the `FAIL:` lines of the permission check.
- **Image** `zaghlol-flutter-android:3.47.9` (`flutter-android.Dockerfile`): the Flutter image plus OpenJDK 17, Android command-line tools 13114758 (SHA-256 checked), platform-tools, `platforms;android-36`, `build-tools;36.0.0`, NDK `28.2.13676358` (Flutter 3.47.9's `flutter.ndkVersion`), licenses accepted, and `flutter precache --android`. Built automatically on the first android step (the base Flutter image is built first if missing). **Expect 10-20 minutes and about 6 GB of disk for the image.**
- **Gradle cache** volume `zaghlol-ci-gradle-cache` mounted at `/root/.gradle` (wrapper distribution and dependencies). **The first Gradle run takes several minutes** (downloads Gradle 9.3.1 and the AGP/Kotlin dependencies, about 1-2 GB); later runs are much faster. Reset with `docker volume rm zaghlol-ci-gradle-cache`.
- **Memory:** `app/android/gradle.properties` asks for `-Xmx8G`. Give Docker Desktop at least 10 GB (WSL2: `memory=` in `%USERPROFILE%\.wslconfig`, then `wsl --shutdown`), otherwise Gradle is killed with exit 137.
- The first push after the runner update therefore shows `RUNNING` for 20-40 minutes. Agents should wait for it once; GitHub Actions stays the gate.

## Reading a result (agents)

Read this **before** waiting on GitHub Actions: it is the fast loop for format, analyze and test errors.

```bash
git fetch -q origin local-ci 2>/dev/null && git show origin/local-ci:<branch with / replaced by __>/<full sha>.status
# Example: git show origin/local-ci:task__T-002-custom-lints/<sha>.status
# The first word is PASS, FAIL, RUNNING or SKIP. Per-step exit codes follow. The <sha>.log next to it starts with a per-step summary (result and seconds), then an `== ERRORS: <step> ==` section for each failing step (dart format/analyze lines, `dotnet format` diagnostics, build errors, failing test names with the first assertion), and ends with the last 1500 raw log lines.
```

If no status shows up within about 3 minutes of a push, the runner is off. Fall back to the GitHub Actions run, which you always need for merging anyway.

## Manual jobs (Lead only, through the device bridge)

Write `queue/<id>.job` containing `branch=<name>` and `pipeline=app|backend|all|quick|quick-app|quick-backend|probe`. Read the result from `results/<id>.status`.
