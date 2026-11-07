# Lead tools

## Progress page
- The page is the "Zaghlol Build Progress" dashboard artifact: https://claude.ai/artifact/JLtixDQ3FQ7aogVaWxRoEG
- Its data is one JSON file with a row per task, exported from `docs/implementation-status.md`.
- To refresh it after any status change:
  1. Run `python3 docs/workflow/tools/progress_export.py docs/implementation-status.md <out>/zaghlol-tasks.json`.
  2. Upload the JSON as a new asset on the artifact (Artifact publish, `asset: true`).
  3. `update` the `datasets/tasks` document with the new `source.url`, `updated` and `edit`.
- The page source is `progress_dashboard.html`. In the artifact it is stored as `files/index.html`.

## Auto-resume
- The usage limit sometimes stops agents ("You've hit your 5-hour limit · resets <time>").
- For this, the Lead keeps an hourly scheduled check-in on this session. Each check-in:
  - restarts any agent stopped by the limit;
  - refreshes the progress page;
  - schedules the next check-in.
