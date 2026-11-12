---
description: Build one task from the board (Phase 5). Review happens later, once per batch of 5 (see /review-batch).
argument-hint: <T-###>
---

Build task $ARGUMENTS. It is reviewed later, together with four other tasks, by `/review-batch` (CLAUDE.md §6 "Batch review round").

1. Read `docs/04-tasks/tasks/$ARGUMENTS.md` and `docs/workflow/model-routing.md`. Check that all dependencies are DONE (or BUILT in the same batch) in `docs/04-tasks/TASKS.md`; if not, stop.
2. Verify the complexity class. If it's C3/C4 and the task has no Design note: for C4 crypto/keys, billing/entitlements and SMS/notification ingestion delegate to `solution-architect` (opus) first; otherwise the implementer writes a short note in the task file before coding.
3. Set status IN_PROGRESS. Delegate to the task's agent, passing the task file path and `docs/workflow/self-check.md`, with the model the class dictates (C4: sonnet, except opus for crypto/keys and data-deleting code; C1: haiku; C1/C2 with `effort: "low"`). Brief it to commit early, push often, run the local checks before pushing, keep C4 negative proofs to 2–3, and not wait for the PC runner.
4. When the builder reports, read its report and the diff stat (open the diff only where the report raises a doubt). Set status BUILT and note the branch and head SHA in `docs/workflow/LEAD_HANDOFF.md` under "Built, waiting for batch review".
5. No reviewer runs now. Up to 5 builders at once, one per task. When 5 tasks are BUILT, run `/review-batch`.
