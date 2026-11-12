---
description: Assemble ~5 BUILT tasks on one batch branch, review them in one round, fix, run CI and merge (Phase 5–6)
argument-hint: <batch number> <T-### T-### ...>
---

Review batch $ARGUMENTS in one round (CLAUDE.md §6 "Batch review round").

1. **Assemble.** Create `batch/<YYYY-MM-DD>-<n>` from current `main` and push it once. Merge each task branch in order; after every merge check `git diff --name-only --diff-filter=U` is empty before committing. Run the local checks on the merged tree (CLAUDE.md §6 "Local checks first") and push.
2. **Pick reviewers.**
   - Any C4 task in the batch → one `code-reviewer` on **opus**, also covering security for the C4 tasks. Otherwise → one `code-reviewer` on **sonnet**. One reviewer only (PO, 2026-11-13).
   - C1 tasks: you spot-check them yourself; leave them out of the reviewer brief.
   
3. **Reviewer brief (short).** Batch branch name, `git diff main...<batch>`, the list of task files with their class, `docs/workflow/self-check.md`, and: "Write one report `docs/05-reviews/batch-<n>.md` with one section per task: verdict APPROVED / CHANGES_REQUESTED, findings rated blocker / major / minor / nit (security: High / Medium / Low / Info, or 'before merge'), each with file:line. Check each acceptance criterion maps to a test. Read the production diff; read only the riskiest tests and run the rest instead of reading them. Commit the report to the batch branch."
4. **Triage.** Blockers, majors, security Medium+ and "before merge" → fix. Everything else → `FU-###` in `docs/implementation-status.md` with an owner task.
5. **Fix once.** One fresh fix agent per lane (Agent `effort: "low"`), all that lane's findings in one brief, working on the batch branch. Fixes of about 30 lines or fewer with a test that fails without them: you verify the delta and append "Lead delta check" to the report. Larger: one delta-only `code-reviewer` on sonnet for the whole batch. If a task still fails, revert its merge from the batch and send it back to its lane; don't hold the other tasks.
6. **Merge.** Update `TASKS.md` (tasks → DONE), `implementation-status.md` and `LEAD_HANDOFF.md` in the batch branch, wait for one full green GitHub run (app-ci, backend-ci, db-platform; rerun infra flakes once), open the PR `batch/... → main` and merge it with a merge commit. Give the PO a 3–5 line summary plus the progress table.
