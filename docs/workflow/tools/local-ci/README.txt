Zaghlol local CI runner v2 (fast checks; GitHub Actions is still the merge gate)

To start:
1. Start Docker Desktop (Linux containers) and set it to start at login. All checks run in Docker containers; the first run downloads the images and takes a while.
2. Double-click START-LOCAL-CI.cmd and leave the window open.

What it does:
- Every 30 seconds it looks for new commits on task/* branches on GitHub.
- For each new commit it runs the quick checks:
  - app: format, analyze and tests, then a debug Android build (devNoSms), its SMS-permission check, Kotlin unit tests and Android lint;
  - backend: build, format and tests.
- It publishes the result to the 'local-ci' branch as <branch>/<sha>.status and .log, so Claude's agents can read it within minutes.
- Publishing uses your normal Git login on this PC. If pushing fails, see results\runner-errors.log.
- Builds run in %USERPROFILE%\zaghlol-ci (separate clones), never in this folder.

The first Android step builds a ~6 GB Docker image (10-20 minutes) and fills a Gradle cache (several more minutes); give Docker Desktop at least 10 GB of memory.

Close the window to stop it. iOS builds still run only on GitHub Actions.
