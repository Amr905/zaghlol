# Local CI on the PO's PC (fast feedback)

GitHub Actions (`app-ci`, `backend-ci`) is still the **merge gate**. The local runner exists only to give agents faster feedback.

## Runner

- Location: `C:\Projects\Zaghlol\.zaghlol-local-ci\` on the PO's Windows PC. The source copy is in `docs/workflow/tools/local-ci/`.
- Toolchain: Flutter 3.47.7 / Dart 3.13.5, .NET SDK 10.0.402, Android SDK, 16 cores. Backend tests need Docker Desktop running.
- The PO starts it with `START-LOCAL-CI.cmd`. It runs only while that window is open.

## Requirements on the PC

- **Flutter 3.47.9** (the version CI pins; the workspace needs Dart ≥ 3.13.7). Older Flutter makes every app job fail at `pub get`.
- The runner forces LF line endings in its clone (`core.autocrlf=false`), because `dotnet format` and `dart format` reject CRLF. After updating `runner.ps1`, close the runner window and start `START-LOCAL-CI.cmd` again.

## What it does

- Every 30 seconds it checks `task/*` branches for new commits.
- For each new commit it runs the **quick** pipeline:
  - **app and packages:** `pub get`, format, analyze, `flutter test`, and `dart test` in each package;
  - **backend:** build `-warnaserror`, `dotnet format`, `dotnet test`.
- It publishes the result to the `local-ci` branch.

## Reading a result (agents)

Read this **before** waiting on GitHub Actions: it is the fast loop for format, analyze and test errors.

```bash
git fetch -q origin local-ci 2>/dev/null && git show origin/local-ci:<branch with / replaced by __>/<full sha>.status
# Example: git show origin/local-ci:task__T-002-custom-lints/<sha>.status
# The first word is PASS, FAIL, RUNNING or SKIP. Per-step exit codes follow. The <sha>.log next to it has the last 400 log lines.
```

If no status shows up within about 3 minutes of a push, the runner is off. Fall back to the GitHub Actions run, which you always need for merging anyway.

## Manual jobs (Lead only, through the device bridge)

Write `queue/<id>.job` containing `branch=<name>` and `pipeline=app|backend|all|quick|quick-app|quick-backend|probe`. Read the result from `results/<id>.status`.
