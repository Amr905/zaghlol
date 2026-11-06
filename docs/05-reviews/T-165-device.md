# T-165: device verification (no OS backups or device transfer)

Manual on-device script for FR-SEC-05, from the T-165 design note. Run it on a release candidate and fill in the result tables. CI already enforces the static guarantees (aapt2 on every final APK, Android lint, the RunnerTests `BackupExclusionTests`). This script checks what only a device can show.

| Field | Value |
|-------|-------|
| Build (Android) | _versionName / versionCode, flavor_ |
| Build (iOS) | _version / build, flavor_ |
| Commit | _SHA_ |
| Tester | |
| Date | |
| Overall verdict | _PASS / FAIL_ |

## Preconditions

- Android: a debuggable **dev** build (`app.zaghlol.dev`) for the steps that need `run-as`, and the Play **internal-track release** (`app.zaghlol`) for the UI checks. Replace the package name in the commands when you test the release build.
- iOS: a TestFlight build on two iPhones signed in to the same Apple Account, plus a Mac with Finder.
- Seed data on every source device first:
  1. Import the synthetic fixtures (never real SMS).
  2. Add a few manual transactions.
  3. Set a backup passphrase and create a Zaghlol backup (needed for step 5c).
- Before each "reinstall" step, note that the app shows the seeded data.

**Expected result everywhere:** after any OS-level restore or transfer, Zaghlol opens at **Welcome** (first-launch state) and offers "I already use Zaghlol" (restore). It never shows the seeded data, never prompts for a lost key, never crashes and never opens partially. If any file was copied anyway, the orphaned-data path (D-50) must wipe it and still show Welcome.

## 1. Android Auto Backup (API 30 and API 35/36)

```sh
adb shell bmgr enable true
adb shell bmgr transport com.android.localtransport/.LocalTransport
adb shell settings put secure backup_local_transport_parameters 'is_encrypted=true'
adb shell bmgr backupnow app.zaghlol.dev
```

Expect "Backup is not allowed", or a success with no app payload.

Reinstall from the pulled APKs, so that the OS would restore any backup:

```sh
adb shell pm path app.zaghlol.dev            # note every base/split path
adb pull <each path> ./apk/
adb shell pm uninstall --user 0 app.zaghlol.dev
adb install-multiple ./apk/*.apk
```

Open the app. It must show Welcome.

| Device / API | bmgr output | After reinstall | Result |
|--------------|-------------|-----------------|--------|
| API 30 | | | |
| API 35 or 36 | | | |

## 2. adb backup (API 26-30 emulator)

```sh
adb backup -noapk -f z.ab app.zaghlol.dev
# Skip the 24-byte header, then inflate (zlib) and list the tar.
dd if=z.ab bs=24 skip=1 2>/dev/null | python3 -c "import sys,zlib; sys.stdout.buffer.write(zlib.decompress(sys.stdin.buffer.read()))" > z.tar
tar tvf z.tar
```

The listing must contain no `apps/app.zaghlol.dev/` data entries. (An empty archive, or only the `_manifest` entry, is a pass.)

| Emulator API | `tar t` listing (summary) | Result |
|--------------|---------------------------|--------|
| | | |

## 3. Device-to-device transfer (API 31+)

```sh
adb shell settings put secure backup_enable_d2d_test_mode 1
adb shell bmgr transport com.google.android.gms/.backup.migrate.service.D2dTransport
adb shell bmgr init com.google.android.gms/.backup.migrate.service.D2dTransport
adb shell bmgr backupnow app.zaghlol.dev
```

Reinstall as in step 1. Expect Welcome, and this to list only first-launch files:

```sh
adb shell run-as app.zaghlol.dev ls -R
```

Reset afterwards:

```sh
adb shell settings put secure backup_enable_d2d_test_mode 0
adb shell bmgr transport com.android.localtransport/.LocalTransport   # or the device's previous transport (bmgr list transports)
```

| Device / API | bmgr output | `run-as ls -R` after reinstall | Opens at | Result |
|--------------|-------------|--------------------------------|----------|--------|
| | | | | |

## 4. OEM transfer

- Samsung Smart Switch on the A-series reference device.
- Pixel "Copy apps & data" over cable.

On the target, Zaghlol must show Welcome. If any file was copied, the orphaned-data path must reset cleanly. Record the result either way.

| Tool | Source -> target | Files copied? (`run-as ls -R` on a dev build) | Opens at | Result |
|------|------------------|-----------------------------------------------|----------|--------|
| Smart Switch | | | | |
| Pixel copy by cable | | | | |

## 5. iOS

**(a) Encrypted Finder backup.** Back up the iPhone in Finder with "Encrypt local backup" on. Open it with an open-source backup reader (for example `iphone_backup_decrypt` or `imobax`). `AppDomain-app.zaghlol*` must contain no `zaghlol.db*`, no `spool/` and no staging files.

**(b) iCloud backup size.** Settings > Apple Account > iCloud > Manage Account Storage > Backups > this iPhone. Zaghlol must show a size in KB only.

**(c) Restore and migration.**
1. Restore the iCloud backup to a second iPhone. Zaghlol must open at Welcome, and restoring from the Zaghlol backup (with the passphrase) must work.
2. Separately, migrate with Quick Start. Same expectation.

| Check | Device / iOS | Observation | Result |
|-------|--------------|-------------|--------|
| 5a Finder backup contents | | | |
| 5b iCloud backup size | | | |
| 5c iCloud restore | | | |
| 5c Quick Start migration | | | |
| 5c Zaghlol restore after 5c | | | |

## Notes and deviations

_Record anything unexpected, with the device model and OS version. Never paste message bodies or real financial data here._
