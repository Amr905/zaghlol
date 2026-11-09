# Local CI on the PO's PC (fast feedback)

GitHub Actions (`app-ci`, `backend-ci`) is still the **merge gate**. The local runner exists only to give agents faster feedback.

## Runner

- Location: `C:\Projects\Zaghlol\.zaghlol-local-ci\` on the PO's Windows PC. The source copy is in `docs/workflow/tools/local-ci/`.
- Toolchain: **everything builds and tests inside pinned Linux Docker containers**, not on Windows (Windows Smart App Control blocks freshly built DLLs, and Windows-only test differences hid real results). Images: `zaghlol-flutter:3.47.9`, built once on the PC from `flutter.Dockerfile` next to `runner.ps1` (no published image exists for every Flutter release; same version and commit as `app-ci.yml`/`app-regen.yml`; ~5–10 min the first time) and `mcr.microsoft.com/dotnet/sdk:10.0.402` (.NET 10 like `backend-ci.yml`). Change the pins at the top of `runner.ps1`, or set the environment variables `ZAGHLOL_FLUTTER_IMAGE` / `ZAGHLOL_DOTNET_IMAGE`.
- Git polling and publishing still run on Windows. Only Git and Docker Desktop are needed on the PC (no local Flutter or .NET).
- The PO starts it with `START-LOCAL-CI.cmd`. It runs only while that window is open.

## Requirements on the PC

- **Docker Desktop** with Linux containers, **running**, and set to **start at login** (Settings > General > "Start Docker Desktop when you sign in"). If Docker is down, the runner publishes `FAIL ... docker-not-running=1` instead of checking anything.
- **First run pulls the images** (several GB for the Flutter image) and fills the cache volumes `zaghlol-ci-pub-cache` and `zaghlol-ci-nuget-cache`; it can take 10+ minutes. Later runs reuse them. Remove the volumes with `docker volume rm` to reset.
- Backend tests use Testcontainers: the runner mounts `/var/run/docker.sock` into the .NET container and sets `TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal`, so the PostgreSQL containers start next to it on Docker Desktop.
- The clone in `%USERPROFILE%\zaghlol-ci\repo` is mounted at `/work`. Its build output (`.dart_tool`, `bin`, `obj`) is written by the containers.
- The runner forces LF line endings in its clone (`core.autocrlf=false`), because `dotnet format` and `dart format` reject CRLF. After updating `runner.ps1`, close the runner window and start `START-LOCAL-CI.cmd` again.

## What it does

- Every 30 seconds it checks `task/*` branches for new commits.
- For each new commit it runs the **quick** pipeline:
  - **app and packages:** `pub get`, format, analyze, `flutter test`, and `dart test` in each package;
  - **backend:** build `-warnaserror`, `dotnet format`, `dotnet test`.
- It publishes the result to the `local-ci` branch. The step names (`pub-get`, `format`, `analyze`, `app-test`, `dart-test-<pkg>`, `dotnet-build`, `dotnet-format`, `dotnet-test`) and the status line format are unchanged.

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
