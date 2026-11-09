# Code review: local-ci-container (runner.ps1 v3, Docker steps)

Branch: task/local-ci-container @9b74996. Reviewer: code-reviewer (Sonnet, C2 tooling). Static review only; the script was not parsed or run (no PowerShell available to the reviewer).

## Verdict: CHANGES_REQUESTED

One major (destructive git commands can run outside the CI clone). Everything else is minor/nit.

## What was checked and found OK

- Syntax read-through of the whole script: no parse problems seen (`${Repo}:/work` is correctly braced, `$(...)` inside `-f` and strings is fine, nested `Ctx` function sees the parent `$lines`/`$hits`, `switch -Regex` branches all `break`).
- Quoting: no `$cmd` contains a double quote, only spaces, so both Windows PowerShell 5.1 (wraps the arg in quotes) and pwsh 7 pass the `bash -c` string intact. Windows paths with spaces in the `-v` argument are also quoted by PowerShell. `START-LOCAL-CI.cmd` is not in the repo (only on the PC), so which PowerShell it uses could not be checked; the script works with either.
- Exit codes: `$ErrorActionPreference = 'Continue'` (not Stop), so native stderr does not abort; stderr ErrorRecords are unwrapped to text; `$LASTEXITCODE` is read right after the pipeline and defaulted to 1 if null. Correct.
- Status-line format `"{0} sha={1} pipeline={2} {3}"`, step names and the `<branch with __>/<sha>.status|.log` layout are unchanged versus main. Publish only adds the summary/error sections to the `.log`.
- safe.directory via `GIT_CONFIG_COUNT/KEY/VALUE` env is valid (git >= 2.31). CRLF handling (`autocrlf=false`, `eol=lf`, one-time renormalize) is consistent with the container mount.
- Testcontainers: `ZaghlolTestDatabase` uses only `PostgreSqlBuilder` with image, port binding and DB name (no bind mounts or resource mappings from the test container's filesystem), so socket mount + `host.docker.internal` is sufficient, including the fixed-host-port restart tests.
- Flutter version in the default image tag (3.47.9) equals `FLUTTER_VERSION` in `app-ci.yml`.
- Test-code changes (`_lf` helper, `FactSkipOnWindows`) are correct and CI is green.

## Findings

### F-1 (major) runner.ps1:152, 157, 163, 166: git reset/clean can run in the wrong directory
`Checkout` does `Push-Location $Repo` and then runs `git rm --cached .`, `git reset --hard`, `git checkout --force`, `git clean -fdx` unguarded. If the clone failed (offline, auth, disk) `$Repo` does not exist, `Push-Location` only writes a non-terminating error under `Continue`, and the commands run in the current directory. That is the runner folder (`C:\Projects\Zaghlol\.zaghlol-local-ci`, inside the PO's project folder). If that is inside a git work tree, `git reset --hard` and `git clean -fdx` (deletes untracked and ignored files, new one-time call at line 163 plus the existing one at 166) hit the PO's working copy. The one-time sentinel guards (`.git\zaghlol-*-ok`) are checked inside `$Repo`, so they do not protect against this.
Required change: after the clone/`Push-Location`, abort when `-not (Test-Path (Join-Path $Repo '.git'))`, and/or use `git -C $Repo ...` everywhere, and verify `(git rev-parse --show-toplevel)` resolves to `$Repo` before any `reset`/`clean`. Return a failing result (so a FAIL status is published) instead of continuing.

### F-2 (minor) runner.ps1:77: no timeout on `docker run`
A hung container (stuck test, Testcontainers waiting for a missing socket) blocks the whole runner loop forever, including queue jobs and later pushes. Add a per-step wall-clock limit (e.g. `Start-Process`/job with timeout then `docker kill`), or at least name the containers (`--name`) so they can be killed. Follow-up is acceptable.

### F-3 (minor) runner.ps1:63: bind mount of an NTFS path is slow
`flutter test`, `dotnet build` (thousands of small files in `obj`/`.dart_tool`) over a Windows bind mount through Docker Desktop is commonly 3-10x slower than native. The ~3 minute feedback target in `local-ci.md` may be missed. Consider keeping the clone inside WSL2 or using named volumes for `obj`/`.dart_tool`. Measure on the first run; follow-up.

### F-4 (minor) runner.ps1:12-30: Docker Desktop in Windows-containers mode
`Docker-Up` returns true in that mode, then the pull fails with a manifest/platform error. The current message ("offline, wrong tag, or not logged in") is misleading. Add "or Docker is set to Windows containers" to the message, or check `docker version --format '{{.Server.Os}}'` equals `linux` in `Docker-Up`.

### F-5 (minor) runner.ps1:193: APK builds in the container have no Gradle cache volume
Only used for non-quick pipelines, so it does not affect the auto loop, but each run re-downloads Gradle and dependencies. Add a `/root/.gradle` named volume. Follow-up.

### F-6 (nit) runner.ps1:36
`Strip-Ansi` leaves bare `\r` progress redraws (dotnet restore, flutter pub get) in the log; they clutter the 1500-line tail. Replace lone `\r` with `\n` or drop them.

### F-7 (nit) KeyRingTests.cs / iso4217_table_test.dart
Both Windows workarounds are now mostly redundant, since the runner no longer executes on Windows and the clone uses LF. They are harmless and help developers running tests locally on Windows; no change required. Note the `[FactSkipOnWindows]` skip is silent in CI summaries only on Windows, so nothing is hidden on Linux.

## Not verified (needs first real run)
- Existence of the image tags `ghcr.io/cirruslabs/flutter:3.47.9` and `mcr.microsoft.com/dotnet/sdk:10.0.402` (env overrides exist).
- `host.docker.internal` reachability from the SDK container to ports published by sibling Postgres containers on the PO's Docker Desktop.
- Which PowerShell `START-LOCAL-CI.cmd` launches (script avoids the known quoting traps for both).
