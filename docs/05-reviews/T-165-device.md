# T-165: device verification (no OS backups or device transfer)

Manual on-device script for FR-SEC-05, from the T-165 design note (revised after review round 1). Run it on a release candidate and fill in the result tables. CI already enforces the static guarantees (aapt2 on every final APK, Android lint, the RunnerTests `BackupExclusionTests`). This script checks what only a device can show.

| Field | Value |
|-------|-------|
| Android flavor(s) tested | _devSms / devNoSms / prodSms / prodNoSms_ (record each one) |
| Build (Android) | _versionName / versionCode_ |
| iOS flavor tested | _dev / staging / prod_ |
| Build (iOS) | _version / build_ |
| Commit | _SHA_ |
| Tester | |
| Date | |
| Overall verdict | _PASS / FAIL_ |

## Where each step runs

| Step | Platform / API level | Build |
|------|---------------------|-------|
| 0 Canary | every Android device used in steps 1-3 | debuggable **dev** (`app.zaghlol.dev`), needed for `run-as` |
| 1 Auto Backup | API 30 **and** API 35 or 36 | dev |
| 2 `adb backup` | API 26-30 emulator **and** API 31+ device or emulator | dev (on API 31+ `adb backup` still exports data for debuggable apps, so only the dev build is a real test there) |
| 3 D2D | API 31+ | dev |
| 4 OEM transfer | Samsung A-series reference device, Pixel | Play internal-track release, plus dev for the `run-as` listing |
| 5 iOS | iOS 17+ | TestFlight build |
| 6 Uninstall dialog | Android 10+ (API 29+) | release |

Replace `app.zaghlol.dev` in the commands when testing another applicationId.

## Expected result everywhere

After any OS-level backup, restore or transfer:
- none of the step 0 canary files exist;
- Zaghlol opens at **Welcome** (first-launch state) and offers "I already use Zaghlol" (restore);
- it never shows earlier data, never prompts for a lost key, never crashes and never opens partially.

If any file was copied anyway, that is a **FAIL** for FR-SEC-05, even if the orphaned-data path (D-50, T-015/T-016) then wipes it.

## 0. Canary files (Android, before steps 1-3)

Seed features may not exist yet, so the canaries are what prove that "nothing came back" means nothing was copied, not that nothing existed. Launch the app once so its data directories exist, then:

```sh
adb shell run-as app.zaghlol.dev sh -c 'mkdir -p files databases shared_prefs && echo T165 > files/t165-canary.txt && echo T165 > databases/t165-canary.db && echo "<map/>" > shared_prefs/t165-canary.xml && ls -l files/t165-canary.txt databases/t165-canary.db shared_prefs/t165-canary.xml'
```

All three files must be listed. To check for them after a restore (expect "No such file" for each):

```sh
adb shell run-as app.zaghlol.dev ls -l files/t165-canary.txt databases/t165-canary.db shared_prefs/t165-canary.xml
```

If real seed data exists (fixture import, manual transactions), add it too and note it. Never use real SMS.

## 1. Android Auto Backup (API 30 and API 35/36, dev build)

Plant the canaries (step 0), then:

```sh
adb shell bmgr enable true
adb shell bmgr transport com.android.localtransport/.LocalTransport
adb shell settings put secure backup_local_transport_parameters 'is_encrypted=true'
adb shell bmgr backupnow app.zaghlol.dev        # record the full output
adb shell dumpsys backup | grep -i -A3 zaghlol   # record; expect no backed-up payload for the package
```

Expect `bmgr backupnow` to report "Backup is not allowed" (or an equivalent refusal) for the package, never a success that transferred data.

Restore explicitly (a reinstall alone does not reliably trigger a restore):

```sh
adb shell bmgr list sets                         # record; note the token of this device's set, if any
adb shell pm clear app.zaghlol.dev               # wipe local data, keep the app installed
adb shell bmgr restore <token> app.zaghlol.dev   # record the output
```

If `bmgr list sets` shows no set, record that; it is a pass for this part.

Then check the canaries (step 0): all three must be absent. Open the app: it must show Welcome.

Also reinstall from the pulled APKs (the path a real user takes):

```sh
adb shell pm path app.zaghlol.dev            # note every base/split path
adb pull <each path> ./apk/
adb shell pm uninstall --user 0 app.zaghlol.dev
adb install-multiple ./apk/*.apk
```

Open the app: Welcome. Canaries absent.

| Device / API | `backupnow` output | `dumpsys backup` lines | `list sets` / `restore` output | Canaries after restore | Opens at | Result |
|--------------|--------------------|------------------------|--------------------------------|------------------------|----------|--------|
| API 30 | | | | | | |
| API 35 or 36 | | | | | | |

## 2. `adb backup` (API 26-30 emulator and API 31+, dev build)

Plant the canaries (step 0). On the device prompt, **leave the backup password empty** (an encrypted archive has a longer header and cannot be checked below).

```sh
adb backup -noapk -f z.ab app.zaghlol.dev
python3 - z.ab << 'EOF'
import io, sys, tarfile, zlib
def done(msg, code=0):
    print(msg)
    sys.exit(code)
data = open(sys.argv[1], "rb").read()
if not data:
    done("PASS: empty file, adb refused the backup")
lines = data.split(b"\n", 4)
if len(lines) < 4 or lines[0] != b"ANDROID BACKUP":
    done("UNEXPECTED: not an adb backup archive (%d bytes); record it" % len(data), 2)
body = lines[4] if len(lines) == 5 else b""
compressed, encryption = lines[2], lines[3]
if encryption != b"none":
    done("RETRY: archive is encrypted; leave the backup password empty", 2)
if not body:
    done("PASS: header only, no app data")
tar = zlib.decompress(body) if compressed == b"1" else body
names = tarfile.open(fileobj=io.BytesIO(tar)).getnames()
print("\n".join(names) or "(no entries)")
leaks = [n for n in names if n.startswith("apps/") and not n.endswith("/_manifest")]
done("FAIL: app data entries present: %s" % leaks, 1) if leaks else done("PASS: no app data entries")
EOF
```

The result must be PASS: no `apps/app.zaghlol.dev/` data entries (an empty file, a header-only file or only `_manifest` are all passes).

| Emulator/device API | Build | Script output (summary) | Result |
|---------------------|-------|-------------------------|--------|
| API 26-30 | dev | | |
| API 31+ | dev (debuggable) | | |

## 3. Device-to-device transfer (API 31+, dev build)

Plant the canaries (step 0), then:

```sh
adb shell settings put secure backup_enable_d2d_test_mode 1
adb shell bmgr transport com.google.android.gms/.backup.migrate.service.D2dTransport
adb shell bmgr init com.google.android.gms/.backup.migrate.service.D2dTransport
adb shell bmgr backupnow app.zaghlol.dev        # record
adb shell dumpsys backup | grep -i -A3 zaghlol   # record
adb shell bmgr list sets                         # record the token, if any
adb shell pm clear app.zaghlol.dev
adb shell bmgr restore <token> app.zaghlol.dev   # record
```

Check the canaries: all absent. Then reinstall as in step 1 and check again. Expect Welcome, and this to list only first-launch files:

```sh
adb shell run-as app.zaghlol.dev ls -R
```

Reset afterwards:

```sh
adb shell settings put secure backup_enable_d2d_test_mode 0
adb shell bmgr transport com.android.localtransport/.LocalTransport   # or the device's previous transport (bmgr list transports)
```

| Device / API | `backupnow` / `dumpsys` | `list sets` / `restore` | Canaries after restore | `run-as ls -R` after reinstall | Opens at | Result |
|--------------|-------------------------|-------------------------|------------------------|--------------------------------|----------|--------|
| | | | | | | |

## 4. OEM transfer (real devices)

- Samsung Smart Switch on the A-series reference device.
- Pixel "Copy apps & data" over cable.

On the source, install the dev build next to the release and plant the canaries in the dev build (step 0). Transfer. On the target:
- Zaghlol (both builds) must show Welcome;
- in the dev build, the canaries must be absent (`run-as`).

If any file was copied, record exactly which ones. That is a FAIL for FR-SEC-05 even if the orphaned-data path then resets the app cleanly (D-50); record whether it did.

| Tool | Source -> target | Files copied? (`run-as ls -R`, dev build) | Opens at | Result |
|------|------------------|-------------------------------------------|----------|--------|
| Smart Switch | | | | |
| Pixel copy by cable | | | | |

## 5. iOS (iOS 17+)

**(a) Encrypted Finder backup: allow-list.** Back up the iPhone in Finder with "Encrypt local backup" on. Open it with an open-source backup reader (for example `iphone_backup_decrypt` or `imobax`) and **record the full listing** of every file and directory in `AppDomain-app.zaghlol*` (all flavors installed).

Only these entries may be present:

| Allowed entry | Condition |
|---------------|-----------|
| the domain root and the `Library` and `Library/Preferences` directory entries | directory entries only |
| `Library/Preferences/<bundle-id>.plist` | must contain **no app-written keys**. Dump it (`plutil -p`) and record every key. Any key written by Zaghlol or its plugins (for example `flutter.*`, or any key the app code sets) is a FAIL. |

**Anything else is a FAIL.** That includes `zaghlol.db*`, `spool/`, staging files, `Documents/` content, and any other `Library/*` entry (for example `Library/<plugin>/`, `Library/WebKit`, `Library/HTTPStorages`, `Library/Cookies`). If an unexpected entry is believed to be OS-generated, record it as a FAIL. Only the security-privacy-reviewer can extend this allow-list, by changing this document.

**App Group.** Also record the listing of `AppDomainGroup-group.app.zaghlol*`. This is **N/A until T-062** adds the App Group. After that, only the container's OS directory entries may appear; `spool/`, `Library/Application Support` and `Library/Caches` content is a FAIL.

**(b) iCloud backup size.** Settings > Apple Account > iCloud > Manage Account Storage > Backups > this iPhone. Zaghlol must show a size in KB only.

**(c) Restore and migration.**
1. Restore the iCloud backup to a second iPhone. Zaghlol must open at Welcome, and restoring from the Zaghlol backup (with its passphrase) must work.
2. Separately, migrate with Quick Start. Same expectation.

| Check | Device / iOS | Observation (attach the full listing for 5a) | Result |
|-------|--------------|----------------------------------------------|--------|
| 5a `AppDomain-app.zaghlol*` allow-list | | | |
| 5a `Library/Preferences/<bundle-id>.plist` keys | | | |
| 5a `AppDomainGroup-group.app.zaghlol*` | | N/A until T-062 | N/A |
| 5b iCloud backup size | | | |
| 5c iCloud restore | | | |
| 5c Quick Start migration | | | |
| 5c Zaghlol restore after 5c | | | |

## 6. Uninstall dialog (Android 10+, release build)

Uninstall Zaghlol from Settings > Apps and from the launcher. The confirmation dialog must **not** offer to keep app data (no "Keep … of app data" checkbox; `hasFragileUserData=false`).

| Device / API | Settings dialog | Launcher dialog | Result |
|--------------|-----------------|-----------------|--------|
| | | | |

## Notes and deviations

_Record anything unexpected, with the device model and OS version. Never paste message bodies or real financial data here._
